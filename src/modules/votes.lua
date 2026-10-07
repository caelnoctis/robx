-- Votes: siapa nge-vote siapa, buat Vote ESP (tag + laser) dan daftar vote di tab Roles.
-- Semua sumber baca-saja:
--   tally    : ServiceNetworks.gameService.talliedVotes (getter, dipanggil client game sendiri buat
--              tanda vote di atas kepala), di-poll pelan.
--   event    : ServiceNetworks.gameService.votePlayer, kalau server menyiarkannya ke client.
--   pointing : ServiceNetworks.pointingService.updateArmPointing (RemoteEvent dari server), lengan
--              yang nunjuk = "laser" ke orang yang di-vote.
--   attr     : Intel.votes() (attribute talliedVotes / playerVotes) sebagai cadangan.
-- Bentuk payload belum pernah terekam isinya (cuma jumlahnya), jadi parser-nya toleran.
--
-- Dipanggil sebagai: local Votes = (<isi file ini>)(ctx); Votes.start()
return function(ctx)
    local V = { log = {}, last = nil, found = {} }
    local Players, LocalPlayer = ctx.Players, ctx.LocalPlayer
    local Net, Game = ctx.Net, ctx.Game

    -- Sumber yang lebih kuat nggak ditimpa sumber yang lebih lemah selama masih segar.
    local RANK = { attr = 1, pointing = 2, event = 3, tally = 4 }
    local FRESH = 30
    local POINT_TTL = 90

    local entries = {} -- [voter] = { target = Player, src = "pointing", t = os.clock() }
    local tallyCounts = {} -- [target] = jumlah dari server
    local tallyAt = -100
    local lastActivity = -100
    local inVote = false
    local alerted = {}
    local pollAt = -100
    local started = false

    local function now()
        return os.clock()
    end

    local function note(text)
        local l = V.log
        l[#l + 1] = string.format("[%.1f] %s", now(), text)
        if #l > 40 then
            table.remove(l, 1)
        end
    end

    local function playerFrom(v)
        if v == nil or type(v) == "boolean" then
            return nil
        end
        local ok, p = pcall(Net.playerFrom, v)
        return ok and p or nil
    end

    local function posOf(v)
        local t = typeof(v)
        if t == "Vector3" then
            return v
        elseif t == "CFrame" then
            return v.Position
        end
        return nil
    end

    -- Pemain yang badannya paling dekat ke titik (titik ujung "laser").
    function V.nearestPlayerTo(pos, exclude, maxDist)
        local best, bestD = nil, maxDist or 6
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= exclude then
                local c = p.Character
                local root = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
                if root then
                    local d = (root.Position - pos).Magnitude
                    if d < bestD then
                        best, bestD = p, d
                    end
                end
            end
        end
        return best
    end

    local function settings()
        return ctx.S or {}
    end

    local function nameOf(p)
        if ctx.nameOf then
            local ok, n = pcall(ctx.nameOf, p)
            if ok and n then
                return n
            end
        end
        return p and p.DisplayName or "?"
    end

    local function maybeAlert(voter, target, src)
        if target == LocalPlayer and voter ~= LocalPlayer then
            -- Vote dari attribute sudah diberi alert oleh Intel.
            if not alerted[voter] and src ~= "attr" and settings().voteAlert ~= false and type(ctx.notify) == "function" then
                pcall(ctx.notify, "Vote", nameOf(voter) .. " is voting for you")
            end
            alerted[voter] = true
        else
            alerted[voter] = nil
        end
    end

    local function setEntry(voter, target, src)
        if not voter or not target or voter == target then
            return false
        end
        local e = entries[voter]
        local t = now()
        if e and e.target ~= target and RANK[e.src] > RANK[src] and t - e.t < FRESH then
            return false
        end
        if not (e and e.target == target and e.src == src) then
            note(nameOf(voter) .. " -> " .. nameOf(target) .. " (" .. src .. ")")
        end
        entries[voter] = { target = target, src = src, t = t }
        lastActivity = t
        maybeAlert(voter, target, src)
        return true
    end

    local function clearEntry(voter, src)
        local e = entries[voter]
        if e and (src == nil or e.src == src) then
            entries[voter] = nil
            alerted[voter] = nil
            return true
        end
        return false
    end

    ------------------------------------------------------------------
    -- Parser payload
    ------------------------------------------------------------------
    local VOTER_KEYS = { "player", "Player", "pointer", "voter", "Voter", "from", "source", "user", "userId" }
    local TARGET_KEYS = { "target", "Target", "votedFor", "vote", "to", "victim", "pointingAt", "subject" }
    local POS_KEYS = { "position", "Position", "point", "hit", "cframe", "CFrame" }

    -- Map { [pemain] = target } di dalam satu argumen.
    local function mapPairs(tbl, out)
        local n = 0
        for k, v in pairs(tbl) do
            if type(k) ~= "number" or k > 1000 then
                local kp = playerFrom(k)
                if kp then
                    local tp = playerFrom(v)
                    if not tp and typeof(v) == "table" then
                        for _, key in ipairs(TARGET_KEYS) do
                            tp = tp or playerFrom(rawget(v, key))
                        end
                    end
                    local pos = not tp and (posOf(v) or (typeof(v) == "table" and (posOf(rawget(v, "position")) or posOf(rawget(v, "Position"))))) or nil
                    if pos then
                        tp = V.nearestPlayerTo(pos, kp, 6)
                    end
                    out[#out + 1] = { kp, tp }
                    n = n + 1
                end
            end
        end
        return n
    end

    -- Return: daftar { pointer, target|nil }. target nil = berhenti nunjuk / bukan ke pemain.
    function V.parsePointing(...)
        local args = table.pack(...)
        local pointer, target, pos
        local function consider(v)
            if v == nil or v == true then
                return
            end
            local p = posOf(v)
            if p then
                pos = pos or p
                return
            end
            local pl = playerFrom(v)
            if pl then
                if not pointer then
                    pointer = pl
                elseif pl ~= pointer and not target then
                    target = pl
                end
            end
        end
        for i = 1, args.n do
            local v = args[i]
            if typeof(v) == "table" then
                local mapped = {}
                if mapPairs(v, mapped) > 0 and not pointer then
                    return mapped
                end
                for _, k in ipairs(VOTER_KEYS) do
                    consider(rawget(v, k))
                end
                for _, k in ipairs(TARGET_KEYS) do
                    consider(rawget(v, k))
                end
                for _, k in ipairs(POS_KEYS) do
                    consider(rawget(v, k))
                end
                for _, x in ipairs(v) do
                    consider(x)
                end
            else
                consider(v)
            end
        end
        if not pointer then
            return {}
        end
        if not target and pos then
            target = V.nearestPlayerTo(pos, pointer, 6)
        end
        return { { pointer, target } }
    end

    -- talliedVotes: { [voter] = target } | { [target] = jumlah } | { [target] = { voter, ... } }
    --               | { { voter = .., target = .. }, ... }
    function V.parseTally(value)
        local votes, counts = {}, {}
        if typeof(value) ~= "table" then
            return votes, counts
        end
        for k, v in pairs(value) do
            local kp = nil
            if type(k) ~= "number" or k > 1000 then
                kp = playerFrom(k)
            end
            if kp then
                local vp = playerFrom(v)
                if vp then
                    votes[kp] = vp
                elseif type(v) == "number" then
                    counts[kp] = v
                elseif typeof(v) == "table" then
                    local n = 0
                    for _, x in pairs(v) do
                        local xp = playerFrom(x)
                        if xp then
                            votes[xp] = kp
                            n = n + 1
                        end
                    end
                    if n > 0 then
                        counts[kp] = n
                    else
                        local tp
                        for _, key in ipairs(TARGET_KEYS) do
                            tp = tp or playerFrom(rawget(v, key))
                        end
                        if tp then
                            votes[kp] = tp
                        end
                        local c = rawget(v, "count") or rawget(v, "votes")
                        if type(c) == "number" then
                            counts[kp] = c
                        end
                    end
                end
            elseif typeof(v) == "table" then
                local voter, tp
                for _, key in ipairs(VOTER_KEYS) do
                    voter = voter or playerFrom(rawget(v, key))
                end
                for _, key in ipairs(TARGET_KEYS) do
                    tp = tp or playerFrom(rawget(v, key))
                end
                if voter and tp then
                    votes[voter] = tp
                end
            end
        end
        return votes, counts
    end

    ------------------------------------------------------------------
    -- Handler jaringan
    ------------------------------------------------------------------
    function V.onPointing(...)
        for _, pair in ipairs(V.parsePointing(...)) do
            local pointer, target = pair[1], pair[2]
            if target then
                setEntry(pointer, target, "pointing")
            else
                clearEntry(pointer, "pointing")
            end
        end
    end

    function V.onVoteEvent(...)
        local list = V.parsePointing(...)
        local pair = list[1]
        if pair and pair[2] then
            setEntry(pair[1], pair[2], "event")
        elseif pair and #list == 1 then
            clearEntry(pair[1], "event")
        end
    end

    function V.applyTally(value)
        local votes, counts = V.parseTally(value)
        for voter, e in pairs(entries) do
            if e.src == "tally" and votes[voter] == nil then
                clearEntry(voter, "tally")
            end
        end
        local any = false
        for voter, target in pairs(votes) do
            setEntry(voter, target, "tally")
            any = true
        end
        tallyCounts = counts
        tallyAt = now()
        if any or next(counts) ~= nil then
            lastActivity = tallyAt
        end
    end

    local function pollTally()
        local remote = Net.service("gameService", "talliedVotes")
        if not remote then
            return
        end
        local ok, res = Net.invoke(remote, 3)
        if ok then
            V.applyTally(res[1])
        end
    end

    ------------------------------------------------------------------
    -- Fase & langkah berkala
    ------------------------------------------------------------------
    function V.isVotePhase()
        local ok, ph = pcall(Game.phase)
        local l = ok and ph and string.lower(tostring(ph)) or ""
        return string.find(l, "vot", 1, true) ~= nil or string.find(l, "ballot", 1, true) ~= nil
            or string.find(l, "trial", 1, true) ~= nil
    end

    local function snapshotLast()
        local list = V.list()
        if #list > 0 then
            V.last = { t = now(), list = list, counts = V.counts() }
        end
    end

    function V.reset()
        entries, tallyCounts, alerted = {}, {}, {}
        tallyAt, lastActivity = -100, -100
    end

    function V.step()
        local t = now()
        local vp = V.isVotePhase()
        if inVote and not vp then
            -- Voting selesai: simpan hasil terakhir, mulai bersih.
            snapshotLast()
            V.reset()
        elseif vp and not inVote then
            pollAt = -100 -- voting baru mulai: langsung tanya server
        end
        inVote = vp

        -- Cadangan dari attribute (Intel).
        local okI, iv = false, nil
        if ctx.Intel and type(ctx.Intel.votes) == "function" then
            okI, iv = pcall(ctx.Intel.votes)
        end
        local attrVoters = {}
        if okI and type(iv) == "table" then
            for voter, e in pairs(iv) do
                if type(e) == "table" and e.target then
                    attrVoters[voter] = true
                    local cur = entries[voter]
                    if not cur or cur.src == "attr" or t - cur.t >= FRESH then
                        setEntry(voter, e.target, "attr")
                    end
                end
            end
        end
        local present = {}
        for _, p in ipairs(Players:GetPlayers()) do
            present[p] = true
        end
        for voter, e in pairs(entries) do
            if (e.src == "attr" and not attrVoters[voter])
                or (e.src == "pointing" and t - e.t > POINT_TTL)
                or not present[voter] or (e.target and not present[e.target]) then
                clearEntry(voter)
            end
        end
        if t - tallyAt > 10 then
            tallyCounts = {}
        end

        -- Getter tally: sering waktu voting / ada aktivitas vote, jarang di luar itu.
        local every = (vp or t - lastActivity < 20) and 2.5 or 20
        if started and t - pollAt >= every then
            pollAt = t
            task.spawn(function()
                local ok, err = pcall(pollTally)
                if not ok and ctx.warnf then
                    ctx.warnf("Votes poll: " .. tostring(err))
                end
            end)
        end
    end

    ------------------------------------------------------------------
    -- API buat ESP / UI
    ------------------------------------------------------------------
    function V.get()
        return entries
    end

    function V.targetOf(p)
        local e = entries[p]
        return e and e.target or nil, e and e.src or nil
    end

    -- Jumlah suara per target: dari server kalau ada, kalau nggak dihitung dari pasangan vote.
    function V.counts()
        local out = {}
        for target, n in pairs(tallyCounts) do
            out[target] = n
        end
        if next(out) == nil then
            for _, e in pairs(entries) do
                if e.target then
                    out[e.target] = (out[e.target] or 0) + 1
                end
            end
        end
        return out
    end

    function V.list()
        local list = {}
        for voter, e in pairs(entries) do
            list[#list + 1] = { voter = voter, target = e.target, src = e.src, t = e.t }
        end
        table.sort(list, function(a, b)
            if a.target ~= b.target then
                return tostring(a.target and a.target.Name) < tostring(b.target and b.target.Name)
            end
            return tostring(a.voter.Name) < tostring(b.voter.Name)
        end)
        return list
    end

    function V.start()
        if started then
            return V.found
        end
        started = true
        local listen = Net.listen
        if type(listen) == "function" then
            V.found.armPointing = listen(Net.service("pointingService", "updateArmPointing"), V.onPointing)
            V.found.votePlayer = listen(Net.service("gameService", "votePlayer"), V.onVoteEvent)
        end
        V.found.talliedVotes = Net.service("gameService", "talliedVotes") ~= nil
        if ctx.connect then
            ctx.connect(Players.PlayerRemoving, function(p)
                entries[p], alerted[p] = nil, nil
                for voter, e in pairs(entries) do
                    if e.target == p then
                        clearEntry(voter)
                    end
                end
            end)
        end
        return V.found
    end

    return V
end
