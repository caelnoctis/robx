-- ID & nama animasi dari game asli (Inspector): player1.KnifeSwing / Glock = serangan,
-- Falling From Stab / Falling From Gunshot / seatedDied.GunShot = korban.
local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
local RS = ctx.ReplicatedStorage
local assets = __mk("Folder", { Name = "assets" }, RS)
local anims = __mk("Folder", { Name = "animations" }, assets)
local p1 = __mk("Folder", { Name = "player1" }, anims)
local seatedDied = __mk("Folder", { Name = "seatedDied" }, anims)
local knife = __mk("Animation", { Name = "KnifeSwing", AnimationId = "rbxassetid://17433486403" }, p1)
local glock = __mk("Animation", { Name = "Glock", AnimationId = "rbxassetid://17429045335" }, p1)
local fallStab = __mk("Animation", { Name = "Falling From Stab", AnimationId = "rbxassetid://111273782270862" }, p1)
local fallShot = __mk("Animation", { Name = "Falling From Gunshot", AnimationId = "rbxassetid://113616977381351" }, p1)
local seatShot = __mk("Animation", { Name = "GunShot", AnimationId = "rbxassetid://119641788723184" }, seatedDied)
ctx.Game.scanAnimations(true)
workspace:SetAttribute("gamePhase", "Night")

local Intel = IntelFactory(ctx)
Intel.start()
local byName = {}
for _, p in ipairs(__players) do byName[p.Name] = p end
-- Hapus tool bawaan dunia mock biar nggak ada bukti lain.
for _, p in ipairs(__players) do
    if p.Character then
        for _, c in ipairs(p.Character:GetChildren()) do if c:IsA("Tool") then c:Destroy() end end
    end
end
local function play(p, anim)
    -- Game memutar track dengan Animation bernama "Animation" (cuma ID yang benar).
    local inst = __mk("Animation", { Name = "Animation", AnimationId = anim.AnimationId })
    local animator = p.Character:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
    animator:LoadAnimation(inst):Play()
end
play(byName.Bob, glock)
play(byName.Cara, fallShot)
play(byName.Dan, seatShot)
play(byName.Eve, fallStab)
play(byName.Alice, knife)
Intel.step()
check(Intel.info(byName.Bob).role == "Mafia", "Glock at night -> Mafia, got " .. tostring(Intel.info(byName.Bob).role))
check(Intel.info(byName.Alice).role == "Mafia", "KnifeSwing at night -> Mafia")
local rCara = Intel.info(byName.Cara).role
check(rCara ~= "Mafia" and rCara ~= "Vigilante", "victim Falling From Gunshot NOT flagged as attacker: " .. tostring(rCara))
local rDan = Intel.info(byName.Dan).role
check(rDan ~= "Mafia" and rDan ~= "Vigilante", "victim seatedDied.GunShot NOT flagged as attacker: " .. tostring(rDan))
local rEve = Intel.info(byName.Eve).role
check(rEve ~= "Mafia" and rEve ~= "Vigilante", "victim Falling From Stab NOT flagged as attacker: " .. tostring(rEve))
for _, w in ipairs(__warns) do fails[#fails + 1] = "WARN " .. w end
if #fails == 0 then print("PASS intel-anim") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
