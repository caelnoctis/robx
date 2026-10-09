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
-- cloneref: container hasil gethui() tidak == Parent kanonik yang dibaca balik, tapi parenting berhasil
do
    local realHui = __mk("Folder", { Name = "HiddenUI" })
    local cloneHui = __mk("Folder", { Name = "HiddenUI" })
    gethui = function()
        return cloneHui
    end
    local fakeGui = setmetatable({}, {
        __index = function(s, k)
            if k == "Parent" then
                return rawget(s, "_p")
            end
        end,
        __newindex = function(s, k, v)
            if k == "Parent" then
                rawset(s, "_p", (v == cloneHui) and realHui or v)
            end
        end,
    })
    local where = I._test.mount(fakeGui)
    check(where == cloneHui and rawget(fakeGui, "_p") == realHui, "mount keeps cloneref'd gethui container (no fallthrough to PlayerGui)")
    gethui = nil
end

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
local crawlRS = __mk("Animation", { Name = "Wounded Crawling", AnimationId = "rbxassetid://111" }, p1)
local runAnim = __mk("Animation", { Name = "RunCustom", AnimationId = "rbxassetid://555" }, p1)
-- animasi yang disimpan di dalam Tool (Backpack / StarterPack)
local aliceGlock = __mk("Tool", { Name = "Glock" }, alice:FindFirstChildOfClass("Backpack"))
__mk("Animation", { Name = "gunShot", AnimationId = "rbxassetid://777" }, __mk("Folder", { Name = "Animations" }, aliceGlock))
local medkitTool = __mk("Tool", { Name = "Medkit" }, game:GetService("StarterPack"))
__mk("Animation", { Name = "heal", AnimationId = "rbxassetid://888" }, medkitTool)
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
-- daftar hasil clone template: semua label punya full name yang sama
local voteList = __mk("Frame", { Name = "VoteList", Visible = true }, hud)
local function mkRow(n)
    local row = __mk("Frame", { Name = "Template", Visible = true }, voteList)
    return __mk("TextLabel", { Name = "PlayerName", Text = n, Visible = true }, row)
end
local rowLbls = { mkRow("Alice"), mkRow("Bob"), mkRow("Cara") }
local ROWKEY = "Me.PlayerGui.HUD.VoteList.Template.PlayerName"

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
-- v2.1: modul client TIDAK di-require (di Xeno itu menjalankan ulang kodenya dan merusak kontrol game)
check(not has(t, 'currentRole = "Mafia"'), "controller is never required (fields not dumped)")
check(has(t, "require: skipped (not a shared.configurations data module"), "controller require skipped with reason")
check(has(t, "client.controllers.brokenController ->") and not has(t, "exploded"), "broken controller not executed")
check(has(t, "shared.configurations.votingConfig ->") and has(t, "voteTime = 30"), "discovered config child")
check(has(t, "client.modules.topbarBus -> not found"), "missing module")
check(has(t, "assets.animations.player1 -> ReplicatedStorage.assets.animations.player1 [Folder]") and has(t, "not a ModuleScript"), "non-module path")
-- remotes / anims / tools
check(has(t, "RemoteEvent ReplicatedStorage.Remotes.RoleReveal") and has(t, "RemoteFunction ReplicatedStorage.Remotes.GetData"), "remotes listed")
check(has(t, "KnifeSwing | rbxassetid://222 | ReplicatedStorage.assets.animations.player1.KnifeSwing"), "animation line")
check(has(t, "[ReplicatedStorage] ReplicatedStorage.Glock"), "tool in RS")
check(has(t, "[Alice.Character] Alice.Steel Knife"), "tool on character")
check(has(t, "[LocalPlayer.Backpack] Me.Backpack.Knife"), "tool in local backpack")
check(has(t, "gunShot | rbxassetid://777 | Alice.Backpack.Glock.Animations.gunShot"), "animation inside a Backpack tool scanned")
check(has(t, "heal | rbxassetid://888 | StarterPack.Medkit.heal"), "animation inside a StarterPack tool scanned")
check(has(t, "[Alice.Backpack] Alice.Backpack.Glock") and has(t, "anims: gunShot=rbxassetid://777"), "TOOLS lists animation ids inside tools")
check(has(t, "require mode: identity 2 via setthreadidentity"), "module probe states require mode")
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
local gnmBoom, ccBoom = false, false
getnamecallmethod = function()
    if gnmBoom then
        error("gnm boom")
    end
    return ncMethod
