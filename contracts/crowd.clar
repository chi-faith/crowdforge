;; CrowdForge - Decentralized Open Source Project Funding Platform
;; Empowering developers to build the future through community-driven funding

;; Error codes
(define-constant ERR-ACCESS-DENIED (err u1))
(define-constant ERR-VENTURE-NOT-FOUND (err u2))
(define-constant ERR-ALREADY-COMPLETED (err u3))
(define-constant ERR-INSUFFICIENT-FUNDS (err u4))
(define-constant ERR-INVALID-AMOUNT (err u5))
(define-constant ERR-OBJECTIVE-NOT-FOUND (err u6))
(define-constant ERR-OBJECTIVE-PENDING (err u7))
(define-constant ERR-INVALID-TITLE (err u8))
(define-constant ERR-INVALID-DESCRIPTION (err u9))
(define-constant ERR-INVALID-OBJECTIVE-TITLE (err u10))
(define-constant ERR-INVALID-OBJECTIVE-DESC (err u11))
(define-constant ERR-INVALID-TIMELINE (err u12))
(define-constant ERR-INVALID-VENTURE-ID (err u13))
(define-constant ERR-INVALID-OBJECTIVE-ID (err u14))
(define-constant ERR-WITHDRAWAL-FAILED (err u15))

;; Data variables
(define-data-var platform-admin principal tx-sender)
(define-map coding-ventures 
    { venture-id: uint }
    {
        founder: principal,
        title: (string-ascii 100),
        description: (string-utf8 500),
        funding-goal: uint,
        raised-amount: uint,
        status: (string-ascii 20),
        launch-block: uint,
        category: (string-ascii 50)
    }
)

(define-map development-objectives
    { venture-id: uint, objective-id: uint }
    {
        title: (string-ascii 100),
        description: (string-utf8 500),
        deadline: uint,
        reward-amount: uint,
        status: (string-ascii 20),
        completion-proof: (string-utf8 200)
    }
)

(define-map backer-contributions
    { venture-id: uint, backer: principal }
    { amount: uint, timestamp: uint }
)

;; Counter for venture IDs
(define-data-var next-venture-id uint u0)

;; Helper functions for validation
(define-private (valid-ascii-string (value (string-ascii 100)))
    (> (len value) u0)
)

(define-private (valid-utf8-string (value (string-utf8 500)))
    (> (len value) u0)
)

(define-private (valid-venture-id (id uint))
    (and 
        (> id u0)
        (<= id (var-get next-venture-id))
    )
)

(define-private (valid-objective-id (id uint))
    (> id u0)
)

(define-private (valid-timeline (deadline uint))
    (>= deadline block-height)
)

;; Initialize platform
(define-public (initialize-platform)
    (begin
        (asserts! (is-eq tx-sender (var-get platform-admin)) ERR-ACCESS-DENIED)
        (ok true)
    )
)

;; Launch a new coding venture
(define-public (launch-venture 
                (title (string-ascii 100)) 
                (description (string-utf8 500))
                (funding-goal uint)
                (category (string-ascii 50)))
    (begin
        ;; Validate inputs
        (asserts! (valid-ascii-string title) ERR-INVALID-TITLE)
        (asserts! (valid-utf8-string description) ERR-INVALID-DESCRIPTION)
        (asserts! (> funding-goal u0) ERR-INVALID-AMOUNT)
        
        (let ((new-venture-id (+ (var-get next-venture-id) u1)))
            (map-insert coding-ventures
                { venture-id: new-venture-id }
                {
                    founder: tx-sender,
                    title: title,
                    description: description,
                    funding-goal: funding-goal,
                    raised-amount: u0,
                    status: "active",
                    launch-block: block-height,
                    category: category
                }
            )
            (var-set next-venture-id new-venture-id)
            (ok new-venture-id)
        )
    )
)

