--[[
    NoctisENIX
    Game     : MAFIA [V2.3] - ACT II  (Topline Studios Inc)
    Executor : Xeno (juga jalan di executor lain yang punya fungsi dasar)

    Catatan teknis
      * Satu file, tanpa library eksternal, tanpa Drawing API.
      * Semua fungsi khusus executor (gethui, cloneref, setclipboard,
        hookmetamethod, dst) dicek dulu dan dibungkus pcall, jadi kalau
        Xeno tidak punya salah satunya, fiturnya saja yang mati.
      * Menjalankan ulang script akan meng-unload instance lama otomatis.

    Cara pakai
      loadstring(game:HttpGet("<RAW_URL_FILE_INI>"))()
      RightShift = buka / tutup menu (bisa diganti di tab Settings)
]]

local genv = (getgenv and getgenv()) or _G

if genv.NoctisENIX and type(genv.NoctisENIX.Unload) == "function" then
    pcall(genv.NoctisENIX.Unload)
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

----------------------------------------------------------------------
-- Config (boleh diedit)
----------------------------------------------------------------------
local Config = {
    Name = "NoctisENIX",
    Version = "1.0.0",
    ToggleKey = Enum.KeyCode.RightShift,

    -- Urutan penting: role paling atas dicek duluan.
    -- Tambahin kata kunci baru di "words" kalau nama tool / role di map beda.
    Roles = {
        {
            name = "Mafia",
            color = Color3.fromRGB(255, 64, 64),
            words = { "mafia", "godfather", "murder", "killer", "assassin", "knife", "dagger", "blade", "shiv", "machete", "cleaver" },
        },
        {
            name = "Detective",
            color = Color3.fromRGB(70, 140, 255),
            words = { "detective", "sheriff", "marshal", "police", "gun", "revolver", "pistol", "rifle", "investigat" },
        },
        {
            name = "Doctor",
            color = Color3.fromRGB(80, 230, 140),
            words = { "doctor", "medic", "nurse", "healer", "syringe", "medkit" },
        },
    },

    -- Nama Attribute / ValueObject yang dianggap menyimpan role.
    RoleAttributes = { "Role", "role", "ROLE", "PlayerRole", "GameRole", "Class", "Team" },
    RoleValues = { "Role", "PlayerRole", "GameRole", "Class" },
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

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

local function warnf(...)
    warn("[" .. Config.Name .. "]", ...)
end

-- Penampung koneksi / instance supaya Unload bisa bersih total.
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
-- State
----------------------------------------------------------------------
local S = {
    alive = true,

    esp = false,
    espHighlight = true,
    espNames = true,
    espDistance = true,
    espHealth = true,
    latch = true,
    notifyRoles = true,

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

    fullbright = false,
    noFog = false,
    instantInteract = false,
    antiAfk = true,

    logRemotes = false,
}

----------------------------------------------------------------------
-- Role detection
----------------------------------------------------------------------
local RoleCache = {} -- [Player] = { role = string, src = string }
local Memory = {}    -- [Player] = { role = string, src = string }
local Announced = {} -- [Player] = role

local function roleFromText(text)
    local lowered = string.lower(tostring(text))
    for _, entry in ipairs(Config.Roles) do
        for _, word in ipairs(entry.words) do
            if string.find(lowered, word, 1, true) then
                return entry.name
            end
        end
    end
    return nil
end

local function isKnownRole(name)
    for _, entry in ipairs(Config.Roles) do
        if entry.name == name then
            return true
        end
    end
    return false
end

local NEUTRAL_COLOR = Color3.fromRGB(190, 255, 205)
local UNKNOWN_COLOR = Color3.fromRGB(200, 200, 210)

local function roleColor(name)
    for _, entry in ipairs(Config.Roles) do
        if entry.name == name then
            return entry.color
        end
    end
    local lowered = string.lower(tostring(name))
    if string.find(lowered, "civil", 1, true) or string.find(lowered, "innocent", 1, true) or string.find(lowered, "town", 1, true) then
        return NEUTRAL_COLOR
    end
    return UNKNOWN_COLOR
end

local function scanTools(container)
    if not container then
        return nil
    end
    for _, item in ipairs(container:GetChildren()) do
        if item:IsA("Tool") or item:IsA("HopperBin") then
            local r = roleFromText(item.Name)
            if r then
                return r, "tool " .. item.Name
            end
        end
    end
    return nil
end

-- Balikin (role, sumber). role bisa nil kalau nggak ada sinyal sama sekali.
local function detectRole(player)
    local char = player.Character
    local raw, rawSrc

    for _, key in ipairs(Config.RoleAttributes) do
        local v = player:GetAttribute(key)
        if v == nil and char then
            v = char:GetAttribute(key)
        end
        if v ~= nil then
            local r = roleFromText(v)
            if r then
                return r, "attribute " .. key
            end
            if not raw then
                raw = tostring(v)
                rawSrc = "attribute " .. key
            end
        end
    end

    local holders = { player }
    if char then
        holders[2] = char
    end
    for _, holder in ipairs(holders) do
        for _, key in ipairs(Config.RoleValues) do
            local obj = holder:FindFirstChild(key)
            if obj and obj:IsA("ValueBase") then
                local r = roleFromText(obj.Value)
                if r then
                    return r, "value " .. key
                end
                if not raw then
                    raw = tostring(obj.Value)
                    rawSrc = "value " .. key
                end
            end
        end
    end

    local team = player.Team
    if team then
        local r = roleFromText(team.Name)
        if r then
            return r, "team " .. team.Name
        end
    end

    local r, src = scanTools(char)
    if r then
        return r, src
    end
    r, src = scanTools(player:FindFirstChildOfClass("Backpack"))
    if r then
        return r, src
    end

    if raw and raw ~= "" then
        return string.sub(raw, 1, 16), rawSrc
    end
    return nil, nil
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
    local accent = color or Theme.Accent
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
        Text = string.format('<b>%s</b>\n%s', esc(title), esc(text or "")),
    }, toastHolder)
    corner(label, 8)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, label)
    new("UIStroke", { Color = accent, Thickness = 1.2, Transparency = 0.2 }, label)
    task.delay(duration or 4, function()
        if label and label.Parent then
            label:Destroy()
        end
    end)
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(560, 390),
    Position = UDim2.new(0.5, -280, 0.5, -195),
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

