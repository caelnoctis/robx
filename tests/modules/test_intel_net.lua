local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
local Intel = IntelFactory(ctx)
Intel.start()
local me, alice, bob, eve
for _, p in ipairs(__players) do
    if p.Name == "Me" then me = p elseif p.Name == "Alice" then alice = p elseif p.Name == "Bob" then bob = p elseif p.Name == "Eve" then eve = p end
end
-- attribute jebakan dari dump asli
eve:SetAttribute("DiscordRoles", "Doctor")
eve:SetAttribute("MafiaBoosters", 3)
eve:SetAttribute("DiscordTagRoles", "Mafia")
eve:SetAttribute("Hotkeys", "Judge")
Intel.step()
local ai = Intel.info(eve)
check(ai.role == nil, "Discord/booster attributes must not set a role, got " .. tostring(ai.role))
-- bukti jaringan
check(Intel.addEvidence(bob, "MAFIA", "confirmed", "role reveal") == true, "addEvidence ok")
check(Intel.info(bob).role == "Mafia" and Intel.info(bob).confidence == "confirmed", "bob mafia")
check(Intel.addTeam(alice, "Veil Team", "confirmed", "teammate") == true, "addTeam ok")
check(Intel.info(alice).team == "VEIL", "alice veil")
check(Intel.addEvidence(alice, "notarole", "confirmed", "x") == false, "unknown role rejected")
Intel.addEvidence(me, "Witch", "confirmed", "server", true)
local r, t = Intel.self()
check(r == "Witch" and t == "EVIL", "self from server: " .. tostring(r) .. "/" .. tostring(t))
Intel.ingestMessage("The Harbinger thinks Bob is a Doctor.", "system")
Intel.ingestMessage("The Harbinger was correct", "system")
local conflict = false
for _, e in ipairs(Intel.feed()) do if string.find(e.text, "Conflict", 1, true) then conflict = true end end
check(Intel.info(bob).role == "Doctor" and conflict, "newer confirmed wins and conflict is logged")
-- v2.3: Bodyguard NEUTRAL, ikut sisi tim yang dia jaga tanpa dianggap konflik
local cara
for _, p in ipairs(__players) do if p.Name == "Cara" then cara = p end end
if cara then
    check(Intel.addEvidence(cara, "Bodyguard", "confirmed", "mafia teamMembers") == true, "bodyguard role")
    check(Intel.info(cara).team == "NEUTRAL", "bodyguard neutral by default: " .. tostring(Intel.info(cara).team))
    check(Intel.addTeam(cara, "EVIL", "confirmed", "teammate (Mafia)") == true, "bodyguard can join a side")
    local ci = Intel.info(cara)
    check(ci.role == "Bodyguard" and ci.team == "EVIL", "bodyguard on mafia side: " .. tostring(ci.role) .. "/" .. tostring(ci.team))
    check(Intel.addTeam(cara, "neutral", "confirmed", "x") == false and Intel.info(cara).team == "EVIL", "known side not overwritten by neutral")
    check(Intel.addTeam(eve, "Neutral", "confirmed", "jester reveal") == true and Intel.info(eve).team == "NEUTRAL", "NEUTRAL accepted by addTeam")
else
    fails[#fails + 1] = "no Cara in mock players"
end
for _, w in ipairs(__warns) do fails[#fails + 1] = "WARN " .. w end
if #fails == 0 then print("PASS intel-net") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
