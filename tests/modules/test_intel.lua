-- Test Intel (role detection engine). Jalan di atas prelude + ctx_mock.
local Players = ctx.Players
local Me = ctx.LocalPlayer
local RS = ctx.ReplicatedStorage
local CS = ctx.CollectionService
local TCS = ctx.TextChatService

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

-- UserId unik (prelude kasih semua 1)
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

local T = 1000
local function adv(dt)
    T = T + dt
end
local nextId = 500
local function newPlayer(name, x)
    local p = __mkPlayer(name, { x = x })
    nextId = nextId + 1
    p.UserId = nextId
    Players.PlayerAdded:Fire(p)
    return p
end
local function animator(p)
    return p.Character:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
end
local function play(p, name, id)
    local anim = __mk("Animation", { Name = name, AnimationId = "rbxassetid://" .. id })
    local tr = animator(p):LoadAnimation(anim)
    tr:Play()
    return tr
end
local function sys(text)
    TCS.MessageReceived:Fire({ Text = text, TextSource = nil, TextChannel = { Name = "RBXSystem" } })
end
local function feedHas(Intel, needle)
    for _, e in ipairs(Intel.feed()) do
        if string.find(e.text, needle, 1, true) then
            return true
        end
    end
    return false
end
local function notesHas(needle)
    for _, n in ipairs(__notes) do
        if string.find(n, needle, 1, true) then
            return true
        end
    end
    return false
end
local function countNotes(needle)
    local n = 0
    for _, s in ipairs(__notes) do
        if string.find(s, needle, 1, true) then
            n = n + 1
        end
    end
    return n
end
local function slow(Intel)
    adv(2.1)
    Intel.step()
end

