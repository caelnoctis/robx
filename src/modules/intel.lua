-- Intel: mesin deteksi role buat MAFIA [V2.3] - ACT II.
-- v1 cuma nebak dari nama tool dan nggak nemu apa-apa. Di sini semua sumber bukti digabung:
-- controller role game, attribute, tag di atas kepala, chat / pengumuman, animasi, tool,
-- transisi status (downed / revive / silence / pintu / pisang) dan irisan kandidat berdasarkan jarak.
-- Hasilnya satu view rapi per player buat ESP dan UI.
-- Dipanggil sebagai: local Intel = (<isi file ini>)(ctx)
return function(ctx)
    local Intel = {}
    local Game = ctx.Game
    local Players = ctx.Players
    local LocalPlayer = ctx.LocalPlayer
    local CollectionService = ctx.CollectionService
    local TextChatService = ctx.TextChatService
    local Workspace = ctx.Workspace or workspace

    local clockFn = os.clock
    local function now()
        return clockFn()
    end

    ------------------------------------------------------------------
    -- Konstanta
    ------------------------------------------------------------------
    local RANK = { suspect = 1, likely = 2, confirmed = 3 }
    local FEED_CAP = 60
    local TEAM_COLORS = {
        EVIL = Color3.fromRGB(255, 64, 64),
        VEIL = Color3.fromRGB(255, 200, 60),
        TOWN = Color3.fromRGB(80, 220, 120),
    }
    local GREY = Color3.fromRGB(170, 170, 170)

    local K = {} -- konstanta (dikumpulin biar jumlah local nggak mepet limit Luau)
    -- status -> nama attribute / tag (lowercase) yang dicek
    K.STATUS_KEYS = {
        dead = { "dead" },
        downed = { "downed" },
        detained = { "detained" },
        silenced = { "witchsilenced", "silenced", "witchsilencedextended" },
        hiding = { "lockerpose", "inlocker", "incloset", "hiding", "hidden" },
        ragdolled = { "ragdolled" },
    }
    K.TAG_NAMES = { "Dead", "Downed", "Detained", "witchSilenced", "Silenced", "Ragdolled", "lockerPose",
        "poisonApplied", "poisonCured", "knifeWound", "InLocker", "Hiding" }
    K.WATCH_ATTRS = {}
    for _, n in ipairs({ "dead", "downed", "detained", "witchsilenced", "silenced", "witchsilencedextended",
        "lockerpose", "inlocker", "incloset", "hiding", "hidden", "poisonapplied", "poisoncured", "ragdolled",
        "knifewound", "cheaptrickshot", "disguisename", "redactedlabel", "talliedvotes", "playervotes",
        "votedfor", "votetarget" }) do
        K.WATCH_ATTRS[n] = true
    end
    K.ROLEISH = { "role", "team", "class", "faction", "align", "side", "job" }
    -- pilihan / riwayat / kosmetik role bukan role ronde ini
    K.IGNORE_ATTR = { "discord", "booster", "setting", "hotkey", "owns", "innercircle", "xp", "level", "credit", "token", "session", "disguise", "label", "guess", "target", "vote", "killer", "cause", "last", "phase",
        "point", "redacted", "display", "spectat", "select", "prefer", "prev", "request", "equip", "fav", "skin",
        "owned", "unlock", "history", "pick" }
    -- cuma nama persis ini yang dihitung "confirmed"; nama roleish lain -> "likely"
    K.ROLE_ATTR_EXACT = {}
    for _, n in ipairs({ "role", "currentrole", "myrole", "rolename", "assignedrole", "playerrole", "actualrole",
        "realrole", "team", "currentteam", "teamname", "myteam", "faction", "alignment", "side" }) do
        K.ROLE_ATTR_EXACT[n] = true
    end
    K.DEATH_WORDS = { "died", "dead", "killed", "executed", "belonged", "unmasked", "eliminated", "murdered",
        "lynched", "hanged", "voted out", "perished", "slain", "body" }
    K.RESET_PHASES = { "lobby", "intermission", "waiting", "start", "roleselect", "reveal" }
    -- fase yang jelas masih di tengah ronde ("nightStart" bukan ronde baru)
    K.IN_ROUND = { "night", "day", "vot", "discuss", "meet" }
    -- Teks penyebab kematian (dari string SummitX) yang cuma masuk akal buat satu role. Tebakan -> "likely".
    K.CAUSE_HINTS = {
        { "wrong role", "Harbinger" },
        { "calling out the wrong", "Harbinger" },
        { "shooting an innocent", "Vigilante" },
        { "murdering an innocent", "Vigilante" },
        { "executing an innocent", "Vigilante" },
        { "hesitation is a capital", "Mafia" },
        { "purged as a sacrifice", "Mafia" },
        { "executed by their own side", "Mafia" },
        { "two consecutive nights", "Mafia" },
    }
    K.HIDE_WORDS = { "locker", "closet", "hiding" }
    K.SKIP_WORDS = { "idle", "equip", "walk", "run", "hold", "crawl", "wound", "emote", "dance", "jump", "fall",
        "climb", "point", "aim", "reload", "inspect", "draw", "spin", "holster", "sheath", "twirl" }
    K.STAB_WORDS = { "knife", "stab", "swing", "slash" }
    K.SHOT_WORDS = { "glock", "gun", "shot", "shoot", "fire", "pistol", "revolver" }
    K.GUN_TOOLS = { "gun", "revolver", "pistol", "rifle", "shotgun" }
    K.ROLE_FUNCS = { "getCurrentRole", "GetCurrentRole", "getRole", "GetRole" }
    K.ROLE_FIELDS = { "role", "Role", "currentRole", "CurrentRole", "myRole", "roleName", "RoleName", "playerRole",
        "assignedRole" }
    K.TEAM_FIELDS = { "team", "Team", "currentTeam", "myTeam", "teamName", "alignment", "faction" }
    K.MATE_FIELDS = { "teammates", "teamMates", "partners", "allies", "members", "mafiaMembers", "knownRoles" }
    K.CALL_SIGS = { "self", "none", "player" }
    -- di-anchor ke awal teks / baris: "Bob: you're mafia lol" bukan layar role
    K.SELF_PATTERNS = { "^you are%s*:?%s*(.+)", "^you're%s*:?%s*(.+)", "^your role is%s*:?%s*(.+)",
        "^your role%s*:%s*(.+)", "^role%s*:%s*(.+)" }
    -- label pembuka yang role-nya ada di label sebelah ("YOU ARE" + "MAFIA")
    K.SELF_PREFIX = {}
    for _, n in ipairs({ "you are", "you are the", "you are a", "you are an", "you're", "your role", "your role is",
        "role" }) do
        K.SELF_PREFIX[n] = true
    end
    K.REVEAL_GUI_WORDS = { "role", "reveal", "intro", "identity" }
    K.CHAT_GUI_WORDS = { "chat", "feed", "message", "bubble", "history", "console" }
    K.VOTE_TARGET_KEYS = { "playervotes", "votedfor", "votetarget" }
    K.CFG_DEFAULTS = { maxSilenceDistance = 20, maxSabotageDistance = 15, maxCleanupDistance = 15 }

    local function weak()
        return setmetatable({}, { __mode = "k" })
    end

    ------------------------------------------------------------------
    -- State
    ------------------------------------------------------------------
    local St = {
        started = false,
        conns = {},
        hooks = {},          -- [Player] = { conns, charConns, char, hum, animator, animConn }
        recs = {},           -- [Player] = record
        removed = weak(),
        feed = {},
        cand = {},           -- [role] = { set = {[Player]=true}, n, reason }
        votes = {},
        voteTargets = {},
        lastAttack = {},     -- [Player] = { t, kind }
        attributed = {},     -- [victim] = t
        harb = nil,
        harbWatch = nil,
        recentDeaths = {},
        pendingRevive = {},
        doorEvents = {},
        doors = weak(),      -- [Instance] = locked(bool)
        doorConns = weak(),  -- [Instance] = connection (diputus waktu pintunya hilang)
        doorCount = 0,
        killedAt = {},       -- [victim] = t (serangannya punya pelaku)
        corpseSeen = weak(),
        bananaSeen = weak(),
        toolSeen = weak(),
        lastBanana = nil,
        recentMsgs = {},
        notified = {},
        selfNotified = false,
        selfLocked = false,
        selfBusy = false,
        selfBusyAt = -100,
        ctrlRole = nil,
        gameStarted = nil,
        phase = nil,
        phaseInit = false,
        charTimes = {},
        lastReset = -100,
        version = 0,
        animNames = {},      -- [id] = nama animasi sendiri (modul animasi / tool)
        animTool = {},       -- [id] = nama tool / grup tempat animasi itu ditemukan
        animModuleOk = false,
        idKind = {},         -- [id] = kind | false
        lockerTrack = {},
        posHist = {},        -- [Player] = { {t, pos}, ... }
        lastSample = -100,
        t = { slow = -100, doors = -100, votes = -100, idKind = -100, phase = -100, wsDoors = -100,
            rcFunc = -100, cfg = -100 },
        warned = {},
        getTagsOk = nil,
        req = {},            -- [path] = { miss, next, pending } backoff require modul game
        rcFuncs = {},        -- [fname] = { sig, fails, dead, pending }
        rcFuncRole = nil,
        cfg = {},            -- angka gameConfig yang dibaca di thread sendiri
        cfgPending = false,
        gmiss = {},          -- [attrName] = { gap, next } globalAttr yang nggak ketemu
        gui = { gap = 2, next = 0, pg = nil, conn = nil }, -- jadwal scan PlayerGui buat role sendiri
    }

    ------------------------------------------------------------------
    -- Util dasar
    ------------------------------------------------------------------
    local function warnOnce(where, err)
        local key = tostring(where) .. ": " .. tostring(err)
        if St.warned[key] then
            return
        end
        St.warned[key] = true
        if type(ctx.warnf) == "function" then
            pcall(ctx.warnf, "[Intel] " .. key)
        end
    end

    local function try(where, fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then
            warnOnce(where, err)
        end
        return ok
    end

    local function addConn(list, signal, fn)
        if signal == nil then
            return nil
        end
        local ok, c = pcall(ctx.connect, signal, function(...)
            if ctx.alive and not ctx.alive() then
                return
            end
            local ok2, err = pcall(fn, ...)
            if not ok2 then
                warnOnce("event", err)
            end
        end)
        if ok and c then
            list[#list + 1] = c
            return c
        end
        return nil
    end

    local function disconnectAll(list)
        for _, c in ipairs(list) do
            pcall(c.Disconnect, c)
        end
    end

    local function bump()
        St.version = St.version + 1
    end

    local function settings()
        return ctx.S or {}
    end

    local function hasAny(s, list)
        for _, w in ipairs(list) do
            if string.find(s, w, 1, true) then
                return true
            end
        end
        return false
    end

    local function trim(s)
        return string.match(s, "^%s*(.-)%s*$") or s
    end

    local function rawIndex(t, k)
        return t[k]
    end

    -- index aman (tabel game bisa punya __index yang error kalau key nggak ada)
    local function index(t, k)
        if type(t) ~= "table" then
            return nil
        end
        local ok, v = pcall(rawIndex, t, k)
        if ok then
            return v
        end
        return nil
    end

    -- Value reaktif (teamMembers:get(), gameStarted:get()) -> isinya
    local function unwrap(v)
        if type(v) == "table" then
            local g = index(v, "get") or index(v, "Get")
            if type(g) == "function" then
                local ok, r = pcall(g, v)
                if ok then
                    return r
                end
                return nil
            end
        end
        return v
    end

    local function stripRich(text)
        if text == nil then
            return ""
        end
        local s = string.gsub(tostring(text), "<[^>]->", "")
        s = string.gsub(s, "&lt;", "<")
        s = string.gsub(s, "&gt;", ">")
        s = string.gsub(s, "&quot;", "\"")
        s = string.gsub(s, "&apos;", "'")
        s = string.gsub(s, "&amp;", "&")
        return s
    end

    local function cleanWord(text)
        local t = string.lower(stripRich(text))
        t = string.gsub(t, "^[%s%p]+", "")
        t = string.gsub(t, "[%s%p]+$", "")
        t = string.gsub(t, "%s+", " ")
        t = string.gsub(t, "^the ", "")
        t = string.gsub(t, "^an? ", "")
        return t
    end

    -- Teks yang isinya PERSIS nama role ("[MAFIA]", "The Doctor") -> nama resmi.
    local function exactRole(text)
        if text == nil then
            return nil
        end
        local t = cleanWord(text)
        if t == "" or #t > 24 then
            return nil
        end
        local ok, map = pcall(Game.roles, false)
        local e = ok and type(map) == "table" and map[t] or nil
        return e and e.name or nil
    end

    local function exactTeam(text)
        if text == nil then
            return nil
        end
        local t = cleanWord(text)
        if t == "" or #t > 24 then
            return nil
        end
        return Game.normalizeTeam(t)
    end

    -- Semua role (whole word) di teks lowercase, urut posisi.
    local function rolesIn(low)
        local out, seen = {}, {}
        local ok, map = pcall(Game.roles, false)
        if not ok or type(map) ~= "table" then
            return out
        end
        for key, e in pairs(map) do
            local esc = string.gsub(key, "%p", "%%%0")
            local s = string.find(low, "%f[%w]" .. esc .. "%f[%W]")
            if s and not seen[e.name] then
                seen[e.name] = true
                out[#out + 1] = { name = e.name, s = s, e = s + #key - 1 }
            end
        end
        table.sort(out, function(a, b)
            return a.s < b.s
        end)
        return out
    end

    local function findWord(low, word)
        local init = 1
        while true do
            local s, e = string.find(low, word, init, true)
            if not s then
                return nil
            end
            local before = s > 1 and string.sub(low, s - 1, s - 1) or ""
            local after = string.sub(low, e + 1, e + 1)
            if not string.find(before, "[%w_]") and not string.find(after, "[%w_]") then
                return s, e
            end
            init = s + 1
        end
    end

    local function nameOf(p)
        if not p then
            return "?"
        end
        local ok, n = pcall(rawIndex, p, "DisplayName")
        if ok and type(n) == "string" and n ~= "" then
            return n
        end
        return tostring(p.Name)
    end

    local function namesOf(p)
        local out = { p.Name, p.DisplayName }
        local rec = St.recs[p]
        if rec then
            if rec.disguise then
                out[#out + 1] = rec.disguise
            end
            if rec.redacted then
                out[#out + 1] = rec.redacted
            end
        end
        return out
    end

    local function playerByName(s)
        local l = string.lower(trim(s))
        if l == "" then
            return nil
        end
        local list = Players:GetPlayers()
        for _, p in ipairs(list) do
            if string.lower(p.Name) == l or string.lower(p.DisplayName) == l then
                return p
            end
        end
        for _, p in ipairs(list) do
            for _, n in ipairs(namesOf(p)) do
                if type(n) == "string" and string.lower(n) == l then
                    return p
                end
            end
        end
        return nil
    end

    local function resolvePlayer(v, depth)
        depth = depth or 0
        if depth > 2 or v == nil then
            return nil
        end
        local tv = typeof(v)
        if tv == "Instance" then
            if v:IsA("Player") then
                return v
            end
            if v:IsA("Model") then
                return Players:GetPlayerFromCharacter(v)
            end
            if v:IsA("ValueBase") then
                return resolvePlayer(v.Value, depth + 1)
            end
            return nil
        elseif tv == "number" then
            if v > 0 then
                local ok, p = pcall(Players.GetPlayerByUserId, Players, v)
                if ok then
                    return p
                end
            end
            return nil
        elseif tv == "string" then
            local s = trim(stripRich(v))
            if string.match(s, "^%d+$") then
                local p = resolvePlayer(tonumber(s), depth + 1)
                if p then
                    return p
                end
            end
            return playerByName(s)
        end
        return nil
    end

    -- Semua player yang namanya (Name / DisplayName / disguise) muncul whole-word di teks.
    local function playersIn(low)
        local out = {}
        for _, p in ipairs(Players:GetPlayers()) do
            local bs, be
            for _, n in ipairs(namesOf(p)) do
                if type(n) == "string" and #n >= 3 and not exactRole(n) then
                    local s, e = findWord(low, string.lower(n))
                    if s and (not bs or (e - s) > (be - bs)) then
                        bs, be = s, e
                    end
                end
            end
            if bs then
                out[#out + 1] = { p = p, s = bs, e = be }
            end
        end
        return out
    end

    local function posOf(p)
        local root = ctx.getRoot(p)
        if root then
            return root.Position
        end
        return nil
    end

    local function instPos(inst)
        if not inst then
            return nil
        end
        if inst:IsA("BasePart") then
            return inst.Position
        end
        if inst:IsA("Model") then
            local ok, cf = pcall(inst.GetPivot, inst)
            if ok and cf then
                return cf.Position
            end
        end
        local part = inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart", true)
        if part and part:IsA("BasePart") then
            return part.Position
        end
        return nil
    end

    local function isText(inst)
        return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
    end

    local function isCollector(inst)
        return inst:IsA("LayerCollector") or inst:IsA("ScreenGui") or inst:IsA("BillboardGui") or inst:IsA("SurfaceGui")
    end

    -- Visible kalau semua GuiObject di atasnya Visible dan LayerCollector-nya Enabled.
    local function guiVisible(inst)
        local node = inst
        while node do
            if isCollector(node) then
                return node.Enabled ~= false
            end
            if node:IsA("GuiObject") and node.Visible == false then
                return false
            end
            node = node.Parent
        end
        return true
    end

    local function isOwnGui(inst)
        local f = ctx.isOwnGui
        if type(f) == "function" then
            local ok, r = pcall(f, inst)
            if ok and r then
                return true
            end
        end
        return false
    end

    ------------------------------------------------------------------
    -- Record per player + view
    ------------------------------------------------------------------
    local function newStatus()
        return { dead = false, downed = false, detained = false, silenced = false, hiding = false, poisoned = false,
            ragdolled = false }
    end

    local EMPTY_VIEW = { status = newStatus() }

    local function getRec(p)
        local rec = St.recs[p]
        if not rec then
            rec = {
                player = p,
                suspects = {},
                notRoles = {},
                seenAttr = {},
                status = newStatus(),
                statusInit = false,
                view = {},
                viewVersion = -1,
            }
            rec.view.status = rec.status
            St.recs[p] = rec
        end
        return rec
    end

    local function rebuildView(rec)
        local v = rec.view
        local p = rec.player
        local cands, cn, single = nil, 0, nil
        if not (rec.role and rec.roleConf == "confirmed") then
            for role in pairs(rec.suspects) do
                if not rec.notRoles[role] and not (cands and cands[role]) then
                    cands = cands or {}
                    cands[role] = true
                    cn = cn + 1
                    single = role
                end
            end
            for role, entry in pairs(St.cand) do
                if entry.set[p] and entry.n > 1 and not rec.notRoles[role] and not (cands and cands[role]) then
                    cands = cands or {}
                    cands[role] = true
                    cn = cn + 1
                    single = role
                end
            end
        end
        v.candidates = cands
        if rec.role then
            local rt = Game.teamOf(rec.role)
            v.role = rec.role
            v.team = ((rt == nil or rt == "NEUTRAL") and rec.team) or rt
            v.confidence = rec.roleConf
            v.reason = rec.reason
        elseif rec.team then
            v.role = nil
            v.team = rec.team
            v.confidence = rec.teamConf
            v.reason = rec.teamReason
        elseif cands then
            v.role = cn == 1 and single or nil
            v.team = nil
            v.confidence = "suspect"
            local entry = cn == 1 and St.cand[single] or nil
            v.reason = (cn == 1 and (rec.suspects[single] or (entry and entry.reason))) or "candidate"
        else
            v.role, v.team, v.confidence, v.reason = nil, nil, nil, nil
        end
        v.disguise = rec.disguise
        v.status = rec.status
        rec.viewVersion = St.version
    end

    local function pushFeed(text)
        local f = St.feed
        f[#f + 1] = { t = now(), text = text }
        while #f > FEED_CAP do
            table.remove(f, 1)
        end
    end

    local function notifyFound(p, label, reason, conf, team)
        if settings().notifyRoles == false then
            return
        end
        local text
        if p == LocalPlayer then
            if St.selfNotified then
                return
            end
            St.selfNotified = true
        end
        local why = conf == "likely" and ("likely, " .. reason) or reason
        if p == LocalPlayer then
            -- sengaja bukan "You are X": toast kita bisa nyasar ke PlayerGui dan kebaca scan layar role
            text = "Detected your role: " .. label .. " (" .. why .. ")"
        else
            text = nameOf(p) .. " is " .. label .. " (" .. why .. ")"
        end
        if type(ctx.notify) == "function" then
            pcall(ctx.notify, "Role found", text, TEAM_COLORS[team or ""] or GREY, 5)
        end
    end

    -- Notif sekali per (player, role) per ronde, di level mana pun yang duluan (upgrade cuma masuk feed).
    local function maybeNotify(p, key, conf, label, reason, team)
        if (RANK[conf] or 0) < 2 then
            return
        end
        if conf ~= "confirmed" and not settings().showGuesses then
            return
        end
        local n = St.notified[p]
        if not n then
            n = {}
            St.notified[p] = n
        end
        if n[key] then
            return
        end
        n[key] = true
        notifyFound(p, label, reason, conf, team)
    end

    local dropCandidate -- forward (setRole <-> kandidat)

    -- Urutan confidence: confirmed > likely > suspect. Confirmed cuma bisa diganti confirmed (dicatat di feed).
    local function setRole(p, role, conf, reason, force)
        if not (p and role and RANK[conf]) or St.removed[p] then
            return false
        end
        local rec = getRec(p)
        if rec.notRoles[role] and conf ~= "confirmed" then
            return false
        end
        if p == LocalPlayer and St.selfLocked and not force and rec.role and rec.role ~= role then
            return false
        end
        local newR = RANK[conf]
        local curR = rec.role and RANK[rec.roleConf] or 0
        if rec.role == role then
            if newR <= curR then
                return false
            end
        elseif rec.role and not force then
            if rec.roleConf == "confirmed" then
                if conf ~= "confirmed" then
                    return false
                end
                pushFeed("Conflict: " .. nameOf(p) .. " was " .. rec.role .. ", now " .. role .. " (" .. reason .. ")")
            elseif newR < curR then
                return false
            end
        end
        local team = Game.teamOf(role)
        if not force and rec.team and rec.teamConf == "confirmed" and conf ~= "confirmed" and team and team ~= "NEUTRAL" and team ~= rec.team then
            return false
        end
        rec.role, rec.roleConf, rec.reason = role, conf, reason
        rec.suspects[role] = nil
        rec.notRoles[role] = nil
        bump()
        if newR >= 2 then
            pushFeed(nameOf(p) .. ": " .. role .. " (" .. (conf == "likely" and "likely, " or "") .. reason .. ")")
            maybeNotify(p, role, conf, role, reason, team)
        end
        if conf == "confirmed" then
            -- sudah pasti role lain -> keluar dari set kandidat role lain (bisa nyisain kandidat terakhir)
            local others
            for r2, entry in pairs(St.cand) do
                if r2 ~= role and entry.set[p] then
                    others = others or {}
                    others[#others + 1] = r2
                end
            end
            if others then
                for _, r2 in ipairs(others) do
                    dropCandidate(r2, p)
                end
            end
        end
        return true
    end

    -- Pengetahuan tim saja (contoh "EVIL TEAM") tanpa role.
    local function setTeam(p, team, conf, reason)
        if not (p and team and RANK[conf]) or St.removed[p] then
            return false
        end
        local rec = getRec(p)
        local newR = RANK[conf]
        if rec.role then
            -- Role NEUTRAL (Bodyguard) bisa berpihak ke tim mana pun, jadi bukan konflik.
            local rt = Game.teamOf(rec.role)
            if rt == "NEUTRAL" and team == "NEUTRAL" and rec.team and rec.team ~= "NEUTRAL" then
                return false -- sisi yang sudah ketahuan jangan ditimpa label "neutral"
            end
            if rt and rt ~= team and rt ~= "NEUTRAL" then
                if RANK[rec.roleConf] >= newR then
                    return false
                end
                pushFeed("Conflict: " .. nameOf(p) .. " is on " .. team .. ", not " .. rec.role .. " (" .. reason .. ")")
                rec.role, rec.roleConf, rec.reason = nil, nil, nil
            end
        end
        local curR = rec.team and RANK[rec.teamConf] or 0
        if rec.team == team then
            if newR <= curR then
                return false
            end
        elseif rec.team and newR < curR then
            return false
        elseif rec.team and rec.teamConf == "confirmed" and conf ~= "confirmed" then
            return false
        end
        rec.team, rec.teamConf, rec.teamReason = team, conf, reason
        bump()
        if newR >= 2 and not rec.role then
            pushFeed(nameOf(p) .. ": " .. team .. " team (" .. reason .. ")")
            maybeNotify(p, "team:" .. team, conf, team .. " team", reason, team)
        end
        return true
    end

    local function addSuspect(p, role, reason)
        if not (p and role) then
            return
        end
        local rec = getRec(p)
        if rec.notRoles[role] or rec.role == role or rec.suspects[role] then
            return
        end
        rec.suspects[role] = reason
        bump()
    end

    local function markNotRole(p, role)
        local rec = getRec(p)
        rec.notRoles[role] = true
        rec.suspects[role] = nil
        if rec.role == role and rec.roleConf ~= "confirmed" then
            rec.role, rec.roleConf, rec.reason = nil, nil, nil
        end
        bump()
        dropCandidate(role, p)
    end

    ------------------------------------------------------------------
    -- Kandidat berdasarkan jarak (Doctor / Witch / Saboteur / Janitor)
    ------------------------------------------------------------------
    -- ignoreStatus: buat deduksi yang nggak butuh dia masih bisa bergerak (kandidat terakhir, Harbinger mati)
    local function eligible(p, role, ignoreStatus)
        if not p or St.removed[p] then
            return false -- sudah keluar dari server
        end
        local rec = St.recs[p]
        if p == LocalPlayer and not (rec and rec.role == role) then
            return false -- diri sendiri cuma kalau memang role kita
        end
        if not rec then
            return true
        end
        local s = rec.status
        if not ignoreStatus and (s.dead or s.downed or s.detained) then
            return false
        end
        if rec.notRoles[role] then
            return false
        end
        if rec.role and rec.role ~= role and rec.roleConf == "confirmed" then
            return false
        end
        local rt = Game.teamOf(role)
        if rt and rt ~= "NEUTRAL" and rec.team and rec.teamConf == "confirmed" and rec.team ~= rt then
            return false
        end
        return true
    end

    -- Keluarkan p dari set kandidat role; sisa satu -> dia "kandidat terakhir" (confirmed).
    dropCandidate = function(role, p)
        local entry = St.cand[role]
        if not (entry and entry.set[p]) then
            return
        end
        entry.set[p] = nil
        local n, last = 0, nil
        for q in pairs(entry.set) do
            n = n + 1
            last = q
        end
        entry.n = n
        bump()
        if n == 0 then
            St.cand[role] = nil
        elseif n == 1 and eligible(last, role, true) then
            setRole(last, role, "confirmed", "last candidate left")
        end
    end

    -- Jarak terdekat dalam ~1.5 detik terakhir (Doctor tp-heal-return cuma mampir sebentar).
    local function minDistance(p, pos)
        local best
        local cur = posOf(p)
        if cur then
            best = (cur - pos).Magnitude
        end
        local hist = St.posHist[p]
        if hist then
            local t = now()
            for _, h in ipairs(hist) do
                if t - h[1] <= 1.5 then
                    local d = (h[2] - pos).Magnitude
                    if not best or d < best then
                        best = d
                    end
                end
            end
        end
        return best
    end

    local function playersNear(pos, radius, role, exclude)
        local set, n = {}, 0
        if not pos then
            return set, n
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= exclude and eligible(p, role) then
                local d = minDistance(p, pos)
                if d and d <= radius then
                    set[p] = true
                    n = n + 1
                end
            end
        end
        return set, n
    end

    -- Irisan kandidat antar event; sisa 1 -> confirmed. Irisan kosong -> mulai lagi dari set terbaru.
    local function candidateEvent(role, set, n, reasonSingle, reasonMulti, label)
        -- set bisa ditangkap beberapa ratus ms lalu: buang yang sudah keluar / nggak eligible lagi
        local fresh = {}
        n = 0
        for p in pairs(set) do
            if eligible(p, role) then
                fresh[p] = true
                n = n + 1
            end
        end
        set = fresh
        if n <= 0 then
            return
        end
        local entry = St.cand[role]
        local usedInter = false
        if entry then
            local inter, k = {}, 0
            for p in pairs(set) do
                if entry.set[p] and eligible(p, role) then
                    inter[p] = true
                    k = k + 1
                end
            end
            if k > 0 then
                set, n, usedInter = inter, k, true
            end
        end
        St.cand[role] = { set = set, n = n, reason = label }
        bump()
        if n == 1 then
            local p = next(set)
            setRole(p, role, "confirmed", usedInter and reasonMulti or reasonSingle)
        end
    end

    ------------------------------------------------------------------
    -- Animasi
    ------------------------------------------------------------------
    local function classifyAnim(name)
        if type(name) ~= "string" or name == "" then
            return nil
        end
        local l = string.lower(name)
        if hasAny(l, K.HIDE_WORDS) then
            return "HIDE"
        end
        if hasAny(l, K.SKIP_WORDS) then
            return nil
        end
        if hasAny(l, K.STAB_WORDS) then
            return "STAB"
        end
        if hasAny(l, K.SHOT_WORDS) then
            return "SHOT"
        end
        return nil
    end

    -- Animasi milik tool / grup ("Revolver" > "Inspect"): yang dinilai nama animasinya sendiri.
    -- Nama tool cuma dipakai kalau nama animasinya generik ("Attack", "Use", "1").
    local function classifyToolAnim(toolName, animName)
        local kind = classifyAnim(animName)
        if kind or type(toolName) ~= "string" or type(animName) ~= "string" then
            return kind
        end
        local al = string.lower(animName)
        if hasAny(al, K.SKIP_WORDS) then
            return nil
        end
        local generic = string.match(al, "^%d+$") or string.find(al, "%f[%a]attack") or string.find(al, "%f[%a]strike")
            or string.find(al, "%f[%a]use%f[%A]")
        if not generic then
            return nil
        end
        local tl = string.lower(toolName)
        if hasAny(tl, K.STAB_WORDS) then
            return "STAB"
        end
        if hasAny(tl, K.SHOT_WORDS) or hasAny(tl, K.GUN_TOOLS) then
            return "SHOT"
        end
        return nil
    end

    -- v2.1: ID animasi serangan asli dari assets.animations.player1 (KnifeSwing / Glock).
    local attackIds, attackIdsAt = nil, -100
    local function attackKinds()
        if attackIds and (next(attackIds) ~= nil or now() - attackIdsAt < 10) then
            return attackIds
        end
        attackIds, attackIdsAt = {}, now()
        local folder = Game.resolve("assets.animations.player1")
        if folder then
            for _, a in ipairs(folder:GetChildren()) do
                if a:IsA("Animation") then
                    local n = string.lower(a.Name)
                    local aid = Game.normalizeId(a.AnimationId)
                    if aid and n == "knifeswing" then
                        attackIds[aid] = "STAB"
                    elseif aid and n == "glock" then
                        attackIds[aid] = "SHOT"
                    end
                end
            end
        end
        return attackIds
    end

    local function animKind(track)
        local anim = track.Animation
        local id = anim and Game.normalizeId(anim.AnimationId)
        if id == "0" then
            id = nil
        end
        local known = attackKinds()
        if next(known) ~= nil then
            -- Mode ketat: cuma ID asli yang dihitung serangan; sisanya cuma dicek buat "sembunyi".
            if id and known[id] then
                return known[id]
            end
            local nm = (id and Game.animationName(id)) or (anim and anim.Name) or track.Name
            if classifyAnim(nm) == "HIDE" then
                return "HIDE"
            end
            return nil
        end
        if id then
            local cached = St.idKind[id]
            if cached ~= nil then
                return cached or nil
            end
        end
        local kind
        if id then
            local nm = St.animNames[id]
            if nm then
                kind = classifyToolAnim(St.animTool[id], nm)
            else
                kind = classifyAnim(Game.animationName(id))
            end
        end
        if not kind and anim and anim.Name ~= "Animation" then
            kind = classifyAnim(anim.Name)
        end
        if not kind and track.Name ~= "Animation" then
            kind = classifyAnim(track.Name)
        end
        if id then
            St.idKind[id] = kind or false
        end
        return kind
    end

    local function onAnimPlayed(p, track)
        if not track then
            return
        end
        local kind = animKind(track)
        if not kind then
            return
        end
        if kind == "HIDE" then
            St.lockerTrack[p] = track
            return
        end
        St.lastAttack[p] = { t = now(), kind = kind }
        local night = Game.isNight()
        if kind == "STAB" then
            if night == true then
                setRole(p, "Mafia", "confirmed", "swung a knife at night")
            elseif night == nil then
                setRole(p, "Mafia", "likely", "swung a knife")
            else
                addSuspect(p, "Mafia", "swung a knife by day")
            end
        else
            if night == true then
                setRole(p, "Mafia", "confirmed", "fired a gun at night")
            elseif night == false then
                setRole(p, "Vigilante", "confirmed", "fired a gun in daylight")
            else
                addSuspect(p, "Mafia", "fired a gun")
                addSuspect(p, "Vigilante", "fired a gun")
            end
        end
    end

    -- id animasi dari modul assets.animations.player1 (SummitX pakai tabel { Knife = id, Glock = id }).
    local function loadAnimNames()
        local added = 0
        local function walk(t, prefix, depth)
            local seen = 0
            for k, v in pairs(t) do
                seen = seen + 1
                if seen > 300 then
                    break
                end
                local name = prefix ~= "" and (prefix .. "." .. tostring(k)) or tostring(k)
                local tv = typeof(v)
                local id
                if tv == "string" or tv == "number" then
                    id = Game.normalizeId(v)
                elseif tv == "Instance" and v:IsA("Animation") then
                    id = Game.normalizeId(v.AnimationId)
                elseif tv == "table" and depth < 3 then
                    walk(v, name, depth + 1)
                end
                if id and #id >= 5 and St.animNames[id] == nil then
                    -- { Knife = { Inspect = id } }: nilai "Inspect", grup "Knife" cuma konteks
                    St.animNames[id] = tostring(k)
                    St.animTool[id] = prefix ~= "" and prefix or nil
                    added = added + 1
                end
            end
        end
        local m = Game.require("assets.animations.player1")
        if type(m) == "table" then
            walk(m, "", 0)
            St.animModuleOk = true
        end
        if added > 0 then
            St.idKind = {}
        end
    end

    local function scanToolAnims(tool)
        for _, d in ipairs(tool:GetDescendants()) do
            if d:IsA("Animation") then
                local id = Game.normalizeId(d.AnimationId)
                if id and id ~= "0" and St.animNames[id] == nil then
                    St.animNames[id] = d.Name
                    St.animTool[id] = tool.Name
                    St.idKind[id] = nil
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Tool
    ------------------------------------------------------------------
    local function onToolAdded(p, tool, equipped)
        if St.toolSeen[tool] then
            return
        end
        St.toolSeen[tool] = true
        try("toolAnims", scanToolAnims, tool)
        local l = string.lower(tool.Name)
        local how = equipped and "holding" or "carries"
        if string.find(l, "glock", 1, true) then
            setRole(p, "Mafia", "likely", how .. " the Glock")
        elseif string.find(l, "knife", 1, true) then
            setRole(p, "Mafia", "likely", how .. " a knife")
        elseif hasAny(l, K.GUN_TOOLS) then
            addSuspect(p, "Vigilante", how .. " a gun")
        elseif string.find(l, "banana", 1, true) then
            setRole(p, "Saboteur", "likely", how .. " a banana")
        elseif string.find(l, "medkit", 1, true) then
            pushFeed(nameOf(p) .. " has a medkit")
        end
    end

    local function scanTools(p)
        local char = p.Character
        if char then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") then
                    onToolAdded(p, c, true)
                end
            end
        end
        local bp = p:FindFirstChildOfClass("Backpack")
        if bp then
            for _, c in ipairs(bp:GetChildren()) do
                if c:IsA("Tool") then
                    onToolAdded(p, c, false)
                end
            end
        end
    end

    -- Senjata api yang lagi dipegang: "glock" (punya Mafia), "gun" (senjata lain), nil.
    local function heldWeapon(p)
        local char = p and p.Character
        if not char then
            return nil
        end
        local found
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Tool") then
                local l = string.lower(c.Name)
                if string.find(l, "glock", 1, true) then
                    return "glock"
                end
                if hasAny(l, K.GUN_TOOLS) then
                    found = "gun"
                end
            end
        end
        return found
    end

    ------------------------------------------------------------------
    -- Snapshot attribute / tag / ValueObject (sekali per refresh, bukan Game.flag per nama)
    ------------------------------------------------------------------
    -- Nilai pertama menang, KECUALI yang lama falsy dan yang baru truthy (Player.Downed=false tapi
    -- Character.Downed=true -> downed).
    local function putSnap(snap, lk, v)
        local old = snap.a[lk]
        if old == nil or (not Game.truthy(old) and Game.truthy(v)) then
            snap.a[lk] = v
        end
    end

    local function addAttrs(snap, inst, where)
        local ok, attrs = pcall(inst.GetAttributes, inst)
        if ok and type(attrs) == "table" then
            for k, v in pairs(attrs) do
                putSnap(snap, string.lower(k), v)
                snap.raw[#snap.raw + 1] = { name = k, value = v, where = where }
            end
        end
    end

    local function addValues(snap, inst)
        for _, c in ipairs(inst:GetChildren()) do
            if c:IsA("ValueBase") then
                local v = c.Value
                putSnap(snap, string.lower(c.Name), v)
                snap.raw[#snap.raw + 1] = { name = c.Name, value = v, where = "value" }
            end
        end
    end

    local function addTags(snap, inst)
        if not CollectionService then
            return
        end
        if St.getTagsOk ~= false then
            local ok, list = pcall(CollectionService.GetTags, CollectionService, inst)
            if ok and type(list) == "table" then
                St.getTagsOk = true
                for _, t in ipairs(list) do
                    snap.tags[string.lower(tostring(t))] = true
                end
                return
            end
            if St.getTagsOk == nil then
                St.getTagsOk = false
            end
        end
        for _, name in ipairs(K.TAG_NAMES) do
            local ok, has = pcall(CollectionService.HasTag, CollectionService, inst, name)
            if ok and has then
                snap.tags[string.lower(name)] = true
            end
        end
    end

    local function snapshot(p)
        local snap = { a = {}, raw = {}, tags = {} }
        local char = p.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        addAttrs(snap, p, "player")
        if char then
            addAttrs(snap, char, "character")
        end
        if hum then
            addAttrs(snap, hum, "humanoid")
        end
        if char then
            addValues(snap, char)
        end
        addValues(snap, p)
        addTags(snap, p)
        if char then
            addTags(snap, char)
        end
        return snap, char, hum
    end

    local function flag(snap, lname)
        return Game.truthy(snap.a[lname]) or snap.tags[lname] == true
    end

    local function anyFlag(snap, list)
        for _, n in ipairs(list) do
            if flag(snap, n) then
                return true
            end
        end
        return false
    end

    local function computeStatus(p, rec, snap, char, hum, prev)
        local s = {}
        local dead = anyFlag(snap, K.STATUS_KEYS.dead)
        if not dead then
            if hum then
                dead = hum.Health <= 0
            else
                dead = prev.dead -- tanpa Humanoid nggak ada info darah: pakai nilai lama
            end
        end
        -- sudah mati ronde ini: karakter baru (spectator / respawn) tetap dihitung mati sampai ronde baru
        s.dead = dead or rec.diedRound == true
        s.downed = anyFlag(snap, K.STATUS_KEYS.downed)
        s.detained = anyFlag(snap, K.STATUS_KEYS.detained)
        s.silenced = anyFlag(snap, K.STATUS_KEYS.silenced)
        local hiding = anyFlag(snap, K.STATUS_KEYS.hiding)
        if not hiding then
            local tr = St.lockerTrack[p]
            if tr then
                if tr.IsPlaying then
                    hiding = true
                else
                    St.lockerTrack[p] = nil
                end
            end
        end
        if not hiding and hum then
            local seat = hum.SeatPart
            if seat and (seat:FindFirstAncestor("Lockers") or seat:FindFirstAncestor("Closets")) then
                hiding = true
            end
        end
        s.hiding = hiding
        s.poisoned = flag(snap, "poisonapplied") and not flag(snap, "poisoncured")
        s.ragdolled = anyFlag(snap, K.STATUS_KEYS.ragdolled)
        if not char then
            -- karakter hilang (badan dibuang): flag karakter nggak kebaca, jangan dianggap "bangun lagi"
            for k, v in pairs(prev) do
                if v == true then
                    s[k] = true
                end
            end
        end
        return s
    end

    -- Attribute / ValueObject yang isinya persis nama role / tim.
    local function scanRoleAttrs(p, rec, snap)
        for _, it in ipairs(snap.raw) do
            local v = it.value
            if type(v) == "string" and v ~= "" and #v <= 32 then
                local key = it.where .. ":" .. it.name
                if rec.seenAttr[key] ~= v then
                    rec.seenAttr[key] = v
                    local ln = string.lower(it.name)
                    local roleish = hasAny(ln, K.ROLEISH)
                    if not hasAny(ln, K.IGNORE_ATTR) and (it.where ~= "value" or roleish) then
                        -- "Role" / "currentRole" -> confirmed; "SomethingRole" / nama lain -> likely
                        local conf = K.ROLE_ATTR_EXACT[ln] and "confirmed" or "likely"
                        local src = (it.where == "value" and "value " or "attribute ") .. it.name
                        local role = exactRole(v)
                        if role then
                            setRole(p, role, conf, src)
                        elseif roleish then
                            -- kata tim umum ("Good", "Innocent") cuma dipercaya di attribute yang memang soal tim/role
                            local team = exactTeam(v)
                            if team then
                                setTeam(p, team, conf, src)
                            end
                        end
                    end
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Event status: downed, revive, mati, silence, cure
    ------------------------------------------------------------------
    local function attributeAttack(victim, downed)
        local vpos = posOf(victim)
        local t = now()
        local best, bestT, kind
        if vpos then
            for p, a in pairs(St.lastAttack) do
                if p ~= victim and p ~= LocalPlayer and t - a.t <= 4 and (not bestT or a.t > bestT) then
                    local d = minDistance(p, vpos)
                    if d and d <= 40 then
                        best, bestT, kind = p, a.t, a.kind
                    end
                end
            end
        end
        if best then
            St.killedAt[victim] = t
            local night = Game.isNight()
            local vn = nameOf(victim)
            pushFeed(nameOf(best) .. (downed and " downed " or " killed ") .. vn)
            if kind ~= "SHOT" then
                setRole(best, "Mafia", "confirmed", "stabbed " .. vn .. (night and " at night" or ""))
            elseif night == true then
                setRole(best, "Mafia", "confirmed", "shot " .. vn .. " at night")
            elseif night == false then
                setRole(best, "Vigilante", "confirmed", "shot " .. vn .. " in daylight")
            else
                -- fase nggak kebaca: tembakan bisa Mafia (Glock) atau Vigilante, lihat senjatanya
                local w = heldWeapon(best)
                if w == "glock" then
                    setRole(best, "Mafia", "likely", "shot " .. vn .. " with the Glock")
                elseif w == "gun" then
                    setRole(best, "Vigilante", "likely", "shot " .. vn .. " with a gun")
                else
                    addSuspect(best, "Mafia", "shot " .. vn)
                    addSuspect(best, "Vigilante", "shot " .. vn)
                end
            end
            return true
        elseif downed then
            pushFeed(nameOf(victim) .. " went down")
        end
        return false
    end

    local function onDowned(victim)
        local last = St.attributed[victim]
        if last and now() - last < 5 then
            return
        end
        St.attributed[victim] = now()
        attributeAttack(victim, true)
    end

    -- Mati karena serangan orang (atau kehabisan darah setelah downed) -> bukan Harbinger yang salah tebak.
    local function onDied(p, rec, wasDowned)
        if not rec.deadFed then
            rec.deadFed = true
            pushFeed(nameOf(p) .. " died")
        end
        rec.diedRound = true
        local t = now()
        local last = St.attributed[p]
        if not last or t - last >= 5 then
            St.attributed[p] = t
            attributeAttack(p, false)
        end
        local killed = wasDowned == true or (St.killedAt[p] ~= nil and t - St.killedAt[p] <= 20)
        St.recentDeaths[#St.recentDeaths + 1] = { p = p, t = t, killed = killed }
        while #St.recentDeaths > 12 do
            table.remove(St.recentDeaths, 1)
        end
        local w = St.harbWatch
        if w and t - w.t <= 8 and p ~= w.exclude and not killed and eligible(p, "Harbinger", true) then
            St.harbWatch = nil
            setRole(p, "Harbinger", "confirmed", "died calling out the wrong role")
        end
    end

    -- Radius dari gameConfig, dibaca di thread scan (require bisa yield); event cuma baca cache.
    local function cfgNum(name)
        return St.cfg[name] or K.CFG_DEFAULTS[name]
    end

    local function onSilenced(p)
        pushFeed(nameOf(p) .. " was silenced")
        local set, n = playersNear(posOf(p), cfgNum("maxSilenceDistance"), "Witch", p)
        candidateEvent("Witch", set, n, "only one in reach when " .. nameOf(p) .. " was silenced",
            "in reach of every silence", "near a silence")
    end

    local function onCured(p)
        pushFeed(nameOf(p) .. " was cured of poison")
        local set, n = playersNear(posOf(p), 12, "Doctor", p)
        candidateEvent("Doctor", set, n, "cured " .. nameOf(p) .. "'s poison", "in reach of every save", "near a save")
    end

    local function transitions(p, rec, prev, cur, cured, wound)
        if cur.dead and not prev.dead then
            onDied(p, rec, prev.downed)
        end
        if not cur.dead then
            if (cur.downed and not prev.downed) or (wound and not rec.wound) then
                onDowned(p)
            end
            if prev.downed and not cur.downed then
                -- dicek lagi sebentar lagi: Downed hilang bisa juga karena mati
                local set, n = playersNear(posOf(p), 12, "Doctor", p)
                St.pendingRevive[#St.pendingRevive + 1] = { victim = p, t = now(), set = set, n = n }
            end
            if cur.silenced and not prev.silenced then
                onSilenced(p)
            end
            if cured and not rec.cured then
                onCured(p)
            end
        end
        if cur.poisoned and not prev.poisoned then
            pushFeed(nameOf(p) .. " was poisoned")
        end
        if cur.detained and not prev.detained then
            pushFeed(nameOf(p) .. " was detained")
        end
    end

    local function refresh(p)
        if not p then
            return
        end
        local rec = getRec(p)
        local snap, char, hum = snapshot(p)
        rec.snap = snap
        local prev = rec.status
        local cur = computeStatus(p, rec, snap, char, hum, prev)
        local dn = snap.a["disguisename"]
        local disg = nil
        if type(dn) == "string" and dn ~= "" and dn ~= p.Name and dn ~= p.DisplayName then
            disg = dn
        end
        if disg ~= rec.disguise then
            rec.disguise = disg
            bump()
        end
        local rl = snap.a["redactedlabel"]
        rec.redacted = (type(rl) == "string" and rl ~= "") and rl or nil
        try("roleAttrs", scanRoleAttrs, p, rec, snap)
        local cured = flag(snap, "poisoncured")
        local wound = flag(snap, "knifewound") or flag(snap, "cheaptrickshot")
        if rec.statusInit then
            try("transitions", transitions, p, rec, prev, cur, cured, wound)
        end
        rec.statusInit = true
        rec.cured, rec.wound = cured, wound
        local changed = false
        for k, v in pairs(cur) do
            if prev[k] ~= v then
                prev[k] = v
                changed = true
            end
        end
        if changed then
            bump()
        end
    end

    local function processPending()
        local t = now()
        if #St.pendingRevive > 0 then
            local keep = {}
            for _, e in ipairs(St.pendingRevive) do
                if t - e.t >= 0.3 then
                    local rec = St.recs[e.victim]
                    if rec and not rec.status.dead and not rec.status.downed then
                        pushFeed(nameOf(e.victim) .. " got back up")
                        candidateEvent("Doctor", e.set, e.n, "revived " .. nameOf(e.victim), "in reach of every save",
                            "near a save")
                    end
                else
                    keep[#keep + 1] = e
                end
            end
            St.pendingRevive = keep
        end
        if #St.doorEvents > 0 then
            local list = St.doorEvents
            local keep = {}
            for _, e in ipairs(list) do
                if not e.done and t - e.t >= 0.6 then
                    e.done = true
                    -- banyak pintu berubah barengan = reset ronde / fase, bukan ulah orang
                    local burst = 0
                    for _, o in ipairs(list) do
                        if math.abs(o.t - e.t) <= 1 then
                            burst = burst + 1
                        end
                    end
                    if burst <= 2 then
                        candidateEvent(e.role, e.set, e.n, e.single, e.multi, e.label)
                    end
                end
                if t - e.t < 3 then
                    keep[#keep + 1] = e
                end
            end
            St.doorEvents = keep
        end
        if St.harbWatch and t - St.harbWatch.t > 8 then
            St.harbWatch = nil
        end
    end

    ------------------------------------------------------------------
    -- Pintu (Locked) dan pisang
    ------------------------------------------------------------------
    local function onDoorChanged(inst)
        local locked = Game.truthy(inst:GetAttribute("Locked"))
        local prev = St.doors[inst]
        St.doors[inst] = locked
        if prev == nil or prev == locked then
            return
        end
        local pos = instPos(inst)
        if not pos then
            return
        end
        local e = { t = now() }
        if locked then
            e.role = "Saboteur"
            e.set, e.n = playersNear(pos, cfgNum("maxSabotageDistance"), "Saboteur", nil)
            e.single, e.multi, e.label = "only one who could have locked that door", "in reach of every lock and banana",
                "near a locked door"
            pushFeed("A door was locked")
        else
            e.role = "Janitor"
            e.set, e.n = playersNear(pos, cfgNum("maxCleanupDistance"), "Janitor", nil)
            e.single, e.multi, e.label = "only one who could have unlocked that door",
                "in reach of every unlock and cleanup", "near an unlocked door"
        end
        St.doorEvents[#St.doorEvents + 1] = e
    end

    -- Koneksi pintu disimpan per pintu (bukan di St.conns) supaya bisa diputus waktu map diganti.
    local function unhookDoor(d)
        local c = St.doorConns[d]
        if c then
            pcall(c.Disconnect, c)
        end
        St.doorConns[d] = nil
        St.doors[d] = nil
    end

    local function hookDoor(inst)
        St.doors[inst] = Game.truthy(inst:GetAttribute("Locked"))
        St.doorCount = St.doorCount + 1
        local ok, sig = pcall(inst.GetAttributeChangedSignal, inst, "Locked")
        if ok and sig then
            St.doorConns[inst] = addConn({}, sig, function()
                onDoorChanged(inst)
            end)
        end
    end

    local function scanDoors()
        local count = 0
        local gone = {}
        for d in pairs(St.doors) do
            if d.Parent then
                count = count + 1
            else
                gone[#gone + 1] = d
            end
        end
        for _, d in ipairs(gone) do
            unhookDoor(d)
        end
        St.doorCount = count
        local map = Workspace:FindFirstChild("Map")
        local root = (map and map:FindFirstChild("Doors")) or map or Workspace
        if root == Workspace then
            -- tanpa Map: scan seluruh workspace mahal, cukup tiap 60 detik
            if now() - St.t.wsDoors < 60 then
                return
            end
            St.t.wsDoors = now()
        end
        for _, d in ipairs(root:GetDescendants()) do
            if St.doorCount >= 300 then
                break
            end
            if St.doors[d] == nil and d:GetAttribute("Locked") ~= nil then
                hookDoor(d)
            end
        end
    end

    local function onWorkspaceDescendant(inst)
        local name = inst.Name
        if type(name) ~= "string" or not string.find(string.lower(name), "banana", 1, true) then
            return
        end
        if St.bananaSeen[inst] then
            return
        end
        -- masih dipegang (di dalam karakter / backpack) -> itu urusan rule tool. Jangan ditandai "seen":
        -- instance yang sama nanti di-drop ke workspace dan harus tetap kehitung.
        local model = inst:FindFirstAncestorOfClass("Model")
        while model do
            if Players:GetPlayerFromCharacter(model) then
                return
            end
            model = model:FindFirstAncestorOfClass("Model")
        end
        if inst:FindFirstAncestorOfClass("Backpack") then
            return
        end
        St.bananaSeen[inst] = true
        local pos = instPos(inst)
        if not pos then
            return
        end
        local lb = St.lastBanana
        if lb and now() - lb.t < 2 and (lb.pos - pos).Magnitude < 6 then
            return
        end
        St.lastBanana = { t = now(), pos = pos }
        pushFeed("A banana was dropped")
        local set, n = playersNear(pos, 10, "Saboteur", nil)
        candidateEvent("Saboteur", set, n, "only one standing where a fresh banana dropped",
            "in reach of every lock and banana", "near a banana")
    end

    ------------------------------------------------------------------
    -- Chat / pengumuman
    ------------------------------------------------------------------
    local function channelTeam(name)
        if type(name) ~= "string" then
            return nil
        end
        local role = exactRole(name)
        if role then
            return Game.teamOf(role)
        end
        return exactTeam(name)
    end

    local function causeHint(low)
        for _, h in ipairs(K.CAUSE_HINTS) do
            if string.find(low, h[1], 1, true) then
                return h[2]
            end
        end
        return nil
    end

    local function harbVerdict(correct)
        local h = St.harb
        St.harb = nil
        if not h or now() - h.t > 60 then
            return
        end
        local who = h.p and nameOf(h.p) or h.name
        if correct then
            pushFeed("Harbinger was right about " .. who)
            if h.p then
                if h.role then
                    setRole(h.p, h.role, "confirmed", "Harbinger call")
                elseif h.team then
                    setTeam(h.p, h.team, "confirmed", "Harbinger call")
                end
            end
            return
        end
        pushFeed("Harbinger was wrong about " .. who)
        if h.p and h.role then
            markNotRole(h.p, h.role)
        end
        -- Harbinger mati karena salah tebak: yang barusan mati, atau yang mati dalam 8 detik.
        -- Yang dibunuh orang / sudah pasti role lain dilewati (watch tetap terbuka).
        local t = now()
        for i = #St.recentDeaths, 1, -1 do
            local d = St.recentDeaths[i]
            if t - d.t <= 3 and d.p ~= h.p and not d.killed and eligible(d.p, "Harbinger", true) then
                setRole(d.p, "Harbinger", "confirmed", "died calling out the wrong role")
                return
            end
        end
        St.harbWatch = { t = t, exclude = h.p }
    end

    local function handleSystem(text)
        local low = string.lower(text)
        local tName, tRole = string.match(low, "the harbinger thinks (.-) is an? ([%a ]+)%.")
        if tName then
            local p = resolvePlayer(tName)
            local role = Game.matchRole(tRole)
            local team = (not role) and Game.normalizeTeam(tRole) or nil
            St.harb = { p = p, role = role, team = team, t = now(), name = tName }
            pushFeed("Harbinger called " .. (p and nameOf(p) or tName) .. " " .. (role or team or trim(tRole)))
        end
        if string.find(low, "harbinger was correct", 1, true) or string.find(low, "harbinger was right", 1, true) then
            harbVerdict(true)
            return
        end
        if string.find(low, "harbinger was incorrect", 1, true) or string.find(low, "harbinger was wrong", 1, true) then
            harbVerdict(false)
            return
        end
        if tName then
            return
        end
        -- Generik: tepat satu player + satu role, role disebut SETELAH nama.
        local found = playersIn(low)
        if #found ~= 1 then
            return
        end
        local p, ne = found[1].p, found[1].e
        local deathy = hasAny(low, K.DEATH_WORDS)
        local hint = causeHint(low)
        if hint then
            if settings().showGuesses then
                setRole(p, hint, "likely", "death cause")
            end
            return
        end
        if string.find(low, "mafia's side", 1, true) or string.find(low, "side of the mafia", 1, true)
            or string.find(low, "not of the mafia", 1, true) then
            if deathy then
                setTeam(p, "EVIL", "confirmed", "revealed on death")
            end
            return
        end
        local roles = rolesIn(low)
        if #roles == 0 then
            local team
            if string.find(low, "of the veil", 1, true) or string.find(low, "veil team", 1, true) then
                team = "VEIL"
            elseif string.find(low, "evil team", 1, true) then
                team = "EVIL"
            elseif string.find(low, "town team", 1, true) then
                team = "TOWN"
            end
            if team and deathy then
                setTeam(p, team, "confirmed", "revealed on death")
            end
            return
        end
        if #roles ~= 1 then
            return
        end
        local r = roles[1]
        if r.s <= ne then
            return -- "The Mafia killed X": role-nya pelaku, bukan X
        end
        local between = string.sub(low, ne + 1, r.s - 1)
        if #between > 40 or string.find(between, " by ", 1, true) or string.find(between, "think", 1, true)
            or string.find(between, "guess", 1, true) or string.find(between, "accus", 1, true) then
            return
        end
        if string.find(between, " not ", 1, true) or string.find(between, "n't", 1, true) then
            markNotRole(p, r.name)
            return
        end
        local linked = string.find(between, "was", 1, true) or string.find(between, "were", 1, true)
            or string.find(between, "belonged", 1, true) or string.find(between, " is ", 1, true)
            or string.find(between, "role", 1, true)
        if linked and deathy then
            setRole(p, r.name, "confirmed", "revealed on death")
        elseif settings().showGuesses then
            setRole(p, r.name, "likely", "announcement")
        end
    end

    local function onChatMessage(raw, isSystem, userId, channelName)
        local text = trim(stripRich(raw))
        if text == "" then
            return
        end
        -- v2.1: chat pemain di game ini lewat jalur sistem ("Fallon: ..."). Itu bukan pengumuman.
        if isSystem then
            local speaker = string.match(text, "^([^:]+):%s")
            if speaker and #speaker <= 40 and playerByName(speaker) then
                isSystem = false
            elseif type(raw) == "string" and string.find(raw, "^%s*<font[^>]*><b>[^<]+:</b>") then
                isSystem = false
            end
        end
        local key = (isSystem and "S:" or "U:") .. text
        local seen = St.recentMsgs[key]
        if seen and now() - seen < 2 then
            return
        end
        St.recentMsgs[key] = now()
        if not isSystem then
            -- pesan di channel tim (nama channel = role / tim) -> pengirimnya satu tim
            local team = channelTeam(channelName)
            if team and userId then
                local p = resolvePlayer(userId)
                if p then
                    setTeam(p, team, "confirmed", "team chat")
                end
            end
            return
        end
        handleSystem(text)
    end

    local function onTCSMessage(message)
        if not message then
            return
        end
        local src = message.TextSource
        local ch = message.TextChannel
        onChatMessage(message.Text, src == nil, src and src.UserId, ch and ch.Name)
    end

    ------------------------------------------------------------------
    -- Scan berkala (tiap 2 detik)
    ------------------------------------------------------------------
    -- Label tim di tag: cuma yang jelas label tim ("EVIL TEAM", "THE VEIL", "EVIL"), bukan kata umum
    -- kayak "Innocent" / "Town" yang bisa saja nama / status.
    local function tagTeam(text)
        local t = cleanWord(text)
        if t == "evil" or t == "veil" then
            return string.upper(t)
        end
        if string.match(t, "^[%a ]+ team$") and #t <= 24 then
            return Game.normalizeTeam(t)
        end
        return nil
    end

    -- names: [cleanWord(nama)] = true; baris yang cuma nama player (nametag "Witch") bukan tag role.
    local function tagTextRole(text, names)
        local raw = stripRich(text)
        for line in string.gmatch(raw, "[^\n]+") do
            if not names[cleanWord(line)] then
                local role = exactRole(line)
                local team = nil
                for inner in string.gmatch(line, "%[([^%]]+)%]") do
                    if not names[cleanWord(inner)] then
                        role = role or exactRole(inner)
                        team = team or tagTeam(inner)
                    end
                end
                if role then
                    return role, nil
                end
                team = tagTeam(line) or team
                if team then
                    return nil, team
                end
            end
        end
        return nil, nil
    end

    -- Tag Billboard/SurfaceGui di karakter. Tag visible -> confirmed, tersembunyi -> likely. Dua-duanya
    -- dibuang kalau tag yang sama nempel di banyak karakter (template / label umum).
    local function scanCharTags()
        local found, count, seen = {}, {}, {}
        local list = Players:GetPlayers()
        for _, p in ipairs(list) do
            local char = p.Character
            if char then
                -- nama dia sendiri (username / display / disguise): nametag, bukan tag role
                local names = {}
                for _, n in ipairs(namesOf(p)) do
                    if type(n) == "string" and n ~= "" then
                        names[cleanWord(n)] = true
                    end
                end
                for _, d in ipairs(char:GetDescendants()) do
                    if isText(d) then
                        local g = d.Parent
                        while g and g ~= char and not (g:IsA("BillboardGui") or g:IsA("SurfaceGui")) do
                            g = g.Parent
                        end
                        if g and g ~= char and not isOwnGui(d) then
                            local role, team = tagTextRole(d.Text, names)
                            if role or team then
                                local vis = guiVisible(d)
                                local key = (vis and "v:" or "h:") .. (role or ("team:" .. team))
                                local mine = seen[p]
                                if not mine then
                                    mine = {}
                                    seen[p] = mine
                                end
                                if not mine[key] then
                                    mine[key] = true
                                    count[key] = (count[key] or 0) + 1
                                    found[#found + 1] = { p = p, role = role, team = team, key = key, vis = vis }
                                end
                            end
                        end
                    end
                end
            end
        end
        local hiddenLimit = math.max(2, math.floor(#list * 0.4))
        local visLimit = math.max(3, math.floor(#list * 0.4))
        for _, h in ipairs(found) do
            if h.vis and count[h.key] <= visLimit then
                if h.role then
                    setRole(h.p, h.role, "confirmed", "visible tag")
                else
                    setTeam(h.p, h.team, "confirmed", "visible tag")
                end
            elseif not h.vis and count[h.key] <= hiddenLimit then
                if h.role then
                    setRole(h.p, h.role, "likely", "hidden tag")
                else
                    setTeam(h.p, h.team, "likely", "hidden tag")
                end
            end
        end
    end

    local function scanChannels()
        if not TextChatService then
            return
        end
        local folder = TextChatService:FindFirstChild("TextChannels")
        if not folder then
            return
        end
        local total = #Players:GetPlayers()
        for _, ch in ipairs(folder:GetChildren()) do
            if ch:IsA("TextChannel") then
                local team = channelTeam(ch.Name)
                if team then
                    local members = {}
                    for _, s in ipairs(ch:GetChildren()) do
                        if s:IsA("TextSource") then
                            local p = resolvePlayer(s.UserId)
                            if p then
                                members[#members + 1] = p
                            end
                        end
                    end
                    -- channel yang isinya hampir semua orang bukan channel tim
                    if #members > 0 and #members <= math.max(1, math.floor(total * 0.6)) then
                        for _, p in ipairs(members) do
                            setTeam(p, team, "confirmed", "team channel")
                        end
                    end
                end
            end
        end
    end

    -- workspace.Map.corpseOutlines: tiap mayat punya SurfaceGui dengan playerName + cause (versi Detective).
    local function scanCorpses()
        local map = Workspace:FindFirstChild("Map")
        local folder = (map and map:FindFirstChild("corpseOutlines")) or Workspace:FindFirstChild("corpseOutlines")
        if not folder then
            return
        end
        for _, c in ipairs(folder:GetChildren()) do
            if not St.corpseSeen[c] then
                local pn = c:FindFirstChild("playerName", true)
                local name = pn and isText(pn) and trim(stripRich(pn.Text)) or ""
                if name ~= "" then
                    St.corpseSeen[c] = true
                    local cz = c:FindFirstChild("cause", true)
                    local cause = cz and isText(cz) and trim(stripRich(cz.Text)) or ""
                    pushFeed("Body: " .. name .. (cause ~= "" and (" - " .. cause) or ""))
                    local p = resolvePlayer(name)
                    if p then
                        local rl = c:FindFirstChild("role", true) or c:FindFirstChild("Role", true)
                        local r = rl and isText(rl) and exactRole(rl.Text) or nil
                        if r then
                            setRole(p, r, "confirmed", "body")
                        else
                            local hint = causeHint(string.lower(cause))
                            if hint then
                                setRole(p, hint, "likely", "death cause")
                            end
                        end
                    end
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Role sendiri
    ------------------------------------------------------------------
    local function roleFromValue(v, depth)
        depth = depth or 0
        if depth > 2 then
            return nil
        end
        v = unwrap(v)
        local tv = typeof(v)
        if tv == "string" then
            return Game.matchRole(v)
        elseif tv == "Instance" then
            if v:IsA("ValueBase") then
                return roleFromValue(v.Value, depth + 1)
            end
            return Game.matchRole(v.Name)
        elseif tv == "table" then
            for _, k in ipairs({ "name", "Name", "role", "Role", "roleName", "id", "value", "Value" }) do
                local x = index(v, k)
                if type(x) == "string" then
                    local r = Game.matchRole(x)
                    if r then
                        return r
                    end
                end
            end
        end
        return nil
    end

    -- Game.require dengan backoff (2, 4, 8 ... 60 s) kalau modulnya nggak ada, dan nggak dipanggil ulang
    -- selama panggilan sebelumnya masih nyangkut (require bisa yield).
    local function reqModule(path)
        local r = St.req[path]
        if not r then
            r = { miss = 0, next = -1, pending = false }
            St.req[path] = r
        end
        if r.pending or now() < r.next then
            return nil
        end
        r.pending = true
        local ok, v = pcall(Game.require, path)
        r.pending = false
        if ok and type(v) == "table" then
            r.miss = 0
            return v
        end
        r.miss = r.miss + 1
        r.next = now() + math.min(60, 2 ^ r.miss)
        return nil
    end

    -- Fungsi role di controller (bisa saja lewat remote): signature yang berhasil diingat, maksimal satu
    -- panggilan per 5 s (10 s selama masih nyari signature), dan nggak dipanggil lagi kalau masih nyangkut.
    local function callRoleFuncs(rc)
        for _, fname in ipairs(K.ROLE_FUNCS) do
            local f = index(rc, fname)
            local st = St.rcFuncs[fname]
            if not st then
                st = { fails = 0 }
                St.rcFuncs[fname] = st
            end
            if type(f) == "function" and not st.pending and not st.dead then
                local anyOk = false
                st.pending = true
                for _, sig in ipairs(st.sig and { st.sig } or K.CALL_SIGS) do
                    local ok, v
                    if sig == "self" then
                        ok, v = pcall(f, rc)
                    elseif sig == "player" then
                        ok, v = pcall(f, LocalPlayer)
                    else
                        ok, v = pcall(f)
                    end
                    if ok then
                        anyOk = true
                        local role = roleFromValue(v)
                        if role then
                            st.sig, st.pending, st.fails = sig, false, 0
                            return role
                        end
                    end
                end
                st.pending = false
                if anyOk then
                    st.fails = 0
                else
                    st.fails = st.fails + 1
                    st.dead = st.fails >= 3
                end
            end
        end
        return nil
    end

    local function readController(rc)
        local role
        -- field dulu (murah, tanpa efek samping); fungsi cuma kalau field nggak ngasih role
        for _, k in ipairs(K.ROLE_FIELDS) do
            role = roleFromValue(index(rc, k))
            if role then
                break
            end
        end
        if not role then
            local t = now()
            if t - St.t.rcFunc >= (St.rcFuncRole and 5 or 10) then
                St.t.rcFunc = t
                St.rcFuncRole = callRoleFuncs(rc)
            end
            role = St.rcFuncRole
        end
        local team
        for _, k in ipairs(K.TEAM_FIELDS) do
            local v = unwrap(index(rc, k))
            if type(v) == "string" then
                team = Game.normalizeTeam(v)
                if team then
                    break
                end
            end
        end
        return role, team
    end

    -- Daftar player dari tabel teman setim (Player, nama, atau UserId).
    local function extractPlayers(t, out, depth)
        if type(t) ~= "table" or depth > 2 then
            return
        end
        local seen = 0
        for k, v in pairs(t) do
            seen = seen + 1
            if seen > 64 then
                break
            end
            local p = resolvePlayer(v)
            local role = nil
            if not p then
                local vRole = type(v) == "string" and exactRole(v) or nil
                -- key = player (nama / UserId) kalau value-nya true atau nama role; index array diabaikan
                if type(k) ~= "number" or v == true or vRole then
                    p = resolvePlayer(k)
                    role = vRole
                end
            end
            if p then
                out[#out + 1] = { p = p, role = role }
            elseif type(v) == "table" then
                local pv = index(v, "player") or index(v, "Player") or index(v, "userId") or index(v, "UserId")
                local pp = resolvePlayer(pv)
                if pp then
                    out[#out + 1] = { p = pp, role = roleFromValue(index(v, "role") or index(v, "Role")) }
                else
                    extractPlayers(v, out, depth + 1)
                end
            end
        end
    end

    -- teamMembers:get() -> { team = "...", members = { [roleKey] = { userId, ... } } } (dari SummitX)
    local function readTeamMembers(rc)
        local tm = unwrap(index(rc, "teamMembers") or index(rc, "TeamMembers"))
        if type(tm) ~= "table" then
            return nil
        end
        local team = Game.normalizeTeam(unwrap(index(tm, "team")))
        local members = index(tm, "members")
        if type(members) ~= "table" then
            return team
        end
        for roleKey, list in pairs(members) do
            local role = type(roleKey) == "string" and Game.matchRole(roleKey) or nil
            if type(list) == "table" then
                for _, id in pairs(list) do
                    local p = resolvePlayer(id)
                    if p then
                        if role then
                            setRole(p, role, "confirmed", p == LocalPlayer and "your role" or "teammate")
                        elseif team then
                            setTeam(p, team, "confirmed", "teammate")
                        end
                    end
                end
            else
                local p = resolvePlayer(roleKey)
                local r = type(list) == "string" and Game.matchRole(list) or nil
                if p and r then
                    setRole(p, r, "confirmed", "teammate")
                elseif p and team then
                    setTeam(p, team, "confirmed", "teammate")
                end
            end
        end
        return team
    end

    local function readMates(src, team)
        if type(src) ~= "table" then
            return
        end
        for _, k in ipairs(K.MATE_FIELDS) do
            local v = unwrap(index(src, k))
            if type(v) == "table" then
                local out = {}
                extractPlayers(v, out, 0)
                for _, e in ipairs(out) do
                    if e.p ~= LocalPlayer then
                        if e.role then
                            setRole(e.p, e.role, "confirmed", "teammate")
                        elseif team then
                            setTeam(e.p, team, "confirmed", "teammate")
                        end
                    end
                end
            end
        end
    end

    -- Teks yang DIAWALI "You are ..." / "Your role: ..." (seluruh teks atau per baris).
    -- "Bob: you're mafia lol" dan "If you are the Doctor, ..." nggak cocok karena polanya di-anchor.
    local function selfFromText(text)
        local low = string.lower(stripRich(text))
        local cands = { (string.gsub(low, "%s+", " ")) }
        if string.find(low, "\n", 1, true) then
            for line in string.gmatch(low, "[^\n]+") do
                cands[#cands + 1] = line
            end
        end
        local team
        for _, c in ipairs(cands) do
            local s = string.gsub(c, "^[%s%p]+", "")
            for _, pat in ipairs(K.SELF_PATTERNS) do
                local rest = string.match(s, pat)
                if rest then
                    rest = string.match(rest, "^[^%.,!;]+") or rest
                    rest = string.gsub(rest, "^now%s+", "")
                    if not string.find(rest, "^%s*not") then
                        local words = {}
                        for w in string.gmatch(rest, "%S+") do
                            words[#words + 1] = w
                            if #words >= 4 then
                                break
                            end
                        end
                        for n = #words, 1, -1 do
                            local r = exactRole(table.concat(words, " ", 1, n))
                            if r then
                                return r, nil
                            end
                        end
                        local onTeam = string.match(rest, "^on (.+)$") or string.match(rest, "^in (.+)$")
                        team = team or (onTeam and exactTeam(onTeam)) or nil
                    end
                end
            end
        end
        return nil, team
    end

    -- ScreenGui tempat label ini. nil kalau di Billboard/SurfaceGui (nempel ke player lain), di dalam
    -- chat / feed, atau di luar ScreenGui. Nggak pernah naik lewat ScreenGui / PlayerGui.
    local function selfGuiRoot(label)
        local node = label.Parent
        while node do
            if hasAny(string.lower(node.Name), K.CHAT_GUI_WORDS) then
                return nil
            end
            if node:IsA("ScreenGui") then
                return node
            end
            if isCollector(node) or node:IsA("PlayerGui") or node:IsA("Player") then
                return nil
            end
            node = node.Parent
        end
        return nil
    end

    -- Ada nama player lain yang kelihatan di GUI ini (scoreboard, kartu vote, daftar tim)?
    local function otherPlayerIn(sg)
        local names = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                for _, n in ipairs(namesOf(p)) do
                    if type(n) == "string" and #n >= 3 and not exactRole(n) then
                        names[#names + 1] = string.lower(n)
                    end
                end
            end
        end
        for _, d in ipairs(sg:GetDescendants()) do
            if isText(d) then
                local t = d.Text
                if type(t) == "string" and t ~= "" and #t < 200 and guiVisible(d) then
                    local low = string.lower(stripRich(t))
                    for _, n in ipairs(names) do
                        if findWord(low, n) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    -- Layar role sendiri di PlayerGui. "You are X" (di awal teks) menang. Label yang isinya cuma nama role
    -- diterima kalau di ScreenGui itu cuma ada satu role DAN (ada label "YOU ARE", atau ScreenGui-nya
    -- bernama role/reveal/intro/identity tanpa nama player lain di situ).
    local function scanSelfGui(pg)
        local team
        local bare, order = {}, {}
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") then
                local text = d.Text
                if type(text) == "string" and text ~= "" and #text < 200 then
                    -- saring murah dulu, baru cek visible / ancestor
                    local low = string.lower(text)
                    local maybe = string.find(low, "you", 1, true) or string.find(low, "role", 1, true)
                    local whole = (not maybe) and #text <= 80 and exactRole(text) or nil
                    -- layar role biasanya di-fade (TextTransparency 1) tapi Visible tetap true
                    local tt = (maybe or whole) and d.TextTransparency
                    local faded = type(tt) == "number" and tt >= 0.99
                    if (maybe or whole) and not faded and guiVisible(d) and not isOwnGui(d) then
                        local sg = selfGuiRoot(d)
                        if sg then
                            local b = bare[sg]
                            if not b then
                                b = { roles = {}, n = 0 }
                                bare[sg] = b
                                order[#order + 1] = sg
                            end
                            if maybe then
                                local r, t = selfFromText(text)
                                if r then
                                    return r, nil
                                end
                                team = team or t
                                if K.SELF_PREFIX[cleanWord(text)] then
                                    b.prefix = true
                                end
                            elseif not b.roles[whole] then
                                b.roles[whole] = true
                                b.n = b.n + 1
                                b.role = whole
                            end
                        end
                    end
                end
            end
        end
        for _, sg in ipairs(order) do
            local b = bare[sg]
            -- label "YOU ARE" sudah cukup kuat (layar Mafia boleh nyebut nama partner); kalau cuma dari nama
            -- ScreenGui, tolak yang ada nama player lain (scoreboard / kartu vote)
            if b.n == 1 and (b.prefix or (hasAny(string.lower(sg.Name), K.REVEAL_GUI_WORDS) and not otherPlayerIn(sg))) then
                return b.role, nil
            end
        end
        return nil, team
    end

    local clearRound -- forward

    -- Jadwal scan PlayerGui: 2 s, mundur sampai 8 s kalau nggak ada yang baru; balik ke 2 s kalau ada GUI
    -- baru masuk, ronde baru, atau fase berubah.
    local function guiKick()
        St.gui.gap, St.gui.next = 2, 0
    end

    -- Role sendiri dari layar. Dicek ulang terus selama role-nya bukan dari controller, jadi layar yang
    -- salah baca bisa dikoreksi layar berikutnya. Return role yang ditemukan (atau nil).
    local function selfGui()
        local g = St.gui
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then
            return nil
        end
        if g.pg ~= pg then
            if g.conn then
                pcall(g.conn.Disconnect, g.conn)
            end
            g.pg = pg
            g.conn = addConn(St.conns, pg.DescendantAdded, guiKick)
            guiKick()
        end
        local t = now()
        if t < g.next then
            return nil
        end
        local r, tm = scanSelfGui(pg)
        local changed = false
        if r then
            changed = setRole(LocalPlayer, r, "confirmed", "role screen")
        elseif tm then
            changed = setTeam(LocalPlayer, tm, "confirmed", "role screen")
        end
        g.gap = changed and 2 or math.min(g.gap * 2, 8)
        g.next = t + g.gap
        return r
    end

    local function detectSelf()
        local rec = getRec(LocalPlayer)
        local ctrlRole, ctrlTeam
        local rc = reqModule("client.controllers.roleController")
        if rc then
            ctrlRole, ctrlTeam = readController(rc)
            local started = unwrap(index(rc, "gameStarted"))
            if type(started) == "boolean" then
                if started and St.gameStarted == false and now() - St.lastReset > 15 then
                    clearRound("new round", true) -- game baru mulai: role lama nggak berlaku lagi
                end
                St.gameStarted = started
            end
        end
        if ctrlRole then
            if St.ctrlRole and St.ctrlRole ~= ctrlRole and now() - St.lastReset > 15 then
                St.ctrlRole = ctrlRole
                clearRound("new round", true) -- role baru dari game = ronde baru
            end
            St.ctrlRole = ctrlRole
            St.selfLocked = true
            setRole(LocalPlayer, ctrlRole, "confirmed", "your role", true)
        else
            -- role dari jaringan (kalau modul Net nyetel St.netRole) tetap mengunci
            St.selfLocked = St.netRole ~= nil
        end
        local selfTeam = ctrlTeam
        if rc then
            selfTeam = readTeamMembers(rc) or selfTeam
        end
        if selfTeam then
            setTeam(LocalPlayer, selfTeam, "confirmed", "your team")
        end
        local myRole = rec.role
        local myTeam = myRole and Game.teamOf(myRole) or nil
        if myTeam == nil or myTeam == "NEUTRAL" then
            myTeam = rec.team
        end
        if rc then
            readMates(rc, myTeam)
        end
        if myTeam == "EVIL" then
            readMates(reqModule("client.controllers.roleController.roles.mafia"), "EVIL")
        end
        if ctrlRole or St.selfLocked then
            return
        end
        if not selfGui() then
            scanTools(LocalPlayer)
        end
    end

    -- Angka gameConfig + tabel role dibaca di sini (require bisa yield), bukan di event / step.
    local function refreshConfig()
        pcall(Game.roles, false)
        for name, def in pairs(K.CFG_DEFAULTS) do
            local ok, v = pcall(Game.configNumber, name, def)
            St.cfg[name] = (ok and type(v) == "number") and v or def
        end
    end

    -- require modul game bisa yield, jadi jalanin di thread sendiri.
    local function spawnSelfScan()
        if St.selfBusy and now() - St.selfBusyAt < 10 then
            return
        end
        St.selfBusy, St.selfBusyAt = true, now()
        task.spawn(function()
            local t = now()
            if not St.cfgPending and t - St.t.cfg >= 30 then
                St.t.cfg = t
                St.cfgPending = true
                try("config", refreshConfig)
                if not St.animModuleOk then
                    try("animModule", loadAnimNames)
                end
                St.cfgPending = false
            end
            try("self", detectSelf)
            St.selfBusy = false
        end)
    end

    ------------------------------------------------------------------
    -- Vote
    ------------------------------------------------------------------
    local function decodeJSON(s)
        if type(s) ~= "string" then
            return nil
        end
        local c = string.sub(s, 1, 1)
        if c ~= "{" and c ~= "[" then
            return nil
        end
        local hs = type(ctx.service) == "function" and ctx.service("HttpService") or nil
        if not hs then
            return nil
        end
        local ok, r = pcall(hs.JSONDecode, hs, s)
        if ok then
            return r
        end
        return nil
    end

    local function countOf(t)
        if type(t) ~= "table" then
            return nil
        end
        if #t > 0 then
            return #t
        end
        local n = 0
        for _, v in pairs(t) do
            n = n + (type(v) == "number" and v or 1)
        end
        return n
    end

    -- Game.globalAttr nyari rekursif di ReplicatedStorage tiap kali attribute-nya nggak ada (miss nggak
    -- di-cache). Di sini miss di-cache dengan jeda 1, 2, 4, 8 s.
    local function globalCached(name)
        local m = St.gmiss[name]
        local t = now()
        if m and t < m.next then
            return nil
        end
        local ok, v = pcall(Game.globalAttr, name)
        if ok and v ~= nil then
            St.gmiss[name] = nil
            return v
        end
        local gap = m and math.min(m.gap * 2, 8) or 1
        St.gmiss[name] = { gap = gap, next = t + gap }
        return nil
    end

    local function resolveVoteTarget(v)
        if type(v) == "string" then
            local d = decodeJSON(v)
            if type(d) == "table" then
                return resolvePlayer(d.target or d.Target or d.userId or d.UserId or d[1])
            end
        end
        return resolvePlayer(v)
    end

    local function refreshVotes()
        local out = {}
        local function entry(p)
            local e = out[p]
            if not e then
                e = { count = 0, target = nil }
                out[p] = e
            end
            return e
        end
        local haveTally = false
        for _, p in ipairs(Players:GetPlayers()) do
            local rec = St.recs[p]
            local snap = rec and rec.snap
            if snap then
                local tv = snap.a["talliedvotes"]
                local c = tonumber(tv)
                if not c then
                    c = countOf(decodeJSON(tv))
                end
                if c then
                    entry(p).count = c
                    haveTally = true
                end
                for _, k in ipairs(K.VOTE_TARGET_KEYS) do
                    local v = snap.a[k]
                    if v ~= nil and type(v) ~= "boolean" then
                        local tp = resolveVoteTarget(v)
                        if tp then
                            entry(p).target = tp
                            break
                        end
                    end
                end
            end
        end
        local gt = globalCached("talliedVotes")
        local gtab = type(gt) == "table" and gt or decodeJSON(gt)
        if type(gtab) == "table" then
            for k, v in pairs(gtab) do
                local p = resolvePlayer(k)
                local c = tonumber(v) or countOf(v)
                if p and c then
                    entry(p).count = c
                    haveTally = true
                end
            end
        end
        local gp = globalCached("playerVotes")
        local gptab = type(gp) == "table" and gp or decodeJSON(gp)
        if type(gptab) == "table" then
            for k, v in pairs(gptab) do
                local voter = resolvePlayer(k)
                local tp = resolveVoteTarget(v)
                if voter and tp then
                    entry(voter).target = tp
                end
            end
        end
        if not haveTally then
            local targets = {}
            for _, e in pairs(out) do
                if e.target then
                    targets[#targets + 1] = e.target
                end
            end
            for _, tp in ipairs(targets) do
                local e = entry(tp)
                e.count = e.count + 1
            end
        end
        for p, e in pairs(out) do
            if e.target == LocalPlayer and St.voteTargets[p] ~= LocalPlayer and p ~= LocalPlayer then
                pushFeed(nameOf(p) .. " voted for you")
                if settings().voteAlert ~= false and type(ctx.notify) == "function" then
                    pcall(ctx.notify, "Vote", nameOf(p) .. " voted for you")
                end
            end
        end
        local targets = {}
        for p, e in pairs(out) do
            targets[p] = e.target
        end
        St.voteTargets = targets
        St.votes = out
    end

    ------------------------------------------------------------------
    -- Hook player / karakter
    ------------------------------------------------------------------
    local function onAttrEvent(p, name)
        if name == nil then
            refresh(p)
            return
        end
        local l = string.lower(tostring(name))
        if K.WATCH_ATTRS[l] or hasAny(l, K.ROLEISH) then
            refresh(p)
        end
    end

    local function hookAnimator(p, h, hum)
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator == h.animator then
            return
        end
        if h.animConn then
            pcall(h.animConn.Disconnect, h.animConn)
        end
        h.animator, h.animConn = animator, nil
        if animator then
            h.animConn = addConn(h.charConns, animator.AnimationPlayed, function(track)
                onAnimPlayed(p, track)
            end)
        end
    end

    local function ensureCharHooks(p)
        local h = St.hooks[p]
        if not h then
            return
        end
        local char = p.Character
        if char ~= h.char then
            disconnectAll(h.charConns)
            h.charConns = {}
            h.char, h.hum, h.animator, h.animConn = char, nil, nil, nil
            St.lockerTrack[p] = nil
            if char then
                addConn(h.charConns, char.AttributeChanged, function(name)
                    onAttrEvent(p, name)
                end)
                addConn(h.charConns, char.ChildAdded, function(c)
                    if c:IsA("Tool") then
                        onToolAdded(p, c, true)
                    elseif c:IsA("Humanoid") then
                        ensureCharHooks(p)
                    end
                end)
                scanTools(p)
            end
        end
        if not char then
            return
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum ~= h.hum then
            h.hum = hum
            if hum then
                addConn(h.charConns, hum.AttributeChanged, function(name)
                    onAttrEvent(p, name)
                end)
            end
        end
        if p ~= LocalPlayer then
            hookAnimator(p, h, hum)
        end
    end

    local function checkRespawnBurst()
        local t = now()
        local list = Players:GetPlayers()
        if #list < 2 then
            return
        end
        local n = 0
        for _, p in ipairs(list) do
            local ct = St.charTimes[p]
            if ct and t - ct <= 6 then
                n = n + 1
            end
        end
        if n >= math.ceil(#list * 0.6) and t - St.lastReset > 15 then
            St.charTimes = {}
            Intel.reset("new round")
        end
    end

    local function onCharacterAdded(p)
        St.charTimes[p] = now()
        local rec = getRec(p)
        rec.statusInit = false -- karakter baru: jangan anggap transisi
        St.posHist[p] = nil
        ensureCharHooks(p)
        refresh(p)
        checkRespawnBurst()
    end

    local function hookPlayer(p)
        if not p or St.hooks[p] then
            return
        end
        local h = { conns = {}, charConns = {} }
        St.hooks[p] = h
        St.removed[p] = nil
        getRec(p)
        addConn(h.conns, p.CharacterAdded, function()
            onCharacterAdded(p)
        end)
        addConn(h.conns, p.AttributeChanged, function(name)
            onAttrEvent(p, name)
        end)
        try("charHooks", ensureCharHooks, p)
        try("refresh", refresh, p)
    end

    local function unhookPlayer(p)
        local h = St.hooks[p]
        if h then
            disconnectAll(h.conns)
            disconnectAll(h.charConns)
        end
        St.hooks[p] = nil
        St.recs[p] = nil
        St.removed[p] = true
        St.votes[p] = nil
        St.voteTargets[p] = nil
        St.lastAttack[p] = nil
        St.lockerTrack[p] = nil
        St.charTimes[p] = nil
        St.notified[p] = nil
        St.attributed[p] = nil
        St.killedAt[p] = nil
        St.posHist[p] = nil
        local roles = {}
        for role, e in pairs(St.cand) do
            if e.set[p] then
                roles[#roles + 1] = role
            end
        end
        for _, role in ipairs(roles) do
            dropCandidate(role, p) -- sisa satu -> kandidat terakhir
        end
        bump()
    end

    local function onTagged(inst)
        if typeof(inst) ~= "Instance" then
            return
        end
        local target = inst
        if inst:IsA("Humanoid") then
            target = inst.Parent
        end
        local p
        if target and target:IsA("Player") then
            p = target
        elseif target then
            p = Players:GetPlayerFromCharacter(target)
        end
        if p then
            refresh(p)
        end
    end

    local function hookLegacyChat()
        local rs = ctx.ReplicatedStorage
        local ev = rs and rs:FindFirstChild("DefaultChatSystemChatEvents")
        if not ev then
            return
        end
        local sys = ev:FindFirstChild("OnNewSystemMessage")
        if sys and sys:IsA("RemoteEvent") then
            addConn(St.conns, sys.OnClientEvent, function(data)
                if type(data) == "table" then
                    onChatMessage(data.Message, true, nil, nil)
                end
            end)
        end
        local done = ev:FindFirstChild("OnMessageDoneFiltering")
        if done and done:IsA("RemoteEvent") then
            addConn(St.conns, done.OnClientEvent, function(data, channel)
                if type(data) == "table" then
                    -- pengumuman game lewat chat lama: speaker bukan player (UserId 0 / nil) atau tipe System
                    local uid = data.SpeakerUserId
                    local speaker = resolvePlayer(uid)
                    if not speaker and type(data.FromSpeaker) == "string" then
                        speaker = playerByName(data.FromSpeaker)
                    end
                    local isSystem = speaker == nil and (data.MessageType == "System" or uid == nil or uid == 0)
                    onChatMessage(data.Message, isSystem, uid, data.OriginalChannel or channel)
                end
            end)
        end
    end

    -- Riwayat posisi ~10 Hz (buat "siapa yang barusan dekat").
    local function samplePositions()
        local t = now()
        if t - St.lastSample < 0.1 then
            return
        end
        St.lastSample = t
        for _, p in ipairs(Players:GetPlayers()) do
            local pos = posOf(p)
            if pos then
                local hist = St.posHist[p]
                if not hist then
                    hist = {}
                    St.posHist[p] = hist
                end
                hist[#hist + 1] = { t, pos }
                while #hist > 0 and t - hist[1][1] > 2 do
                    table.remove(hist, 1)
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Ronde
    ------------------------------------------------------------------
    -- dropSelf: buang juga role sendiri (game benar-benar mulai baru). Selain itu role sendiri dibawa ke
    -- ronde berikut sebagai "likely": layar role sudah hilang dan nggak bisa dibaca ulang, tapi bukti baru
    -- (layar role baru, controller, tool) tetap bisa menggantinya.
    clearRound = function(reason, dropSelf)
        local me = St.recs[LocalPlayer]
        local keep
        if me and not dropSelf then
            keep = { role = me.role, roleConf = me.roleConf, reason = me.reason, team = me.team,
                teamConf = me.teamConf, teamReason = me.teamReason }
            -- dari tool (pisau / Glock / pisang): dicek ulang habis reset, jangan dibawa kalau tool-nya sudah hilang
            local r = type(me.reason) == "string" and me.reason or ""
            if string.find(r, "^carries ") or string.find(r, "^holding ") then
                keep.role = nil
            end
        end
        for _, rec in pairs(St.recs) do
            rec.role, rec.roleConf, rec.reason = nil, nil, nil
            rec.team, rec.teamConf, rec.teamReason = nil, nil, nil
            rec.suspects, rec.notRoles, rec.seenAttr = {}, {}, {}
            rec.deadFed = false
            rec.diedRound = nil
        end
        St.cand, St.lastAttack, St.attributed, St.killedAt = {}, {}, {}, {}
        St.harb, St.harbWatch = nil, nil
        St.recentDeaths, St.pendingRevive, St.doorEvents = {}, {}, {}
        St.votes, St.voteTargets = {}, {}
        St.notified, St.selfNotified = {}, false
        St.corpseSeen, St.toolSeen, St.bananaSeen = weak(), weak(), weak()
        St.selfLocked = false
        if keep and (keep.role or keep.team) then
            local function soft(c)
                return c == "confirmed" and "likely" or c
            end
            if keep.role then
                me.role, me.roleConf, me.reason = keep.role, soft(keep.roleConf), keep.reason
                St.notified[LocalPlayer] = { [keep.role] = true } -- sudah dikasih tahu, jangan notif ulang
            end
            if keep.team then
                me.team, me.teamConf, me.teamReason = keep.team, soft(keep.teamConf), keep.teamReason
            end
        end
        -- ronde baru: coba lagi modul / fungsi / layar yang tadi gagal
        for _, r in pairs(St.req) do
            r.miss, r.next = 0, -1
        end
        for _, f in pairs(St.rcFuncs) do
            f.fails, f.dead = 0, false
        end
        St.gui.gap, St.gui.next = 2, 0
        St.lastReset = now()
        bump()
        pushFeed("New round (" .. tostring(reason) .. ")")
    end

    local function checkPhase()
        local v = globalCached("gamePhase")
        local ph = v ~= nil and string.lower(tostring(v)) or nil
        if ph == St.phase then
            return
        end
        St.phase = ph
        St.gui.gap, St.gui.next = 2, 0 -- fase baru: layar role mungkin baru muncul
        if St.phaseInit and ph and hasAny(ph, K.RESET_PHASES) and not hasAny(ph, K.IN_ROUND)
            and now() - St.lastReset > 10 then
            Intel.reset("new round")
        end
        St.phaseInit = true
    end

    local function slowScan()
        spawnSelfScan()
        for _, p in ipairs(Players:GetPlayers()) do
            try("charHooks", ensureCharHooks, p)
            if p ~= LocalPlayer then
                try("tools", scanTools, p)
            end
        end
        try("tags", scanCharTags)
        try("channels", scanChannels)
        try("corpses", scanCorpses)
        local t = now()
        if t - St.t.idKind >= 30 then
            St.t.idKind = t
            for id, k in pairs(St.idKind) do
                if k == false then
                    St.idKind[id] = nil
                end
            end
        end
        for k, at in pairs(St.recentMsgs) do
            if t - at > 10 then
                St.recentMsgs[k] = nil
            end
        end
    end

    ------------------------------------------------------------------
    -- API publik
    ------------------------------------------------------------------
    -- Bukti dari jaringan game (Net module): role / tim / pesan sistem.
    function Intel.addEvidence(p, role, conf, reason, force)
        if typeof(p) ~= "Instance" or not p:IsA("Player") then
            return false
        end
        local r = Game.matchRole(role)
        if not r then
            return false
        end
        conf = conf or "confirmed"
        reason = reason or "network"
        if p == LocalPlayer and force then
            -- Role dari server berganti = ronde baru.
            if St.netRole and St.netRole ~= r and now() - St.lastReset > 15 then
                St.netRole = r
                clearRound("new round")
            end
            St.netRole = r
            St.selfLocked = true
        end
        local ok, res = pcall(setRole, p, r, conf, reason, force)
        return ok and res or false
    end

    function Intel.addTeam(p, team, conf, reason)
        if typeof(p) ~= "Instance" or not p:IsA("Player") then
            return false
        end
        local t = Game.normalizeTeam(team) or (type(team) == "string" and string.upper(team) or nil)
        if t ~= "EVIL" and t ~= "VEIL" and t ~= "TOWN" and t ~= "NEUTRAL" then
            return false
        end
        local ok, res = pcall(setTeam, p, t, conf or "confirmed", reason or "network")
        return ok and res or false
    end

    function Intel.ingestMessage(text, source)
        if type(text) ~= "string" or text == "" then
            return
        end
        pcall(onChatMessage, text, true, nil, source)
    end

    function Intel.start()
        if St.started then
            return true
        end
        St.started = true
        addConn(St.conns, Players.PlayerAdded, function(p)
            hookPlayer(p)
        end)
        addConn(St.conns, Players.PlayerRemoving, function(p)
            unhookPlayer(p)
        end)
        if TextChatService then
            addConn(St.conns, TextChatService.MessageReceived, onTCSMessage)
        end
        try("legacyChat", hookLegacyChat)
        addConn(St.conns, Workspace.DescendantAdded, onWorkspaceDescendant)
        if CollectionService then
            for _, tag in ipairs(K.TAG_NAMES) do
                local ok1, added = pcall(CollectionService.GetInstanceAddedSignal, CollectionService, tag)
                if ok1 then
                    addConn(St.conns, added, onTagged)
                end
                local ok2, removed = pcall(CollectionService.GetInstanceRemovedSignal, CollectionService, tag)
                if ok2 then
                    addConn(St.conns, removed, onTagged)
                end
            end
        end
        if ctx.RunService then
            addConn(St.conns, ctx.RunService.Heartbeat, samplePositions)
        end
        for _, p in ipairs(Players:GetPlayers()) do
            hookPlayer(p)
        end
        local okPh, ph = pcall(Game.phase)
        St.phase = okPh and ph or nil
        St.phaseInit = true
        Intel.step()
        return true
    end

    function Intel.step()
        if not St.started then
            return
        end
        if ctx.alive and not ctx.alive() then
            return
        end
        local t = now()
        for _, p in ipairs(Players:GetPlayers()) do
            if not St.hooks[p] then
                hookPlayer(p)
            end
            try("refresh", refresh, p)
        end
        try("pending", processPending)
        -- globalAttr nyari rekursif di ReplicatedStorage kalau attribute-nya nggak ada, jadi dijarangin
        if t - St.t.phase >= 0.5 then
            St.t.phase = t
            try("phase", checkPhase)
        end
        if t - St.t.votes >= 1 then
            St.t.votes = t
            try("votes", refreshVotes)
        end
        if t - St.t.slow >= 2 then
            St.t.slow = t
            try("slow", slowScan)
        end
        if t - St.t.doors >= 15 then
            St.t.doors = t
            try("doors", scanDoors)
        end
    end

    -- Tidak pernah nil buat player yang ada. Tabel yang sama dipakai ulang (jangan diubah pemanggil).
    function Intel.info(p)
        if not p then
            return nil
        end
        if St.removed[p] and not St.recs[p] then
            return EMPTY_VIEW
        end
        local rec = getRec(p)
        if rec.viewVersion ~= St.version then
            try("view", rebuildView, rec)
        end
        return rec.view
    end

    function Intel.self()
        local rec = St.recs[LocalPlayer]
        if not rec then
            return nil, nil
        end
        local team = rec.role and Game.teamOf(rec.role) or nil
        if team == nil or team == "NEUTRAL" then
            team = rec.team or team
        end
        return rec.role, team
    end

    function Intel.reset(reason)
        try("reset", clearRound, reason or "reset")
        for _, p in ipairs(Players:GetPlayers()) do
            try("refresh", refresh, p)
        end
        spawnSelfScan()
        return true
    end

    function Intel.feed()
        local out = {}
        for i, e in ipairs(St.feed) do
            out[i] = { t = e.t, text = e.text }
        end
        return out
    end

    function Intel.votes()
        return St.votes
    end

    function Intel.stop()
        St.started = false
        disconnectAll(St.conns)
        St.conns = {}
        for _, h in pairs(St.hooks) do
            disconnectAll(h.conns)
            disconnectAll(h.charConns)
        end
        St.hooks = {}
        for _, c in pairs(St.doorConns) do
            pcall(c.Disconnect, c)
        end
        St.doors, St.doorConns = weak(), weak()
        St.doorCount = 0
        St.lockerTrack = {}
        St.posHist = {}
        St.selfBusy = false
        St.gui.pg, St.gui.conn = nil, nil
        return true
    end

    -- Buat test: ganti sumber waktu.
    Intel._test = {
        setClock = function(fn)
            clockFn = fn or os.clock
        end,
        state = St,
    }

    return Intel
end
