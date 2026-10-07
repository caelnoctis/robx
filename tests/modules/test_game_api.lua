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
workspace:SetAttribute("gamePhase", nil)
G.addPhaseProvider(function() return "Night 3" end)
check(G.isNight() == true, "phase from provider")
-- roles
check(G.matchRole("[MAFIA]") == "Mafia", "matchRole bracket: " .. tostring(G.matchRole("[MAFIA]")))
check(G.matchRole("the dark witch") == "Witch", "matchRole witch")
check(G.matchRole("mafiaDead") == nil, "matchRole must not match inside words")
check(G.teamOf("Janitor") == "TOWN", "team janitor (counters saboteur)")
check(G.teamOf("Bodyguard") == "NEUTRAL", "team bodyguard (neutral, follows protege): " .. tostring(G.teamOf("Bodyguard")))
check(G.matchRole("snowspirit") == "Snow Spirit", "alias snowspirit: " .. tostring(G.matchRole("snowspirit")))
check(G.matchRole("the snow spirit froze them") == "Snow Spirit", "snow spirit phrase")
check(G.matchRole("DETAINER") == "Detainer", "detainer")
check(G.teamOf("Jester") == "NEUTRAL", "jester neutral")
check(G.teamOf("Poisoner") == "VEIL" and G.teamOf("Harbinger") == "VEIL", "poisoner / harbinger veil")
check(G.teamOf("Judge") == "TOWN" and G.teamOf("Suppressor") == "TOWN", "judge / suppressor town")
check(G.teamOf("Witch") == "EVIL", "witch evil")
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
-- v2.3: warna role (cadangan dari capture), role musiman, hotkey game
local mc = G.roleColor("Mafia")
check(typeof(mc) == "Color3" and math.abs(mc.R - 151 / 255) < 0.01 and math.abs(mc.G - 32 / 255) < 0.01, "mafia role color fallback")
check(G.roleColor("Snow Spirit") ~= nil and G.roleColor("snowspirit") ~= nil, "role color key normalised")
check(G.roleColor("Nobody") == nil, "unknown role has no color")
check(G.roleEnabled("Phantom") == true, "seasonal role enabled when config is missing")
local hk = G.gameHotkeys(true)
local byId = {}
for _, a in ipairs(hk) do byId[a.id] = a end
check(byId.ability1 and byId.ability1.key == "T" and byId.ability2.key == "G" and byId.ability3.key == "R", "default ability keys T/G/R")
check(G.hotkeyAction("G") == "Second ability", "G is Second ability: " .. tostring(G.hotkeyAction("G")))
check(G.hotkeyAction("K") == nil, "K is free")
me:SetAttribute("Hotkeys", '{"freeCursor":"U","ability2":"F","flashlight":"G","perk":"None"}')
hk = G.gameHotkeys(true)
byId = {}
for _, a in ipairs(hk) do byId[a.id] = a end
check(byId.ability2.key == "F" and byId.ability2.custom == true, "ability2 rebound to F")
check(byId.flashlight.key == "G" and byId.freeCursor.key == "U", "flashlight G, free cursor U")
check(byId.perk.key == nil, "perk unbound")
check(G.hotkeyAction("G") == "Flashlight", "G now flashlight: " .. tostring(G.hotkeyAction("G")))
check(G.hotkeyAction("F") == "Second ability", "F now second ability")
me:SetAttribute("Hotkeys", "[]")
check(G.gameHotkeys(true)[1].key == "E", "empty override keeps defaults")
if #fails == 0 then print("PASS game_api") else for _, f in ipairs(fails) do print("FAIL " .. f) end end

