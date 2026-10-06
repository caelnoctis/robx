-- Test Actions (deception + teleport tools). Jalan di atas prelude + ctx_mock.
local Players = ctx.Players
local Me = ctx.LocalPlayer
local RS = ctx.ReplicatedStorage
local CS = ctx.CollectionService
local RunService = ctx.RunService

local sectionFails = {}
local totalChecks, totalFails = 0, 0
local function check(cond, msg)
    totalChecks = totalChecks + 1
    if not cond then
        totalFails = totalFails + 1
        sectionFails[#sectionFails + 1] = msg
    end
end
local function section(name)
    if #sectionFails == 0 then
        print("PASS " .. name)
    else
        for _, m in ipairs(sectionFails) do
            print("FAIL " .. name .. ": " .. m)
        end
    end
    sectionFails = {}
end

for i, p in ipairs(__players) do
    p.UserId = 100 + i
end
local function P(name)
    for _, p in ipairs(__players) do
        if p.Name == name then
            return p
        end
    end
    return nil
end
local Alice, Bob, Cara, Dan, Eve, Frank = P("Alice"), P("Bob"), P("Cara"), P("Dan"), P("Eve"), P("Frank")

local function root(p)
    return p.Character:FindFirstChild("HumanoidRootPart")
end
local function hum(p)
    return p.Character:FindFirstChildOfClass("Humanoid")
end
local function pos(p)
    return root(p).CFrame.Position
end
local function v3(x, y, z)
    return Vector3.new(x, y, z)
end
local function near(a, b, tol)
    return (a - b).Magnitude <= (tol or 0.01)
end
local function fmt(v)
    if v == nil then
        return "nil"
    end
    return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end
local function setPos(p, x, y, z)
    root(p).CFrame = CFrame.new(x, y, z)
end
local function clearDelays()
    for i = #__delays, 1, -1 do
        __delays[i] = nil
    end
end
local function runDelays()
    local list = {}
    for i, f in ipairs(__delays) do
        list[i] = f
    end
    clearDelays()
    for _, f in ipairs(list) do
        f()
    end
end
local function noteHas(text)
    for _, n in ipairs(__notes) do
        if string.find(n, text, 1, true) then
            return true
        end
    end
    return false
end
local function newChar(p, x)
    local tmp = __buildPlayer(p.Name, { x = x or 0 })
    local c = tmp.Character
    __mk("Animator", nil, c:FindFirstChildOfClass("Humanoid"))
    local r = c:FindFirstChild("HumanoidRootPart")
    r.CFrame = CFrame.new(r.Position)
    p.Character = c
    return c
end

-- Waktu dikontrol test
local T = 1000
-- Game.require diganti stub: path -> tabel
local modules = {}
ctx.Game.require = function(path)
    return modules[path]
end

local A = ActionsFactory(ctx)
A._test.setClock(function()
    return T
end)
local St = A._test.state()

-- Ekstensi mock: log UnequipTools
local unequipCalls = 0
__Methods.UnequipTools = function()
    unequipCalls = unequipCalls + 1
end

---------------------------------------------------------------------------
-- 1. livingPlayers
---------------------------------------------------------------------------
do
    local list = A.livingPlayers()
    local names = {}
    for _, p in ipairs(list) do
        names[#names + 1] = p.Name
    end
    check(table.concat(names, ",") == "Alice,Bob,Cara,Dan,Eve", "living sorted/filtered: " .. table.concat(names, ","))
    Eve:SetAttribute("Dead", true)
    names = {}
    for _, p in ipairs(A.livingPlayers()) do
        names[#names + 1] = p.Name
    end
    check(table.concat(names, ",") == "Alice,Bob,Cara,Dan", "Dead flag excluded: " .. table.concat(names, ","))
    Eve:SetAttribute("Dead", nil)
    Dan.DisplayName = "aaron"
    local first = A.livingPlayers()[1]
    check(first == Dan, "sort is by DisplayName, case-insensitive")
    Dan.DisplayName = "DanD"
end
section("livingPlayers")

---------------------------------------------------------------------------
-- 2. target
---------------------------------------------------------------------------
do
    local ok, msg = A.setTarget(Me)
    check(ok == false and msg == "You cannot target yourself.", "self target refused: " .. tostring(msg))
    ok = A.setTarget(Frank)
    check(ok == false, "dead target refused")
    ok = A.setTarget("Alice")
    check(ok == false, "non-player refused")
    ok, msg = A.setTarget(Alice)
    check(ok == true and A.getTarget() == Alice, "set Alice")
    check(msg == "Target: AliceD", "target msg: " .. tostring(msg))
    check(A.status().target == Alice, "status.target")
    hum(Alice).Health = 0
    check(A.getTarget() == nil, "auto-clear when target dies")
    hum(Alice).Health = 100
    check(A.getTarget() == nil, "stays cleared after revive")
    A.setTarget(Bob)
    Players.PlayerRemoving:Fire(Bob)
    check(A.getTarget() == nil, "auto-clear when target leaves")
    A.setTarget(Bob)
    ok, msg = A.setTarget(nil)
    check(ok == true and A.getTarget() == nil and msg == "Target cleared.", "clear target")
end
section("target")

---------------------------------------------------------------------------
-- 3. teleports
---------------------------------------------------------------------------
do
    setPos(Me, 0, 0, 0)
    local ok, msg = A.toTarget()
    check(ok == false and msg == "Pick a living player in Target first.", "toTarget without target: " .. tostring(msg))

    A.setTarget(Bob)
    root(Me).AssemblyLinearVelocity = v3(5, 5, 5)
    ok, msg = A.toTarget()
    check(ok == true, "toTarget ok: " .. tostring(msg))
    check(near(pos(Me), v3(25, 0, 3)), "3 studs behind Bob: " .. fmt(pos(Me)))
    check(near(root(Me).CFrame.LookVector, v3(0, 0, -1)), "facing Bob: " .. fmt(root(Me).CFrame.LookVector))
    check(near(root(Me).AssemblyLinearVelocity, v3(0, 0, 0)), "velocity zeroed")

    -- PivotTo dipakai kalau PrimaryPart = root
    local pivoted = 0
    local oldPivot = __Methods.PivotTo
    __Methods.PivotTo = function(self, cf)
        pivoted = pivoted + 1
        local r = self:FindFirstChild("HumanoidRootPart")
        if r then
            r.CFrame = cf
        end
    end
    Me.Character.PrimaryPart = root(Me)
    setPos(Me, 0, 0, 0)
    ok = A.toTarget()
    check(ok and pivoted == 1 and near(pos(Me), v3(25, 0, 3)), "PivotTo used when PrimaryPart is root")
    Me.Character.PrimaryPart = nil
    __Methods.PivotTo = oldPivot

    -- duduk
    setPos(Me, 0, 0, 0)
    hum(Me).SeatPart = __mk("Seat")
    ok, msg = A.toTarget()
    check(ok == false and msg == "Get out of your seat first.", "seated refused: " .. tostring(msg))
    check(near(pos(Me), v3(0, 0, 0)), "seated: not moved")
    hum(Me).SeatPart = nil

    -- tanpa karakter
    local char = Me.Character
    Me.Character = nil
    ok, msg = A.toTarget()
    check(ok == false and msg == "You have no living character to move.", "no character: " .. tostring(msg))
    Me.Character = char

    -- downed / detained
    ok, msg = A.toDowned()
    check(ok == false and msg == "Nobody is downed right now.", "nobody downed: " .. tostring(msg))
    ok, msg = A.toDetained()
    check(ok == false and msg == "Nobody is detained right now.", "nobody detained: " .. tostring(msg))
    Frank.Character:SetAttribute("Downed", true)
    ok = A.toDowned()
    check(ok == false, "dead downed player ignored")
    Cara.Character:SetAttribute("Downed", true)
    Eve.Character:SetAttribute("Downed", true)
    setPos(Me, 60, 0, 0)
    ok, msg = A.toDowned()
    check(ok == true and near(pos(Me), v3(55, 0, 3)), "nearest downed (Eve): " .. fmt(pos(Me)) .. " " .. tostring(msg))
    setPos(Me, 30, 0, 0)
    A.toDowned()
    check(near(pos(Me), v3(35, 0, 3)), "nearest downed (Cara): " .. fmt(pos(Me)))
    Cara.Character:SetAttribute("Downed", nil)
    Eve.Character:SetAttribute("Downed", nil)
    Frank.Character:SetAttribute("Downed", nil)
    CS:AddTag(Dan.Character, "Detained")
    ok, msg = A.toDetained()
    check(ok == true and near(pos(Me), v3(45, 0, 3)), "detained via tag (Dan): " .. fmt(pos(Me)))
    check(msg == "Teleported to DanD.", "teleport msg: " .. tostring(msg))
    CS:RemoveTag(Dan.Character, "Detained")
    setPos(Me, 0, 0, 0)
    A.setTarget(nil)
end
section("teleports")

---------------------------------------------------------------------------
-- 4. fake crawl
---------------------------------------------------------------------------
local animFolder
do
    local assets = __mk("Folder", { Name = "assets" }, RS)
    local anims = __mk("Folder", { Name = "animations" }, assets)
    animFolder = __mk("Folder", { Name = "player1" }, anims)
end
local function addAnim(name, id)
    __mk("Animation", { Name = name, AnimationId = "rbxassetid://" .. id }, animFolder)
    ctx.Game.scanAnimations(true)
end

do
    local h = hum(Me)
    local ok, msg = A.setFakeCrawl(true)
    check(ok == false and msg == "Crawl animation not found in this game version.", "missing anim: " .. tostring(msg))
    check(h.WalkSpeed == 16 and not A.status().fakeCrawl, "missing anim: speed untouched")

    addAnim("Wounded Crawling", 111)

    Me.Character:SetAttribute("Downed", true)
    ok, msg = A.setFakeCrawl(true)
    check(ok == false and msg == "You are actually wounded right now, so nobody would see a difference.", "refuse when downed: " .. tostring(msg))
    Me.Character:SetAttribute("Downed", nil)

    -- tanpa Wounded Idle: pose crawl dibekukan saat diam
    ok, msg = A.setFakeCrawl(true)
    check(ok == true and A.status().fakeCrawl, "crawl on (no idle anim): " .. tostring(msg))
    check(St.Crawl.idle == nil, "idle anim must not fall back to the crawl anim")
    local c = St.Crawl.crawl
    check(c and c.IsPlaying and c.Speed == 0, "frozen crawl pose while still")
    check(c and c.Looped == true and c.Priority == Enum.AnimationPriority.Action, "crawl track looped + Action priority")
    h.MoveDirection = v3(1, 0, 0)
    RunService.Heartbeat:Fire(0.016)
    check(c.IsPlaying and c.Speed == 1, "crawl animates while moving")
    h.MoveDirection = v3(0, 0, 0)
    A.setFakeCrawl(false)
    check(not c.IsPlaying and h.WalkSpeed == 16, "off restores (no idle)")

    addAnim("Wounded Idle", 112)
    ok, msg = A.setFakeCrawl(true)
    check(ok == true and msg == "Everyone sees you crawling wounded.", "crawl on: " .. tostring(msg))
    c = St.Crawl.crawl
    local i = St.Crawl.idle
    check(i ~= nil and i.Animation.Name == "Wounded Idle", "idle track loaded")
    check(h.WalkSpeed == 4, "crawl speed applied: " .. tostring(h.WalkSpeed))
    check(i.IsPlaying and not c.IsPlaying, "idle plays while still")

    h.MoveDirection = v3(1, 0, 0)
    RunService.Heartbeat:Fire(0.016)
    check(c.IsPlaying and not i.IsPlaying, "crawl plays while moving")
    h.MoveDirection = v3(0.01, 0, 0)
    RunService.Heartbeat:Fire(0.05)
    check(c.IsPlaying, "hysteresis: brief stop keeps crawl")
    RunService.Heartbeat:Fire(0.1)
    check(i.IsPlaying and not c.IsPlaying, "idle after standing still long enough")
    h.MoveDirection = v3(0.03, 0, 0)
    RunService.Heartbeat:Fire(0.5)
    check(i.IsPlaying, "dead zone between thresholds keeps current mode")

    h.WalkSpeed = 10
    RunService.Heartbeat:Fire(0.016)
    check(h.WalkSpeed == 4, "speed re-applied each Heartbeat")

    -- speed hack script utama nulis WalkSpeed di Heartbeat juga: Stepped (tepat sebelum physics) menang
    h.WalkSpeed = 22
    RunService.Stepped:Fire(0, 0.016)
    check(h.WalkSpeed == 4, "crawl speed re-applied in Stepped before physics: " .. tostring(h.WalkSpeed))

    -- track kita di-Stop dari luar (Animate / equip tool / ganti state) -> diputar lagi dalam 0.25 s
    i:Stop()
    RunService.Heartbeat:Fire(0.3)
    check(i.IsPlaying and St.Crawl.mode == "idle", "idle track restarted after an external Stop")
    h.MoveDirection = v3(1, 0, 0)
    RunService.Heartbeat:Fire(0.016)
    c:Stop()
    RunService.Heartbeat:Fire(0.016)
    check(not c.IsPlaying, "restart only on the 0.25 s check, not every frame")
    RunService.Heartbeat:Fire(0.3)
    check(c.IsPlaying and St.Crawl.mode == "move", "crawl track restarted after an external Stop")
    h.MoveDirection = v3(0, 0, 0)
    RunService.Heartbeat:Fire(0.016)
    RunService.Heartbeat:Fire(0.2)
    check(i.IsPlaying and not c.IsPlaying, "back to idle")

    -- beneran downed di tengah fake crawl -> pause, game yang atur
    Me.Character:SetAttribute("Downed", true)
    RunService.Heartbeat:Fire(0.3)
    check(not i.IsPlaying and not c.IsPlaying, "paused while really downed")
    h.WalkSpeed = 3
    RunService.Heartbeat:Fire(0.3)
    check(h.WalkSpeed == 3, "no speed forcing while really downed")
    Me.Character:SetAttribute("Downed", nil)
    RunService.Heartbeat:Fire(0.3)
    check(i.IsPlaying and h.WalkSpeed == 4, "resumes after real downed clears")

    ok, msg = A.setFakeCrawl(false)
    check(ok and msg == "Fake crawl off.", "off msg")
    check(not i.IsPlaying and not c.IsPlaying, "tracks stopped on off")
    check(h.WalkSpeed == 16, "WalkSpeed restored: " .. tostring(h.WalkSpeed))
    RunService.Heartbeat:Fire(0.016)
    check(h.WalkSpeed == 16, "no Heartbeat work after off")

    -- crawlKeepSpeed dinyalakan DI TENGAH crawl -> speed normal langsung balik
    A.setFakeCrawl(true)
    RunService.Heartbeat:Fire(0.016)
    check(h.WalkSpeed == 4, "crawl speed before the keepSpeed toggle")
    ctx.S.crawlKeepSpeed = true
    RunService.Heartbeat:Fire(0.016)
    check(h.WalkSpeed == 16, "crawlKeepSpeed turned on mid-crawl restores speed: " .. tostring(h.WalkSpeed))
    RunService.Stepped:Fire(0, 0.016)
    check(h.WalkSpeed == 16, "Stepped does not force speed under crawlKeepSpeed")
    ctx.S.crawlKeepSpeed = nil
    RunService.Heartbeat:Fire(0.016)
    check(h.WalkSpeed == 4, "crawl speed again once crawlKeepSpeed is off")
    A.setFakeCrawl(false)
    check(h.WalkSpeed == 16, "restored after the keepSpeed round trip")

    -- crawlKeepSpeed
    ctx.S.crawlKeepSpeed = true
    A.setFakeCrawl(true)
    RunService.Heartbeat:Fire(0.016)
    check(h.WalkSpeed == 16, "crawlKeepSpeed keeps speed")
    A.setFakeCrawl(false)
    check(h.WalkSpeed == 16, "crawlKeepSpeed off: untouched")
    ctx.S.crawlKeepSpeed = nil

    -- kecepatan dari gameConfig
    modules["shared.configurations.gameConfig"] = { movement = { CrawlSpeed = 6 } }
    A.setFakeCrawl(true)
    check(h.WalkSpeed == 6, "crawl speed from gameConfig: " .. tostring(h.WalkSpeed))
    -- game ganti speed sendiri -> jangan ditimpa saat restore
    A.setFakeCrawl(false)
    check(h.WalkSpeed == 16, "restore after config speed")
    modules["shared.configurations.gameConfig"] = nil

    -- respawn saat crawl aktif
    A.setFakeCrawl(true)
    local oldChar = Me.Character
    local nc = newChar(Me, 0)
    Me.CharacterAdded:Fire(nc)
    local nh = nc:FindFirstChildOfClass("Humanoid")
    RunService.Heartbeat:Fire(0.016)
    check(St.Crawl.hum == nh, "rebound to new humanoid")
    check(St.Crawl.idle and St.Crawl.idle.IsPlaying, "idle playing on new character")
    check(nh.WalkSpeed == 4, "crawl speed on new humanoid")
    A.setFakeCrawl(false)
    check(nh.WalkSpeed == 16, "new humanoid speed restored")
    Me.Character = oldChar

    -- tanpa Animator
    local animator = h:FindFirstChildOfClass("Animator")
    animator.Parent = nil
    ok, msg = A.setFakeCrawl(true)
    check(ok == false and msg == "Your character has no Animator yet, try again in a second.", "no animator: " .. tostring(msg))
    animator.Parent = h
end
section("fake crawl")

---------------------------------------------------------------------------
-- 5. fake stab / gunshot
---------------------------------------------------------------------------
do
    clearDelays()
    local ok, msg = A.fakeStab()
    check(ok == false and msg == "Stab animation not found in this game version.", "stab missing: " .. tostring(msg))
    ok, msg = A.fakeShot()
    check(ok == false and msg == "Gunshot animation not found in this game version.", "shot missing: " .. tostring(msg))

    -- fallback: modul assets.animations.player1 yang isinya ID
    modules["assets.animations.player1"] = { combat = { KnifeSwing = "rbxassetid://4444", Wounded = "not an id 2" } }
    ok, msg = A.fakeStab()
    check(ok == true and msg == "Played KnifeSwing", "anim from module ids: " .. tostring(msg))
    local mt = St.Shot.tracks.stab and St.Shot.tracks.stab.track
    check(mt and mt.Animation.AnimationId == "rbxassetid://4444", "Animation built from module id")
    modules["assets.animations.player1"] = nil
    -- fallback: Animation di dalam tool di Backpack (bukan ReplicatedStorage)
    local knifeTool = Me:FindFirstChildOfClass("Backpack"):FindFirstChild("Knife")
    local toolAnim = __mk("Animation", { Name = "Glock", AnimationId = "rbxassetid://5555" }, knifeTool)
    T = T + 11
    ok, msg = A.fakeShot()
    check(ok == true and St.Shot.tracks.shot.track.Animation == toolAnim, "anim found in Backpack tool: " .. tostring(msg))
    toolAnim:Destroy()
    T = T + 11
    clearDelays()

    -- substring di ReplicatedStorage (KnifeIdle) tidak boleh menang dari nama exact di sumber lain (Stab di tool)
    addAnim("KnifeIdle", 6661)
    local stabInTool = __mk("Animation", { Name = "KnifeSwing", AnimationId = "rbxassetid://6662" }, knifeTool)
    ok, msg = A.fakeStab()
    check(ok == true and msg == "Played KnifeSwing", "exact name in Backpack tool beats substring in ReplicatedStorage: " .. tostring(msg))
    stabInTool:Destroy()
    T = T + 11
    clearDelays()
    ok, msg = A.fakeStab()
    check(ok == false and msg == "Stab animation not found in this game version.", "idle pose never played as a stab: " .. tostring(msg))
    animFolder:FindFirstChild("KnifeIdle"):Destroy()
    T = T + 11
    clearDelays()

    -- seatedDied.GunShot = animasi MATI di kursi; fake gunshot tidak boleh pernah memutar ini
    addAnim("GunShot", 444)
    T = T + 11
    clearDelays()
    ok, msg = A.fakeShot()
    check(ok == false, "death animation GunShot is never used as a fake shot: " .. tostring(msg))
    animFolder:FindFirstChild("GunShot"):Destroy()
    T = T + 11
    clearDelays()
    addAnim("KnifeSwing", 222)
    addAnim("Glock", 333)

    local logStart = #__animLog
    ok, msg = A.fakeStab()
    check(ok == true and msg == "Played KnifeSwing", "fake stab: " .. tostring(msg))
    local e = __animLog[logStart + 1]
    check(e and e[1] == "play" and e[2] == "KnifeSwing", "KnifeSwing played")
    local tr = St.Shot.tracks.stab.track
    check(tr.Priority == Enum.AnimationPriority.Action4 and tr.Looped == false, "one-shot track: Action4 (above crawl), not looped")
    check(#__delays == 1, "stop scheduled")
    ok, msg = A.fakeStab()
    check(ok == false and msg == "Too fast, wait a moment.", "cooldown: " .. tostring(msg))
    T = T + 0.7
    ok = A.fakeStab()
    check(ok == true and St.Shot.tracks.stab.track == tr, "plays again after cooldown, track reused")
    check(#__delays == 2, "second stop scheduled")
    -- delay lama tidak boleh memotong putaran baru
    local first = __delays[1]
    local second = __delays[2]
    clearDelays()
    first()
    check(tr.IsPlaying, "stale stop ignored")
    second()
    check(not tr.IsPlaying, "stopped after Length")

    ok, msg = A.fakeShot()
    check(ok == true and msg == "Played Glock", "fake shot: " .. tostring(msg))
    check(__remoteLog == nil or #__remoteLog == 0, "no remotes fired")
    check(Me.Character:FindFirstChild("Knife") == nil, "no tool equipped")
    T = T + 1
    local char = Me.Character
    Me.Character = nil
    ok, msg = A.fakeStab()
    check(ok == false and msg == "You have no living character to do it with.", "no character: " .. tostring(msg))
    Me.Character = char
    clearDelays()
end
section("fake stab / shot")

---------------------------------------------------------------------------
-- 6. ghost
---------------------------------------------------------------------------
local rsSig = RunService.RenderStepped
local defaultWait = rsSig.Wait
do
    local h = hum(Me)
    setPos(Me, 0, 5, 0)
    h.SeatPart = __mk("Seat")
    local ok, msg = A.setGhost(true)
    check(ok == false and msg == "Get out of your seat first.", "seated refused: " .. tostring(msg))
    h.SeatPart = nil

    ok, msg = A.setGhost(true)
    check(ok == true and A.status().ghost, "ghost on: " .. tostring(msg))
    local mids = {}
    rsSig.Wait = function()
        mids[#mids + 1] = pos(Me)
    end
    root(Me).AssemblyLinearVelocity = v3(1, 2, 3)
    RunService.Heartbeat:Fire(0.016)
    check(#mids == 1 and near(mids[1], v3(0, -35, 0)), "offset 40 down during replication: " .. fmt(mids[1]))
    check(near(pos(Me), v3(0, 5, 0)), "restored after RenderStepped: " .. fmt(pos(Me)))
    check(near(root(Me).AssemblyLinearVelocity, v3(1, 2, 3)), "velocity kept")

    ctx.S.ghostDepth = 25
    RunService.Heartbeat:Fire(0.016)
    check(near(mids[2], v3(0, -20, 0)), "ghostDepth setting: " .. fmt(mids[2]))
    ctx.S.ghostDepth = nil

    -- anti numpuk: Heartbeat nested saat frame masih in-flight
    mids = {}
    local nested = false
    rsSig.Wait = function()
        mids[#mids + 1] = pos(Me)
        if not nested then
            nested = true
            RunService.Heartbeat:Fire(0.016)
        end
    end
    RunService.Heartbeat:Fire(0.016)
    check(#mids == 1 and near(mids[1], v3(0, -35, 0)), "no stacking: " .. tostring(#mids) .. " " .. fmt(mids[1]))
    check(near(pos(Me), v3(0, 5, 0)), "restored after nested")

    -- duduk saat ghost aktif: pause
    mids = {}
    rsSig.Wait = function()
        mids[#mids + 1] = pos(Me)
    end
    h.SeatPart = __mk("Seat")
    RunService.Heartbeat:Fire(0.016)
    check(#mids == 0 and near(pos(Me), v3(0, 5, 0)), "paused while seated")
    h.SeatPart = nil

    -- game memindahkan kita di antara Heartbeat dan render (kursi meeting / reset ronde): posisi baru dipakai
    rsSig.Wait = function()
        setPos(Me, 100, 2, 0)
    end
    RunService.Heartbeat:Fire(0.016)
    check(near(pos(Me), v3(100, 2, 0)), "server teleport during a ghost frame is kept: " .. fmt(pos(Me)))
    check(St.Ghost.pending == nil, "pending frame dropped")
    setPos(Me, 0, 5, 0)
    rsSig.Wait = function()
        mids[#mids + 1] = pos(Me)
    end
    RunService.Heartbeat:Fire(0.016)
    check(near(pos(Me), v3(0, 5, 0)), "normal restore still works afterwards: " .. fmt(pos(Me)))
    mids = {}

    -- dimatikan di tengah frame -> tetap dibalikin
    rsSig.Wait = function()
        A.setGhost(false)
    end
    RunService.Heartbeat:Fire(0.016)
    check(not A.status().ghost and near(pos(Me), v3(0, 5, 0)), "off mid-frame restores: " .. fmt(pos(Me)))
    check(St.Ghost.pending == nil, "no pending frame")
    rsSig.Wait = function()
        mids[#mids + 1] = pos(Me)
    end
    RunService.Heartbeat:Fire(0.016)
    check(#mids == 0, "no Heartbeat work after off")

    -- auto-off saat mati
    A.setGhost(true)
    h.Died:Fire()
    check(not A.status().ghost and noteHas("you died"), "auto-off on death")
    -- auto-off saat respawn
    A.setGhost(true)
    local oldChar = Me.Character
    local nc = newChar(Me, 0)
    Me.CharacterAdded:Fire(nc)
    check(not A.status().ghost and noteHas("respawned"), "auto-off on respawn")
    Me.Character = oldChar
    -- karakter berubah tanpa event
    A.setGhost(true)
    Me.Character = nc
    RunService.Heartbeat:Fire(0.016)
    check(not A.status().ghost, "auto-off when character changes")
    Me.Character = oldChar

    -- BindToRenderStep tersedia: restore di prioritas First
    local bound = {}
    __Methods.BindToRenderStep = function(self, name, prio, fn)
        bound[name] = { prio = prio, fn = fn }
    end
    __Methods.UnbindFromRenderStep = function(self, name)
        bound[name] = nil
    end
    Enum.RenderPriority.First.Value = 0
    A.setGhost(true)
    local b = bound.NoctisENIX_GhostRestore
    check(b ~= nil and b.prio == 0, "restore bound at First priority")
    mids = {}
    rsSig.Wait = function()
        mids[#mids + 1] = pos(Me)
    end
    local before
    rsSig.Wait = function()
        before = pos(Me)
        if b then
            b.fn(0.016)
        end
        mids[#mids + 1] = pos(Me)
    end
    RunService.Heartbeat:Fire(0.016)
    check(before and near(before, v3(0, -35, 0)) and near(mids[1], v3(0, 5, 0)), "bound restore puts you back before RenderStepped resumes")
    A.setGhost(false)
    check(bound.NoctisENIX_GhostRestore == nil, "unbound on off")
    __Methods.BindToRenderStep = nil
    __Methods.UnbindFromRenderStep = nil
    Enum.RenderPriority.First.Value = nil
    rsSig.Wait = defaultWait
end
section("ghost")

---------------------------------------------------------------------------
-- 7. Teleport-Stab-Return
---------------------------------------------------------------------------
do
    setPos(Me, 0, 0, 0)
    local origin = v3(0, 0, 0)
    local ok, msg = A.tpStabReturn()
    check(ok == false and msg == "Pick a living player in Target first.", "no target: " .. tostring(msg))
    A.setTarget(Alice)
    ctx.selfRole = function()
        return "Doctor", "TOWN"
    end
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "Mafia only.", "non-mafia refused: " .. tostring(msg))
    ctx.selfRole = function()
        return nil, "TOWN"
    end
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "Mafia only.", "town team refused")
    check(near(pos(Me), origin), "refusal does not move you")

    ctx.selfRole = function()
        return "Mafia", "EVIL"
    end
    -- a) handler method-style
    local M = { calls = 0 }
    local reentry, distAtStab
    function M:setTargetCharacter(c)
        self.target = c
    end
    function M:handleMafiaStab()
        self.calls = self.calls + 1
        distAtStab = (pos(Me) - pos(Alice)).Magnitude
        local okR, msgR = A.tpStabReturn()
        reentry = { okR, msgR }
        -- pin: target jalan, Heartbeat narik kita lagi ke belakangnya
        setPos(Alice, 15, 0, -20)
        RunService.Heartbeat:Fire(0.016)
        self.pinned = pos(Me)
        setPos(Alice, 15, 0, 0)
        self.target:SetAttribute("Downed", true)
    end
    modules["client.controllers.roleController.roles.mafia"] = M
    ok, msg = A.tpStabReturn()
    check(ok == true and msg == "Stab landed on AliceD", "handler stab: " .. tostring(msg))
    check(M.target == Alice.Character and M.calls == 1, "setTargetCharacter(self, char) then handleMafiaStab(self)")
    check(distAtStab and math.abs(distAtStab - 3) < 0.01, "stood 3 studs from target: " .. tostring(distAtStab))
    check(reentry and reentry[1] == false and reentry[2] == "Already running, wait a second.", "busy guard")
    check(M.pinned and near(M.pinned, v3(15, 0, -17)), "pinned behind moving target: " .. fmt(M.pinned))
    check(near(pos(Me), origin), "returned to origin: " .. fmt(pos(Me)))
    check(A.status().lastMethod == "handler:handleMafiaStab", "lastMethod: " .. tostring(A.status().lastMethod))
    check(A.status().busy == false, "busy cleared")
    Alice.Character:SetAttribute("Downed", nil)

    -- b) handler fungsi biasa (1 param)
    local got = {}
    modules["client.controllers.roleController.roles.mafia"] = {
        setTargetCharacter = function(c)
            got.set = c
        end,
        handleMafiaStab = function(c)
            got.stab = c
            c:SetAttribute("Downed", true)
        end,
    }
    ok, msg = A.tpStabReturn()
    check(ok and got.set == Alice.Character and got.stab == Alice.Character, "plain-function convention (char): " .. tostring(msg))
    Alice.Character:SetAttribute("Downed", nil)

    -- c) handler input-style (self, actionName, inputState, inputObject)
    local M3 = {}
    function M3:setTargetCharacter(c)
        self.t = c
    end
    function M3:handleMafiaStab(actionName, state, input)
        if state ~= Enum.UserInputState.Begin then
            return
        end
        self.input = input
        self.t:SetAttribute("Downed", true)
    end
    modules["client.controllers.roleController.roles.mafia"] = M3
    ok, msg = A.tpStabReturn()
    check(ok and M3.input and M3.input.UserInputType == Enum.UserInputType.MouseButton1, "input-handler convention: " .. tostring(msg))
    Alice.Character:SetAttribute("Downed", nil)

    -- d) lewat roleController.roles.mafia
    modules["client.controllers.roleController.roles.mafia"] = nil
    local M4 = { tries = 0 }
    function M4:handleMafiaStab()
        M4.tries = M4.tries + 1
        -- Roblox: field asing di Instance = error (mock tidak), jadi ditiru di sini
        if typeof(self) == "Instance" then
            error("hit is not a valid member of Model")
        end
        self.hit = true
        Alice.Character:SetAttribute("Downed", true)
    end
    modules["client.controllers.roleController"] = { roles = { mafia = M4 } }
    ok, msg = A.tpStabReturn()
    check(ok and M4.hit, "found via roleController.roles.mafia: " .. tostring(msg))
    check(M4.tries == 2, "unknown style, 1 param: (char) failed, then (self): " .. tostring(M4.tries))
    Alice.Character:SetAttribute("Downed", nil)
    modules["client.controllers.roleController"] = nil

    -- e) handler error -> fallback ke Knife tool
    modules["client.controllers.roleController.roles.mafia"] = {
        handleMafiaStab = function()
            error("boom")
        end,
    }
    local knife = Me:FindFirstChildOfClass("Backpack"):FindFirstChild("Knife")
    local actConn = knife.Activated:Connect(function()
        Alice.Character:SetAttribute("Downed", true)
    end)
    unequipCalls = 0
    local logStart = #__animLog
    ok, msg = A.tpStabReturn()
    check(ok == true and msg == "Stab landed on AliceD", "tool fallback: " .. tostring(msg))
    check(A.status().lastMethod == "tool:Knife", "lastMethod tool: " .. tostring(A.status().lastMethod))
    local activated = false
    for k = logStart + 1, #__animLog do
        if __animLog[k][1] == "activate" and __animLog[k][2] == "Knife" then
            activated = true
        end
    end
    check(activated, "Knife:Activate called")
    check(unequipCalls == 1, "knife unequipped afterwards")
    check(near(pos(Me), origin), "returned after tool path")
    Alice.Character:SetAttribute("Downed", nil)
    actConn:Disconnect()
    knife.Parent = Me:FindFirstChildOfClass("Backpack")

    -- f) tool jalan tapi tidak ada efek
    modules["client.controllers.roleController.roles.mafia"] = nil
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "No stab registered; the server may still be counting your cooldown.", "no stab registered: " .. tostring(msg))
    check(near(pos(Me), origin), "returned even when nothing registered")
    knife.Parent = Me:FindFirstChildOfClass("Backpack")

    -- g) tidak ada apa-apa -> tidak teleport sama sekali (tidak ada pin Heartbeat)
    knife.Parent = nil
    local connsBefore = #__conns
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "The stab handler has not loaded yet -- try again in a second.", "nothing available: " .. tostring(msg))
    check(near(pos(Me), origin), "returned when nothing available")
    check(#__conns == connsBefore, "no teleport / pin when nothing can be tried")

    -- h) ProximityPrompt (fireproximityprompt)
    local prompt = __mk("ProximityPrompt", { ActionText = "Stab", Enabled = true }, root(Alice))
    local fired
    fireproximityprompt = function(pr)
        fired = pr
        Alice.Character:SetAttribute("Downed", true)
    end
    ok, msg = A.tpStabReturn()
    check(ok and fired == prompt and A.status().lastMethod == "prompt:fireproximityprompt", "prompt via fireproximityprompt: " .. tostring(msg))
    Alice.Character:SetAttribute("Downed", nil)
    -- InputHoldBegin fallback
    fireproximityprompt = nil
    local held
    __Methods.InputHoldBegin = function(self)
        held = self
    end
    __Methods.InputHoldEnd = function(self)
        if held == self then
            Alice.Character:SetAttribute("Downed", true)
        end
    end
    ok, msg = A.tpStabReturn()
    check(ok and held == prompt and A.status().lastMethod == "prompt:InputHold", "prompt via InputHoldBegin/End: " .. tostring(msg))
    Alice.Character:SetAttribute("Downed", nil)
    __Methods.InputHoldBegin = nil
    __Methods.InputHoldEnd = nil
    -- prompt yang tidak cocok diabaikan
    prompt.ActionText = "Open"
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "The stab handler has not loaded yet -- try again in a second.", "non-matching prompt ignored: " .. tostring(msg))
    prompt:Destroy()

    -- i) role belum diketahui -> tetap jalan, dengan catatan
    knife.Parent = Me:FindFirstChildOfClass("Backpack")
    ctx.selfRole = function()
        return nil, nil
    end
    ok, msg = A.tpStabReturn()
    check(ok == false and string.find(tostring(msg), "role unknown, trying anyway", 1, true) ~= nil, "unknown role note: " .. tostring(msg))
    ctx.selfRole = function()
        return "Mafia", "EVIL"
    end

    -- j) duduk
    hum(Me).SeatPart = __mk("Seat")
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "Get out of your seat first.", "seated: " .. tostring(msg))
    hum(Me).SeatPart = nil

    -- k) ghost aktif: frame in-flight dibereskan dulu, ghost di-suspend selama trip
    A.setGhost(true)
    local ghostMid = 0
    modules["client.controllers.roleController.roles.mafia"] = {
        handleMafiaStab = function()
            RunService.Heartbeat:Fire(0.016)
            Alice.Character:SetAttribute("Downed", true)
        end,
    }
    rsSig.Wait = function()
        ghostMid = ghostMid + 1
    end
    ok, msg = A.tpStabReturn()
    check(ok and ghostMid == 0, "ghost suspended during trip: " .. tostring(ghostMid))
    check(near(pos(Me), origin), "origin intact with ghost on")
    A.setGhost(false)
    rsSig.Wait = defaultWait
    Alice.Character:SetAttribute("Downed", nil)

    local MAFIA = "client.controllers.roleController.roles.mafia"
    -- l) handler ada tapi error, tidak ada strategi lain -> "No stab registered", bukan "belum ke-load"
    knife.Parent = nil
    modules[MAFIA] = {
        handleMafiaStab = function()
            error("on cooldown")
        end,
    }
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "No stab registered; the server may still be counting your cooldown.", "handler error -> stabNone: " .. tostring(msg))
    check(A.status().lastMethod == "handler:handleMafiaStab (errored)", "lastMethod errored: " .. tostring(A.status().lastMethod))
    check(near(pos(Me), origin), "returned after handler error")

    -- m) handler return false -> dipanggil SEKALI saja, pesan stabNone
    local falseCalls = 0
    local MF = {}
    function MF:handleMafiaStab()
        falseCalls = falseCalls + 1
        return false
    end
    modules[MAFIA] = MF
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "No stab registered; the server may still be counting your cooldown.", "handler false -> stabNone: " .. tostring(msg))
    check(falseCalls == 1, "handler returning false is not re-called with other args: " .. tostring(falseCalls))
    check(A.status().lastMethod == "handler:handleMafiaStab (refused)", "lastMethod refused: " .. tostring(A.status().lastMethod))

    -- n) handler di tabel modul diam-diam tidak melakukan apa-apa -> lanjut ke Knife yang beneran kena
    knife.Parent = Me:FindFirstChildOfClass("Backpack")
    local noopCalls = 0
    modules[MAFIA] = {
        handleMafiaStab = function()
            noopCalls = noopCalls + 1
        end,
    }
    local kConn = knife.Activated:Connect(function()
        Alice.Character:SetAttribute("Downed", true)
    end)
    ok, msg = A.tpStabReturn()
    check(ok == true and msg == "Stab landed on AliceD", "silent handler falls through to the knife: " .. tostring(msg))
    check(noopCalls == 1 and A.status().lastMethod == "tool:Knife", "lastMethod after silent handler: " .. tostring(A.status().lastMethod))
    kConn:Disconnect()
    Alice.Character:SetAttribute("Downed", nil)
    knife.Parent = Me:FindFirstChildOfClass("Backpack")
    -- handler yang langsung kena: knife tidak ikut dipakai
    local actCount = 0
    kConn = knife.Activated:Connect(function()
        actCount = actCount + 1
    end)
    modules[MAFIA] = {
        handleMafiaStab = function()
            Alice.Character:SetAttribute("Downed", true)
        end,
    }
    ok, msg = A.tpStabReturn()
    check(ok and actCount == 0 and A.status().lastMethod == "handler:handleMafiaStab", "confirmed handler stops the chain: " .. tostring(actCount))
    kConn:Disconnect()
    Alice.Character:SetAttribute("Downed", nil)

    -- o) handler dicari SEBELUM teleport; ada jeda tsrPre setelah teleport
    local reqPos = nil
    local oldReq = ctx.Game.require
    ctx.Game.require = function(path)
        if path == MAFIA then
            reqPos = pos(Me)
        end
        return oldReq(path)
    end
    local waits = {}
    local oldWait = task.wait
    task.wait = function(t)
        waits[#waits + 1] = t
        return 0
    end
    ok, msg = A.tpStabReturn()
    task.wait = oldWait
    ctx.Game.require = oldReq
    check(ok and reqPos ~= nil and near(reqPos, origin), "handler resolved before teleporting: " .. fmt(reqPos))
    local sawPre = false
    for _, w in ipairs(waits) do
        if w == 0.12 then
            sawPre = true
        end
    end
    check(sawPre, "tsrPre delay after the teleport")
    Alice.Character:SetAttribute("Downed", nil)

    -- p) prompt pemain lain / NPC dalam 12 stud tidak boleh dipakai; prop dunia boleh
    knife.Parent = nil
    modules[MAFIA] = nil
    local bobChar = Bob.Character
    bobChar.Parent = workspace
    setPos(Bob, 20, 0, 0)
    local alicePrompt = __mk("ProximityPrompt", { ActionText = "Stab", Enabled = false }, root(Alice))
    local bobPrompt = __mk("ProximityPrompt", { ActionText = "Stab", Enabled = true }, root(Bob))
    local npc = __mk("Model", { Name = "Dummy" }, workspace)
    __mk("Humanoid", nil, npc)
    __mk("ProximityPrompt", { ActionText = "Kill", Enabled = true }, __mk("Part", { Name = "Torso", CFrame = CFrame.new(16, 0, 0) }, npc))
    local worldKnife = __mk("Part", { Name = "KnifePickup", CFrame = CFrame.new(17, 0, 0) }, workspace)
    __mk("ProximityPrompt", { ActionText = "Pick up", ObjectText = "Knife", Enabled = true }, worldKnife)
    local firedP = {}
    fireproximityprompt = function(pr)
        firedP[#firedP + 1] = pr
        if pr == bobPrompt then
            Bob.Character:SetAttribute("Downed", true)
        end
    end
    T = T + 6
    ok, msg = A.tpStabReturn()
    check(#firedP == 0 and not Bob.Character:GetAttribute("Downed"), "no bystander / NPC / item prompt fired: " .. tostring(#firedP))
    check(ok == false and msg == "The stab handler has not loaded yet -- try again in a second.", "nothing usable -> not loaded: " .. tostring(msg))
    local prop = __mk("Part", { Name = "Altar", CFrame = CFrame.new(18, 0, 0) }, workspace)
    local propPrompt = __mk("ProximityPrompt", { ActionText = "Stab", Enabled = true }, prop)
    fireproximityprompt = function(pr)
        firedP[#firedP + 1] = pr
        if pr == propPrompt then
            Alice.Character:SetAttribute("Downed", true)
        end
    end
    T = T + 6
    ok, msg = A.tpStabReturn()
    check(ok and #firedP == 1 and firedP[1] == propPrompt, "world prop prompt within 12 studs used: " .. tostring(msg))
    Alice.Character:SetAttribute("Downed", nil)
    fireproximityprompt = nil
    prop:Destroy()
    npc:Destroy()
    worldKnife:Destroy()
    alicePrompt:Destroy()
    bobPrompt:Destroy()
    bobChar.Parent = nil
    setPos(Bob, 25, 0, 0)
    T = T + 6

    -- q) target keluar / karakternya hilang selama trip -> bukan "Stab landed"
    local aliceChar = Alice.Character
    modules[MAFIA] = {
        handleMafiaStab = function()
            Alice.Character = nil
        end,
    }
    ok, msg = A.tpStabReturn()
    check(ok == false and msg == "No stab registered; the server may still be counting your cooldown.", "vanished target is not a landed stab: " .. tostring(msg))
    check(near(pos(Me), origin), "returned after target vanished")
    Alice.Character = aliceChar
    -- Health 0 di karakter yang sama tetap dihitung
    modules[MAFIA] = {
        handleMafiaStab = function()
            hum(Alice).Health = 0
        end,
    }
    ok, msg = A.tpStabReturn()
    check(ok == true and msg == "Stab landed on AliceD", "Health 0 counts as landed: " .. tostring(msg))
    hum(Alice).Health = 100
    A.setTarget(Alice)

    -- r) Bring aktif saat TSR: target ditaruh di posisi aslinya selama aksi, bring off menulis balik posisi asli
    A.setBring(true)
    rsSig:Fire(0.016)
    check(near(pos(Alice), v3(0, 0, -6)), "Alice brought in front of me: " .. fmt(pos(Alice)))
    local distSeen
    modules[MAFIA] = {
        handleMafiaStab = function()
            rsSig:Fire(0.016)
            distSeen = (pos(Me) - pos(Alice)).Magnitude
            Alice.Character:SetAttribute("Downed", true)
        end,
    }
    ok, msg = A.tpStabReturn()
    check(ok and distSeen and math.abs(distSeen - 3) < 0.01, "target at its real spot during TSR (client view): " .. tostring(distSeen))
    rsSig:Fire(0.016)
    check(near(pos(Alice), v3(0, 0, -6)), "bring resumes after TSR")
    A.setBring(false)
    check(near(pos(Alice), v3(15, 0, 0)), "bring off writes the real CFrame back: " .. fmt(pos(Alice)))
    Alice.Character:SetAttribute("Downed", nil)
    knife.Parent = Me:FindFirstChildOfClass("Backpack")
    modules[MAFIA] = nil
    A.setTarget(nil)
end
section("tp-stab-return")

---------------------------------------------------------------------------
-- 8. Teleport-Heal-Return
---------------------------------------------------------------------------
do
    setPos(Me, 0, 0, 0)
    local origin = v3(0, 0, 0)
    ctx.selfRole = function()
        return "Mafia", "EVIL"
    end
    local ok, msg = A.tpHealReturn()
    check(ok == false and msg == "Doctor only.", "non-doctor refused: " .. tostring(msg))
    ctx.selfRole = function()
        return "Doctor", "TOWN"
    end
    ok, msg = A.tpHealReturn()
    check(ok == false and msg == "Nobody is downed right now.", "nobody downed: " .. tostring(msg))

    Cara.Character:SetAttribute("Downed", true)
    local D = {}
    local errs = 0
    function D:setTargetCharacter(c)
        self.t = c
    end
    function D:onHealed()
        errs = errs + 1
    end
    function D:playHealEffect()
        errs = errs + 1
    end
    function D:handleDoctorSave()
        self.dist = (pos(Me) - pos(Cara)).Magnitude
        self.t:SetAttribute("Downed", false)
    end
    modules["client.controllers.roleController.roles.doctor"] = D
    ok, msg = A.tpHealReturn()
    check(ok == true and msg == "Saved CaraD", "heal via handler: " .. tostring(msg))
    check(A.status().lastMethod == "handler:handleDoctorSave", "lastMethod: " .. tostring(A.status().lastMethod))
    check(errs == 0, "skipped on*/play* functions")
    check(D.dist and math.abs(D.dist - 3) < 0.01, "stood next to downed player")
    check(near(pos(Me), origin), "returned after heal")

    -- healthChanged bukan "heal" (kata utuh); handle* didahulukan dari nama lain
    Cara.Character:SetAttribute("Downed", true)
    local D2 = { called = {} }
    function D2:healthChanged()
        self.called[#self.called + 1] = "healthChanged"
    end
    function D2:revivePlayer()
        self.called[#self.called + 1] = "revivePlayer"
    end
    function D2:handleDoctorSave()
        self.called[#self.called + 1] = "handleDoctorSave"
        Cara.Character:SetAttribute("Downed", false)
    end
    modules["client.controllers.roleController.roles.doctor"] = D2
    ok, msg = A.tpHealReturn()
    check(ok == true and table.concat(D2.called, ",") == "handleDoctorSave", "only handleDoctorSave called: " .. table.concat(D2.called, ",") .. " " .. tostring(msg))
    check(A.status().lastMethod == "handler:handleDoctorSave", "lastMethod D2: " .. tostring(A.status().lastMethod))

    -- roleController sendiri (bukan modul doctor): cuma kata heal/revive, pickDisguise tidak boleh terpanggil
    modules["client.controllers.roleController.roles.doctor"] = nil
    local picked = false
    modules["client.controllers.roleController"] = {
        pickDisguise = function()
            picked = true
        end,
    }
    Cara.Character:SetAttribute("Downed", true)
    ok, msg = A.tpHealReturn()
    check(ok == false and not picked and msg == "The heal handler has not loaded yet -- try again in a second.", "strict: pick* on roleController ignored: " .. tostring(msg))
    modules["client.controllers.roleController"].reviveDowned = function(c)
        c:SetAttribute("Downed", false)
    end
    ok, msg = A.tpHealReturn()
    check(ok == true and not picked and A.status().lastMethod == "handler:reviveDowned", "strict: revive* on roleController used: " .. tostring(msg))
    modules["client.controllers.roleController"] = nil

    -- prompt: "Revive" di badan target diutamakan dari "Pick up" di dekatnya
    Cara.Character:SetAttribute("Downed", true)
    local pickPart = __mk("Part", { Name = "BananaPart", CFrame = CFrame.new(36, 0, 0) }, workspace)
    local pickPrompt = __mk("ProximityPrompt", { ActionText = "Pick up", Enabled = true }, pickPart)
    local farPart = __mk("Part", { Name = "FarPart", CFrame = CFrame.new(80, 0, 0) }, workspace)
    local farPrompt = __mk("ProximityPrompt", { ActionText = "Revive", Enabled = true }, farPart)
    local revivePrompt = __mk("ProximityPrompt", { ActionText = "Revive", Enabled = true }, root(Cara))
    T = T + 6
    local firedList = {}
    fireproximityprompt = function(pr)
        firedList[#firedList + 1] = pr
        if pr == revivePrompt then
            Cara.Character:SetAttribute("Downed", false)
        end
    end
    ok, msg = A.tpHealReturn()
    check(ok and #firedList == 1 and firedList[1] == revivePrompt, "body prompt preferred: " .. tostring(msg))
    revivePrompt:Destroy()
    Cara.Character:SetAttribute("Downed", true)
    T = T + 6
    firedList = {}
    ok, msg = A.tpHealReturn()
    check(#firedList == 0, "item pickup prompt (Banana) and far prompt never fired: " .. tostring(#firedList))
    check(ok == false and msg == "The heal handler has not loaded yet -- try again in a second.", "nothing usable for heal: " .. tostring(msg))

    -- "Help" di prop dunia tidak dipakai (kata umum cuma untuk badan target); prompt Revive di pemain lain
    -- (Dan, dekat Cara) juga tidak; prop dunia "Revive" dalam 12 stud boleh
    local helpPart = __mk("Part", { Name = "HelpSign", CFrame = CFrame.new(37, 0, 0) }, workspace)
    __mk("ProximityPrompt", { ActionText = "Help", Enabled = true }, helpPart)
    local danChar = Dan.Character
    danChar.Parent = workspace
    setPos(Dan, 39, 0, 0)
    local danPrompt = __mk("ProximityPrompt", { ActionText = "Revive", Enabled = true }, root(Dan))
    T = T + 6
    firedList = {}
    ok, msg = A.tpHealReturn()
    check(#firedList == 0, "Help sign / other player's Revive prompt not fired: " .. tostring(#firedList))
    local station = __mk("Part", { Name = "ReviveStation", CFrame = CFrame.new(38, 0, 0) }, workspace)
    local stationPrompt = __mk("ProximityPrompt", { ActionText = "Revive", Enabled = true }, station)
    fireproximityprompt = function(pr)
        firedList[#firedList + 1] = pr
        if pr == stationPrompt then
            Cara.Character:SetAttribute("Downed", false)
        end
    end
    T = T + 6
    ok, msg = A.tpHealReturn()
    check(ok and #firedList == 1 and firedList[1] == stationPrompt, "world Revive prop near the downed player used: " .. tostring(msg))
    -- "Pick up" / "Help" di badan pemain yang downed tetap boleh
    Cara.Character:SetAttribute("Downed", true)
    station:Destroy()
    local bodyPick = __mk("ProximityPrompt", { ActionText = "Help up", Enabled = true }, root(Cara))
    fireproximityprompt = function(pr)
        firedList[#firedList + 1] = pr
        if pr == bodyPick then
            Cara.Character:SetAttribute("Downed", false)
        end
    end
    firedList = {}
    T = T + 6
    ok, msg = A.tpHealReturn()
    check(ok and firedList[1] == bodyPick, "Help prompt on the downed body used: " .. tostring(msg))
    bodyPick:Destroy()
    helpPart:Destroy()
    danPrompt:Destroy()
    danChar.Parent = nil
    setPos(Dan, 45, 0, 0)
    fireproximityprompt = nil
    pickPart:Destroy()
    farPart:Destroy()
    T = T + 6

    -- handler tidak ada, medkit tidak ada
    Cara.Character:SetAttribute("Downed", true)
    ok, msg = A.tpHealReturn()
    check(ok == false and msg == "The heal handler has not loaded yet -- try again in a second.", "heal not loaded: " .. tostring(msg))

    -- medkit ada tapi tidak ada efek
    local medkit = __mk("Tool", { Name = "Medkit" }, Me:FindFirstChildOfClass("Backpack"))
    ok, msg = A.tpHealReturn()
    check(ok == false and msg == "No heal registered; the server may still be counting your cooldown.", "no heal registered: " .. tostring(msg))
    check(A.status().lastMethod == "tool:Medkit", "medkit tried")
    check(near(pos(Me), origin), "returned after medkit")
    medkit:Destroy()

    -- role tidak diketahui -> catatan
    ctx.selfRole = function()
        return nil, nil
    end
    ok, msg = A.tpHealReturn()
    check(string.find(tostring(msg), "role unknown, trying anyway", 1, true) ~= nil, "unknown role note: " .. tostring(msg))
    Cara.Character:SetAttribute("Downed", nil)
    ctx.selfRole = nil
end
section("tp-heal-return")

---------------------------------------------------------------------------
-- 9. Bring target
---------------------------------------------------------------------------
do
    setPos(Me, 0, 0, 0)
    local ok, msg = A.setBring(true)
    check(ok == false and msg == "Pick a living player in Target first.", "bring without target: " .. tostring(msg))
    A.setTarget(Bob)
    ok, msg = A.setBring(true)
    check(ok == true and msg == "Only you see them move." and A.status().bring, "bring on: " .. tostring(msg))
    rsSig:Fire(0.016)
    check(near(pos(Bob), v3(0, 0, -6)), "Bob in front of me: " .. fmt(pos(Bob)))
    check(near(root(Bob).CFrame.LookVector, v3(0, 0, 1)), "Bob faces me")
    -- update replikasi = posisi asli; teleport pakai posisi asli, bukan posisi bring
    setPos(Bob, 100, 0, 0)
    rsSig:Fire(0.016)
    check(near(pos(Bob), v3(0, 0, -6)), "re-applied every frame")
    ok = A.toTarget()
    check(ok and near(pos(Me), v3(100, 0, 3)), "toTarget uses Bob's real position: " .. fmt(pos(Me)))
    rsSig:Fire(0.016)
    check(near(pos(Bob), v3(100, 0, -3)), "follows me after teleport: " .. fmt(pos(Bob)))
    -- target hilang -> auto-off
    hum(Bob).Health = 0
    T = T + 0.3
    rsSig:Fire(0.016)
    check(not A.status().bring and noteHas("Target lost"), "auto-off when target dies")
    hum(Bob).Health = 100
    setPos(Bob, 25, 0, 0)
    setPos(Me, 0, 0, 0)
    -- setTarget(nil) mematikan bring, dengan notifikasi
    A.setTarget(Bob)
    A.setBring(true)
    A.setTarget(nil)
    check(not A.status().bring and noteHas("Target cleared, bring turned off."), "clearing target turns bring off (notified)")
    -- PlayerRemoving
    A.setTarget(Bob)
    A.setBring(true)
    Players.PlayerRemoving:Fire(Bob)
    check(not A.status().bring and A.getTarget() == nil, "target leaving turns bring off")
    rsSig:Fire(0.016)

    -- off: target diam (tidak ada update replikasi, mis. duduk di kursi anchored) ditulis balik ke posisi asli
    A.setTarget(Bob)
    A.setBring(true)
    rsSig:Fire(0.016)
    check(near(pos(Bob), v3(0, 0, -6)), "Bob brought: " .. fmt(pos(Bob)))
    A.setBring(false)
    check(near(pos(Bob), v3(25, 0, 0)), "bring off writes Bob's real CFrame back: " .. fmt(pos(Bob)))
    -- replikasi sudah menimpa dengan posisi yang lebih baru: jangan ditimpa posisi lama
    A.setBring(true)
    rsSig:Fire(0.016)
    setPos(Bob, 30, 0, 0)
    A.setBring(false)
    check(near(pos(Bob), v3(30, 0, 0)), "newer replicated position kept on off: " .. fmt(pos(Bob)))
    setPos(Bob, 25, 0, 0)
    -- ganti target saat bring aktif: bring ikut target baru, target lama balik ke posisi asli
    A.setBring(true)
    rsSig:Fire(0.016)
    local okS, msgS = A.setTarget(Cara)
    check(okS and msgS == "Target: CaraD" and A.status().bring, "bring stays on when switching target: " .. tostring(msgS))
    check(near(pos(Bob), v3(25, 0, 0)), "old target restored on switch: " .. fmt(pos(Bob)))
    rsSig:Fire(0.016)
    check(near(pos(Cara), v3(0, 0, -6)), "bring follows the new target: " .. fmt(pos(Cara)))
    ok = A.toTarget()
    check(ok and near(pos(Me), v3(35, 0, 3)), "toTarget uses Cara's real position: " .. fmt(pos(Me)))
    A.setBring(false)
    check(near(pos(Cara), v3(35, 0, 0)), "Cara restored: " .. fmt(pos(Cara)))
    setPos(Me, 0, 0, 0)
    A.setTarget(nil)

    -- toDowned: "terdekat" pakai posisi asli, bukan posisi palsu hasil bring
    setPos(Me, 45, 0, 0)
    Bob.Character:SetAttribute("Downed", true)
    Cara.Character:SetAttribute("Downed", true)
    A.setTarget(Bob)
    A.setBring(true)
    rsSig:Fire(0.016)
    ok, msg = A.toDowned()
    check(ok and msg == "Teleported to CaraD." and near(pos(Me), v3(35, 0, 3)), "nearest downed by real position: " .. tostring(msg) .. " " .. fmt(pos(Me)))
    A.setBring(false)
    Bob.Character:SetAttribute("Downed", nil)
    Cara.Character:SetAttribute("Downed", nil)
    setPos(Bob, 25, 0, 0)
    setPos(Me, 0, 0, 0)
    A.setTarget(nil)
    -- BindToRenderStep tersedia
    local bound = {}
    __Methods.BindToRenderStep = function(self, name, prio, fn)
        bound[name] = { prio = prio, fn = fn }
    end
    __Methods.UnbindFromRenderStep = function(self, name)
        bound[name] = nil
    end
    Enum.RenderPriority.Camera.Value = 200
    setPos(Bob, 25, 0, 0)
    A.setTarget(Bob)
    A.setBring(true)
    local b = bound.NoctisENIX_Bring
    check(b ~= nil and b.prio == 199, "bound at Camera - 1")
    local handlers = #rawget(rsSig, "handlers")
    check(handlers == 0, "no RenderStepped fallback when bound: " .. tostring(handlers))
    if b then
        b.fn(0.016)
    end
    check(near(pos(Bob), v3(0, 0, -6)), "bound step moves target")
    ok, msg = A.setBring(false)
    check(ok and msg == "Bring off." and bound.NoctisENIX_Bring == nil, "unbound on off")
    setPos(Bob, 25, 0, 0)
    A.setTarget(nil)
end
section("bring")

---------------------------------------------------------------------------
-- 10. stop()
---------------------------------------------------------------------------
do
    local h = hum(Me)
    setPos(Me, 0, 5, 0)
    h.WalkSpeed = 16
    A.setFakeCrawl(true)
    A.setGhost(true)
    A.setTarget(Bob)
    A.setBring(true)
    local st = A.status()
    check(st.fakeCrawl and st.ghost and st.bring, "all on before stop")
    local tracks = { St.Crawl.crawl, St.Crawl.idle }
    A.stop()
    st = A.status()
    check(not st.fakeCrawl and not st.ghost and not st.bring, "all off after stop")
    check(h.WalkSpeed == 16, "WalkSpeed restored by stop")
    check(not tracks[1].IsPlaying and not tracks[2].IsPlaying, "tracks stopped by stop")
    local hb = rawget(RunService, "_signals").Heartbeat
    check(#hb.handlers == 0, "no Heartbeat handlers left: " .. tostring(#hb.handlers))
    local stepped = rawget(RunService, "_signals").Stepped
    check(stepped ~= nil and #stepped.handlers == 0, "no Stepped handlers left")
    local mids = 0
    rsSig.Wait = function()
        mids = mids + 1
    end
    RunService.Heartbeat:Fire(0.016)
    check(mids == 0 and near(pos(Me), v3(0, 5, 0)), "no ghost offset after stop")
    rsSig.Wait = defaultWait
    check(#__conns > 0, "connections go through ctx.connect")
    local okStop = pcall(A.stop)
    check(okStop, "stop is idempotent")

    -- Unload lewat Janitor: stop() terdaftar di ctx.track sebagai fungsi
    local janitorFn = nil
    for _, x in ipairs(__tracked) do
        if type(x) == "function" then
            janitorFn = x
        end
    end
    check(janitorFn ~= nil, "stop registered with ctx.track for unload")
    h.WalkSpeed = 16
    A.setFakeCrawl(true)
    A.setGhost(true)
    check(h.WalkSpeed == 4 and A.status().ghost, "crawl + ghost on before janitor")
    if janitorFn then
        janitorFn()
    end
    local after = A.status()
    check(not after.fakeCrawl and not after.ghost and h.WalkSpeed == 16, "janitor function turns everything off")
end
section("stop")

print(string.format("SUMMARY %d checks, %d failed", totalChecks, totalFails))
