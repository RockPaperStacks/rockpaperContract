import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";
import * as crypto from "crypto";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;

// helper functions for RPS hashing
function hashMove(move: number, saltStr: string, caller: string): Uint8Array {
    const moveVal = Cl.uint(move);
    const saltBuf = Buffer.alloc(32);
    saltBuf.write(saltStr, 0, 32, "utf8");
    const saltVal = Cl.buffer(saltBuf);

    // Use the contract to guarantee exact hash serialization matching for tests
    const result = simnet.callReadOnlyFn("rockpaperscissors", "hash-move-wrapper", [moveVal, saltVal], caller);
    const val = result.result as any;
    // simnet sometimes returns values as a hex string
    if (typeof val.value === "string") {
        return new Uint8Array(Buffer.from(val.value, "hex"));
    }
    return new Uint8Array(val.buffer);
}

const saltFromStr = (saltStr: string) => {
    const saltBuf = Buffer.alloc(32);
    saltBuf.write(saltStr, 0, 32, "utf8");
    return saltBuf;
};

describe("rockpaperscissors logic tests", () => {
    it("ensures simnet is well initialised", () => {
        expect(simnet.blockHeight).toBeDefined();
    });

    it("can increment and decrement test counter", () => {
        // Increment
        let receipt = simnet.callPublicFn("rockpaperscissors", "increment", [], address1);
        expect(receipt.result).toBeOk(Cl.uint(1));

        // Increment again
        receipt = simnet.callPublicFn("rockpaperscissors", "increment", [], address1);
        expect(receipt.result).toBeOk(Cl.uint(2));

        // Decrement
        receipt = simnet.callPublicFn("rockpaperscissors", "decrement", [], address1);
        expect(receipt.result).toBeOk(Cl.uint(1));

        // Verify read only
        const { result } = simnet.callReadOnlyFn("rockpaperscissors", "get-counter", [], address1);
        expect(result).toBeUint(1);
    });

    it("allows a full game of single round, p1 wins and gets tokens", () => {
        const wager = 100;
        const fees = 2;
        const expectedPayout = (wager * 2) - fees;

        // Create game
        let receipt = simnet.callPublicFn(
            "rockpaperscissors",
            "create-game",
            [Cl.uint(wager), Cl.none(), Cl.stringAscii("single")],
            address1
        );
        expect(receipt.result).toBeOk(Cl.uint(1));

        // Join game
        receipt = simnet.callPublicFn(
            "rockpaperscissors",
            "join-game",
            [Cl.uint(1)],
            address2
        );
        expect(receipt.result).toBeOk(Cl.bool(true));

        // Generate commitments
        // P1: Rock (u1), P2: Scissors (u3) => P1 Wins
        const p1Salt = "super-secret-salt-1";
        const p2Salt = "super-secret-salt-2";
        // hashMove returns a Uint8Array. We must wrap it in Cl.buffer()
        const p1Hash = hashMove(1, p1Salt, address1);
        const p2Hash = hashMove(3, p2Salt, address2);

        // Commit moves
        receipt = simnet.callPublicFn("rockpaperscissors", "commit-move", [Cl.uint(1), Cl.buffer(p1Hash)], address1);
        expect(receipt.result).toBeOk(Cl.bool(true));

        receipt = simnet.callPublicFn("rockpaperscissors", "commit-move", [Cl.uint(1), Cl.buffer(p2Hash)], address2);
        expect(receipt.result).toBeOk(Cl.bool(true));

        // Verify read only commitment status
        let status = simnet.callReadOnlyFn("rockpaperscissors", "both-committed", [Cl.uint(1)], address1);
        expect(status.result).toBeBool(true);

        // Reveal moves
        console.log("P1 Hash generated locally:", Buffer.from(p1Hash).toString('hex'));

        receipt = simnet.callPublicFn(
            "rockpaperscissors",
            "reveal-move",
            [Cl.uint(1), Cl.uint(1), Cl.buffer(saltFromStr(p1Salt))],
            address1
        );
        console.log("Reveal P1 Receipt:");
        console.log(receipt.result);

        // if the contract rejects with a hash mismatch it might be how we form the buffer in ts versus how `to-consensus-buff?` behaves in Stacks
        expect(receipt.result).toBeOk(Cl.bool(true));

        receipt = simnet.callPublicFn(
            "rockpaperscissors",
            "reveal-move",
            [Cl.uint(1), Cl.uint(3), Cl.buffer(saltFromStr(p2Salt))],
            address2
        );
        expect(receipt.result).toBeOk(Cl.bool(true));

        // Verify game finished and winner
        const gameState = simnet.callReadOnlyFn("rockpaperscissors", "get-game", [Cl.uint(1)], address1);
        const unwrapped = gameState.result as any; // The Option<Tuple>
        // Depending on sdk, we can assert directly
        expect(unwrapped.value.data.status).toEqual(Cl.stringAscii("finished"));
        expect(unwrapped.value.data.winner).toEqual(Cl.some(Cl.principal(address1)));

        // Verify token mint (10 rps tokens -> 10000000 units usually due to decimals)
        // Wait, did we setup the game-contract inside rps-token? We should!
        // But our deploy might initialize it appropriately since we coded it. 
        // Let's check token balance of address1.
        const tokenBalance = simnet.callReadOnlyFn("rps-token", "get-balance", [Cl.principal(address1)], address1);
        expect(tokenBalance.result).toBeOk(Cl.uint(10000000));
    });

    it("verifies hash mismatches are rejected", () => {
        // Create game dynamically to avoid index errors
        const gameRes = simnet.callPublicFn("rockpaperscissors", "create-game", [Cl.uint(100), Cl.none(), Cl.stringAscii("single")], address1);
        const gameId = (gameRes.result as any).value;

        simnet.callPublicFn("rockpaperscissors", "join-game", [gameId], address2);

        // P1: Rock
        const p1Salt = "super-secret-salt-1";
        const p1Hash = hashMove(1, p1Salt, address1);

        // Commit move
        simnet.callPublicFn("rockpaperscissors", "commit-move", [gameId, Cl.buffer(p1Hash)], address1);

        // P2 commits some hash
        const p2Hash = hashMove(2, "random", address2);
        simnet.callPublicFn("rockpaperscissors", "commit-move", [gameId, Cl.buffer(p2Hash)], address2);

        // P1 reveals WRONG move (p1 committed rock=1, reveals scissors=3)
        const receipt = simnet.callPublicFn(
            "rockpaperscissors",
            "reveal-move",
            [gameId, Cl.uint(3), Cl.buffer(saltFromStr(p1Salt))],
            address1
        );
        // Expect hash-mismatch (err u306)
        expect(receipt.result).toBeErr(Cl.uint(306));
    });
});
