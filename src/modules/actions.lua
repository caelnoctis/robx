-- Actions: Deception (fake crawl / stab / gunshot, ghost) + Teleport / Mafia tools.
-- Dipanggil sebagai: local Actions = (<isi file ini>)(ctx)
-- Semua fungsi publik return ok, message (message: English, pendek). Tidak pernah error ke caller.
return function(ctx)
    local Actions = {}
    local Game = ctx.Game
    local Players = ctx.Players
    local RunService = ctx.RunService
    local LocalPlayer = ctx.LocalPlayer

    local MSG = {
        noTarget = "Pick a living player in Target first.",
        noBody = "You have no living character to move.",
        noBodyAct = "You have no living character to do it with.",
        noAnimator = "Your character has no Animator yet, try again in a second.",
        seated = "Get out of your seat first.",
        noTargetBody = "That player has no body to stand next to.",
        noDowned = "Nobody is downed right now.",
        noDetained = "Nobody is detained right now.",
        reallyDowned = "You are actually wounded right now, so nobody would see a difference.",
        noCrawlAnim = "Crawl animation not found in this game version.",
        cooldown = "Too fast, wait a moment.",
        busy = "Already running, wait a second.",
        stabNotLoaded = "The stab handler has not loaded yet -- try again in a second.",
        stabNone = "No stab registered; the server may still be counting your cooldown.",
        healNotLoaded = "The heal handler has not loaded yet -- try again in a second.",
        healNone = "No heal registered; the server may still be counting your cooldown.",
        mafiaOnly = "Mafia only.",
        doctorOnly = "Doctor only.",
        bring = "Only you see them move.",
        roleUnknown = "role unknown, trying anyway",
    }

    ------------------------------------------------------------------
    -- Util
    ------------------------------------------------------------------
    local clockFn = os.clock
    local function now()
        return clockFn()
    end

    local function setting(name, default)
        local s = ctx.S
        local v = nil
        if type(s) == "table" then
            v = s[name]
        end
        if v == nil then
            return default
        end
        return v
    end

    local function live()
        if type(ctx.alive) ~= "function" then
            return true
        end
        local ok, r = pcall(ctx.alive)
        return not ok or r ~= false
    end

    local function notify(title, text)
        if type(ctx.notify) == "function" then
            pcall(ctx.notify, title, text)
        end
    end

    local warned = {}
    local function warnOnce(key, text)
        if warned[key] then
            return
        end
        warned[key] = true
        if type(ctx.warnf) == "function" then
            pcall(ctx.warnf, "[Actions] " .. tostring(text))
        end
    end

    local function disconnect(conn)
        if conn then
            pcall(function()
                conn:Disconnect()
            end)
        end
        return nil
    end

    local function connect(signal, fn)
        local ok, c = pcall(ctx.connect, signal, fn)
        if ok then
            return c
        end
        return nil
    end

    local function pack(...)
        return { n = select("#", ...), ... }
    end

    local function idx(t, k)
        local ok, v = pcall(function()
            return t[k]
        end)
        if ok then
            return v
        end
        return nil
    end

    local function fnOf(t, name)
        if type(t) ~= "table" then
            return nil
        end
        local v = idx(t, name)
        if type(v) == "function" then
            return v
        end
        return nil
    end

    local function body(p)
        local char = p and p.Character
        if not char then
            return nil, nil, nil
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
        return char, hum, root
    end

    local function alive(p)
        if not p then
            return false
        end
        local ok, r = pcall(Game.isAlive, p)
        return ok and r == true
    end

    local function flag(p, name)
        local ok, r = pcall(Game.flag, p, name)
        return ok and r == true
    end

    -- char, hum, root kalau karakter lokal hidup, selain itu nil
    local function myBody()
        local char, hum, root = body(LocalPlayer)
        if not (char and hum and root) or not alive(LocalPlayer) then
            return nil, nil, nil
        end
        return char, hum, root
    end

    local function isSeated(hum)
        local ok, r = pcall(function()
            return hum.SeatPart ~= nil or hum.Sit == true
        end)
        return ok and r == true
    end

    local function nameOf(p)
        local ok, n = pcall(function()
            return p.DisplayName
        end)
        if ok and type(n) == "string" and n ~= "" then
            return n
        end
        return tostring(p and p.Name or "?")
    end

    local function req(path)
        local ok, m = pcall(Game.require, path)
        if ok then
            return m
        end
        return nil
    end

    local function isAnimation(v)
        if typeof(v) ~= "Instance" then
            return false
        end
        local ok, r = pcall(function()
            return v:IsA("Animation")
        end)
        return ok and r == true
    end

    -- Cocokkan nama: exact dulu (urut kandidat), lalu substring.
    local function matchByName(entries, names, resolveFn)
        for pass = 1, 2 do
            for _, c in ipairs(names) do
                local lc = string.lower(c)
                for _, e in ipairs(entries) do
                    local hit
                    if pass == 1 then
                        hit = e.key == lc
                    else
                        hit = string.find(e.key, lc, 1, true) ~= nil
                    end
                    if hit then
                        local a = resolveFn(e)
                        if a then
                            return a
                        end
                    end
                end
            end
        end
        return nil
    end

    -- Fallback 1: Animation di PlayerScripts / ReplicatedFirst / Backpack / Character / StarterPack (cache 10 s).
    local extraAnims = { at = -100, list = {} }
    local function extraAnimEntries()
        if now() - extraAnims.at < 10 then
            return extraAnims.list
        end
        local roots = {}
        pcall(function()
            for _, r in ipairs(Game.roots()) do
                if r ~= ctx.ReplicatedStorage then
                    roots[#roots + 1] = r
                end
            end
        end)
        pcall(function()
            roots[#roots + 1] = LocalPlayer:FindFirstChildOfClass("Backpack")
            roots[#roots + 1] = LocalPlayer.Character
            if type(ctx.service) == "function" then
                roots[#roots + 1] = ctx.service("StarterPack")
            end
        end)
        local list = {}
        for _, r in pairs(roots) do
            pcall(function()
                for _, d in ipairs(r:GetDescendants()) do
                    if d:IsA("Animation") then
                        list[#list + 1] = { key = string.lower(d.Name), value = d }
                    end
                end
            end)
        end
        extraAnims.list, extraAnims.at = list, now()
        return list
    end

    -- Fallback 2: modul animasi (assets.animations.player1) yang isinya ID, bukan Animation instance.
    local madeAnims = {}
    local function parseAnimId(v)
        if type(v) == "number" then
            if v >= 1000 then
                return tostring(math.floor(v))
            end
            return nil
        end
        if type(v) ~= "string" then
            return nil
        end
        return string.match(v, "^%s*rbxassetid://(%d+)") or string.match(v, "[?&][iI][dD]=(%d+)") or string.match(v, "^%s*(%d%d%d%d+)%s*$")
    end

    local function makeAnim(name, raw)
        local id = parseAnimId(raw)
        if not id then
            return nil
        end
        if madeAnims[id] then
            return madeAnims[id]
        end
        local ok, inst = pcall(function()
            local a = Instance.new("Animation")
            a.Name = tostring(name)
            a.AnimationId = "rbxassetid://" .. id
            return a
        end)
        if ok and inst then
            madeAnims[id] = inst
            if type(ctx.track) == "function" then
                pcall(ctx.track, inst)
            end
            return inst
        end
        return nil
    end

    local function flattenAnims(t, out, depth, seen)
        if type(t) ~= "table" or depth > 2 or seen[t] then
            return
        end
        seen[t] = true
        pcall(function()
            for k, v in pairs(t) do
                if type(k) == "string" then
                    out[#out + 1] = { key = string.lower(k), name = k, value = v }
                end
                if type(v) == "table" then
                    flattenAnims(v, out, depth + 1, seen)
                end
            end
        end)
    end

    local function moduleAnimValue(e)
        local v = e.value
        if isAnimation(v) then
            return v
        end
        if type(v) == "table" then
            local id = rawget(v, "AnimationId") or rawget(v, "animationId") or rawget(v, "id") or rawget(v, "Id")
            return makeAnim(e.name, id)
        end
        return makeAnim(e.name, v)
    end

    local function findAnim(names)
        local ok, a = pcall(Game.findAnimation, names)
        if ok and isAnimation(a) then
            return a
        end
        local hit = matchByName(extraAnimEntries(), names, function(e)
            return e.value
        end)
        if hit then
            return hit
        end
        local entries, seen = {}, {}
        for _, path in ipairs({ "assets.animations.player1", "assets.animations" }) do
            flattenAnims(req(path), entries, 0, seen)
        end
        if #entries == 0 then
            return nil
        end
        return matchByName(entries, names, moduleAnimValue)
    end

    local function sameAnim(a, b)
        if a == nil or b == nil then
            return false
        end
        if a == b then
            return true
        end
        local ok, r = pcall(function()
            local ia, ib = Game.normalizeId(a.AnimationId), Game.normalizeId(b.AnimationId)
            return ia ~= nil and ia ~= "0" and ia == ib
        end)
        return ok and r == true
    end

    local function renderPriority(name, delta)
        local ok, v = pcall(function()
            return Enum.RenderPriority[name].Value
        end)
        if ok and type(v) == "number" then
            return v + delta
        end
        return nil
    end

    local function bindRender(name, priority, fn)
        if type(priority) ~= "number" then
            return false
        end
        local ok = pcall(function()
            RunService:BindToRenderStep(name, priority, fn)
        end)
        return ok
    end

    local function unbindRender(name)
        pcall(function()
            RunService:UnbindFromRenderStep(name)
        end)
    end

    -- Pindahkan karakter lokal. PivotTo kalau PrimaryPart = root, selain itu set root.CFrame (assembly ikut).
    local function placeAt(char, root, cf)
        local ok = false
        if char and char.PrimaryPart == root then
            ok = pcall(function()
                char:PivotTo(cf)
            end)
        end
        if not ok then
            ok = pcall(function()
                root.CFrame = cf
            end)
        end
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        return ok
    end

    -- Posisi `dist` stud di belakang target (LookVector didatarkan), menghadap target, tetap tegak.
    local function standCF(targetCF, dist)
        local pos = targetCF.Position
        local look = targetCF.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 0.01 then
            flat = Vector3.new(0, 0, -1)
        else
            flat = flat.Unit
        end
        local dest = pos - flat * dist
        return CFrame.new(dest, Vector3.new(pos.X, dest.Y, pos.Z))
    end

    ------------------------------------------------------------------
    -- State
    ------------------------------------------------------------------
    local Target = { player = nil }
    local Busy = { on = false }
    local Last = { method = nil }
    local Crawl = {
        on = false, hb = nil, hum = nil, crawl = nil, idle = nil, crawlAnim = nil, idleAnim = nil,
        mode = nil, still = 0, flagT = 0, paused = false, saved = nil, speed = 4, wrote = false, retry = 0,
    }
    local Shot = { last = {}, token = {}, tracks = {} }
    local Ghost = { on = false, hb = nil, died = nil, char = nil, pending = nil, suspended = false, bound = false }
    local Bring = { on = false, conn = nil, bound = false, player = nil, root = nil, real = nil, lastSet = nil, checkT = 0 }
    local GHOST_BIND = "NoctisENIX_GhostRestore"
    local BRING_BIND = "NoctisENIX_Bring"

    ------------------------------------------------------------------
    -- Animasi
    ------------------------------------------------------------------
    local function loadTrack(animator, anim, looped)
        local ok, track = pcall(function()
            return animator:LoadAnimation(anim)
        end)
        if not ok or not track then
            return nil
        end
        pcall(function()
            track.Priority = Enum.AnimationPriority.Action
            track.Looped = looped
        end)
        return track
    end

    local function stopTrack(track, fade)
        if track then
            pcall(function()
                track:Stop(fade)
            end)
        end
    end

    local function dropTrack(track)
        if not track then
            return
        end
        stopTrack(track, 0.2)
        task.delay(0.3, function()
            pcall(function()
                track:Destroy()
            end)
        end)
    end

    ------------------------------------------------------------------
    -- Fake crawl
    ------------------------------------------------------------------
    local function crawlSpeed()
        local v = setting("crawlSpeed", nil)
        if type(v) == "number" and v > 0 then
            return v
        end
        for _, k in ipairs({ "crawlSpeed", "CrawlSpeed", "crawlWalkSpeed", "downedWalkSpeed", "downedSpeed", "woundedWalkSpeed", "woundedSpeed" }) do
            local ok, n = pcall(Game.configNumber, k, nil)
            if ok and type(n) == "number" and n > 0 then
                return n
            end
        end
        return 4
    end

    local function crawlRelease()
        dropTrack(Crawl.crawl)
        dropTrack(Crawl.idle)
        Crawl.crawl, Crawl.idle, Crawl.mode = nil, nil, nil
    end

    -- Balikin WalkSpeed cuma kalau nilainya masih punya kita (tidak diubah game / fitur lain).
    local function crawlRestoreSpeed()
        local hum = Crawl.hum
        if Crawl.wrote and hum and Crawl.saved then
            pcall(function()
                if math.abs(hum.WalkSpeed - Crawl.speed) < 0.01 then
                    hum.WalkSpeed = Crawl.saved
                end
            end)
        end
        Crawl.wrote = false
    end

    local function crawlBind(hum)
        local animator = hum:FindFirstChildOfClass("Animator")
        if not animator then
            return false
        end
        crawlRelease()
        local track = loadTrack(animator, Crawl.crawlAnim, true)
        if not track then
            return false
        end
        Crawl.hum = hum
        Crawl.saved = hum.WalkSpeed
        Crawl.wrote = false
        Crawl.crawl = track
        if Crawl.idleAnim then
            Crawl.idle = loadTrack(animator, Crawl.idleAnim, true)
        end
        Crawl.mode = nil
        Crawl.still = 0
        return true
    end

    local function crawlSetMode(mode)
        local c, i = Crawl.crawl, Crawl.idle
        if mode == "move" then
            stopTrack(i, 0.2)
            if c then
                pcall(function()
                    if not c.IsPlaying then
                        c:Play(0.2)
                    end
                    c:AdjustSpeed(1)
                end)
            end
        elseif mode == "idle" then
            if i then
                stopTrack(c, 0.2)
                pcall(function()
                    if not i.IsPlaying then
                        i:Play(0.2)
                    end
                end)
            elseif c then
                -- tidak ada anim idle: bekukan pose crawl
                pcall(function()
                    if not c.IsPlaying then
                        c:Play(0.2)
                    end
                    c:AdjustSpeed(0)
                end)
            end
        else
            stopTrack(c, 0.2)
            stopTrack(i, 0.2)
        end
        Crawl.mode = mode
    end

    local function crawlStep(dt)
        if not Crawl.on or not live() then
            return
        end
        dt = tonumber(dt) or 0
        local _, hum = body(LocalPlayer)
        if not hum or hum.Health <= 0 then
            return
        end
        if hum ~= Crawl.hum then
            -- respawn: muat ulang track di Animator baru (kalau sudah ada), coba lagi tiap 0.5 s
            Crawl.retry = Crawl.retry - dt
            if Crawl.retry > 0 then
                return
            end
            if not crawlBind(hum) then
                Crawl.retry = 0.5
                return
            end
            Crawl.retry = 0
            Crawl.flagT = 1
        end
        -- beneran downed? biarkan game yang animasiin (cek tiap 0.25 s, bukan tiap frame)
        Crawl.flagT = Crawl.flagT + dt
        if Crawl.flagT >= 0.25 then
            Crawl.flagT = 0
            local was = Crawl.paused
            Crawl.paused = flag(LocalPlayer, "Downed")
            if Crawl.paused and not was then
                crawlSetMode(nil)
                Crawl.wrote = false
            end
        end
        if Crawl.paused then
            return
        end
        if not setting("crawlKeepSpeed", false) then
            if hum.WalkSpeed ~= Crawl.speed then
                hum.WalkSpeed = Crawl.speed
            end
            Crawl.wrote = true
        end
        local mag = 0
        pcall(function()
            mag = hum.MoveDirection.Magnitude
        end)
        -- hysteresis: mulai jalan langsung, berhenti setelah diam 0.12 s
        local want = Crawl.mode
        if mag > 0.05 then
            Crawl.still = 0
            want = "move"
        elseif mag < 0.02 then
            Crawl.still = Crawl.still + dt
            if Crawl.mode ~= "move" or Crawl.still >= 0.12 then
                want = "idle"
            end
        end
        if want == nil then
            want = "idle"
        end
        if want ~= Crawl.mode then
            crawlSetMode(want)
        end
    end

    local function crawlOff()
        Crawl.on = false
        Crawl.hb = disconnect(Crawl.hb)
        crawlRelease()
        crawlRestoreSpeed()
        Crawl.hum = nil
        Crawl.paused = false
    end

    function Actions.setFakeCrawl(on)
        if not on then
            if not Crawl.on then
                return true, "Fake crawl is already off."
            end
            crawlOff()
            return true, "Fake crawl off."
        end
        if Crawl.on then
            return true, "Fake crawl is already on."
        end
        local char, hum = myBody()
        if not char then
            return false, MSG.noBodyAct
        end
        if flag(LocalPlayer, "Downed") then
            return false, MSG.reallyDowned
        end
        local crawlAnim = findAnim({ "Wounded Crawling", "crawl", "Crawling" })
        if not crawlAnim then
            return false, MSG.noCrawlAnim
        end
        local idleAnim = findAnim({ "Wounded Idle", "wounded" })
        if sameAnim(idleAnim, crawlAnim) then
            idleAnim = nil
        end
        if not hum:FindFirstChildOfClass("Animator") then
            return false, MSG.noAnimator
        end
        Crawl.crawlAnim, Crawl.idleAnim = crawlAnim, idleAnim
        Crawl.speed = crawlSpeed()
        Crawl.hum = nil
        Crawl.paused = false
        Crawl.flagT = 0
        Crawl.retry = 0
        if not crawlBind(hum) then
            return false, "Could not load the crawl animation."
        end
        Crawl.on = true
        Crawl.hb = connect(RunService.Heartbeat, crawlStep)
        crawlStep(0)
        return true, "Everyone sees you crawling wounded."
    end

    ------------------------------------------------------------------
    -- Fake stab / fake gunshot (cuma animasi: tanpa equip tool, tanpa remote)
    ------------------------------------------------------------------
    local function oneShot(kind, names, label)
        local t = now()
        local last = Shot.last[kind]
        if last and t - last < 0.6 then
            return false, MSG.cooldown
        end
        local char, hum = myBody()
        if not char then
            return false, MSG.noBodyAct
        end
        local animator = hum:FindFirstChildOfClass("Animator")
        if not animator then
            return false, MSG.noAnimator
        end
        local anim = findAnim(names)
        if not anim then
            return false, label .. " animation not found in this game version."
        end
        local cache = Shot.tracks[kind]
        local track = nil
        if cache and cache.animator == animator and cache.anim == anim then
            track = cache.track
        end
        if not track then
            if cache then
                pcall(function()
                    cache.track:Destroy()
                end)
            end
            track = loadTrack(animator, anim, false)
            if not track then
                return false, "Could not load " .. tostring(anim.Name) .. "."
            end
            Shot.tracks[kind] = { animator = animator, anim = anim, track = track }
        end
        local okPlay = pcall(function()
            if track.IsPlaying then
                track:Stop(0)
            end
            track:Play(0.05)
        end)
        if not okPlay then
            return false, "Could not play " .. tostring(anim.Name) .. "."
        end
        Shot.last[kind] = t
        local tok = (Shot.token[kind] or 0) + 1
        Shot.token[kind] = tok
        local len = 0
        pcall(function()
            len = track.Length
        end)
        -- Length = 0 kalau asset belum ke-load
        if type(len) ~= "number" or len <= 0 then
            len = 1
        elseif len > 4 then
            len = 4
        end
        task.delay(len, function()
            if Shot.token[kind] == tok then
                stopTrack(track, 0.15)
            end
        end)
        return true, "Played " .. tostring(anim.Name)
    end

    function Actions.fakeStab()
        return oneShot("stab", { "KnifeSwing", "stab", "Knife" }, "Stab")
    end

    function Actions.fakeShot()
        return oneShot("shot", { "gunShot", "gunshot", "Shoot", "Fire" }, "Gunshot")
    end

    ------------------------------------------------------------------
    -- Ghost (CFrame desync)
    -- Heartbeat: geser root ke bawah map -> replikasi kirim posisi palsu -> render berikutnya balikin.
    -- Catatan: server bisa rubber-band atau nge-flag ini (anti-teleport). Pakai dengan risiko sendiri.
    ------------------------------------------------------------------
    local function ghostRestore()
        local p = Ghost.pending
        if not p then
            return
        end
        Ghost.pending = nil
        if p.root.Parent and p.char == LocalPlayer.Character then
            pcall(function()
                p.root.CFrame = p.cf
                p.root.AssemblyLinearVelocity = p.vel
            end)
        end
    end

    local ghostOff
    local function ghostBeat()
        -- satu frame in-flight saja (anti numpuk)
        if not Ghost.on or Ghost.pending or Ghost.suspended or not live() then
            return
        end
        local char, hum, root = body(LocalPlayer)
        if char ~= Ghost.char or not (hum and root) or hum.Health <= 0 then
            ghostOff("Ghost turned off (your character changed).")
            return
        end
        if isSeated(hum) then
            return
        end
        local depth = tonumber(setting("ghostDepth", 40)) or 40
        local okSave, cf, vel = pcall(function()
            return root.CFrame, root.AssemblyLinearVelocity
        end)
        if not okSave then
            return
        end
        Ghost.pending = { root = root, char = char, cf = cf, vel = vel }
        local okSet = pcall(function()
            root.CFrame = cf + Vector3.new(0, -depth, 0)
        end)
        if not okSet then
            Ghost.pending = nil
            return
        end
        -- Kalau BindToRenderStep jalan, restore terjadi di prioritas First (sebelum kamera).
        -- Wait ini cadangan; ghostRestore idempotent.
        pcall(function()
            RunService.RenderStepped:Wait()
        end)
        ghostRestore()
    end

    ghostOff = function(reason)
        local was = Ghost.on
        Ghost.on = false
        Ghost.hb = disconnect(Ghost.hb)
        Ghost.died = disconnect(Ghost.died)
        if Ghost.bound then
            unbindRender(GHOST_BIND)
            Ghost.bound = false
        end
        -- jangan pernah tinggalkan karakter di bawah map
        ghostRestore()
        Ghost.char = nil
        if was and reason then
            notify("Ghost", reason)
        end
    end

    function Actions.setGhost(on)
        if not on then
            if not Ghost.on then
                return true, "Ghost is already off."
            end
            ghostOff(nil)
            return true, "Ghost off. Everyone sees you where you really are."
        end
        if Ghost.on then
            return true, "Ghost is already on."
        end
        local char, hum = myBody()
        if not char then
            return false, MSG.noBodyAct
        end
        if isSeated(hum) then
            return false, MSG.seated
        end
        Ghost.on = true
        Ghost.char = char
        Ghost.pending = nil
        Ghost.suspended = false
        Ghost.hb = connect(RunService.Heartbeat, ghostBeat)
        Ghost.died = connect(hum.Died, function()
            ghostOff("Ghost turned off (you died).")
        end)
        Ghost.bound = bindRender(GHOST_BIND, renderPriority("First", 0), ghostRestore)
        return true, "Others see you under the map. You cannot stab, heal or interact while it is on."
    end

    ------------------------------------------------------------------
    -- Target
    ------------------------------------------------------------------
    local bringOff

    function Actions.livingPlayers()
        local out = {}
        pcall(function()
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and alive(p) then
                    out[#out + 1] = p
                end
            end
        end)
        pcall(table.sort, out, function(a, b)
            local na, nb = string.lower(nameOf(a)), string.lower(nameOf(b))
            if na == nb then
                return tostring(a.Name) < tostring(b.Name)
            end
            return na < nb
        end)
        return out
    end

    function Actions.getTarget()
        local p = Target.player
        if p and (p == LocalPlayer or not alive(p)) then
            Target.player = nil
            p = nil
        end
        return p
    end

    function Actions.setTarget(p)
        if p == nil then
            Target.player = nil
            if Bring.on then
                bringOff(nil)
            end
            return true, "Target cleared."
        end
        local okP, isPlr = pcall(function()
            return typeof(p) == "Instance" and p:IsA("Player")
        end)
        if not (okP and isPlr) then
            return false, "That is not a player."
        end
        if p == LocalPlayer then
            return false, "You cannot target yourself."
        end
        if not alive(p) then
            return false, MSG.noTarget
        end
        if Bring.on and Bring.player ~= p then
            bringOff(nil)
        end
        Target.player = p
        return true, "Target: " .. nameOf(p)
    end

    ------------------------------------------------------------------
    -- Bring target (client-side saja; server tetap otoritas, replikasi menimpa tiap frame)
    ------------------------------------------------------------------
    -- CFrame target yang asli (bukan hasil bring kita)
    local function realTargetCF(p)
        local _, _, r = body(p)
        if not r then
            return nil
        end
        if Bring.on and Bring.player == p and Bring.root == r and Bring.real then
            return Bring.real
        end
        local ok, cf = pcall(function()
            return r.CFrame
        end)
        if ok then
            return cf
        end
        return nil
    end

    bringOff = function(reason)
        local was = Bring.on
        Bring.on = false
        if Bring.bound then
            unbindRender(BRING_BIND)
            Bring.bound = false
        end
        Bring.conn = disconnect(Bring.conn)
        Bring.player, Bring.root, Bring.real, Bring.lastSet = nil, nil, nil, nil
        if was and reason then
            notify("Bring target", reason)
        end
    end

    local function bringStep()
        if not Bring.on then
            return
        end
        if not live() then
            bringOff(nil)
            return
        end
        local t = now()
        local p, tRoot = Bring.player, Bring.root
        -- validasi target (isAlive) dibatasi 4x per detik
        if t - Bring.checkT >= 0.25 or not (tRoot and tRoot.Parent) then
            Bring.checkT = t
            p = Actions.getTarget()
            local _, _, r = body(p)
            if p ~= Bring.player or r ~= Bring.root then
                Bring.real, Bring.lastSet = nil, nil
            end
            Bring.player, Bring.root = p, r
            tRoot = r
        end
        if not (p and tRoot and tRoot.Parent) then
            bringOff("Target lost, bring turned off.")
            return
        end
        local _, _, myRoot = body(LocalPlayer)
        if not myRoot then
            return
        end
        pcall(function()
            local cur = tRoot.CFrame
            -- beda dari yang kita set = update replikasi baru = posisi asli
            if Bring.lastSet == nil or cur ~= Bring.lastSet then
                Bring.real = cur
            end
            -- selama TSR / THR target dibiarkan di posisi asli (cek jarak di client game)
            if Busy.on then
                return
            end
            local myCF = myRoot.CFrame
            local pos = (myCF * CFrame.new(0, 0, -6)).Position
            local myPos = myCF.Position
            local cf = CFrame.new(pos, Vector3.new(myPos.X, pos.Y, myPos.Z))
            tRoot.CFrame = cf
            Bring.lastSet = cf
        end)
    end

    function Actions.setBring(on)
        if not on then
            bringOff(nil)
            return true, "Bring off."
        end
        local p = Actions.getTarget()
        if not p then
            return false, MSG.noTarget
        end
        local _, _, r = body(p)
        if not r then
            return false, MSG.noTargetBody
        end
        if not myBody() then
            return false, MSG.noBodyAct
        end
        bringOff(nil)
        Bring.on = true
        Bring.player, Bring.root, Bring.checkT = p, r, now()
        Bring.bound = bindRender(BRING_BIND, renderPriority("Camera", -1), bringStep)
        if not Bring.bound then
            Bring.conn = connect(RunService.RenderStepped, bringStep)
        end
        return true, MSG.bring
    end

    ------------------------------------------------------------------
    -- Teleport
    ------------------------------------------------------------------
    local function nearestWith(flagName)
        local _, _, myRoot = body(LocalPlayer)
        local myPos = nil
        if myRoot then
            pcall(function()
                myPos = myRoot.CFrame.Position
            end)
        end
        local best, bestD = nil, nil
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and alive(p) and flag(p, flagName) then
                local _, _, r = body(p)
                if r then
                    local d = 0
                    if myPos then
                        pcall(function()
                            d = (r.CFrame.Position - myPos).Magnitude
                        end)
                    end
                    if not best or d < bestD then
                        best, bestD = p, d
                    end
                end
            end
        end
        return best
    end

    local function teleportNear(p)
        local char, hum, root = myBody()
        if not char then
            return false, MSG.noBody
        end
        if isSeated(hum) then
            return false, MSG.seated
        end
        local tcf = realTargetCF(p)
        if not tcf then
            return false, MSG.noTargetBody
        end
        ghostRestore()
        local okCF, dest = pcall(standCF, tcf, tonumber(setting("tpDistance", 3)) or 3)
        if not okCF or not placeAt(char, root, dest) then
            return false, "Teleport failed."
        end
        return true, "Teleported to " .. nameOf(p) .. "."
    end

    function Actions.toTarget()
        local p = Actions.getTarget()
        if not p then
            return false, MSG.noTarget
        end
        return teleportNear(p)
    end

    function Actions.toDowned()
        local ok, p = pcall(nearestWith, "Downed")
        if not (ok and p) then
            return false, MSG.noDowned
        end
        return teleportNear(p)
    end

    function Actions.toDetained()
        local ok, p = pcall(nearestWith, "Detained")
        if not (ok and p) then
            return false, MSG.noDetained
        end
        return teleportNear(p)
    end

    ------------------------------------------------------------------
    -- Handler game (roleController.roles.mafia / doctor)
    ------------------------------------------------------------------
    local STAB_FNS = { "handleMafiaStab", "handleStab", "tryStab", "attemptStab" }
    local HEAL_WORDS = { "heal", "revive", "save", "pick" }
    local SKIP_PREFIX = { "set", "get", "is", "can", "has", "on", "init", "start", "setup", "update", "render", "play", "show", "hide", "destroy", "clean" }

    local function exactFn(host, names)
        for _, n in ipairs(names) do
            local f = fnOf(host, n)
            if f then
                return n, f
            end
        end
        return nil, nil
    end

    -- Fungsi aksi berdasarkan kata di namanya (juga method di metatable __index).
    local function wordFn(host, words)
        if type(host) ~= "table" then
            return nil, nil
        end
        local found = {}
        local function scan(t)
            pcall(function()
                for k, v in pairs(t) do
                    if type(k) == "string" and type(v) == "function" and found[k] == nil then
                        found[k] = v
                    end
                end
            end)
        end
        scan(host)
        local okMt, mt = pcall(getmetatable, host)
        if okMt and type(mt) == "table" and type(rawget(mt, "__index")) == "table" then
            scan(rawget(mt, "__index"))
        end
        local best, bestScore, bestFn = nil, nil, nil
        for name, fn in pairs(found) do
            local l = string.lower(name)
            local skip = false
            for _, pre in ipairs(SKIP_PREFIX) do
                if string.sub(l, 1, #pre) == pre then
                    skip = true
                    break
                end
            end
            if not skip then
                for i, w in ipairs(words) do
                    if string.find(l, w, 1, true) then
                        local score = i * 10
                        if string.sub(l, 1, 6) ~= "handle" then
                            score = score + 5
                        end
                        if not best or score < bestScore or (score == bestScore and name < best) then
                            best, bestScore, bestFn = name, score, fn
                        end
                        break
                    end
                end
            end
        end
        return best, bestFn
    end

    -- strict: dipakai untuk tabel yang bukan modul role khusus (roleController sendiri, field-nya, getgc),
    -- supaya fungsi lain seperti pickDisguise tidak ikut terpanggil.
    local STRICT_HEAL_WORDS = { "heal", "revive" }
    local HOSTS = {
        mafia = {
            path = "client.controllers.roleController.roles.mafia",
            keys = { "mafia", "Mafia" },
            test = function(t, strict)
                return (exactFn(t, STAB_FNS)) ~= nil
            end,
        },
        doctor = {
            path = "client.controllers.roleController.roles.doctor",
            keys = { "doctor", "Doctor" },
            test = function(t, strict)
                return (wordFn(t, strict and STRICT_HEAL_WORDS or HEAL_WORDS)) ~= nil
            end,
        },
    }

    -- getgc: cari tabel yang punya handleMafiaStab / setTargetCharacter (sekali per 15 s, mahal).
    local gcCache = { at = -100, list = nil }
    local function gcCandidates()
        if type(getgc) ~= "function" then
            return {}
        end
        if gcCache.list and now() - gcCache.at < 15 then
            return gcCache.list
        end
        local list = {}
        pcall(function()
            local objs = getgc(true)
            if type(objs) ~= "table" then
                return
            end
            local n = 0
            for _, v in pairs(objs) do
                n = n + 1
                if n > 400000 or #list >= 40 then
                    break
                end
                if type(v) == "table" then
                    local a = rawget(v, "handleMafiaStab")
                    local b = rawget(v, "setTargetCharacter")
                    if type(a) == "function" or type(b) == "function" then
                        list[#list + 1] = v
                    end
                end
            end
        end)
        gcCache.list, gcCache.at = list, now()
        return list
    end

    -- return host, strict
    local function findHost(kind)
        local h = HOSTS[kind]
        local m = req(h.path)
        if h.test(m, false) then
            return m, false
        end
        local rc = req("client.controllers.roleController")
        if type(rc) == "table" then
            for _, c in ipairs({ idx(rc, "roles"), idx(rc, "Roles"), rc }) do
                if type(c) == "table" then
                    for _, k in ipairs(h.keys) do
                        local r = idx(c, k)
                        if h.test(r, false) then
                            return r, false
                        end
                    end
                end
            end
            if h.test(rc, true) then
                return rc, true
            end
            -- role aktif yang disimpan controller di field yang namanya tidak kita tahu
            local okScan, hit = pcall(function()
                for _, v in pairs(rc) do
                    if type(v) == "table" and h.test(v, true) then
                        return v
                    end
                end
                return nil
            end)
            if okScan and hit then
                return hit, true
            end
        end
        for _, t in ipairs(gcCandidates()) do
            if h.test(t, true) then
                return t, true
            end
        end
        return nil, false
    end

    local function arity(fn)
        if type(debug) ~= "table" or type(debug.info) ~= "function" then
            return nil, nil
        end
        local ok, n, va = pcall(debug.info, fn, "a")
        if ok and type(n) == "number" then
            return n, va == true
        end
        return nil, nil
    end

    local function tryCalls(fn, sets)
        for _, args in ipairs(sets) do
            local ok, r = pcall(fn, table.unpack(args, 1, args.n))
            if ok and r ~= false then
                return true, args
            end
        end
        return false, nil
    end

    -- return true (method, self dulu), false (fungsi biasa), nil (gagal)
    local function callSetter(host, fn, tChar)
        local n, va = arity(fn)
        local sets
        if n == 1 and not va then
            sets = { pack(tChar) }
        else
            sets = { pack(host, tChar), pack(tChar) }
        end
        local ok, used = tryCalls(fn, sets)
        if not ok then
            return nil
        end
        return used.n >= 2 and used[1] == host
    end

    local function fakeInput()
        local t = {}
        pcall(function()
            t.UserInputType = Enum.UserInputType.MouseButton1
            t.UserInputState = Enum.UserInputState.Begin
            t.KeyCode = Enum.KeyCode.Unknown
            t.Position = Vector3.zero
            t.Delta = Vector3.zero
        end)
        return t
    end

    -- Konvensi panggil berdasarkan numparams (debug.info "a"):
    -- 0 -> () / (self); 1 -> (self) kalau method-style, selain itu (char); 2 -> (self, char) / (char, player);
    -- >= 3 -> kemungkinan handler input (actionName, UserInputState.Begin, input).
    local function callAction(host, fn, style, st)
        local n, va = arity(fn)
        local char, plr = st.tChar, st.p
        local begin = nil
        pcall(function()
            begin = Enum.UserInputState.Begin
        end)
        local input = fakeInput()
        local sets
        if n == nil or (n == 0 and va) then
            if style == true then
                sets = { pack(host) }
            elseif style == false then
                sets = { pack(), pack(char) }
            else
                sets = { pack(host), pack(char) }
            end
        elseif n == 0 then
            sets = { pack() }
        elseif n == 1 then
            if style == true then
                sets = { pack(host) }
            elseif style == false then
                sets = { pack(char) }
            else
                sets = { pack(char), pack(host) }
            end
        elseif n == 2 then
            if style == false then
                sets = { pack(char, plr), pack(host, char) }
            else
                sets = { pack(host, char), pack(char, plr) }
            end
        elseif n == 3 and style ~= true then
            sets = { pack("NoctisENIX", begin, input), pack(host, "NoctisENIX", begin, input), pack(host, char, plr), pack(char, plr) }
        else
            sets = { pack(host, "NoctisENIX", begin, input), pack(host, char, plr), pack("NoctisENIX", begin, input) }
        end
        local ok = tryCalls(fn, sets)
        return ok
    end

    ------------------------------------------------------------------
    -- ProximityPrompt
    ------------------------------------------------------------------
    local promptCache = { at = -100, list = {} }
    local function allPrompts()
        if now() - promptCache.at < 5 then
            return promptCache.list
        end
        local list = {}
        pcall(function()
            for _, d in ipairs(ctx.Workspace:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    list[#list + 1] = d
                end
            end
        end)
        promptCache.list, promptCache.at = list, now()
        return list
    end

    local function promptPos(pr)
        local ok, pos = pcall(function()
            local parent = pr.Parent
            if not parent then
                return nil
            end
            if parent:IsA("Attachment") then
                return parent.WorldPosition
            elseif parent:IsA("BasePart") then
                return parent.CFrame.Position
            elseif parent:IsA("Model") then
                return parent:GetPivot().Position
            end
            return nil
        end)
        if ok then
            return pos
        end
        return nil
    end

    -- Urutan: prompt di badan target dulu, lalu kata yang lebih spesifik (urutan `words`), lalu yang terdekat.
    local function matchingPrompts(tChar, center, words, radius)
        local hits, seen = {}, {}
        local function consider(pr, base, dist)
            if seen[pr] then
                return
            end
            seen[pr] = true
            local okT, text = pcall(function()
                if pr.Enabled == false then
                    return nil
                end
                return string.lower(tostring(pr.ActionText or "") .. " " .. tostring(pr.ObjectText or "") .. " " .. tostring(pr.Name or ""))
            end)
            if not (okT and text) then
                return
            end
            for i, w in ipairs(words) do
                if string.find(text, w, 1, true) then
                    hits[#hits + 1] = { pr = pr, score = base + i * 20 + dist }
                    return
                end
            end
        end
        pcall(function()
            for _, d in ipairs(tChar:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    consider(d, 0, 0)
                end
            end
        end)
        if center then
            for _, pr in ipairs(allPrompts()) do
                local pos = promptPos(pr)
                if pos then
                    local okD, d = pcall(function()
                        return (pos - center).Magnitude
                    end)
                    if okD and d <= radius then
                        consider(pr, 1000, d)
                    end
                end
            end
        end
        pcall(table.sort, hits, function(a, b)
            return a.score < b.score
        end)
        local out = {}
        for i, h in ipairs(hits) do
            out[i] = h.pr
        end
        return out
    end

    local function firePrompt(pr)
        if type(fireproximityprompt) == "function" then
            if pcall(fireproximityprompt, pr) then
                return "fireproximityprompt"
            end
        end
        local began = pcall(function()
            pr:InputHoldBegin()
        end)
        if began then
            local hold = 0
            pcall(function()
                hold = tonumber(pr.HoldDuration) or 0
            end)
            if hold > 0 then
                task.wait(hold + 0.05)
            end
            pcall(function()
                pr:InputHoldEnd()
            end)
            return "InputHold"
        end
        return nil
    end

    ------------------------------------------------------------------
    -- Strategi (return "ok", method | "skip", reason | "fail", reason)
    ------------------------------------------------------------------
    local function findTool(words)
        local places = { LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }
        for _, place in ipairs(places) do
            if place then
                for _, c in ipairs(place:GetChildren()) do
                    if c:IsA("Tool") then
                        local n = string.lower(tostring(c.Name))
                        for _, w in ipairs(words) do
                            if string.find(n, w, 1, true) then
                                return c
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function handlerStrategy(kind, actionPicker, notLoaded)
        return function(st)
            local host, strict = findHost(kind)
            if not host then
                return "skip", notLoaded
            end
            local style = nil
            local setFn = fnOf(host, "setTargetCharacter")
            if setFn then
                style = callSetter(host, setFn, st.tChar)
            end
            local name, fn = actionPicker(host, strict)
            if not fn then
                return "skip", notLoaded
            end
            if callAction(host, fn, style, st) then
                return "ok", "handler:" .. name
            end
            return "fail", "handler " .. name .. " errored"
        end
    end

    local function promptStrategy(words)
        return function(st)
            local list = matchingPrompts(st.tChar, st.center, words, 12)
            if #list == 0 then
                return "skip", nil
            end
            for _, pr in ipairs(list) do
                local how = firePrompt(pr)
                if how then
                    return "ok", "prompt:" .. how
                end
            end
            return "fail", "prompt could not be fired"
        end
    end

    local function toolStrategy(words)
        return function(st)
            local tool = findTool(words)
            if not tool then
                return "skip", nil
            end
            if tool.Parent ~= st.char then
                local okE = pcall(function()
                    st.hum:EquipTool(tool)
                end)
                if not okE then
                    return "fail", "could not equip " .. tostring(tool.Name)
                end
                st.equipped = tool
                task.wait()
            end
            local okA = pcall(function()
                tool:Activate()
            end)
            if okA then
                return "ok", "tool:" .. tostring(tool.Name)
            end
            return "fail", "could not use " .. tostring(tool.Name)
        end
    end

    -- Remote asli game (ReplicatedStorage.RoleNetworks.mafia.onStab / doctor.onHeal) lewat Net module.
    local function netStrategy(kind)
        return function(st)
            local net = ctx.Net
            local fn = net and (kind == "stab" and net.stab or net.heal)
            if type(fn) ~= "function" then
                return "skip", nil
            end
            local ok, method = fn(st.p)
            if ok then
                return "ok", method
            end
            if type(method) == "string" and string.find(method, "not found", 1, true) then
                return "skip", nil
            end
            return "fail", "remote: " .. tostring(method)
        end
    end

    local STAB_STRATEGIES = {
        netStrategy("stab"),
        handlerStrategy("mafia", function(host)
            return exactFn(host, STAB_FNS)
        end, MSG.stabNotLoaded),
        promptStrategy({ "stab", "kill", "attack", "knife" }),
        toolStrategy({ "knife" }),
    }
    local HEAL_STRATEGIES = {
        netStrategy("heal"),
        handlerStrategy("doctor", function(host, strict)
            return wordFn(host, strict and STRICT_HEAL_WORDS or HEAL_WORDS)
        end, MSG.healNotLoaded),
        promptStrategy({ "heal", "revive", "save", "help", "pick" }),
        toolStrategy({ "medkit", "med kit", "heal", "bandage", "syringe" }),
    }

    ------------------------------------------------------------------
    -- Role gate: true kalau boleh, plus catatan kalau role belum diketahui
    ------------------------------------------------------------------
    local function roleGate(want, wantTeam)
        if setting("ignoreRoleCheck", false) then
            return true, nil
        end
        local role, team = nil, nil
        if type(ctx.selfRole) == "function" then
            local ok, r, t = pcall(ctx.selfRole)
            if ok then
                role, team = r, t
            end
        end
        if type(role) == "string" and role ~= "" then
            local official = role
            pcall(function()
                official = Game.matchRole(role) or role
            end)
            return string.lower(official) == want, nil
        end
        local nt = nil
        if team ~= nil then
            pcall(function()
                nt = Game.normalizeTeam(team)
            end)
        end
        if nt and nt ~= wantTeam then
            return false, nil
        end
        return true, MSG.roleUnknown
    end

    local function withNote(text, note)
        if note then
            return text .. " (" .. note .. ")"
        end
        return text
    end

    ------------------------------------------------------------------
    -- Teleport -> aksi -> balik (dipakai Stab dan Heal). BOLEH yield.
    ------------------------------------------------------------------
    local function startPin(p, dist)
        return connect(RunService.Heartbeat, function()
            if not Busy.on then
                return
            end
            local char, _, root = body(LocalPlayer)
            local tcf = realTargetCF(p)
            if not (root and tcf) then
                return
            end
            local okD, dest = pcall(standCF, tcf, dist)
            if not okD then
                return
            end
            local okF, far = pcall(function()
                return (root.CFrame.Position - dest.Position).Magnitude > 1.5
            end)
            if okF and far then
                placeAt(char, root, dest)
            end
        end)
    end

    local function pollUntil(fn, timeout)
        local t0 = now()
        local tries = 0
        while true do
            local ok, r = pcall(fn)
            if ok and r then
                return true
            end
            tries = tries + 1
            if tries >= 60 or now() - t0 >= timeout then
                return false
            end
            task.wait(0.05)
        end
    end

    local function tripInner(op, st)
        local dist = tonumber(setting("tsrDistance", 3)) or 3
        local origin = st.root.CFrame
        st.origin = origin
        local okCF, dest = pcall(standCF, st.tcf, dist)
        if not okCF or not placeAt(st.char, st.root, dest) then
            return false, "Teleport failed."
        end
        st.moved = true
        st.pin = startPin(st.p, dist)
        -- 2 frame supaya server lihat posisi baru
        task.wait()
        task.wait()
        local res = { ran = false, method = nil, reason = nil }
        for _, strat in ipairs(op.strategies) do
            local okS, status, info = pcall(strat, st)
            if not okS then
                warnOnce(op.kind .. tostring(status), status)
            elseif status == "ok" then
                res.ran, res.method = true, info
                break
            elseif status == "skip" and info and not res.reason then
                res.reason = info
            end
        end
        task.wait(tonumber(setting("tsrHold", 0.35)) or 0.35)
        st.pin = disconnect(st.pin)
        -- selalu balik
        placeAt(st.char, st.root, origin)
        st.moved = false
        if st.equipped then
            pcall(function()
                st.hum:UnequipTools()
            end)
            st.equipped = nil
        end
        Last.method = res.method
        if not res.ran then
            return false, withNote(res.reason or op.notLoaded, op.note)
        end
        if pollUntil(op.check, op.verifyTime) then
            return true, withNote(op.success .. nameOf(st.p), op.note)
        end
        return false, withNote(op.none, op.note)
    end

    local function trip(op)
        local char, hum, root = myBody()
        if not char then
            return false, MSG.noBodyAct
        end
        if isSeated(hum) then
            return false, MSG.seated
        end
        local p = op.player
        ghostRestore()
        local tcf = realTargetCF(p)
        local tChar = p.Character
        if not (tcf and tChar) then
            return false, MSG.noTargetBody
        end
        local center = nil
        pcall(function()
            center = tcf.Position
        end)
        local st = { p = p, tChar = tChar, tcf = tcf, center = center, char = char, hum = hum, root = root }
        Busy.on = true
        Ghost.suspended = true
        local okRun, ok, msg = pcall(tripInner, op, st)
        -- finally: lepas pin, balik ke posisi awal kalau belum, lepas tool
        st.pin = disconnect(st.pin)
        if st.moved and st.origin and st.root.Parent then
            placeAt(st.char, st.root, st.origin)
        end
        if st.equipped then
            pcall(function()
                st.hum:UnequipTools()
            end)
        end
        Ghost.suspended = false
        Busy.on = false
        if not okRun then
            warnOnce("trip" .. tostring(ok), ok)
            return false, "Something went wrong, you were moved back."
        end
        return ok, msg
    end

    local function hurtState(p)
        return {
            downed = flag(p, "Downed"),
            dead = flag(p, "Dead") or not alive(p),
            wound = flag(p, "knifeWound"),
        }
    end

    function Actions.tpStabReturn()
        if Busy.on then
            return false, MSG.busy
        end
        local p = Actions.getTarget()
        if not p then
            return false, MSG.noTarget
        end
        local allowed, note = roleGate("mafia", "EVIL")
        if not allowed then
            return false, MSG.mafiaOnly
        end
        local before = hurtState(p)
        return trip({
            kind = "stab",
            player = p,
            note = note,
            strategies = STAB_STRATEGIES,
            notLoaded = MSG.stabNotLoaded,
            none = MSG.stabNone,
            success = "Stab landed on ",
            verifyTime = 1,
            check = function()
                local n = hurtState(p)
                return (n.downed and not before.downed) or (n.dead and not before.dead) or (n.wound and not before.wound)
            end,
        })
    end

    function Actions.tpHealReturn()
        if Busy.on then
            return false, MSG.busy
        end
        local allowed, note = roleGate("doctor", "TOWN")
        if not allowed then
            return false, MSG.doctorOnly
        end
        local okN, p = pcall(nearestWith, "Downed")
        if not (okN and p) then
            return false, MSG.noDowned
        end
        return trip({
            kind = "heal",
            player = p,
            note = note,
            strategies = HEAL_STRATEGIES,
            notLoaded = MSG.healNotLoaded,
            none = MSG.healNone,
            success = "Saved ",
            verifyTime = 1.5,
            check = function()
                return not flag(p, "Downed") and alive(p)
            end,
        })
    end

    ------------------------------------------------------------------
    -- Status / cleanup
    ------------------------------------------------------------------
    function Actions.status()
        return {
            fakeCrawl = Crawl.on,
            ghost = Ghost.on,
            bring = Bring.on,
            target = Actions.getTarget(),
            lastMethod = Last.method,
            busy = Busy.on,
        }
    end

    function Actions.stop()
        pcall(crawlOff)
        pcall(ghostOff, nil)
        pcall(bringOff, nil)
        for _, c in pairs(Shot.tracks) do
            stopTrack(c.track, 0.1)
            pcall(function()
                c.track:Destroy()
            end)
        end
        Shot.tracks = {}
        Shot.token = {}
        unbindRender(GHOST_BIND)
        unbindRender(BRING_BIND)
        return true, "Actions stopped."
    end

    -- Respawn: ghost mati, crawl dipasang ulang di Heartbeat berikutnya.
    pcall(function()
        connect(LocalPlayer.CharacterAdded, function()
            if Ghost.on then
                ghostOff("Ghost turned off (you respawned).")
            end
            if Crawl.on then
                crawlRelease()
                Crawl.hum = nil
            end
        end)
    end)
    pcall(function()
        connect(Players.PlayerRemoving, function(p)
            if p == Target.player then
                Target.player = nil
                if Bring.on then
                    bringOff("Target left, bring turned off.")
                end
            end
        end)
    end)

    -- Hook khusus test
    Actions._test = {
        setClock = function(fn)
            clockFn = fn or os.clock
        end,
        state = function()
            return { Crawl = Crawl, Ghost = Ghost, Bring = Bring, Busy = Busy, Shot = Shot }
        end,
    }

    return Actions
end
