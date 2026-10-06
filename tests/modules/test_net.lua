-- Test Net module: remote lookup, invoke timeout, ekstraksi payload, listener pasif, poller, stab/heal.
local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
local function sig(inst, name) return rawget(inst, "_signals")[name] end

local RS = ctx.ReplicatedStorage
local SN = __mk("Folder", { Name = "ServiceNetworks" }, RS)
local RN = __mk("Folder", { Name = "RoleNetworks" }, RS)
local function svc(name)
    return __mk("Folder", { Name = name }, SN)
end
local gameSvc = svc("gameService")
local roleSvc = svc("roleService")
local chatSvc = svc("chatService")
local annSvc = svc("announcementService")
local teamSvc = svc("teamService")
local revealRoles = __mk("RemoteEvent", { Name = "revealRoles" }, gameSvc)
local deathCut = __mk("RemoteEvent", { Name = "playDeathCutscene" }, gameSvc)
local topbar = __mk("RemoteEvent", { Name = "setTopbarText" }, gameSvc)
local gamePhase = __mk("RemoteFunction", { Name = "gamePhase" }, gameSvc)
local roleRF = __mk("RemoteFunction", { Name = "role" }, roleSvc)
local getRoleNetwork = __mk("RemoteEvent", { Name = "getRoleNetwork" }, roleSvc)
local sysMsg = __mk("RemoteEvent", { Name = "onSystemMessage" }, chatSvc)
local annShow = __mk("RemoteEvent", { Name = "show" }, annSvc)
local teamRF = __mk("RemoteFunction", { Name = "teamMembers" }, teamSvc)
local mafiaF = __mk("Folder", { Name = "mafia" }, RN)
local onStab = __mk("RemoteFunction", { Name = "onStab" }, mafiaF)
local mafiaTeam = __mk("RemoteFunction", { Name = "teamMembers" }, mafiaF)
local doctorF = __mk("Folder", { Name = "doctor" }, RN)
local onHeal = __mk("RemoteFunction", { Name = "onHeal" }, doctorF)

local me, alice, bob, cara
for _, p in ipairs(__players) do
    if p.Name == "Me" then me = p elseif p.Name == "Alice" then alice = p elseif p.Name == "Bob" then bob = p elseif p.Name == "Cara" then cara = p end
end
alice.UserId = 5001
bob.UserId = 5002

