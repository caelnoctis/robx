
-- ===================== v2 MAIN SMOKE TESTS =====================
local failures = {}
local function check(cond, msg) if not cond then failures[#failures + 1] = msg end end
local function sigOf(inst, name) return rawget(inst, "_signals")[name] end
local function all() return screen:GetDescendants() end
local function findButton(text)
    for _, d in ipairs(all()) do
        if d:IsA("TextButton") and d.Text == text then return d end
    end
end
local function click(btn) rawget(btn, "_signals").MouseButton1Click:Fire() end
local function toastHas(sub)
    for _, d in ipairs(toastHolder:GetChildren()) do
        if d:IsA("TextLabel") and string.find(d.Text, sub, 1, true) then return true end
    end
    return false
end
local alice
for _, p in ipairs(__players) do if p.Name == "Alice" then alice = p end end

-- 1. ESP pakai Intel
S.esp = true
ESP.step()
local ao = ESP.objs[alice]
check(ao ~= nil, "ESP object for Alice")
if ao then
    check(math.abs(ao.hl.FillColor.R - 1) < 0.01 and ao.hl.FillColor.G < 0.3, "Alice red (EVIL)")
    check(string.find(ao.tx.Text, "EVIL TEAM", 1, true) ~= nil, "team line: " .. ao.tx.Text)
    check(string.find(ao.tx.Text, "[MAFIA]", 1, true) ~= nil, "role line")
    check(string.find(ao.tx.Text, "Mask", 1, true) ~= nil and string.find(ao.tx.Text, "@Alice", 1, true) ~= nil, "disguise shown with real name")
    check(string.find(ao.tx.Text, "DOWNED", 1, true) ~= nil, "status tag")
end
check(ESP.objs[__players[1]] == nil, "no ESP on self")

-- 2. refreshUi
refreshUi()
check(string.find(selfRoleLabel.Text, "Doctor", 1, true) ~= nil and string.find(selfRoleLabel.Text, "TOWN", 1, true) ~= nil, "self role label: " .. selfRoleLabel.Text)
local foundKnown = false
for _, d in ipairs(all()) do
    if d:IsA("TextLabel") and string.find(d.Text, "AliceD: Mafia [EVIL]", 1, true) then foundKnown = true end
end
check(foundKnown, "known roles feed lists Alice")

-- 3. click semua tombol biasa (lewati key button & tombol berbahaya)
local skip = { ["Unload NoctisENIX"] = true, ["Rejoin server"] = true, ["NONE"] = true, ["..."] = true, ["RightShift"] = true }
local function clickPass()
    local n = 0
    for _, d in ipairs(all()) do
        if d:IsA("TextButton") and not skip[d.Text] and not string.find(d.Text, "  v", 1, true) then
            local s = rawget(d, "_signals").MouseButton1Click
            if s then s:Fire() n = n + 1 end
        end
    end
    return n
end
local n1 = clickPass()
check(n1 > 30, "many clicks: " .. n1)
check(S.speedOn and S.fly and S.noclip and S.fullbright, "toggles on")
for _, d in ipairs(toastHolder:GetChildren()) do d:Destroy() end
click(findButton("Teleport-Heal-Return"))
check(toastHas("Doctor only."), "heal-return message surfaced")
local ghostLabel
for _, d in ipairs(all()) do
    if d:IsA("TextLabel") and string.find(d.Text, "Ghost (others", 1, true) then ghostLabel = d end
end
local ghostHit = ghostLabel and ghostLabel.Parent:FindFirstChildOfClass("TextButton")
for _, c in ipairs(ghostLabel.Parent:GetChildren()) do
    if c:IsA("TextButton") and c.Text == "" then ghostHit = c end
end
click(ghostHit)
check(toastHas("Get out of your seat first."), "ghost refusal surfaced")
local hb = sigOf(__services.RunService, "Heartbeat")
for _ = 1, 4 do hb:Fire(0.3) end
clickPass()
hb:Fire(0.3)
check(not (S.speedOn or S.fly or S.noclip or S.fullbright), "toggles off after second pass")

-- 4. keybind: Fake stab
local holder
for _, d in ipairs(all()) do
    if d:IsA("TextButton") and d.Text == "Fake stab" then holder = d.Parent end
end
check(holder ~= nil, "fake stab holder")
local kb
for _, c in ipairs(holder:GetChildren()) do if c:IsA("TextButton") and c.Text == "NONE" then kb = c end end
check(kb ~= nil, "fake stab key button")
local uis = __services.UserInputService
if kb then
    click(kb)
    check(UI.capturing == true, "capturing")
    sigOf(uis, "InputBegan"):Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.G }, false)
    check(kb.Text == "G", "bound to G: " .. kb.Text)
    UI.lastCapture = -1
    for _, d in ipairs(toastHolder:GetChildren()) do d:Destroy() end
    sigOf(uis, "InputBegan"):Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.G }, false)
    check(toastHas("Played KnifeSwing"), "G triggers fake stab")
    -- hapus bind dengan Backspace
    click(kb)
    sigOf(uis, "InputBegan"):Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Backspace }, false)
    check(kb.Text == "NONE", "bind cleared")
end

-- 5. dropdown target
local dd
for _, d in ipairs(all()) do
    if d:IsA("TextButton") and string.find(d.Text, "  v", 1, true) then dd = d end
end
check(dd ~= nil, "dropdown button")
if dd then
    click(dd)
    local opt = findButton("AliceD (@Alice)")
    check(opt ~= nil, "dropdown option for Alice")
    if opt then click(opt) end
    check(Actions.getTarget() == alice, "target set via dropdown")
    check(string.find(dd.Text, "AliceD", 1, true) ~= nil, "dropdown label updated")
    check(findButton("AliceD (@Alice)") == nil, "dropdown closed")
end

-- 6. menu key
UI.lastCapture = -1
main.Visible = true
sigOf(uis, "InputBegan"):Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.RightShift }, false)
check(main.Visible == false, "menu key hides")

-- 7. unload
local ub = findButton("Unload NoctisENIX")
check(ub ~= nil, "unload button")
if ub then click(ub) end
check(S.alive == false, "unloaded")
check(rawget(screen, "_destroyed") == true, "screen destroyed")
check(__G.NoctisENIX == nil, "genv cleared")
check(#Janitor == 0, "janitor empty")

for _, w in ipairs(__warns) do failures[#failures + 1] = "WARN: " .. w end
if #failures == 0 then print("ALL V2 SMOKE TESTS PASSED") else
    print("FAILURES (" .. #failures .. "):")
    for _, f in ipairs(failures) do print(" - " .. f) end
end
return table.concat(__out, "\n")
