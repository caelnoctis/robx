-- Votes: siapa nge-vote siapa, buat Vote ESP (tag + laser) dan daftar vote di tab Roles.
-- Semua sumber baca-saja:
--   tally    : ServiceNetworks.gameService.talliedVotes (getter, dipanggil client game sendiri buat
--              tanda vote di atas kepala), di-poll pelan.
--   event    : ServiceNetworks.gameService.votePlayer, kalau server menyiarkannya ke client.
--   pointing : ServiceNetworks.pointingService.updateArmPointing (RemoteEvent dari server), lengan
--              yang nunjuk = "laser" ke orang yang di-vote.
--   attr     : Intel.votes() (attribute talliedVotes / playerVotes) sebagai cadangan.
-- Bentuk payload belum pernah terekam isinya (cuma jumlahnya), jadi parser-nya toleran.
-- Toast "X is voting for you" cuma dari modul ini (Intel diam kalau ctx.votesOwnAlerts).
--
-- Dipanggil sebagai: local Votes = (<isi file ini>)(ctx); Votes.start()
return function(ctx)
    local V = { log = {}, last = nil, found = {} }
    local Players, LocalPlayer = ctx.Players, ctx.LocalPlayer
    local Net, Game = ctx.Net, ctx.Game

    -- Sumber yang lebih kuat nggak ditimpa sumber yang lebih lemah selama masih segar.
    local RANK = { attr = 1, pointing = 2, event = 3, tally = 4 }
    local FRESH = 30
    -- tally & attr di-refresh sumbernya sendiri; pointing & event bisa diam tanpa "stop".
    local ENTRY_TTL = { pointing = 90, event = 90 }
    local ALERT_GAP = 20 -- toast ulang untuk pemilih yang sama paling cepat sekali per 20 dtk
    local DEAD_RETRY = 30 -- getter tally yang ditandai mati dicoba lagi setelah jeda ini
    local TALLY_TIMEOUT = 5
    local AIM_NEAR_BODY = 3 -- titik sedekat ini ke tangan si penunjuk = posisi lengan, bukan target
    local RAY_WIDTH = 3.5 -- jarak tegak lurus maksimum dari sinar lengan ke badan target
    local RAY_RANGE = 150
    local SHRINK_GRACE = 1.5 -- vote yang hilang satu-satu dalam jeda ini = lengan turun di akhir voting

    local entries = {} -- [voter] = { target = Player, src = "pointing", t = waktu }
    local tallyCounts = {} -- [target] = jumlah dari server
    local tallyAt = -100
    local lastActivity = -100
    local inVote = false
    local alerted = {} -- [voter] = waktu toast terakhir
    local pollAt = -100
    local deadSince = nil
    local held = nil -- daftar vote terakhir yang nggak kosong; jadi V.last begitu daftar kosong / voting selesai
    local shrinkAt = nil -- waktu daftar mulai mengecil; held belum ditimpa sampai jelas ini bukan akhir voting
    local version, heldVersion = 0, -1
    local started = false

    V._clock = os.clock
    local function now()
        return V._clock()
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

    local function bodyPos(p)
        local c = p and p.Character
        local part = c and (c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso") or c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
        return part and part.Position or nil
    end

    local function handPos(p)
        local c = p and p.Character
        local hand = c and (c:FindFirstChild("RightHand") or c:FindFirstChild("Right Arm") or c:FindFirstChild("RightLowerArm"))
        if hand then
            return hand.Position
        end
        local root = c and c:FindFirstChild("HumanoidRootPart")
        return root and (root.Position + Vector3.new(0, 1, 0)) or nil
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

    -- Pemain pertama yang kena sinar dari origin ke arah dir (yang paling dekat di sepanjang sinar).
    function V.alongRay(origin, dir, exclude)
        if dir.Magnitude < 1e-3 then
            return nil
        end
        local unit = dir.Unit
        local best, bestAlong = nil, RAY_RANGE
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= exclude then
                local bp = bodyPos(p)
                if bp then
                    local v = bp - origin
                    local along = v:Dot(unit)
                    if along > 0.5 and along < bestAlong then
                        local perp = (v - unit * along).Magnitude
                        if perp <= RAY_WIDTH then
                            best, bestAlong = p, along
                        end
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

    -- Dipanggil cuma waktu target seorang pemilih BERUBAH ke kita (bukan tiap refresh).
    local function maybeAlert(voter, target)
        if target ~= LocalPlayer or voter == LocalPlayer then
            return
        end
        local t = now()
        local last = alerted[voter]
        alerted[voter] = t
        if last and t - last < ALERT_GAP then
            return
        end
        if settings().voteAlert ~= false and type(ctx.notify) == "function" then
            pcall(ctx.notify, "Vote", nameOf(voter) .. " is voting for you")
        end
    end

    local function setEntry(voter, target, src)
        if not voter or not target or voter == target then
            return false
        end
        local e = entries[voter]
        local t = now()
        if e and RANK[e.src] > RANK[src] and t - e.t < FRESH then
            -- Sumber yang lebih kuat masih segar: entri tetap miliknya. Sumber lemah yang setuju nggak
            -- mengganti label / waktunya, supaya "stop" dari sumber lemah nggak menghapus vote itu.
            return e.target == target
        end
        local changed = not e or e.target ~= target
        if changed or e.src ~= src then
            note(nameOf(voter) .. " -> " .. nameOf(target) .. " (" .. src .. ")")
            version = version + 1
        end
        entries[voter] = { target = target, src = src, t = t }
        lastActivity = t
        if changed then
            maybeAlert(voter, target)
        end
        return true
    end

    local function clearEntry(voter, src)
        local e = entries[voter]
        if e and (src == nil or e.src == src) then
            entries[voter] = nil
            version = version + 1
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

    -- { pos = Vector3, look = Vector3|nil } untuk Vector3 / CFrame.
    local function pointOf(v)
        local t = typeof(v)
        if t == "Vector3" then
            return { pos = v }
        elseif t == "CFrame" then
            return { pos = v.Position, look = v.LookVector }
        end
        return nil
    end

    -- Target dari titik / CFrame / arah yang dikirim bersama si penunjuk.
    local function targetFromPoints(pointer, points)
        if #points == 0 then
            return nil
        end
        local origin = handPos(pointer)
        if not origin then
            return V.nearestPlayerTo(points[1].pos, pointer, 6)
        end
        -- 1) titik dunia yang jauh dari tangannya (ujung laser): ambil yang paling jauh.
        local far, farD = nil, AIM_NEAR_BODY
        for _, pt in ipairs(points) do
            local d = (pt.pos - origin).Magnitude
            if d > farD and pt.pos.Magnitude > 1.5 then
                far, farD = pt, d
            end
        end
        if far then
            local p = V.nearestPlayerTo(far.pos, pointer, 6)
            if p then
                return p
            end
        end
        -- 2) CFrame lengan / vektor arah: ikuti sinarnya dari tangan.
        for _, pt in ipairs(points) do
            local dir = pt.look
            if not dir and pt.pos.Magnitude <= 1.5 then
                dir = pt.pos
            end
            if dir then
                local p = V.alongRay(origin, dir, pointer)
                if p then
                    return p
                end
            end
        end
        return nil
    end

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
                    if not tp then
                        local pts = {}
                        local pt = pointOf(v)
                        if not pt and typeof(v) == "table" then
                            pt = pointOf(rawget(v, "position")) or pointOf(rawget(v, "Position"))
                        end
                        if pt then
                            pts[1] = pt
                            tp = targetFromPoints(kp, pts)
                        end
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
        local pointer, target
        local points = {}
        local function consider(v)
            if v == nil or v == true then
                return
            end
            local pt = pointOf(v)
            if pt then
                points[#points + 1] = pt
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
        if not target then
            target = targetFromPoints(pointer, points)
        end
        return { { pointer, target } }
    end

    local function plausibleCount(c)
        return type(c) == "number" and c >= 0 and c <= 1000
    end

    -- talliedVotes: { [voter] = target } | { [target] = jumlah } | { [target] = { voter, ... } }
    --               | { [voter] = { target = .. } } | { { voter = .., target = .. }, ... }
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
                    -- jumlah suara; UserId (> 1000) yang pemainnya sudah keluar bukan jumlah
                    if plausibleCount(v) then
                        counts[kp] = v
                    end
                elseif typeof(v) == "table" then
                    -- { [voter] = { target = X } }: record milik si pemilih
                    local tp
                    for _, key in ipairs(TARGET_KEYS) do
                        tp = tp or playerFrom(rawget(v, key))
                    end
                    if tp and tp ~= kp then
                        votes[kp] = tp
                    else
                        -- { [target] = { voter, ... } } atau { voters = {...} }: cuma elemen array yang pemilih
                        local list = v
                        if #v == 0 then
                            local alt = rawget(v, "voters") or rawget(v, "votes")
                            list = typeof(alt) == "table" and alt or {}
                        end
                        local n = 0
                        for _, x in ipairs(list) do
                            local xp = playerFrom(x)
                            if xp and xp ~= kp then
                                votes[xp] = kp
                                n = n + 1
                            end
                        end
                        local c = rawget(v, "count") or rawget(v, "votes")
                        if n > 0 then
                            counts[kp] = n
                        elseif plausibleCount(c) then
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
        version = version + 1
        if any or next(counts) ~= nil then
            lastActivity = tallyAt
        end
    end

    local function pollTally()
        local remote = Net.service("gameService", "talliedVotes")
        if not remote then
            return
        end
        if Net.dead and Net.dead[remote] then
            -- Satu balasan lambat menandai getter ini mati; coba lagi setelah jeda, bukan selamanya.
            deadSince = deadSince or now()
            if now() - deadSince < DEAD_RETRY then
                return
            end
            Net.dead[remote] = nil
            deadSince = nil
            note("retrying talliedVotes")
        end
        local ok, res = Net.invoke(remote, TALLY_TIMEOUT)
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

    local function promoteHeld(t)
        if held then
            held.t = t
            V.last, held = held, nil
        end
    end

    -- Data voting yang sedang jalan (dipanggil juga saat voting selesai).
    function V.reset()
        entries, tallyCounts, alerted = {}, {}, {}
        tallyAt, lastActivity = -100, -100
        held, shrinkAt = nil, nil
        version = version + 1
    end

    -- Ronde baru / reset manual: hasil voting terakhir ikut dibuang.
    function V.clearAll()
        V.reset()
        V.last = nil
    end

    function V.step()
        local t = now()
        local vp = V.isVotePhase()

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
                    setEntry(voter, e.target, "attr")
                end
            end
        end
        local present = {}
        for _, p in ipairs(Players:GetPlayers()) do
            present[p] = true
        end
        for voter, e in pairs(entries) do
            local ttl = ENTRY_TTL[e.src]
            if (e.src == "attr" and not attrVoters[voter])
                or (ttl and t - e.t > ttl)
                or not present[voter] or (e.target and not present[e.target]) then
                clearEntry(voter)
            end
        end
        if t - tallyAt > 10 and next(tallyCounts) ~= nil then
            tallyCounts = {}
            version = version + 1
        end

        -- Hasil terakhir: disimpan selama ada vote, dipakai begitu daftarnya kosong (lengan turun,
        -- tally jadi {}) atau voting selesai. Nggak bergantung pada nama fase. Kalau daftar mengecil,
        -- held ditahan SHRINK_GRACE dtk: lengan yang turun satu-satu di akhir voting tetap tercatat
        -- lengkap, sedangkan orang yang memang membatalkan vote masuk setelah jeda itu.
        if version ~= heldVersion then
            heldVersion = version
            local live = V.list()
            if #live == 0 then
                promoteHeld(t)
                shrinkAt = nil
            elseif held and #live < #held.list then
                shrinkAt = shrinkAt or t
            else
                held = { t = t, list = live, counts = V.counts() }
                shrinkAt = nil
            end
        end
        if shrinkAt and t - shrinkAt >= SHRINK_GRACE then
            local live = V.list()
            if #live > 0 then
                held = { t = t, list = live, counts = V.counts() }
            end
            shrinkAt = nil
        end
        if inVote and not vp then
            promoteHeld(t)
            V.reset()
        elseif vp and not inVote then
            pollAt = -100 -- voting baru mulai: langsung tanya server
        end
        inVote = vp

        -- Getter tally: sering di siang hari / waktu voting / ada aktivitas vote, jarang malam hari.
        local okN, night = pcall(Game.isNight)
        local busy = vp or not (okN and night) or t - lastActivity < 20
        local every = busy and 2.5 or 20
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

    -- Jumlah suara per target: dihitung dari pasangan vote, lalu ditimpa jumlah dari server per target.
    function V.counts()
        local out = {}
        for _, e in pairs(entries) do
            if e.target then
                out[e.target] = (out[e.target] or 0) + 1
            end
        end
        for target, n in pairs(tallyCounts) do
            out[target] = n
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
                clearEntry(p)
                alerted[p] = nil
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
