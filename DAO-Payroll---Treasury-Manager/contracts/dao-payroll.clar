;; DAO Payroll & Treasury Manager
;; Enhanced automated payroll and milestone-based payments for DAOs

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-milestone-incomplete (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-employee-inactive (err u107))
(define-constant err-invalid-period (err u108))
(define-constant err-budget-exceeded (err u109))
(define-constant err-invalid-role (err u110))

(define-map dao-employees
  { dao: principal, employee: principal }
  {
    salary: uint,
    pay-period: uint,
    last-payment: uint,
    next-payment: uint,
    total-earned: uint,
    active: bool,
    hired-at: uint,
    role: (string-ascii 64),
    performance-score: uint
  })

(define-map dao-treasuries
  principal
  {
    balance: uint,
    total-disbursed: uint,
    created-at: uint,
    monthly-budget: uint,
    current-month-spent: uint,
    last-budget-reset: uint,
    admin: principal
  })

(define-map milestones
  { dao: principal, milestone-id: uint }
  {
    assignee: principal,
    description: (string-ascii 256),
    reward: uint,
    completed: bool,
    approved: bool,
    created-at: uint,
    due-date: uint,
    category: (string-ascii 32),
    priority: uint
  })

(define-map dao-milestone-counter principal uint)
(define-map employee-bonuses { dao: principal, employee: principal } uint)
(define-map vacation-requests 
  { dao: principal, employee: principal, request-id: uint }
  { start-date: uint, end-date: uint, approved: bool, created-at: uint })

(define-public (create-treasury (initial-deposit uint) (monthly-budget uint) (admin principal))
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? dao-treasuries caller)) err-already-exists)
    (asserts! (>= (stx-get-balance caller) initial-deposit) err-insufficient-funds)
    (asserts! (> monthly-budget u0) err-invalid-amount)
    
    (try! (stx-transfer? initial-deposit caller (as-contract tx-sender)))
    
    (ok (map-set dao-treasuries caller {
      balance: initial-deposit,
      total-disbursed: u0,
      created-at: block-height,
      monthly-budget: monthly-budget,
      current-month-spent: u0,
      last-budget-reset: block-height,
      admin: admin
    }))))

(define-public (add-treasury-funds (amount uint))
  (let ((caller tx-sender)
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found)))
    (asserts! (>= (stx-get-balance caller) amount) err-insufficient-funds)
    (asserts! (> amount u0) err-invalid-amount)
    
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    
    (ok (map-set dao-treasuries caller
      (merge treasury {
        balance: (+ (get balance treasury) amount)
      })))))

(define-public (update-monthly-budget (new-budget uint))
  (let ((caller tx-sender)
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found)))
    (asserts! (is-eq caller (get admin treasury)) err-unauthorized)
    (asserts! (> new-budget u0) err-invalid-amount)
    
    (ok (map-set dao-treasuries caller
      (merge treasury {
        monthly-budget: new-budget
      })))))

(define-public (reset-monthly-budget)
  (let ((caller tx-sender)
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found)))
    (asserts! (is-eq caller (get admin treasury)) err-unauthorized)
    (asserts! (>= (- block-height (get last-budget-reset treasury)) u4320) err-unauthorized) ;; ~30 days
    
    (ok (map-set dao-treasuries caller
      (merge treasury {
        current-month-spent: u0,
        last-budget-reset: block-height
      })))))

(define-private (check-budget-limit (dao principal) (amount uint))
  (let ((treasury (unwrap! (map-get? dao-treasuries dao) err-not-found)))
    (asserts! (<= (+ (get current-month-spent treasury) amount) (get monthly-budget treasury)) err-budget-exceeded)
    (ok true)))

