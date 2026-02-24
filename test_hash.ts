import { simnet } from '@hirosystems/clarinet-sdk';
import { Cl } from '@stacks/transactions';

const moveVal = Cl.uint(1);
const saltStr = "super-secret-salt-1";
const saltBuf = Buffer.alloc(32);
saltBuf.write(saltStr, 0, 32, "utf8");
const saltVal = Cl.buffer(saltBuf);

const result = simnet.callReadOnlyFn("rockpaperscissors", "hash-move-wrapper", [moveVal, saltVal], "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM");
console.log("RESULT:", result.result);