-- v2.1: require cuma untuk shared.configurations, tim via getTeamOfRole, tanpa role palsu
do
    local fails2 = {}
    local function check2(c, m) if not c then fails2[#fails2 + 1] = m end end
    local G2 = ctx.Game
    local RS2 = ctx.ReplicatedStorage
    local sharedF = RS2:FindFirstChild("shared")
    local cfgF = sharedF:FindFirstChild("configurations")
    local rolesM = cfgF:FindFirstChild("roles")
    local teamsM = __mk("ModuleScript", { Name = "teamsConfig" }, cfgF)
    local colorsM = __mk("ModuleScript", { Name = "roleColorsConfig" }, cfgF)
    local seasonalM = __mk("ModuleScript", { Name = "seasonalRolesConfig" }, cfgF)
    local hotkeysM = __mk("ModuleScript", { Name = "hotkeysConfig" }, cfgF)
    local ctrl = RS2:FindFirstChild("Src"):FindFirstChild("client"):FindFirstChild("controllers"):FindFirstChild("roleController")
    check2(G2.requireAllowed(rolesM) == true, "config module allowed")
    check2(G2.requireAllowed(ctrl) == false, "client controller blocked")
    local required = {}
    require = function(m)
        required[m] = true
        if m == rolesM then
            return {
                mafia = { name = "Mafia" }, witch = { name = "Witch" }, jester = { name = "Jester" },
                detective = { name = "Detective" }, civilian = { name = "Civilian" },
            }
        elseif m == colorsM then
            return { mafia = Color3.fromRGB(10, 20, 30), bogus = "x" }
        elseif m == seasonalM then
            return { enabled = { phantom = false, snowspirit = false } }
        elseif m == hotkeysM then
            return {
                ATTRIBUTE = "Hotkeys", UNBOUND = "None",
                actions = {
                    { id = "ability1", default = "T", label = "Main ability", group = "ROLE" },
                    { id = "ability2", default = "G", label = "Second ability", group = "ROLE" },
                    { id = "disguiseMusic", default = "M", label = "Disguise music", devOnly = true },
                },
            }
        elseif m == teamsM then
            return {
                getTeamOfRole = function(r)
                    local t = { mafia = "mafia", witch = "mafia", jester = "neutral", detective = "town", civilian = "town" }
                    return t[r]
                end,
                teams = {
                    veil = { name = "The Veil", roles = { "saboteur", "mirage" }, highlightTypes = { a = 1 } },
                    mafia = { name = "Mafia", roles = { "mafia", "witch" }, chatChannel = "Mafia" },
                },
            }
        end
        error("should not be required")
    end
    G2.caps.require = true
    G2.flushConfig()
    local ok, res = pcall(G2.require, ctrl)
    check2(required[ctrl] == nil, "controller never required")
    local map = G2.roles(true)
    check2(G2.rolesFromConfig == true, "roles from config")
    check2(G2.teamOf("Witch") == "EVIL", "witch team via getTeamOfRole")
    check2(G2.teamOf("Jester") == "NEUTRAL", "jester neutral: " .. tostring(G2.teamOf("Jester")))
    check2(G2.teamOf("Saboteur") == "VEIL", "saboteur via teams.veil.roles / fallback")
    check2(map["the veil"] == nil and map["roles"] == nil and map["highlighttypes"] == nil and map["chatchannel"] == nil, "no bogus roles from teams config")
    check2(G2.matchRole("these roles are confusing") == nil, "'roles' is not a role")
    local c2 = G2.roleColor("Mafia")
    check2(c2 and math.abs(c2.R - 10 / 255) < 0.01, "role color from roleColorsConfig")
    check2(G2.roleEnabled("Phantom") == false and G2.roleEnabled("Snow Spirit") == false and G2.roleEnabled("Mafia") == true, "seasonalRolesConfig respected")
    G2.roles(true)
    check2(G2.matchRole("the phantom") == nil and G2.matchRole("snow spirit") == nil, "disabled seasonal roles not matched")
    check2(G2.matchRole("the mafia") == "Mafia", "normal roles still matched")
    ctx.LocalPlayer:SetAttribute("Hotkeys", nil)
    local hk2 = G2.gameHotkeys(true)
    check2(#hk2 == 2 and hk2[1].key == "T", "hotkeys from hotkeysConfig, devOnly skipped: " .. #hk2)
    check2(G2.hotkeyAction("M") == nil, "dev-only key ignored")
    require = nil
    G2.caps.require = false
    if #fails2 == 0 then print("PASS game_api v2.1") else for _, f in ipairs(fails2) do print("FAIL " .. f) end end
end