end
checkcaller = function()
    if ccBoom then
        error("cc boom")
    end
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
-- Bob lagi downed waktu Start: game menaruh id crawl (juga ada di ReplicatedStorage) di slot idle
local walkSlot = animate:FindFirstChild("walk")
__mk("Animation", { Name = "IdleAnim", AnimationId = "rbxassetid://111" }, __mk("StringValue", { Name = "idle" }, animate))

local okL = I.startLive()
check(okL == true and St.live == true, "startLive")
check(St.defaultAnims["333"] == true and St.defaultAnims["111"] == nil, "Animate slot id that is also a game animation is not default")
check(not has(liveSection(I.text()), "initial:"), "no 'initial' attribute lines for instances present at start")
check(not has(liveSection(I.text()), "already tagged"), "no 'already tagged' lines at start")
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
-- crawl id juga ada di slot idle Bob: tetap dianggap animasi game (dedupe 1 dtk saja)
local caraAnimator = cara.Character:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
local caraCrawl = caraAnimator:LoadAnimation(crawlRS)
caraCrawl:Play()
T = T + 2
caraCrawl:Play()
-- set gerak custom (looped, prioritas Movement): sekali per 10 dtk per pemain+id
local runTr = aliceAnimator:LoadAnimation(runAnim)
runTr.Looped = true
runTr.Priority = Enum.AnimationPriority.Movement
runTr:Play()
T = T + 2
runTr:Play()
T = T + 2
runTr:Play()
T = T + 7
runTr:Play()
-- tool baru di Backpack + tool yang dipegang: id animasi di dalamnya ikut terpetakan
local bobBp = bob:FindFirstChildOfClass("Backpack")
local rev2 = __mk("Tool", { Name = "Revolver2" }, bobBp)
local shootAnim = __mk("Animation", { Name = "shoot", AnimationId = "rbxassetid://999" }, rev2)
bobBp.DescendantAdded:Fire(rev2)
bobBp.DescendantAdded:Fire(shootAnim)
local sword = __mk("Tool", { Name = "Sword" }, bob.Character)
__mk("Animation", { Name = "slash", AnimationId = "rbxassetid://1001" }, sword)
bob.Character.ChildAdded:Fire(sword)
bobAnimator:LoadAnimation(__mk("Animation", { Name = "Animation", AnimationId = "rbxassetid://999" })):Play()
bobAnimator:LoadAnimation(__mk("Animation", { Name = "Animation", AnimationId = "rbxassetid://1001" })):Play()
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
-- burst pengumuman sistem (vote) tidak boleh ke-suppress di 20 baris
for i = 1, 40 do
    tcs.MessageReceived:Fire({ Text = "Voter" .. i .. " voted for Bob", PrefixText = "", TextSource = nil })
