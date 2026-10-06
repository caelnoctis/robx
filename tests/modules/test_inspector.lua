-- Test NoctisENIX Inspector. Modul sudah jalan waktu di-wrap (sebelum file ini),
-- jadi semua fungsi executor di-mock di sini dan inspector harus lookup secara lazy.
local I = Inspector
local fails, passes = {}, 0
local function check(c, m)
    if c then
        passes = passes + 1
    else
        fails[#fails + 1] = m
    end
end
local function has(s, sub)
    return type(s) == "string" and string.find(s, sub, 1, true) ~= nil
end
local function count(s, sub)
    local n, i = 0, 1
    while true do
        local a, b = string.find(s, sub, i, true)
        if not a then
            return n
        end
        n = n + 1
        i = b + 1
    end
end
local function liveSection(t)
    local a = string.find(t, "==== LIVE LOG ====", 1, true)
    return a and string.sub(t, a) or ""
end

check(type(I) == "table", "module returns API table")
check(getgenv().NoctisENIX_Inspector == I, "API registered in genv")
for _, k in ipairs({ "snapshot", "startLive", "stopLive", "save", "text", "lines", "unload" }) do
    check(type(I[k]) == "function", "API has " .. k)
end
local St = I._test.state()
check(#St.errs == 0, "no errors at load: " .. table.concat(St.errs, " | "))
local gui = I._test.gui()
check(gui ~= nil and gui.Parent ~= nil, "gui mounted")
check(gui and gui.Parent == game:GetService("CoreGui"), "gui in CoreGui when gethui missing")

----------------------------------------------------------------------
-- Mock executor (lazy lookup)
----------------------------------------------------------------------
local files, folders = {}, {}
writefile = function(p, c)
    if string.find(p, "/", 1, true) and not folders[string.match(p, "^(.-)/")] then
        error("no folder")
    end
    files[p] = c
end
makefolder = function(p)
    folders[p] = true
end
isfolder = function(p)
    return folders[p] == true
end
identifyexecutor = function()
    return "MockExec", "9.9"
end
local identity = 8
local reqLog = {}
getthreadidentity = function()
    return identity
end
setthreadidentity = function(n)
    identity = n
end
local exportsOf = {}
require = function(m)
    reqLog[#reqLog + 1] = { m.Name, identity }
    local e = exportsOf[m]
    if e == nil then
        error("module " .. tostring(m.Name) .. " exploded")
    end
    return e
end
__Methods.GetAllTags = function()
    local set, out = {}, {}
    for _, tags in pairs(__tags) do
        for t, on in pairs(tags) do
            if on and not set[t] then
                set[t] = true
                out[#out + 1] = t
            end
        end
    end
    return out
end
__Methods.GetTags = function(self, inst)
    local out = {}
    for t, on in pairs(__tags[inst] or {}) do
        if on then
            out[#out + 1] = t
        end
    end
    return out
end

----------------------------------------------------------------------
-- Dunia palsu
----------------------------------------------------------------------
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local me = ctx.LocalPlayer
local function P(name)
    for _, p in ipairs(__players) do
        if p.Name == name then
            return p
        end
    end
end
local alice, bob, cara, dan, eve = P("Alice"), P("Bob"), P("Cara"), P("Dan"), P("Eve")
alice.UserId = 2

local shared = __mk("Folder", { Name = "shared" }, RS)
local cfgs = __mk("Folder", { Name = "configurations" }, shared)
local rolesM = __mk("ModuleScript", { Name = "roles" }, cfgs)
local gameCfgM = __mk("ModuleScript", { Name = "gameConfig" }, cfgs)
local voteCfgM = __mk("ModuleScript", { Name = "votingConfig" }, cfgs)
exportsOf[rolesM] = { Mafia = { team = "EVIL", description = "Kills at night" }, Doctor = { team = "TOWN" } }
exportsOf[gameCfgM] = {
    maxSilenceDistance = 20,
    nested = { deeper = { deepest = { x = 1 } } },
    roles = { Witch = true, Saboteur = true },
}
exportsOf[voteCfgM] = { voteTime = 30 }

local ps = __mk("PlayerScripts", { Name = "PlayerScripts" }, me)
local client = __mk("Folder", { Name = "client" }, ps)
local ctrls = __mk("Folder", { Name = "controllers" }, client)
local roleCtrl = __mk("ModuleScript", { Name = "roleController" }, ctrls)
__mk("ModuleScript", { Name = "brokenController" }, ctrls)
exportsOf[roleCtrl] = setmetatable({ currentRole = "Mafia", handleMafiaStab = function(target, ...) end }, {})

local props = __mk("Folder", { Name = "Props" }, RS)
for i = 1, 50 do
    __mk(i <= 30 and "Part" or "MeshPart", { Name = "P" .. i }, props)
end
local remotes = __mk("Folder", { Name = "Remotes" }, RS)
local roleRemote = __mk("RemoteEvent", { Name = "RoleReveal" }, remotes)
local stabRemote = __mk("RemoteEvent", { Name = "Stab" }, remotes)
__mk("RemoteFunction", { Name = "GetData" }, remotes)
local assets = __mk("Folder", { Name = "assets" }, RS)
local animsF = __mk("Folder", { Name = "animations" }, assets)
local p1 = __mk("Folder", { Name = "player1" }, animsF)
local knifeAnim = __mk("Animation", { Name = "KnifeSwing", AnimationId = "rbxassetid://222" }, p1)
__mk("Animation", { Name = "Wounded Crawling", AnimationId = "rbxassetid://111" }, p1)
local phase = __mk("StringValue", { Name = "gamePhase", Value = "Night" }, RS)
__mk("Tool", { Name = "Glock" }, RS)
RS:SetAttribute("roundId", 7)

local map = __mk("Folder", { Name = "Map" }, workspace)
local doors = __mk("Folder", { Name = "Doors" }, map)
local door1 = __mk("Model", { Name = "Door1" }, doors)
door1:SetAttribute("Locked", false)
local handle = __mk("Part", { Name = "Handle" }, door1)
local prompt = __mk("ProximityPrompt", { Name = "ProximityPrompt", ActionText = "Lock", ObjectText = "Door", HoldDuration = 0.45, MaxActivationDistance = 8, Enabled = true }, handle)

local pg = __mk("PlayerGui", { Name = "PlayerGui" }, me)
local hud = __mk("ScreenGui", { Name = "HUD", Enabled = true }, pg)
__mk("TextLabel", { Name = "RoleLabel", Text = "You are the <b>MAFIA</b>", Visible = true }, hud)
__mk("TextLabel", { Name = "Hidden", Text = "SECRET_TEXT", Visible = false }, hud)
local hiddenFrame = __mk("Frame", { Name = "HiddenFrame", Visible = false }, hud)
__mk("TextLabel", { Name = "Inner", Text = "INNER_HIDDEN" }, hiddenFrame)
local offGui = __mk("ScreenGui", { Name = "OffGui", Enabled = false }, pg)
__mk("TextLabel", { Name = "X", Text = "DISABLED_GUI_TEXT" }, offGui)

local tcs = game:GetService("TextChatService")
tcs.ChatVersion = "TextChatService"
local chans = __mk("Folder", { Name = "TextChannels" }, tcs)
__mk("TextChannel", { Name = "RBXGeneral" }, chans)

alice.Character:SetAttribute("DisguiseName", "Bob")
CS:AddTag(alice.Character, "Downed")
local bb = __mk("BillboardGui", { Name = "RoleTag", Enabled = true }, alice.Character:FindFirstChild("Head"))
__mk("TextLabel", { Name = "L", Text = "EVIL TEAM" }, bb)

getgc = function()
    return { { role = "Mafia", owner = "Alice" }, { Team = "EVIL" }, { foo = 1 }, { [alice] = "Doctor" }, function() end, "str" }
end
getconnections = function()
    return { { Function = function(input, gp) end, Enabled = true }, { ForeignState = true } }
end

----------------------------------------------------------------------
-- Snapshot #1
----------------------------------------------------------------------
local ok, n = I.snapshot()
check(ok == true and type(n) == "number" and n > 80, "snapshot ok: " .. tostring(n))
local t = I.text()
for i, title in ipairs({ "EXECUTOR", "GAME", "TREE", "MODULE PROBE", "REMOTES", "ANIMATIONS", "TOOLS", "PLAYERS", "GLOBAL STATE", "PLAYERGUI", "WORKSPACE OVERVIEW", "TEXTCHATSERVICE", "GETGC PROBE", "GETCONNECTIONS PROBE" }) do
    check(has(t, "==== [" .. i .. "] " .. title), "section header " .. i .. " " .. title)
end
check(not has(t, "] ERROR:"), "no section errors in snapshot #1")
-- executor
check(has(t, "executor: MockExec 9.9"), "identifyexecutor")
check(string.find(t, "getgc:%s+yes") ~= nil, "cap getgc yes")
check(string.find(t, "hookmetamethod:%s+no") ~= nil, "cap hookmetamethod no")
check(string.find(t, "Drawing:%s+no") ~= nil, "cap Drawing no")
check(string.find(t, "debug%.info:%s+yes") ~= nil, "cap debug.info yes")
check(has(t, "thread identity: 8"), "thread identity value")
check(has(t, "require test module: ReplicatedStorage.shared.configurations.gameConfig"), "require test picks gameConfig")
check(has(t, "require @current identity: ok (table"), "require at current identity")
check(has(t, "require @identity 2: ok (table"), "require at identity 2")
check(has(t, "same result object: true"), "same object compare")
check(reqLog[1] and reqLog[1][2] == 8 and reqLog[2] and reqLog[2][2] == 2, "require identities 8 then 2")
check(identity == 8, "identity restored after identity-2 require: " .. tostring(identity))
-- game
check(has(t, "PlaceId: 123") and has(t, "place name: MAFIA [V2.3] - ACT II"), "game section")
-- tree
check(has(t, "  Props [Folder]") and has(t, "P15 [Part]"), "tree shows first 15")
check(not has(t, "P16 [Part]"), "tree hides children past 15")
check(has(t, "... (+35 more, classes: MeshPart x20, Part x15)"), "tree collapse summary")
check(has(t, 'gamePhase [StringValue] = "Night"'), "tree value")
check(has(t, "roundId=7"), "tree/global attrs")
check(has(t, "LocalPlayer.PlayerScripts [PlayerScripts]"), "tree PlayerScripts root")
-- modules
check(has(t, "WARNING: requiring game modules"), "module side-effect warning")
check(has(t, "shared.configurations.roles -> ReplicatedStorage.shared.configurations.roles [ModuleScript]"), "module resolved")
check(has(t, 'team = "EVIL"'), "module table serialized")
check(has(t, "deepest = {1 keys}"), "module depth cap 3")
check(has(t, "roles keys @shared.configurations.roles: Doctor, Mafia"), "roles module keys")
check(has(t, "roles keys @shared.configurations.gameConfig.roles: Saboteur, Witch"), "roles sub-table keys")
check(has(t, "client.controllers.roleController -> Me.PlayerScripts.client.controllers.roleController"), "controller resolved in PlayerScripts")
check(has(t, 'currentRole = "Mafia"'), "controller fields")
check(has(t, "handleMafiaStab = function(1, vararg)"), "function signature via debug.info")
check(has(t, "require@2: ok (table, 2 keys, metatable)"), "metatable presence")
check(has(t, "client.controllers.brokenController ->") and has(t, "require@2: error:") and has(t, "exploded"), "discovered failing controller")
check(has(t, "shared.configurations.votingConfig ->") and has(t, "voteTime = 30"), "discovered config child")
check(has(t, "client.modules.topbarBus -> not found"), "missing module")
check(has(t, "assets.animations.player1 -> ReplicatedStorage.assets.animations.player1 [Folder]") and has(t, "not a ModuleScript"), "non-module path")
-- remotes / anims / tools
check(has(t, "RemoteEvent ReplicatedStorage.Remotes.RoleReveal") and has(t, "RemoteFunction ReplicatedStorage.Remotes.GetData"), "remotes listed")
check(has(t, "KnifeSwing | rbxassetid://222 | ReplicatedStorage.assets.animations.player1.KnifeSwing"), "animation line")
check(has(t, "[ReplicatedStorage] ReplicatedStorage.Glock"), "tool in RS")
check(has(t, "[Alice.Character] Alice.Steel Knife"), "tool on character")
check(has(t, "[LocalPlayer.Backpack] Me.Backpack.Knife"), "tool in local backpack")
-- players
check(has(t, "-- Me ") and has(t, "(YOU)"), "local player marked")
check(has(t, 'Character attrs: DisguiseName="Bob"'), "character attrs")
check(has(t, 'Player attrs: Role="Doctor"'), "player attrs")
check(has(t, 'StringValue Role = "Civilian"'), "player value children")
check(has(t, "BillboardGui RoleTag") and has(t, '"EVIL TEAM"'), "billboard texts")
check(has(t, "Tags player: (none) | character: Downed"), "character tags")
-- global
check(has(t, 'value ReplicatedStorage.gamePhase [StringValue] = "Night"'), "RS value objects")
check(has(t, "tag Downed x1: Alice [Alice]"), "tag counts with owner")
-- playergui
check(has(t, 'Me.PlayerGui.HUD.RoleLabel: "You are the MAFIA"'), "visible text stripped of rich text")
check(not has(t, "SECRET_TEXT") and not has(t, "INNER_HIDDEN") and not has(t, "DISABLED_GUI_TEXT"), "hidden texts skipped")
check(has(t, "gui HUD [ScreenGui] Enabled=true"), "screen gui list")
-- workspace
check(has(t, "Workspace.Map.Doors [Folder] match=door"), "map container found")
check(has(t, "sample 1: Door1 [Model] attrs: Locked=false"), "container sample attrs")
check(has(t, 'prompt ActionText="Lock" ObjectText="Door" hold=0.45 dist=8'), "prompt details")
check(has(t, "attr Locked x1"), "workspace attribute summary")
-- chat / gc / connections
check(has(t, "ChatVersion: TextChatService") and has(t, "channel RBXGeneral [TextChannel]"), "text chat section")
check(has(t, 'keys[role] {') and has(t, 'role="Mafia"'), "getgc key hit")
check(has(t, 'keys[Team] {Team="EVIL"}'), "getgc Team hit")
check(has(t, 'P1 keyed by Player(Alice): {[Player(Alice)]="Doctor"}'), "getgc player-keyed table")
check(not has(t, "foo=1"), "getgc ignores unrelated tables")
check(has(t, "UserInputService.InputBegan: 2 connections") and has(t, "[foreign]") and has(t, "(no Lua function)"), "getconnections listing")
check(has(t, "OnClientEvent ReplicatedStorage.Remotes.RoleReveal: 2 connections"), "remote connections")

-- busy guard
St.busy = true
local okB, msgB = I.snapshot()
check(okB == false and msgB == "busy", "snapshot busy guard")
St.busy = false

-- Snapshot #2: section gagal tidak boleh menghentikan section lain
getgc = function()
    error("gc boom")
end
local ok2 = I.snapshot()
check(ok2 == true, "snapshot #2 ok despite failing section")
t = I.text()
local s2 = string.find(t, "######## SNAPSHOT #2", 1, true)
check(s2 ~= nil, "snapshot #2 present")
local errAt = s2 and string.find(t, "[getgc] ERROR:", s2, true)
local nextAt = errAt and string.find(t, "==== [14] GETCONNECTIONS PROBE ====", errAt, true)
check(errAt ~= nil and has(t, "gc boom"), "section error written")
check(nextAt ~= nil, "section after the failing one still ran")
getgc = nil

----------------------------------------------------------------------
-- Live log
----------------------------------------------------------------------
local T = 1000
I._test.setClock(function()
    return T
end)
__SignalNames.Seated = true
__SignalNames.PromptButtonHoldBegan = true
local ncMethod, isCaller, hooked, hookCount = nil, false, nil, 0
getnamecallmethod = function()
    return ncMethod
end
checkcaller = function()
    return isCaller
end
newcclosure = function(f)
    return f
end
hookmetamethod = function(obj, mm, fn)
    hookCount = hookCount + 1
    hooked = fn
    return function(self, ...)
        return "orig:" .. tostring(ncMethod)
    end
end
getcallingscript = function()
    return roleCtrl
end
local deferred = 0
task.defer = function(f, ...)
    deferred = deferred + 1
    f(...)
end

__SignalNames.HealthChanged = true
-- Animate bawaan Bob: slot standar "walk" = default, slot custom "crawl" tetap dianggap penting
local animate = __mk("LocalScript", { Name = "Animate" }, bob.Character)
local walkAnim = __mk("Animation", { Name = "WalkAnim", AnimationId = "rbxassetid://333" }, __mk("StringValue", { Name = "walk" }, animate))
local crawlAnim = __mk("Animation", { Name = "CrawlAnim", AnimationId = "rbxassetid://444" }, __mk("StringValue", { Name = "crawl" }, animate))

local okL = I.startLive()
check(okL == true and St.live == true, "startLive")
check(I._test.buttons().live.Text == "Stop live log", "API startLive refreshes the UI at once")
check(hookCount == 1 and type(hooked) == "function", "namecall hook installed once")
check(getgenv().NoctisENIX_InspectorHook and getgenv().NoctisENIX_InspectorHook.installed == true, "hook state stored in genv")
check(St.outStatus == "on", "remote out status on")

-- ATTR
me.Character:SetAttribute("Downed", true)
cara:SetAttribute("Role", "Mafia")
-- ANIM (+ dedupe)
local aliceAnimator = alice.Character:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
local tr = aliceAnimator:LoadAnimation(knifeAnim)
tr:Play()
tr:Play()
T = T + 2
tr:Play()
local bobAnimator = bob.Character:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
local walkTr = bobAnimator:LoadAnimation(walkAnim)
walkTr:Play()
T = T + 2
walkTr:Play()
bobAnimator:LoadAnimation(crawlAnim):Play()
-- HUM health: regen kecil diabaikan
local eveHum = eve.Character:FindFirstChildOfClass("Humanoid")
eveHum.HealthChanged:Fire(99)
eveHum.HealthChanged:Fire(80)
eveHum.HealthChanged:Fire(81)
eveHum.HealthChanged:Fire(0)
eveHum.HealthChanged:Fire(100)
-- CHAT
tcs.MessageReceived:Fire({ Text = "The Harbinger thinks <b>Bob</b> is a Mafia.", PrefixText = "", TextSource = nil })
tcs.MessageReceived:Fire({ Text = "hello", PrefixText = "Alice:", TextSource = { UserId = 2, Name = "2" } })
-- REMOTE IN
roleRemote.OnClientEvent:Fire("Mafia", { team = "EVIL", list = { 1, 2 } }, alice)
local late = __mk("RemoteEvent", { Name = "LateEvent" }, remotes)
RS.DescendantAdded:Fire(late)
late.OnClientEvent:Fire(42)
-- REMOTE OUT
ncMethod = "FireServer"
local r1 = hooked(stabRemote, "target", 5)
check(r1 == "orig:FireServer", "hook forwards to original")
isCaller = true
hooked(stabRemote, "FROM_EXECUTOR")
isCaller = false
ncMethod = "GetChildren"
hooked(stabRemote, "NOT_A_REMOTE_CALL")
ncMethod = "InvokeServer"
hooked(stabRemote, "INVOKE_ME")
check(deferred == 2, "remote-out logging runs via task.defer: " .. deferred)
-- tanpa task.defer: tetap forward, tidak log (task.spawn akan merusak namecall method)
local savedDefer = task.defer
task.defer = nil
ncMethod = "FireServer"
check(hooked(stabRemote, "NO_DEFER") == "orig:FireServer", "hook forwards without task.defer")
task.defer = savedDefer
-- TAG
CS:AddTag(eve.Character, "Detained")
CS:AddTag(door1, "CustomTag")
-- TOOL
local tool = __mk("Tool", { Name = "Knife" }, bob.Character)
bob.Character.ChildAdded:Fire(tool)
bob.Character.ChildRemoved:Fire(tool)
-- PROMPT
local pps = game:GetService("ProximityPromptService")
pps.PromptTriggered:Fire(prompt, me)
pps.PromptButtonHoldBegan:Fire(prompt, me)
-- SPAWN
local banana = __mk("Part", { Name = "Banana", Position = Vector3.new(1, 2, 3) }, workspace)
workspace.DescendantAdded:Fire(banana)
workspace.DescendantAdded:Fire(__mk("Part", { Name = "Rock" }, workspace))
workspace.DescendantAdded:Fire(__mk("Sound", { Name = "KnifeSound" }, workspace))
-- SEAT
local seat = __mk("Seat", { Name = "MeetingSeat" }, workspace)
me.Character:FindFirstChildOfClass("Humanoid").Seated:Fire(true, seat)
-- PLAYER join + respawn
local zed = __mkPlayer("Zed", {})
game:GetService("Players").PlayerAdded:Fire(zed)
zed:SetAttribute("Role", "Witch")
local zchar = __mk("Model", { Name = "Zed" })
__mk("Humanoid", {}, zchar)
zed.Character = zchar
zed.CharacterAdded:Fire(zchar)
zchar:SetAttribute("Ragdolled", true)
-- VALUE
phase.Value = "Day"
phase:GetPropertyChangedSignal("Value"):Fire()
-- MAP
door1:SetAttribute("Locked", true)
local door2 = __mk("Model", { Name = "Door2" }, doors)
doors.ChildAdded:Fire(door2)
-- HUM WalkSpeed
local myHum = me.Character:FindFirstChildOfClass("Humanoid")
myHum.WalkSpeed = 4
myHum:GetPropertyChangedSignal("WalkSpeed"):Fire()

local L1 = liveSection(I.text())
check(has(L1, "LIVE started (session 1)"), "live start marker")
check(has(L1, "ATTR Me.Character Downed = true  (was nil)"), "ATTR character")
check(has(L1, 'ATTR Cara Role = "Mafia"  (was "Doctor")'), "ATTR player with old value")
check(count(L1, 'ANIM Alice "KnifeSwing" id=222 -> KnifeSwing') == 2, "ANIM resolved + deduped within 1s: " .. count(L1, "ANIM Alice"))
check(count(L1, 'ANIM Bob "WalkAnim" id=333') == 1 and has(L1, "[default]"), "default anim marked and throttled")
check(has(L1, 'ANIM Bob "CrawlAnim" id=444') and not string.find(L1, 'CrawlAnim[^\n]*%[default%]'), "custom Animate slot not treated as default")
check(count(L1, "HUM Eve Health =") == 3 and has(L1, "HUM Eve Health = 80 (was 100)") and has(L1, "HUM Eve Health = 0 (was 80)"), "health regen noise filtered: " .. count(L1, "HUM Eve Health ="))
check(has(L1, 'CHAT SYSTEM [?] prefix="" text="The Harbinger thinks Bob is a Mafia."') and has(L1, 'raw="The Harbinger thinks <b>Bob</b> is a Mafia."'), "CHAT system message")
check(has(L1, 'CHAT Alice [?] prefix="Alice:" text="hello"'), "CHAT player via UserId")
check(has(L1, 'REMOTE_IN ReplicatedStorage.Remotes.RoleReveal ("Mafia", {') and has(L1, 'team="EVIL"') and has(L1, "list={1, 2}") and has(L1, "Player(Alice))"), "REMOTE_IN serialized args")
check(has(L1, "REMOTE_IN ReplicatedStorage.Remotes.LateEvent (42)"), "REMOTE_IN for remote added later")
check(has(L1, 'REMOTE_OUT FireServer ReplicatedStorage.Remotes.Stab from Me.PlayerScripts.client.controllers.roleController ("target", 5)'), "REMOTE_OUT from game script")
check(has(L1, 'REMOTE_OUT InvokeServer ReplicatedStorage.Remotes.Stab') and has(L1, "INVOKE_ME"), "REMOTE_OUT invoke")
check(not has(L1, "FROM_EXECUTOR") and not has(L1, "NOT_A_REMOTE_CALL"), "REMOTE_OUT skips executor calls and other methods")
check(not has(L1, "NO_DEFER"), "REMOTE_OUT never logs synchronously")
check(has(L1, "TAG +Detained Eve [Eve]"), "TAG pre-hooked tag with owner")
check(not has(L1, "CustomTag"), "unknown tag not hooked before rescan")
check(has(L1, 'TOOL Bob equipped "Knife"') and has(L1, 'TOOL Bob unequipped "Knife"'), "TOOL equip/unequip")
check(has(L1, 'PROMPT PromptTriggered ActionText="Lock"') and has(L1, "by Me"), "PROMPT triggered")
check(has(L1, "PROMPT PromptButtonHoldBegan"), "PROMPT hold began")
check(has(L1, "SPAWN Banana [Part] at (1.0, 2.0, 3.0) in Workspace"), "SPAWN banana")
check(not has(L1, "SPAWN Rock") and not has(L1, "KnifeSound"), "SPAWN filters name and class")
check(has(L1, "SEAT seated=true seat=Workspace.MeetingSeat"), "SEAT")
check(has(L1, "PLAYER Zed joined") and has(L1, 'ATTR Zed Role = "Witch"'), "PLAYER join rehook")
check(has(L1, "PLAYER Zed spawned") and has(L1, "ATTR Zed.Character Ragdolled = true"), "CharacterAdded rehook")
check(has(L1, 'VALUE ReplicatedStorage.gamePhase = "Day"'), "VALUE change")
check(has(L1, "MAP Workspace.Map.Doors.Door1 Locked = true  (was false)"), "MAP door attribute")
check(has(L1, "MAP + Door2 [Model] in Workspace.Map.Doors"), "MAP child added")
check(has(L1, "HUM Me WalkSpeed = 4"), "HUM walkspeed")
local badLine = nil
for line in string.gmatch(L1, "[^\n]+") do
    if line ~= "==== LIVE LOG ====" and not string.match(line, "^%[%+%d+%.%d%ds%] [%u_]+ ") then
        badLine = line
        break
    end
end
check(badLine == nil, "every live line is '[+t.ttS] CATEGORY ...': " .. tostring(badLine))

-- GUI diff + tag rescan via Heartbeat
local RunService = game:GetService("RunService")
local phaseLbl = __mk("TextLabel", { Name = "Phase", Text = "Night 2", Visible = true }, hud)
__mk("TextLabel", { Name = "Ghost", Text = "INVISIBLE_NEW", Visible = false }, hud)
T = T + 11
RunService.Heartbeat:Fire(0.016)
CS:AddTag(handle, "CustomTag")
phaseLbl.Text = "Night 3"
T = T + 3
RunService.Heartbeat:Fire(0.016)
phaseLbl.Text = "Night 4"
T = T + 3
RunService.Heartbeat:Fire(0.016)
phaseLbl.Text = "Day 1"
T = T + 3
RunService.Heartbeat:Fire(0.016)
local L2 = liveSection(I.text())
check(has(L2, 'GUI Me.PlayerGui.HUD.Phase: "Night 2"'), "GUI new text")
check(has(L2, '"Night 3"') and not has(L2, '"Night 4"'), "GUI ticking digits throttled")
check(has(L2, 'GUI Me.PlayerGui.HUD.Phase: "Day 1"'), "GUI non-digit change logged")
check(not has(L2, "INVISIBLE_NEW") and count(L2, "RoleLabel") == 0, "GUI skips hidden + unchanged texts")
check(has(L2, "TAG +CustomTag Workspace.Map.Doors.Door1.Handle"), "TAG rescan hooks new tags")
check(string.find(I._test.gui():FindFirstChild("Main"):FindFirstChild("Status").Text, "Live: ON", 1, true) ~= nil, "status label updated by heartbeat")

-- Rate limit: 20 baris / 10 dtk per sumber, lalu 1 baris suppressed
for i = 1, 30 do
    eve.Character:SetAttribute("Spam", i)
end
local L3 = liveSection(I.text())
check(count(L3, "ATTR Eve.Character Spam =") == 20, "rate limit keeps 20: " .. count(L3, "ATTR Eve.Character Spam ="))
check(has(L3, "ATTR suppressed 10 lines from ATTR:Eve.Character:Spam"), "suppressed line")
T = T + 11
eve.Character:SetAttribute("Spam", 999)
local L4 = liveSection(I.text())
check(has(L4, "ATTR Eve.Character Spam = 999"), "new window logs again")
check(count(L4, "suppressed 10 lines") == 1, "suppressed count written once")

-- stopLive
I.stopLive()
check(St.live == false and #St.liveConns == 0, "stopLive disconnects")
check(getgenv().NoctisENIX_InspectorHook.sink == nil, "hook sink cleared")
local before = I.lines()
me.Character:SetAttribute("AfterStop", 1)
roleRemote.OnClientEvent:Fire("after")
ncMethod = "FireServer"
check(hooked(stabRemote, "AFTER_STOP") == "orig:FireServer", "inert hook still forwards")
CS:AddTag(bob.Character, "Detained")
check(I.lines() == before, "no logging after stop")
check(has(liveSection(I.text()), "LIVE stopped"), "stop marker")

-- restart: rehook, hook tidak dipasang dua kali
I.startLive()
me.Character:SetAttribute("Again", 1)
check(has(liveSection(I.text()), "LIVE started (session 2)") and has(I.text(), "ATTR Me.Character Again = 1"), "restart rehooks")
check(hookCount == 1, "namecall hook not reinstalled")
-- getgc tidak boleh melaporkan tabel milik inspector sendiri (St.hk di-key pakai Player)
getgc = function()
    return { St.hk, St, St.tagHooked, { role = "Spy" } }
end
I.snapshot({ noRequire = true })
local tg = I.text()
local s3 = string.find(tg, "######## SNAPSHOT #3", 1, true)
check(s3 ~= nil and string.find(tg, "key hits: 1, player-keyed: 0", s3, true) ~= nil, "getgc skips inspector-owned tables")
check(has(liveSection(tg), "SNAPSHOT #3 taken"), "snapshot marker in live log")
getgc = nil
I.stopLive()

----------------------------------------------------------------------
-- Save
----------------------------------------------------------------------
local okS, info = I.save()
check(okS == true and type(info) == "string" and string.match(info, "^NoctisENIX/inspector_123_%d+%.txt %+ clipboard$") ~= nil, "save to file + clipboard: " .. tostring(info))
local path = info and string.match(info, "^(%S+)")
check(folders.NoctisENIX == true, "makefolder called")
check(path and files[path] ~= nil and files[path] == __clip, "file content == clipboard")
check(path and has(files[path], "NoctisENIX Inspector v1.0.0") and has(files[path], "executor: MockExec") and has(files[path], "==== LIVE LOG ===="), "saved text has header + live log")
check(St.lastSave == info, "status keeps last save")
check(St.savedMark == St.pushed + St.snapN, "save marks everything as saved")
check(has(I._test.gui():FindFirstChild("Main"):FindFirstChild("Status").Text, "Save: " .. info), "status label shows save path")
writefile = nil
local _, info2 = I.save()
check(info2 == "clipboard only", "clipboard only: " .. tostring(info2))
setclipboard = nil
toclipboard = nil
local realPrint = print
local chunks = {}
print = function(s)
    chunks[#chunks + 1] = s
end
local _, info3 = I.save()
print = realPrint
check(type(info3) == "string" and string.match(info3, "^console %(%d+ chunks%)$") ~= nil, "console fallback: " .. tostring(info3))
check(#chunks >= 2 and #chunks[1] == 3000 and string.sub(chunks[1], 1, 20) == "NoctisENIX Inspector", "console chunks of 3000")

-- Ring buffer: simpan 20000 terbaru
for i = 1, 20010 do
    I._test.push("RING", tostring(i))
end
check(St.count == 20000 and St.dropped > 0, "ring buffer capped at 20000")
local L5 = liveSection(I.text())
local first = string.match(L5, "==== LIVE LOG ====\n([^\n]*)")
check(first and string.match(first, " RING 11$") ~= nil, "oldest lines dropped first: " .. tostring(first))
check(string.match(L5, " RING 20010\n") ~= nil or string.match(L5, " RING 20010$") ~= nil, "newest kept")

----------------------------------------------------------------------
-- UI + unload
----------------------------------------------------------------------
local b = I._test.buttons()
check(b and b.live and b.live.Text == "Start live log", "live button idle text")
b.live.MouseButton1Click:Fire()
check(St.live == true and b.live.Text == "Stop live log", "live button starts")
b.live.MouseButton1Click:Fire()
check(St.live == false and b.live.Text == "Start live log", "live button stops")
local nBefore = St.snapN
b.snapshot.MouseButton1Click:Fire()
check(St.snapN == nBefore + 1, "snapshot button")
I.snapshot({ noRequire = true })
check(#St.snaps == 3 and not has(I.text(), "######## SNAPSHOT #1 "), "only 3 newest snapshots kept")
check(has(I.text(), "require: skipped (noRequire)"), "noRequire option")
b.close.MouseButton1Click:Fire()
check(St.alive == true and has(I._test.gui():FindFirstChild("Main"):FindFirstChild("Info").Text, "Click Close again"), "close asks for confirmation when unsaved")
b.close.MouseButton1Click:Fire()
check(St.alive == false, "second close unloads")
check(rawget(gui, "_destroyed") == true and gui.Parent == nil, "gui destroyed")
check(getgenv().NoctisENIX_Inspector == nil, "genv entry removed")
local okU, msgU = I.snapshot()
check(okU == false and msgU == "unloaded", "snapshot after unload refused")
check(I.startLive() == false, "startLive after unload refused")
b.live.MouseButton1Click:Fire()
check(St.live == false, "ui connections disconnected")
RunService.Heartbeat:Fire(0.016)
local okU2 = I.unload()
check(okU2 == true, "unload idempotent")
check(#St.errs == 0, "no inspector errors: " .. table.concat(St.errs, " | "))

if #fails == 0 then
    print("PASS inspector (" .. passes .. " checks)")
else
    for _, f in ipairs(fails) do
        print("FAIL " .. f)
    end
    print("passed " .. passes .. ", failed " .. #fails)
end
