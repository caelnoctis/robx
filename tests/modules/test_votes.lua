-- Test Votes: parser updateArmPointing / talliedVotes, prioritas sumber, alert, fase, poll, cadangan Intel.
local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
local function sig(inst, name) return rawget(inst, "_signals")[name] end

local RS = ctx.ReplicatedStorage
local SN = __mk("Folder", { Name = "ServiceNetworks" }, RS)
local pointSvc = __mk("Folder", { Name = "pointingService" }, SN)
local gameSvc = __mk("Folder", { Name = "gameService" }, SN)
local armRE = __mk("RemoteEvent", { Name = "updateArmPointing" }, pointSvc)
local voteRE = __mk("RemoteEvent", { Name = "votePlayer" }, gameSvc)
local tallyRF = __mk("RemoteFunction", { Name = "talliedVotes" }, gameSvc)

local me, alice, bob, cara, dan, eve
for _, p in ipairs(__players) do
    if p.Name == "Me" then me = p elseif p.Name == "Alice" then alice = p elseif p.Name == "Bob" then bob = p
    elseif p.Name == "Cara" then cara = p elseif p.Name == "Dan" then dan = p elseif p.Name == "Eve" then eve = p end
end
alice.UserId, bob.UserId, cara.UserId, dan.UserId, eve.UserId = 5001, 5002, 5003, 5004, 5005

local tallyValue = nil
local invoked = 0
__Methods.InvokeServer = function(self, ...)
    if self == tallyRF then
        invoked = invoked + 1
        return tallyValue
    end
    return nil
end