-- Drag
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

local tabBar = new("Frame", {
    Position = UDim2.fromOffset(8, 44),
    Size = UDim2.new(0, 112, 1, -52),
    BackgroundTransparency = 1,
}, main)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)

local content = new("Frame", {
    Position = UDim2.fromOffset(128, 44),
    Size = UDim2.new(1, -136, 1, -52),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
}, main)
corner(content, 8)

local tabs = {}
local orderCounter = setmetatable({}, { __mode = "k" })
local function nextOrder(frame)
    local n = (orderCounter[frame] or 0) + 1
    orderCounter[frame] = n
    return n
end

local function selectTab(target)
    for _, t in ipairs(tabs) do
        local active = t == target
        t.page.Visible = active
        tween(t.button, {
            BackgroundColor3 = active and Theme.Accent or Theme.Elem,
            TextColor3 = active and Color3.new(1, 1, 1) or Theme.Sub,
        })
    end
end

local function createTab(name)
    local button = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Theme.Elem,
        BorderSizePixel = 0,
        Text = name,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextColor3 = Theme.Sub,
        AutoButtonColor = false,
        LayoutOrder = #tabs + 1,
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
    tabs[#tabs + 1] = tab
    connect(button.MouseButton1Click, function()
        selectTab(tab)
    end)
    return page
end

local function addRow(page, height)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Elem,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(page),
    }, page)
    corner(row, 6)
    return row
