-- Test Inspector v1.2.0: section LIGHTING + baris LIGHT di live log (apa yang EMP ubah di layar).
-- Inspector sudah jalan waktu di-wrap; dunia palsu dibangun di sini dan dibaca secara lazy.
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
local function handlers(inst, key)
    local s = rawget(inst, "_signals")[key]
    return s and #s.handlers or 0
end

local St = I._test.state()
check(I.version == "1.2.0", "version 1.2.0: " .. tostring(I.version))

----------------------------------------------------------------------
-- Inspector harus murni baca: catat semua tulis property di luar GUI inspector sendiri,
-- semua panggilan remote, dan require.
----------------------------------------------------------------------
local InstMT = getmetatable(game)
local realNewindex = InstMT.__newindex
local writes, testWriting = {}, false
local function inInspectorGui(inst)
    local g = I._test.gui()
    local n = inst
    while n do
        if n == g then
            return true
        end
        n = rawget(n, "_parent")
    end
    return false
end
InstMT.__newindex = function(self, k, v)
    if not testWriting and not inInspectorGui(self) then
        writes[#writes + 1] = tostring(rawget(self, "_props").Name) .. "." .. tostring(k)
    end
    return realNewindex(self, k, v)
end
local remoteCalls, reqCalls = {}, 0
__Methods.FireServer = function(self)
    remoteCalls[#remoteCalls + 1] = "FireServer " .. tostring(self.Name)
end
__Methods.InvokeServer = function(self)
    remoteCalls[#remoteCalls + 1] = "InvokeServer " .. tostring(self.Name)
    return nil
end
require = function(m)
    reqCalls = reqCalls + 1
    error("require is not allowed in this test")
end

-- Tulis property seperti game (tween): set lalu tembak GetPropertyChangedSignal + Changed.
local function setProp(inst, k, v)
    testWriting = true
    inst[k] = v
    testWriting = false
    local sigs = rawget(inst, "_signals")
    local s = sigs["Prop:" .. k]
    if s then
        s:Fire()
    end
    local ch = sigs.Changed
    if ch then
        ch:Fire(k)
    end
end
local function rawProps(inst, t)
    local p = rawget(inst, "_props")
    for k, v in pairs(t) do
        p[k] = v
    end
end
local function P(name)
    for _, p in ipairs(__players) do
        if p.Name == name then
            return p
        end
    end
end

----------------------------------------------------------------------
-- Dunia palsu: Lighting.DV (ColorCorrectionEffect) + Atmosphere, gui EmpInk / EmpAfterimage, lampu
----------------------------------------------------------------------
local Lighting = game:GetService("Lighting")
rawProps(Lighting, {
    Brightness = 2, ClockTime = 0, FogStart = 0, FogEnd = 900, GlobalShadows = true, ExposureCompensation = 0,
    Ambient = Color3.new(0, 0, 0), OutdoorAmbient = Color3.new(0, 0, 0),
})
local DV = __mk("ColorCorrectionEffect", { Name = "DV", Enabled = true, Brightness = 0.1, Contrast = 0.2, Saturation = -0.3, TintColor = Color3.fromRGB(200, 220, 255) }, Lighting)
local atmo = __mk("Atmosphere", { Name = "Atmosphere", Density = 0.395, Offset = 0, Color = Color3.fromRGB(10, 10, 20), Decay = Color3.new(0, 0, 0), Glare = 0, Haze = 1.5 }, Lighting)
__mk("Sky", { Name = "Sky", CelestialBodiesShown = true, StarCount = 3000 }, Lighting)
local cam = workspace.CurrentCamera
local camBlur = __mk("BlurEffect", { Name = "CamBlur", Enabled = false, Size = 0 }, cam)

local me = game:GetService("Players").LocalPlayer
local pg = me:FindFirstChildOfClass("PlayerGui") or __mk("PlayerGui", { Name = "PlayerGui" }, me)
local empInk = __mk("ScreenGui", { Name = "EmpInk", Enabled = true, DisplayOrder = 50, IgnoreGuiInset = true, ResetOnSpawn = false }, pg)
local inkFrame = __mk("Frame", { Name = "Ink", Visible = false, BackgroundTransparency = 1, BackgroundColor3 = Color3.new(0, 0, 0) }, empInk)
local splat = __mk("ImageLabel", { Name = "Splat", Visible = true, BackgroundTransparency = 1, ImageTransparency = 1, Image = "rbxassetid://12345" }, inkFrame)
local inner = __mk("Frame", { Name = "Inner", Visible = true }, splat)
__mk("Frame", { Name = "TooDeep", Visible = true }, inner)
local after = __mk("ScreenGui", { Name = "EmpAfterimage", Enabled = true, DisplayOrder = 49 }, pg)
__mk("Frame", { Name = "Flash", Visible = true, BackgroundTransparency = 1, BackgroundColor3 = Color3.new(1, 1, 1) }, after)
local hud = __mk("ScreenGui", { Name = "HUD", Enabled = true }, pg)
local hudFrame = __mk("Frame", { Name = "HudFrame", Visible = true }, hud)
__mk("ScreenGui", { Name = "Temperature", Enabled = true }, pg)
__mk("ScreenGui", { Name = "empLower", Enabled = false }, pg)
local big = __mk("ScreenGui", { Name = "EmpBig", Enabled = true }, pg)
for i = 1, 60 do
    __mk("Frame", { Name = "Cell" .. i, Visible = true }, big)
end

local mapF = __mk("Folder", { Name = "LightsMap" }, workspace)
for i = 1, 5 do
    __mk("PointLight", { Name = "PointLight", Enabled = (i <= 3), Brightness = 2, Range = 16 }, __mk("Part", { Name = "Lamp" .. i }, mapF))
end
__mk("SurfaceLight", { Name = "SurfaceLight", Enabled = true }, __mk("Part", { Name = "Wall" }, mapF))
local alice = P("Alice")
testWriting = true
alice.Character.Parent = workspace
testWriting = false
__mk("SpotLight", { Name = "Flashlight", Enabled = true, Brightness = 5, Range = 40, Color = Color3.new(1, 1, 1) }, alice.Character:FindFirstChild("Head"))

local RS = game:GetService("ReplicatedStorage")
local SN = __mk("Folder", { Name = "ServiceNetworks" }, RS)
local empSvc = __mk("Folder", { Name = "empService" }, SN)
local detonated = __mk("RemoteEvent", { Name = "detonated" }, empSvc)
__mk("RemoteFunction", { Name = "device" }, empSvc)
__mk("RemoteFunction", { Name = "detonate" }, empSvc)
getconnections = function(sig)
    if sig == detonated.OnClientEvent then
        return { { Function = function(pos) end, Enabled = true } }
    end
    return {}
end

----------------------------------------------------------------------
-- Snapshot: section LIGHTING
----------------------------------------------------------------------
local okS = I.snapshot({ noRequire = true, noNetwork = true, noDecompile = true })
check(okS == true, "snapshot ok")
local t = I.text()
local a = string.find(t, "==== %[%d+%] LIGHTING %(")
local b = a and string.find(t, "\n==== ", a + 1, true)
local S = a and string.sub(t, a, b) or ""
check(a ~= nil, "LIGHTING section present")
local net = string.find(t, "] GAME NETWORK", 1, true)
check(a ~= nil and net ~= nil and a < net, "LIGHTING comes before GAME NETWORK")
check(not has(t, "[lighting] ERROR"), "no LIGHTING section error")
check(not has(t, "] ERROR:"), "no section errors")
check(has(S, "Lighting properties:\n  Brightness = 2\n  ClockTime = 0\n  Ambient = Color3(0, 0, 0)"), "Lighting properties listed in order")
check(has(S, "  ExposureCompensation = 0") and has(S, "  FogEnd = 900") and has(S, "  GlobalShadows = true"), "Lighting exposure / fog / shadows")
check(has(S, "  ColorShift_Top = nil") and has(S, "  Technology = nil") and has(S, "  ShadowSoftness = nil"), "unreadable Lighting properties still listed")
check(has(S, "Lighting children: 3"), "Lighting child count")
check(has(S, "  DV [ColorCorrectionEffect] Enabled=true Brightness=0.1 Contrast=0.2 Saturation=-0.3 TintColor=Color3(200, 220, 255)"), "DV ColorCorrectionEffect with key properties")
check(has(S, "  Atmosphere [Atmosphere] Density=0.395 Offset=0 Color=Color3(10, 10, 20) Decay=Color3(0, 0, 0) Glare=0 Haze=1.5"), "Atmosphere with key properties")
check(has(S, "  Sky [Sky] CelestialBodiesShown=true StarCount=3000"), "Sky listed")
check(has(S, "CurrentCamera Camera children: 1") and has(S, "  CamBlur [BlurEffect] Enabled=false Size=0"), "camera effects listed")
check(has(S, "Emp* ScreenGuis in PlayerGui: 4"), "Emp* gui count (EmpInk, EmpAfterimage, empLower, EmpBig)")
check(has(S, "gui EmpInk [ScreenGui] Enabled=true DisplayOrder=50 IgnoreGuiInset=true ResetOnSpawn=false descendants=4"), "EmpInk header")
check(has(S, "    Ink [Frame] Visible=false BackgroundTransparency=1 BackgroundColor3=Color3(0, 0, 0)"), "EmpInk frame with visibility / transparency / color")
check(has(S, '      Splat [ImageLabel] Visible=true BackgroundTransparency=1 ImageTransparency=1 Image="rbxassetid://12345"'), "image label with ImageTransparency")
check(has(S, "        Inner [Frame] Visible=true") and not has(S, "TooDeep"), "Emp tree depth 3")
check(has(S, "gui EmpAfterimage [ScreenGui] Enabled=true DisplayOrder=49") and has(S, "    Flash [Frame] Visible=true BackgroundTransparency=1 BackgroundColor3=Color3(255, 255, 255)"), "EmpAfterimage listed")
check(has(S, "gui empLower [ScreenGui] Enabled=false"), "Emp prefix matched in any case")
check(not has(S, "gui HUD") and not has(S, "HudFrame") and not has(S, "Temperature"), "non-Emp guis not in Emp list")
check(has(S, "    Cell40 [Frame]") and not has(S, "    Cell41 [Frame]") and has(S, "    ... tree cap 40 nodes"), "Emp tree capped at 40 nodes")
check(has(S, "empService.detonated [RemoteEvent] (not called) client listeners: 1") and has(S, "empService.detonate [RemoteFunction] (not called)"), "empService remotes listed, not called")
check(string.find(S, "\n    #1 [^\n]+", 1) ~= nil, "detonated client listener described")
check(has(S, "lights in workspace: PointLight x5 (enabled 3), SpotLight x1 (enabled 1), SurfaceLight x1 (enabled 1); scanned "), "light counts")
check(not has(S, "(cap 20000)"), "light scan below cap")
check(has(S, "lights inside player characters: 1 (enabled 1)") and has(S, "Workspace.Alice.Head.Flashlight [SpotLight] Enabled=true Brightness=5 Range=40 Color=Color3(255, 255, 255) [Alice]"), "flashlight in a character")
check(#writes == 0, "snapshot wrote no game property: " .. table.concat(writes, ", "))

----------------------------------------------------------------------
-- Live log: baris LIGHT + coalescing
----------------------------------------------------------------------
local T = 5000
I._test.setClock(function()
    return T
end)
local RunService = game:GetService("RunService")
local okL = I.startLive()
check(okL == true and St.live == true, "startLive")
local L0 = liveSection(I.text())
check(has(L0, "LIGHT baseline Lighting Brightness=2 ClockTime=0 Ambient=Color3(0, 0, 0)"), "baseline Lighting line")
check(has(L0, "LIGHT baseline Lighting child: DV [ColorCorrectionEffect] Enabled=true Brightness=0.1"), "baseline DV line")
check(has(L0, "LIGHT baseline Lighting child: Atmosphere [Atmosphere] Density=0.395"), "baseline Atmosphere line")
check(has(L0, "LIGHT baseline Camera child: CamBlur [BlurEffect] Enabled=false Size=0"), "baseline camera line")
check(has(L0, "LIGHT baseline gui EmpInk [ScreenGui] Enabled=true") and has(L0, "LIGHT baseline gui EmpAfterimage [ScreenGui]"), "baseline Emp gui lines")
check(not has(L0, "gui HUD") and not has(L0, "Temperature"), "non-Emp guis not hooked")
check(has(L0, "REMOTE_IN") == false, "no remote traffic at start")

local BR = "LIGHT Lighting.DV [ColorCorrectionEffect] Brightness = "
-- 50 update di frame yang sama: satu baris, sisanya ditahan
for i = 1, 50 do
    setProp(DV, "Brightness", -i / 50)
end
local LA = liveSection(I.text())
check(count(LA, BR) == 1, "50 quick DV.Brightness updates give one line: " .. count(LA, BR))
check(has(LA, BR .. "-0.02  (was 0.1)"), "first update logged with old value")
check(next(St.lightPend) ~= nil, "skipped updates pending")
-- property lain di instance yang sama punya window sendiri
setProp(DV, "Contrast", 0.5)
check(has(liveSection(I.text()), "LIGHT Lighting.DV [ColorCorrectionEffect] Contrast = 0.5  (was 0.2)"), "other property not coalesced with Brightness")
-- window lewat -> Heartbeat menulis nilai akhir + jumlah update yang dilewati
T = T + 0.3
RunService.Heartbeat:Fire(0.016)
local LB = liveSection(I.text())
check(count(LB, BR) == 2, "trailing line after the window: " .. count(LB, BR))
check(has(LB, BR .. "-1  (was -0.02)  (+49 updates coalesced)"), "trailing line has final value and skipped count")
check(next(St.lightPend) == nil, "nothing pending after flush")
-- tween 60 fps-ish: update tiap 0.06 dtk selama 2.4 dtk -> satu baris per 0.25 dtk
for i = 1, 40 do
    T = T + 0.06
    setProp(DV, "Brightness", -1 + i / 40)
    RunService.Heartbeat:Fire(0.016)
end
local LC = liveSection(I.text())
check(count(LC, BR) == 10, "40-step tween coalesced to 8 lines: " .. (count(LC, BR) - 2))
check(count(LC, "(+4 updates coalesced)") == 8, "each tween line counts the 4 skipped updates: " .. count(LC, "(+4 updates coalesced)"))
check(has(LC, BR .. "0  (was -0.125)  (+4 updates coalesced)"), "tween end value logged")
check(not has(LC, "LIGHT suppressed"), "coalescing keeps LIGHT under the rate limit")

-- Lighting, Atmosphere, gui Emp*
T = T + 1
setProp(Lighting, "ExposureCompensation", -3)
setProp(Lighting, "Brightness", 0)
setProp(atmo, "Density", 0.9)
setProp(empInk, "Enabled", false)
setProp(inkFrame, "Visible", true)
for i = 1, 20 do
    setProp(inkFrame, "BackgroundTransparency", 1 - i / 20)
end
setProp(splat, "ImageTransparency", 0.25)
setProp(hudFrame, "Visible", false)
setProp(camBlur, "Size", 10)
T = T + 0.3
RunService.Heartbeat:Fire(0.016)
local LD = liveSection(I.text())
check(has(LD, "LIGHT Lighting ExposureCompensation = -3  (was 0)"), "Lighting.ExposureCompensation change")
check(has(LD, "LIGHT Lighting Brightness = 0  (was 2)"), "Lighting.Brightness change")
check(has(LD, "LIGHT Lighting.Atmosphere [Atmosphere] Density = 0.9  (was 0.395)"), "Atmosphere.Density change")
check(has(LD, "LIGHT Me.PlayerGui.EmpInk [ScreenGui] Enabled = false  (was true)"), "EmpInk Enabled change")
check(has(LD, "LIGHT Me.PlayerGui.EmpInk.Ink [Frame] Visible = true  (was false)"), "Emp frame Visible change")
check(has(LD, "LIGHT Me.PlayerGui.EmpInk.Ink [Frame] BackgroundTransparency = 0.95  (was 1)"), "Emp frame transparency first step")
check(has(LD, "LIGHT Me.PlayerGui.EmpInk.Ink [Frame] BackgroundTransparency = 0  (was 0.95)  (+19 updates coalesced)"), "Emp frame transparency tween coalesced")
check(has(LD, "LIGHT Me.PlayerGui.EmpInk.Ink.Splat [ImageLabel] ImageTransparency = 0.25  (was 1)"), "Emp image transparency change")
check(not has(LD, "HudFrame"), "non-Emp gui changes not logged")
check(has(LD, "LIGHT Camera.CamBlur [BlurEffect] Size = 10  (was 0)"), "camera effect change")

-- anak baru / hilang di Lighting dan Camera
local empCC = __mk("ColorCorrectionEffect", { Name = "EmpCC", Brightness = -0.5 }, Lighting)
Lighting.ChildAdded:Fire(empCC)
setProp(empCC, "Brightness", -0.8)
testWriting = true
empCC.Parent = nil
testWriting = false
Lighting.ChildRemoved:Fire(empCC)
local blur2 = __mk("BlurEffect", { Name = "EmpBlur", Enabled = true, Size = 24 }, cam)
cam.ChildAdded:Fire(blur2)
-- Emp gui dibuat ulang (ResetOnSpawn) + isi baru di EmpInk
local ink2 = __mk("ScreenGui", { Name = "EmpInk2", Enabled = true }, pg)
local ink2Frame = __mk("Frame", { Name = "Ink2", Visible = false }, ink2)
pg.ChildAdded:Fire(ink2)
pg.ChildAdded:Fire(__mk("ScreenGui", { Name = "Scoreboard" }, pg))
setProp(ink2Frame, "Visible", true)
local blots = {}
for i = 1, 10 do
    blots[i] = __mk("ImageLabel", { Name = "Blot" .. i, ImageTransparency = 0.5 }, empInk)
    empInk.DescendantAdded:Fire(blots[i])
end
T = T + 0.3
RunService.Heartbeat:Fire(0.016)
setProp(blots[10], "ImageTransparency", 0)
-- EMP dari server (REMOTE_IN yang sudah ada) di timeline yang sama
detonated.OnClientEvent:Fire("EMP_BOOM")
local LE = liveSection(I.text())
check(has(LE, "LIGHT + EmpCC [ColorCorrectionEffect] Enabled=true Brightness=-0.5") and has(LE, "in Lighting"), "Lighting ChildAdded logged with properties")
check(has(LE, "LIGHT Lighting.EmpCC [ColorCorrectionEffect] Brightness = -0.8  (was -0.5)"), "new Lighting effect hooked")
check(has(LE, "LIGHT - EmpCC [ColorCorrectionEffect] from Lighting"), "Lighting ChildRemoved logged")
check(has(LE, "LIGHT + EmpBlur [BlurEffect] Enabled=true Size=24 in Camera"), "Camera ChildAdded logged")
check(has(LE, "LIGHT + gui EmpInk2 [ScreenGui] Enabled=true"), "new Emp gui logged")
check(has(LE, "LIGHT Me.PlayerGui.EmpInk2.Ink2 [Frame] Visible = true  (was false)"), "new Emp gui hooked")
check(not has(LE, "Scoreboard"), "new non-Emp gui ignored")
check(count(LE, "LIGHT Me.PlayerGui.EmpInk [ScreenGui] + Blot") == 2, "DescendantAdded burst coalesced: " .. count(LE, "LIGHT Me.PlayerGui.EmpInk [ScreenGui] + Blot"))
check(has(LE, "LIGHT Me.PlayerGui.EmpInk [ScreenGui] + Blot1 [ImageLabel] ImageTransparency=0.5"), "first DescendantAdded logged")
check(has(LE, "LIGHT Me.PlayerGui.EmpInk [ScreenGui] + Blot10 [ImageLabel] ImageTransparency=0.5  (+9 updates coalesced)"), "last DescendantAdded logged with count")
check(has(LE, "LIGHT Me.PlayerGui.EmpInk.Blot10 [ImageLabel] ImageTransparency = 0  (was 0.5)"), "added Emp descendant hooked")
check(has(LE, 'REMOTE_IN ReplicatedStorage.ServiceNetworks.empService.detonated ("EMP_BOOM")'), "EMP remote in the same timeline")

-- kamera diganti
local newCam = __mk("Camera", { Name = "Camera2" })
testWriting = true
workspace.CurrentCamera = newCam
testWriting = false
workspace:GetPropertyChangedSignal("CurrentCamera"):Fire()
__mk("ColorCorrectionEffect", { Name = "CamCC" }, newCam)
newCam.ChildAdded:Fire(newCam:FindFirstChild("CamCC"))
local LF = liveSection(I.text())
check(has(LF, "LIGHT CurrentCamera -> Camera2") and has(LF, "LIGHT new camera Camera2: no children"), "camera replacement logged")
check(has(LF, "LIGHT + CamCC [ColorCorrectionEffect]") and has(LF, "in Camera2"), "new camera hooked")

local badLine = nil
for line in string.gmatch(LF, "[^\n]+") do
    if line ~= "==== LIVE LOG ====" and not string.match(line, "^%[%+%d+%.%d%ds%] [%u_]+ ") then
        badLine = line
        break
    end
end
check(badLine == nil, "every live line is '[+t.ttS] CATEGORY ...': " .. tostring(badLine))

-- stop: update yang masih ditahan ditulis dulu, lalu semua koneksi lepas
setProp(DV, "Saturation", -0.6)
setProp(DV, "Saturation", -0.9)
I.stopLive()
local LG = liveSection(I.text())
local satAt = string.find(LG, "LIGHT Lighting.DV [ColorCorrectionEffect] Saturation = -0.9  (was -0.6)  (+1 updates coalesced)", 1, true)
local stopAt = string.find(LG, "LIVE stopped", 1, true)
check(satAt ~= nil and stopAt ~= nil and satAt < stopAt, "pending update flushed before LIVE stopped")
check(St.live == false and #St.liveConns == 0, "stopLive disconnects everything")
check(handlers(DV, "Prop:Brightness") == 0 and handlers(Lighting, "Prop:ExposureCompensation") == 0, "property signals released")
check(handlers(Lighting, "ChildAdded") == 0 and handlers(pg, "ChildAdded") == 0 and handlers(empInk, "DescendantAdded") == 0, "child signals released")
check(handlers(inkFrame, "Prop:Visible") == 0 and handlers(cam, "ChildAdded") == 0, "Emp gui / camera signals released")
check(next(St.lightPend) == nil and St.lightN == 0, "LIGHT state reset")
local before = I.lines()
setProp(DV, "Brightness", 0.7)
setProp(inkFrame, "Visible", false)
check(I.lines() == before, "nothing logged after stop")

-- start lagi -> hook ulang; unload -> lepas lagi
T = T + 5
I.startLive()
setProp(DV, "Brightness", 0.3)
check(has(liveSection(I.text()), BR .. "0.3  (was 0.7)"), "restart rehooks LIGHT")
-- batas hook: maksimal 200 isi per gui Emp*, 600 instance total, lalu satu baris catatan
local flood = {}
for g = 1, 4 do
    local fg = __mk("ScreenGui", { Name = "EmpFlood" .. g, Enabled = true }, pg)
    for i = 1, 210 do
        flood[#flood + 1] = __mk("Frame", { Name = "F" .. i, Visible = true }, fg)
    end
    pg.ChildAdded:Fire(fg)
end
check(St.lightN == 600, "LIGHT hook cap 600 instances: " .. St.lightN)
check(count(liveSection(I.text()), "LIGHT hook cap reached (600 instances)") == 1, "hook cap noted once")
check(handlers(flood[1], "Prop:Visible") == 1 and handlers(flood[201], "Prop:Visible") == 0, "per-gui cap: 200 descendants hooked")
check(handlers(flood[#flood], "Prop:Visible") == 0, "nothing hooked past the total cap")
I.unload()
check(St.alive == false and #St.liveConns == 0, "unload")
check(handlers(DV, "Prop:Brightness") == 0 and handlers(pg, "ChildAdded") == 0, "unload releases LIGHT connections")

-- read-only
check(#writes == 0, "inspector wrote no game property: " .. table.concat(writes, ", "))
check(#remoteCalls == 0, "inspector called no remote: " .. table.concat(remoteCalls, ", "))
check(reqCalls == 0, "inspector required nothing: " .. reqCalls)
check(#St.errs == 0, "no inspector errors: " .. table.concat(St.errs, " | "))

if #fails == 0 then
    print("PASS inspector-light (" .. passes .. " checks)")
else
    for _, f in ipairs(fails) do
        print("FAIL " .. f)
    end
    print("passed " .. passes .. ", failed " .. #fails)
end
