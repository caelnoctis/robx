
-- ===================== v2 MAIN SMOKE TESTS =====================
-- Dijalankan setelah prelude.lua + NoctisENIX.lua dalam satu chunk, jadi local script (S, UI, ESP, ...) terlihat.
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
local function toastHas(sub)
    for _, d in ipairs(UI.toastHolder:GetDescendants()) do
        if d:IsA("TextLabel") and string.find(d.Text, sub, 1, true) then return true end
    end
    return false
end
local function clearToasts()
    for _, d in ipairs(UI.toastHolder:GetChildren()) do
        if d.Name == "Toast" then d:Destroy() end
    end
end
local uis = __services.UserInputService
local function press(key)
    sigOf(uis, "InputBegan"):Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = key }, false)
end
local alice
for _, p in ipairs(__players) do if p.Name == "Alice" then alice = p end end

-- 0. struktur dasar
check(#UI.tabs == 9, "9 tabs, got " .. #UI.tabs)
check(UI.modal.Modal == true, "modal button unlocks mouse")

-- 1. ESP pakai Intel
S.esp = true
ESP.step()
local ao = ESP.objs[alice]
check(ao ~= nil, "ESP object for Alice")
if ao then
    check(math.abs(ao.hl.FillColor.R - 1) < 0.01 and ao.hl.FillColor.G < 0.35, "Alice red (EVIL)")
    check(string.find(ao.tx.Text, "EVIL TEAM", 1, true) ~= nil, "team line: " .. ao.tx.Text)
    check(string.find(ao.tx.Text, "[MAFIA]", 1, true) ~= nil, "role line")
    check(string.find(ao.tx.Text, "Mask", 1, true) ~= nil and string.find(ao.tx.Text, "@Alice", 1, true) ~= nil, "disguise + real name")
    check(string.find(ao.tx.Text, "DOWNED", 1, true) ~= nil, "status tag")
    check(ao.stroke.Color == TeamColors.EVIL, "panel stroke team color")
end
check(ESP.objs[__players[1]] == nil, "no ESP on self")

-- 2. refreshUi
refreshUi()
local function anyLabel(sub)
    for _, d in ipairs(all()) do
        if d:IsA("TextLabel") and d.Visible ~= false and string.find(d.Text, sub, 1, true) then return true end
    end
    return false
end
check(anyLabel("Doctor"), "self role shown")
check(anyLabel("<b>AliceD</b>  Mafia  [EVIL]"), "known roles lists Alice")
check(anyLabel("stub event"), "evidence feed")
check(PlayerRows.rows[alice] and PlayerRows.rows[alice].role.Text == "MAFIA", "player row role chip")

-- 3. klik semua toggle & action (lewati yang berbahaya)
local skipCards = { ["Card_Unload NoctisENIX"] = true, ["Card_Rejoin server"] = true }
local function clickPass()
    local n = 0
    for _, d in ipairs(all()) do
        if d:IsA("TextButton") and (d.Name == "Toggle" or d.Name == "Action") then
            local c = d.Name == "Toggle" and d.Parent or d.Parent.Parent
            if not skipCards[c.Name] then
                click(d)
                n = n + 1
            end
        end
    end
    return n
end
local n1 = clickPass()
check(n1 > 35, "many controls clicked: " .. n1)
check(S.speedOn and S.fly and S.noclip and S.fullbright, "toggles flipped")
local hb = sigOf(__services.RunService, "Heartbeat")
for _ = 1, 4 do hb:Fire(0.3) end
clickPass()
hb:Fire(0.3)
check(not (S.speedOn or S.fly or S.noclip or S.fullbright), "toggles off after second pass")

-- 4. pesan dari Actions sampai ke toast
clearToasts()
click(control("Teleport-Heal-Return", "Action"))
check(toastHas("Doctor only."), "heal-return message surfaced")
clearToasts()
click(control("Ghost", "Toggle"))
check(toastHas("Get out of your seat first."), "ghost refusal surfaced")
-- toggle harus balik off kalau Actions menolak
local ghostSwitch = card("Ghost"):FindFirstChild("Right"):FindFirstChild("Switch")
check(ghostSwitch ~= nil, "ghost switch exists")

-- 5. keybind Fake stab
local kb = control("Fake stab", "Key")
check(kb ~= nil and kb.Text == "NONE", "fake stab key chip")
if kb then
    click(kb)
    check(UI.capturing == true, "capturing")
    press(Enum.KeyCode.G)
    check(kb.Text == "G", "bound to G: " .. kb.Text)
    UI.lastCapture = -1
    clearToasts()
    press(Enum.KeyCode.G)
    check(toastHas("Played KnifeSwing"), "G triggers fake stab")
    click(kb)
    press(Enum.KeyCode.Backspace)
    check(kb.Text == "NONE", "bind cleared")
    UI.lastCapture = -1
end

-- 6. dropdown target
local dd = control("Target", "Dropdown")
check(dd ~= nil, "dropdown button")
if dd then
    click(dd)
    local opt
    for _, d in ipairs(all()) do
        if d.Name == "Option" and string.find(d.Text, "AliceD", 1, true) then opt = d end
    end
    check(opt ~= nil, "dropdown option for Alice")
    check(opt and string.find(opt.Text, "[Mafia]", 1, true) ~= nil, "option shows known role")
    click(opt)
    check(Actions.getTarget() == alice, "target set via dropdown")
    check(string.find(dd.Text, "AliceD", 1, true) ~= nil, "dropdown label updated")
    local still = false
    for _, d in ipairs(all()) do if d.Name == "Option" then still = true end end
    check(not still, "dropdown closed")
end

-- 7. perbaikan kursor (v2.2): MouseBehavior milik game TIDAK PERNAH disentuh
UI.setVisible(true)
uis.MouseIconEnabled = false
uis.MouseBehavior = Enum.MouseBehavior.LockCenter
__mouse = Vector2.new(5, 5)
__runRenderBinds()
check(uis.MouseIconEnabled == true, "mouse icon shown while hovering the window")
check(uis.MouseBehavior == Enum.MouseBehavior.LockCenter, "MouseBehavior untouched (game keeps aiming control)")
check(UI.modal.Visible == true, "Modal button frees the mouse while menu open")
check(UI.halo.Visible == true, "halo over window")
__mouse = Vector2.new(5000, 5000)
__runRenderBinds()
check(UI.halo.Visible == false, "no halo outside window")
check(uis.MouseIconEnabled == false, "icon back to the game's value once the mouse leaves the window")
-- game mengubah ikon sendiri saat kita nggak memaksa -> kita nggak menimpa
uis.MouseIconEnabled = true
__runRenderBinds()
check(uis.MouseIconEnabled == true, "game's own icon state left alone")
uis.MouseIconEnabled = false
UI.lastCapture = -1
press(Enum.KeyCode.RightShift)
check(UI.main.Visible == false, "menu key hides")
__runRenderBinds()
check(UI.modal.Visible == false, "Modal hidden with the menu (engine re-locks the mouse)")
check(uis.MouseBehavior == Enum.MouseBehavior.LockCenter and uis.MouseIconEnabled == false, "nothing restored over the game's state on close")
press(Enum.KeyCode.RightShift)
check(UI.main.Visible == true, "menu key shows again")

-- 8. minimize
click(UI.minButton)
check(UI.sidebar.Visible == false and UI.contentArea.Visible == false, "minimized")
click(UI.minButton)
check(UI.sidebar.Visible == true and UI.contentArea.Visible == true, "restored")

-- 9. unload
local ub = control("Unload NoctisENIX", "Action")
check(ub ~= nil, "unload button")
click(ub)
check(S.alive == false, "unloaded")
check(rawget(screen, "_destroyed") == true and rawget(cursorGui, "_destroyed") == true, "guis destroyed")
check(__G.NoctisENIX == nil, "genv cleared")
check(#Janitor == 0, "janitor empty")
local leftBinds = 0
for _ in pairs(__renderBinds) do leftBinds = leftBinds + 1 end
check(leftBinds == 0, "render step unbound")

for _, w in ipairs(__warns) do failures[#failures + 1] = "WARN: " .. w end
if #failures == 0 then print("ALL V2 SMOKE TESTS PASSED") else
    print("FAILURES (" .. #failures .. "):")
    for _, f in ipairs(failures) do print(" - " .. f) end
end
return table.concat(__out, "\n")
