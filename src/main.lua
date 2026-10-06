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
    Version = "2.0.0",
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

local function esc(text)
    text = tostring(text)
    text = string.gsub(text, "&", "&amp;")
    text = string.gsub(text, "<", "&lt;")
    text = string.gsub(text, ">", "&gt;")
    return text
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
    notifyRoles = true,
    voteAlert = true,

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

    logRemotes = false,
}

local TeamColors = {
    EVIL = Color3.fromRGB(255, 64, 64),
    VEIL = Color3.fromRGB(255, 196, 64),
    TOWN = Color3.fromRGB(80, 230, 120),
}
local UNKNOWN_COLOR = Color3.fromRGB(215, 215, 225)
local GOOD_COLOR = Color3.fromRGB(80, 230, 140)
local BAD_COLOR = Color3.fromRGB(255, 90, 90)

local function teamColor(team)
    return (team and TeamColors[team]) or UNKNOWN_COLOR
end

----------------------------------------------------------------------
-- GUI helpers
----------------------------------------------------------------------
local Theme = {
    Bg = Color3.fromRGB(13, 12, 20),
    Panel = Color3.fromRGB(20, 18, 32),
    Elem = Color3.fromRGB(30, 27, 46),
    ElemHover = Color3.fromRGB(42, 38, 64),
    Accent = Color3.fromRGB(168, 85, 247),
    Text = Color3.fromRGB(236, 232, 248),
    Sub = Color3.fromRGB(150, 144, 176),
    Off = Color3.fromRGB(58, 54, 84),
}

local function new(class, props, parent)
    local inst = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            inst[k] = v
        end
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function tween(inst, props, t)
    local info = TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(inst, info, props):Play()
end

local function corner(inst, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, inst)
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

local function mount(inst)
    local ok = pcall(function()
        local hui = gethui and gethui()
        inst.Parent = hui or CoreGui
    end)
    if not ok or not inst.Parent then
        inst.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local screen = new("ScreenGui", {
    Name = randomName(),
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
})
if syn and syn.protect_gui then
    pcall(syn.protect_gui, screen)
end
mount(screen)
track(screen)

-- Highlight / Billboard harus ada di dalam DataModel biar ke-render, jadi
-- jangan ditaruh di container gethui() yang di beberapa executor ada di luar game.
local espFolder = new("Folder", { Name = randomName() })
do
    local ok = pcall(function()
        espFolder.Parent = CoreGui
    end)
    if not ok or not espFolder.Parent then
        espFolder.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end
track(espFolder)

----------------------------------------------------------------------
-- Notifikasi (toast)
----------------------------------------------------------------------
local toastHolder = new("Frame", {
    BackgroundTransparency = 1,
    Size = UDim2.new(0, 280, 1, -20),
    Position = UDim2.new(1, -290, 0, 10),
}, screen)
new("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
}, toastHolder)

local toastCount = 0
local function notify(title, text, color, duration)
    if not S.alive then
        return
    end
    toastCount = toastCount + 1
    local label = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        RichText = true,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Theme.Text,
        LayoutOrder = toastCount,
        Text = string.format("<b>%s</b>\n%s", esc(title), esc(text or "")),
    }, toastHolder)
    corner(label, 8)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, label)
    new("UIStroke", { Color = color or Theme.Accent, Thickness = 1.2, Transparency = 0.2 }, label)
    -- Tumpukan toast dibatasi biar nggak menutupi layar.
    local children = toastHolder:GetChildren()
    local labels = {}
    for _, c in ipairs(children) do
        if c:IsA("TextLabel") then
            labels[#labels + 1] = c
        end
    end
    if #labels > 6 then
        table.sort(labels, function(a, b)
            return a.LayoutOrder < b.LayoutOrder
        end)
        for i = 1, #labels - 6 do
            labels[i]:Destroy()
        end
    end
    task.delay(duration or 4, function()
        if label and label.Parent then
            label:Destroy()
        end
    end)
end

local function report(title, ok, msg)
    notify(title, msg or (ok and "Done" or "Failed"), ok and GOOD_COLOR or BAD_COLOR, ok and 3 or 4)
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(600, 420),
    Position = UDim2.new(0.5, -300, 0.5, -210),
    BackgroundColor3 = Theme.Bg,
    BorderSizePixel = 0,
    Active = true,
}, screen)
corner(main, 10)
new("UIStroke", { Color = Theme.Accent, Thickness = 1.4, Transparency = 0.35 }, main)

local titleBar = new("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
}, main)
corner(titleBar, 10)
new("Frame", {
    Size = UDim2.new(1, 0, 0, 10),
    Position = UDim2.new(0, 0, 1, -10),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
}, titleBar)

