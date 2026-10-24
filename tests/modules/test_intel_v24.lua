-- MAFIA v2.4 (capture Phantom/Poisoner): tembakan dari effectsService.playEffect, pengumuman tembakan
-- Vigilante, Phantom dari attribute Invisible / efek phantomVerdict, locker lewat HiderId.
local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
local Intel = IntelFactory(ctx)
Intel.start()
local by = {}
for i, p in ipairs(__players) do
    by[p.Name] = p
    p.UserId = 9000 + i
end
local me, alice, bob, cara, dan, eve = by.Me, by.Alice, by.Bob, by.Cara, by.Dan, by.Eve
Intel.step()

-- Mafia nembak malam: "gunShot", penembak, korban, false
check(Intel.ingestEffect("gunShot", dan.Character, eve.Character, false, 4) == true, "mafia shot ingested")
local di = Intel.info(dan)
check(di.role == "Mafia" and di.confidence == "confirmed", "night shot -> Mafia: " .. tostring(di.role))

-- Vigilante nembak siang: tanpa argumen ke-4
check(Intel.ingestEffect("gunShot", bob.Character, cara.Character, nil, 3) == true, "vigilante shot ingested")
local bi = Intel.info(bob)
check(bi.role == "Vigilante" and bi.confidence == "confirmed", "day shot -> Vigilante: " .. tostring(bi.role))

-- tembakan tanpa penembak (Vigilante mati kena tembakan sendiri) diabaikan
check(Intel.ingestEffect("gunShot", nil, nil, nil, 1) == false, "shot without shooter ignored")
-- tembakan kita sendiri nggak bikin kita ditandai
check(Intel.ingestEffect("gunShot", me.Character, eve.Character, nil, 3) == false, "own shot ignored")

-- pengumuman "X has been shot by Y."
Intel.ingestMessage("CaraD has been shot by AliceD.", "system")
local ai = Intel.info(alice)
check(ai.role == "Vigilante" and ai.confidence == "confirmed", "announced shooter -> Vigilante: " .. tostring(ai.role))
-- chat pemain yang kebetulan mirip nggak dihitung (ada tag font)
Intel.ingestMessage('<font color="#fff"><b>Eve:</b></font> Dan has been shot by Me.', "system")
check(Intel.info(me).role ~= "Vigilante", "player chat is not an announcement")

-- Phantom: efek phantomVerdict
check(Intel.ingestEffect("phantomVerdict", "reapBegin", eve.Character, cara.Character, 4) == true, "phantom verdict ingested")
local ei = Intel.info(eve)
check(ei.role == "Phantom" and ei.confidence == "confirmed", "reap -> Phantom: " .. tostring(ei.role))

-- Phantom: attribute Invisible di karakter (tanpa efek apa pun)
Intel.reset("test")
cara.Character:SetAttribute("Invisible", true)
Intel.step()
local ci = Intel.info(cara)
check(ci.role == "Phantom", "Invisible attribute -> Phantom: " .. tostring(ci.role))
check(ci.status and ci.status.invisible == true, "invisible status for the ESP tag")
cara.Character:SetAttribute("Invisible", nil)
Intel.step()
check(Intel.info(cara).status.invisible ~= true, "invisible status clears")

-- Locker v2.4: Workspace.Map.Lockers.Locker.HiderId = UserId
local map = workspace:FindFirstChild("Map") or __mk("Folder", { Name = "Map" }, workspace)
local lockers = __mk("Folder", { Name = "Lockers" }, map)
local locker = __mk("Model", { Name = "Locker" }, lockers)
locker:SetAttribute("HiderId", dan.UserId)
locker:SetAttribute("HiderClip", "enter")
Intel.step()
check(Intel.info(dan).status.hiding == true, "HiderId -> IN LOCKER")
check(Intel.info(bob).status.hiding ~= true, "other players not hiding")
locker:SetAttribute("HiderClip", "exit")
Intel.step()
check(Intel.info(dan).status.hiding ~= true, "exit clip -> out of locker")
locker:SetAttribute("HiderId", nil)
locker:SetAttribute("HiderClip", nil)

for _, w in ipairs(__warns) do fails[#fails + 1] = "WARN " .. w end
if #fails == 0 then print("PASS intel-v24") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