local notes = {}
ctx.notify = function(t, x) notes[#notes + 1] = tostring(t) .. ": " .. tostring(x) end
ctx.S = { voteAlert = true }
local intelVotes = {}
ctx.Intel = { votes = function() return intelVotes end }
local phase = "Night"
ctx.Game.addPhaseProvider(function() return phase end)

local Net = NetFactory(ctx)
ctx.Net = Net
Net.start({})
local Votes = VotesFactory(ctx)
local clock = 1000
Votes._clock = function() return clock end
local found = Votes.start()
check(found.armPointing == true and found.votePlayer == true and found.talliedVotes == true, "vote remotes found")

local function one(...)
    local l = Votes.parsePointing(...)
    return l[1] and l[1][1], l[1] and l[1][2], #l
end

-- 1. bentuk payload updateArmPointing
local p1, t1 = one(alice, bob)
check(p1 == alice and t1 == bob, "pointer, target players")
p1, t1 = one(alice.Character, bob.Character:FindFirstChild("HumanoidRootPart"))
check(p1 == alice and t1 == bob, "character + body part")
p1, t1 = one(alice, Vector3.new(25, 1, 0))
check(p1 == alice and t1 == bob, "position near bob -> bob: " .. tostring(t1 and t1.Name))
p1, t1 = one(alice, CFrame.new(35, 0, 1))
check(p1 == alice and t1 == cara, "cframe near cara")
p1, t1 = one(alice, Vector3.new(500, 0, 0))
check(p1 == alice and t1 == nil, "position far from everyone -> no target")
p1, t1 = one({ player = alice, target = bob })
check(p1 == alice and t1 == bob, "table with keys")
p1, t1 = one({ alice, bob })
check(p1 == alice and t1 == bob, "array table")
p1, t1 = one("5001", 5002)
check(p1 == alice and t1 == bob, "userIds")
p1, t1 = one(alice)
check(p1 == alice and t1 == nil, "pointer only = stop")
p1, t1 = one(alice, false)
check(p1 == alice and t1 == nil, "false = stop")
local wall = __mk("Part", { Name = "Wall", Position = Vector3.new(0, 0, 0) }, workspace)
p1, t1 = one(alice, wall)
check(p1 == alice and t1 == nil, "pointing at a map part is not a vote")
local mapped = Votes.parsePointing({ [alice] = bob, [cara] = dan })
check(#mapped == 2, "map of pointers: " .. #mapped)
local _, _, n0 = one(nil)
check(n0 == 0, "nothing parsed from nil")

-- 2. event jaringan -> entri vote
sig(armRE, "OnClientEvent"):Fire(alice, bob)
check(Votes.targetOf(alice) == bob, "pointing event -> alice votes bob")
check(Votes.counts()[bob] == 1, "count from pairs")
sig(armRE, "OnClientEvent"):Fire(cara, bob)
check(Votes.counts()[bob] == 2, "two votes on bob")
sig(armRE, "OnClientEvent"):Fire(cara)
check(Votes.targetOf(cara) == nil and Votes.counts()[bob] == 1, "stop pointing clears cara")
sig(voteRE, "OnClientEvent"):Fire(dan, eve)
local tgt, src = Votes.targetOf(dan)
check(tgt == eve and src == "event", "votePlayer broadcast")

-- 3. alert kalau ada yang nge-vote kita, sekali saja
sig(armRE, "OnClientEvent"):Fire(eve, me)
sig(armRE, "OnClientEvent"):Fire(eve, me)
local alerts = 0
for _, n in ipairs(notes) do if string.find(n, "is voting for you", 1, true) then alerts = alerts + 1 end end
check(alerts == 1, "one alert when voted, got " .. alerts)
local function alertCount()
    local a = 0
    for _, n in ipairs(notes) do if string.find(n, "is voting for you", 1, true) then a = a + 1 end end
    return a
end
-- pindah lalu balik lagi dalam 20 dtk (lengan goyang): nggak toast lagi
sig(armRE, "OnClientEvent"):Fire(eve, alice)
sig(armRE, "OnClientEvent"):Fire(eve, me)
sig(armRE, "OnClientEvent"):Fire(eve)
sig(armRE, "OnClientEvent"):Fire(eve, me)
check(alertCount() == 1, "no repeat toast while the arm jitters, got " .. alertCount())
clock = clock + 25
sig(armRE, "OnClientEvent"):Fire(eve, alice)
sig(armRE, "OnClientEvent"):Fire(eve, me)
check(alertCount() == 2, "alert again after switching away and back later, got " .. alertCount())

-- 4. parser talliedVotes
local v, c = Votes.parseTally({ ["5001"] = 5002 })
check(v[alice] == bob, "tally voter -> target")
v, c = Votes.parseTally({ ["5002"] = 3 })
check(c[bob] == 3 and next(v) == nil, "tally counts")
v, c = Votes.parseTally({ ["5002"] = { 5001, "5003" } })
check(v[alice] == bob and v[cara] == bob and c[bob] == 2, "tally voter lists")
v, c = Votes.parseTally({ { voter = dan, target = alice } })
check(v[dan] == alice, "tally record list")
v, c = Votes.parseTally({})
check(next(v) == nil and next(c) == nil, "empty tally")
v, c = Votes.parseTally({ ["5001"] = { target = 5002 } })
check(v[alice] == bob and v[bob] == nil and c[alice] == nil, "record keyed by the voter is not reversed")
v, c = Votes.parseTally({ ["5002"] = { voters = { 5001, 5003 }, time = 12 } })
check(v[alice] == bob and v[cara] == bob and c[bob] == 2, "voters list field")
v, c = Votes.parseTally({ ["5001"] = 5002, ["5003"] = 4145298002 })
check(v[alice] == bob and c[cara] == nil, "unresolvable UserId is not a vote count")

-- 5. tally dari server mengalahkan pointing, pointing nggak bisa menimpa tally yang segar
Votes.applyTally({ ["5001"] = 5003 })
tgt, src = Votes.targetOf(alice)
check(tgt == cara and src == "tally", "server tally wins: " .. tostring(tgt and tgt.Name))
sig(armRE, "OnClientEvent"):Fire(alice, dan)
check(Votes.targetOf(alice) == cara, "weaker source does not override fresh tally")
check(Votes.targetOf(dan) == eve, "unrelated entries kept")
Votes.applyTally({})
check(Votes.targetOf(alice) == nil, "tally entry removed when server drops it")

-- 5b. sumber lemah yang setuju nggak boleh mengambil alih vote dari sumber kuat
Votes.reset()
local a0 = alertCount()
Votes.applyTally({ ["5005"] = 4000 })
check(Votes.targetOf(eve) == nil, "tally to an unknown local id ignored")
me.UserId = 4000
Votes.applyTally({ ["5005"] = 4000 })
check(Votes.targetOf(eve) == me and alertCount() == a0 + 1, "tally eve -> me alerts once")
sig(armRE, "OnClientEvent"):Fire(eve, me)
tgt, src = Votes.targetOf(eve)
check(tgt == me and src == "tally", "agreeing pointing keeps the tally label: " .. tostring(src))
sig(armRE, "OnClientEvent"):Fire(eve)
check(Votes.targetOf(eve) == me, "pointing stop does not delete a fresh tally vote")
Votes.applyTally({ ["5005"] = 4000 })
check(alertCount() == a0 + 1, "no second toast on the next tally poll")
sig(armRE, "OnClientEvent"):Fire(eve, me)
Votes.applyTally({})
check(Votes.targetOf(eve) == nil, "server unvote clears it even after an agreeing pointing")
sig(voteRE, "OnClientEvent"):Fire(dan, cara)
sig(armRE, "OnClientEvent"):Fire(dan, cara)
sig(armRE, "OnClientEvent"):Fire(dan)
tgt, src = Votes.targetOf(dan)
check(tgt == cara and src == "event", "votePlayer vote survives a pointing stop")
clock = clock + 31
sig(armRE, "OnClientEvent"):Fire(dan, eve)
tgt, src = Votes.targetOf(dan)
check(tgt == eve and src == "pointing", "stale stronger source can be taken over")
Votes.reset()

-- 5c. arah / CFrame lengan / beberapa titik
p1, t1 = one(alice, Vector3.new(16, 1.5, 0), Vector3.new(55, 1, 0))
check(p1 == alice and t1 == eve, "point next to the pointer's hand is ignored, far point wins: " .. tostring(t1 and t1.Name))
p1, t1 = one(alice, Vector3.new(1, 0, 0))
check(t1 == bob, "direction vector -> first player along the ray: " .. tostring(t1 and t1.Name))
p1, t1 = one(alice, CFrame.lookAt(Vector3.new(15, 1, 0), Vector3.new(35, 0, 0)))
check(t1 == bob, "arm CFrame at the hand -> ray hits bob first: " .. tostring(t1 and t1.Name))
p1, t1 = one(alice, Vector3.new(0, 0, 1))
check(t1 == nil, "direction with nobody on the ray")
-- satu-satunya titik = posisi tangan sendiri; tetangga duduk 3 stud dari situ jangan dikira target
local eveRoot = eve.Character:FindFirstChild("HumanoidRootPart")
local evePos = eveRoot.Position
eveRoot.Position = Vector3.new(19, 0, 0)
p1, t1 = one(alice, Vector3.new(16, 1.5, 0))
check(p1 == alice and t1 == nil, "hand position alone is not an aim point: " .. tostring(t1 and t1.Name))
eveRoot.Position = evePos

-- 6. cadangan attribute dari Intel
intelVotes = { [bob] = { target = dan, count = 0 } }
Votes.step()
tgt, src = Votes.targetOf(bob)
check(tgt == dan and src == "attr", "intel attribute votes merged")
intelVotes = {}
Votes.step()
check(Votes.targetOf(bob) == nil, "attr entry dropped when attribute is gone")

-- 7. poll getter talliedVotes (sering waktu voting)
phase = "Voting"
tallyValue = { ["5004"] = 5001 }
local before = invoked
Votes.step()
check(invoked > before, "tally polled during voting")
check(Votes.targetOf(dan) == alice, "polled tally applied: " .. tostring(Votes.targetOf(dan) and Votes.targetOf(dan).Name))
check(#Votes.list() >= 1, "list has entries")

-- 8. voting selesai -> hasil terakhir disimpan, data aktif dibersihkan
phase = "Night"
Votes.step()
check(Votes.last ~= nil and #Votes.last.list >= 1, "last voting kept")
check(next(Votes.get()) == nil, "active votes cleared after voting")

-- 8b. daftar kosong duluan (lengan turun / tally {}) sebelum fase berubah: hasilnya tetap tersimpan
Votes.clearAll()
check(Votes.last == nil, "clearAll forgets the last voting")
tallyValue = {}
phase = "Voting"
Votes.step()
sig(armRE, "OnClientEvent"):Fire(alice, bob)
sig(armRE, "OnClientEvent"):Fire(cara, bob)
Votes.step()
sig(armRE, "OnClientEvent"):Fire(alice)
sig(armRE, "OnClientEvent"):Fire(cara)
Votes.step()
phase = "Night"
Votes.step()
check(Votes.last ~= nil and #Votes.last.list == 2 and Votes.last.counts[bob] == 2, "last voting kept when arms drop before the phase change")
-- lengan turun satu-satu (beda step) tetap tercatat lengkap
Votes.clearAll()
phase = "Voting"
Votes.step()
sig(armRE, "OnClientEvent"):Fire(alice, bob)
sig(armRE, "OnClientEvent"):Fire(cara, bob)
sig(armRE, "OnClientEvent"):Fire(dan, eve)
Votes.step()
clock = clock + 0.3
sig(armRE, "OnClientEvent"):Fire(alice)
Votes.step()
clock = clock + 0.3
sig(armRE, "OnClientEvent"):Fire(cara)
Votes.step()
clock = clock + 0.3
sig(armRE, "OnClientEvent"):Fire(dan)
Votes.step()
check(Votes.last ~= nil and #Votes.last.list == 3, "arms dropped one by one: all 3 votes kept, got " .. (Votes.last and #Votes.last.list or 0))
-- orang yang memang batal nge-vote di tengah voting nggak ikut di hasil akhir
Votes.clearAll()
Votes.step()
sig(armRE, "OnClientEvent"):Fire(alice, bob)
sig(armRE, "OnClientEvent"):Fire(cara, bob)
Votes.step()
sig(armRE, "OnClientEvent"):Fire(alice)
Votes.step()
clock = clock + 2
Votes.step()
phase = "Night"
Votes.step()
check(Votes.last ~= nil and #Votes.last.list == 1 and Votes.last.list[1].voter == cara, "a real unvote is not in the final result")

-- 8c. nama fase yang nggak dikenali: tetap disimpan, entri event kedaluwarsa
Votes.clearAll()
phase = "Meeting"
sig(voteRE, "OnClientEvent"):Fire(alice, cara)
Votes.step()
sig(voteRE, "OnClientEvent"):Fire(alice)
Votes.step()
check(Votes.last ~= nil and #Votes.last.list == 1, "snapshot does not depend on the phase name")
sig(voteRE, "OnClientEvent"):Fire(dan, cara)
clock = clock + 91
Votes.step()
check(Votes.targetOf(dan) == nil, "event votes expire without a stop event")

-- 8d. polling: siang hari cepat, getter yang ditandai mati dicoba lagi
local b2 = invoked
clock = clock + 3
Votes.step()
check(invoked > b2, "tally polled every 2.5 s outside night")
Net.dead[tallyRF] = true
b2 = invoked
clock = clock + 3
Votes.step()
check(invoked == b2, "dead getter skipped for a while")
clock = clock + 31
Votes.step()
check(invoked > b2 and not Net.dead[tallyRF], "dead getter retried after a back-off")
phase = "Night"
Votes.step()

-- 9. pemain keluar
sig(armRE, "OnClientEvent"):Fire(alice, bob)
sig(ctx.Players, "PlayerRemoving"):Fire(bob)
check(Votes.targetOf(alice) == nil, "votes on a leaving player removed")

for _, w in ipairs(__warns) do fails[#fails + 1] = "WARN " .. w end
if #fails == 0 then print("PASS votes") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
