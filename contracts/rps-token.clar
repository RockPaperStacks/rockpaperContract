;; title: rps-token
;; version: 1.0
;; summary: Reward token for RockPaperStacks winners

(define-fungible-token rps-token)

;; constants
(define-constant err-unauthorized (err u401))

;; data vars
(define-data-var admin principal tx-sender)
(define-data-var game-contract principal .rockpaperscissors)

;; public functions
(define-public (set-game-contract (new-contract principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) err-unauthorized)
        (ok (var-set game-contract new-contract))
    )
)

(define-public (mint (amount uint) (recipient principal))
    (begin
        (asserts! (or (is-eq contract-caller (var-get game-contract)) (is-eq tx-sender (var-get admin))) err-unauthorized)
        (ft-mint? rps-token amount recipient)
    )
)

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (or (is-eq tx-sender sender) (is-eq contract-caller sender)) err-unauthorized)
        (ft-transfer? rps-token amount sender recipient)
    )
)

;; read only functions
(define-read-only (get-name)
    (ok "RockPaperStacks Token")
)

(define-read-only (get-symbol)
    (ok "RPS")
)

(define-read-only (get-decimals)
    (ok u6)
)

(define-read-only (get-balance (who principal))
    (ok (ft-get-balance rps-token who))
)

(define-read-only (get-total-supply)
    (ok (ft-get-supply rps-token))
)

(define-read-only (get-token-uri)
    (ok none)
)
