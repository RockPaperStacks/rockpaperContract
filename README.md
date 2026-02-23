# RockPaperStacks ✊✋✌️

> A provably fair Rock-Paper-Scissors game on the Stacks blockchain — powered by a commit-reveal scheme so neither player can cheat.

RockPaperStacks is an open-source, fully on-chain Rock-Paper-Scissors game built in Clarity on Stacks. Two players lock in their moves secretly using cryptographic commitments, reveal simultaneously, and the winner is paid instantly — no middleman, no trust required.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [The Cheating Problem](#the-cheating-problem)
- [How Commit-Reveal Solves It](#how-commit-reveal-solves-it)
- [Game Flow](#game-flow)
- [Architecture](#architecture)
- [Game Mechanics](#game-mechanics)
- [Contract Reference](#contract-reference)
- [Getting Started](#getting-started)
- [Playing a Game](#playing-a-game)
- [Timeouts & Disputes](#timeouts--disputes)
- [Stats & Leaderboard](#stats--leaderboard)
- [Security Model](#security-model)
- [Project Structure](#project-structure)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Rock-Paper-Scissors sounds simple — but putting it on a blockchain is surprisingly tricky. On a public chain, every transaction is visible. If Player 1 submits their move first, Player 2 can see it and always win. Naive on-chain RPS is completely broken.

RockPaperStacks fixes this with a **commit-reveal scheme**. Both players lock in a cryptographic hash of their move before either move is revealed. Once both commitments are on-chain, both players reveal. The contract verifies the reveals match the commitments, determines the winner, and pays out instantly.

No one can cheat. No one can back out without penalty. The blockchain enforces everything.

---

## Features

- ✊ **Provably fair** — commit-reveal scheme prevents move snooping
- 💸 **STX wagers** — put real STX on the line, winner takes all
- 🔐 **Salted commitments** — moves are hashed with a secret salt to prevent brute-force guessing
- ⏱️ **Timeout protection** — if opponent goes missing, you can claim a timeout win
- 🏆 **On-chain leaderboard** — permanent win/loss/draw record for every address
- 🎮 **Open challenges** — post an open game anyone can join, or challenge a specific address
- 🔄 **Best-of series** — play best-of-3 or best-of-5 matches in a single session
- 📊 **Full game history** — every game result permanently logged on-chain
- 🤝 **Draw handling** — draws refund both players instantly
- 🧪 **Full Clarinet test suite**

---

## The Cheating Problem

In a naive on-chain RPS implementation, moves are submitted as plain transactions:

```
Player 1 submits: ROCK   ← visible on-chain immediately
Player 2 sees it: submits PAPER  ← Player 2 wins every time
```

Even if the contract tries to hide moves, the blockchain is public. Anyone can watch the mempool, see a pending transaction, decode the move, and submit a winning counter-move — all before the first transaction even confirms.

This makes naive on-chain RPS completely unplayable as a fair game.

---

## How Commit-Reveal Solves It

RockPaperStacks uses a two-phase commit-reveal scheme:

**Phase 1 — Commit**
Each player submits a hash of their move combined with a secret salt:

```
commitment = SHA-256(move + salt)
```

The commitment is stored on-chain. Neither player can see the other's move — only a hash that reveals nothing about the underlying choice.

**Phase 2 — Reveal**
Once both commitments are on-chain, each player reveals their plaintext move and salt. The contract:
1. Hashes the revealed `move + salt`
2. Compares it against the stored commitment
3. Rejects the reveal if they don't match
4. Determines the winner once both reveals are verified

Because both moves are committed before either is revealed, neither player can change their move after seeing the opponent's commitment. The salt prevents brute-force guessing (there are only 3 possible moves, so without a salt an attacker could trivially derive the move from the hash).

---

## Game Flow

```
Player 1                    Contract                    Player 2
    │                          │                           │
    │── create-game (wager) ──►│                           │
    │◄─ game-id returned ──────│                           │
    │                          │◄── join-game (wager) ─────│
    │                          │                           │
    │   ── COMMIT PHASE ──────────────────────────────     │
    │── commit-move (hash) ───►│                           │
    │                          │◄── commit-move (hash) ────│
    │                          │                           │
    │   ── REVEAL PHASE ──────────────────────────────     │
    │── reveal-move (move+salt)►│                          │
    │                          │◄── reveal-move (move+salt)│
    │                          │                           │
    │                          │── determine winner ───────│
    │◄─ payout (if winner) ────│─── payout (if winner) ───►│
    │                          │                           │
```

---

## Architecture

RockPaperStacks is a single Clarity contract. All game state, commitments, reveals, and results live on-chain.

```
┌──────────────────────────────────────────────────────────┐
│                  rockpaperstacks.clar                    │
│                                                          │
│  ┌──────────────────────┐  ┌────────────────────────┐   │
│  │      Game Map        │  │   Commitment Map        │   │
│  │  game-id → {         │  │  {game-id, player} → { │   │
│  │    player1,          │  │    move-hash,           │   │
│  │    player2,          │  │    revealed,            │   │
│  │    wager,            │  │    move,                │   │
│  │    status,           │  │    salt                 │   │
│  │    winner,           │  │  }                      │   │
│  │    created-at,       │  └────────────────────────┘   │
│  │    round,            │                                │
│  │    series-wins-p1,   │  ┌────────────────────────┐   │
│  │    series-wins-p2    │  │    Player Stats Map     │   │
│  │  }                   │  │  player → {             │   │
│  └──────────────────────┘  │    wins, losses,        │   │
│                            │    draws, total-games,  │   │
│  ┌──────────────────────┐  │    stx-won, stx-lost,   │   │
│  │   Open Games List    │  │    current-streak,      │   │
│  │  (joinable by anyone)│  │    best-streak          │   │
│  └──────────────────────┘  │  }                      │   │
│                            └────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

---

## Game Mechanics

### Moves

| Value | Move | Beats |
|---|---|---|
| `u1` | ✊ Rock | Scissors |
| `u2` | ✋ Paper | Rock |
| `u3` | ✌️ Scissors | Paper |

### Game Modes

| Mode | Description |
|---|---|
| **Single round** | One commit-reveal cycle. Winner takes the wager. |
| **Best of 3** | First to 2 wins takes the full wager pool. |
| **Best of 5** | First to 3 wins takes the full wager pool. |

### Wager Rules

- Both players must deposit equal wagers to start
- Wagers are locked in the contract for the duration of the game
- Winner receives both wagers minus a small protocol fee
- Draws refund both players in full, no fee applied
- Open challenges specify a fixed wager — joiners must match exactly

### Timeout Windows

| Phase | Timeout |
|---|---|
| Waiting for Player 2 to join | 500 blocks (~3.5 days) |
| Waiting for both commits | 150 blocks (~25 hours) |
| Waiting for both reveals | 100 blocks (~16 hours) |

If an opponent misses their window, you can call `claim-timeout` and receive your wager back plus a timeout penalty from the opponent.

---

## Contract Reference

### Public Functions

#### `create-game`
Create a new game. Optionally challenge a specific address or leave open for anyone.

```clarity
(define-public (create-game
  (wager uint)
  (opponent (optional principal))
  (mode (string-ascii 8)))
```

| Parameter | Description |
|---|---|
| `wager` | Amount in microSTX each player puts up |
| `opponent` | Specific opponent principal, or `none` for open challenge |
| `mode` | `"single"`, `"best-of-3"`, or `"best-of-5"` |

---

#### `join-game`
Join an open game or an accepted direct challenge. Must match the wager exactly.

```clarity
(define-public (join-game (game-id uint)))
```

---

#### `commit-move`
Submit your hashed move. Must be called by both players before either can reveal.

```clarity
(define-public (commit-move
  (game-id uint)
  (move-hash (buff 32)))
```

| Parameter | Description |
|---|---|
| `game-id` | The game you are committing to |
| `move-hash` | SHA-256 hash of `(move + salt)` — see hashing guide below |

---

#### `reveal-move`
Reveal your plaintext move and salt. The contract verifies against your commitment.

```clarity
(define-public (reveal-move
  (game-id uint)
  (move uint)
  (salt (buff 32)))
```

| Parameter | Description |
|---|---|
| `game-id` | The game you are revealing in |
| `move` | Your move: `u1` Rock, `u2` Paper, `u3` Scissors |
| `salt` | The random salt you used when committing |

---

#### `claim-timeout`
Claim a timeout win if your opponent missed their commit or reveal window.

```clarity
(define-public (claim-timeout (game-id uint)))
```

---

#### `cancel-game`
Cancel an open game before anyone joins. Returns wager to creator.

```clarity
(define-public (cancel-game (game-id uint)))
```

---

### Read-Only Functions

```clarity
;; Get full game state
(define-read-only (get-game (game-id uint)))

;; Get commitment status for a player in a game
(define-read-only (get-commitment (game-id uint) (player principal)))

;; Get player win/loss/draw stats
(define-read-only (get-player-stats (player principal)))

;; Get list of open joinable games
(define-read-only (get-open-games))

;; Get total number of games ever created
(define-read-only (get-game-count))

;; Check if both players have committed in a game
(define-read-only (both-committed (game-id uint)))

;; Check if both players have revealed in a game
(define-read-only (both-revealed (game-id uint)))

;; Get current protocol fee percentage
(define-read-only (get-fee-rate))
```

---

### Error Codes

| Code | Constant | Description |
|---|---|---|
| `u300` | `err-game-not-found` | Game ID does not exist |
| `u301` | `err-not-participant` | Caller is not a player in this game |
| `u302` | `err-wrong-wager` | Joined with incorrect wager amount |
| `u303` | `err-already-committed` | Player already committed this round |
| `u304` | `err-not-committed` | Cannot reveal without prior commit |
| `u305` | `err-already-revealed` | Player already revealed this round |
| `u306` | `err-hash-mismatch` | Revealed move+salt does not match commitment |
| `u307` | `err-invalid-move` | Move must be u1, u2, or u3 |
| `u308` | `err-game-not-open` | Game is not in a joinable state |
| `u309` | `err-timeout-not-reached` | Timeout window has not expired yet |
| `u310` | `err-wrong-opponent` | Only the invited opponent can join |
| `u311` | `err-game-complete` | Game is already finished |
| `u312` | `err-not-creator` | Only the game creator can cancel |
| `u313` | `err-reveal-before-both-commit` | Both players must commit before revealing |

---

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) — Clarity development toolchain
- [Hiro Wallet](https://wallet.hiro.so/) — for testnet/mainnet play
- Node.js v18+ — for helper scripts
- STX for wagers and gas fees

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/rockpaperstacks.git
cd rockpaperstacks

# Install dependencies
npm install

# Verify contracts compile
clarinet check

# Run the test suite
clarinet test
```

---

## Playing a Game

### Step 1 — Create or join a game

**Create an open game (anyone can join):**
```clarity
;; Create a single-round game with a 10 STX wager
(contract-call? .rockpaperstacks create-game
  u10000000
  none
  "single")
```

**Challenge a specific opponent:**
```clarity
;; Challenge SP9876...opponent to a best-of-3 for 5 STX each
(contract-call? .rockpaperstacks create-game
  u5000000
  (some 'SP9876...opponent)
  "best-of-3")
```

**Join an open game:**
```clarity
(contract-call? .rockpaperstacks join-game u42)
```

---

### Step 2 — Commit your move

Hash your move locally using the helper script. Never share your salt.

```bash
# Hash move 1 (Rock) with a random salt
node scripts/hash-move.js --move 1 --salt "my-super-secret-salt-abc123"
# → 0x7f3a9b...your-commitment-hash
```

```clarity
;; Submit your commitment
(contract-call? .rockpaperstacks commit-move u42 0x7f3a9b...)
```

> ⚠️ **Save your salt!** If you lose your salt before revealing, you forfeit and your opponent can claim a timeout win.

---

### Step 3 — Reveal your move

Once both players have committed, reveal your move:

```clarity
;; Reveal Rock (u1) with your salt
(contract-call? .rockpaperstacks reveal-move
  u42
  u1
  0x6d792d73757065722d7365637265742d73616c742d61626331323300...)
```

The contract verifies your reveal matches your commitment, then waits for the opponent to reveal. Once both reveals are in, the winner is determined and paid out automatically.

---

### Step 4 — Check the result

```clarity
;; Get the final game state
(contract-call? .rockpaperstacks get-game u42)

;; Check your stats
(contract-call? .rockpaperstacks get-player-stats 'SPYourAddress...)
```

---

## Timeouts & Disputes

RockPaperStacks has no admin key and no arbitration — timeouts are enforced by the contract itself.

**Scenario 1 — Opponent never joins:**
Creator can cancel after 500 blocks and receive their wager back.

```clarity
(contract-call? .rockpaperstacks cancel-game u42)
```

**Scenario 2 — Opponent commits but never reveals:**
After 100 blocks past the reveal deadline, the player who revealed can claim the timeout:

```clarity
(contract-call? .rockpaperstacks claim-timeout u42)
```

The timeout claimant receives their wager back plus the opponent's wager as a penalty.

**Scenario 3 — Opponent never commits:**
After 150 blocks past the commit deadline, the player who committed can claim timeout and receive both wagers.

---

## Stats & Leaderboard

Every game result is permanently recorded on-chain. Query any address to see their full record:

```clarity
(contract-call? .rockpaperstacks get-player-stats 'SP1234...player)
```

| Field | Description |
|---|---|
| `wins` | Total games won |
| `losses` | Total games lost |
| `draws` | Total games drawn |
| `total-games` | Total games played |
| `stx-won` | Total microSTX won across all games |
| `stx-lost` | Total microSTX lost across all games |
| `current-streak` | Current consecutive win streak |
| `best-streak` | All-time best win streak |
| `win-rate` | Wins divided by total games (as percentage) |

---

## Security Model

**Salted commitments** — moves are hashed with a secret salt chosen by the player. Since there are only 3 possible moves, an unsalted hash could be brute-forced instantly. The salt makes preimage attacks computationally infeasible.

**Simultaneous commitment requirement** — neither player can reveal until both have committed. This ensures no player can see the opponent's commitment and game their reveal.

**Timeout enforcement** — players who stall or go offline are penalized. This prevents griefing where a losing player simply refuses to reveal, leaving the game stuck forever.

**No admin key** — once deployed, no privileged address can alter game outcomes, move funds, or modify player records. The contract is fully autonomous.

**Wager lockup** — STX is transferred into the contract at join time and held until the game resolves. No external party can access locked funds.

**Replay protection** — each game has a unique auto-incrementing ID. Commitments are scoped to `(game-id, player)` pairs and cannot be replayed across games.

**Salt privacy** — salts are never stored on-chain. Only their effect (the commitment hash) is stored. Players must keep their salt private until the reveal phase.

---

## Project Structure

```
rockpaperstacks/
├── contracts/
│   └── rockpaperstacks.clar        # Main game contract
├── tests/
│   └── rockpaperstacks_test.ts     # Full Clarinet test suite
├── scripts/
│   ├── hash-move.js                # Local move hashing utility
│   ├── create-game.ts              # CLI: create a new game
│   ├── join-game.ts                # CLI: join an open game
│   ├── commit-move.ts              # CLI: commit your move
│   ├── reveal-move.ts              # CLI: reveal your move
│   └── claim-timeout.ts           # CLI: claim timeout win
├── deployments/
│   ├── devnet.yaml
│   ├── testnet.yaml
│   └── mainnet.yaml
├── settings/
│   └── Devnet.toml
├── Clarinet.toml
├── package.json
└── README.md
```

---

## Testing

```bash
# Run all tests
clarinet test

# Run with coverage report
clarinet test --coverage

# Open interactive Clarinet console
clarinet console
```

### Test coverage includes

- Full happy path: create → join → commit → reveal → payout
- Rock beats Scissors, Paper beats Rock, Scissors beats Paper
- Draw: both players choose same move, both refunded
- Reveal rejected if move+salt doesn't match commitment
- Reveal rejected before both players have committed
- Timeout claim: opponent never commits
- Timeout claim: opponent commits but never reveals
- Timeout rejected if window hasn't passed
- Open game joinable by anyone
- Direct challenge only joinable by invited opponent
- Wrong wager amount rejected on join
- Cancel open game before anyone joins
- Best-of-3 series tracks round wins correctly
- Best-of-5 series pays out after 3 wins
- Player stats update correctly after win, loss, draw
- Streak increments and resets correctly
- All error codes triggered and verified

---

## Roadmap

- [x] Single round commit-reveal game
- [x] Open challenges and direct challenges
- [x] STX wagers with instant payout
- [x] Timeout protection for both phases
- [x] On-chain player stats and leaderboard
- [x] Best-of-3 and best-of-5 series mode
- [ ] Web UI with wallet integration
- [ ] Live game lobby showing open challenges
- [ ] Spectator mode — watch live games as they resolve
- [ ] Tournament bracket — 8 or 16 player elimination
- [ ] NFT trophy for milestone wins (10, 50, 100 wins)
- [ ] Token-gated high-stakes tables (hold a badge NFT)
- [ ] Integration with WitStac — trivia decides who picks first
- [ ] Mobile-friendly interface
- [ ] Seasonal leaderboard resets with prize pools

---

## Contributing

Contributions are welcome. To get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`clarinet test`)
5. Open a pull request with a clear description

Please read [CONTRIBUTING.md](./CONTRIBUTING.md) before submitting.

---

## License

RockPaperStacks is open source under the [MIT License](./LICENSE).

---

Built with ❤️ on [Stacks](https://stacks.co) — Bitcoin's smart contract layer.