end

local function addSection(page, text)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = string.upper(text),
        LayoutOrder = nextOrder(page),
    }, page)
end

local function addLabel(page, text)
    local label = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Theme.Sub,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = text,
        LayoutOrder = nextOrder(page),
    }, page)
    return label
end

local function addToggle(page, text, default, callback)
    local row = addRow(page, 30)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -64, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
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
    render()
    return api
end

local function addButton(page, text, callback)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Theme.Elem,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextColor3 = Theme.Text,
        Text = text,
        AutoButtonColor = false,
        LayoutOrder = nextOrder(page),
    }, page)
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
    return btn
end

local function addSlider(page, text, min, max, default, callback, decimals)
    local row = addRow(page, 46)
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

----------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
local ESP = { objs = {} }

local function espEnsure(player)
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
        Size = UDim2.fromOffset(190, 48),
        StudsOffset = Vector3.new(0, 2.8, 0),
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
        TextStrokeTransparency = 0.4,
        TextColor3 = Color3.new(1, 1, 1),
        TextWrapped = true,
    }, o.bb)
    ESP.objs[player] = o
    return o
end

local function espRemove(player)
    local o = ESP.objs[player]
    if o then
        o.hl:Destroy()
        o.bb:Destroy()
        ESP.objs[player] = nil
    end
end

local function espHide(player)
    local o = ESP.objs[player]
    if o then
        o.hl.Enabled = false
        o.hl.Adornee = nil
        o.bb.Enabled = false
        o.bb.Adornee = nil
    end
end