new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(14, 0),
    Size = UDim2.new(1, -60, 1, 0),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
    RichText = true,
    TextColor3 = Theme.Text,
    Text = 'Noctis<font color="#a855f7">ENIX</font>  <font color="#968fb0" size="12">MAFIA V2.3 ACT II  |  v' .. Config.Version .. "</font>",
}, titleBar)

local closeBtn = new("TextButton", {
    Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -34, 0.5, -11),
    BackgroundColor3 = Theme.Elem,
    BorderSizePixel = 0,
    Text = "X",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = Theme.Text,
    AutoButtonColor = false,
}, titleBar)
corner(closeBtn, 5)

do
    local dragging, dragStart, startPos = false, nil, nil
    connect(titleBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local tabBar = new("ScrollingFrame", {
    Position = UDim2.fromOffset(8, 44),
    Size = UDim2.new(0, 112, 1, -52),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)

local content = new("Frame", {
    Position = UDim2.fromOffset(128, 44),
    Size = UDim2.new(1, -136, 1, -52),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
}, main)
corner(content, 8)

----------------------------------------------------------------------
-- Komponen UI
----------------------------------------------------------------------
local UI = { tabs = {}, binds = {}, capturing = false, lastCapture = -1 }
local orderCounter = setmetatable({}, { __mode = "k" })

function UI.nextOrder(frame)
    local n = (orderCounter[frame] or 0) + 1
    orderCounter[frame] = n
    return n
end

function UI.selectTab(target)
    for _, t in ipairs(UI.tabs) do
        local active = t == target
        t.page.Visible = active
        tween(t.button, {
            BackgroundColor3 = active and Theme.Accent or Theme.Elem,
            TextColor3 = active and Color3.new(1, 1, 1) or Theme.Sub,
        })
    end
end

function UI.tab(name)
    local button = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Theme.Elem,
        BorderSizePixel = 0,
        Text = name,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextColor3 = Theme.Sub,
        AutoButtonColor = false,
        LayoutOrder = #UI.tabs + 1,
    }, tabBar)
    corner(button, 6)

    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Theme.Accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
    }, content)
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 10),
    }, page)

    local tab = { name = name, button = button, page = page }
    UI.tabs[#UI.tabs + 1] = tab
    connect(button.MouseButton1Click, function()
        UI.selectTab(tab)
    end)
    return page
end

function UI.row(page, height)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Elem,
        BorderSizePixel = 0,
        LayoutOrder = UI.nextOrder(page),
    }, page)
    corner(row, 6)
    return row
end

function UI.section(page, text)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = string.upper(text),
        LayoutOrder = UI.nextOrder(page),
    }, page)
end

function UI.label(page, text)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Theme.Sub,
        TextWrapped = true,
        RichText = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = text,
        LayoutOrder = UI.nextOrder(page),
    }, page)
end

-- Tombol kecil buat keybind. Klik lalu tekan tombol; Escape / Backspace = hapus.
function UI.keyButton(parent, position, bind)
    local kb = new("TextButton", {
        Size = UDim2.fromOffset(58, 20),
        Position = position,
        BackgroundColor3 = Theme.Off,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
        TextColor3 = Theme.Text,
        Text = bind.key and bind.key.Name or "NONE",
        AutoButtonColor = false,
        ZIndex = 3,
    }, parent)
    corner(kb, 4)
    connect(kb.MouseButton1Click, function()
        if UI.capturing then
            return
        end
        UI.capturing = true
        kb.Text = "..."
        local conn
        conn = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
                bind.key = nil
            else
                bind.key = input.KeyCode
            end
            kb.Text = bind.key and bind.key.Name or "NONE"
            conn:Disconnect()
            UI.capturing = false
            UI.lastCapture = os.clock()
        end)
        track(conn)
    end)
    return kb
end

function UI.bind(fire)
    local bind = { key = nil, fire = fire }
    UI.binds[#UI.binds + 1] = bind
    return bind
end

-- opts.bind = true -> tombol keybind yang men-toggle.
function UI.toggle(page, text, default, callback, opts)
    local row = UI.row(page, 30)
    local hasBind = opts and opts.bind
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, hasBind and -130 or -64, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = text,
    }, row)
    local trackFrame = new("Frame", {
        Size = UDim2.fromOffset(36, 18),
        Position = UDim2.new(1, -46, 0.5, -9),
        BackgroundColor3 = Theme.Off,
        BorderSizePixel = 0,
    }, row)
    corner(trackFrame, 9)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, trackFrame)
    corner(knob, 7)
    local hit = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }, row)

    local state = default and true or false
    local api = {}
    local function render()
        tween(trackFrame, { BackgroundColor3 = state and Theme.Accent or Theme.Off })
        tween(knob, { Position = state and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2) })
    end
    function api.Set(value, silent)
        state = value and true or false
        render()
        if not silent and callback then
            task.spawn(safe, callback, state)
        end
    end
    function api.Get()
        return state
    end
    connect(hit.MouseButton1Click, function()
        api.Set(not state)
    end)
    if hasBind then
        api.bind = UI.bind(function()
            api.Set(not state)
        end)
        UI.keyButton(row, UDim2.new(1, -112, 0.5, -10), api.bind)
    end
    render()
    return api