-- Respon remote palsu (per remote)
local responses = {}
__Methods.InvokeServer = function(self, ...)
    local fn = responses[self]
    __remoteLog = __remoteLog or {}
    __remoteLog[#__remoteLog + 1] = { self.Name, ... }
    if fn then return fn(...) end
    return nil
end

local Net = NetFactory(ctx)
local got = { role = {}, team = {}, self = {}, msg = {}, death = {}, mate = {} }
local found = Net.start({
    role = function(p, r, conf, why) got.role[#got.role + 1] = { p, r, conf, why } end,
    team = function(p, t, conf, why) got.team[#got.team + 1] = { p, t, conf, why } end,
    self = function(r, why) got.self[#got.self + 1] = { r, why } end,
    message = function(t, src) got.msg[#got.msg + 1] = { t, src } end,
    death = function(p, src) got.death[#got.death + 1] = { p, src } end,
    teammate = function(p, team, why) got.mate[#got.mate + 1] = { p, team, why } end,
})
check(found.revealRoles and found.onSystemMessage and found.topbar and found.onStab and found.onHeal, "listeners found")

-- lookup
check(Net.role("Mafia", "onStab") == onStab, "role folder lookup case-insensitive")
check(Net.role("Snow Spirit", "x") == nil, "missing role remote nil")
check(Net.roleFolder("Snow Spirit") == "snowspirit", "role folder name")

-- extract: map-style, record-style, positional
local ex = Net.extract({ [alice] = "Mafia", { player = bob, role = "Doctor" }, { name = "Cara", team = "Veil Team" } })
local seen = {}
for _, e in ipairs(ex) do seen[e.player.Name] = e.role or e.team end
check(seen.Alice == "Mafia", "map-style extract")
check(seen.Bob == "Doctor", "record-style extract")
check(seen.Cara == "VEIL", "team record by name")
local ex2 = Net.extract({ [5001] = { role = "Witch" } })
check(ex2[1] and ex2[1].player == alice and ex2[1].role == "Witch", "userId key extract")
check(#Net.extract({ 1, 2, 3, "Mafia" }) == 0, "no false pairs from arrays")

-- revealRoles: semua role di akhir ronde
sig(revealRoles, "OnClientEvent"):Fire({ [alice] = "Mafia", [bob] = "Doctor" })
check(#got.role == 2, "reveal produced 2 roles, got " .. #got.role)
check(got.role[1][3] == "confirmed", "reveal confirmed")
-- revealRoles posisional (Player, role)
got.role = {}
sig(revealRoles, "OnClientEvent"):Fire(cara, "Jester")
check(got.role[1] and got.role[1][1] == cara and got.role[1][2] == "Jester", "positional reveal")
-- revealRoles cuma nama role -> role sendiri
sig(revealRoles, "OnClientEvent"):Fire("Detainer")
check(got.self[#got.self][1] == "Detainer", "self reveal")

-- getRoleNetwork(folder) -> role sendiri
sig(getRoleNetwork, "OnClientEvent"):Fire(mafiaF)
check(got.self[#got.self][1] == "Mafia" and Net.selfRole == "Mafia", "role network folder")

-- pesan sistem & announcement
sig(sysMsg, "OnClientEvent"):Fire("The Harbinger thinks Bob is a Doctor.")
sig(annShow, "OnClientEvent"):Fire({ title = "Night falls", body = "Alice belonged to the Mafia" })
check(#got.msg >= 3, "messages forwarded: " .. #got.msg)

-- cutscene kematian
sig(deathCut, "OnClientEvent"):Fire({ victim = bob, role = "Doctor" })
check(got.death[1] and got.death[1][1] == bob, "death victim")

-- topbar -> phase
sig(topbar, "OnClientEvent"):Fire("Night 2 - 0:45")
check(Net.phase() == "night", "topbar phase: " .. tostring(Net.phase()))
check(ctx.Game.isNight() == true, "GameAPI uses Net phase provider")

-- poller: role sendiri, gamePhase, teammates
responses[roleRF] = function() return { name = "Witch" } end
responses[gamePhase] = function() return "Day" end
responses[teamRF] = function() return { alice, bob } end
Net.selfRole = nil
Net.step()
check(Net.selfRole == "Witch", "poll self role: " .. tostring(Net.selfRole))
check(Net.phaseText == "Day" and ctx.Game.isNight() == false, "poll phase")
local mates = {}
for _, m in ipairs(got.mate) do mates[m[1].Name] = m[2] end
check(mates.Alice == "EVIL" and mates.Bob == "EVIL", "teammates get own team (Witch -> EVIL)")

-- invoke: remote yang nggak pernah jawab -> timeout lalu ditandai
local hang = __mk("RemoteFunction", { Name = "hang" }, gameSvc)
local realSpawn = task.spawn
task.spawn = function(f, ...) end -- simulasikan thread yang nggak pernah selesai
local ok, why = Net.invoke(hang, 0.2)
task.spawn = realSpawn
check(ok == false and why == "timeout", "timeout detected: " .. tostring(why))
check(Net.dead[hang] == true, "unresponsive remote marked")
local ok2, why2 = Net.invoke(hang, 0.2)
check(ok2 == false and why2 == "unresponsive", "no second call to dead remote")
-- server error
responses[gamePhase] = function() error("boom") end
local ok3 = Net.invoke(gamePhase, 1)
check(ok3 == false, "server error returns false")

-- stab: Player ditolak (false), Character diterima
responses[onStab] = function(arg)
    if typeof(arg) == "Instance" and arg:IsA("Player") then return false end
    return true
end
local sOk, sMethod = Net.stab(alice)
check(sOk == true and string.find(sMethod, "Character", 1, true) ~= nil, "stab falls back to Character: " .. tostring(sMethod))
responses[onStab] = function() error("wrong args") end
local sOk2, sWhy2 = Net.stab(alice)
check(sOk2 == false, "stab fails cleanly: " .. tostring(sWhy2))
responses[onHeal] = function(arg) return true end
local hOk, hMethod = Net.heal(bob)
check(hOk == true and string.find(hMethod, "Player", 1, true) ~= nil, "heal with Player: " .. tostring(hMethod))

for _, w in ipairs(__warns) do fails[#fails + 1] = "WARN " .. w end
if #fails == 0 then print("PASS net") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
