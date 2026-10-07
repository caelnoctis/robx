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

    function G.requireAllowed(inst)
        local shared = ReplicatedStorage:FindFirstChild("shared")
        local cfg = shared and shared:FindFirstChild("configurations")
        if not cfg then
            return false
        end
        local ok, inside = pcall(function()
            return inst:IsDescendantOf(cfg)
        end)
        return ok and inside or false
    end

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
        -- Di Xeno, require modul client (controller) MENJALANKAN ULANG kodenya dan error di tengah
        -- jalan; efek sampingnya bisa merusak kontrol game (tombol stab / tembak hilang). Jadi cuma
        -- config data murni yang boleh di-require.
        if not G.requireAllowed(inst) then
            return nil, "blocked: only shared.configurations modules are required"
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

    -- Sumber fase tambahan (mis. Net module: remote gameService.gamePhase / setTopbarText).
    G.phaseProviders = {}
    function G.addPhaseProvider(fn)
        G.phaseProviders[#G.phaseProviders + 1] = fn
    end

    function G.phase()
        local v = G.globalAttr("gamePhase")
        if v == nil then
            for _, fn in ipairs(G.phaseProviders) do
                local ok, r = pcall(fn)
                if ok and r ~= nil then
                    v = r
                    break
                end
            end
        end
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
        local p1 = G.resolve("assets.animations.player1")
        if p1 then
            for _, c in ipairs(candidates) do
                local lc = string.lower(c)
                for _, a in ipairs(p1:GetChildren()) do
                    if a:IsA("Animation") and string.lower(a.Name) == lc then
                        return a
                    end
                end
            end
        end
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
    -- Tim cadangan kalau teamsConfig nggak bisa di-require (di lobby modul itu memang nggak ada).
    -- Dicocokkan ke capture Inspector: teamsConfig in-game (mafia 2 role, veil 4, town 8, neutral 3),
    -- statsConfig.Roles, dan roleHandbookConfig ("The Bodyguard is a neutral protective role").
    -- Bodyguard ikut sisi orang yang dia jaga, jadi timnya NEUTRAL sampai ada bukti sisi (lihat Intel).
    local FALLBACK_TEAMS = {
        mafia = "EVIL",
        witch = "EVIL",
        saboteur = "VEIL",
        mirage = "VEIL",
        poisoner = "VEIL",
        harbinger = "VEIL",
        detective = "TOWN",
        doctor = "TOWN",
        vigilante = "TOWN",
        janitor = "TOWN",
        detainer = "TOWN",
        judge = "TOWN",
        suppressor = "TOWN",
        civilian = "TOWN",
        bodyguard = "NEUTRAL",
        jester = "NEUTRAL",
    }
    local FALLBACK_ROLES = {
        "Mafia", "Witch", "Bodyguard", "Saboteur", "Mirage", "Poisoner", "Phantom", "Harbinger",
        "Detective", "Doctor", "Vigilante", "Janitor", "Detainer", "Judge", "Suppressor", "Jester", "Snow Spirit",
        "Civilian",
    }
    -- Nama folder RoleNetworks -> nama role.
    local ROLE_ALIASES = { snowspirit = "snow spirit" }

    local TEAM_ALIASES = {
        evil = "EVIL", mafia = "EVIL",
        veil = "VEIL", ["the veil"] = "VEIL",
        town = "TOWN", good = "TOWN", innocent = "TOWN", civilian = "TOWN", villager = "TOWN",
        neutral = "NEUTRAL",
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
        key = ROLE_ALIASES[key] or key
        local entry = map[key]
        if not entry then
            entry = { name = name }
            map[key] = entry
        end
        entry.team = entry.team or G.normalizeTeam(team) or FALLBACK_TEAMS[key] or FALLBACK_TEAMS[(string.gsub(key, " ", ""))]
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

    -- teamsConfig game: punya getTeamOfRole(role) dan teams.<tim>.roles. Cuma MENETAPKAN tim untuk
    -- role yang sudah dikenal; nggak pernah menambah "role" baru (dulu field seperti "roles" atau
    -- "The Veil" ikut terbaca sebagai nama role).
    local function teamNameOf(v)
        if type(v) == "table" then
            v = rawget(v, "name") or rawget(v, "Name") or rawget(v, "team")
        end
        return G.normalizeTeam(v)
    end

    local function parseTeamsConfig(cfg, map)
        if type(cfg) ~= "table" then
            return
        end
        local fn = rawget(cfg, "getTeamOfRole")
        if type(fn) == "function" then
            for key, entry in pairs(map) do
                if not string.find(key, " ", 1, true) then
                    local ok, res = pcall(fn, key)
                    local t = ok and teamNameOf(res) or nil
                    if t then
                        entry.team = t
                    end
                end
            end
        end
        local teams = rawget(cfg, "teams")
        if type(teams) == "table" then
            for teamKey, info in pairs(teams) do
                local t = G.normalizeTeam(teamKey) or (type(info) == "table" and teamNameOf(info)) or nil
                local roles = type(info) == "table" and rawget(info, "roles") or nil
                if t and type(roles) == "table" then
                    for k, v in pairs(roles) do
                        local name = type(v) == "string" and v or (type(k) == "string" and k or nil)
                        local entry = name and map[string.lower(name)]
                        if entry and not entry.team then
                            entry.team = t
                        end
                    end
                end
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
        parseTeamsConfig(teamsCfg, map)
        for _, n in ipairs(FALLBACK_ROLES) do
            addRole(map, n, nil)
        end
        for alias, key in pairs(ROLE_ALIASES) do
            if map[key] and not map[alias] then
                map[alias] = map[key]
            end
        end
        -- Role musiman yang lagi dimatikan game (seasonalRolesConfig) nggak ikut dicocokkan.
        for key in pairs(map) do
            if not G.roleEnabled(key) then
                map[key] = nil
            end
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
        local key = string.lower(roleName)
        local e = G.roles(false)[ROLE_ALIASES[key] or key]
        return e and e.team or FALLBACK_TEAMS[key] or FALLBACK_TEAMS[(string.gsub(key, " ", ""))]
    end

    local function compactKey(name)
        return (string.gsub(string.lower(tostring(name)), "[%s_%-]", ""))
    end

    -- seasonalRolesConfig.enabled = { phantom = false, snowspirit = false } -> role itu nggak ada di ronde.
    function G.roleEnabled(roleName)
        if roleName == nil then
            return false
        end
        local cfg = G.require("shared.configurations.seasonalRolesConfig")
        local enabled = type(cfg) == "table" and rawget(cfg, "enabled") or nil
        if type(enabled) ~= "table" then
            return true
        end
        return rawget(enabled, compactKey(roleName)) ~= false
    end

    -- Warna role persis dari roleColorsConfig; cadangannya salinan nilai yang terbaca di capture.
    local ROLE_COLORS_FALLBACK = {
        bodyguard = { 144, 160, 173 }, civilian = { 36, 156, 48 }, detainer = { 100, 215, 190 },
        detective = { 211, 109, 0 }, doctor = { 29, 162, 205 }, harbinger = { 217, 54, 121 },
        janitor = { 207, 227, 21 }, jester = { 151, 32, 37 }, judge = { 58, 105, 52 },
        mafia = { 151, 32, 37 }, mirage = { 230, 168, 60 }, phantom = { 212, 212, 205 },
        poisoner = { 232, 211, 12 }, saboteur = { 214, 72, 237 }, snowspirit = { 7, 218, 255 },
        suppressor = { 212, 184, 30 }, vigilante = { 104, 120, 208 }, witch = { 100, 215, 190 },
    }
    local roleColors, roleColorsAt = nil, -100

    function G.roleColor(roleName)
        if roleName == nil then
            return nil
        end
        if not roleColors or now() - roleColorsAt > 30 then
            local map = {}
            for k, rgb in pairs(ROLE_COLORS_FALLBACK) do
                map[k] = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
            end
            local cfg = G.require("shared.configurations.roleColorsConfig")
            if type(cfg) == "table" then
                for k, v in pairs(cfg) do
                    if type(k) == "string" and typeof(v) == "Color3" then
                        map[compactKey(k)] = v
                    end
                end
            end
            roleColors, roleColorsAt = map, now()
        end
        return roleColors[compactKey(roleName)]
    end

    ------------------------------------------------------------------
    -- Hotkey game (hotkeysConfig + attribute "Hotkeys" milik pemain)
    ------------------------------------------------------------------
    -- Attribute "Hotkeys" isinya JSON override, contoh {"ability2":"F","flashlight":"G"}; "[]" = default.
    local HOTKEY_DEFAULTS = {
        { id = "interact", label = "Interact", key = "E", group = "GENERAL" },
        { id = "flashlight", label = "Flashlight", key = "F", group = "GENERAL" },
        { id = "ability1", label = "Main ability", key = "T", group = "ROLE" },
        { id = "ability2", label = "Second ability", key = "G", group = "ROLE" },
        { id = "ability3", label = "Third ability", key = "R", group = "ROLE" },
        { id = "perk", label = "Use perk", key = "Q", group = "ROLE" },
        { id = "playerList", label = "Player list", key = "Tab", group = "INTERFACE" },
        { id = "tips", label = "Role tips", key = "H", group = "INTERFACE" },
        { id = "freeCursor", label = "Free cursor", key = "P", group = "INTERFACE" },
        { id = "openSettings", label = "Settings", key = "P", group = "INTERFACE" },
    }

    local hotkeyCache, hotkeyAt = nil, -100

    function G.gameHotkeys(force)
        if hotkeyCache and not force and now() - hotkeyAt < 3 then
            return hotkeyCache
        end
        local list = {}
        local cfg = G.require("shared.configurations.hotkeysConfig")
        local actions = type(cfg) == "table" and rawget(cfg, "actions") or nil
        if type(actions) == "table" then
            for _, a in ipairs(actions) do
                if type(a) == "table" and not rawget(a, "devOnly") then
                    local id, key = rawget(a, "id"), rawget(a, "default")
                    if type(id) == "string" and type(key) == "string" then
                        local label = rawget(a, "label")
                        list[#list + 1] = {
                            id = id,
                            label = type(label) == "string" and label or id,
                            key = key,
                            group = rawget(a, "group"),
                        }
                    end
                end
            end
        end
        if #list == 0 then
            for i, a in ipairs(HOTKEY_DEFAULTS) do
                list[i] = { id = a.id, label = a.label, key = a.key, group = a.group }
            end
        end
        local attrName = type(cfg) == "table" and rawget(cfg, "ATTRIBUTE") or nil
        local unbound = type(cfg) == "table" and rawget(cfg, "UNBOUND") or nil
        attrName = type(attrName) == "string" and attrName or "Hotkeys"
        unbound = type(unbound) == "string" and unbound or "None"
        local raw = G.attr(LocalPlayer, attrName)
        local http = ctx.service and ctx.service("HttpService")
        if type(raw) == "string" and raw ~= "" and http then
            local ok, overrides = pcall(function()
                return http:JSONDecode(raw)
            end)
            if ok and type(overrides) == "table" then
                for _, a in ipairs(list) do
                    local v = rawget(overrides, a.id)
                    if v == unbound then
                        a.key, a.custom = nil, true
                    elseif type(v) == "string" and v ~= "" then
                        a.key, a.custom = v, true
                    end
                end
            end
        end
        hotkeyCache, hotkeyAt = list, now()
        return list
    end

    -- Aksi game yang memakai tombol ini (nama KeyCode, mis. "G"), atau nil.
    function G.hotkeyAction(keyName)
        if type(keyName) ~= "string" then
            return nil
        end
        local hits = {}
        for _, a in ipairs(G.gameHotkeys()) do
            if a.key == keyName then
                hits[#hits + 1] = a.label
            end
        end
        return #hits > 0 and table.concat(hits, " / ") or nil
    end

    -- Buang cache config (role, warna, hotkey) supaya dibaca ulang dari modul game.
    function G.flushConfig()
        roleInfo, roleColors, hotkeyCache = nil, nil, nil
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