end
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
-- getnamecallmethod / checkcaller error: hook tidak boleh melempar error ke game, tetap forward
ncMethod = "FireServer"
gnmBoom = true
local okGB, rGB = pcall(hooked, stabRemote, "GNM_BOOM")
gnmBoom = false
ccBoom = true
local okCB, rCB = pcall(hooked, stabRemote, "CC_BOOM")
ccBoom = false
check(okGB and rGB == "orig:FireServer", "hook survives getnamecallmethod error: " .. tostring(rGB))
check(okCB and rCB == "orig:FireServer", "hook survives checkcaller error: " .. tostring(rCB))
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
-- darah di dalam karakter korban dicatat (dengan pemilik); tool di karakter tidak (sudah TOOL)
workspace.DescendantAdded:Fire(__mk("Part", { Name = "BloodPuddle" }, alice.Character))
workspace.DescendantAdded:Fire(__mk("Tool", { Name = "Knife2" }, alice.Character))
-- SEAT
local seat = __mk("Seat", { Name = "MeetingSeat" }, workspace)
me.Character:FindFirstChildOfClass("Humanoid").Seated:Fire(true, seat)
-- PLAYER join + respawn
local zed = __mkPlayer("Zed", {})
game:GetService("Players").PlayerAdded:Fire(zed)
zed:SetAttribute("Role", "Witch")
local zchar = __mk("Model", { Name = "Zed" })
-- karakter baru dibangun server dengan state yang sudah terisi (tidak memicu AttributeChanged)
local zhum = __mk("Humanoid", {}, zchar)
zhum:SetAttribute("abilitiesEnabled", true)
zchar:SetAttribute("RoleTeam", "EVIL")
__mk("StringValue", { Name = "Disguise", Value = "Bob" }, zchar)
zed.Character = zchar
zed.CharacterAdded:Fire(zchar)
zchar:SetAttribute("Ragdolled", true)
-- HRP nyusul setelah CharacterAdded, sudah bawa attribute
local zhrp = __mk("Part", { Name = "HumanoidRootPart" })
zhrp:SetAttribute("Carried", false)
zhrp.Parent = zchar
zchar.ChildAdded:Fire(zhrp)
-- pemain join dengan attribute yang sudah ter-replikasi
local yan = __mkPlayer("Yan", { attr = { "Role", "Witch" } })
game:GetService("Players").PlayerAdded:Fire(yan)
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
-- default anim set / gerak custom
check(count(L1, 'ANIM Cara "Wounded Crawling" id=111 -> Wounded Crawling') == 2 and not string.find(L1, 'Wounded Crawling[^\n]*%[default%]'), "game crawl id in an Animate slot is not throttled as default")
check(count(L1, 'ANIM Alice "RunCustom" id=555') == 2 and has(L1, "looped=true prio=Movement"), "looped Movement track deduped per 10 s: " .. count(L1, 'ANIM Alice "RunCustom"'))
-- animasi tool
check(St.animNames["999"] == "shoot" and has(L1, 'ANIM Bob "Animation" id=999 -> shoot'), "Backpack tool animation resolved live")
check(St.animNames["1001"] == "slash" and has(L1, 'ANIM Bob "Animation" id=1001 -> slash'), "equipped tool animation resolved live")
check(St.animNames["777"] == "gunShot", "Backpack tool animation mapped at start")
-- namecall hook error
check(not has(L1, "GNM_BOOM") and not has(L1, "CC_BOOM"), "nothing logged when getnamecallmethod/checkcaller fail")
-- chat sistem
check(count(L1, 'CHAT SYSTEM [?] prefix="" text="Voter') == 40 and not has(L1, "suppressed") , "system chat burst not suppressed: " .. count(L1, 'text="Voter'))
-- SPAWN di karakter
check(has(L1, "SPAWN BloodPuddle [Part] at") and has(L1, "in Alice [Alice]"), "SPAWN logs matching part inside a character with owner")
check(not has(L1, "SPAWN Knife2"), "SPAWN skips tools inside characters")
-- state awal instance baru
check(has(L1, 'ATTR Zed.Character initial: RoleTeam="EVIL"'), "initial character attributes on CharacterAdded")
check(has(L1, "ATTR Zed.Humanoid initial: abilitiesEnabled=true"), "initial humanoid attributes on CharacterAdded")
check(has(L1, 'VALUE Zed.Character.Disguise = "Bob" (initial)'), "initial character value on CharacterAdded")
check(has(L1, "ATTR Zed.HRP initial: Carried=false"), "initial attributes of a part streamed in after CharacterAdded")
check(has(L1, "PLAYER Yan joined") and has(L1, 'ATTR Yan initial: Role="Witch"'), "initial player attributes on PlayerAdded")
check(not has(L1, "Alice.Character initial") and not has(L1, "Cara initial"), "no initial lines for players hooked at start")
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
check(has(L2, "TAG +CustomTag Workspace.Map.Doors.Door1 (already tagged when discovered)"), "TAG rescan logs instances tagged before the hook")
check(count(L2, ROWKEY) == 0, "GUI same-named template rows not re-logged every scan: " .. count(L2, ROWKEY))
-- satu baris berubah -> sekali; daftar dibangun ulang dengan teks sama -> tidak ada baris baru
rowLbls[2].Text = "Bob (DEAD)"
T = T + 3
RunService.Heartbeat:Fire(0.016)
T = T + 3
RunService.Heartbeat:Fire(0.016)
for _, c in ipairs(voteList:GetChildren()) do
    c:Destroy()