end

-- opts.bind = true -> tombol keybind yang menjalankan callback.
function UI.button(page, text, callback, opts)
    local hasBind = opts and opts.bind
    local holder = page
    local btnParent = page
    local btnSize = UDim2.new(1, 0, 0, 30)
    local btnPos = nil
    local holderFrame
    if hasBind then
        holderFrame = new("Frame", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            LayoutOrder = UI.nextOrder(page),
        }, page)
        holder = holderFrame
        btnParent = holderFrame
        btnSize = UDim2.new(1, -66, 1, 0)
        btnPos = UDim2.fromOffset(0, 0)
    end
    local btn = new("TextButton", {
        Size = btnSize,
        Position = btnPos or UDim2.new(),
        BackgroundColor3 = Theme.Elem,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextColor3 = Theme.Text,
        Text = text,
        AutoButtonColor = false,
        LayoutOrder = hasBind and 0 or UI.nextOrder(page),
    }, btnParent)
    corner(btn, 6)
    connect(btn.MouseEnter, function()
        tween(btn, { BackgroundColor3 = Theme.ElemHover })
    end)
    connect(btn.MouseLeave, function()
        tween(btn, { BackgroundColor3 = Theme.Elem })
    end)
    connect(btn.MouseButton1Click, function()
        task.spawn(safe, callback)
    end)
    if hasBind then
        local bind = UI.bind(function()
            task.spawn(safe, callback)
        end)
        UI.keyButton(holder, UDim2.new(1, -60, 0.5, -10), bind)
        return btn, bind
    end
    return btn
end

function UI.slider(page, text, min, max, default, callback, decimals)
    local row = UI.row(page, 46)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 3),
        Size = UDim2.new(1, -80, 0, 18),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
    }, row)
    local valueLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -70, 0, 3),
        Size = UDim2.fromOffset(60, 18),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = tostring(default),
    }, row)
    local bar = new("Frame", {
        Position = UDim2.new(0, 10, 1, -15),
        Size = UDim2.new(1, -20, 0, 6),
        BackgroundColor3 = Theme.Off,
        BorderSizePixel = 0,
    }, row)
    corner(bar, 3)
    local fill = new("Frame", {
        Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
    }, bar)
    corner(fill, 3)
    local hit = new("TextButton", {
        Position = UDim2.new(0, 0, 1, -26),
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Text = "",
    }, row)

    local dragging = false
    local value = default
    local function apply(v)
        value = v
        fill.Size = UDim2.new((v - min) / (max - min), 0, 1, 0)
        valueLabel.Text = tostring(v)
        if callback then
            callback(v)
        end
    end
    local function fromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = min + (max - min) * rel
        if decimals and decimals > 0 then
            v = tonumber(string.format("%." .. decimals .. "f", v))
        else
            v = math.floor(v + 0.5)
        end
        if v ~= value then
            apply(v)
        end
    end
    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            fromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- Dropdown: getOptions() -> { {label=, value=}, ... }, dipanggil tiap dibuka.
function UI.dropdown(page, text, getOptions, onSelect)
    local row = UI.row(page, 30)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(0.4, -10, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
    }, row)
    local valueBtn = new("TextButton", {
        Position = UDim2.new(0.4, 0, 0.5, -11),
        Size = UDim2.new(0.6, -8, 0, 22),
        BackgroundColor3 = Theme.Off,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
        TextColor3 = Theme.Text,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = "None  v",
        AutoButtonColor = false,
    }, row)
    corner(valueBtn, 5)
    local list = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = UI.nextOrder(page),
    }, page)
    new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, list)

    local api = {}
    function api.SetLabel(label)
        valueBtn.Text = tostring(label) .. "  v"
    end
    local function close()
        list.Visible = false
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then
                c:Destroy()
            end
        end
    end
    connect(valueBtn.MouseButton1Click, function()
        if list.Visible then
            close()
            return
        end
        local ok, options = pcall(getOptions)
        if not ok or type(options) ~= "table" then
            options = {}
        end
        if #options == 0 then
            options = { { label = "(nobody)", value = nil, empty = true } }
        end
        for i, opt in ipairs(options) do
            local ob = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundColor3 = Theme.Elem,
                BorderSizePixel = 0,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = opt.color or Theme.Text,
                Text = opt.label,
                AutoButtonColor = true,
                LayoutOrder = i,
            }, list)
            corner(ob, 5)
            connect(ob.MouseButton1Click, function()
                close()
                if not opt.empty then
                    api.SetLabel(opt.label)
                    task.spawn(safe, onSelect, opt.value)
                end
            end)
        end
        list.Visible = true
    end)
    return api
