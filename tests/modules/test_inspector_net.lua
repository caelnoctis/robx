local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
local RS = game:GetService("ReplicatedStorage")
local SN = __mk("Folder", { Name = "ServiceNetworks" }, RS)
local RN = __mk("Folder", { Name = "RoleNetworks" }, RS)
local roleSvc = __mk("Folder", { Name = "roleService" }, SN)
local roleRF = __mk("RemoteFunction", { Name = "role" }, roleSvc)
local mafia = __mk("Folder", { Name = "mafia" }, RN)
local teamRF = __mk("RemoteFunction", { Name = "teamMembers" }, mafia)
local onStab = __mk("RemoteFunction", { Name = "onStab" }, mafia)
local called = {}
__Methods.InvokeServer = function(self)
    called[self.Name] = (called[self.Name] or 0) + 1
    if self == roleRF then return "Mafia" end
    if self == teamRF then return { "Alice" } end
    return nil
end
-- decompile palsu: harus dipanggil untuk modul client (baca saja), bukan require
local client = __mk("Folder", { Name = "client" }, RS)
local controllers = __mk("Folder", { Name = "controllers" }, client)
local rc = __mk("ModuleScript", { Name = "roleController" }, controllers)
local rolesF = __mk("Folder", { Name = "roles" }, rc)
local mafiaMod = __mk("ModuleScript", { Name = "mafia" }, rolesF)
local decompiled = {}
decompile = function(m)
    decompiled[m] = true
    return "local net = require(x)\nfunction M.handleMafiaStab(target)\n  net.onStab:InvokeServer(target.Character)\nend"
end
local API = (getgenv and getgenv() or _G).NoctisENIX_Inspector
API.snapshot()
local text = API.text()
check(string.find(text, "GAME NETWORK", 1, true) ~= nil, "network section present")
check(string.find(text, 'roleService.role -> "Mafia"', 1, true) ~= nil, "role getter printed")
check(string.find(text, "Own role folder: mafia", 1, true) ~= nil, "own role folder found")
check(string.find(text, "mafia.teamMembers ->", 1, true) ~= nil, "safe role getter called")
check(string.find(text, "mafia.onStab (RemoteFunction, not called)", 1, true) ~= nil, "action remote NOT called")
check(called.onStab == nil, "onStab never invoked")
local text2 = API.text()
check(decompiled[mafiaMod] == true, "mafia module decompiled")
check(string.find(text2, ">> 3:   net.onStab:InvokeServer(target.Character)", 1, true) ~= nil, "key call line highlighted")
decompile = nil
if #fails == 0 then print("PASS inspector-net") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
