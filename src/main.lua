--[[
    NoctisENIX v2
    Game     : MAFIA [V2.3] - ACT II  (Topline Studios Inc)
    Executor : Xeno (juga jalan di executor lain yang punya fungsi dasar)

    File NoctisENIX.lua adalah HASIL BUILD dari src/ (python3 tools/build.py).
    Edit file di src/, jangan edit NoctisENIX.lua langsung.

    Catatan teknis
      * Satu file, tanpa library eksternal, tanpa Drawing API, tanpa request keluar.
      * Semua fungsi khusus executor dicek dulu dan dibungkus pcall. Kalau Xeno
        nggak punya salah satunya, fitur yang butuh itu saja yang mati.
      * Role pemain lain nggak dikirim ke client oleh game, jadi Intel engine
        menyimpulkannya dari bukti (animasi tusuk/tembak, silence, pintu, heal,
        pengumuman, tag tim). Lihat tab Roles.
      * Menjalankan ulang script akan meng-unload instance lama otomatis.

    Cara pakai
      loadstring(game:HttpGet("<RAW_URL>/NoctisENIX.lua"))()
      RightShift = buka / tutup menu (bisa diganti di tab Settings)
]]

local genv = (getgenv and getgenv()) or _G

if genv.NoctisENIX and type(genv.NoctisENIX.Unload) == "function" then
    pcall(genv.NoctisENIX.Unload)
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Config = {
    Name = "NoctisENIX",
    Version = "2.6.0",
    ToggleKey = Enum.KeyCode.RightShift,
}

----------------------------------------------------------------------
-- Util dasar
----------------------------------------------------------------------
local cloneref = cloneref or function(obj)
    return obj
end

local function service(name)
    local ok, svc = pcall(game.GetService, game, name)
    if ok and svc then
        return cloneref(svc)
    end
    return nil
end

local Players = service("Players")
local RunService = service("RunService")
local UserInputService = service("UserInputService")
local TweenService = service("TweenService")
local Lighting = service("Lighting")
local CoreGui = service("CoreGui")
local HttpService = service("HttpService")
local TeleportService = service("TeleportService")
local VirtualUser = service("VirtualUser")
local MarketplaceService = service("MarketplaceService")
local ProximityPromptService = service("ProximityPromptService")
local ReplicatedStorage = service("ReplicatedStorage")
local CollectionService = service("CollectionService")
local TextChatService = service("TextChatService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

local function warnf(...)
    warn("[" .. Config.Name .. "]", ...)
end

-- Penampung koneksi / instance / fungsi cleanup supaya Unload bisa bersih total.
local Janitor = {}
local function track(item)
    Janitor[#Janitor + 1] = item
    return item
end

local function connect(signal, fn)
    return track(signal:Connect(fn))
end

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warnf(tostring(err))
    end
    return ok
end

local warned = {}
local function safeOnce(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local key = tostring(err)
        if not warned[key] then
            warned[key] = true
            warnf(key)
        end
    end
    return ok
end

local function copyText(text)
    local fn = setclipboard or toclipboard
    if fn then
        return pcall(fn, text)
    end
    return false
end

local function getChar(p)
    return p and p.Character
end

local function getHum(p)
    local c = getChar(p)
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getRoot(p)
    local c = getChar(p)
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

local function getCamera()
    return workspace.CurrentCamera
end

local function randomName()
    local ok, guid = pcall(function()
        return HttpService:GenerateGUID(false)
    end)
    if ok and guid then
        return guid
    end
    return tostring(math.random(100000, 999999)) .. tostring(os.clock())
end

----------------------------------------------------------------------
-- State (dibaca juga oleh modul lewat ctx.S)
----------------------------------------------------------------------
local S = {
    alive = true,

    esp = false,
    espHighlight = true,
    espNames = true,
    espRoles = true,
    espStatus = true,
    espDistance = true,
    espHealth = false,
    espRealName = false, -- false = cuma nama karakter in-game (DisguiseName), tanpa @username
    espPanel = false, -- false = teks langsung di atas kepala tanpa kotak gelap
    voteEsp = true, -- tag "-> target" / jumlah vote di atas kepala
    voteLasers = true, -- garis dari tangan pemilih ke orang yang dia vote
    notifyRoles = true,
    voteAlert = true,
    showGuesses = false, -- false = cuma role / tim yang PASTI yang ditampilkan

    speedOn = false,
    speed = 32,
    jumpOn = false,
    jump = 75,
    infJump = false,
    noclip = false,
    fly = false,
    flySpeed = 60,
    fovOn = false,
    fov = 90,

    crawlKeepSpeed = false,
    ghostDepth = 40,
    tsrHold = 0.35,

    fullbright = false,
    noFog = false,
    instantInteract = false,
    antiAfk = true,

    freeMouse = true,
    cursorHalo = true,

    logRemotes = false,
}

local TeamColors = {
    EVIL = Color3.fromRGB(255, 70, 80),
    VEIL = Color3.fromRGB(255, 196, 70),
    TOWN = Color3.fromRGB(80, 225, 130),
    NEUTRAL = Color3.fromRGB(200, 170, 255),
}
local UNKNOWN_COLOR = Color3.fromRGB(205, 205, 215)

local function teamColor(team)
    return (team and TeamColors[team]) or UNKNOWN_COLOR
end

----------------------------------------------------------------------
-- GUI root
----------------------------------------------------------------------
local function mount(inst)
    local ok = pcall(function()
        local hui = gethui and gethui()
        inst.Parent = hui or CoreGui
    end)
    if not ok or not inst.Parent then
        inst.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function newGui(order)
    local g = Instance.new("ScreenGui")
    g.Name = randomName()
    g.ResetOnSpawn = false
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    g.IgnoreGuiInset = true
    g.DisplayOrder = order
    if syn and syn.protect_gui then
        pcall(syn.protect_gui, g)
    end
    mount(g)
    return track(g)
end

local screen = newGui(999)
local cursorGui = newGui(1000)

-- Highlight / Billboard harus ada di dalam DataModel biar ke-render, jadi
-- jangan ditaruh di container gethui() yang di beberapa executor ada di luar game.
local espFolder = Instance.new("Folder")
espFolder.Name = randomName()
do
    local ok = pcall(function()
        espFolder.Parent = CoreGui
    end)
    if not ok or not espFolder.Parent then
        espFolder.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end
track(espFolder)

local UI = (function()
--@@INCLUDE modules/ui.lua@@
end)()({
    screen = screen,
    cursorGui = cursorGui,
    connect = connect,
    track = track,
    safe = safe,
    safeOnce = safeOnce,
    UserInputService = UserInputService,
    RunService = RunService,
    TweenService = TweenService,
    HttpService = HttpService,
    LocalPlayer = LocalPlayer,
    Config = Config,
    S = S,
})
local new, esc, hex, Theme = UI.new, UI.esc, UI.hex, UI.Theme
local notify, report = UI.notify, UI.report

----------------------------------------------------------------------
-- Modul (GameAPI, Intel, Actions)
----------------------------------------------------------------------
local ctx = {
    Players = Players,
    RunService = RunService,
    UserInputService = UserInputService,
    ReplicatedStorage = ReplicatedStorage,
    CollectionService = CollectionService,
    TextChatService = TextChatService,
    Lighting = Lighting,
    Workspace = workspace,
    LocalPlayer = LocalPlayer,
    service = service,
    connect = connect,
    track = track,
    notify = notify,
    warnf = warnf,
    getChar = getChar,
    getHum = getHum,
    getRoot = getRoot,
    S = S,
    alive = function()
        return S.alive
    end,
}

local Game = (function()
--@@INCLUDE modules/game_api.lua@@
end)()(ctx)
ctx.Game = Game

local Intel = (function()
--@@INCLUDE modules/intel.lua@@
end)()(ctx)

local Net = (function()
--@@INCLUDE modules/net.lua@@
end)()(ctx)
ctx.Net = Net

ctx.selfRole = function()
    local ok, role, team = pcall(Intel.self)
    if ok and role then
        return role, team
    end
    if Net.selfRole then
        return Net.selfRole, Game.teamOf(Net.selfRole)
    end
    return nil, nil
end

-- Bukti dari jaringan game (ServiceNetworks / RoleNetworks) diteruskan ke Intel.
local function intelCall(name, ...)
    local fn = Intel[name]
    if type(fn) == "function" then
        local ok, err = pcall(fn, ...)
        if not ok then
            warnf("Intel." .. name .. ": " .. tostring(err))
        end
    end
end

local Actions = (function()
--@@INCLUDE modules/actions.lua@@
end)()(ctx)

local function intelInfo(p)
    local ok, info = pcall(Intel.info, p)
    if not (ok and type(info) == "table") then
        return { status = {} }
    end
    local view = {
        role = info.role,
        team = info.team,
        confidence = info.confidence,
        reason = info.reason,
        disguise = info.disguise,
        status = type(info.status) == "table" and info.status or {},
    }
    -- Mode ketat (default): tebakan (likely / suspect) nggak ditampilkan sama sekali.
    if not S.showGuesses and view.confidence ~= "confirmed" then
        view.role, view.team, view.confidence, view.reason = nil, nil, nil, nil
    end
    return view
end

-- Nama karakter in-game (DisguiseName); kalau belum ada, DisplayName.
local function charName(p, info)
    info = info or intelInfo(p)
    if info.disguise and info.disguise ~= "" then
        return info.disguise
    end
    local okA, dn = pcall(Game.attr, p, "DisguiseName")
    if okA and type(dn) == "string" and dn ~= "" then
        return dn
    end
    return p.DisplayName
end

local function infoTeam(info)
    return info.team or (info.role and Game.teamOf(info.role)) or nil
end

ctx.Intel = Intel
ctx.nameOf = function(p)
    return charName(p)
end
local Votes = (function()
--@@INCLUDE modules/votes.lua@@
end)()(ctx)
ctx.votesOwnAlerts = true

-- Warna role persis dari game (roleColorsConfig), dicerahkan kalau terlalu gelap untuk panel ESP.
local function roleTint(role, fallback)
    local ok, c = pcall(Game.roleColor, role)
    if not (ok and typeof(c) == "Color3") then
        return fallback
    end
    if 0.299 * c.R + 0.587 * c.G + 0.114 * c.B < 0.45 then
        c = c:Lerp(Color3.new(1, 1, 1), 0.35)
    end
    return c
end

----------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
local ESP = { objs = {} }

function ESP.ensure(player)
    local o = ESP.objs[player]
    if o then
        return o
    end
    o = {}
    o.hl = new("Highlight", {
        FillTransparency = 0.7,
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Enabled = false,
    }, espFolder)
    o.bb = new("BillboardGui", {
        Size = UDim2.fromOffset(260, 110),
        StudsOffset = Vector3.new(0, 3.4, 0),
        AlwaysOnTop = true,
        LightInfluence = 0,
        ResetOnSpawn = false,
        Enabled = false,
    }, espFolder)
    -- Panel gelap di belakang teks biar tetap kebaca di map yang terang.
    o.tx = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, 0),
        Size = UDim2.new(0, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundColor3 = Color3.fromRGB(10, 9, 16),
        BackgroundTransparency = S.espPanel and 0.3 or 1,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        RichText = true,
        TextStrokeColor3 = Color3.new(0, 0, 0),
        TextStrokeTransparency = 0.25,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Center,
    }, o.bb)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, o.tx)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 3),
        PaddingBottom = UDim.new(0, 3),
        PaddingLeft = UDim.new(0, 7),
        PaddingRight = UDim.new(0, 7),
    }, o.tx)
    o.stroke = new("UIStroke", {
        Thickness = 1,
        Transparency = 0.35,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Enabled = S.espPanel,
    }, o.tx)
    ESP.objs[player] = o
    return o
