local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
local me, alice, bob
for _, p in ipairs(__players) do
    if p.Name == "Me" then me = p elseif p.Name == "Alice" then alice = p elseif p.Name == "Bob" then bob = p end
end
local calls = {}
ctx.Net = {
    stab = function(p)
        calls[#calls + 1] = "stab:" .. p.Name
        if p == alice then
            p.Character:SetAttribute("Downed", true)
            return true, "remote onStab(Player)"
        end
        return false, "server said no (Player)"
    end,
    heal = function(p)
        calls[#calls + 1] = "heal:" .. p.Name
        p.Character:SetAttribute("Downed", false)
        return true, "remote onHeal(Player)"
    end,
}
ctx.selfRole = function() return "Mafia", "EVIL" end
local A = ActionsFactory(ctx)
local myRoot = me.Character:FindFirstChild("HumanoidRootPart")
local origin = myRoot.CFrame.Position
A.setTarget(alice)
local ok, msg = A.tpStabReturn()
check(ok == true, "stab via remote ok: " .. tostring(msg))
check(calls[1] == "stab:alice" or calls[1] == "stab:Alice", "net strategy called first: " .. tostring(calls[1]))
check(A.status().lastMethod == "remote onStab(Player)", "lastMethod: " .. tostring(A.status().lastMethod))
local back = me.Character:GetPivot().Position
check((back - origin).Magnitude < 0.01 or (myRoot.CFrame.Position - origin).Magnitude < 0.01, "returned to origin")
-- remote menolak -> lanjut ke strategi lain, pesan jujur
A.setTarget(bob)
local ok2, msg2 = A.tpStabReturn()
check(ok2 == false, "rejected stab reports failure: " .. tostring(msg2))
check(calls[#calls] ~= nil, "net called for bob")
-- heal
ctx.selfRole = function() return "Doctor", "TOWN" end
bob.Character:SetAttribute("Downed", true)
local ok3, msg3 = A.tpHealReturn()
check(ok3 == true, "heal via remote ok: " .. tostring(msg3))
for _, w in ipairs(__warns) do fails[#fails + 1] = "WARN " .. w end
if #fails == 0 then print("PASS actions-net") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
