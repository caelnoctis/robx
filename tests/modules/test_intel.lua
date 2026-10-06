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

-- chat lama (legacy) harus ada sebelum start() supaya di-hook
local legacyEv = __mk("Folder", { Name = "DefaultChatSystemChatEvents" }, RS)
local legacyDone = __mk("RemoteEvent", { Name = "OnMessageDoneFiltering" }, legacyEv)

local Intel = IntelFactory(ctx)
Intel._test.setClock(function()
    return T
end)
local function countFeed(needle)
    local n = 0
    for _, e in ipairs(Intel.feed()) do
        if string.find(e.text, needle, 1, true) then
            n = n + 1
        end
    end
    return n
end
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
check(di.role == "Civilian" and di.team == "TOWN" and di.confidence == "confirmed", "Dan StringValue Role=Civilian -> role Civilian (a real role in this game), team TOWN")
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
check(countNotes("Role found: AceD") == 1, "likely -> confirmed upgrade notifies once: " .. countNotes("Role found: AceD"))
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
check(qi.role == nil, "strict mode: announcement without death is not used")
ctx.S.showGuesses = true
sys("QinD is the Detective now.")
local qi2 = Intel.info(qin)
check(qi2.role == "Detective" and qi2.confidence == "likely" and qi2.reason == "announcement", "showGuesses: announcement without death -> likely")
ctx.S.showGuesses = nil
-- chat pemain lewat jalur sistem ("Name: ...") bukan pengumuman
sys("QinD: OliD is the Witch")
check(Intel.info(oli).role == nil, "player chat via system channel ignored")
section("status, disguise, announcements")

------------------------------------------------------------------
-- 9. Confidence tidak turun; confirmed lawan confirmed dicatat
------------------------------------------------------------------
do
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
end

------------------------------------------------------------------
-- 10. Notifikasi
------------------------------------------------------------------
do
    check(notesHas("Role found: EveD is Mafia (visible tag)"), "notify on confirmed role")
    check(not notesHas("Role found: LiaD is Witch (likely, attribute Something)"), "strict mode: no notification for likely role")
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
end