end

-- Daftar baris teks (feed). api.Set({ {text=, color=}, ... }).
function UI.feed(page, maxLines)
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Elem,
        BorderSizePixel = 0,
        LayoutOrder = UI.nextOrder(page),
    }, page)
    corner(holder, 6)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, holder)
    new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
    local lines = {}
    for i = 1, maxLines do
        lines[i] = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Sub,
            Text = "",
            Visible = false,
            LayoutOrder = i,
        }, holder)
    end
    local api = {}
    function api.Set(items)
        for i = 1, maxLines do
            local item = items[i]
            local l = lines[i]
            if item then
                l.Text = item.text
                l.TextColor3 = item.color or Theme.Sub
                l.Visible = true
            else
                l.Visible = false
            end
        end
    end
    return api
end

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

ctx.selfRole = function()
    local ok, role, team = pcall(Intel.self)
    if ok then
        return role, team
    end
    return nil, nil
end

local Actions = (function()
--@@INCLUDE modules/actions.lua@@
end)()(ctx)

local function intelInfo(p)
    local ok, info = pcall(Intel.info, p)
    if ok and type(info) == "table" then
        return info
    end
    return { status = {} }
end

local function infoTeam(info)
    return info.team or (info.role and Game.teamOf(info.role)) or nil
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
        FillTransparency = 0.65,
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Enabled = false,
    }, espFolder)
    o.bb = new("BillboardGui", {
        Size = UDim2.fromOffset(200, 70),
        StudsOffset = Vector3.new(0, 3.2, 0),
        AlwaysOnTop = true,
        LightInfluence = 0,
        ResetOnSpawn = false,
        Enabled = false,
    }, espFolder)
    o.tx = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        RichText = true,
        TextStrokeTransparency = 0.4,
        TextColor3 = Color3.new(1, 1, 1),
        TextYAlignment = Enum.TextYAlignment.Bottom,
        TextWrapped = true,
    }, o.bb)
    ESP.objs[player] = o
    return o
end

function ESP.remove(player)
    local o = ESP.objs[player]
    if o then
        o.hl:Destroy()
        o.bb:Destroy()
        ESP.objs[player] = nil
    end
end

function ESP.hide(player)
    local o = ESP.objs[player]
    if o then
        o.hl.Enabled = false
        o.hl.Adornee = nil
        o.bb.Enabled = false
        o.bb.Adornee = nil
    end
end

function ESP.clear()
    for p in pairs(ESP.objs) do
        ESP.remove(p)
    end
end

