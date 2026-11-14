// Unit tests for src/lib/sports-parse.ts. Run: node scripts/test-sports-parse.ts
import assert from "node:assert/strict";

import { parseEvents, parseLineup } from "../src/lib/sports-parse.ts";

const lu = parseLineup("1 Alisson GK\n4 Virgil van Dijk DF\nSalah\n\nsubs\n18 Gakpo FW");
assert.equal(lu.length, 4);
assert.deepEqual(lu[0], { name: "Alisson", number: 1, position: "GK", starter: true });
assert.deepEqual(lu[1], { name: "Virgil van Dijk", number: 4, position: "DF", starter: true });
assert.deepEqual(lu[2], { name: "Salah", starter: true });
assert.deepEqual(lu[3], { name: "Gakpo", number: 18, position: "FW", starter: false });

const ev = parseEvents("12 goal home Salah (Szoboszlai)\n45+2 yellow away Rice\n90' red\n67 substitution home Gakpo");
assert.deepEqual(ev.errors, []);
assert.equal(ev.out.length, 4);
assert.deepEqual(ev.out[0], { minute: 12, extra_minute: null, type: "goal", side: "home", player: "Salah", assist: "Szoboszlai" });
assert.deepEqual(ev.out[1], { minute: 45, extra_minute: 2, type: "yellow", side: "away", player: "Rice", assist: null });
assert.deepEqual(ev.out[2], { minute: 90, extra_minute: null, type: "red", side: null, player: null, assist: null });

const bad = parseEvents("twelve goal home X\n10 dance home Y");
assert.equal(bad.out.length, 0);
assert.equal(bad.errors.length, 2);
console.log("sports-parse: all tests passed");
