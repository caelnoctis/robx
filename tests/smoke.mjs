// Usage: node smoke.mjs [../NoctisENIX.lua] [smoke_main.lua]
import { LuauState } from "luau-web";
import fs from "node:fs";
import path from "node:path";
const here = path.dirname(new URL(import.meta.url).pathname);
const script = fs.readFileSync(process.argv[2] || path.join(here, "..", "NoctisENIX.lua"), "utf8");
const prelude = fs.readFileSync(path.join(here, "prelude.lua"), "utf8");
const epilogue = fs.readFileSync(process.argv[3] || path.join(here, "smoke_main.lua"), "utf8");
const code = prelude + "\n" + script + "\n" + epilogue;
fs.mkdirSync(path.join(here, ".debug"), { recursive: true });
fs.writeFileSync(path.join(here, ".debug", "smoke_combined.lua"), code);
const state = await LuauState.createAsync();
const fn = state.loadstring(code, "smoke");
if (typeof fn === "string") { console.log("COMPILE ERROR:", fn); process.exit(1); }
try {
  const r = String(await fn());
  const verdict = r.split("\n").filter((l) => /ALL V2|FAILURES| - /.test(l));
  console.log(verdict.join("\n"));
  process.exit(/FAILURES/.test(r) ? 1 : 0);
} catch (e) { console.log("RUNTIME ERROR:", e?.message ?? e, "(see tests/.debug/smoke_combined.lua)"); process.exit(1); }