end

function ESP.remove(player)
    local o = ESP.objs[player]
    if o then
        o.hl:Destroy()
        o.bb:Destroy()
        if o.laser then
            o.laser:Destroy()
        end
        ESP.objs[player] = nil
    end
end

local function hideLaser(o)
    if o.laser then
        o.laser.Visible = false
        o.laser.Adornee = nil
    end
end

function ESP.hide(player)
    local o = ESP.objs[player]
    if o then
        o.hl.Enabled = false
        o.hl.Adornee = nil
        o.bb.Enabled = false
        o.bb.Adornee = nil
        hideLaser(o)
    end
end

-- Laser vote: LineHandleAdornment dengan Adornee = Terrain (CFrame-nya identitas, jadi CFrame garis
-- = koordinat dunia). AlwaysOnTop supaya kelihatan tembus tembok seperti ESP lainnya.
local VOTE_COLOR = Color3.fromRGB(255, 159, 67)
local VOTE_SKIP_COLOR = Color3.fromRGB(185, 185, 200)

-- Nama tujuan vote: SKIP, "you" untuk kita sendiri, selain itu nama karakter.
local function voteName(target, you)
    if target == nil then
        return "?"
    end
    if target == Votes.SKIP then
        return "SKIP"
    end
    if target == LocalPlayer then
        return you
    end
    return charName(target)
end
local VOTE_ME_COLOR = Color3.fromRGB(255, 70, 80)

local function handPos(char)
    local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or char:FindFirstChild("RightLowerArm")
    if hand then
        return hand.Position
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    return root and (root.Position + Vector3.new(0, 1, 0)) or nil
end

local function chestPos(char)
    local t = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
    return t and t.Position or nil
end

function ESP.laserStep(o, char, target)
    local tchar = target and target.Character
    local from = char and handPos(char)
    local to = tchar and chestPos(tchar)
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if not (from and to and terrain) or (to - from).Magnitude < 0.5 then
        hideLaser(o)
        return
    end
    if not o.laser then
        o.laser = new("LineHandleAdornment", {
            Name = "Laser",
            AlwaysOnTop = true,
            ZIndex = 5,
            Thickness = 3,
            Transparency = 0.15,
            Visible = false,
        }, espFolder)
    end
    local l = o.laser
    l.Adornee = terrain
    l.CFrame = CFrame.lookAt(from, to)
    l.Length = (to - from).Magnitude
    l.Color3 = target == LocalPlayer and VOTE_ME_COLOR or VOTE_COLOR
    l.Visible = true
end

function ESP.clear()
    for p in pairs(ESP.objs) do
        ESP.remove(p)
    end
end