------------------------------------------------------------------
-- 11. Vote
------------------------------------------------------------------
do
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
end

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
-- koneksi pintu disimpan per pintu (bukan di St.conns) dan diputus waktu pintunya hilang
do
    local stDoors = Intel._test.state
    local dconn = (stDoors.doorConns or {})[d2]
    check(dconn ~= nil and dconn.Connected == true, "door hook stored per door")
    local connsBefore = #stDoors.conns
    d2:Destroy()
    adv(16)
    Intel.step()
    check(dconn ~= nil and dconn.Connected == false, "removed door's hook disconnected")
    check((stDoors.doorConns or {})[d2] == nil and stDoors.doors[d2] == nil, "removed door forgotten")
    check(#stDoors.conns == connsBefore, "door hooks do not pile up in St.conns")
end
section("banana & doors")

------------------------------------------------------------------
-- 13. Mayat, channel tim, chat tim
------------------------------------------------------------------
do
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
end

------------------------------------------------------------------
-- 14. Role sendiri: tool, lalu layar role
------------------------------------------------------------------
local r0 = Intel.self()
check(r0 == "Mafia", "self from own Knife -> Mafia: " .. tostring(r0))
check(Intel.info(Me).confidence == "likely", "self tool evidence is likely")
local pg = __mk("PlayerGui", { Name = "PlayerGui" }, Me)
-- GUI baru masuk -> Roblox nembak PlayerGui.DescendantAdded (scan role sendiri dijadwal ulang dari situ)
local function addGui(class, props, parent)
    local inst = __mk(class, props, parent)
    pg.DescendantAdded:Fire(inst)
    return inst
end
local sgui = addGui("ScreenGui", { Name = "RoleReveal" }, pg)
local fr = addGui("Frame", { Name = "Holder" }, sgui)
local tut = addGui("TextLabel", { Name = "Help", Text = "If you are the Doctor, heal people." }, fr)
slow(Intel)
check(Intel.self() == "Mafia", "tutorial 'If you are the Doctor' ignored: " .. tostring(Intel.self()))
tut:Destroy()
local lbl = addGui("TextLabel", { Name = "Title", Text = "You are the <b>Saboteur</b>!" }, fr)
slow(Intel)
local sr, steam = Intel.self()
check(sr == "Saboteur" and steam == "VEIL", "self from role screen: " .. tostring(sr) .. "/" .. tostring(steam))
check(countNotes("Detected your role") == 1, "self notified once per round")
check(countNotes("You are ") == 0, "self toast is not worded like a role screen")
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
do
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
end

------------------------------------------------------------------
-- 17. roleController: role sendiri + teman setim + ganti ronde
------------------------------------------------------------------
local alice = P("Alice")
local currentRole = "witch"
local roleCalls = 0
local fieldRole = nil
local realRequire = ctx.Game.require
ctx.Game.require = function(path)
    if path == "client.controllers.roleController" then
        return {
            currentRole = fieldRole,
            getCurrentRole = function()
                roleCalls = roleCalls + 1
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
check(roleCalls == 1, "first probe stops at the first signature that gives a role: " .. roleCalls)
local al = Intel.info(alice)
check(al.role == "Mafia" and al.confidence == "confirmed" and al.reason == "teammate", "teammate from teamMembers: " .. tostring(al.reason))
slow(Intel)
check(roleCalls == 1 and Intel.self() == "Witch", "role function not re-called every 2 s: " .. roleCalls)
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
check(roleCalls == 2, "remembered signature -> one call per check: " .. roleCalls)
check(feedHas(Intel, "New round (new round)"), "role change -> new round")
-- field role ada -> fungsi tidak dipanggil sama sekali
fieldRole = "doctor"
adv(20)
slow(Intel)
adv(20)
slow(Intel)
check(roleCalls == 2 and Intel.self() == "Doctor", "role field read first, function skipped: " .. roleCalls)
ctx.Game.require = realRequire
section("roleController")

------------------------------------------------------------------
-- 18. Deteksi ronde baru: respawn massal & fase
------------------------------------------------------------------
do
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
end

------------------------------------------------------------------
-- 20. Tembakan saat fase tidak diketahui: lihat senjatanya, jangan langsung "Mafia confirmed"
------------------------------------------------------------------
do
    workspace:SetAttribute("gamePhase", nil)
    adv(20)
    local vigP = newPlayer("Vig", 20000)
    local revolver = __mk("Tool", { Name = "Revolver" }, vigP.Character)
    vigP.Character.ChildAdded:Fire(revolver)
    local vigV = newPlayer("Vgv", 20010)
    Intel.step()
    play(vigP, "gunShot", 81001)
    adv(0.5)
    vigV.Character:SetAttribute("Downed", true)
    local vgi = Intel.info(vigP)
    check(vgi.role == "Vigilante" and vgi.confidence == "likely", "unknown-phase revolver shot that downs someone -> Vigilante likely: " .. tostring(vgi.role) .. "/" .. tostring(vgi.confidence))
    check(feedHas(Intel, "VigD downed VgvD"), "unknown-phase shot still in kill feed")
    local gloP = newPlayer("Glo", 21000)
    local glock = __mk("Tool", { Name = "Glock" }, gloP.Character)
    gloP.Character.ChildAdded:Fire(glock)
    local gloV = newPlayer("Glv", 21010)
    adv(6)
    play(gloP, "gunShot", 81001)
    adv(0.5)
    gloV.Character:FindFirstChildOfClass("Humanoid").Health = 0
    Intel.step()
    local gli = Intel.info(gloP)
    check(gli.role == "Mafia" and gli.confidence == "likely", "unknown-phase Glock kill -> Mafia likely, not confirmed: " .. tostring(gli.confidence))
    local nwP = newPlayer("Nwp", 22000)
    local nwV = newPlayer("Nwv", 22010)
    adv(6)
    play(nwP, "gunShot", 81001)
    adv(0.5)
    nwV.Character:SetAttribute("Downed", true)
    local nwi = Intel.info(nwP)
    check(nwi.confidence == "suspect" and nwi.candidates and nwi.candidates.Mafia and nwi.candidates.Vigilante, "unknown-phase shot, no gun seen -> Mafia/Vigilante suspect")
    section("unknown-phase gunshot")
end

------------------------------------------------------------------
-- 21. Animasi tool dinilai dari nama animasinya sendiri
------------------------------------------------------------------
do
    workspace:SetAttribute("gamePhase", "Night")
    local rvp = newPlayer("Rvp", 23000)
    local rvt = __mk("Tool", { Name = "Revolver" }, rvp.Character)
    __mk("Animation", { Name = "Inspect", AnimationId = "rbxassetid://99001" }, rvt)
    rvp.Character.ChildAdded:Fire(rvt)
    play(rvp, "Animation", 99001)
    local rvi = Intel.info(rvp)
    check(rvi.role ~= "Mafia" and rvi.confidence ~= "confirmed", "revolver 'Inspect' anim at night is not a gunshot: " .. tostring(rvi.role) .. "/" .. tostring(rvi.reason))
    local knp = newPlayer("Knp", 23500)
    local knt = __mk("Tool", { Name = "Knife" }, knp.Character)
    __mk("Animation", { Name = "Attack", AnimationId = "rbxassetid://99002" }, knt)
    knp.Character.ChildAdded:Fire(knt)
    play(knp, "Animation", 99002)
    local kni = Intel.info(knp)
    check(kni.role == "Mafia" and kni.confidence == "confirmed" and kni.reason == "swung a knife at night", "generic 'Attack' anim of a knife -> stab: " .. tostring(kni.reason))
    workspace:SetAttribute("gamePhase", nil)
    section("tool animations")
end

------------------------------------------------------------------
-- 22. Status: nilai truthy menang, badan hilang, mati tetap mati
------------------------------------------------------------------
do
    local sta = newPlayer("Sta", 28000)
    sta:SetAttribute("Downed", false)
    sta.Character:SetAttribute("Downed", true)
    Intel.step()
    check(Intel.info(sta).status.downed == true, "Player Downed=false does not hide Character Downed=true")
    local bod = newPlayer("Bod", 28500)
    local bdn = newPlayer("Bdn", 28505)
    Intel.step()
    bod.Character:SetAttribute("Downed", true)
    Intel.step()
    bod.Character = nil
    Intel.step()
    adv(0.5)
    Intel.step()
    check(not feedHas(Intel, "BodD got back up"), "body removed while downed is not a revive")
    check(Intel.info(bod).status.downed == true, "status carried over while the character is gone")
    check(Intel.info(bdn).role ~= "Doctor", "no Doctor credit for a removed body")
    local ded = newPlayer("Ded", 29000)
    local dsv = newPlayer("Dsv", 29005)
    Intel.step()
    ded.Character:FindFirstChildOfClass("Humanoid").Health = 0
    Intel.step()
    check(feedHas(Intel, "DedD died"), "death logged")
    adv(6)
    local spare = __buildPlayer("SpareBody", { x = 29003 })
    local newChar = spare.Character
    __mk("Animator", nil, newChar:FindFirstChildOfClass("Humanoid"))
    ded.Character = newChar
    ded.CharacterAdded:Fire(newChar)
    Intel.step()
    check(Intel.info(ded).status.dead == true, "died this round -> still dead with a fresh character")
    dsv.Character:SetAttribute("witchSilenced", true)
    local dei = Intel.info(ded)
    check(dei.role ~= "Witch" and not (dei.candidates and dei.candidates.Witch), "dead player is not a Witch candidate")
    section("status edge cases")
end

------------------------------------------------------------------
-- 23. Kandidat terakhir; player yang keluar
------------------------------------------------------------------
do
    adv(20)
    Intel.reset("cand")
    local wc = newPlayer("Wc", 24000)
    local wd = newPlayer("Wd", 24010)
    local vcx = newPlayer("Vcx", 24005)
    Intel.step()
    vcx.Character:SetAttribute("witchSilenced", true)
    local wci0, wdi0 = Intel.info(wc), Intel.info(wd)
    check(wci0.candidates and wci0.candidates.Witch and wdi0.candidates and wdi0.candidates.Witch, "silence -> two Witch suspects")
    adv(4)
    sys("The Harbinger thinks WdD is a Witch.")
    sys("The Harbinger was incorrect.")
    local wci = Intel.info(wc)
    check(wci.role == "Witch" and wci.confidence == "confirmed" and wci.reason == "last candidate left", "ruled-out candidate leaves the last one confirmed: " .. tostring(wci.role) .. " " .. tostring(wci.reason))
    adv(9)
    Intel.step()
    local function leave(p)
        Players.PlayerRemoving:Fire(p)
        local list = rawget(Players, "_players")
        for k, q in ipairs(list) do
            if q == p then
                table.remove(list, k)
                break
            end
        end
    end
    adv(20)
    Intel.reset("cand2")
    local xa = newPlayer("Xa", 25000)
    local xb = newPlayer("Xb", 25010)
    local xv = newPlayer("Xv", 25005)
    Intel.step()
    xv.Character:SetAttribute("witchSilenced", true)
    leave(xb)
    local xai = Intel.info(xa)
    check(xai.role == "Witch" and xai.reason == "last candidate left", "candidate leaving -> last one confirmed: " .. tostring(xai.role))
    -- set kandidat yang ditangkap sebelum seseorang keluar tidak boleh mengonfirmasi dia
    local rvv = newPlayer("Rvv", 26000)
    local dlv = newPlayer("Dlv", 26005)
    Intel.step()
    rvv.Character:SetAttribute("Downed", true)
    rvv.Character:SetAttribute("Downed", false)
    leave(dlv)
    adv(0.5)
    Intel.step()
    check(Intel._test.state.recs[dlv] == nil, "departed player gets no new record")
    check(Intel.info(dlv).role == nil, "departed player not confirmed Doctor")
    check(not notesHas("DlvD is Doctor"), "no notification for a departed player")
    section("candidates")
end

------------------------------------------------------------------
-- 24. Harbinger: yang mati tapi sudah pasti role lain / dibunuh orang dilewati
------------------------------------------------------------------
do
    adv(20)
    Intel.reset("harb2")
    local mafP = newPlayer("Maf", 27000)
    mafP:SetAttribute("Role", "Mafia")
    local tgtP = newPlayer("Tgt", 27100)
    local hrbP = newPlayer("Hrb", 27200)
    Intel.step()
    check(Intel.info(mafP).role == "Mafia", "Maf confirmed Mafia by attribute")
    adv(4)
    sys("The Harbinger thinks TgtD is a Witch.")
    sys("The Harbinger was incorrect.")
    adv(0.5)
    mafP.Character:FindFirstChildOfClass("Humanoid").Health = 0
    Intel.step()
    check(Intel.info(mafP).role == "Mafia", "confirmed Mafia dying in the window stays Mafia: " .. tostring(Intel.info(mafP).role))
    adv(0.5)
    hrbP.Character:FindFirstChildOfClass("Humanoid").Health = 0
    Intel.step()
    local hbi = Intel.info(hrbP)
    check(hbi.role == "Harbinger" and hbi.confidence == "confirmed", "watch stays open for the real Harbinger: " .. tostring(hbi.role))
    check(Intel.info(tgtP).role == nil, "called target untouched")
    adv(9)
    Intel.step()
    workspace:SetAttribute("gamePhase", "Night")
    local stb = newPlayer("Stb", 27500)
    local stv = newPlayer("Stv", 27505)
    local hb2 = newPlayer("Hb2", 27900)
    Intel.step()
    adv(4)
    sys("The Harbinger thinks StbD is a Doctor.")
    sys("The Harbinger was incorrect.")
    play(stb, "KnifeSwing", 70001)
    adv(0.5)
    stv.Character:FindFirstChildOfClass("Humanoid").Health = 0
    Intel.step()
    check(Intel.info(stv).role ~= "Harbinger", "stabbed victim is not the Harbinger")
    adv(0.5)
    hb2:SetAttribute("Dead", true)
    Intel.step()
    check(Intel.info(hb2).role == "Harbinger", "real Harbinger found after a stab death")
    workspace:SetAttribute("gamePhase", nil)
    adv(9)
    Intel.step()
    section("harbinger eligibility")
end

------------------------------------------------------------------
-- 25. Tag di atas kepala: nametag & label umum bukan role / tim
------------------------------------------------------------------
do
    local wn = newPlayer("xX_W_Xx", 30000)
    wn.DisplayName = "Witch"
    local nbb = __mk("BillboardGui", { Name = "NameTag" }, wn.Character:FindFirstChild("Head"))
    __mk("TextLabel", { Name = "DisplayName", Text = "Witch" }, nbb)
    local inno = newPlayer("Inno", 30500)
    local ib = __mk("BillboardGui", { Name = "Status" }, inno.Character:FindFirstChild("Head"))
    __mk("TextLabel", { Text = "Innocent" }, ib)
    slow(Intel)
    local wni = Intel.info(wn)
    check(wni.role == nil and wni.confidence == nil, "nametag showing a role-word display name is not a role tag: " .. tostring(wni.role))
    check(Intel.info(inno).team == nil, "generic 'Innocent' label is not a team tag")
    -- label "[MAFIA]" yang kelihatan di hampir semua karakter = template, bukan bukti
    local fresh = newPlayer("Fresh", 31500)
    local tmplV = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local head = p.Character and p.Character:FindFirstChild("Head")
        if head then
            local g = __mk("BillboardGui", { Name = "Overhead" }, head)
            __mk("TextLabel", { Text = "[MAFIA]" }, g)
            tmplV[#tmplV + 1] = g
        end
    end
    slow(Intel)
    check(Intel.info(fresh).role ~= "Mafia", "visible [MAFIA] on most characters is a template")
    for _, g in ipairs(tmplV) do
        g:Destroy()
    end
    nbb:Destroy()
    ib:Destroy()
    section("tag false positives")
end

------------------------------------------------------------------
-- 26. Attribute pilihan / riwayat role bukan role ronde ini
------------------------------------------------------------------
do
    local pre = newPlayer("Pre", 32500)
    pre:SetAttribute("SelectedRole", "Doctor")
    pre:SetAttribute("PreviousRole", "Mafia")
    pre:SetAttribute("EquippedRoleSkin", "Witch")
    pre:SetAttribute("Mood", "Good")
    Intel.step()
    check(Intel.info(pre).role == nil and Intel.info(pre).team == nil, "selected / previous / skin role attributes ignored")
    pre:SetAttribute("PlayerClass", "Janitor")
    Intel.step()
    local pri = Intel.info(pre)
    check(pri.role == "Janitor" and pri.confidence == "likely", "non-exact roleish attribute -> likely only: " .. tostring(pri.confidence))
    section("attribute names")
end

------------------------------------------------------------------
-- 27. Pisang dipegang dulu, lalu instance yang sama dijatuhkan
------------------------------------------------------------------
do
    adv(20)
    Intel.reset("banana")
    local sbt = newPlayer("Sbt", 33500)
    local btool = __mk("Tool", { Name = "Banana" }, sbt.Character)
    __mk("Part", { Name = "Handle", Position = Vector3.new(33501, 0, 0) }, btool)
    sbt.Character.ChildAdded:Fire(btool)
    workspace.DescendantAdded:Fire(btool)
    local bdBefore = countFeed("A banana was dropped")
    check(Intel.info(sbt).confidence == "likely", "held banana -> likely only")
    adv(3)
    btool.Parent = workspace
    workspace.DescendantAdded:Fire(btool)
    local sbi = Intel.info(sbt)
    check(sbi.role == "Saboteur" and sbi.confidence == "confirmed", "same banana instance dropped later -> Saboteur: " .. tostring(sbi.confidence))
    check(countFeed("A banana was dropped") == bdBefore + 1, "drop logged once")
    section("banana drop after holding")
end

------------------------------------------------------------------
-- 28. Chat lama (legacy): pengumuman dari speaker non-player dipakai
------------------------------------------------------------------
do
    local lhk = newPlayer("Lhk", 34000)
    Intel.step()
    adv(3)
    legacyDone.OnClientEvent:Fire({ Message = "The Harbinger thinks LhkD is a Janitor.", FromSpeaker = "Game", SpeakerUserId = 0, MessageType = "Message", OriginalChannel = "All" }, "All")
    legacyDone.OnClientEvent:Fire({ Message = "The Harbinger was correct!", FromSpeaker = "Game", SpeakerUserId = 0, MessageType = "Message", OriginalChannel = "All" }, "All")
    local lhi = Intel.info(lhk)
    check(lhi.role == "Janitor" and lhi.confidence == "confirmed" and lhi.reason == "Harbinger call", "legacy-chat system announcement used: " .. tostring(lhi.role))
    local lpl = newPlayer("Lpl", 34500)
    legacyDone.OnClientEvent:Fire({ Message = "LplD was the Mafia and died", FromSpeaker = "Bob", SpeakerUserId = bob.UserId, MessageType = "Message", OriginalChannel = "All" }, "All")
    check(Intel.info(lpl).role == nil, "legacy chat from a player is not an announcement")
    section("legacy chat")
end

------------------------------------------------------------------
-- 29. Role sendiri dari layar: yang bukan layar role diabaikan, role dibawa lewat reset
------------------------------------------------------------------
do
    sgui:Destroy()
    adv(20)
    Intel.reset("knife check")
    check(Intel.self() == "Mafia" and Intel.info(Me).reason == "carries a knife", "knife still carried -> self Mafia (likely): " .. tostring(Intel.self()) .. "/" .. tostring(Intel.info(Me).reason))
    local myKnife = Me:FindFirstChildOfClass("Backpack"):FindFirstChild("Knife")
    if myKnife then
        myKnife:Destroy()
    end
    local lastNote = nil
    local realNotify = ctx.notify
    ctx.notify = function(t, x, ...)
        if type(x) == "string" and string.find(x, "your role", 1, true) then
            lastNote = { title = t, text = x } -- toast tentang diri sendiri saja
        end
        return realNotify(t, x, ...)
    end
    adv(20)
    Intel.reset("self tests")
    check(Intel.self() == nil, "tool-derived self role not carried over once the tool is gone: " .. tostring(Intel.self()))
    local intro = addGui("ScreenGui", { Name = "Intro" }, pg)
    addGui("TextLabel", { Name = "Title", Text = "YOU ARE THE JANITOR" }, intro)
    slow(Intel)
    check(Intel.self() == "Janitor" and Intel.info(Me).confidence == "confirmed", "explicit reveal -> self Janitor: " .. tostring(Intel.self()))
    check(lastNote ~= nil and string.find(lastNote.text, "Detected your role: Janitor", 1, true) ~= nil, "self notification wording")
    ctx.notify = realNotify
    intro:Destroy()
    slow(Intel)
    check(Intel.self() == "Janitor", "role kept after the reveal screen is gone")
    -- respawn massal (dipindah ke map) -> reset, role sendiri tetap ada
    adv(20)
    local nrBefore = countFeed("New round (new round)")
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            p.CharacterAdded:Fire(p.Character)
        end
    end
    check(countFeed("New round (new round)") == nrBefore + 1, "mass respawn reset happened")
    check(Intel.self() == "Janitor" and Intel.info(Me).confidence == "likely", "self role kept (as likely) across reset: " .. tostring(Intel.self()))
    slow(Intel)
    check(Intel.self() == "Janitor", "kept role survives the next scan")
    check(countNotes("Detected your role: Janitor") == 1, "kept role is not re-announced")
    -- chat / teks yang tidak diawali "you are"
    local chatGui = addGui("ScreenGui", { Name = "CustomChat" }, pg)
    local msgs = addGui("Frame", { Name = "Messages" }, chatGui)
    addGui("TextLabel", { Name = "Line", Text = "Bob: you're mafia lol" }, msgs)
    addGui("TextLabel", { Name = "Body", Text = "you're mafia lol" }, msgs)
    local hud = addGui("ScreenGui", { Name = "HUD" }, pg)
    addGui("TextLabel", { Name = "Tip", Text = "Bob says you are the Mafia" }, hud)
    slow(Intel)
    check(Intel.self() == "Janitor", "chat / non-anchored 'you are' text ignored: " .. tostring(Intel.self()))
    -- role orang lain di GUI: scoreboard, kartu vote, billboard teman, daftar role, username berisi "role"
    local mainUi = addGui("ScreenGui", { Name = "MainUI" }, pg)
    local board = addGui("Frame", { Name = "Scoreboard" }, mainUi)
    local row = addGui("Frame", { Name = "Alice" }, board)
    addGui("TextLabel", { Name = "PlayerName", Text = "AliceD" }, row)
    addGui("TextLabel", { Name = "RoleLabel", Text = "Doctor" }, row)
    local voteUi = addGui("ScreenGui", { Name = "RoleVoting" }, pg)
    local card = addGui("Frame", { Name = "PlayerCard" }, voteUi)
    addGui("TextLabel", { Name = "Name", Text = "AliceD" }, card)
    addGui("TextLabel", { Name = "Status", Text = "Mafia" }, card)
    local mateBb = addGui("BillboardGui", { Name = "TeammateRole" }, pg)
    addGui("TextLabel", { Name = "Label", Text = "Mafia" }, mateBb)
    local guide = addGui("ScreenGui", { Name = "RolesGuide" }, pg)
    addGui("TextLabel", { Text = "Mafia" }, guide)
    addGui("TextLabel", { Text = "Doctor" }, guide)
    addGui("TextLabel", { Text = "Witch" }, guide)
    local myName = Me.Name
    Me.Name = "Caroleena"
    local over = addGui("BillboardGui", { Name = "Overhead" }, pg)
    addGui("TextLabel", { Text = "[DOCTOR]" }, over)
    slow(Intel)
    check(Intel.self() == "Janitor", "other players' roles in GUIs are not our role: " .. tostring(Intel.self()))
    Me.Name = myName
    -- toast "Role found" kita sendiri yang nyasar ke PlayerGui
    local noteTitle = lastNote and lastNote.title or "Role found"
    local noteText = lastNote and lastNote.text or "Detected your role: Janitor (role screen)"
    local toastGui = addGui("ScreenGui", { Name = "Toasts" }, pg)
    addGui("TextLabel", { Name = "Body", Text = string.format("<b>%s</b>\n%s", noteTitle, (string.gsub(noteText, "Janitor", "Mafia"))) }, toastGui)
    slow(Intel)
    check(Intel.self() == "Janitor", "own 'Role found' toast is not read as a role screen")
    -- ctx.isOwnGui dari integrator dihormati
    local ownGui = addGui("ScreenGui", { Name = "NoctisUI" }, pg)
    addGui("TextLabel", { Text = "You are the Mafia" }, ownGui)
    ctx.isOwnGui = function(i)
        return i:IsDescendantOf(ownGui)
    end
    slow(Intel)
    check(Intel.self() == "Janitor", "labels inside ctx.isOwnGui are skipped")
    ctx.isOwnGui = nil
    ownGui:Destroy()
    -- scan PlayerGui mundur kalau nggak ada yang berubah, balik cepat kalau ada GUI baru
    local gs = Intel._test.state.gui or {}
    for _ = 1, 6 do
        slow(Intel)
    end
    check(gs.gap == 8, "self GUI scan backs off when nothing changes: " .. tostring(gs.gap))
    -- layar role beneran: "YOU ARE..." + label role terpisah
    local reveal = addGui("ScreenGui", { Name = "MainHud" }, pg)
    addGui("TextLabel", { Name = "Top", Text = "YOU ARE..." }, reveal)
    addGui("TextLabel", { Name = "Big", Text = "<b>WITCH</b>" }, reveal)
    check(gs.gap == 2 and gs.next == 0, "new GUI resets the scan schedule")
    slow(Intel)
    local wr, wt = Intel.self()
    check(wr == "Witch" and wt == "EVIL" and Intel.info(Me).confidence == "confirmed", "split 'YOU ARE' + role label -> self Witch: " .. tostring(wr))
    -- layar berikutnya yang eksplisit tetap bisa mengoreksi (scan jalan terus selama role dari layar)
    local popup = addGui("ScreenGui", { Name = "Popup" }, pg)
    addGui("TextLabel", { Text = "You are now the Doctor." }, popup)
    slow(Intel)
    check(Intel.self() == "Doctor", "later explicit reveal corrects a screen-derived role: " .. tostring(Intel.self()))
    for _, g in ipairs({ chatGui, hud, mainUi, voteUi, mateBb, guide, over, toastGui, reveal, popup }) do
        g:Destroy()
    end
    -- layar lama yang sudah di-fade (TextTransparency 1, Visible tetap true) tidak dibaca lagi
    local fadedGui = addGui("ScreenGui", { Name = "OldReveal" }, pg)
    addGui("TextLabel", { Text = "You are the Witch", TextTransparency = 1 }, fadedGui)
    slow(Intel)
    check(Intel.self() == "Doctor", "faded-out reveal text ignored: " .. tostring(Intel.self()))
    fadedGui:Destroy()
    -- layar Mafia yang menyebut partner: "YOU ARE" + "MAFIA" + nama partner tetap diterima
    local mreveal = addGui("ScreenGui", { Name = "Reveal2" }, pg)
    addGui("TextLabel", { Text = "YOU ARE" }, mreveal)
    addGui("TextLabel", { Text = "MAFIA" }, mreveal)
    addGui("TextLabel", { Text = "Partner: AliceD" }, mreveal)
    slow(Intel)
    check(Intel.self() == "Mafia", "'YOU ARE' + role + partner name -> self Mafia: " .. tostring(Intel.self()))
    mreveal:Destroy()
    section("self role screen")
end

------------------------------------------------------------------
-- 30. Jalur event tanpa require; miss globalAttr di-cache
------------------------------------------------------------------
do
    local stc = Intel._test.state
    local cfg = stc.cfg or {}
    check(cfg.maxSilenceDistance == 20 and cfg.maxSabotageDistance == 15 and cfg.maxCleanupDistance == 15, "config radii cached by the scan thread")
    local sil = newPlayer("Sil", 35000)
    Intel.step()
    local cfgCalls = 0
    local realCfg = ctx.Game.configNumber
    ctx.Game.configNumber = function(...)
        cfgCalls = cfgCalls + 1
        return realCfg(...)
    end
    sil.Character:SetAttribute("witchSilenced", true)
    check(cfgCalls == 0, "silence event does not call Game.configNumber: " .. cfgCalls)
    ctx.Game.configNumber = realCfg
    check((stc.gmiss or {}).talliedVotes ~= nil, "missing global attribute is remembered")
    local gaCalls = 0
    local realGA = ctx.Game.globalAttr
    ctx.Game.globalAttr = function(...)
        gaCalls = gaCalls + 1
        return realGA(...)
    end
    for _ = 1, 8 do
        adv(0.6)
        Intel.step()
    end
    check(gaCalls <= 4, "global attribute misses are backed off: " .. gaCalls)
    ctx.Game.globalAttr = realGA
    local rq = (stc.req or {})["client.controllers.roleController"]
    check(rq ~= nil and rq.miss > 0 and rq.next > T, "missing roleController lookups are backed off")
    section("hot paths")
end

------------------------------------------------------------------
-- 19. Player keluar, stop
------------------------------------------------------------------
do
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
end

if #__warns > 0 then
    for _, w in ipairs(__warns) do
        print("FAIL warn: " .. w)
    end
end
print(string.format("SUMMARY intel: %d checks, %d failed, %d warnings", totalChecks, totalFails, #__warns))