local function hex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
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

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local char = p.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            local head = char and char:FindFirstChild("Head")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if S.esp and char and root and hum and hum.Health > 0 then
                local info = intelInfo(p)
                local status = info.status or {}
                local team = infoTeam(info)
                local color = teamColor(team)
                local o = ESP.ensure(p)

                o.hl.Adornee = char
                o.hl.FillColor = color
                o.hl.OutlineColor = color
                o.hl.FillTransparency = (status.downed and blink) and 0.25 or 0.65
                o.hl.Enabled = S.espHighlight

                local lines = {}
                if S.espRoles and team then
                    lines[#lines + 1] = string.format('<font color="%s" size="11">%s TEAM</font>', hex(color), team)
                end
                if S.espNames then
                    local name = esc(p.DisplayName)
                    if info.disguise then
                        name = esc(info.disguise) .. ' <font size="11">(@' .. esc(p.Name) .. ")</font>"
                    end
                    lines[#lines + 1] = name
                end
                if S.espRoles and info.role then
                    local mark = ""
                    if info.confidence == "likely" then
                        mark = "?"
                    elseif info.confidence == "suspect" then
                        mark = "??"
                    end
                    lines[#lines + 1] = string.format('<font color="%s">[%s%s]</font>', hex(color), esc(string.upper(info.role)), mark)
                end
                local extra = {}
                if S.espStatus then
                    for _, tag in ipairs(ESP.statusTags(status)) do
                        extra[#extra + 1] = tag
                    end
                end
                if S.espDistance and origin then
                    extra[#extra + 1] = string.format("%dm", math.floor((root.Position - origin).Magnitude))
                end
                if S.espHealth then
                    extra[#extra + 1] = string.format("%dHP", math.floor(hum.Health))
                end
                if #extra > 0 then
                    lines[#lines + 1] = '<font size="11">' .. table.concat(extra, "  ") .. "</font>"
                end

                o.bb.Adornee = head or root
                o.bb.Enabled = #lines > 0
                o.tx.Text = table.concat(lines, "\n")
                o.tx.TextColor3 = (info.role or team) and color or Color3.new(1, 1, 1)
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
local World = { saved = nil, origHold = setmetatable({}, { __mode = "k" }) }

function World.refreshLighting()
    if S.fullbright or S.noFog then
        if not World.saved then
            World.saved = {
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd,
                GlobalShadows = Lighting.GlobalShadows,
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
            }
        end
    elseif World.saved then
        for k, v in pairs(World.saved) do
            Lighting[k] = v
        end
        World.saved = nil
    end
end

function World.lightStep()
    if S.fullbright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    end
    if S.noFog then
        Lighting.FogEnd = 1e6
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
        notify("Spectate", player.DisplayName .. " has no character", nil, 2)
    end
end

function View.teleportTo(player)
    local me, them = getRoot(LocalPlayer), getRoot(player)
    if me and them then
        me.CFrame = them.CFrame * CFrame.new(0, 0, 3)
    else
        notify("Teleport", "Target is not available", nil, 2)
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
-- Tabs
----------------------------------------------------------------------
local Pages = {
    esp = UI.tab("ESP"),
    roles = UI.tab("Roles"),
    deception = UI.tab("Deception"),
    teleport = UI.tab("Teleport"),
    player = UI.tab("Player"),
    players = UI.tab("Players"),
    world = UI.tab("World"),
    dev = UI.tab("Dev Tools"),
    settings = UI.tab("Settings"),
}

-- ESP ---------------------------------------------------------------
UI.section(Pages.esp, "Player ESP")
UI.toggle(Pages.esp, "Enable ESP", S.esp, function(v)
    S.esp = v
    if not v then
        ESP.clear()
    end
end)
UI.toggle(Pages.esp, "Highlight (team color)", S.espHighlight, function(v)
    S.espHighlight = v
end)
UI.toggle(Pages.esp, "Name (+ real name behind disguise)", S.espNames, function(v)
    S.espNames = v
end)
UI.toggle(Pages.esp, "Team + role tag", S.espRoles, function(v)
    S.espRoles = v
end)
UI.toggle(Pages.esp, "Status (downed, detained, silenced, locker)", S.espStatus, function(v)
    S.espStatus = v
end)
UI.toggle(Pages.esp, "Distance", S.espDistance, function(v)
    S.espDistance = v
end)
UI.toggle(Pages.esp, "Health", S.espHealth, function(v)
    S.espHealth = v
end)
UI.label(Pages.esp, '<font color="#FF4040">Merah = Evil</font>, <font color="#FFC440">emas = Veil</font>, <font color="#50E678">hijau = Town</font>, putih = belum ketahuan. "?" = kemungkinan, "??" = curiga. Pemain DOWNED berkedip.')

-- Roles -------------------------------------------------------------
UI.section(Pages.roles, "You")
local selfRoleLabel = UI.label(Pages.roles, "Your role: scanning...")
local configLabel = UI.label(Pages.roles, "Game config: checking...")
UI.section(Pages.roles, "Detection")
UI.toggle(Pages.roles, "Notify when a role is found", S.notifyRoles, function(v)
    S.notifyRoles = v
end)
UI.toggle(Pages.roles, "Alert when someone votes for you", S.voteAlert, function(v)
    S.voteAlert = v
end)
UI.button(Pages.roles, "Reset round evidence", function()
    pcall(Intel.reset, "manual")
    notify("Roles", "Evidence cleared", nil, 2)
end)
UI.section(Pages.roles, "Known roles")
local knownFeed = UI.feed(Pages.roles, 16)
UI.section(Pages.roles, "Kill feed + evidence")
local evidenceFeed = UI.feed(Pages.roles, 12)
UI.label(Pages.roles, "Role orang lain disimpulkan dari bukti: tusukan / tembakan malam (Mafia), tembakan siang (Vigilante), silence (Witch), kunci pintu / banana (Saboteur), buka pintu / bersih-bersih (Janitor), heal (Doctor), tebakan Harbinger, tag tim, dan pengumuman kematian.")

-- Deception ----------------------------------------------------------
UI.section(Pages.deception, "Your body")
local crawlToggle
crawlToggle = UI.toggle(Pages.deception, "Fake crawl", false, function(v)
    local ok, msg = Actions.setFakeCrawl(v)
    if v and not ok then
        crawlToggle.Set(false, true)
    end
    report("Fake crawl", ok, msg)
end, { bind = true })
UI.toggle(Pages.deception, "Keep extra speed while crawling", S.crawlKeepSpeed, function(v)
    S.crawlKeepSpeed = v
end)
UI.button(Pages.deception, "Fake stab", function()
    report("Fake stab", Actions.fakeStab())
end, { bind = true })
UI.button(Pages.deception, "Fake gunshot", function()
    report("Fake gunshot", Actions.fakeShot())
end, { bind = true })
local ghostToggle
ghostToggle = UI.toggle(Pages.deception, "Ghost (others see you under the map)", false, function(v)
    local ok, msg = Actions.setGhost(v)
    if v and not ok then
        ghostToggle.Set(false, true)
    end
    report("Ghost", ok, msg)
end, { bind = true })
UI.slider(Pages.deception, "Ghost depth (studs)", 20, 120, S.ghostDepth, function(v)
    S.ghostDepth = v
end)
UI.label(Pages.deception, "Fake crawl / stab / gunshot memutar animasi game di karakter kamu, dan animasi itu terlihat pemain lain. Ghost: kamu nggak bisa tusuk, heal, interact, atau pakai ability selama aktif.")

-- Teleport -----------------------------------------------------------
UI.section(Pages.teleport, "Target")
local function targetLabel(p)
    if not p then
        return "None"
    end
    return p.DisplayName .. " (@" .. p.Name .. ")"
end
local targetDropdown = UI.dropdown(Pages.teleport, "Target", function()
    local options = {}
    local ok, list = pcall(Actions.livingPlayers)
    if ok and type(list) == "table" then
        for _, p in ipairs(list) do
            local info = intelInfo(p)
            options[#options + 1] = { label = targetLabel(p), value = p, color = teamColor(infoTeam(info)) }
        end
    end
    return options
end, function(p)
    Actions.setTarget(p)
end)
UI.button(Pages.teleport, "To target", function()
    report("Teleport", Actions.toTarget())
end)
UI.button(Pages.teleport, "To downed", function()
    report("Teleport", Actions.toDowned())
end)
UI.button(Pages.teleport, "To detained", function()
    report("Teleport", Actions.toDetained())
end)
UI.section(Pages.teleport, "Mafia")
UI.button(Pages.teleport, "Teleport-Stab-Return", function()
    report("Teleport-Stab-Return", Actions.tpStabReturn())
end, { bind = true })
UI.slider(Pages.teleport, "Time at target before return (s)", 0.15, 1.5, S.tsrHold, function(v)
    S.tsrHold = v
end, 2)
local bringToggle
bringToggle = UI.toggle(Pages.teleport, "Bring target (only you see them move)", false, function(v)
    local ok, msg = Actions.setBring(v)
    if v and not ok then
        bringToggle.Set(false, true)
    end
    report("Bring target", ok, msg)
end, { bind = true })
UI.section(Pages.teleport, "Doctor")
UI.button(Pages.teleport, "Teleport-Heal-Return", function()
    report("Teleport-Heal-Return", Actions.tpHealReturn())
end, { bind = true })

-- Player -------------------------------------------------------------
UI.section(Pages.player, "Movement")
UI.toggle(Pages.player, "Walk speed", false, function(v)
    local hum = getHum(LocalPlayer)
    if v then
        Move.baseSpeed = hum and hum.WalkSpeed or 16
    elseif hum then
        hum.WalkSpeed = Move.baseSpeed
    end
    S.speedOn = v
end)
UI.slider(Pages.player, "Speed value", 16, 150, S.speed, function(v)
    S.speed = v
end)
UI.toggle(Pages.player, "Jump power", false, function(v)
    local hum = getHum(LocalPlayer)
    if v then
        Move.baseJump = hum and hum.JumpPower or 50
    elseif hum then
        hum.JumpPower = Move.baseJump
    end
    S.jumpOn = v
end)
UI.slider(Pages.player, "Jump value", 50, 250, S.jump, function(v)
    S.jump = v
end)
UI.toggle(Pages.player, "Infinite jump", false, function(v)
    S.infJump = v
end)
UI.toggle(Pages.player, "Noclip", false, function(v)
    S.noclip = v
end, { bind = true })
UI.section(Pages.player, "Fly (W A S D, Space naik, Ctrl turun)")
UI.toggle(Pages.player, "Fly", false, function(v)
    S.fly = v
    if not v then
        Move.stopFly()
    end
end, { bind = true })
UI.slider(Pages.player, "Fly speed", 20, 200, S.flySpeed, function(v)
    S.flySpeed = v
end)
UI.section(Pages.player, "Camera")
UI.toggle(Pages.player, "Custom FOV", false, function(v)
    local cam = getCamera()
    if v then
        Move.baseFov = cam and cam.FieldOfView or 70
    elseif cam then
        cam.FieldOfView = Move.baseFov
    end
    S.fovOn = v
end)
UI.slider(Pages.player, "FOV value", 40, 120, S.fov, function(v)
    S.fov = v
end)

-- Players ------------------------------------------------------------
UI.section(Pages.players, "Player list")
local listHolder = new("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    LayoutOrder = UI.nextOrder(Pages.players),
}, Pages.players)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listHolder)
UI.button(Pages.players, "Stop spectating", View.stop)

local PlayerRows = {}

local function smallButton(text, x, parent)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(44, 22),
        Position = UDim2.new(1, x, 0.5, -11),
        BackgroundColor3 = Theme.Off,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
        TextColor3 = Theme.Text,
        Text = text,
        AutoButtonColor = false,
    }, parent)
    corner(b, 5)
    return b
end

function PlayerRows.add(p)
    if PlayerRows[p] then
        return
    end
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Theme.Elem,
        BorderSizePixel = 0,
        LayoutOrder = #listHolder:GetChildren(),
    }, listHolder)
    corner(row, 6)
    local nameLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(0.38, -8, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = p.DisplayName,
    }, row)
    local roleLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0.38, 0, 0, 0),
        Size = UDim2.new(0.62, -150, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = UNKNOWN_COLOR,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = "?",
    }, row)
    local tgt = smallButton("Tgt", -146, row)
    local tp = smallButton("TP", -98, row)
    local vw = smallButton("View", -50, row)
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
    PlayerRows[p] = { row = row, role = roleLabel, name = nameLabel }
