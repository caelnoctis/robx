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
local API = (getgenv and getgenv() or _G).NoctisENIX_Inspector
API.snapshot()
local text = API.text()
check(string.find(text, "GAME NETWORK", 1, true) ~= nil, "network section present")
check(string.find(text, 'roleService.role -> "Mafia"', 1, true) ~= nil, "role getter printed")
check(string.find(text, "Own role folder: mafia", 1, true) ~= nil, "own role folder found")
check(string.find(text, "mafia.teamMembers ->", 1, true) ~= nil, "safe role getter called")
check(string.find(text, "mafia.onStab (RemoteFunction, not called)", 1, true) ~= nil, "action remote NOT called")
check(called.onStab == nil, "onStab never invoked")
if #fails == 0 then print("PASS inspector-net") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