function ESP.statusTags(status)
    local tags = {}
    if status.downed then
        tags[#tags + 1] = "DOWNED"
    end
    if status.detained then
        tags[#tags + 1] = "DETAINED"
    end
    if status.silenced then
        tags[#tags + 1] = "SILENCED"
    end
    if status.hiding then
        tags[#tags + 1] = "IN LOCKER"
    end
    if status.poisoned then
        tags[#tags + 1] = "POISONED"
    end
    return tags
end

function ESP.step()
    local cam = getCamera()
    local myRoot = getRoot(LocalPlayer)
    local origin = (myRoot and myRoot.Position) or (cam and cam.CFrame.Position)
    local blink = (os.clock() % 0.8) < 0.4
    local voteCounts = {}
    if S.voteEsp then
        local okC, c = pcall(Votes.counts)
        voteCounts = okC and c or {}
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local char = p.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            local head = char and char:FindFirstChild("Head")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local voteTarget = (S.voteEsp or S.voteLasers) and Votes.targetOf(p) or nil
            local voteCount = S.voteEsp and voteCounts[p] or nil
            local hasVote = voteTarget ~= nil or (voteCount and voteCount > 0)

            if (S.esp or hasVote) and char and root and hum and hum.Health > 0 then
                local info = intelInfo(p)
                local status = info.status
                local team = infoTeam(info)
                local color = teamColor(team)
                local o = ESP.ensure(p)

                o.hl.Adornee = char
                o.hl.FillColor = color
                o.hl.OutlineColor = color
                o.hl.FillTransparency = (status.downed and blink) and 0.25 or 0.7
                o.hl.Enabled = S.esp and S.espHighlight
                o.tx.BackgroundTransparency = S.espPanel and 0.3 or 1
                o.stroke.Enabled = S.espPanel

                local lines = {}
                if not S.esp and S.voteEsp then
                    -- Cuma Vote ESP: nama + vote saja.
                    lines[#lines + 1] = esc(charName(p, info))
                end
                if S.esp and S.espRoles and team then
                    lines[#lines + 1] = string.format('<font color="%s" size="10">%s TEAM</font>', hex(color), team)
                end
                if S.esp and S.espNames then
                    local name = esc(charName(p, info))
                    if S.espRealName then
                        name = name .. ' <font size="10" color="#BBBBCC">@' .. esc(p.Name) .. "</font>"
                    end
                    lines[#lines + 1] = name
                end
                if S.esp and S.espRoles and info.role then
                    local mark = ""
                    if info.confidence == "likely" then
                        mark = " ?"
                    elseif info.confidence == "suspect" then
                        mark = " ??"
                    end
                    lines[#lines + 1] = string.format('<font color="%s">[%s%s]</font>', hex(roleTint(info.role, color)), esc(string.upper(info.role)), mark)
                end
                if voteTarget and S.voteEsp then
                    local tagColor = (voteTarget == LocalPlayer and VOTE_ME_COLOR) or (voteTarget == Votes.SKIP and VOTE_SKIP_COLOR) or VOTE_COLOR
                    lines[#lines + 1] = string.format('<font color="%s">VOTES → %s</font>', hex(tagColor), esc(voteName(voteTarget, "YOU")))
                end
                if voteCount and voteCount > 0 then
                    lines[#lines + 1] = string.format('<font color="%s">%d VOTE%s</font>', hex(VOTE_COLOR), voteCount, voteCount == 1 and "" or "S")
                end
                local extra = {}
                if S.esp and S.espStatus then
                    for _, tag in ipairs(ESP.statusTags(status)) do
                        extra[#extra + 1] = '<font color="#FFB84E">' .. tag .. "</font>"
                    end
                end
                if S.esp and S.espDistance and origin then
                    extra[#extra + 1] = string.format("%dm", math.floor((root.Position - origin).Magnitude))
                end
                if S.esp and S.espHealth then
                    extra[#extra + 1] = string.format("%dHP", math.floor(hum.Health))
                end
                if #extra > 0 then
                    lines[#lines + 1] = '<font size="10" color="#CFCBE0">' .. table.concat(extra, "  ") .. "</font>"
                end

                o.bb.Adornee = head or root
                o.bb.Enabled = #lines > 0
                o.tx.Text = table.concat(lines, "\n")
                o.stroke.Color = S.esp and color or UNKNOWN_COLOR
                if voteTarget and voteTarget ~= Votes.SKIP and S.voteLasers then
                    ESP.laserStep(o, char, voteTarget)
                else
                    hideLaser(o)
                end
            else
                ESP.hide(p)
            end
        end
    end
end

----------------------------------------------------------------------
-- Movement
----------------------------------------------------------------------
local Move = { baseSpeed = 16, baseJump = 50, bv = nil, bg = nil, baseFov = 70 }

function Move.stopFly()
    if Move.bv then
        Move.bv:Destroy()
        Move.bv = nil
    end
    if Move.bg then
        Move.bg:Destroy()
        Move.bg = nil
    end
    local hum = getHum(LocalPlayer)
    if hum then
        hum.PlatformStand = false
    end
end

function Move.flyStep()
    local root, hum = getRoot(LocalPlayer), getHum(LocalPlayer)
    local cam = getCamera()
    if not (root and hum and cam) then
        return
    end
    if not Move.bv or Move.bv.Parent ~= root then
        Move.stopFly()
        Move.bv = new("BodyVelocity", {
            MaxForce = Vector3.new(1e9, 1e9, 1e9),
            Velocity = Vector3.new(0, 0, 0),
        }, root)
        Move.bg = new("BodyGyro", {
            MaxTorque = Vector3.new(1e9, 1e9, 1e9),
            P = 9e4,
            CFrame = root.CFrame,
        }, root)
    end
    hum.PlatformStand = true

    local cf = cam.CFrame
    local dir = Vector3.new(0, 0, 0)
    if not UserInputService:GetFocusedTextBox() then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            dir = dir + cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            dir = dir - cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            dir = dir + cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            dir = dir - cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            dir = dir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            dir = dir - Vector3.new(0, 1, 0)
        end
    end
    if dir.Magnitude > 0 then
        Move.bv.Velocity = dir.Unit * S.flySpeed
    else
        Move.bv.Velocity = Vector3.new(0, 0, 0)
    end
    Move.bg.CFrame = cf
end

function Move.frameStep()
    local hum = getHum(LocalPlayer)
    if hum then
        if S.speedOn then
            hum.WalkSpeed = S.speed
        end
        if S.jumpOn then
            hum.UseJumpPower = true
            hum.JumpPower = S.jump
        end
    end
    if S.fly then
        Move.flyStep()
    end
    if S.fovOn then
        local cam = getCamera()
        if cam then
            cam.FieldOfView = S.fov
        end
    end
end

connect(RunService.Stepped, function()
    if S.noclip then
        local char = LocalPlayer.Character
        if char then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("BasePart") and d.CanCollide then
                    d.CanCollide = false
                end
            end
        end
    end
end)

connect(UserInputService.JumpRequest, function()
    if S.infJump then
        local hum = getHum(LocalPlayer)
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

----------------------------------------------------------------------
-- World
----------------------------------------------------------------------
local World = {
    savedLight = nil,
    savedFog = nil,
    origHold = setmetatable({}, { __mode = "k" }),
    -- Tabel biasa (bukan weak): userdata Instance bisa di-GC lalu dibuat ulang, sehingga kunci weak
    -- bisa hilang padahal instance-nya masih ada dan masih kita matikan. Isinya cuma beberapa entri.
    heldFx = {}, -- [ColorCorrectionEffect] = Enabled asli
    heldGui = {}, -- [ScreenGui EMP] = Enabled asli
    heldAtmo = {}, -- [Atmosphere] = { Density, Haze } asli
}

-- Fullbright. Waktu EMP game mengubah lighting tiap frame (lampu kedip / mati), menutup layar
-- lewat ScreenGui EmpInk / EmpAfterimage di PlayerGui, dan bisa menggelapkan lewat ColorCorrection.
-- Jadi nilai kita ditulis di render step paling akhir (sesudah script game), overlay EMP dimatikan
-- lokal, dan ColorCorrection yang menggelapkan dimatikan selama fullbright menyala.
local FULLBRIGHT = {
    Brightness = 2,
    ClockTime = 14,
    GlobalShadows = false,
    Ambient = Color3.fromRGB(178, 178, 178),
    OutdoorAmbient = Color3.fromRGB(178, 178, 178),
    ExposureCompensation = 0,
}
local FOG = { FogEnd = 1e6, FogStart = 1e6 }
local EMP_GUIS = { EmpInk = true, EmpAfterimage = true }

local function readProps(inst, props)
    local out = {}
    for k in pairs(props) do
        local ok, v = pcall(function()
            return inst[k]
        end)
        if ok and v ~= nil then
            out[k] = v
        end
    end
    return out
end

local function writeProps(inst, values)
    for k, v in pairs(values) do
        pcall(function()
            if inst[k] ~= v then
                inst[k] = v
            end
        end)
    end
end

local function luminance(c)
    return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- ColorCorrection yang bikin gelap (Brightness negatif atau tint gelap). Yang cuma ngatur warna dibiarkan.
function World.isDarkening(fx)
    local ok, dark = pcall(function()
        return fx.Brightness < -0.05 or luminance(fx.TintColor) < 0.8
    end)
    return ok and dark or false
end

-- Efek yang sudah kita matikan baru dilepas kalau benar-benar netral lagi (histeresis), supaya tween
-- gelap -> normal di akhir EMP nggak bikin layar sempat redup di tengah jalan.
function World.isNeutral(fx)
    local ok, neutral = pcall(function()
        return fx.Brightness >= -0.01 and luminance(fx.TintColor) >= 0.97
    end)
    return ok and neutral or false
end

-- Cuma overlay yang sudah terkonfirmasi. Pola nama yang lebih longgar bisa ikut menyembunyikan UI
-- tombol / cooldown EMP milik pemain Mafia.
local function isEmpGui(g)
    return g:IsA("ScreenGui") and EMP_GUIS[g.Name] == true
end

-- Dipulihkan walaupun instance-nya lagi nggak punya parent (game bisa memasangnya lagi nanti).
function World.restoreBlackout()
    for fx, enabled in pairs(World.heldFx) do
        pcall(function()
            fx.Enabled = enabled
        end)
        World.heldFx[fx] = nil
    end
    for g, enabled in pairs(World.heldGui) do
        pcall(function()
            g.Enabled = enabled
        end)
        World.heldGui[g] = nil
    end
end

function World.restoreAtmosphere()
    for a, saved in pairs(World.heldAtmo) do
        writeProps(a, saved)
        World.heldAtmo[a] = nil
    end
end

function World.refreshLighting()
    if S.fullbright then
        World.savedLight = World.savedLight or readProps(Lighting, FULLBRIGHT)
    else
        if World.savedLight then
            writeProps(Lighting, World.savedLight)
            World.savedLight = nil
        end
        World.restoreBlackout()
    end
    if S.noFog then
        World.savedFog = World.savedFog or readProps(Lighting, FOG)
    else
        if World.savedFog then
            writeProps(Lighting, World.savedFog)
            World.savedFog = nil
        end
        World.restoreAtmosphere()
    end
end

local function blackoutStep()
    for _, parent in ipairs({ Lighting, getCamera() }) do
        for _, fx in ipairs(parent:GetChildren()) do
            if fx:IsA("ColorCorrectionEffect") then
                local held = World.heldFx[fx]
                if held ~= nil then
                    -- Sudah kita matikan: lepas lagi begitu game benar-benar berhenti menggelapkan.
                    if World.isNeutral(fx) then
                        fx.Enabled = held
                        World.heldFx[fx] = nil
                    elseif fx.Enabled then
                        fx.Enabled = false
                    end
                elseif fx.Enabled and World.isDarkening(fx) then
                    World.heldFx[fx] = true
                    fx.Enabled = false
                end
            end
        end
    end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, g in ipairs(pg:GetChildren()) do
            if isEmpGui(g) and g.Enabled then
                if World.heldGui[g] == nil then
                    World.heldGui[g] = true
                end
                g.Enabled = false
            end
        end
    end
end

local function fogStep()
    for _, a in ipairs(Lighting:GetChildren()) do
        if a:IsA("Atmosphere") then
            if not World.heldAtmo[a] then
                World.heldAtmo[a] = readProps(a, { Density = true, Haze = true })
            end
            writeProps(a, { Density = 0, Haze = 0 })
        end
    end
end

function World.lightStep()
    if S.fullbright then
        writeProps(Lighting, FULLBRIGHT)
        blackoutStep()
    end
    if S.noFog then
        writeProps(Lighting, FOG)
        fogStep()
    end
end

if ProximityPromptService then
    connect(ProximityPromptService.PromptShown, function(prompt)
        if S.instantInteract and prompt.HoldDuration > 0 then
            World.origHold[prompt] = prompt.HoldDuration
            prompt.HoldDuration = 0
        end
    end)
end

function World.restorePrompts()
    for prompt, hold in pairs(World.origHold) do
        if prompt.Parent then
            prompt.HoldDuration = hold
        end
        World.origHold[prompt] = nil
    end
end

connect(LocalPlayer.Idled, function()
    if S.antiAfk and VirtualUser then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

----------------------------------------------------------------------
-- Spectate / teleport sederhana (tab Players)
----------------------------------------------------------------------
local View = { player = nil }

function View.stop()
    local cam = getCamera()
    local hum = getHum(LocalPlayer)
    if cam and hum then
        cam.CameraSubject = hum
    end
    View.player = nil
end

function View.start(player)
    local cam = getCamera()
    local hum = getHum(player)
    if cam and hum then
        cam.CameraSubject = hum
        View.player = player
        notify("Spectate", "Viewing " .. player.DisplayName, nil, 2)
    else
        notify("Spectate", player.DisplayName .. " has no character", Theme.Bad, 2)
    end
end

function View.teleportTo(player)
    local me, them = getRoot(LocalPlayer), getRoot(player)
    if me and them then
        me.CFrame = them.CFrame * CFrame.new(0, 0, 3)
    else
        notify("Teleport", "Target is not available", Theme.Bad, 2)
    end
end

----------------------------------------------------------------------
-- Dev tools: scanner, logger, dump
----------------------------------------------------------------------
local Dev = {}

function Dev.serialize(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        if depth > 2 then
            return "{...}"
        end
        local parts, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n > 12 then
                parts[#parts + 1] = "..."
                break
            end
            parts[#parts + 1] = "[" .. Dev.serialize(k, depth + 1) .. "]=" .. Dev.serialize(x, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Instance" then
        local ok, name = pcall(function()
            return v:GetFullName()
        end)
        return ok and name or tostring(v)
    end
    return tostring(v)
end

function Dev.scanRemotes()
    local out = {}
    local roots = { ReplicatedStorage, workspace, LocalPlayer:FindFirstChildOfClass("PlayerGui") }
    for _, root in ipairs(roots) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                    out[#out + 1] = d.ClassName .. "  " .. d:GetFullName()
                    if #out >= 500 then
                        break
                    end
                end
            end
        end
    end
    local text = table.concat(out, "\n")
    print("[" .. Config.Name .. "] Remotes (" .. #out .. "):\n" .. text)
    local copied = copyText(text)
    notify("Remote scan", #out .. " remotes found" .. (copied and ", copied to clipboard" or ", see console (F9)"), nil, 4)
end

-- State logger disimpan di genv supaya hook cuma kepasang sekali walau script dieksekusi ulang.
local LogState = genv.NoctisENIX_RemoteLog
if not LogState then
    LogState = { enabled = false, lines = {}, hooked = false, unavailable = false }
    genv.NoctisENIX_RemoteLog = LogState
end
LogState.enabled = false

function Dev.pushLog(remote, method, args)
    local parts = {}
    for i = 1, args.n do
        parts[#parts + 1] = Dev.serialize(args[i])
    end
    local line = string.format("%s :%s(%s)", Dev.serialize(remote), method, table.concat(parts, ", "))
    local lines = LogState.lines
    lines[#lines + 1] = line
    if #lines > 200 then
        table.remove(lines, 1)
    end
    print("[" .. Config.Name .. "] " .. line)
end

function Dev.installLogger()
    if LogState.hooked then
        return true
    end
    if not (hookmetamethod and getnamecallmethod and checkcaller) then
        LogState.unavailable = true
        return false
    end
    local pushLog = Dev.pushLog
    local ok = pcall(function()
        local old
        local hook = function(self, ...)
            local method = getnamecallmethod()
            if LogState.enabled and (method == "FireServer" or method == "InvokeServer") and not checkcaller() then
                local args = table.pack(...)
                task.spawn(pushLog, self, method, args)
            end
            return old(self, ...)
        end
        if newcclosure then
            hook = newcclosure(hook)
        end
        old = hookmetamethod(game, "__namecall", hook)
    end)
    LogState.hooked = ok
    LogState.unavailable = not ok
    return ok
end

function Dev.dumpPlayer(p)
    local lines = { "== " .. p.Name .. " (" .. p.DisplayName .. ") ==" }
    lines[#lines + 1] = "Team: " .. (p.Team and p.Team.Name or "none")
    local info = intelInfo(p)
    lines[#lines + 1] = "Intel: role=" .. tostring(info.role) .. " team=" .. tostring(info.team)
        .. " conf=" .. tostring(info.confidence) .. " reason=" .. tostring(info.reason)
    for k, v in pairs(p:GetAttributes()) do
        lines[#lines + 1] = "player attr " .. k .. " = " .. tostring(v)
    end
    local char = p.Character
    if char then
        for k, v in pairs(char:GetAttributes()) do
            lines[#lines + 1] = "char attr " .. k .. " = " .. tostring(v)
        end
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Tool") then
                lines[#lines + 1] = "char tool " .. c.Name
            end
        end
    end
    for _, c in ipairs(p:GetChildren()) do
        local extra = ""
        if c:IsA("ValueBase") then
            extra = " = " .. tostring(c.Value)
        end
        lines[#lines + 1] = "player child " .. c.ClassName .. " " .. c.Name .. extra
    end
    return table.concat(lines, "\n")
end

function Dev.dumpAllPlayers()
    local blocks = {}
    for _, p in ipairs(Players:GetPlayers()) do
        blocks[#blocks + 1] = Dev.dumpPlayer(p)
    end
    local text = table.concat(blocks, "\n\n")
    print("[" .. Config.Name .. "]\n" .. text)
    local copied = copyText(text)
    notify("Player dump", copied and "Copied to clipboard" or "Printed to console (F9)", nil, 4)
end

----------------------------------------------------------------------
-- Halaman
----------------------------------------------------------------------
UI.group("Intel")
local Pages = {}
Pages.esp = UI.tab("Visuals", "👁", "See every player through walls, colored by team")
Pages.roles = UI.tab("Roles", "🕵", "Role detection, evidence and votes")
UI.group("Player")
Pages.deception = UI.tab("Deception", "🎭", "Look like something you are not")
Pages.player = UI.tab("Player", "🏃", "Movement and camera")
UI.group("Tools")
Pages.teleport = UI.tab("Teleport", "📍", "Teleports and Mafia / Doctor tools")
Pages.players = UI.tab("Players", "👥", "Everyone in the server")
Pages.world = UI.tab("World", "🌙", "Lighting and interaction")
UI.group("Other")
Pages.dev = UI.tab("Dev Tools", "🛠", "Calibration helpers")
Pages.settings = UI.tab("Settings", "⚙", "Menu, cursor and session")

-- Visuals ------------------------------------------------------------
UI.section(Pages.esp, "Player ESP")
UI.toggle(Pages.esp, "Enable ESP", "Highlights every living player through walls. Red is Evil, gold is the Veil, green is Town, purple is Neutral, grey is not known for sure yet.", S.esp, function(v)
    S.esp = v
    if not v then
        ESP.clear()
    end
end, { bind = true, risk = "local" })
UI.toggle(Pages.esp, "Highlight", "Colored outline and fill on the body.", S.espHighlight, function(v)
    S.espHighlight = v
end)
UI.toggle(Pages.esp, "Character names", "Shows each player's in-game character name (the disguise everyone sees), not their Roblox name.", S.espNames, function(v)
    S.espNames = v
end)
UI.toggle(Pages.esp, "Also show Roblox username", "Adds the real @username next to the character name.", S.espRealName, function(v)
    S.espRealName = v
end)
UI.toggle(Pages.esp, "Team and role tags", "EVIL TEAM / [MAFIA] style tags. Only roles that are certain are shown.", S.espRoles, function(v)
    S.espRoles = v
end)
UI.toggle(Pages.esp, "Show guesses too", 'Also show likely ("?") and suspected ("??") roles. Off = only certain roles.', S.showGuesses, function(v)
    S.showGuesses = v
end)
UI.toggle(Pages.esp, "Status tags", "DOWNED, DETAINED, SILENCED, IN LOCKER, POISONED. Downed players also blink.", S.espStatus, function(v)
    S.espStatus = v
end)
UI.toggle(Pages.esp, "Distance", nil, S.espDistance, function(v)
    S.espDistance = v
end)
UI.toggle(Pages.esp, "Health", nil, S.espHealth, function(v)
    S.espHealth = v
end)
UI.toggle(Pages.esp, "Text background", "Dark box behind the text. Off = plain outlined text right above the head.", S.espPanel, function(v)
    S.espPanel = v
end)
UI.section(Pages.esp, "Votes")
UI.toggle(Pages.esp, "Vote tags", "Judge vision for every role: shows who each player votes for (VOTES → name or SKIP) and how many votes each player has, above their head. Works even with ESP off.", S.voteEsp, function(v)
    S.voteEsp = v
end, { risk = "local" })
UI.toggle(Pages.esp, "Vote lasers", "Draws a line through walls from each voter's hand to the player they vote for. Red = they are voting you.", S.voteLasers, function(v)
    S.voteLasers = v
end, { risk = "local" })

-- Roles --------------------------------------------------------------
UI.section(Pages.roles, "You")
local selfFeed = UI.feed(Pages.roles, "Your role", 2)
UI.section(Pages.roles, "Detection")
UI.toggle(Pages.roles, "Notify on detection", "Pops a notification the moment someone's role is figured out, and what gave them away.", S.notifyRoles, function(v)
    S.notifyRoles = v
end)
UI.toggle(Pages.roles, "Alert when voted", "Warns you the moment someone votes for you.", S.voteAlert, function(v)
    S.voteAlert = v
end)
UI.button(Pages.roles, "Reset round evidence", "Clears everything learned this round. Happens automatically when a new round starts.", function()
    pcall(Intel.reset, "manual")
    pcall(Votes.clearAll)
    notify("Roles", "Evidence cleared", nil, 2)
end, { action = "Reset" })
UI.section(Pages.roles, "Votes")
local voteFeed = UI.feed(Pages.roles, "Who votes who", 16, "No votes yet. They show up during voting.")
UI.section(Pages.roles, "Known roles")
local knownFeed = UI.feed(Pages.roles, "Figured out so far", 16, "Nobody yet. Evidence shows up as things happen in the round.")
UI.section(Pages.roles, "Kill feed and evidence")
local evidenceFeed = UI.feed(Pages.roles, "Latest first", 12, "Nothing happened yet.")
UI.note(Pages.roles, "Other players' roles are never sent to your client, so they are deduced: stabs or shots at night (Mafia), shots by day (Vigilante), silences (Witch), locked doors and bananas (Saboteur), unlocked doors and cleanups (Janitor), revives and cures (Doctor), Harbinger calls, team tags and death announcements.")

-- Deception ----------------------------------------------------------
UI.section(Pages.deception, "Your body")
local crawlToggle
crawlToggle = UI.toggle(Pages.deception, "Fake crawl", "Everyone sees you crawling around wounded while you are actually fine. You move at a wounded crawl so it looks real.", false, function(v)
    local ok, msg = Actions.setFakeCrawl(v)
    if v and not ok then
        crawlToggle.Set(false, true)
    end
    report("Fake crawl", ok, msg)
end, { bind = true, risk = "visible" })
UI.toggle(Pages.deception, "Keep speed while crawling", "Keeps your normal speed while crawling, real or fake.", S.crawlKeepSpeed, function(v)
    S.crawlKeepSpeed = v
end)
UI.button(Pages.deception, "Fake stab", "Makes you look like you just stabbed someone, so others think you are the Mafia. Works best in the dark or from a distance.", function()
    report("Fake stab", Actions.fakeStab())
end, { bind = true, risk = "visible", action = "Play" })
UI.button(Pages.deception, "Fake gunshot", "Makes you look like you just fired the Mafia's gun. Works best in the dark or from a distance.", function()
    report("Fake gunshot", Actions.fakeShot())
end, { bind = true, risk = "visible", action = "Play" })
local ghostToggle
ghostToggle = UI.toggle(Pages.deception, "Ghost", "Everyone else sees you hidden under the map while you walk around normally, so nobody can stab you. You cannot stab, heal, interact or use abilities while it is on.", false, function(v)
    local ok, msg = Actions.setGhost(v)
    if v and not ok then
        ghostToggle.Set(false, true)
    end
    report("Ghost", ok, msg)
end, { bind = true, risk = "server" })
UI.slider(Pages.deception, "Ghost depth", "How far under the map others see you, in studs.", 20, 120, S.ghostDepth, function(v)
    S.ghostDepth = v
end)

UI.section(Pages.deception, "Meeting")
local escapeToggle
escapeToggle = UI.toggle(Pages.deception, "Escape meeting seat", "Gets you out of your seat during meetings so you can walk around while everyone else is stuck at the table. Keeps pulling you out whenever the game seats you.", false, function(v)
    local ok, msg = Actions.setEscapeSeat(v)
    if v and not ok then
        escapeToggle.Set(false, true)
    end
    report("Escape meeting seat", ok, msg)
end, { bind = true, risk = "server" })
UI.button(Pages.deception, "Stand on the table", "Teleports you on top of the meeting table (gets you out of your seat first).", function()
    report("Stand on the table", Actions.toTable())
end, { bind = true, risk = "server", action = "Go" })

-- Teleport -----------------------------------------------------------
local function targetLabel(p)
    if not p then
        return "None"
    end
    if S.espRealName then
        return charName(p) .. "  @" .. p.Name
    end
    return charName(p)
end

UI.section(Pages.teleport, "Target")
local targetDropdown = UI.dropdown(Pages.teleport, "Target", "Choose which living player to teleport to.", function()
    local options = {}
    local ok, list = pcall(Actions.livingPlayers)
    if ok and type(list) == "table" then
        for _, p in ipairs(list) do
            local info = intelInfo(p)
            local label = targetLabel(p)
            if info.role then
                label = label .. "  [" .. info.role .. "]"
            end
            options[#options + 1] = { label = label, value = p, color = teamColor(infoTeam(info)) }
        end
    end
    return options
end, function(p)
    Actions.setTarget(p)
end)
UI.button(Pages.teleport, "To target", "Teleports you next to your target.", function()
    report("Teleport", Actions.toTarget())
end, { risk = "server", action = "Go" })
UI.button(Pages.teleport, "To downed", "Teleports you to the nearest downed player.", function()
    report("Teleport", Actions.toDowned())
end, { risk = "server", action = "Go" })
UI.button(Pages.teleport, "To detained", "Teleports you to the nearest detained player.", function()
    report("Teleport", Actions.toDetained())
end, { risk = "server", action = "Go" })

UI.section(Pages.teleport, "Mafia")
UI.button(Pages.teleport, "Teleport-Stab-Return", "Teleports you to your target, stabs them and brings you right back. Mafia only.", function()
    report("Teleport-Stab-Return", Actions.tpStabReturn())
end, { bind = true, risk = "server", action = "Strike" })
UI.slider(Pages.teleport, "Time at target", "Seconds spent next to the target before returning.", 0.15, 1.5, S.tsrHold, function(v)
    S.tsrHold = v
end, 2)
local bringToggle
bringToggle = UI.toggle(Pages.teleport, "Bring target", "Brings your target right in front of you so you can line up a shot. Only you see them move.", false, function(v)
    local ok, msg = Actions.setBring(v)
    if v and not ok then
        bringToggle.Set(false, true)
    end
    report("Bring target", ok, msg)
end, { bind = true, risk = "local" })

UI.section(Pages.teleport, "Doctor")
UI.button(Pages.teleport, "Teleport-Heal-Return", "Teleports you to whoever is down, saves them and brings you right back. Doctor only.", function()
    report("Teleport-Heal-Return", Actions.tpHealReturn())
end, { bind = true, risk = "server", action = "Save" })

-- Player -------------------------------------------------------------
UI.section(Pages.player, "Movement")
UI.toggle(Pages.player, "Walk speed", "Move faster than everyone else.", false, function(v)
    local hum = getHum(LocalPlayer)
    if v then
        Move.baseSpeed = hum and hum.WalkSpeed or 16
    elseif hum then
        hum.WalkSpeed = Move.baseSpeed
    end
    S.speedOn = v
end, { bind = true, risk = "server" })
UI.slider(Pages.player, "Speed", nil, 16, 150, S.speed, function(v)
    S.speed = v
end)
UI.toggle(Pages.player, "Jump power", nil, false, function(v)
    local hum = getHum(LocalPlayer)
    if v then
        Move.baseJump = hum and hum.JumpPower or 50
    elseif hum then
        hum.JumpPower = Move.baseJump
    end
    S.jumpOn = v
end, { risk = "server" })
UI.slider(Pages.player, "Jump", nil, 50, 250, S.jump, function(v)
    S.jump = v
end)
UI.toggle(Pages.player, "Infinite jump", nil, false, function(v)
    S.infJump = v
end, { risk = "server" })
UI.toggle(Pages.player, "Noclip", "Walk straight through walls and doors. Anyone watching will see you pass through them.", false, function(v)
    S.noclip = v
end, { bind = true, risk = "server" })
UI.section(Pages.player, "Fly")
UI.toggle(Pages.player, "Fly", "W A S D to move, Space up, Ctrl down.", false, function(v)
    S.fly = v
    if not v then
        Move.stopFly()
    end
end, { bind = true, risk = "server" })
UI.slider(Pages.player, "Fly speed", nil, 20, 200, S.flySpeed, function(v)
    S.flySpeed = v
end)
UI.section(Pages.player, "Camera")
UI.toggle(Pages.player, "Custom FOV", nil, false, function(v)
    local cam = getCamera()
    if v then
        Move.baseFov = cam and cam.FieldOfView or 70
    elseif cam then
        cam.FieldOfView = Move.baseFov
    end
    S.fovOn = v
end, { risk = "local" })
UI.slider(Pages.player, "FOV", nil, 40, 120, S.fov, function(v)
    S.fov = v
end)

-- Players ------------------------------------------------------------
UI.section(Pages.players, "Player list")
local listHolder = new("Frame", {
    Name = "PlayerList",
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    LayoutOrder = UI.nextOrder(Pages.players),
}, Pages.players)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, listHolder)
UI.button(Pages.players, "Stop spectating", "Puts the camera back on your own character.", View.stop, { action = "Stop" })

local PlayerRows = { rows = {} }

local function pillButton(name, label, parent, order)
    local b = new("TextButton", {
        Name = name,
        Size = UDim2.fromOffset(52, 26),
        BackgroundColor3 = Theme.Ink,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBlack,
        TextSize = 11,
        TextColor3 = Theme.Text,
        Text = string.upper(label),
        AutoButtonColor = false,
        LayoutOrder = order,
        ZIndex = 4,
    }, parent)
    new("UIStroke", { Color = Theme.Paper, Thickness = 1, Transparency = 0.55, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
    connect(b.MouseEnter, function()
        UI.tween(b, { BackgroundColor3 = Theme.Accent })
    end)
    connect(b.MouseLeave, function()
        UI.tween(b, { BackgroundColor3 = Theme.Ink })
    end)
    return b
end

function PlayerRows.add(p)
    if PlayerRows.rows[p] then
        return
    end
    local _, right, left = UI.card(listHolder, p.DisplayName, "@" .. p.Name, 180, nil)
    local card = right.Parent
    card.Name = "PlayerRow"
    local roleChip = UI.chip(left:FindFirstChild("TitleRow"), "?", UNKNOWN_COLOR, 3)
    local tgt = pillButton("Target", "Target", right, 1)
    local tp = pillButton("TP", "TP", right, 2)
    local vw = pillButton("View", "View", right, 3)
    connect(tgt.MouseButton1Click, function()
        local ok, msg = Actions.setTarget(p)
        if ok ~= false then
            targetDropdown.SetLabel(targetLabel(p))
        end
        report("Target", ok ~= false, msg or ("Target: " .. p.DisplayName))
    end)
    connect(tp.MouseButton1Click, function()
        View.teleportTo(p)
    end)
    connect(vw.MouseButton1Click, function()
        View.start(p)
    end)
    PlayerRows.rows[p] = { card = card, role = roleChip, title = left:FindFirstChild("TitleRow"):FindFirstChild("Title") }
end

function PlayerRows.remove(p)
    local r = PlayerRows.rows[p]
    if r then
        r.card:Destroy()
        PlayerRows.rows[p] = nil
    end
end

-- World --------------------------------------------------------------
UI.section(Pages.world, "Lighting")
UI.toggle(Pages.world, "Fullbright", "Lights up the whole map, also during an EMP blackout (hides the EMP ink overlay and dark color filters). Only you see the difference.", false, function(v)
    S.fullbright = v
    World.refreshLighting()
end, { bind = true, risk = "local" })
UI.toggle(Pages.world, "No fog", "Removes distance fog and the map's Atmosphere haze.", false, function(v)
    S.noFog = v
    World.refreshLighting()
end, { risk = "local" })
UI.section(Pages.world, "Interaction")
UI.toggle(Pages.world, "Instant interact", "Sets hold time of every prompt you see to zero (lockers, doors, medkits).", false, function(v)
    S.instantInteract = v
    if not v then
        World.restorePrompts()
    end
end, { risk = "server" })
UI.section(Pages.world, "Utility")
UI.toggle(Pages.world, "Anti AFK", "Stops the idle kick.", S.antiAfk, function(v)
    S.antiAfk = v
end)

-- Dev tools ----------------------------------------------------------
UI.note(Pages.dev, "For a full calibration run <b>NoctisENIX Inspector</b> (separate loadstring, see README) during a match and send the saved file. These buttons are the quick version.")
UI.section(Pages.dev, "Game network")
local netFeed = UI.feed(Pages.dev, "Network hooks and recent events", 10, "Waiting for the game's network...")
UI.section(Pages.dev, "Scanner")
UI.button(Pages.dev, "Scan remotes", "Lists every RemoteEvent / RemoteFunction and copies them.", Dev.scanRemotes, { action = "Scan" })
UI.button(Pages.dev, "Dump players", "Attributes, tools, values and current intel for everyone.", Dev.dumpAllPlayers, { action = "Dump" })
UI.section(Pages.dev, "Remote logger")
UI.toggle(Pages.dev, "Log remote calls", "Logs FireServer / InvokeServer calls your client makes. Needs hookmetamethod.", false, function(v)
    if v and not Dev.installLogger() then
        notify("Remote logger", "This executor does not support hookmetamethod", Theme.Bad, 4)
        LogState.enabled = false
        return
    end
    LogState.enabled = v
    S.logRemotes = v
end)
UI.button(Pages.dev, "Copy remote log", nil, function()
    local text = table.concat(LogState.lines, "\n")
    if text == "" then
        notify("Remote logger", "Log is empty", nil, 2)
        return
    end
    local copied = copyText(text)
    notify("Remote logger", copied and "Copied to clipboard" or "Printed in console (F9)", nil, 3)
end, { action = "Copy" })

-- Settings -----------------------------------------------------------
UI.section(Pages.settings, "Menu")
local menuBind = { key = Config.ToggleKey }
UI.registerBind(menuBind, "__menu", true)
UI.keyCard(Pages.settings, "Menu key", "Opens and closes this window. Right-click resets it to " .. Config.ToggleKey.Name .. ".", menuBind)
UI.section(Pages.settings, "Keybinds")
UI.note(Pages.settings, "Click a key chip, then press a key. Right-click a chip (or press Backspace while it says PRESS) to remove that keybind. Keybinds are saved to <b>workspace/NoctisENIX/settings.json</b> and come back next time you run the script.")
UI.button(Pages.settings, "Clear all keybinds", "Removes every feature keybind (the menu key stays).", function()
    local ok = UI.clearAllBinds()
    report("Keybinds", true, ok and "All keybinds cleared and saved." or "All keybinds cleared (this executor cannot save files).")
end, { action = "Clear" })
UI.slider(Pages.settings, "UI scale", "Makes the whole window bigger or smaller.", 0.7, 1.3, 1, function(v)
    UI.scale.Scale = v
end, 2)
UI.section(Pages.settings, "Game hotkeys")
local hotkeyFeed = UI.feed(Pages.settings, "Your in-game keys", 5)
UI.note(Pages.settings, "Read live from the game's own hotkey settings (* = you changed it in the game's Settings). If an ability seems dead, check its key here first. Binding a NoctisENIX feature to one of these keys shows a warning, because pressing it would do both.")
UI.keyConflict = function(keyCode)
    return Game.hotkeyAction(keyCode.Name)
end
UI.section(Pages.settings, "Cursor")
UI.toggle(Pages.settings, "Free mouse while menu is open", "Unlocks and shows the mouse while the menu is open, even when the game hides it.", S.freeMouse, function(v)
    S.freeMouse = v
    if not v then
        UI.restoreCursor()
    end
end)
UI.toggle(Pages.settings, "Cursor halo", "Draws a ring under your mouse over the menu so you never lose it.", S.cursorHalo, function(v)
    S.cursorHalo = v
end)
UI.note(Pages.settings, "Close the menu (" .. Config.ToggleKey.Name .. ") before you aim a stab or a shot. While it is open the mouse is freed, so the game cannot aim with it.")
UI.section(Pages.settings, "Game")
local statusFeed = UI.feed(Pages.settings, "Status", 3)
UI.section(Pages.settings, "Session")
UI.button(Pages.settings, "Rejoin server", nil, function()
    pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end, { action = "Rejoin" })

local Unload
UI.button(Pages.settings, "Unload NoctisENIX", "Turns everything off and removes the script.", function()
    Unload()
end, { action = "Unload" })

----------------------------------------------------------------------
-- Refresh UI berkala
----------------------------------------------------------------------
local Status = { game = "checking...", config = "checking..." }

local function refreshUi()
    for p, r in pairs(PlayerRows.rows) do
        local info = intelInfo(p)
        local team = infoTeam(info)
        local label = info.role and string.upper(info.role) or (team and (team .. " TEAM")) or "?"
        if info.role and info.confidence and info.confidence ~= "confirmed" then
            label = label .. " ?"
        end
        local color = teamColor(team)
        r.role.Text = label
        r.role.TextColor3 = info.role and roleTint(info.role, color) or color
        r.role.BackgroundColor3 = color
        if r.title then
            r.title.Text = charName(p, info)
        end
    end

    local okSelf, role, team = pcall(Intel.self)
    if not okSelf then
        role, team = nil, nil
    end
    team = team or (role and Game.teamOf(role))
    selfFeed.Set({
        { text = "<b>" .. esc(role or "Unknown yet") .. "</b>" .. (team and ("  -  " .. team .. " TEAM") or ""), color = teamColor(team) },
    })

    local known = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local info = intelInfo(p)
            local t = infoTeam(info)
            if info.role or t then
                local line = "<b>" .. esc(charName(p, info)) .. "</b>  " .. esc(info.role or "?") .. (t and ("  [" .. t .. "]") or "")
                if info.confidence then
                    line = line .. "  -  " .. info.confidence
                end
                if info.reason then
                    line = line .. '  <font color="#8F89AA">(' .. esc(info.reason) .. ")</font>"
                end
                known[#known + 1] = { text = line, color = teamColor(t) }
            end
        end
    end
    knownFeed.Set(known)

    local voteItems = {}
    local okV, vlist = pcall(Votes.list)
    local okVC, vcounts = pcall(Votes.counts)
    local shownLast = false
    if okV and type(vlist) == "table" and #vlist == 0 and not Votes.skip and Votes.last and os.clock() - Votes.last.t < 120 then
        vlist, vcounts, shownLast = Votes.last.list, Votes.last.counts, true
        okVC = true
    end
    if okV and type(vlist) == "table" then
        if shownLast then
            voteItems[#voteItems + 1] = { text = "Last voting:", color = Theme.Muted }
        end
        if okVC and type(vcounts) == "table" then
            local tally = {}
            for target, n in pairs(vcounts) do
                if target and n > 0 then
                    tally[#tally + 1] = { target = target, n = n }
                end
            end
            table.sort(tally, function(a, b)
                return a.n > b.n
            end)
            local parts = {}
            for i = 1, math.min(#tally, 6) do
                local e = tally[i]
                local n = tostring(e.n)
                if e.target == Votes.SKIP and Votes.skip and Votes.skip.need and not shownLast then
                    n = n .. "/" .. Votes.skip.need
                end
                parts[#parts + 1] = "<b>" .. esc(voteName(e.target, "You")) .. "</b> " .. n
            end
            if #parts > 0 then
                voteItems[#voteItems + 1] = { text = "Tally: " .. table.concat(parts, "   "), color = VOTE_COLOR }
            end
        end
        for _, e in ipairs(vlist) do
            if #voteItems >= 16 then
                break
            end
            local me = e.target == LocalPlayer
            voteItems[#voteItems + 1] = {
                text = "<b>" .. esc(voteName(e.voter, "You")) .. "</b>  →  <b>"
                    .. esc(voteName(e.target, "You")) .. '</b>  <font color="#8F89AA">(' .. esc(e.src) .. ")</font>",
                color = me and VOTE_ME_COLOR or nil,
            }
        end
    end
    voteFeed.Set(voteItems)

    local okFeed, feed = pcall(Intel.feed)
    local items = {}
    if okFeed and type(feed) == "table" then
        for i = #feed, math.max(1, #feed - 11), -1 do
            local e = feed[i]
            items[#items + 1] = {
                text = string.format('<font color="#8F89AA">%ds</font>  %s', math.floor(os.clock() - (e.t or os.clock())), esc(e.text)),
            }
        end
    end
    evidenceFeed.Set(items)

    local okT, target = pcall(Actions.getTarget)
    if okT then
        targetDropdown.SetLabel(targetLabel(target))
    end

    local hooks, nHooks = {}, 0
    for k, v in pairs(Net.found or {}) do
        if v then
            nHooks = nHooks + 1
            hooks[#hooks + 1] = k
        end
    end
    for k, v in pairs(Votes.found or {}) do
        if v then
            nHooks = nHooks + 1
            hooks[#hooks + 1] = k
        end
    end
    table.sort(hooks)
    statusFeed.Set({
        { text = "Game: " .. esc(Status.game) },
        { text = "Config: " .. esc(Status.config) },
        { text = "Network: " .. nHooks .. " hooks" .. (Net.selfRole and ("  |  server says you are " .. esc(Net.selfRole)) or "") },
    })
    local netItems = { { text = "Hooks: " .. (#hooks > 0 and esc(table.concat(hooks, ", ")) or "none found"), color = nHooks > 0 and Theme.Good or Theme.Warn } }
    local log = Net.log or {}
    for i = #log, math.max(1, #log - 8), -1 do
        netItems[#netItems + 1] = { text = esc(log[i]) }
    end
    netFeed.Set(netItems)

    local okH, hotkeys = pcall(Game.gameHotkeys)
    local hkItems = {}
    if okH and type(hotkeys) == "table" then
        local row = {}
        for _, a in ipairs(hotkeys) do
            if a.group == "ROLE" or a.group == "GENERAL" or a.id == "freeCursor" then
                row[#row + 1] = esc(a.label) .. "  <b>" .. esc(a.key or "unbound") .. "</b>" .. (a.custom and "*" or "")
                if #row == 3 then
                    hkItems[#hkItems + 1] = { text = table.concat(row, "     "), color = Theme.Text }
                    row = {}
                end
            end
        end
        if #row > 0 then
            hkItems[#hkItems + 1] = { text = table.concat(row, "     "), color = Theme.Text }
        end
    end
    hotkeyFeed.Set(hkItems)
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
for _, p in ipairs(Players:GetPlayers()) do
    PlayerRows.add(p)
end
connect(Players.PlayerAdded, PlayerRows.add)
connect(Players.PlayerRemoving, function(p)
    PlayerRows.remove(p)
    ESP.remove(p)
    if View.player == p then
        View.stop()
    end
end)

connect(LocalPlayer.CharacterAdded, function()
    -- Fly dibangun ulang otomatis oleh flyStep.
    Move.bv, Move.bg = nil, nil
    View.player = nil
end)

safe(Intel.start)
safe(Net.start, {
    role = function(p, role, conf, why)
        intelCall("addEvidence", p, role, conf, why)
    end,
    team = function(p, team, conf, why)
        intelCall("addTeam", p, team, conf, why)
    end,
    self = function(role, why)
        intelCall("addEvidence", LocalPlayer, role, "confirmed", why, true)
    end,
    message = function(text, source)
        intelCall("ingestMessage", text, source)
    end,
    teammate = function(p, team, why)
        if team then
            intelCall("addTeam", p, team, "confirmed", why)
        end
    end,
    round = function()
        pcall(Votes.clearAll)
    end,
})
safe(Votes.start)

-- Lighting ditulis di render step paling akhir (sesudah efek EMP game, sebelum kursor menu).
do
    local lightBind = "NoctisENIX_Light_" .. tostring(math.random(1000, 9999))
    local function lightFrame()
        if S.alive then
            safeOnce(World.lightStep)
        end
    end
    local bound = pcall(function()
        RunService:BindToRenderStep(lightBind, Enum.RenderPriority.Last.Value + 40, lightFrame)
    end)
    if bound then
        track(function()
            pcall(function()
                RunService:UnbindFromRenderStep(lightBind)
            end)
        end)
    else
        connect(RunService.RenderStepped, lightFrame)
    end
end

local acc = { intel = 0, esp = 0, ui = 0 }
connect(RunService.Heartbeat, function(dt)
    if not S.alive then
        return
    end
    safeOnce(Move.frameStep)

    acc.intel = acc.intel + dt
    if acc.intel >= 0.25 then
        acc.intel = 0
        safeOnce(Intel.step)
        safeOnce(Net.step)
        safeOnce(Votes.step)
    end
    acc.esp = acc.esp + dt
    if acc.esp >= 0.1 then
        acc.esp = 0
        safeOnce(ESP.step)
    end
    acc.ui = acc.ui + dt
    if acc.ui >= 0.5 then
        acc.ui = 0
        if UI.main.Visible then
            safeOnce(refreshUi)
        end
    end
end)

connect(UI.closeButton.MouseButton1Click, function()
    UI.setVisible(false)
    notify("NoctisENIX", "Menu hidden. Press " .. (menuBind.key and menuBind.key.Name or "the menu key") .. " to open it again.", nil, 3)
end)

connect(UserInputService.InputBegan, function(input, processed)
    if processed or UI.capturing or os.clock() - UI.lastCapture < 0.3 then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end
    if UserInputService:GetFocusedTextBox() then
        return
    end
    if menuBind.key and input.KeyCode == menuBind.key then
        UI.setVisible(not UI.main.Visible)
        if UI.main.Visible then
            safeOnce(refreshUi)
        end
        return
    end
    for _, bind in ipairs(UI.binds) do
        if bind.fire and bind.key and bind.key == input.KeyCode then
            task.spawn(safe, bind.fire)
        end
    end
end)

Unload = function()
    if not S.alive then
        return
    end
    S.alive = false
    LogState.enabled = false

    pcall(Actions.stop)
    pcall(Intel.stop)
    pcall(Move.stopFly)
    pcall(View.stop)
    pcall(World.restorePrompts)
    pcall(UI.restoreCursor)
    pcall(function()
        S.fullbright, S.noFog = false, false
        World.refreshLighting()
    end)
    pcall(function()
        local hum = getHum(LocalPlayer)
        if hum then
            if S.speedOn then
                hum.WalkSpeed = Move.baseSpeed
            end
            if S.jumpOn then
                hum.JumpPower = Move.baseJump
            end
        end
        local cam = getCamera()
        if cam and S.fovOn then
            cam.FieldOfView = Move.baseFov
        end
    end)
    pcall(ESP.clear)

    for _, item in ipairs(Janitor) do
        local kind = typeof(item)
        if kind == "RBXScriptConnection" then
            pcall(function()
                item:Disconnect()
            end)
        elseif kind == "Instance" then
            pcall(function()
                item:Destroy()
            end)
        elseif kind == "function" then
            pcall(item)
        end
    end
    Janitor = {}

    if genv.NoctisENIX and genv.NoctisENIX.Unload == Unload then
        genv.NoctisENIX = nil
    end
end

genv.NoctisENIX = { Version = Config.Version, Unload = Unload, Intel = Intel, Actions = Actions, Game = Game, Net = Net, Votes = Votes, UI = UI }

UI.selectTab(UI.tabs[1])
safe(UI.loadSettings)

task.spawn(function()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    local name = (ok and info and info.Name) or "unknown"
    if string.find(string.lower(name), "mafia", 1, true) then
        Status.game = name .. " (OK)"
    else
        Status.game = name .. " (not MAFIA? general features still work)"
    end
end)

task.spawn(function()
    local caps = Game.caps or {}
    local okRoles = pcall(Game.roles, true)
    local fromConfig = okRoles and Game.rolesFromConfig
    Status.config = string.format(
        "%s | require %s | identity switch %s",
        fromConfig and "roles loaded from the game" or "built-in role list",
        caps.require and "yes" or "no",
        caps.setthreadidentity and "yes" or "no"
    )
end)

refreshUi()
notify("NoctisENIX v" .. Config.Version, "Loaded. " .. (menuBind.key and menuBind.key.Name or Config.ToggleKey.Name) .. " opens and closes the menu.", nil, 5)
