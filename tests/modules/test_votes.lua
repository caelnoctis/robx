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
sig(armRE, "OnClientEvent"):Fire(eve, alice)
sig(armRE, "OnClientEvent"):Fire(eve, me)
alerts = 0
for _, n in ipairs(notes) do if string.find(n, "is voting for you", 1, true) then alerts = alerts + 1 end end
check(alerts == 2, "alert again after switching away and back")

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

-- 5. tally dari server mengalahkan pointing, pointing nggak bisa menimpa tally yang segar
Votes.applyTally({ ["5001"] = 5003 })
tgt, src = Votes.targetOf(alice)
check(tgt == cara and src == "tally", "server tally wins: " .. tostring(tgt and tgt.Name))
sig(armRE, "OnClientEvent"):Fire(alice, dan)
check(Votes.targetOf(alice) == cara, "weaker source does not override fresh tally")
check(Votes.targetOf(dan) == eve, "unrelated entries kept")
Votes.applyTally({})
check(Votes.targetOf(alice) == nil, "tally entry removed when server drops it")

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

-- 9. pemain keluar
sig(armRE, "OnClientEvent"):Fire(alice, bob)
sig(ctx.Players, "PlayerRemoving"):Fire(bob)
check(Votes.targetOf(alice) == nil, "votes on a leaving player removed")

for _, w in ipairs(__warns) do fails[#fails + 1] = "WARN " .. w end
if #fails == 0 then print("PASS votes") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