local Intel = IntelFactory(ctx)
Intel._test.setClock(function()
    return T
end)
check(Intel.start() == true, "start returns true")
check(Intel.start() == true, "start idempotent")
local connsAfterStart = #__conns
Intel.start()
check(#__conns == connsAfterStart, "second start adds no connections")
section("start")

------------------------------------------------------------------
-- 1. Attribute / ValueObject yang di-replicate
------------------------------------------------------------------
local cara, dan, bob = P("Cara"), P("Dan"), P("Bob")
local ci = Intel.info(cara)
check(ci.role == "Doctor", "Cara role from attribute: " .. tostring(ci.role))
check(ci.confidence == "confirmed", "Cara confirmed: " .. tostring(ci.confidence))
check(ci.team == "TOWN", "Cara team TOWN: " .. tostring(ci.team))
check(ci.reason == "attribute Role", "Cara reason: " .. tostring(ci.reason))
local di = Intel.info(dan)
check(di.role == nil and di.team == "TOWN" and di.confidence == "confirmed", "Dan StringValue Role=Civilian -> TOWN team only")
-- Bob pegang Revolver -> Vigilante suspect dulu
local bi = Intel.info(bob)
check(bi.confidence == "suspect" and bi.candidates and bi.candidates.Vigilante, "Bob revolver -> Vigilante suspect")
check(bi.role == "Vigilante", "single candidate shown as suspect role")
-- live attribute change di karakter
bob.Character:SetAttribute("currentRole", "Saboteur")
bi = Intel.info(bob)
check(bi.role == "Saboteur" and bi.confidence == "confirmed" and bi.team == "VEIL", "Bob live attr -> Saboteur confirmed: " .. tostring(bi.role))
-- attribute dengan nama tidak jelas -> likely saja; attribute "guess" diabaikan
local lia = newPlayer("Lia", 1500)
lia:SetAttribute("Something", "Witch")
lia:SetAttribute("harbingerGuess", "Mafia")
Intel.step()
local li = Intel.info(lia)
check(li.role == "Witch" and li.confidence == "likely", "Lia odd attr -> Witch likely: " .. tostring(li.role) .. "/" .. tostring(li.confidence))
-- substring bukan role ("mafiaDead" / kalimat) tidak dianggap role
local lou = newPlayer("Lou", 1550)
lou:SetAttribute("Role", "Killed by the Mafia")
Intel.step()
check(Intel.info(lou).role == nil, "sentence containing role word is not a role attribute")
section("attribute roles")

------------------------------------------------------------------
-- 2. Tag Billboard di atas kepala
------------------------------------------------------------------
local eve = P("Eve")
local bb = __mk("BillboardGui", { Name = "RoleTag" }, eve.Character:FindFirstChild("Head"))
__mk("TextLabel", { Name = "Label", Text = "<b>[MAFIA]</b>" }, bb)
slow(Intel)
local ei = Intel.info(eve)
check(ei.role == "Mafia" and ei.confidence == "confirmed" and ei.reason == "visible tag", "Eve visible tag -> Mafia: " .. tostring(ei.role) .. " " .. tostring(ei.reason))
check(ei.team == "EVIL", "Eve team EVIL")
-- nama tag yang cuma username / display name bukan role
local doc2 = newPlayer("Doctor_Strange", 1600)
local bb2 = __mk("BillboardGui", { Name = "NameTag" }, doc2.Character:FindFirstChild("Head"))
__mk("TextLabel", { Text = "Doctor_Strange" }, bb2)
-- tag tersembunyi -> likely
local hal = newPlayer("Hal", 1700)
local bb3 = __mk("BillboardGui", { Name = "Hidden", Enabled = false }, hal.Character:FindFirstChild("Head"))
__mk("TextLabel", { Text = "JANITOR" }, bb3)
-- template tersembunyi yang sama di banyak karakter -> diabaikan
local templ = {}
for _, n in ipairs({ "Alice", "Dan", "Frank", "Me", "Lia", "Lou" }) do
    local g = __mk("BillboardGui", { Name = "Tmpl", Enabled = false }, P(n).Character:FindFirstChild("Head"))
    __mk("TextLabel", { Text = "[WITCH]" }, g)
    templ[#templ + 1] = g
end
-- label tim
local tess = newPlayer("Tess", 1800)
local bb4 = __mk("BillboardGui", { Name = "TeamTag" }, tess.Character:FindFirstChild("Head"))
__mk("TextLabel", { Text = "EVIL TEAM" }, bb4)
slow(Intel)
check(Intel.info(doc2).role == nil, "username containing role word is not a tag")
local hi = Intel.info(hal)
check(hi.role == "Janitor" and hi.confidence == "likely" and hi.reason == "hidden tag", "hidden tag -> likely: " .. tostring(hi.role) .. "/" .. tostring(hi.confidence))
check(Intel.info(P("Frank")).role ~= "Witch" and Intel.info(P("Alice")).role ~= "Witch", "repeated hidden template ignored")
local ti = Intel.info(tess)
check(ti.role == nil and ti.team == "EVIL" and ti.confidence == "confirmed", "EVIL TEAM label -> team only")
for _, g in ipairs(templ) do
    g:Destroy()
end
section("visible tags")

------------------------------------------------------------------
-- 3. Animasi: tusuk malam, tembak siang
------------------------------------------------------------------
workspace:SetAttribute("gamePhase", "Night")
local sam = newPlayer("Sam", 3000)
play(sam, "KnifeSwing", 70001)
local si = Intel.info(sam)
check(si.role == "Mafia" and si.confidence == "confirmed" and si.reason == "swung a knife at night", "night stab -> Mafia confirmed: " .. tostring(si.reason))
-- idle pisau tidak dihitung serangan
local ian = newPlayer("Ian", 3050)
play(ian, "KnifeIdle", 70009)
check(Intel.info(ian).role == nil, "knife idle anim is not an attack")
-- animasi replicate bernama "Animation", dikenali lewat AnimationId di assets.animations
local assets = __mk("Folder", { Name = "assets" }, RS)
local anims = __mk("Folder", { Name = "animations" }, assets)
local p1 = __mk("Folder", { Name = "player1" }, anims)
__mk("Animation", { Name = "gunShot", AnimationId = "rbxassetid://70002" }, p1)
__mk("Animation", { Name = "lockerPose", AnimationId = "rbxassetid://70010" }, p1)
ctx.Game.scanAnimations(true)
workspace:SetAttribute("gamePhase", "Day")
local rex = newPlayer("Rex", 3100)
play(rex, "Animation", 70002)
local ri = Intel.info(rex)
check(ri.role == "Vigilante" and ri.confidence == "confirmed", "day shot (id lookup) -> Vigilante: " .. tostring(ri.role))
-- fase tidak diketahui -> tembakan cuma bikin kandidat
workspace:SetAttribute("gamePhase", nil)
local gus = newPlayer("Gus", 3200)
play(gus, "Animation", 70002)
local gi = Intel.info(gus)
check(gi.confidence == "suspect" and gi.candidates and gi.candidates.Mafia and gi.candidates.Vigilante and gi.role == nil, "unknown-phase shot -> suspect Mafia/Vigilante")
section("animations")

------------------------------------------------------------------
-- 4. Downed: siapa pelakunya
------------------------------------------------------------------
local ace = newPlayer("Ace", 3500)
local vic = newPlayer("Vic", 3510)
play(ace, "stab", 70003)
local ai = Intel.info(ace)
check(ai.role == "Mafia" and ai.confidence == "likely", "unknown phase stab -> Mafia likely")
adv(1)
vic.Character:SetAttribute("Downed", true)
ai = Intel.info(ace)
check(ai.confidence == "confirmed" and ai.reason == "stabbed VicD", "downed attribution upgrades to confirmed: " .. tostring(ai.confidence) .. " " .. tostring(ai.reason))
check(feedHas(Intel, "AceD downed VicD"), "kill feed downed line")
check(Intel.info(vic).status.downed == true, "victim status downed")
-- serangan lebih dari 4 detik lalu tidak dihitung
local old = newPlayer("Old", 3600)
local ov = newPlayer("Ovi", 3605)
play(old, "Slash", 70004)
adv(5)
ov.Character:SetAttribute("Downed", true)
check(feedHas(Intel, "OviD went down"), "no attacker -> went down")
check(Intel.info(old).confidence == "likely", "stale attack not attributed")
section("downed attribution")

------------------------------------------------------------------
-- 5. Doctor: revive dengan satu kandidat
------------------------------------------------------------------
local vin = newPlayer("Vin", 4000)
local docP = newPlayer("Doc", 4006)
local far = newPlayer("Far", 4100)
vin.Character:SetAttribute("Downed", true)
vin.Character:SetAttribute("Downed", false)
Intel.step() -- belum 0.3 s
check(Intel.info(docP).role == nil, "revive waits before crediting")
adv(0.5)
Intel.step()
local dci = Intel.info(docP)
check(dci.role == "Doctor" and dci.confidence == "confirmed" and dci.reason == "revived VinD", "single candidate revive -> Doctor: " .. tostring(dci.role) .. " " .. tostring(dci.reason))
check(Intel.info(far).role == nil, "far player not Doctor")
-- Downed hilang karena mati -> bukan revive
local vik = newPlayer("Vik", 4500)
local nur = newPlayer("Nur", 4505)
vik.Character:SetAttribute("Downed", true)
vik.Character:SetAttribute("Downed", false)
vik.Character:SetAttribute("Dead", true)
adv(0.5)
Intel.step()
check(Intel.info(nur).role == nil, "downed->dead is not a revive")
check(feedHas(Intel, "VikD died"), "death in feed")
section("doctor revive")

------------------------------------------------------------------
-- 6. Witch: irisan dua silence
------------------------------------------------------------------
local w1 = newPlayer("Wa", 5000)
local w2 = newPlayer("Wb", 5010)
local v1 = newPlayer("Va", 5005)
local v2 = newPlayer("Vb", 4984)
v1.Character:SetAttribute("witchSilenced", true)
local wa, wb = Intel.info(w1), Intel.info(w2)
check(wa.confidence == "suspect" and wa.candidates and wa.candidates.Witch, "first silence -> Wa suspect")
check(wb.candidates and wb.candidates.Witch and wb.role == "Witch", "first silence -> Wb suspect")
check(Intel.info(v1).status.silenced == true, "victim silenced status")
adv(3)
v2:SetAttribute("Silenced", 1)
wa, wb = Intel.info(w1), Intel.info(w2)
check(wa.role == "Witch" and wa.confidence == "confirmed" and wa.reason == "in reach of every silence", "intersection -> Wa Witch: " .. tostring(wa.reason))
check(wb.confidence ~= "confirmed" and not (wb.candidates and wb.candidates.Witch), "Wb dropped from candidates")
section("witch intersection")

------------------------------------------------------------------
-- 7. Harbinger: benar, salah, dan urutan terbalik
------------------------------------------------------------------
local hank = newPlayer("Hank", 6000)
sys("The Harbinger thinks <font color=\"#ff0000\">HankD</font> is a Janitor.")
check(Intel.info(hank).role == nil, "pending call is not evidence yet")
sys("The Harbinger was correct!")
local hk = Intel.info(hank)
check(hk.role == "Janitor" and hk.confidence == "confirmed" and hk.reason == "Harbinger call", "correct call -> confirmed: " .. tostring(hk.role))
local ike = newPlayer("Ike", 6100)
local ivy = newPlayer("Ivy", 6200)
adv(3)
sys("The Harbinger thinks IkeD is a Witch.")
sys("The Harbinger was incorrect.")
check(Intel._test.state.recs[ike].notRoles.Witch == true, "wrong call marks target not-that-role")
ike:SetAttribute("Something", "Witch")
Intel.step()
check(Intel.info(ike).role ~= "Witch", "not-role blocks weaker evidence")
adv(2)
ivy.Character:FindFirstChildOfClass("Humanoid").Health = 0
Intel.step()
local iv = Intel.info(ivy)
check(iv.role == "Harbinger" and iv.confidence == "confirmed", "next death after wrong call -> Harbinger: " .. tostring(iv.role))
check(iv.status.dead == true, "health 0 -> dead status")
-- urutan terbalik: mati dulu, baru pengumuman salah
local jo = newPlayer("Jo", 6300)
local kat = newPlayer("Kat", 6400)
adv(3)
jo:SetAttribute("Dead", true)
sys("The Harbinger thinks KatD is a Doctor.")
sys("The Harbinger was incorrect.")
check(Intel.info(jo).role == "Harbinger", "death just before wrong call -> Harbinger")
-- watch habis setelah 8 detik
local kip = newPlayer("Kip", 6500)
local kim2 = newPlayer("Kai", 6600)
adv(3)
sys("The Harbinger thinks KipD is a Mafia.")
sys("The Harbinger was incorrect.")
adv(9)
Intel.step()
kim2:SetAttribute("Dead", true)
Intel.step()
check(Intel.info(kim2).role ~= "Harbinger", "death after 8 s window is not Harbinger")
section("harbinger")

------------------------------------------------------------------
-- 8. Status, disguise, pengumuman generik
------------------------------------------------------------------
local stan = newPlayer("Stan", 8000)
stan:SetAttribute("Detained", true)
stan.Character:SetAttribute("witchSilenced", true)
stan.Character:SetAttribute("poisonApplied", true)
stan.Character:SetAttribute("lockerPose", true)
CS:AddTag(stan.Character, "Ragdolled")
stan.Character:SetAttribute("Downed", true)
Intel.step()
local st = Intel.info(stan).status
check(st.detained and st.silenced and st.poisoned and st.hiding and st.ragdolled and st.downed, "all statuses on")
check(st.dead == false, "not dead")
stan.Character:SetAttribute("poisonCured", true)
stan.Character:SetAttribute("lockerPose", false)
Intel.step()
st = Intel.info(stan).status
check(st.poisoned == false, "cured -> not poisoned")
check(st.hiding == false, "left locker")
-- hiding lewat animasi lockerPose
local hid = newPlayer("Hid", 8100)
local tr = play(hid, "Animation", 70010)
Intel.step()
check(Intel.info(hid).status.hiding == true, "lockerPose animation -> hiding")
tr:Stop()
Intel.step()
check(Intel.info(hid).status.hiding == false, "locker animation stopped -> not hiding")
-- disguise
local dex = newPlayer("Dex", 8200)
dex:SetAttribute("DisguiseName", "Hudson")
Intel.step()
check(Intel.info(dex).disguise == "Hudson", "disguise name")
check(Intel.info(stan).disguise == nil, "no disguise -> nil")
-- pengumuman pakai nama disguise
adv(3)
sys("Hudson has died. They were the Janitor.")
local dx = Intel.info(dex)
check(dx.role == "Janitor" and dx.confidence == "confirmed" and dx.reason == "revealed on death", "death reveal via disguise name: " .. tostring(dx.role) .. " " .. tostring(dx.reason))
local mo = newPlayer("Mo", 8300)
local ned = newPlayer("Ned", 8400)
local oli = newPlayer("Oli", 8500)
local pat = newPlayer("Pat", 8600)
local qin = newPlayer("Qin", 8700)
sys("The Mafia has killed MoD.")
sys("NedD was saved by the Doctor.")
sys("OliD was not the Mafia.")
sys("QinD is the Detective.")
TCS.MessageReceived:Fire({ Text = "PatD was the Mafia and died lol", TextSource = { UserId = 101 }, TextChannel = { Name = "RBXGeneral" } })
check(Intel.info(mo).role == nil, "role before name (actor) ignored")
check(Intel.info(ned).role == nil, "'by the Doctor' ignored")
check(Intel._test.state.recs[oli].notRoles.Mafia == true, "'was not the Mafia' -> not-role")
check(Intel.info(pat).role == nil, "player chat ignored")
local qi = Intel.info(qin)
check(qi.role == "Detective" and qi.confidence == "likely" and qi.reason == "announcement", "announcement without death -> likely")
section("status, disguise, announcements")

------------------------------------------------------------------
-- 9. Confidence tidak turun; confirmed lawan confirmed dicatat
------------------------------------------------------------------
local banana = __mk("Tool", { Name = "Banana" }, cara.Character)
cara.Character.ChildAdded:Fire(banana)
ci = Intel.info(cara)
check(ci.role == "Doctor" and ci.confidence == "confirmed", "likely evidence does not downgrade confirmed")
local bbc = __mk("BillboardGui", { Name = "RoleTag" }, cara.Character:FindFirstChild("Head"))
__mk("TextLabel", { Text = "JANITOR" }, bbc)
slow(Intel)
ci = Intel.info(cara)
check(ci.role == "Janitor" and ci.confidence == "confirmed", "confirmed conflict replaces: " .. tostring(ci.role))
check(feedHas(Intel, "Conflict: CaraD was Doctor, now Janitor"), "conflict logged")
bbc:Destroy()
section("confidence ordering")

------------------------------------------------------------------
-- 10. Notifikasi
------------------------------------------------------------------
check(notesHas("Role found: EveD is Mafia (visible tag)"), "notify on confirmed role")
check(notesHas("Role found: LiaD is Witch (likely, attribute Something)"), "notify on likely role")
check(notesHas("Role found: TessD is EVIL team"), "notify on team-only")
check(countNotes("Role found: EveD") == 1, "notify only once per role")
local before = #__notes
ctx.S.notifyRoles = false
local ray = newPlayer("Ray", 8800)
ray:SetAttribute("Role", "Mirage")
Intel.step()
check(Intel.info(ray).role == "Mirage", "Ray Mirage")
check(#__notes == before, "notifyRoles=false suppresses")
ctx.S.notifyRoles = nil
section("notifications")

------------------------------------------------------------------
-- 11. Vote
------------------------------------------------------------------
bob:SetAttribute("playerVotes", "Me")
Me:SetAttribute("talliedVotes", 3)
adv(1.1)
Intel.step()
local votes = Intel.votes()
check(votes[bob] and votes[bob].target == Me, "Bob vote target = Me")
check(votes[Me] and votes[Me].count == 3, "tallied count 3")
check(notesHas("Vote: BobD voted for you"), "vote alert")
local vn = countNotes("voted for you")
adv(1.1)
Intel.step()
check(countNotes("voted for you") == vn, "vote alert only on change")
ctx.S.voteAlert = false
dan:SetAttribute("votedFor", Me.UserId)
adv(1.1)
Intel.step()
check(Intel.votes()[dan] and Intel.votes()[dan].target == Me, "vote by UserId")
check(not notesHas("DanD voted for you"), "voteAlert=false suppresses")
ctx.S.voteAlert = nil
section("votes")

------------------------------------------------------------------
-- 12. Pisang & pintu
------------------------------------------------------------------
local bea = newPlayer("Bea", 9500)
local peel = __mk("Part", { Name = "BananaPeel", Position = Vector3.new(9503, 0, 0) }, workspace)
workspace.DescendantAdded:Fire(peel)
local be = Intel.info(bea)
check(be.role == "Saboteur" and be.confidence == "confirmed", "banana drop -> Saboteur: " .. tostring(be.role))
local ben = newPlayer("Ben", 9700)
local held = __mk("Tool", { Name = "Banana" }, ben.Character)
workspace.DescendantAdded:Fire(held)
check(Intel.info(ben).role == nil, "held banana is not a drop")
local map = __mk("Model", { Name = "Map" }, workspace)
local doorsF = __mk("Folder", { Name = "Doors" }, map)
local door = __mk("Part", { Name = "Door1", Position = Vector3.new(9000, 0, 0) }, doorsF)
door:SetAttribute("Locked", false)
local sab = newPlayer("Sab", 9005)
local jan = newPlayer("Jan", 9008)
adv(16)
Intel.step()
jan.Character:SetAttribute("Downed", true) -- downed tidak bisa ngunci
Intel.step()
door:SetAttribute("Locked", true)
Intel.step()
check(Intel.info(sab).role == nil, "door event waits for burst check")
adv(1)
Intel.step()
local sb = Intel.info(sab)
check(sb.role == "Saboteur" and sb.reason == "only one who could have locked that door", "lock -> Saboteur: " .. tostring(sb.role) .. " " .. tostring(sb.reason))
jan.Character:SetAttribute("Downed", false)
adv(2)
Intel.step()
door:SetAttribute("Locked", false)
adv(1)
Intel.step()
local jn = Intel.info(jan)
check(jn.role == "Janitor" and jn.confidence == "confirmed", "unlock -> Janitor (Saboteur excluded): " .. tostring(jn.role))
-- banyak pintu berubah barengan -> diabaikan
local d2 = __mk("Part", { Name = "Door2", Position = Vector3.new(9900, 0, 0) }, doorsF)
local d3 = __mk("Part", { Name = "Door3", Position = Vector3.new(9900, 0, 5) }, doorsF)
local d4 = __mk("Part", { Name = "Door4", Position = Vector3.new(9900, 0, 9) }, doorsF)
d2:SetAttribute("Locked", false)
d3:SetAttribute("Locked", false)
d4:SetAttribute("Locked", false)
local lone = newPlayer("Lone", 9902)
adv(16)
Intel.step()
d2:SetAttribute("Locked", true)
d3:SetAttribute("Locked", true)
d4:SetAttribute("Locked", true)
adv(1)
Intel.step()
check(Intel.info(lone).role == nil, "mass door lock ignored")
section("banana & doors")

------------------------------------------------------------------
-- 13. Mayat, channel tim, chat tim
------------------------------------------------------------------
local kim = newPlayer("Kim", 9990)
local co = __mk("Folder", { Name = "corpseOutlines" }, map)
local body = __mk("Model", { Name = "Body" }, co)
local sg = __mk("SurfaceGui", { Name = "SurfaceGui", Enabled = false }, body)
__mk("TextLabel", { Name = "playerName", Text = "KimD" }, sg)
__mk("TextLabel", { Name = "cause", Text = "died calling out the wrong role" }, sg)
local zed = newPlayer("Zed", 10100)
local yan = newPlayer("Yan", 10200)
local chans = __mk("Folder", { Name = "TextChannels" }, TCS)
local mch = __mk("TextChannel", { Name = "Mafia" }, chans)
__mk("TextSource", { Name = "Zed", UserId = zed.UserId }, mch)
local gen = __mk("TextChannel", { Name = "RBXGeneral" }, chans)
__mk("TextSource", { Name = "Yan", UserId = yan.UserId }, gen)
slow(Intel)
local km = Intel.info(kim)
check(km.role == "Harbinger" and km.confidence == "likely" and km.reason == "death cause", "corpse cause -> Harbinger likely: " .. tostring(km.role))
check(feedHas(Intel, "Body: KimD - died calling out the wrong role"), "corpse in feed")
local zi = Intel.info(zed)
check(zi.team == "EVIL" and zi.confidence == "confirmed" and zi.reason == "team channel", "team channel member -> EVIL")
check(Intel.info(yan).team == nil, "general channel says nothing")
TCS.MessageReceived:Fire({ Text = "go left", TextSource = { UserId = yan.UserId }, TextChannel = { Name = "EVIL" } })
check(Intel.info(yan).team == "EVIL" and Intel.info(yan).reason == "team chat", "team chat message -> EVIL")
section("corpses & channels")

------------------------------------------------------------------
-- 14. Role sendiri: tool, lalu layar role
------------------------------------------------------------------
local r0 = Intel.self()
check(r0 == "Mafia", "self from own Knife -> Mafia: " .. tostring(r0))
check(Intel.info(Me).confidence == "likely", "self tool evidence is likely")
local pg = __mk("PlayerGui", { Name = "PlayerGui" }, Me)
local sgui = __mk("ScreenGui", { Name = "RoleReveal" }, pg)
local fr = __mk("Frame", { Name = "Holder" }, sgui)
local tut = __mk("TextLabel", { Name = "Help", Text = "If you are the Doctor, heal people." }, fr)
slow(Intel)
check(Intel.self() == "Mafia", "tutorial 'If you are the Doctor' ignored: " .. tostring(Intel.self()))
tut:Destroy()
local lbl = __mk("TextLabel", { Name = "Title", Text = "You are the <b>Saboteur</b>!" }, fr)
slow(Intel)
local sr, steam = Intel.self()
check(sr == "Saboteur" and steam == "VEIL", "self from role screen: " .. tostring(sr) .. "/" .. tostring(steam))
check(countNotes("You are ") == 1, "self notified once per round")
lbl.Text = "You are not the Mafia"
section("self role (tools, gui)")

------------------------------------------------------------------
-- 15. Reset ronde
------------------------------------------------------------------
check(Intel.reset("test") == true, "reset returns true")
check(Intel.info(eve).role == nil, "reset clears tag evidence until the next tag scan")
slow(Intel)
check(Intel.info(eve).role == "Mafia", "tag still on character -> re-detected on next scan")
bb:Destroy()
adv(20)
Intel.reset("test2")
check(Intel.info(eve).role == nil, "reset clears evidence (Eve)")
check(Intel.info(hank).role == nil, "reset clears Harbinger call")
check(Intel.info(cara).role == "Doctor", "attribute role re-detected after reset")
check(Intel._test.state.recs[oli].notRoles.Mafia == nil, "not-roles cleared")
check(next(Intel.votes()) == nil, "votes cleared")
check(Intel.self() == "Mafia", "self role re-detected after reset (gui says 'not', knife remains)")
check(feedHas(Intel, "New round (test2)"), "reset logged")
check(Intel.info(stan).status.detained == true, "statuses survive reset")
lbl:Destroy()
section("reset")

------------------------------------------------------------------
-- 16. Feed dibatasi 60
------------------------------------------------------------------
for i = 1, 70 do
    Intel.reset("r" .. i)
end
local feed = Intel.feed()
check(#feed == 60, "feed capped at 60: " .. #feed)
check(feedHas(Intel, "New round (r70)"), "newest kept")
check(not feedHas(Intel, "New round (r1)"), "oldest dropped")
local ordered = true
for i = 2, #feed do
    if feed[i].t < feed[i - 1].t then
        ordered = false
    end
end
check(ordered, "feed newest last")
feed[1].text = "tampered"
check(Intel.feed()[1].text ~= "tampered", "feed returns a copy")
section("feed cap")

------------------------------------------------------------------
-- 17. roleController: role sendiri + teman setim + ganti ronde
------------------------------------------------------------------
local alice = P("Alice")
local currentRole = "witch"
local realRequire = ctx.Game.require
ctx.Game.require = function(path)
    if path == "client.controllers.roleController" then
        return {
            getCurrentRole = function()
                return currentRole
            end,
            teamMembers = {
                get = function(self)
                    return { team = "EVIL", members = { mafia = { alice.UserId }, witch = { Me.UserId } } }
                end,
            },
            gameStarted = {
                get = function()
                    return true
                end,
            },
        }
    end
    return nil
end
slow(Intel)
local cr, ct = Intel.self()
check(cr == "Witch" and ct == "EVIL", "self from roleController: " .. tostring(cr) .. "/" .. tostring(ct))
local al = Intel.info(alice)
check(al.role == "Mafia" and al.confidence == "confirmed" and al.reason == "teammate", "teammate from teamMembers: " .. tostring(al.reason))
-- bukti lain tidak boleh menimpa role dari controller
Me:SetAttribute("Role", "Doctor")
Intel.step()
check(Intel.self() == "Witch", "controller role locked against other evidence")
Me:SetAttribute("Role", nil)
-- role berubah -> ronde baru
adv(20)
currentRole = "doctor"
slow(Intel)
check(Intel.self() == "Doctor", "new controller role")
check(feedHas(Intel, "New round (new round)"), "role change -> new round")
ctx.Game.require = realRequire
section("roleController")

------------------------------------------------------------------
-- 18. Deteksi ronde baru: respawn massal & fase
------------------------------------------------------------------
local function countFeed(needle)
    local n = 0
    for _, e in ipairs(Intel.feed()) do
        if string.find(e.text, needle, 1, true) then
            n = n + 1
        end
    end
    return n
end
adv(20)
local nr = countFeed("New round (new round)")
local all = Players:GetPlayers()
for i = 1, math.ceil(#all * 0.6) do
    all[i].CharacterAdded:Fire(all[i].Character)
end
check(countFeed("New round (new round)") == nr + 1, "mass respawn -> reset")
adv(20)
workspace:SetAttribute("gamePhase", "Night")
adv(0.6)
Intel.step()
nr = countFeed("New round (new round)")
workspace:SetAttribute("gamePhase", "nightStart")
adv(0.6)
Intel.step()
check(countFeed("New round (new round)") == nr, "'nightStart' is mid-round, no reset")
workspace:SetAttribute("gamePhase", "Intermission")
adv(0.6)
Intel.step()
check(countFeed("New round (new round)") == nr + 1, "intermission phase -> reset")
workspace:SetAttribute("gamePhase", "Day")
adv(0.6)
Intel.step()
check(countFeed("New round (new round)") == nr + 1, "day phase does not reset")
section("round detection")

------------------------------------------------------------------
-- 19. Player keluar, stop
------------------------------------------------------------------
Players.PlayerRemoving:Fire(far)
local fi = Intel.info(far)
check(fi ~= nil and fi.role == nil and fi.status ~= nil, "removed player -> empty view")
check(Intel.info(nil) == nil, "info(nil) -> nil")
check(Intel.stop() == true, "stop returns true")
local stillOn = 0
for _, c in ipairs(__conns) do
    if c.Connected then
        stillOn = stillOn + 1
    end
end
check(stillOn == 0, "all connections disconnected: " .. stillOn)
local zack = newPlayer("Zack", 11000)
adv(3)
sys("The Harbinger thinks ZackD is a Mafia.")
sys("The Harbinger was correct")
check(Intel.info(zack).role == nil, "no evidence after stop")
Intel.step()
check(true, "step after stop does not error")
section("stop")

if #__warns > 0 then
    for _, w in ipairs(__warns) do
        print("FAIL warn: " .. w)
    end
end
print(string.format("SUMMARY intel: %d checks, %d failed, %d warnings", totalChecks, totalFails, #__warns))
