;; ---------------------------------------------------------
;; RockPaperStacks Game Contract
;; ---------------------------------------------------------

;; Constants
(define-constant err-game-not-found (err u300))
(define-constant err-not-participant (err u301))
(define-constant err-wrong-wager (err u302))
(define-constant err-already-committed (err u303))
(define-constant err-not-committed (err u304))
(define-constant err-already-revealed (err u305))
(define-constant err-hash-mismatch (err u306))
(define-constant err-invalid-move (err u307))
(define-constant err-game-not-open (err u308))
(define-constant err-timeout-not-reached (err u309))
(define-constant err-wrong-opponent (err u310))
(define-constant err-game-complete (err u311))
(define-constant err-not-creator (err u312))
(define-constant err-reveal-before-both-commit (err u313))

(define-constant timeout-join u500)
(define-constant timeout-commit u150)
(define-constant timeout-reveal u100)
(define-constant fee-percent u2)

;; Data Vars
(define-data-var fee-address principal tx-sender)
(define-data-var game-counter uint u0)

;; Game maps
(define-map games uint {
    player1: principal,
    player2: (optional principal),
    wager: uint,
    status: (string-ascii 20),
    winner: (optional principal),
    created-at: uint,
    updated-at: uint,
    round: uint,
    series-wins-p1: uint,
    series-wins-p2: uint,
    mode: (string-ascii 8)
})

(define-map commitments { game-id: uint, round: uint, player: principal } {
    move-hash: (buff 32),
    revealed: bool,
    move: (optional uint),
    salt: (optional (buff 32))
})

(define-map player-stats principal {
    wins: uint, losses: uint, draws: uint, total-games: uint,
    stx-won: uint, stx-lost: uint,
    current-streak: uint, best-streak: uint
})

(define-data-var open-games-var (list 50 uint) (list))

;; ---------------------------------------------------------
;; Utility Testing Functions (Counter Logic)
;; ---------------------------------------------------------
(define-data-var test-counter uint u0)

(define-public (increment)
    (begin
        (var-set test-counter (+ (var-get test-counter) u1))
        (ok (var-get test-counter))
    )
)

(define-public (decrement)
    (begin
        (var-set test-counter (- (var-get test-counter) u1))
        (ok (var-get test-counter))
    )
)

(define-read-only (get-counter)
    (var-get test-counter)
)

;; ---------------------------------------------------------
;; Core Game Logic
;; ---------------------------------------------------------
(define-public (create-game (wager uint) (opponent (optional principal)) (mode (string-ascii 8)))
    (let (
        (new-id (+ (var-get game-counter) u1))
    )
        (asserts! (or (is-eq mode "single") (is-eq mode "best-of-3") (is-eq mode "best-of-5")) (err u400))
        (try! (stx-transfer? wager tx-sender (as-contract tx-sender)))
        (map-set games new-id {
            player1: tx-sender,
            player2: opponent,
            wager: wager,
            status: "open",
            winner: none,
            created-at: block-height,
            updated-at: block-height,
            round: u1,
            series-wins-p1: u0,
            series-wins-p2: u0,
            mode: mode
        })
        (var-set game-counter new-id)
        (if (is-none opponent)
            (match (as-max-len? (append (var-get open-games-var) new-id) u50)
                success (var-set open-games-var success)
                err false
            )
            false
        )
        (ok new-id)
    )
)

(define-public (join-game (game-id uint))
    (let (
        (game (unwrap! (map-get? games game-id) err-game-not-found))
    )
        (asserts! (is-eq (get status game) "open") err-game-not-open)
        (asserts! (or (is-none (get player2 game)) (is-eq (some tx-sender) (get player2 game))) err-wrong-opponent)
        (try! (stx-transfer? (get wager game) tx-sender (as-contract tx-sender)))
        (map-set games game-id (merge game {
            player2: (some tx-sender),
            status: "joined",
            updated-at: block-height
        }))
        (ok true)
    )
)

(define-public (cancel-game (game-id uint))
    (let (
        (game (unwrap! (map-get? games game-id) err-game-not-found))
    )
        (asserts! (is-eq (get status game) "open") err-game-complete)
        (asserts! (is-eq tx-sender (get player1 game)) err-not-creator)
        (try! (as-contract (stx-transfer? (get wager game) tx-sender (get player1 game))))
        (map-set games game-id (merge game {
            status: "cancelled",
            updated-at: block-height
        }))
        (ok true)
    )
)

(define-public (commit-move (game-id uint) (move-hash (buff 32)))
    (let (
        (game (unwrap! (map-get? games game-id) err-game-not-found))
        (round (get round game))
    )
        (asserts! (or (is-eq (get status game) "joined") (is-eq (get status game) "committed")) err-game-complete)
        (asserts! (or (is-eq tx-sender (get player1 game)) (is-eq (some tx-sender) (get player2 game))) err-not-participant)
        (asserts! (is-none (map-get? commitments { game-id: game-id, round: round, player: tx-sender })) err-already-committed)
        
        (map-set commitments { game-id: game-id, round: round, player: tx-sender } {
            move-hash: move-hash,
            revealed: false,
            move: none,
            salt: none
        })
        
        (let (
            (opponent (if (is-eq tx-sender (get player1 game)) (unwrap-panic (get player2 game)) (get player1 game)))
            (opponent-commit (map-get? commitments { game-id: game-id, round: round, player: opponent }))
        )
            (if (is-some opponent-commit)
                (map-set games game-id (merge game { status: "committed", updated-at: block-height }))
                (map-set games game-id (merge game { status: "joined", updated-at: block-height }))
            )
        )
        (ok true)
    )
)