(define-public (hire-employee 
  (employee principal)
  (salary uint)
  (pay-period uint)
  (role (string-ascii 64)))
  (let ((caller tx-sender)
        (employee-key {dao: caller, employee: employee})
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found)))
    (asserts! (is-eq caller (get admin treasury)) err-unauthorized)
    (asserts! (is-none (map-get? dao-employees employee-key)) err-already-exists)
    (asserts! (> salary u0) err-invalid-amount)
    (asserts! (> pay-period u0) err-invalid-period)
    
    (ok (map-set dao-employees employee-key {
      salary: salary,
      pay-period: pay-period,
      last-payment: u0,
      next-payment: (+ block-height pay-period),
      total-earned: u0,
      active: true,
      hired-at: block-height,
      role: role,
      performance-score: u75
    }))))

(define-public (update-employee-salary (employee principal) (new-salary uint))
  (let ((caller tx-sender)
        (employee-key {dao: caller, employee: employee})
        (employment (unwrap! (map-get? dao-employees employee-key) err-not-found))
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found)))
    (asserts! (is-eq caller (get admin treasury)) err-unauthorized)
    (asserts! (> new-salary u0) err-invalid-amount)
    
    (ok (map-set dao-employees employee-key
      (merge employment {salary: new-salary})))))

(define-public (update-performance-score (employee principal) (score uint))
  (let ((caller tx-sender)
        (employee-key {dao: caller, employee: employee})
        (employment (unwrap! (map-get? dao-employees employee-key) err-not-found))
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found)))
    (asserts! (is-eq caller (get admin treasury)) err-unauthorized)
    (asserts! (<= score u100) err-invalid-amount)
    
    (ok (map-set dao-employees employee-key
      (merge employment {performance-score: score})))))

(define-public (process-payroll (employee principal))
  (let ((caller tx-sender)
        (employee-key {dao: caller, employee: employee})
        (employment (unwrap! (map-get? dao-employees employee-key) err-not-found))
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found)))
    (asserts! (get active employment) err-employee-inactive)
    (asserts! (>= block-height (get next-payment employment)) err-unauthorized)
    (asserts! (>= (get balance treasury) (get salary employment)) err-insufficient-funds)
    (try! (check-budget-limit caller (get salary employment)))
    
    (try! (as-contract (stx-transfer? (get salary employment) tx-sender employee)))
    
    (map-set dao-employees employee-key
      (merge employment {
        last-payment: block-height,
        next-payment: (+ block-height (get pay-period employment)),
        total-earned: (+ (get total-earned employment) (get salary employment))
      }))
    
    (ok (map-set dao-treasuries caller
      (merge treasury {
        balance: (- (get balance treasury) (get salary employment)),
        total-disbursed: (+ (get total-disbursed treasury) (get salary employment)),
        current-month-spent: (+ (get current-month-spent treasury) (get salary employment))
      })))))

(define-public (terminate-employee (employee principal))
  (let ((caller tx-sender)
        (employee-key {dao: caller, employee: employee})
        (employment (unwrap! (map-get? dao-employees employee-key) err-not-found))
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found)))
    (asserts! (is-eq caller (get admin treasury)) err-unauthorized)
    
    (ok (map-set dao-employees employee-key
      (merge employment {active: false})))))

(define-public (award-bonus (employee principal) (bonus-amount uint) (reason (string-ascii 128)))
  (let ((caller tx-sender)
        (employee-key {dao: caller, employee: employee})
        (employment (unwrap! (map-get? dao-employees employee-key) err-not-found))
        (treasury (unwrap! (map-get? dao-treasuries caller) err-not-found))
        (current-bonus (default-to u0 (map-get? employee-bonuses employee-key))))
    (asserts! (is-eq caller (get admin treasury)) err-unauthorized)
    (asserts! (get active employment) err-employee-inactive)
    (asserts! (>= (get balance treasury) bonus-amount) err-insufficient-funds)
    (try! (check-budget-limit caller bonus-amount))
    
    (try! (as-contract (stx-transfer? bonus-amount tx-sender employee)))
    
    (map-set employee-bonuses employee-key (+ current-bonus bonus-amount))
    
    (ok (map-set dao-treasuries caller
      (merge treasury {
        balance: (- (get balance treasury) bonus-amount),
        total-disbursed: (+ (get total-disbursed treasury) bonus-amount),
        current-month-spent: (+ (get current-month-spent treasury) bonus-amount)
      })))))