end

function PlayerRows.remove(p)
    local r = PlayerRows[p]
    if r then
        r.row:Destroy()
        PlayerRows[p] = nil
    end
end

-- World --------------------------------------------------------------
UI.section(Pages.world, "Lighting")
UI.toggle(Pages.world, "Fullbright", false, function(v)
    S.fullbright = v
    World.refreshLighting()
end)
UI.toggle(Pages.world, "No fog", false, function(v)
    S.noFog = v
    World.refreshLighting()
end)
UI.section(Pages.world, "Interaction")
UI.toggle(Pages.world, "Instant interact (hold = 0)", false, function(v)
    S.instantInteract = v
    if not v then
        World.restorePrompts()
    end
end)
UI.section(Pages.world, "Utility")
UI.toggle(Pages.world, "Anti AFK", S.antiAfk, function(v)
    S.antiAfk = v
end)

-- Dev tools ----------------------------------------------------------
UI.label(Pages.dev, "Buat kalibrasi yang lengkap, jalankan NoctisENIX Inspector (file terpisah, lihat README). Tombol di bawah versi ringkasnya.")
UI.section(Pages.dev, "Scanner")
UI.button(Pages.dev, "Scan remotes", Dev.scanRemotes)
UI.button(Pages.dev, "Dump all players (attributes, tools, intel)", Dev.dumpAllPlayers)
UI.section(Pages.dev, "Remote logger")
UI.label(Pages.dev, "Log FireServer / InvokeServer yang kamu picu sendiri (butuh hookmetamethod).")
UI.toggle(Pages.dev, "Log remote calls", false, function(v)
    if v and not Dev.installLogger() then
        notify("Remote logger", "Executor ini nggak support hookmetamethod", nil, 4)
        LogState.enabled = false
        return
    end
    LogState.enabled = v
    S.logRemotes = v
end)
UI.button(Pages.dev, "Copy remote log", function()
    local text = table.concat(LogState.lines, "\n")
    if text == "" then
        notify("Remote logger", "Log masih kosong", nil, 2)
        return
    end
    local copied = copyText(text)
    notify("Remote logger", copied and "Copied to clipboard" or "Printed in console (F9)", nil, 3)
end)