(define-private (calculate-fee (wager uint))
    (/ (* wager fee-percent) u100)
)

(define-private (update-stats (player principal) (is-win bool) (is-draw bool) (s-won uint) (s-lost uint))
    (let (
        (stats (default-to { wins: u0, losses: u0, draws: u0, total-games: u0, stx-won: u0, stx-lost: u0, current-streak: u0, best-streak: u0 } (map-get? player-stats player)))
        (new-streak (if is-win (+ (get current-streak stats) u1) u0))
        (best-streak (if (> new-streak (get best-streak stats)) new-streak (get best-streak stats)))
    )
        (map-set player-stats player {
            wins: (+ (get wins stats) (if is-win u1 u0)),
            losses: (+ (get losses stats) (if (and (not is-win) (not is-draw)) u1 u0)),
            draws: (+ (get draws stats) (if is-draw u1 u0)),
            total-games: (+ (get total-games stats) u1),
            stx-won: (+ (get stx-won stats) s-won),
            stx-lost: (+ (get stx-lost stats) s-lost),
            current-streak: new-streak,
            best-streak: best-streak
        })
    )
)

(define-private (resolve-round (game-id uint) (game { player1: principal, player2: (optional principal), wager: uint, status: (string-ascii 20), winner: (optional principal), created-at: uint, updated-at: uint, round: uint, series-wins-p1: uint, series-wins-p2: uint, mode: (string-ascii 8) }))
    (let (
        (round (get round game))
        (p1 (get player1 game))
        (p2 (unwrap-panic (get player2 game)))
        (m1 (unwrap-panic (get move (unwrap-panic (map-get? commitments { game-id: game-id, round: round, player: p1 })))))
        (m2 (unwrap-panic (get move (unwrap-panic (map-get? commitments { game-id: game-id, round: round, player: p2 })))))
        (p1-wins (or (and (is-eq m1 u1) (is-eq m2 u3)) (and (is-eq m1 u2) (is-eq m2 u1)) (and (is-eq m1 u3) (is-eq m2 u2))))
        (draw (is-eq m1 m2))
        (p2-wins (and (not p1-wins) (not draw)))
        (wins-req (if (is-eq (get mode game) "single") u1 (if (is-eq (get mode game) "best-of-3") u2 u3)))
        (new-p1-wins (+ (get series-wins-p1 game) (if p1-wins u1 u0)))
        (new-p2-wins (+ (get series-wins-p2 game) (if p2-wins u1 u0)))
        (series-over-by-wins (or (>= new-p1-wins wins-req) (>= new-p2-wins wins-req)))
        (is-single (is-eq (get mode game) "single"))
        (series-over (or series-over-by-wins (and is-single draw)))
    )
        (if series-over
            (let (
                (wager (get wager game))
                (fee (calculate-fee wager))
                (payout (- (* wager u2) fee))
            )
                (if (and is-single draw)
                    (begin
                        (try! (as-contract (stx-transfer? wager tx-sender p1)))
                        (try! (as-contract (stx-transfer? wager tx-sender p2)))
                        (update-stats p1 false true u0 u0)
                        (update-stats p2 false true u0 u0)
                        (map-set games game-id (merge game { status: "finished", round: round, updated-at: block-height }))
                        (ok true)
                    )
                    (let (
                        (winner (if (>= new-p1-wins wins-req) p1 p2))
                        (loser (if (>= new-p1-wins wins-req) p2 p1))
                    )
                        (try! (as-contract (stx-transfer? payout tx-sender winner)))
                        (if (> fee u0) (try! (as-contract (stx-transfer? fee tx-sender (var-get fee-address)))) true)
                        (update-stats winner true false payout wager)
                        (update-stats loser false false u0 wager)
                        (try! (as-contract (contract-call? .rps-token mint u10000000 winner)))
                        (map-set games game-id (merge game { status: "finished", winner: (some winner), series-wins-p1: new-p1-wins, series-wins-p2: new-p2-wins, updated-at: block-height }))
                        (ok true)
                    )
                )
            )
            (begin
                (map-set games game-id (merge game {
                    status: "joined",
                    round: (+ round u1),
                    series-wins-p1: new-p1-wins,
                    series-wins-p2: new-p2-wins,
                    updated-at: block-height
                }))
                (ok true)
            )
        )
    )
)

