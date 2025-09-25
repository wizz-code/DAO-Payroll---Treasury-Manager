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