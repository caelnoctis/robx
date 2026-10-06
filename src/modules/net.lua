-- Net: jalur jaringan game (ReplicatedStorage.ServiceNetworks.<service>.<name> dan
-- ReplicatedStorage.RoleNetworks.<role>.<name>), hasil scan remote di game asli.
--
-- Pasif  : dengar OnClientEvent (revealRoles, getRoleNetwork, onSystemMessage, announcement,
--          cutscene kematian, topbar).
-- Aktif  : cuma getter yang memang dipanggil client game sendiri (role, teamMembers, gamePhase),
--          masing-masing dengan timeout. Remote yang nggak menjawab ditandai dan nggak dipanggil lagi.
-- Aksi   : stab / heal lewat RoleNetworks.mafia.onStab dan RoleNetworks.doctor.onHeal.
--
-- Dipanggil sebagai: local Net = (<isi file ini>)(ctx); Net.start(hooks)
return function(ctx)
    local Net = {
        phaseText = nil,
        topbarText = nil,
        selfRole = nil,
        dead = {},      -- [remote] = true kalau pernah timeout
        busy = {},      -- [remote] = true selama invoke berjalan
        log = {},       -- ringkasan kejadian jaringan (buat dev tools)
    }
    local Game = ctx.Game
    local Players, LocalPlayer, RS = ctx.Players, ctx.LocalPlayer, ctx.ReplicatedStorage
    local hooks = {}
    local started = false

    local function now()
        return os.clock()
    end

    local function note(text)
        local l = Net.log
        l[#l + 1] = string.format("[%.1f] %s", now(), text)
        if #l > 80 then
            table.remove(l, 1)
        end
    end

    local function call(name, ...)
        local fn = hooks[name]
        if type(fn) == "function" then
            local ok, err = pcall(fn, ...)
            if not ok and ctx.warnf then
                ctx.warnf("Net hook " .. name .. ": " .. tostring(err))
            end
        end
    end

    ------------------------------------------------------------------
    -- Remote lookup
    ------------------------------------------------------------------
    local cache = {}
    function Net.remote(group, folder, name)
        local key = group .. "." .. folder .. "." .. name
        local hit = cache[key]
        if hit and hit.Parent then
            return hit
        end
        local g = RS:FindFirstChild(group)
        local f = g and g:FindFirstChild(folder)
        local r = f and f:FindFirstChild(name)
        cache[key] = r
        return r
    end

    function Net.service(svc, name)
        return Net.remote("ServiceNetworks", svc, name)
    end

    -- "Snow Spirit" -> "snowspirit"
    function Net.roleFolder(roleName)
        if not roleName then
            return nil
        end
        local key = string.gsub(string.lower(tostring(roleName)), "[^%a]", "")
        return key
    end

    function Net.role(roleName, name)
        local folder = Net.roleFolder(roleName)
        return folder and Net.remote("RoleNetworks", folder, name) or nil
    end

    ------------------------------------------------------------------
    -- Invoke dengan timeout. Return ok, results(packed) | false, reason
    ------------------------------------------------------------------
    function Net.invoke(remote, timeout, ...)
        if typeof(remote) ~= "Instance" or not remote:IsA("RemoteFunction") then
            return false, "missing"
        end
        if Net.dead[remote] then
            return false, "unresponsive"
        end
        if Net.busy[remote] then
            return false, "busy"
        end
        Net.busy[remote] = true
        local args = table.pack(...)
        local state = { done = false }
        task.spawn(function()
            local res = table.pack(pcall(function()
                return remote:InvokeServer(table.unpack(args, 1, args.n))
            end))
            state.done = true
            state.res = res
            Net.busy[remote] = nil
        end)
        local elapsed, limit = 0, timeout or 3
        while not state.done and elapsed < limit do
            local dt = task.wait(0.05)
            elapsed = elapsed + ((type(dt) == "number" and dt > 0) and dt or 0.05)
        end
        if not state.done then
            -- Thread-nya tetap menunggu di belakang; tandai biar nggak dipanggil lagi.
            Net.dead[remote] = true
            note("timeout " .. remote.Name)
            return false, "timeout"
        end
        local res = state.res
        if not res[1] then
            return false, tostring(res[2])
        end
        return true, table.pack(table.unpack(res, 2, res.n))
    end

    ------------------------------------------------------------------
    -- Ekstraksi pemain / role / tim dari payload sembarang
    ------------------------------------------------------------------
    local function playerFrom(v)
        local t = typeof(v)
        if t == "Instance" then
            if v:IsA("Player") then
                return v
            end
            if v:IsA("Model") then
                return Players:GetPlayerFromCharacter(v)
            end
            local model = v:FindFirstAncestorOfClass("Model")
            return model and Players:GetPlayerFromCharacter(model) or nil
        elseif t == "number" then
            if v > 1000 then
                local ok, p = pcall(Players.GetPlayerByUserId, Players, v)
                return ok and p or nil
            end
        elseif t == "string" then
            local l = string.lower(v)
            for _, p in ipairs(Players:GetPlayers()) do
                if string.lower(p.Name) == l or string.lower(p.DisplayName) == l then
                    return p
                end
            end
        end
        return nil
    end
    Net.playerFrom = playerFrom

    local function roleOf(v)
        if type(v) == "table" then
            v = rawget(v, "name") or rawget(v, "Name") or rawget(v, "role") or rawget(v, "Role")
        end
        if typeof(v) == "Instance" then
            v = v.Name
        end
        if type(v) == "string" then
            return Game.matchRole(v)
        end
        return nil
    end
    Net.roleOf = roleOf

    local function teamOf(v)
        if type(v) == "table" then
            v = rawget(v, "team") or rawget(v, "Team") or rawget(v, "name") or rawget(v, "Name")
        end
        if type(v) == "string" then
            return Game.normalizeTeam(v)
        end
        return nil
    end

    local PLAYER_KEYS = { player = true, plr = true, user = true, userid = true, target = true, character = true, char = true, victim = true }
    local ROLE_KEYS = { role = true, rolename = true, class = true }
    local TEAM_KEYS = { team = true, teamname = true, faction = true, alignment = true, side = true }

    -- List of { player, role, team } dari tabel (record-style atau map-style), depth <= 4.
    function Net.extract(value)
        local out, seen = {}, {}
        local function visit(t, depth)
            if type(t) ~= "table" or seen[t] or depth > 4 then
                return
            end
            seen[t] = true
            local p, r, tm
            for k, v in pairs(t) do
                if type(k) == "string" then
                    local lk = string.lower(k)
                    if PLAYER_KEYS[lk] or lk == "name" then
                        p = p or playerFrom(v)
                    end
                    if ROLE_KEYS[lk] then
                        r = r or roleOf(v)
                    end
                    if TEAM_KEYS[lk] then
                        tm = tm or teamOf(v)
                    end
                end
            end
            if p and (r or tm) then
                out[#out + 1] = { player = p, role = r, team = tm }
            end
            for k, v in pairs(t) do
                local kp = nil
                if typeof(k) == "Instance" or (type(k) == "number" and k > 1000) or type(k) == "string" then
                    kp = playerFrom(k)
                end
                if kp then
                    local vr = roleOf(v)
                    local vt = teamOf(v)
                    if vr or vt then
                        out[#out + 1] = { player = kp, role = vr, team = vt }
                    end
                end
                if type(v) == "table" then
                    visit(v, depth + 1)
                end
            end
        end
        visit(value, 0)
        return out
    end

    -- Semua pemain yang muncul di payload (Player, karakter, UserId, nama persis).
    function Net.playersIn(value)
        local set, seen = {}, {}
        local function visit(v, depth)
            local p = playerFrom(v)
            if p then
                set[p] = true
                return
            end
            if type(v) ~= "table" or seen[v] or depth > 4 then
                return
            end
            seen[v] = true
            for k, x in pairs(v) do
                if typeof(k) == "Instance" then
                    local kp = playerFrom(k)
                    if kp then
                        set[kp] = true
                    end
                end
                visit(x, depth + 1)
            end
        end
        visit(value, 0)
        return set
    end

    -- Semua string di payload (buat pesan sistem).
    local function stringsIn(value, out, depth, seen)
        out = out or {}
        seen = seen or {}
        depth = depth or 0
        if type(value) == "string" then
            out[#out + 1] = value
        elseif type(value) == "table" and not seen[value] and depth <= 3 then
            seen[value] = true
            for _, v in pairs(value) do
                stringsIn(v, out, depth + 1, seen)
            end
        end
        return out
    end
    Net.stringsIn = stringsIn

    ------------------------------------------------------------------
    -- Handler event pasif
    ------------------------------------------------------------------
    local function handlePairs(pairsList, conf, reason)
        for _, e in ipairs(pairsList) do
            if e.role then
                call("role", e.player, e.role, conf, reason)
            elseif e.team then
                call("team", e.player, e.team, conf, reason)
            end
        end
    end

    local function onReveal(...)
        local args = table.pack(...)
        local found = Net.extract(args)
        -- Bentuk posisional: (Player, "Mafia")
        local p1 = playerFrom(args[1])
        local r2 = roleOf(args[2])
        if p1 and r2 then
            found[#found + 1] = { player = p1, role = r2 }
        end
        if #found > 0 then
            handlePairs(found, "confirmed", "role reveal")
        else
            -- Cuma nama role tanpa pemain: reveal role sendiri di awal ronde.
            for i = 1, args.n do
                local r = roleOf(args[i])
                if r then
                    Net.selfRole = r
                    call("self", r, "role reveal")
                    break
                end
            end
        end
        note("revealRoles " .. #found .. " pairs")
    end

    local function onRoleNetwork(...)
        local args = table.pack(...)
        for i = 1, args.n do
            local v = args[i]
            local r
            if typeof(v) == "Instance" then
                -- Folder RoleNetworks.<role> -> nama role
                r = Game.matchRole(v.Name)
            else
                r = roleOf(v)
            end
            if r then
                Net.selfRole = r
                call("self", r, "role network")
                note("getRoleNetwork " .. r)
                return
            end
        end
    end

    local function onMessage(source)
        return function(...)
            local texts = stringsIn(table.pack(...))
            for _, t in ipairs(texts) do
                call("message", t, source)
            end
        end
    end

    local function onDeath(source)
        return function(...)
            local args = table.pack(...)
            local found = Net.extract(args)
            handlePairs(found, "confirmed", "revealed on death")
            for _, t in ipairs(stringsIn(args)) do
                call("message", t, source)
            end
            local victims = Net.playersIn(args)
            for p in pairs(victims) do
                call("death", p, source)
            end
        end
    end

    local function onTopbar(...)
        local texts = stringsIn(table.pack(...))
        if texts[1] then
            Net.topbarText = texts[1]
            call("topbar", texts[1])
        end
    end

    ------------------------------------------------------------------
    -- Poller aktif (getter)
    ------------------------------------------------------------------
    local timers = { role = -100, team = -100, roleTeam = -100, phase = -100 }

    local function pollSelfRole()
        local remote = Net.service("roleService", "role")
        if not remote then
            return
        end
        local ok, res = Net.invoke(remote, 4)
        if not ok then
            return
        end
        local r
        for i = 1, res.n do
            r = r or roleOf(res[i])
            if not r and type(res[i]) == "table" then
                for _, s in ipairs(stringsIn(res[i])) do
                    r = r or Game.matchRole(s)
                end
            end
        end
        if r then
            if r ~= Net.selfRole then
                note("roleService.role " .. r)
            end
            Net.selfRole = r
            call("self", r, "server")
        end
    end

    local function pollTeam(remote, reason)
        local ok, res = Net.invoke(remote, 4)
        if not ok then
            return
        end
        local found = Net.extract(res)
        handlePairs(found, "confirmed", reason)
        local members = Net.playersIn(res)
        local myTeam = Net.selfRole and Game.teamOf(Net.selfRole) or nil
        for p in pairs(members) do
            if p ~= LocalPlayer then
                call("teammate", p, myTeam, reason)
            end
        end
    end

    local function pollPhase()
        local remote = Net.service("gameService", "gamePhase")
        if not remote then
            return
        end
        local ok, res = Net.invoke(remote, 3)
        if ok and res.n > 0 then
            local v = res[1]
            if type(v) == "table" then
                v = rawget(v, "name") or rawget(v, "Name") or rawget(v, "phase")
            end
            if v ~= nil then
                Net.phaseText = tostring(v)
            end
        end
    end

    local function spawnPoll(fn, ...)
        task.spawn(function(...)
            local ok, err = pcall(fn, ...)
            if not ok and ctx.warnf then
                ctx.warnf("Net poll: " .. tostring(err))
            end
        end, ...)
    end

    function Net.step()
        if not started then
            return
        end
        local t = now()
        if t - timers.phase >= 3 then
            timers.phase = t
            spawnPoll(pollPhase)
        end
        local roleEvery = Net.selfRole and 30 or 8
        if t - timers.role >= roleEvery then
            timers.role = t
            spawnPoll(pollSelfRole)
        end
        if t - timers.team >= 12 then
            timers.team = t
            local remote = Net.service("teamService", "teamMembers")
            if remote then
                spawnPoll(pollTeam, remote, "teammate")
            end
        end
        if Net.selfRole and t - timers.roleTeam >= 15 then
            timers.roleTeam = t
            local remote = Net.role(Net.selfRole, "teamMembers") or Net.role(Net.selfRole, "getTeamMembers")
            if remote then
                spawnPoll(pollTeam, remote, "teammate (" .. Net.selfRole .. ")")
            end
        end
    end

    -- Fase dari remote / topbar, dipakai GameAPI kalau attribute gamePhase nggak ada.
    function Net.phase()
        if Net.phaseText then
            return Net.phaseText
        end
        local tb = Net.topbarText and string.lower(Net.topbarText) or nil
        if tb then
            for _, w in ipairs({ "night", "day", "discussion", "voting", "vote", "meeting" }) do
                if string.find(tb, w, 1, true) then
                    return w
                end
            end
        end
        return nil
    end

    ------------------------------------------------------------------
    -- Aksi (dipakai Actions)
    ------------------------------------------------------------------
    -- Coba beberapa bentuk argumen; sukses kalau server menjawab tanpa error dan bukan false.
    local function tryForms(remote, forms)
        local lastErr = "no forms"
        for _, form in ipairs(forms) do
            local ok, res = Net.invoke(remote, 3, table.unpack(form.args, 1, form.n))
            if ok then
                local first = res[1]
                if first ~= false then
                    return true, form.label, first
                end
                lastErr = "server said no (" .. form.label .. ")"
            else
                lastErr = res
                if res == "timeout" or res == "unresponsive" or res == "busy" then
                    break
                end
            end
        end
        return false, lastErr
    end

    local function targetForms(target)
        local forms = {}
        local char = target and target.Character
        if target then
            forms[#forms + 1] = { label = "Player", args = { target }, n = 1 }
        end
        if char then
            forms[#forms + 1] = { label = "Character", args = { char }, n = 1 }
        end
        return forms
    end

    function Net.stab(target)
        local remote = Net.role("mafia", "onStab")
        if not remote then
            return false, "onStab remote not found"
        end
        local ok, label = tryForms(remote, targetForms(target))
        note("onStab " .. tostring(ok) .. " " .. tostring(label))
        return ok, ok and ("remote onStab(" .. label .. ")") or label
    end

    function Net.heal(target)
        local remote = Net.role("doctor", "onHeal")
        if not remote then
            return false, "onHeal remote not found"
        end
        local ok, label = tryForms(remote, targetForms(target))
        note("onHeal " .. tostring(ok) .. " " .. tostring(label))
        return ok, ok and ("remote onHeal(" .. label .. ")") or label
    end

    ------------------------------------------------------------------
    -- Start
    ------------------------------------------------------------------
    local function listen(remote, fn)
        if typeof(remote) == "Instance" and (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
            ctx.connect(remote.OnClientEvent, function(...)
                local ok, err = pcall(fn, ...)
                if not ok and ctx.warnf then
                    ctx.warnf("Net " .. remote.Name .. ": " .. tostring(err))
                end
            end)
            return true
        end
        return false
    end

    function Net.start(h)
        hooks = h or {}
        if started then
            return Net.found
        end
        started = true
        local found = {}
        found.revealRoles = listen(Net.service("gameService", "revealRoles"), onReveal)
        found.getRoleNetwork = listen(Net.service("roleService", "getRoleNetwork"), onRoleNetwork)
        found.onSystemMessage = listen(Net.service("chatService", "onSystemMessage"), onMessage("system"))
        found.announcement = listen(Net.service("announcementService", "show"), onMessage("announcement"))
        found.deathCutscene = listen(Net.service("gameService", "playDeathCutscene"), onDeath("death cutscene"))
        found.bodyFound = listen(Net.service("gameService", "playBodyFoundCutscene"), onDeath("body found"))
        found.topbar = listen(Net.service("gameService", "setTopbarText"), onTopbar)
        found.roleService = Net.service("roleService", "role") ~= nil
        found.onStab = Net.role("mafia", "onStab") ~= nil
        found.onHeal = Net.role("doctor", "onHeal") ~= nil
        Net.found = found
        if Game.addPhaseProvider then
            Game.addPhaseProvider(Net.phase)
        end
        local n = 0
        for _, v in pairs(found) do
            if v then
                n = n + 1
            end
        end
        note("started, " .. n .. " network hooks")
        return found
    end

    function Net.reset()
        Net.selfRole = nil
        Net.phaseText = nil
        timers.role, timers.team, timers.roleTeam = -100, -100, -100
    end

    return Net
end