-- Settings -----------------------------------------------------------
UI.section(Pages.settings, "Menu")
local gameStatus = UI.label(Pages.settings, "Checking game...")
local menuBind = { key = Config.ToggleKey }
do
    local row = UI.row(Pages.settings, 30)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -90, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "Menu toggle key",
    }, row)
    UI.keyButton(row, UDim2.new(1, -66, 0.5, -10), menuBind)
end
UI.section(Pages.settings, "Session")
UI.button(Pages.settings, "Rejoin server", function()
    pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end)

local Unload
UI.button(Pages.settings, "Unload NoctisENIX", function()
    Unload()
end)

----------------------------------------------------------------------
-- Refresh UI berkala
----------------------------------------------------------------------
local function refreshUi()
    for p, r in pairs(PlayerRows) do
        if type(r) == "table" and r.role then
            local info = intelInfo(p)
            local team = infoTeam(info)
            local text = info.role or (team and (team .. " team")) or "?"
            if info.role and info.confidence and info.confidence ~= "confirmed" then
                text = text .. "?"
            end
            r.role.Text = text
            r.role.TextColor3 = teamColor(team)
            r.name.Text = info.disguise and (info.disguise .. " (@" .. p.Name .. ")") or p.DisplayName
        end
    end

    local okSelf, role, team = pcall(Intel.self)
    if not okSelf then
        role, team = nil, nil
    end
    team = team or (role and Game.teamOf(role))
    selfRoleLabel.Text = "Your role: " .. (role or "unknown") .. (team and ("  (" .. team .. ")") or "")
    selfRoleLabel.TextColor3 = teamColor(team)

    local known = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local info = intelInfo(p)
            local t = infoTeam(info)
            if info.role or t then
                local line = p.DisplayName .. ": " .. (info.role or "?") .. (t and (" [" .. t .. "]") or "")
                if info.confidence then
                    line = line .. " - " .. info.confidence
                end
                if info.reason then
                    line = line .. " (" .. info.reason .. ")"
                end
                known[#known + 1] = { text = line, color = teamColor(t) }
            end
        end
    end
    if #known == 0 then
        known[1] = { text = "Belum ada yang ketahuan. Bukti muncul saat ada aksi di game." }
    end
    knownFeed.Set(known)

    local okFeed, feed = pcall(Intel.feed)
    local items = {}
    if okFeed and type(feed) == "table" then
        for i = #feed, math.max(1, #feed - 11), -1 do
            local e = feed[i]
            items[#items + 1] = { text = string.format("%ds ago  %s", math.floor(os.clock() - (e.t or os.clock())), tostring(e.text)) }
        end
    end
    evidenceFeed.Set(items)

    local okT, target = pcall(Actions.getTarget)
    if okT then
        targetDropdown.SetLabel(targetLabel(target))
    end
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

local acc = { intel = 0, esp = 0, ui = 0 }
connect(RunService.Heartbeat, function(dt)
    if not S.alive then
        return
    end
    safeOnce(Move.frameStep)
    safeOnce(World.lightStep)

    acc.intel = acc.intel + dt
    if acc.intel >= 0.25 then
        acc.intel = 0
        safeOnce(Intel.step)
    end
    acc.esp = acc.esp + dt
    if acc.esp >= 0.1 then
        acc.esp = 0
        safeOnce(ESP.step)
    end
    acc.ui = acc.ui + dt
    if acc.ui >= 0.5 then
        acc.ui = 0
        safeOnce(refreshUi)
    end
end)

connect(closeBtn.MouseButton1Click, function()
    main.Visible = false
    notify("NoctisENIX", "Menu hidden. Tekan " .. (menuBind.key and menuBind.key.Name or "menu key") .. " buat buka lagi.", nil, 3)
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
        main.Visible = not main.Visible
        return
    end
    for _, bind in ipairs(UI.binds) do
        if bind.key and bind.key == input.KeyCode then
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

genv.NoctisENIX = { Version = Config.Version, Unload = Unload, Intel = Intel, Actions = Actions, Game = Game }

UI.selectTab(UI.tabs[1])

task.spawn(function()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    local name = (ok and info and info.Name) or "unknown"
    if string.find(string.lower(name), "mafia", 1, true) then
        gameStatus.Text = "Game: " .. esc(name) .. "  (OK)"
        gameStatus.TextColor3 = GOOD_COLOR
    else
        gameStatus.Text = "Game: " .. esc(name) .. "  (bukan MAFIA? fitur umum tetap jalan)"
        gameStatus.TextColor3 = Color3.fromRGB(255, 190, 80)
    end
end)

task.spawn(function()
    local caps = Game.caps or {}
    local okRoles = pcall(Game.roles, true)
    local fromConfig = okRoles and Game.rolesFromConfig
    configLabel.Text = string.format(
        "Game config: %s | require: %s | identity switch: %s",
        fromConfig and "loaded from game" or "fallback list",
        caps.require and "yes" or "no",
        caps.setthreadidentity and "yes" or "no"
    )
end)

notify("NoctisENIX v" .. Config.Version .. " loaded", Config.ToggleKey.Name .. " = toggle menu", nil, 5)
