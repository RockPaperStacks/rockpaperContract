import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";
import * as crypto from "crypto";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;

// helper functions for RPS hashing
function hashMove(move: number, saltStr: string): Uint8Array {
    // We need to hash exactly what clarity`to-consensus-buff?` would produce for a tuple of { move: uint, salt: (buff 32) }
    // Clarinet SDK simnet provides some native support for hashes but often we construct them explicitly.
    // Actually, to-consensus-buff? generates a specific clarity serialization format.
    // Simpler way: For testing we can just let clarity verify a predefined payload or use the built in simnet support
    // The Clarity `sha256` function hashes a buffer.
    // Here we use the Cl.tuple to serialize it into the clarity buffer representation 
    const moveVal = Cl.uint(move);
    // Pad the salt to 32 bytes
    const saltBuf = new Uint8Array(32);
    const saltBytes = new TextEncoder().encode(saltStr);
    saltBuf.set(saltBytes.slice(0, 32));
    const saltVal = Cl.buffer(saltBuf);

    const tuple = Cl.tuple({ move: moveVal, salt: saltVal });
    // The serialize() method output is exactly what `to-consensus-buff?` yields in clarity!
    const serialized = Cl.serialize(tuple);
    const hash = crypto.createHash('sha256');
    hash.update(serialized);
    return new Uint8Array(hash.digest());
}

const saltFromStr = (saltStr: string) => {
    const saltBuf = new Uint8Array(32);
    const saltBytes = new TextEncoder().encode(saltStr);
    saltBuf.set(saltBytes.slice(0, 32));
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
        const p1Hash = hashMove(1, p1Salt);
        const p2Hash = hashMove(3, p2Salt);

        // Commit moves
        receipt = simnet.callPublicFn("rockpaperscissors", "commit-move", [Cl.uint(1), Cl.buffer(p1Hash)], address1);
        expect(receipt.result).toBeOk(Cl.bool(true));

        receipt = simnet.callPublicFn("rockpaperscissors", "commit-move", [Cl.uint(1), Cl.buffer(p2Hash)], address2);
        expect(receipt.result).toBeOk(Cl.bool(true));

        // Verify read only commitment status
        let status = simnet.callReadOnlyFn("rockpaperscissors", "both-committed", [Cl.uint(1)], address1);
        expect(status.result).toBeBool(true);

        // Reveal moves
        receipt = simnet.callPublicFn(
            "rockpaperscissors",
            "reveal-move",
            [Cl.uint(1), Cl.uint(1), Cl.buffer(saltFromStr(p1Salt))],
            address1
        );
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
        // Create game
        simnet.callPublicFn("rockpaperscissors", "create-game", [Cl.uint(100), Cl.none(), Cl.stringAscii("single")], address1);
        simnet.callPublicFn("rockpaperscissors", "join-game", [Cl.uint(2)], address2);

        // P1: Rock
        const p1Salt = "super-secret-salt-1";
        const p1Hash = hashMove(1, p1Salt);

        // Commit move
        simnet.callPublicFn("rockpaperscissors", "commit-move", [Cl.uint(2), Cl.buffer(p1Hash)], address1);

        // P2 commits some hash
        const p2Hash = hashMove(2, "random");
        simnet.callPublicFn("rockpaperscissors", "commit-move", [Cl.uint(2), Cl.buffer(p2Hash)], address2);

        // P1 reveals WRONG move (p1 committed rock=1, reveals scissors=3)
        const receipt = simnet.callPublicFn(
            "rockpaperscissors",
            "reveal-move",
            [Cl.uint(2), Cl.uint(3), Cl.buffer(saltFromStr(p1Salt))],
            address1
        );
        // Expect hash-mismatch (err u306)
        expect(receipt.result).toBeErr(Cl.uint(306));
    });
});
