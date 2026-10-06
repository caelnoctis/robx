// Usage: node modtest.mjs <test.lua> [FactoryName=path/to/module.lua ...]
// Menyusun: prelude + __GameFactory (game_api.lua) + factory modul + ctx_mock + test, lalu jalanin di Luau (luau-web).
import { LuauState } from "luau-web";
import fs from "node:fs";
import path from "node:path";
const here = path.dirname(new URL(import.meta.url).pathname);
const [testFile, ...mods] = process.argv.slice(2);
if (!testFile) { console.log("usage: node modtest.mjs <test.lua> [Name=module.lua ...]"); process.exit(2); }
const wrap = (name, file) => `local ${name} = (function()\n${fs.readFileSync(file, "utf8")}\nend)()\n`;
let code = fs.readFileSync(path.join(here, "prelude.lua"), "utf8") + "\n";
code += wrap("__GameFactory_local", path.join(here, "..", "src", "modules", "game_api.lua")) + "__GameFactory = __GameFactory_local\n";
for (const m of mods) { const [n, f] = m.split("="); code += wrap(n, f); }
code += fs.readFileSync(path.join(here, "ctx_mock.lua"), "utf8") + "\n";
code += fs.readFileSync(testFile, "utf8") + "\nreturn table.concat(__out, '\\n')\n";
const dbg = path.join(here, ".debug", "modtest_" + path.basename(testFile));
fs.mkdirSync(path.dirname(dbg), { recursive: true });
fs.writeFileSync(dbg, code);
const state = await LuauState.createAsync();
const fn = state.loadstring(code, "modtest");
if (typeof fn === "string") { console.log("COMPILE ERROR:", fn, "\n(line numbers refer to " + dbg + ")"); process.exit(1); }
try { const r = await fn(); console.log(String(r)); } catch (e) { console.log("RUNTIME ERROR:", e?.message ?? e, "\n(line numbers refer to " + dbg + ")"); process.exit(1); }
