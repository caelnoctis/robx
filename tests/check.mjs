import { LuauState } from "./luau.mjs";
import fs from "node:fs";
const file = process.argv[2];
const src = fs.readFileSync(file, "utf8");
const state = await LuauState.createAsync();
const res = state.loadstring(src, "NoctisENIX");
if (typeof res === "string") {
  console.log("SYNTAX ERROR:", res);
  process.exit(1);
}
console.log("SYNTAX OK:", file);
process.exit(0);