(define-public (reveal-move (game-id uint) (move uint) (salt (buff 32)))
    (let (
        (game (unwrap! (map-get? games game-id) err-game-not-found))
        (round (get round game))
        (commit (unwrap! (map-get? commitments { game-id: game-id, round: round, player: tx-sender }) err-not-committed))
    )
        (asserts! (is-eq (get status game) "committed") err-reveal-before-both-commit)
        (asserts! (not (get revealed commit)) err-already-revealed)
        (asserts! (or (is-eq move u1) (is-eq move u2) (is-eq move u3)) err-invalid-move)
        
        ;; verify hash
        (asserts! (is-eq (get move-hash commit) (sha256 (unwrap-panic (to-consensus-buff? { move: move, salt: salt })))) err-hash-mismatch)
        
        (map-set commitments { game-id: game-id, round: round, player: tx-sender } (merge commit {
            revealed: true,
            move: (some move),
            salt: (some salt)
        }))
        
        (let (
            (opponent (if (is-eq tx-sender (get player1 game)) (unwrap-panic (get player2 game)) (get player1 game)))
            (opponent-commit (unwrap-panic (map-get? commitments { game-id: game-id, round: round, player: opponent })))
        )
            (if (get revealed opponent-commit)
                (resolve-round game-id (merge game { status: "revealed", updated-at: block-height }))
                (begin
                    (map-set games game-id (merge game { updated-at: block-height }))
                    (ok true)
                )
            )
        )
    )
)

(define-public (claim-timeout (game-id uint))
    (let (
        (game (unwrap! (map-get? games game-id) err-game-not-found))
        (status (get status game))
        (updated (get updated-at game))
        (round (get round game))
    )
        (if (is-eq status "open")
            (begin
                (asserts! (is-eq tx-sender (get player1 game)) err-not-participant)
                (asserts! (>= block-height (+ updated timeout-join)) err-timeout-not-reached)
                (try! (as-contract (stx-transfer? (get wager game) tx-sender (get player1 game))))
                (map-set games game-id (merge game { status: "cancelled", updated-at: block-height }))
                (ok true)
            )
            (if (is-eq status "joined")
                (let (
                    (player-commit-opt (map-get? commitments { game-id: game-id, round: round, player: tx-sender }))
                )
                    (asserts! (is-some player-commit-opt) err-not-committed)
                    (asserts! (>= block-height (+ updated timeout-commit)) err-timeout-not-reached)
                    (let (
                        (wager (get wager game))
                        (payout (* wager u2))
                    )
                        (try! (as-contract (stx-transfer? payout tx-sender tx-sender)))
                        (update-stats tx-sender true false payout wager)
                        (map-set games game-id (merge game { status: "finished", winner: (some tx-sender), updated-at: block-height }))
                        (ok true)
                    )
                )
                (if (is-eq status "committed")
                    (let (
                        (player-commit (unwrap-panic (map-get? commitments { game-id: game-id, round: round, player: tx-sender })))
                    )
                        (asserts! (get revealed player-commit) err-not-committed)
                        (asserts! (>= block-height (+ updated timeout-reveal)) err-timeout-not-reached)
                        (let (
                            (wager (get wager game))
                            (payout (* wager u2))
                        )
                            (try! (as-contract (stx-transfer? payout tx-sender tx-sender)))
                            (update-stats tx-sender true false payout wager)
                            (map-set games game-id (merge game { status: "finished", winner: (some tx-sender), updated-at: block-height }))
                            (ok true)
                        )
                    )
                    err-game-complete
                )
            )
        )
    )
)

;; ---------------------------------------------------------
;; Read-Only Functions
;; ---------------------------------------------------------

(define-read-only (get-game (game-id uint))
    (map-get? games game-id)
)

(define-read-only (get-commitment (game-id uint) (player principal))
    (map-get? commitments { game-id: game-id, round: (unwrap-panic (get round (map-get? games game-id))), player: player })
)

(define-read-only (get-player-stats (player principal))
    (map-get? player-stats player)
)

(define-read-only (get-open-games)
    (var-get open-games-var)
)

(define-read-only (get-game-count)
    (var-get game-counter)
)

(define-read-only (both-committed (game-id uint))
    (let (
        (game (unwrap! (map-get? games game-id) false))
        (round (get round game))
        (p1 (get player1 game))
        (p2-opt (get player2 game))
    )
        (if (is-none p2-opt)
            false
            (let (
                (p2 (unwrap-panic p2-opt))
                (c1 (is-some (map-get? commitments { game-id: game-id, round: round, player: p1 })))
                (c2 (is-some (map-get? commitments { game-id: game-id, round: round, player: p2 })))
            )
                (and c1 c2)
            )
        )
    )
)

(define-read-only (both-revealed (game-id uint))
    (let (
        (game (unwrap! (map-get? games game-id) false))
        (round (get round game))
        (p1 (get player1 game))
        (p2-opt (get player2 game))
    )
        (if (is-none p2-opt)
            false
            (let (
                (p2 (unwrap-panic p2-opt))
                (c1 (map-get? commitments { game-id: game-id, round: round, player: p1 }))
                (c2 (map-get? commitments { game-id: game-id, round: round, player: p2 }))
            )
                (and 
                    (is-some c1) (get revealed (unwrap-panic c1))
                    (is-some c2) (get revealed (unwrap-panic c2))
                )
            )
        )
    )
)

(define-read-only (get-fee-rate)
    fee-percent
)