end
rowLbls = { mkRow("Cara"), mkRow("Alice"), mkRow("Bob (DEAD)") }
T = T + 3
RunService.Heartbeat:Fire(0.016)
-- hitungan vote per baris: tiap bentuk teks punya throttle sendiri
rowLbls[1].Text = "Cara 1"
T = T + 3
RunService.Heartbeat:Fire(0.016)
rowLbls[2].Text = "Alice 1"
rowLbls[1].Text = "Cara 2"
T = T + 3
RunService.Heartbeat:Fire(0.016)
local L2b = liveSection(I.text())
check(count(L2b, ROWKEY .. ': "Bob (DEAD)"') == 1, "GUI changed template row logged once: " .. count(L2b, ROWKEY .. ': "Bob (DEAD)"'))
check(count(L2b, ROWKEY .. ': "Alice"') == 0 and count(L2b, ROWKEY .. ': "Cara"') == 0, "GUI rebuilt list with same texts not re-logged")
check(has(L2b, ROWKEY .. ': "Alice 1"') and has(L2b, ROWKEY .. ': "Cara 1"') and has(L2b, ROWKEY .. ': "Cara 2"'), "GUI per-row count changes of different rows both logged")
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

-- restart: rehook, hook tidak dipasang dua kali.
-- getconnections per sinyal: LazyRole belum punya listener game -> jangan connect (antrean event Roblox)
local lazy = __mk("RemoteEvent", { Name = "LazyRole" }, remotes)
local listening = { [roleRemote.OnClientEvent] = true, [stabRemote.OnClientEvent] = true, [late.OnClientEvent] = true }
getconnections = function(sig)
    if listening[sig] then
        return { { Enabled = true } }
    end
    return {}
