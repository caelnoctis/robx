-- GameAPI: lapisan akses ke internal MAFIA [V2.3] - ACT II.
-- Dipanggil sebagai: local Game = (<isi file ini>)(ctx)
return function(ctx)
    local G = {}
    local Players = ctx.Players
    local ReplicatedStorage = ctx.ReplicatedStorage
    local LocalPlayer = ctx.LocalPlayer
    local CollectionService = ctx.CollectionService

    local function now()
        return os.clock()
    end

    ------------------------------------------------------------------
    -- Kapabilitas executor
    ------------------------------------------------------------------
    G.caps = {
        require = type(require) == "function",
        getthreadidentity = type(getthreadidentity) == "function",
        setthreadidentity = type(setthreadidentity) == "function",
        getconnections = type(getconnections) == "function",
        getgc = type(getgc) == "function",
        hookmetamethod = type(hookmetamethod) == "function",
        fireproximityprompt = type(fireproximityprompt) == "function",
        writefile = type(writefile) == "function",
        setclipboard = type(setclipboard) == "function" or type(toclipboard) == "function",
    }

    ------------------------------------------------------------------
    -- Resolusi path modul bertitik, contoh "client.controllers.roleController"
    ------------------------------------------------------------------
    local pathCache = {}
    local missCache = {}

    function G.roots()
        local list = { ReplicatedStorage }
        local ps = LocalPlayer:FindFirstChildOfClass("PlayerScripts")
        if ps then
            list[#list + 1] = ps
        end
        local rf = ctx.service("ReplicatedFirst")
        if rf then
            list[#list + 1] = rf
        end
        local sp = ctx.service("StarterPlayer")
        local sps = sp and sp:FindFirstChildOfClass("StarterPlayerScripts")
        if sps then
            list[#list + 1] = sps
        end
        return list
    end

    local function splitPath(path)
        local segs = {}
        for s in string.gmatch(path, "[^.]+") do
            segs[#segs + 1] = s
        end
        return segs
    end

    function G.resolve(path)
        local hit = pathCache[path]
        if hit and hit.Parent then
            return hit
        end
        local miss = missCache[path]
        if miss and now() - miss < 5 then
            return nil
        end
        local segs = splitPath(path)
        if #segs == 0 then
            return nil
        end
        local roots = G.roots()
        for _, root in ipairs(roots) do
            local node = root
            for _, s in ipairs(segs) do
                node = node and node:FindFirstChild(s)
            end
            if node then
                pathCache[path] = node
                missCache[path] = nil
                return node
            end
        end
        -- Fallback: cari segmen terakhir di mana saja, lalu cocokkan rantai parent-nya.
        local last = segs[#segs]
        for _, root in ipairs(roots) do
            for _, d in ipairs(root:GetDescendants()) do
                if d.Name == last then
                    local ok, node = true, d
                    for i = #segs - 1, 1, -1 do
                        node = node.Parent
                        if not node or node.Name ~= segs[i] then
                            ok = false
                            break
                        end
                    end
                    if ok then
                        pathCache[path] = d
                        missCache[path] = nil
                        return d
                    end
                end
            end
        end
        missCache[path] = now()
        return nil
    end

    ------------------------------------------------------------------
    -- require aman (identity 2 kalau executor mendukung, supaya dapat
    -- cache modul yang sama dengan script game)
    ------------------------------------------------------------------
    local reqCache = {}
    local reqFail = {}

    function G.require(target)
        if not G.caps.require then
            return nil, "require unsupported"
        end
        local inst = target
        if type(target) == "string" then
            inst = G.resolve(target)
        end
        if typeof(inst) ~= "Instance" or not inst:IsA("ModuleScript") then
            return nil, "module not found"
        end
        local cached = reqCache[inst]
        if cached ~= nil then
            return cached
        end
        local failedAt = reqFail[inst]
        if failedAt and now() - failedAt < 5 then
            return nil, "recently failed"
        end
        local oldIdentity
        if G.caps.getthreadidentity and G.caps.setthreadidentity then
            local okId, id = pcall(getthreadidentity)
            if okId then
                oldIdentity = id
            end
            pcall(setthreadidentity, 2)
        end
        local ok, res = pcall(require, inst)
        if oldIdentity then
            pcall(setthreadidentity, oldIdentity)
        end
        if ok and res ~= nil then
            reqCache[inst] = res
            reqFail[inst] = nil
            return res
        end
        reqFail[inst] = now()
        return nil, tostring(res)
    end

    ------------------------------------------------------------------
    -- Attribute / flag / tag
    ------------------------------------------------------------------
    local function findAttr(inst, name)
        if not inst then
            return nil
        end
        local v = inst:GetAttribute(name)
        if v ~= nil then
            return v
        end
        local lname = string.lower(name)
        for k, val in pairs(inst:GetAttributes()) do
            if string.lower(k) == lname then
                return val
            end
        end
        return nil
    end
    G.findAttr = findAttr

    local function isPlayer(x)
        return typeof(x) == "Instance" and x:IsA("Player")
    end

    -- target: Player atau Instance. Untuk Player dicek Player, Character, Humanoid, lalu ValueObject bernama sama.
    function G.attr(target, name)
        if not isPlayer(target) then
            return findAttr(target, name)
        end
        local v = findAttr(target, name)
        if v ~= nil then
            return v
        end
        local char = target.Character
        if char then
            v = findAttr(char, name)
            if v ~= nil then
                return v
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            v = hum and findAttr(hum, name)
            if v ~= nil then
                return v
            end
            local obj = char:FindFirstChild(name)
            if obj and obj:IsA("ValueBase") then
                return obj.Value
            end
        end
        local obj = target:FindFirstChild(name)
        if obj and obj:IsA("ValueBase") then
            return obj.Value
        end
        return nil
    end

    local function truthy(v)
        local t = type(v)
        if t == "boolean" then
            return v
        elseif t == "number" then
            return v > 0
        elseif t == "string" then
            local l = string.lower(v)
            return l ~= "" and l ~= "false" and l ~= "0" and l ~= "none"
        end
        return v ~= nil
    end
    G.truthy = truthy

    local function hasTag(inst, name)
        if not (inst and CollectionService) then
            return false
        end
        local ok, res = pcall(CollectionService.HasTag, CollectionService, inst, name)
        return ok and res or false
    end

    -- true kalau attribute bernilai truthy ATAU instance punya CollectionService tag bernama sama.
    function G.flag(target, name)
        if truthy(G.attr(target, name)) then
            return true
        end
        if isPlayer(target) then
            return hasTag(target, name) or hasTag(target.Character, name)
        end
        return hasTag(target, name)
    end

    ------------------------------------------------------------------
    -- State global (gamePhase, timer, dst)
    ------------------------------------------------------------------
    local globalObjCache = {}
    function G.globalAttr(name)
        local holders = { workspace, ReplicatedStorage, ctx.Lighting, Players }
        for _, h in ipairs(holders) do
            if h then
                local v = findAttr(h, name)
                if v ~= nil then
                    return v
                end
            end
        end
        local obj = globalObjCache[name]
        if not (obj and obj.Parent) then
            obj = ReplicatedStorage:FindFirstChild(name, true)
            globalObjCache[name] = obj
        end
        if obj and obj:IsA("ValueBase") then
            return obj.Value
        end
        return nil
    end

    function G.phase()
        local v = G.globalAttr("gamePhase")
        if v == nil then
            return nil
        end
        return string.lower(tostring(v))
    end

    -- true = malam, false = siang / meeting / voting, nil = tidak diketahui.
    function G.isNight()
        local p = G.phase()
        if not p then
            return nil
        end
        if string.find(p, "night", 1, true) then
            return true
        end
        if string.find(p, "day", 1, true) or string.find(p, "discuss", 1, true) or string.find(p, "vot", 1, true) or string.find(p, "meet", 1, true) then
            return false
        end
        return nil
    end

    function G.isAlive(p)
        local char = p and p.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (hum and hum.Health > 0) then
            return false
        end
        return not G.flag(p, "Dead")
    end

    ------------------------------------------------------------------
    -- Animasi game
    ------------------------------------------------------------------
    local animByName, nameById, animScanAt = {}, {}, -100

    function G.normalizeId(id)
        return id and string.match(tostring(id), "%d+") or nil
    end

    function G.scanAnimations(force)
        if not force and now() - animScanAt < 10 then
            return animByName
        end
        animScanAt = now()
        local roots = {}
        local assets = G.resolve("assets.animations")
        if assets then
            roots[#roots + 1] = assets
        end
        roots[#roots + 1] = ReplicatedStorage
        for _, root in ipairs(roots) do
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("Animation") then
                    local lname = string.lower(d.Name)
                    if animByName[lname] == nil then
                        animByName[lname] = d
                    end
                    local id = G.normalizeId(d.AnimationId)
                    if id and nameById[id] == nil then
                        nameById[id] = d.Name
                    end
                end
            end
        end
        return animByName
    end

    -- candidates: list nama (case-insensitive). Exact match dulu, lalu substring.
    function G.findAnimation(candidates)
        local map = G.scanAnimations(false)
        for _, c in ipairs(candidates) do
            local a = map[string.lower(c)]
            if a then
                return a
            end
        end
        for _, c in ipairs(candidates) do
            local lc = string.lower(c)
            for lname, a in pairs(map) do
                if string.find(lname, lc, 1, true) then
                    return a
                end
            end
        end
        return nil
    end

    function G.animationName(animationId)
        G.scanAnimations(false)
        local id = G.normalizeId(animationId)
        return id and nameById[id] or nil
    end

    ------------------------------------------------------------------
    -- Config role / tim (dibaca dari modul game kalau bisa di-require)
    ------------------------------------------------------------------
    local FALLBACK_TEAMS = {
        mafia = "EVIL",
        janitor = "EVIL",
        witch = "EVIL",
        bodyguard = "EVIL",
        saboteur = "VEIL",
        mirage = "VEIL",
        detective = "TOWN",
        doctor = "TOWN",
        vigilante = "TOWN",
    }
    local FALLBACK_ROLES = { "Mafia", "Janitor", "Witch", "Bodyguard", "Saboteur", "Mirage", "Harbinger", "Detective", "Doctor", "Vigilante" }

    local TEAM_ALIASES = {
        evil = "EVIL", mafia = "EVIL",
        veil = "VEIL", ["the veil"] = "VEIL",
        town = "TOWN", good = "TOWN", innocent = "TOWN", civilian = "TOWN", villager = "TOWN",
    }

    function G.normalizeTeam(v)
        if v == nil then
            return nil
        end
        local l = string.lower(tostring(v))
        l = string.gsub(l, "%s*team%s*$", "")
        return TEAM_ALIASES[l]
    end

    local roleInfo -- [lower] = { name = "Mafia", team = "EVIL" | nil }
    local roleInfoAt = -100

    local function addRole(map, name, team)
        if type(name) ~= "string" or name == "" or #name > 24 then
            return
        end
        local key = string.lower(name)
        local entry = map[key]
        if not entry then
            entry = { name = name }
            map[key] = entry
        end
        entry.team = entry.team or G.normalizeTeam(team) or FALLBACK_TEAMS[key]
    end

    local function teamField(t)
        for _, k in ipairs({ "team", "Team", "faction", "Faction", "alignment", "Alignment", "side", "Side" }) do
            local v = rawget(t, k)
            if type(v) == "string" then
                return v
            end
        end
        return nil
    end

    local function nameField(t)
        for _, k in ipairs({ "name", "Name", "displayName", "DisplayName", "roleName", "RoleName" }) do
            local v = rawget(t, k)
            if type(v) == "string" then
                return v
            end
        end
        return nil
    end

    local function parseRolesConfig(cfg, map)
        if type(cfg) ~= "table" then
            return
        end
        local scanned = 0
        for k, v in pairs(cfg) do
            scanned = scanned + 1
            if scanned > 200 then
                break
            end
            if type(v) == "table" then
                local nm = nameField(v) or (type(k) == "string" and k or nil)
                if nm and (teamField(v) or rawget(v, "description") or rawget(v, "Description") or type(k) == "string") then
                    addRole(map, nm, teamField(v))
                end
            elseif type(k) == "string" and type(v) == "string" and G.normalizeTeam(v) then
                addRole(map, k, v)
            end
        end
    end

    -- teamsConfig: cari key berupa nama tim yang isinya daftar role.
    local function parseTeamsConfig(cfg, map, depth)
        if type(cfg) ~= "table" or depth > 3 then
            return
        end
        for k, v in pairs(cfg) do
            local team = type(k) == "string" and G.normalizeTeam(k) or nil
            if team and type(v) == "table" then
                for k2, v2 in pairs(v) do
                    if type(v2) == "string" then
                        addRole(map, v2, team)
                    elseif type(k2) == "string" and (v2 == true or type(v2) == "table") then
                        addRole(map, k2, team)
                    end
                end
            elseif type(v) == "table" then
                parseTeamsConfig(v, map, depth + 1)
            end
        end
    end

    function G.roles(force)
        if roleInfo and not force and now() - roleInfoAt < 30 then
            return roleInfo
        end
        local map = {}
        local rolesCfg = G.require("shared.configurations.roles")
        parseRolesConfig(rolesCfg, map)
        local teamsCfg = G.require("shared.configurations.teamsConfig")
        parseTeamsConfig(teamsCfg, map, 0)
        for _, n in ipairs(FALLBACK_ROLES) do
            addRole(map, n, nil)
        end
        roleInfo, roleInfoAt = map, now()
        G.rolesFromConfig = rolesCfg ~= nil
        return map
    end

    -- Normalisasi teks bebas ("MAFIA", "the mafia", "[Doctor]") ke nama role resmi.
    function G.matchRole(text)
        if text == nil then
            return nil
        end
        local l = string.lower(tostring(text))
        local map = G.roles(false)
        local entry = map[l]
        if entry then
            return entry.name
        end
        local best
        for key, e in pairs(map) do
            local escaped = string.gsub(key, "%p", "%%%0")
            if string.find(l, "%f[%w]" .. escaped .. "%f[%W]") then
                if not best or #key > #string.lower(best) then
                    best = e.name
                end
            end
        end
        return best
    end

    function G.teamOf(roleName)
        if not roleName then
            return nil
        end
        local e = G.roles(false)[string.lower(roleName)]
        return e and e.team or FALLBACK_TEAMS[string.lower(roleName)]
    end

    function G.gameConfig()
        return G.require("shared.configurations.gameConfig")
    end

    -- Ambil angka dari gameConfig (case-insensitive, cari sampai kedalaman 2), default kalau tidak ada.
    function G.configNumber(name, default)
        local cfg = G.gameConfig()
        if type(cfg) ~= "table" then
            return default
        end
        local lname = string.lower(name)
        local function search(t, depth)
            for k, v in pairs(t) do
                if type(k) == "string" and string.lower(k) == lname and type(v) == "number" then
                    return v
                end
            end
            if depth < 2 then
                for _, v in pairs(t) do
                    if type(v) == "table" then
                        local r = search(v, depth + 1)
                        if r then
                            return r
                        end
                    end
                end
            end
            return nil
        end
        local ok, r = pcall(search, cfg, 0)
        return (ok and r) or default
    end

    return G
end
