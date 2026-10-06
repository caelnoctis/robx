
-- ===================== v2 SMOKE TESTS WITH REAL MODULES =====================
-- prelude.lua + NoctisENIX.lua (dengan intel/actions asli) + file ini, satu chunk.
local failures = {}
local function check(cond, msg) if not cond then failures[#failures + 1] = msg end end
local function sigOf(inst, name) return rawget(inst, "_signals")[name] end
local function all() return screen:GetDescendants() end
local function click(btn)
    if not btn then return false end
    local s = rawget(btn, "_signals").MouseButton1Click
    if s then s:Fire() end
    return true
end
local function card(title)
    for _, d in ipairs(all()) do
        if d.Name == "Card_" .. title then return d end
    end
end
local function control(title, name)
    local c = card(title)
    if not c then return nil end
    if name == "Toggle" then return c:FindFirstChild("Toggle") end
    local right = c:FindFirstChild("Right")
    return right and right:FindFirstChild(name)
end
local function toastText()
    local t = {}
    for _, d in ipairs(UI.toastHolder:GetDescendants()) do
        if d:IsA("TextLabel") then t[#t + 1] = d.Text end
    end
    return table.concat(t, " | ")
end
local function clearToasts()
    for _, d in ipairs(UI.toastHolder:GetChildren()) do
        if d.Name == "Toast" then d:Destroy() end
    end
end
local hb = sigOf(__services.RunService, "Heartbeat")
local function tick(n) for _ = 1, (n or 1) do hb:Fire(0.3) end end

local me, alice, bob
for _, p in ipairs(__players) do
    if p.Name == "Me" then me = p elseif p.Name == "Alice" then alice = p elseif p.Name == "Bob" then bob = p end
end
check(Intel ~= nil and type(Intel.info) == "function", "real Intel loaded")
check(Actions ~= nil and type(Actions.tpStabReturn) == "function", "real Actions loaded")

-- Aset & jaringan dibuat di smoke_world.lua (sebelum script dimuat).
local knifeAnim = __world.knifeAnim
Game.scanAnimations(true)
workspace:SetAttribute("gamePhase", "Night")

-- 1. Bob mengayunkan pisau saat malam -> Mafia confirmed -> ESP [MAFIA]
local bobAnimator = bob.Character:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
local track = bobAnimator:LoadAnimation(knifeAnim)
track:Play()
tick(4)
local info = Intel.info(bob)
check(info.role == "Mafia", "Bob deduced Mafia, got " .. tostring(info.role) .. " / " .. tostring(info.reason))
check(info.confidence == "confirmed", "Bob confirmed, got " .. tostring(info.confidence))
check(info.team == "EVIL" or Game.teamOf(info.role) == "EVIL", "Bob team EVIL")
S.esp = true
ESP.step()
local bo = ESP.objs[bob]
check(bo ~= nil and string.find(bo.tx.Text, "[MAFIA]", 1, true) ~= nil, "ESP shows [MAFIA] for Bob: " .. (bo and bo.tx.Text or "nil"))
check(bo ~= nil and math.abs(bo.hl.FillColor.R - 1) < 0.01, "Bob highlighted red")

-- 2. Fake stab memutar animasi game di karakter sendiri
__animLog = {}
clearToasts()
click(control("Fake stab", "Action"))
local played = false
for _, e in ipairs(__animLog) do if e[1] == "play" and e[2] == "KnifeSwing" then played = true end end
check(played, "fake stab played KnifeSwing on local animator")
check(string.find(toastText(), "Fake stab", 1, true) ~= nil, "fake stab toast: " .. toastText())

-- 3. Target via dropdown, lalu To target
local dd = control("Target", "Dropdown")
click(dd)
local opt
for _, d in ipairs(all()) do
    if d.Name == "Option" and string.find(d.Text, "BobD", 1, true) then opt = d end
end
check(opt ~= nil, "Bob in target dropdown")
click(opt)
check(Actions.getTarget() == bob, "target Bob")
local myRoot = me.Character:FindFirstChild("HumanoidRootPart")
local before = myRoot.CFrame
clearToasts()
click(control("To target", "Action"))
local after = myRoot.CFrame or me.Character:GetPivot()
local moved = (me.Character:GetPivot() ~= before) or (after ~= before)
check(moved, "teleported toward target")
check(string.find(toastText(), "Teleport", 1, true) ~= nil, "teleport toast: " .. toastText())

-- 4. Ghost on/off lewat UI
clearToasts()
click(control("Ghost", "Toggle"))
tick(2)
click(control("Ghost", "Toggle"))
tick(1)
check(string.find(toastText(), "Ghost", 1, true) ~= nil, "ghost toasts: " .. toastText())

-- 5. Fake crawl on/off
clearToasts()
click(control("Fake crawl", "Toggle"))
tick(2)
click(control("Fake crawl", "Toggle"))
tick(1)
check(string.find(toastText(), "Fake crawl", 1, true) ~= nil, "crawl toasts: " .. toastText())

-- 6. Roles tab tampil
refreshUi()
local foundBob = false
for _, d in ipairs(all()) do
    if d:IsA("TextLabel") and string.find(d.Text, "<b>BobD</b>  Mafia", 1, true) then foundBob = true end
end
check(foundBob, "Roles tab lists Bob as Mafia")

-- 7. Unload bersih
click(control("Unload NoctisENIX", "Action"))
check(S.alive == false and #Janitor == 0, "unloaded cleanly")

for _, w in ipairs(__warns) do failures[#failures + 1] = "WARN: " .. w end
if #failures == 0 then print("ALL V2 SMOKE TESTS PASSED (real modules)") else
    print("FAILURES (" .. #failures .. "):")
    for _, f in ipairs(failures) do print(" - " .. f) end
end
return table.concat(__out, "\n")