;; Add development objective
(define-public (add-objective 
                (venture-id uint)
                (title (string-ascii 100))
                (description (string-utf8 500))
                (deadline uint)
                (reward-amount uint))
    (begin
        ;; Validate inputs
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        (asserts! (valid-ascii-string title) ERR-INVALID-OBJECTIVE-TITLE)
        (asserts! (valid-utf8-string description) ERR-INVALID-OBJECTIVE-DESC)
        (asserts! (valid-timeline deadline) ERR-INVALID-TIMELINE)
        
        (let ((venture-info (unwrap! (map-get? coding-ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND)))
            (asserts! (is-eq (get founder venture-info) tx-sender) ERR-ACCESS-DENIED)
            (asserts! (>= (get funding-goal venture-info) reward-amount) ERR-INVALID-AMOUNT)
            
            (map-insert development-objectives
                { 
                    venture-id: venture-id,
                    objective-id: u1
                }
                {
                    title: title,
                    description: description,
                    deadline: deadline,
                    reward-amount: reward-amount,
                    status: "pending",
                    completion-proof: u""
                }
            )
            (ok true)
        )
    )
)

;; Back a venture with funding
(define-public (back-venture (venture-id uint) (amount uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        
        (let (
            (venture-info (unwrap! (map-get? coding-ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
            (current-raised (get raised-amount venture-info))
            (goal (get funding-goal venture-info))
        )
            (asserts! (is-eq (get status venture-info) "active") ERR-ALREADY-COMPLETED)
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            (asserts! (<= (+ current-raised amount) goal) ERR-INVALID-AMOUNT)
            
            ;; Transfer STX from backer to contract
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            
            ;; Update venture funding
            (map-set coding-ventures
                { venture-id: venture-id }
                (merge venture-info {
                    raised-amount: (+ current-raised amount)
                })
            )
            
            ;; Record backer contribution
            (match (map-get? backer-contributions 
                    { venture-id: venture-id, backer: tx-sender })
                existing-contribution 
                (map-set backer-contributions
                    { venture-id: venture-id, backer: tx-sender }
                    { 
                        amount: (+ amount (get amount existing-contribution)),
                        timestamp: block-height
                    }
                )
                (map-insert backer-contributions
                    { venture-id: venture-id, backer: tx-sender }
                    { amount: amount, timestamp: block-height }
                )
            )
            
            (ok true)
        )
    )
)

;; Complete development objective
(define-public (complete-objective (venture-id uint) (objective-id uint) (proof (string-utf8 200)))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        (asserts! (valid-objective-id objective-id) ERR-INVALID-OBJECTIVE-ID)
        
        (let (
            (venture-info (unwrap! (map-get? coding-ventures 
                { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
            (objective-info (unwrap! (map-get? development-objectives 
                { venture-id: venture-id, objective-id: objective-id }) 
                ERR-OBJECTIVE-NOT-FOUND))
        )
            (asserts! (is-eq (get founder venture-info) tx-sender) ERR-ACCESS-DENIED)
            (asserts! (>= block-height (get deadline objective-info)) ERR-OBJECTIVE-PENDING)
            
            ;; Update objective status
            (map-set development-objectives
                { venture-id: venture-id, objective-id: objective-id }
                (merge objective-info { 
                    status: "completed",
                    completion-proof: proof
                })
            )
            
            ;; Transfer reward to founder
            (try! (as-contract (stx-transfer? 
                (get reward-amount objective-info) 
                tx-sender 
                (get founder venture-info))))
            
            (ok true)
        )
    )
)

;; NEW FUNCTION: Withdraw unused funds (if venture fails to reach goal)
(define-public (withdraw-contribution (venture-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        
        (let (
            (venture-info (unwrap! (map-get? coding-ventures { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
            (contribution-info (unwrap! (map-get? backer-contributions 
                { venture-id: venture-id, backer: tx-sender }) ERR-VENTURE-NOT-FOUND))
        )
            ;; Only allow withdrawal if venture is marked as failed or expired
            (asserts! (is-eq (get status venture-info) "failed") ERR-ACCESS-DENIED)
            (asserts! (> (get amount contribution-info) u0) ERR-INVALID-AMOUNT)
            
            ;; Transfer funds back to backer
            (try! (as-contract (stx-transfer? 
                (get amount contribution-info)
                tx-sender
                tx-sender)))
            
            ;; Remove contribution record
            (map-delete backer-contributions { venture-id: venture-id, backer: tx-sender })
            
            (ok (get amount contribution-info))
        )
    )
)

;; Read-only functions
;; Get venture details
(define-read-only (get-venture-info (venture-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        (ok (unwrap! (map-get? coding-ventures 
            { venture-id: venture-id }) ERR-VENTURE-NOT-FOUND))
    )
)

;; Get objective details
(define-read-only (get-objective-info (venture-id uint) (objective-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        (asserts! (valid-objective-id objective-id) ERR-INVALID-OBJECTIVE-ID)
        (ok (unwrap! (map-get? development-objectives 
            { venture-id: venture-id, objective-id: objective-id }) 
            ERR-OBJECTIVE-NOT-FOUND))
    )
)

;; Get total ventures count
(define-read-only (get-venture-count)
    (ok (var-get next-venture-id))
)

;; Get backer contribution
(define-read-only (get-backer-info (venture-id uint) (backer principal))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        (ok (unwrap! (map-get? backer-contributions 
            { venture-id: venture-id, backer: backer }) 
            ERR-VENTURE-NOT-FOUND))
    )
)

;; Check if venture reached funding goal
(define-read-only (is-fully-funded (venture-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        (match (map-get? coding-ventures { venture-id: venture-id })
            venture-info (ok (>= (get raised-amount venture-info) 
                                (get funding-goal venture-info)))
            ERR-VENTURE-NOT-FOUND
        )
    )
)

;; Check if objective is completed
(define-read-only (is-objective-done (venture-id uint) (objective-id uint))
    (begin
        (asserts! (valid-venture-id venture-id) ERR-INVALID-VENTURE-ID)
        (asserts! (valid-objective-id objective-id) ERR-INVALID-OBJECTIVE-ID)
        (match (map-get? development-objectives 
            { venture-id: venture-id, objective-id: objective-id })
            objective-info (ok (is-eq (get status objective-info) "completed"))
            ERR-OBJECTIVE-NOT-FOUND
        )
    )
)