local function espStep()
    local cam = getCamera()
    local myRoot = getRoot(LocalPlayer)
    local origin = (myRoot and myRoot.Position) or (cam and cam.CFrame.Position)

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local char = p.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            local head = char and char:FindFirstChild("Head")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if S.esp and char and root and hum and hum.Health > 0 then
                local info = RoleCache[p]
                local role = info and info.role or "Unknown"
                local color = roleColor(role)
                local o = espEnsure(p)

                o.hl.Adornee = char
                o.hl.FillColor = color
                o.hl.OutlineColor = color
                o.hl.Enabled = S.espHighlight

                local lines = {}
                if S.espNames then
                    lines[#lines + 1] = p.DisplayName .. "  [" .. role .. "]"
                end
                if S.espDistance and origin then
                    lines[#lines + 1] = string.format("%dm", math.floor((root.Position - origin).Magnitude))
                end
                if S.espHealth then
                    lines[#lines + 1] = string.format("%d HP", math.floor(hum.Health))
                end
                o.bb.Adornee = head or root
                o.bb.Enabled = #lines > 0
                o.tx.Text = table.concat(lines, "\n")
                o.tx.TextColor3 = color
            else
                espHide(p)
            end
        end
    end
end

local function espClear()
    for p in pairs(ESP.objs) do
        espRemove(p)
    end
end

----------------------------------------------------------------------
-- Role loop
----------------------------------------------------------------------
local function roleStep()
    for _, p in ipairs(Players:GetPlayers()) do
        local role, src = detectRole(p)
        if role and isKnownRole(role) and S.latch then
            local mem = Memory[p]
            if not mem or mem.role ~= role then
                Memory[p] = { role = role, src = src }
            end
        end

        local shown, shownSrc = role, src
        if not shown and S.latch and Memory[p] then
            shown, shownSrc = Memory[p].role, "memory (" .. Memory[p].src .. ")"
        end
        RoleCache[p] = { role = shown or "Unknown", src = shownSrc or "no signal" }

        if S.notifyRoles and shown and isKnownRole(shown) and Announced[p] ~= shown then
            Announced[p] = shown
            if p == LocalPlayer then
                notify("Your role", shown, roleColor(shown), 5)
            else
                notify("Role detected", p.DisplayName .. " is " .. shown, roleColor(shown), 5)
            end
        end
    end
end

local function clearRoleMemory()
    Memory = {}
    Announced = {}
    RoleCache = {}
end

----------------------------------------------------------------------
-- Movement
----------------------------------------------------------------------
local Move = { baseSpeed = 16, baseJump = 50, bv = nil, bg = nil, baseFov = 70 }

local function stopFly()
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

local function flyStep()
    local root, hum = getRoot(LocalPlayer), getHum(LocalPlayer)
    local cam = getCamera()
    if not (root and hum and cam) then
        return
    end
    if not Move.bv or Move.bv.Parent ~= root then
        stopFly()
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

local function frameStep()
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
        flyStep()
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
local Light = { saved = nil }

local function refreshLighting()
    if S.fullbright or S.noFog then
        if not Light.saved then
            Light.saved = {
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd,
                GlobalShadows = Lighting.GlobalShadows,
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
            }
        end
    elseif Light.saved then
        for k, v in pairs(Light.saved) do
            Lighting[k] = v
        end
        Light.saved = nil
    end
end

local function lightStep()
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

local origHold = setmetatable({}, { __mode = "k" })
if ProximityPromptService then
    connect(ProximityPromptService.PromptShown, function(prompt)
        if S.instantInteract and prompt.HoldDuration > 0 then
            origHold[prompt] = prompt.HoldDuration
            prompt.HoldDuration = 0
        end
    end)
end
local function restorePrompts()
    for prompt, hold in pairs(origHold) do
        if prompt.Parent then
            prompt.HoldDuration = hold
        end
        origHold[prompt] = nil
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
-- Teleport / spectate
----------------------------------------------------------------------
local Viewing = nil

local function unview()
    local cam = getCamera()
    local hum = getHum(LocalPlayer)
    if cam and hum then
        cam.CameraSubject = hum
    end
    Viewing = nil
end

local function view(player)
    local cam = getCamera()
    local hum = getHum(player)
    if cam and hum then
        cam.CameraSubject = hum
        Viewing = player
        notify("Spectate", "Viewing " .. player.DisplayName, nil, 2)
    else
        notify("Spectate", player.DisplayName .. " has no character", nil, 2)
    end
end

local function teleportTo(player)
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
local function serialize(v, depth)
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
            parts[#parts + 1] = "[" .. serialize(k, depth + 1) .. "]=" .. serialize(x, depth + 1)
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

local function scanRemotes()
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

-- State logger disimpan di genv supaya hook cuma kepasang sekali
-- walau script dieksekusi ulang.
local LogState = genv.NoctisENIX_RemoteLog
if not LogState then
    LogState = { enabled = false, lines = {}, hooked = false, unavailable = false }
    genv.NoctisENIX_RemoteLog = LogState
end
LogState.enabled = false

local function pushLog(remote, method, args)
    local parts = {}
    for i = 1, args.n do
        parts[#parts + 1] = serialize(args[i])
    end
    local line = string.format("%s :%s(%s)", serialize(remote), method, table.concat(parts, ", "))
    local lines = LogState.lines
    lines[#lines + 1] = line
    if #lines > 200 then
        table.remove(lines, 1)
    end
    print("[" .. Config.Name .. "] " .. line)
end

local function installLogger()
    if LogState.hooked then
        return true
    end
    if not (hookmetamethod and getnamecallmethod and checkcaller) then
        LogState.unavailable = true
        return false
    end
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

local function dumpPlayer(p)
    local lines = { "== " .. p.Name .. " (" .. p.DisplayName .. ") ==" }
    lines[#lines + 1] = "Team: " .. (p.Team and p.Team.Name or "none")
    local role = RoleCache[p]
    lines[#lines + 1] = "Detected: " .. (role and (role.role .. " via " .. role.src) or "n/a")
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
        if c.Name == "leaderstats" or c:IsA("Backpack") then
            for _, g in ipairs(c:GetChildren()) do
                local val = g:IsA("ValueBase") and (" = " .. tostring(g.Value)) or ""
                lines[#lines + 1] = "   " .. g.ClassName .. " " .. g.Name .. val
            end
        end
    end
    return table.concat(lines, "\n")
end

local function dumpAllPlayers()
    local blocks = {}
    for _, p in ipairs(Players:GetPlayers()) do
        blocks[#blocks + 1] = dumpPlayer(p)
    end
    local text = table.concat(blocks, "\n\n")
    print("[" .. Config.Name .. "]\n" .. text)
    local copied = copyText(text)
    notify("Player dump", copied and "Copied to clipboard" or "Printed to console (F9)", nil, 4)
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
local pageEsp = createTab("ESP")
local pagePlayer = createTab("Player")
local pagePlayers = createTab("Players")
local pageWorld = createTab("World")
local pageTools = createTab("Dev Tools")
local pageSettings = createTab("Settings")

-- ESP
addSection(pageEsp, "Role ESP")
local selfRoleLabel = addLabel(pageEsp, "Your role: scanning...")
addToggle(pageEsp, "Enable ESP", S.esp, function(v)
    S.esp = v
    if not v then
        espClear()
    end
end)
addToggle(pageEsp, "Highlight (outline + fill)", S.espHighlight, function(v)
    S.espHighlight = v
end)
addToggle(pageEsp, "Name + role tag", S.espNames, function(v)
    S.espNames = v
end)
addToggle(pageEsp, "Distance", S.espDistance, function(v)
    S.espDistance = v
end)
addToggle(pageEsp, "Health", S.espHealth, function(v)
    S.espHealth = v
end)
addSection(pageEsp, "Role intel")
addToggle(pageEsp, "Remember roles (latch)", S.latch, function(v)
    S.latch = v
end)
addToggle(pageEsp, "Notify on role detected", S.notifyRoles, function(v)
    S.notifyRoles = v
end)
addButton(pageEsp, "Clear role memory", function()
    clearRoleMemory()
    notify("Roles", "Memory cleared", nil, 2)
end)
addLabel(pageEsp, "Red = Mafia, Blue = Detective, Green = Doctor, grey = no signal. Role pemain lain cuma kebaca kalau tool-nya lagi dipegang atau game menyimpan role di Attribute / Value / Team.")

-- Player
addSection(pagePlayer, "Movement")
local speedToggle = addToggle(pagePlayer, "Walk speed", false, function(v)
    if v then
        local hum = getHum(LocalPlayer)
        Move.baseSpeed = hum and hum.WalkSpeed or 16
    else
        local hum = getHum(LocalPlayer)
        if hum then
            hum.WalkSpeed = Move.baseSpeed
        end
    end
    S.speedOn = v
end)
addSlider(pagePlayer, "Speed value", 16, 150, S.speed, function(v)
    S.speed = v
end)
addToggle(pagePlayer, "Jump power", false, function(v)
    if v then
        local hum = getHum(LocalPlayer)
        Move.baseJump = hum and hum.JumpPower or 50
    else
        local hum = getHum(LocalPlayer)
        if hum then
            hum.JumpPower = Move.baseJump
        end
    end
    S.jumpOn = v
end)
addSlider(pagePlayer, "Jump value", 50, 250, S.jump, function(v)
    S.jump = v
end)
addToggle(pagePlayer, "Infinite jump", false, function(v)
    S.infJump = v
end)
addToggle(pagePlayer, "Noclip", false, function(v)
    S.noclip = v
end)
addSection(pagePlayer, "Fly (W A S D, Space naik, Ctrl turun)")
addToggle(pagePlayer, "Fly", false, function(v)
    S.fly = v
    if not v then
        stopFly()
    end
end)
addSlider(pagePlayer, "Fly speed", 20, 200, S.flySpeed, function(v)
    S.flySpeed = v
end)
addSection(pagePlayer, "Camera")
addToggle(pagePlayer, "Custom FOV", false, function(v)
    if v then
        local cam = getCamera()
        Move.baseFov = cam and cam.FieldOfView or 70
    else
        local cam = getCamera()
        if cam then
            cam.FieldOfView = Move.baseFov
        end
    end
    S.fovOn = v
end)
addSlider(pagePlayer, "FOV value", 40, 120, S.fov, function(v)
    S.fov = v
end)

-- Players
addSection(pagePlayers, "Player list")
local listHolder = new("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    LayoutOrder = nextOrder(pagePlayers),
}, pagePlayers)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listHolder)
addButton(pagePlayers, "Stop spectating", unview)

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

local function addPlayerRow(p)
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
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(0.4, -8, 1, 0),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = p.DisplayName,
    }, row)
    local roleLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0.4, 0, 0, 0),
        Size = UDim2.new(0.28, 0, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = UNKNOWN_COLOR,
        Text = "Unknown",
    }, row)
    local tp = smallButton("TP", -98, row)
    local vw = smallButton("View", -50, row)
    connect(tp.MouseButton1Click, function()
        teleportTo(p)
    end)
    connect(vw.MouseButton1Click, function()
        view(p)
    end)
    PlayerRows[p] = { row = row, role = roleLabel }
end

local function removePlayerRow(p)
    local r = PlayerRows[p]
    if r then
        r.row:Destroy()
        PlayerRows[p] = nil
    end
end

local function refreshPlayersUi()
    for p, r in pairs(PlayerRows) do
        local info = RoleCache[p]
        local role = info and info.role or "Unknown"
        r.role.Text = role
        r.role.TextColor3 = roleColor(role)
    end
    local mine = RoleCache[LocalPlayer]
    local role = mine and mine.role or "Unknown"
    selfRoleLabel.Text = "Your role: " .. role .. (mine and ("   (" .. mine.src .. ")") or "")
    selfRoleLabel.TextColor3 = roleColor(role)
end

-- World
addSection(pageWorld, "Lighting")
addToggle(pageWorld, "Fullbright", false, function(v)
    S.fullbright = v
    refreshLighting()
end)
addToggle(pageWorld, "No fog", false, function(v)
    S.noFog = v
    refreshLighting()
end)
addSection(pageWorld, "Interaction")
addToggle(pageWorld, "Instant interact (hold = 0)", false, function(v)
    S.instantInteract = v
    if not v then
        restorePrompts()
    end
end)
addSection(pageWorld, "Utility")
addToggle(pageWorld, "Anti AFK", S.antiAfk, function(v)
    S.antiAfk = v
end)

-- Dev tools
addLabel(pageTools, "Alat buat kalibrasi. Jalanin pas lagi di dalam match, lalu kirim hasil copy-nya buat nyempurnain deteksi role atau nambah fitur yang nembak remote game.")
addSection(pageTools, "Scanner")
addButton(pageTools, "Scan remotes", scanRemotes)
addButton(pageTools, "Dump all players (attributes, tools, values)", dumpAllPlayers)
addSection(pageTools, "Remote logger")
local loggerLabel = addLabel(pageTools, "Log FireServer / InvokeServer yang kamu picu sendiri (butuh hookmetamethod).")
addToggle(pageTools, "Log remote calls", false, function(v)
    if v then
        if not installLogger() then
            notify("Remote logger", "Executor ini nggak support hookmetamethod", nil, 4)
            LogState.enabled = false
            return
        end
    end
    LogState.enabled = v
    S.logRemotes = v
end)
addButton(pageTools, "Copy remote log", function()
    local text = table.concat(LogState.lines, "\n")
    if text == "" then
        notify("Remote logger", "Log masih kosong", nil, 2)
        return
    end
    local copied = copyText(text)
    notify("Remote logger", copied and "Copied to clipboard" or "Printed in console (F9)", nil, 3)
end)

-- Settings
addSection(pageSettings, "Menu")
local gameStatus = addLabel(pageSettings, "Checking game...")
local keyButton
local rebindConn
local lastRebind = -1
keyButton = addButton(pageSettings, "Toggle key: " .. Config.ToggleKey.Name .. "  (klik buat ganti)", function()
    if rebindConn then
        return
    end
    keyButton.Text = "Press any key..."
    rebindConn = UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            Config.ToggleKey = input.KeyCode
            keyButton.Text = "Toggle key: " .. input.KeyCode.Name .. "  (klik buat ganti)"
            rebindConn:Disconnect()
            rebindConn = nil
            lastRebind = os.clock()
        end
    end)
    track(rebindConn)
end)
addSection(pageSettings, "Session")
addButton(pageSettings, "Rejoin server", function()
    pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end)

local Unload
addButton(pageSettings, "Unload NoctisENIX", function()
    Unload()
end)

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local function hookPlayer(p)
    addPlayerRow(p)
    connect(p.CharacterAdded, function()
        Memory[p] = nil
        Announced[p] = nil
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    hookPlayer(p)
end
connect(Players.PlayerAdded, hookPlayer)
connect(Players.PlayerRemoving, function(p)
    removePlayerRow(p)
    espRemove(p)
    Memory[p] = nil
    Announced[p] = nil
    RoleCache[p] = nil
    if Viewing == p then
        unview()
    end
end)

connect(LocalPlayer.CharacterAdded, function()
    -- Fly dan state fisika dibangun ulang otomatis oleh flyStep.
    Move.bv, Move.bg = nil, nil
    if Viewing then
        Viewing = nil
    end
end)

local acc = { role = 0, esp = 0, ui = 0 }
connect(RunService.Heartbeat, function(dt)
    if not S.alive then
        return
    end
    safeOnce(frameStep)
    safeOnce(lightStep)

    acc.role = acc.role + dt
    if acc.role >= 0.25 then
        acc.role = 0
        safeOnce(roleStep)
    end
    acc.esp = acc.esp + dt
    if acc.esp >= 0.1 then
        acc.esp = 0
        safeOnce(espStep)
    end
    acc.ui = acc.ui + dt
    if acc.ui >= 0.75 then
        acc.ui = 0
        safeOnce(refreshPlayersUi)
    end
end)

connect(closeBtn.MouseButton1Click, function()
    main.Visible = false
    notify("NoctisENIX", "Menu hidden. Tekan " .. Config.ToggleKey.Name .. " buat buka lagi.", nil, 3)
end)

connect(UserInputService.InputBegan, function(input, processed)
    if processed or rebindConn or os.clock() - lastRebind < 0.3 then
        return
    end
    if input.KeyCode == Config.ToggleKey then
        main.Visible = not main.Visible
    end
end)

Unload = function()
    if not S.alive then
        return
    end
    S.alive = false
    LogState.enabled = false

    pcall(stopFly)
    pcall(unview)
    pcall(restorePrompts)
    pcall(function()
        S.fullbright, S.noFog = false, false
        refreshLighting()
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
    pcall(espClear)

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

genv.NoctisENIX = { Version = Config.Version, Unload = Unload }

selectTab(tabs[1])

-- Cek game (cuma peringatan, fitur umum tetap jalan walau nggak cocok).
task.spawn(function()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    local name = (ok and info and info.Name) or "unknown"
    if string.find(string.lower(name), "mafia", 1, true) then
        gameStatus.Text = "Game: " .. name .. "  (OK)"
        gameStatus.TextColor3 = Color3.fromRGB(80, 230, 140)
    else
        gameStatus.Text = "Game: " .. name .. "  (bukan MAFIA? fitur umum tetap jalan, deteksi role mungkin meleset)"
        gameStatus.TextColor3 = Color3.fromRGB(255, 190, 80)
    end
end)

notify("NoctisENIX loaded", Config.ToggleKey.Name .. " = toggle menu", nil, 5)
