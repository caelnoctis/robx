import luaparse from "luaparse";
import fs from "node:fs";
const src = fs.readFileSync(process.argv[2], "utf8");
const ast = luaparse.parse(src, { scope: true, luaVersion: "5.1", locations: true });
const allowed = new Set(`game workspace Instance Enum Vector3 Vector2 CFrame Color3 UDim2 UDim TweenInfo task tick time os math string table
pairs ipairs next select type typeof tostring tonumber pcall xpcall error assert print warn setmetatable getmetatable rawget rawset unpack
_G coroutine utf8 bit32 ColorSequence ColorSequenceKeypoint NumberSequence NumberSequenceKeypoint NumberRange Rect Font BrickColor Ray RaycastParams OverlapParams Region3 PhysicalProperties DateTime Random tick
getgenv cloneref gethui setclipboard toclipboard hookmetamethod getnamecallmethod checkcaller newcclosure syn require debug getthreadidentity setthreadidentity getidentity setidentity getconnections getgc getreg getrenv getsenv getloadedmodules getrunningscripts getscripts getnilinstances getinstances getcallingscript getscriptbytecode decompile writefile readfile appendfile isfile isfolder makefolder listfiles delfile fireproximityprompt firetouchinterest fireclickdetector firesignal identifyexecutor getexecutorname hookfunction getrawmetatable setrawmetatable setreadonly isreadonly iscclosure islclosure isexecutorclosure sethiddenproperty gethiddenproperty getupvalue getupvalues getconstants getprotos request http_request queue_on_teleport`.split(/\s+/));
const found = new Map();
(function walk(n) {
  if (!n || typeof n !== "object") return;
  if (Array.isArray(n)) return n.forEach(walk);
  if (n.type === "Identifier" && n.isLocal === false) {
    // luaparse marks only variable refs with isLocal
    if (!allowed.has(n.name)) {
      const k = n.name;
      if (!found.has(k)) found.set(k, []);
      found.get(k).push(n.loc.start.line);
    }
  }
  for (const key of Object.keys(n)) if (key !== "loc" && key !== "range") walk(n[key]);
})(ast);
if (found.size === 0) console.log("LINT OK: no unknown globals");
else { for (const [k, v] of found) console.log("UNKNOWN GLOBAL", k, "lines", v.join(",")); process.exit(1); }
