local G = ctx.Game
local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
-- struktur modul palsu
local RS = ctx.ReplicatedStorage
local shared = __mk("Folder", { Name = "shared" }, RS)
local cfgs = __mk("Folder", { Name = "configurations" }, shared)
__mk("ModuleScript", { Name = "roles" }, cfgs)
check(G.resolve("shared.configurations.roles") ~= nil, "resolve direct")
local deep = __mk("Folder", { Name = "Src" }, RS)
local cl = __mk("Folder", { Name = "client" }, deep)
local ctr = __mk("Folder", { Name = "controllers" }, cl)
__mk("ModuleScript", { Name = "roleController" }, ctr)
check(G.resolve("client.controllers.roleController") ~= nil, "resolve deep fallback")
check(G.resolve("nope.nothing") == nil, "resolve miss")
-- require di mock tidak ada -> nil
check(G.require("shared.configurations.roles") == nil, "require nil without support")
-- attr case-insensitive & flag
local me = ctx.LocalPlayer
me.Character:SetAttribute("downed", true)
check(G.flag(me, "Downed") == true, "flag case-insensitive on character")
check(G.flag(me, "Detained") == false, "flag false")
game:GetService("CollectionService"):AddTag(me.Character, "Detained")
check(G.flag(me, "Detained") == true, "flag via tag")
-- phase
workspace:SetAttribute("gamePhase", "Night")
check(G.isNight() == true, "night")
workspace:SetAttribute("gamePhase", "Voting")
check(G.isNight() == false, "voting not night")
-- roles
check(G.matchRole("[MAFIA]") == "Mafia", "matchRole bracket: " .. tostring(G.matchRole("[MAFIA]")))
check(G.matchRole("the dark witch") == "Witch", "matchRole witch")
check(G.matchRole("mafiaDead") == nil, "matchRole must not match inside words")
check(G.teamOf("Janitor") == "EVIL", "team janitor")
check(G.teamOf("Saboteur") == "VEIL", "team saboteur")
check(G.normalizeTeam("VEIL TEAM") == "VEIL", "normalizeTeam")
-- animations
local assets = __mk("Folder", { Name = "assets" }, RS)
local anims = __mk("Folder", { Name = "animations" }, assets)
local p1 = __mk("Folder", { Name = "player1" }, anims)
__mk("Animation", { Name = "Wounded Crawling", AnimationId = "rbxassetid://111" }, p1)
__mk("Animation", { Name = "KnifeSwing", AnimationId = "rbxassetid://222" }, p1)
G.scanAnimations(true)
check(G.findAnimation({ "Wounded Crawling" }) ~= nil, "find anim exact")
check(G.findAnimation({ "knife" }) ~= nil, "find anim substring")
check(G.animationName("http://www.roblox.com/asset/?id=222") == "KnifeSwing", "anim by id")
check(G.configNumber("maxSilenceDistance", 12) == 12, "config default")
if #fails == 0 then print("PASS game_api") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