end
I.startLive()
me.Character:SetAttribute("Again", 1)
check(has(liveSection(I.text()), "LIVE started (session 2)") and has(I.text(), "ATTR Me.Character Again = 1"), "restart rehooks")
check(hookCount == 1, "namecall hook not reinstalled")
check(has(liveSection(I.text()), "1 waiting for a game listener"), "remote without game listener is deferred")
lazy.OnClientEvent:Fire("EARLY_EVENT")
roleRemote.OnClientEvent:Fire("S2_ROLE")
check(St.remoteWait[lazy] ~= nil and not has(I.text(), "EARLY_EVENT"), "deferred remote not connected yet")
check(has(I.text(), 'RoleReveal ("S2_ROLE")'), "remote with a game listener hooked at start")
listening[lazy.OnClientEvent] = true
T = T + 2.5
RunService.Heartbeat:Fire(0.016)
lazy.OnClientEvent:Fire("LAZY_AFTER")
check(St.remoteWait[lazy] == nil and has(I.text(), 'REMOTE_IN ReplicatedStorage.Remotes.LazyRole ("LAZY_AFTER")'), "deferred remote hooked once the game listens")
-- tanpa getconnections: remote baru ditunda REMOTE_GRACE (5 dtk)
getconnections = nil
local freshR = __mk("RemoteEvent", { Name = "FreshEvent" }, remotes)
RS.DescendantAdded:Fire(freshR)
freshR.OnClientEvent:Fire("FRESH_1")
T = T + 2.5
RunService.Heartbeat:Fire(0.016)
freshR.OnClientEvent:Fire("FRESH_2")
T = T + 3
RunService.Heartbeat:Fire(0.016)
freshR.OnClientEvent:Fire("FRESH_3")
local tR = I.text()
check(not has(tR, "FRESH_1") and not has(tR, "FRESH_2") and has(tR, 'REMOTE_IN ReplicatedStorage.Remotes.FreshEvent ("FRESH_3")'), "new remote hooked after the grace period")
-- getgc tidak boleh melaporkan tabel milik inspector sendiri (St.hk di-key pakai Player), salinan
-- GetAttributes ({Role="Doctor"}) dan himpunan teks GUI (berisi nama pemain)
local attrCopies = {}
local realGetAttributes = __Methods.GetAttributes
__Methods.GetAttributes = function(self)
    local a = realGetAttributes(self)
    attrCopies[#attrCopies + 1] = a
    return a
end
local guiSets = 0
getgc = function()
    local list = { St.hk, St, St.tagHooked, { role = "Spy" } }
    for _, a in ipairs(attrCopies) do
        list[#list + 1] = a
    end
    local gp = St.guiPrev
    if gp then
        list[#list + 1] = gp
        for _, set in pairs(gp) do
            guiSets = guiSets + 1
            list[#list + 1] = set
            list[#list + 1] = set.t
            list[#list + 1] = set.s
        end
    end
    return list
end
I.snapshot({ noRequire = true })
__Methods.GetAttributes = realGetAttributes
local roleCopies = 0
for _, a in ipairs(attrCopies) do
    if a.Role ~= nil then
        roleCopies = roleCopies + 1
    end
end
check(roleCopies > 0 and guiSets > 0, "getgc test sees attribute copies and GUI text sets: " .. roleCopies .. "/" .. guiSets)
local tg = I.text()
local s3 = string.find(tg, "######## SNAPSHOT #3", 1, true)
check(s3 ~= nil and string.find(tg, "key hits: 1, player-keyed: 0", s3, true) ~= nil, "getgc skips inspector-owned tables")
check(has(liveSection(tg), "SNAPSHOT #3 taken"), "snapshot marker in live log")
getgc = nil
I.stopLive()

-- hookmetamethod tanpa original + tanpa getrawmetatable: hook tetap meneruskan, logging mati
do
    local savedHMM = hookmetamethod
    local hooked2 = nil
    getgenv().NoctisENIX_InspectorHook = nil
    getrawmetatable = nil
    hookmetamethod = function(obj, mm, fn)
        hooked2 = fn
        return nil
    end
    I.startLive()
    check(type(hooked2) == "function" and string.find(tostring(St.outStatus), "^off %(hookmetamethod gave no original") ~= nil, "no-original hook reported off: " .. tostring(St.outStatus))
    check(getgenv().NoctisENIX_InspectorHook.sink == nil, "no-original hook has no sink")
    ncMethod = "GetChildren"
    local okP, kids = pcall(hooked2, remotes)
    check(okP and type(kids) == "table" and #kids >= 3, "no-original hook passes the call through via __index: " .. tostring(kids))
    gnmBoom = true
    local okP2 = pcall(hooked2, remotes)
    gnmBoom = false
    check(okP2, "no-original hook does not throw when getnamecallmethod fails")
    I.stopLive()
    -- original dari getrawmetatable (diambil sebelum hook) dipakai kalau hookmetamethod return nil
    getgenv().NoctisENIX_InspectorHook = nil
    getrawmetatable = function()
        return {
            __namecall = function(self, ...)
                return "raw:" .. tostring(ncMethod)
            end,
        }
    end
    I.startLive()
    check(St.outStatus == "on", "hook with getrawmetatable fallback is on: " .. tostring(St.outStatus))
    ncMethod = "FireServer"
    check(hooked2(stabRemote, "VIA_RAW") == "raw:FireServer", "hook forwards to the pre-captured original")
    check(has(liveSection(I.text()), "VIA_RAW"), "hook with fallback original logs FireServer")
    I.stopLive()
    hookmetamethod = savedHMM
    getrawmetatable = nil
end

-- tanpa setthreadidentity: label require jujur (bukan "require@2")
do
    local savedSet = setthreadidentity
    setthreadidentity = nil
    I.snapshot()
    local tq = I.text()
    local sq = string.find(tq, "######## SNAPSHOT #" .. St.snapN, 1, true)
    check(sq ~= nil and string.find(tq, "require@current (no setthreadidentity): ok", sq, true) ~= nil, "module probe labels current identity without setthreadidentity")
    check(sq ~= nil and string.find(tq, "require@2:", sq, true) == nil, "no require@2 label without setthreadidentity")
    check(sq ~= nil and string.find(tq, "require mode: current identity (no setthreadidentity)", sq, true) ~= nil, "require mode line without setthreadidentity")
    setthreadidentity = savedSet
end

-- Start berikutnya membangun ulang set default anim (slot walk Bob sudah hilang)
walkSlot:Destroy()
I.startLive()
check(St.defaultAnims["333"] == nil, "default anim set rebuilt at start")
I.stopLive()

----------------------------------------------------------------------
-- Save
----------------------------------------------------------------------
local okS, info = I.save()
check(okS == true and type(info) == "string" and string.match(info, "^NoctisENIX/inspector_123_%d+%.txt %+ clipboard$") ~= nil, "save to file + clipboard: " .. tostring(info))
local path = info and string.match(info, "^(%S+)")
check(folders.NoctisENIX == true, "makefolder called")
check(path and files[path] ~= nil and files[path] == __clip, "file content == clipboard")
check(I.version == "1.3.0", "inspector version 1.3.0: " .. tostring(I.version))
check(path and has(files[path], "NoctisENIX Inspector v" .. I.version) and has(files[path], "executor: MockExec") and has(files[path], "==== LIVE LOG ===="), "saved text has header + live log")
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
