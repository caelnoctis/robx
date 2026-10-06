-- NoctisENIX UI library: window, sidebar, cards, toasts, keybinds, cursor fix.
-- Dipanggil sebagai: local UI = (<isi file ini>)(env)
-- env = { screen, cursorGui, connect, track, safe, safeOnce, UserInputService, RunService, TweenService,
--         LocalPlayer, Config, S }
return function(env)
    local UI = {
        tabs = {},
        binds = {},
        capturing = false,
        lastCapture = -1,
        minimized = false,
    }
    local connect, track, safe = env.connect, env.track, env.safe
    local UserInputService, RunService, TweenService = env.UserInputService, env.RunService, env.TweenService
    local S, Config = env.S, env.Config

    local Theme = {
        Bg = Color3.fromRGB(12, 11, 18),
        Side = Color3.fromRGB(16, 14, 25),
        Card = Color3.fromRGB(23, 21, 35),
        CardHover = Color3.fromRGB(30, 27, 46),
        Stroke = Color3.fromRGB(44, 39, 66),
        Accent = Color3.fromRGB(150, 108, 255),
        Accent2 = Color3.fromRGB(96, 165, 255),
        Text = Color3.fromRGB(244, 242, 255),
        Sub = Color3.fromRGB(164, 158, 190),
        Muted = Color3.fromRGB(112, 106, 140),
        Off = Color3.fromRGB(50, 46, 72),
        Chip = Color3.fromRGB(34, 31, 50),
        Good = Color3.fromRGB(88, 222, 150),
        Warn = Color3.fromRGB(255, 186, 78),
        Bad = Color3.fromRGB(255, 92, 104),
    }
    UI.Theme = Theme

    local RISK = {
        ["local"] = { text = "LOCAL ONLY", color = Theme.Good },
        visible = { text = "OTHERS SEE IT", color = Theme.Accent2 },
        server = { text = "SERVER CAN SEE", color = Theme.Warn },
    }

    ------------------------------------------------------------------
    -- Helpers
    ------------------------------------------------------------------
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
    UI.new = new

    local function tween(inst, props, t)
        local info = TweenInfo.new(t or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local ok, tw = pcall(TweenService.Create, TweenService, inst, info, props)
        if ok and tw then
            tw:Play()
        else
            for k, v in pairs(props) do
                pcall(function()
                    inst[k] = v
                end)
            end
        end
    end
    UI.tween = tween

    local function corner(inst, r)
        return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, inst)
    end

    local function stroke(inst, color, thickness, transparency)
        return new("UIStroke", {
            Color = color or Theme.Stroke,
            Thickness = thickness or 1,
            Transparency = transparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, inst)
    end

    local function pad(inst, t, r, b, l)
        return new("UIPadding", {
            PaddingTop = UDim.new(0, t),
            PaddingRight = UDim.new(0, r),
            PaddingBottom = UDim.new(0, b),
            PaddingLeft = UDim.new(0, l),
        }, inst)
    end

    local function accentGradient(inst, rotation)
        return new("UIGradient", {
            Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
            Rotation = rotation or 0,
        }, inst)
    end

    local function text(props, parent)
        props.BackgroundTransparency = props.BackgroundTransparency or 1
        props.Font = props.Font or Enum.Font.Gotham
        props.TextColor3 = props.TextColor3 or Theme.Text
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        props.BorderSizePixel = 0
        return new("TextLabel", props, parent)
    end
    UI.text = text

    local function hex(c)
        return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    UI.hex = hex

    local function esc(s)
        s = tostring(s)
        s = string.gsub(s, "&", "&amp;")
        s = string.gsub(s, "<", "&lt;")
        s = string.gsub(s, ">", "&gt;")
        return s
    end
    UI.esc = esc

    local orderCounter = setmetatable({}, { __mode = "k" })
    function UI.nextOrder(frame)
        local n = (orderCounter[frame] or 0) + 1
        orderCounter[frame] = n
        return n
    end

    local function chip(parent, label, color, order)
        local c = text({
            Name = "Chip",
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.new(0, 0, 0, 18),
            BackgroundTransparency = 0.82,
            BackgroundColor3 = color,
            TextColor3 = color,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            Text = label,
            LayoutOrder = order or 0,
            TextXAlignment = Enum.TextXAlignment.Center,
        }, parent)
        corner(c, 5)
        pad(c, 0, 7, 0, 7)
        return c
    end
    UI.chip = chip

    ------------------------------------------------------------------
    -- Window
    ------------------------------------------------------------------
    local screen = env.screen
    local WIN_W, WIN_H, HEADER_H, SIDE_W = 780, 520, 54, 200

    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.fromOffset(WIN_W, WIN_H),
        Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel = 0,
        Active = true,
    }, screen)
    corner(main, 14)
    stroke(main, Theme.Stroke, 1, 0)
    UI.main = main
    UI.scale = new("UIScale", { Scale = 1 }, main)

    -- Glow halus di atas window.
    local glow = new("Frame", {
        Name = "Glow",
        Size = UDim2.new(1, 0, 0, 160),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.86,
        BorderSizePixel = 0,
        ZIndex = 0,
    }, main)
    corner(glow, 14)
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, glow)

    -- Modal = true bikin mouse kebuka (tidak terkunci di tengah) selama tombol ini terlihat.
    UI.modal = new("TextButton", {
        Name = "MouseUnlock",
        Modal = true,
        BackgroundTransparency = 1,
        Text = "",
        Size = UDim2.fromOffset(1, 1),
    }, main)

    local header = new("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_H),
        BackgroundTransparency = 1,
    }, main)
    new("Frame", {
        Name = "Divider",
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
    }, header)

    local logo = new("Frame", {
        Size = UDim2.fromOffset(32, 32),
        Position = UDim2.fromOffset(16, 11),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, header)
    corner(logo, 9)
    accentGradient(logo, 45)
    text({
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamBlack,
        TextSize = 18,
        Text = "N",
        TextXAlignment = Enum.TextXAlignment.Center,
    }, logo)

    text({
        Position = UDim2.fromOffset(58, 0),
        Size = UDim2.new(0, 150, 1, 0),
        Font = Enum.Font.GothamBlack,
        TextSize = 19,
        RichText = true,
        Text = 'NOCTIS<font color="' .. hex(Theme.Accent) .. '">ENIX</font>',
    }, header)

    local chips = new("Frame", {
        Position = UDim2.fromOffset(196, 0),
        Size = UDim2.new(0, 260, 1, 0),
        BackgroundTransparency = 1,
    }, header)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, chips)
    chip(chips, "MAFIA  ACT II", Theme.Accent, 1)
    chip(chips, "v" .. tostring(Config.Version), Theme.Sub, 2)

    local function headerButton(label, x, hoverColor)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(30, 30),
            Position = UDim2.new(1, x, 0.5, -15),
            BackgroundColor3 = Theme.Card,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 16,
            TextColor3 = Theme.Sub,
            Text = label,
            AutoButtonColor = false,
        }, header)
        corner(b, 8)
        connect(b.MouseEnter, function()
            tween(b, { BackgroundTransparency = 0, TextColor3 = hoverColor or Theme.Text })
        end)
        connect(b.MouseLeave, function()
            tween(b, { BackgroundTransparency = 1, TextColor3 = Theme.Sub })
        end)
        return b
    end
    UI.closeButton = headerButton("X", -44, Theme.Bad)
    UI.closeButton.Name = "Close"
    UI.minButton = headerButton("-", -80, Theme.Text)
    UI.minButton.Name = "Minimize"

    -- Drag lewat header.
    do
        local dragging, dragStart, startPos = false, nil, nil
        connect(header.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = main.Position
            end
        end)
        connect(UserInputService.InputChanged, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- Sidebar
    local sidebar = new("Frame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(0, HEADER_H),
        Size = UDim2.new(0, SIDE_W, 1, -HEADER_H),
        BackgroundColor3 = Theme.Side,
        BorderSizePixel = 0,
    }, main)
    corner(sidebar, 14)
    -- Tutup sudut atas & kanan sidebar biar cuma kiri-bawah yang membulat.
    new("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = Theme.Side, BorderSizePixel = 0 }, sidebar)
    new("Frame", {
        Position = UDim2.new(1, -16, 0, 0),
        Size = UDim2.new(0, 16, 1, 0),
        BackgroundColor3 = Theme.Side,
        BorderSizePixel = 0,
    }, sidebar)
    new("Frame", {
        Position = UDim2.new(1, -1, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
    }, sidebar)
    UI.sidebar = sidebar

    local nav = new("ScrollingFrame", {
        Name = "Nav",
        Position = UDim2.fromOffset(0, 8),
        Size = UDim2.new(1, -1, 1, -84),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, sidebar)
    new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, nav)
    pad(nav, 4, 10, 8, 10)

    -- Profil di bawah sidebar.
    local profile = new("Frame", {
        Name = "Profile",
        Position = UDim2.new(0, 0, 1, -70),
        Size = UDim2.new(1, -1, 0, 70),
        BackgroundTransparency = 1,
    }, sidebar)
    new("Frame", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -28, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
    }, profile)
    local avatar = new("ImageLabel", {
        Position = UDim2.fromOffset(16, 16),
        Size = UDim2.fromOffset(38, 38),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(env.LocalPlayer.UserId) .. "&w=48&h=48",
    }, profile)
    corner(avatar, 19)
    stroke(avatar, Theme.Accent, 1.5, 0.2)
    text({
        Position = UDim2.fromOffset(64, 17),
        Size = UDim2.new(1, -76, 0, 18),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = env.LocalPlayer.DisplayName,
    }, profile)
    text({
        Position = UDim2.fromOffset(64, 35),
        Size = UDim2.new(1, -76, 0, 16),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = "@" .. env.LocalPlayer.Name,
    }, profile)

    local contentArea = new("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(SIDE_W, HEADER_H),
        Size = UDim2.new(1, -SIDE_W, 1, -HEADER_H),
        BackgroundTransparency = 1,
    }, main)
    UI.contentArea = contentArea

    ------------------------------------------------------------------
    -- Navigasi
    ------------------------------------------------------------------
    function UI.group(name)
        return text({
            Name = "Group",
            Size = UDim2.new(1, 0, 0, 26),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.Muted,
            TextYAlignment = Enum.TextYAlignment.Bottom,
            Text = "  " .. string.upper(name),
            LayoutOrder = UI.nextOrder(nav),
        }, nav)
    end

    function UI.selectTab(target)
        for _, t in ipairs(UI.tabs) do
            local active = t == target
            t.page.Visible = active
            tween(t.button, { BackgroundTransparency = active and 0.8 or 1 })
            tween(t.label, { TextColor3 = active and Theme.Text or Theme.Sub })
            t.bar.Visible = active
        end
        UI.current = target
    end

    function UI.tab(name, icon, subtitle)
        local button = new("TextButton", {
            Name = "Nav_" .. name,
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = UI.nextOrder(nav),
        }, nav)
        corner(button, 9)
        local bar = new("Frame", {
            Position = UDim2.new(0, 0, 0.5, -9),
            Size = UDim2.fromOffset(3, 18),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            Visible = false,
        }, button)
        corner(bar, 2)
        accentGradient(bar, 90)
        text({
            Position = UDim2.fromOffset(12, 0),
            Size = UDim2.new(0, 22, 1, 0),
            TextSize = 16,
            Text = icon or "",
            TextXAlignment = Enum.TextXAlignment.Center,
        }, button)
        local label = text({
            Position = UDim2.fromOffset(42, 0),
            Size = UDim2.new(1, -48, 1, 0),
            Font = Enum.Font.GothamMedium,
            TextSize = 14,
            TextColor3 = Theme.Sub,
            Text = name,
        }, button)

        local page = new("Frame", {
            Name = "Page_" .. name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
        }, contentArea)
        text({
            Position = UDim2.fromOffset(26, 16),
            Size = UDim2.new(1, -52, 0, 26),
            Font = Enum.Font.GothamBold,
            TextSize = 22,
            Text = name,
        }, page)
        text({
            Position = UDim2.fromOffset(26, 44),
            Size = UDim2.new(1, -52, 0, 18),
            TextSize = 13,
            TextColor3 = Theme.Sub,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = subtitle or "",
        }, page)
        local scroll = new("ScrollingFrame", {
            Name = "Scroll",
            Position = UDim2.fromOffset(0, 72),
            Size = UDim2.new(1, 0, 1, -72),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollBarImageTransparency = 0.3,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
        }, page)
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
        pad(scroll, 4, 22, 18, 26)

        local tab = { name = name, button = button, page = page, scroll = scroll, label = label, bar = bar }
        UI.tabs[#UI.tabs + 1] = tab
        connect(button.MouseEnter, function()
            if UI.current ~= tab then
                tween(button, { BackgroundTransparency = 0.92 })
            end
        end)
        connect(button.MouseLeave, function()
            if UI.current ~= tab then
                tween(button, { BackgroundTransparency = 1 })
            end
        end)
        connect(button.MouseButton1Click, function()
            UI.selectTab(tab)
        end)
        return scroll
    end

    ------------------------------------------------------------------
    -- Komponen konten
    ------------------------------------------------------------------
    function UI.section(page, label)
        return text({
            Name = "Section",
            Size = UDim2.new(1, 0, 0, 24),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.Accent,
            TextYAlignment = Enum.TextYAlignment.Bottom,
            Text = string.upper(label),
            LayoutOrder = UI.nextOrder(page),
        }, page)
    end

    function UI.note(page, body)
        local card = new("Frame", {
            Name = "Note",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.93,
            BorderSizePixel = 0,
            LayoutOrder = UI.nextOrder(page),
        }, page)
        corner(card, 10)
        stroke(card, Theme.Accent, 1, 0.75)
        pad(card, 10, 14, 10, 14)
        return text({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextSize = 12,
            TextColor3 = Theme.Sub,
            TextWrapped = true,
            RichText = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            Text = body,
        }, card)
    end

    -- Kartu dasar: kiri judul + badge + deskripsi, kanan area kontrol.
    function UI.card(page, title, desc, rightWidth, risk)
        local card = new("Frame", {
            Name = "Card_" .. title,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Card,
            BorderSizePixel = 0,
            LayoutOrder = UI.nextOrder(page),
        }, page)
        corner(card, 10)
        stroke(card, Theme.Stroke, 1, 0.25)
        pad(card, 12, 14, 12, 14)
        connect(card.MouseEnter, function()
            tween(card, { BackgroundColor3 = Theme.CardHover })
        end)
        connect(card.MouseLeave, function()
            tween(card, { BackgroundColor3 = Theme.Card })
        end)

        local left = new("Frame", {
            Name = "Left",
            Size = UDim2.new(1, -(rightWidth or 0), 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, card)
        new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, left)
        -- Tinggi minimum = tinggi kontrol kanan, biar AutomaticSize kartu nggak melingkar.
        new("UISizeConstraint", { MinSize = Vector2.new(0, 30), MaxSize = Vector2.new(math.huge, math.huge) }, left)
        local titleRow = new("Frame", {
            Name = "TitleRow",
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            LayoutOrder = 1,
        }, left)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, titleRow)
        text({
            Name = "Title",
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.new(0, 0, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            Text = title,
            LayoutOrder = 1,
        }, titleRow)
        local r = risk and RISK[risk]
        if r then
            chip(titleRow, r.text, r.color, 2)
        end
        if desc and desc ~= "" then
            text({
                Name = "Desc",
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                TextSize = 12,
                TextColor3 = Theme.Sub,
                TextWrapped = true,
                TextYAlignment = Enum.TextYAlignment.Top,
                Text = desc,
                LayoutOrder = 2,
            }, left)
        end
        local right = new("Frame", {
            Name = "Right",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, rightWidth or 0, 0, 30),
            BackgroundTransparency = 1,
            ZIndex = 3,
        }, card)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, right)
        return card, right, left
    end

    -- Chip keybind. Klik lalu tekan tombol; Escape / Backspace = hapus.
    function UI.keyChip(parent, bind, order)
        local kb = new("TextButton", {
            Name = "Key",
            Size = UDim2.fromOffset(64, 26),
            BackgroundColor3 = Theme.Chip,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.Sub,
            Text = bind.key and bind.key.Name or "NONE",
            AutoButtonColor = false,
            LayoutOrder = order or 1,
            ZIndex = 4,
        }, parent)
        corner(kb, 7)
        stroke(kb, Theme.Stroke, 1, 0)
        connect(kb.MouseButton1Click, function()
            if UI.capturing then
                return
            end
            UI.capturing = true
            kb.Text = "PRESS"
            kb.TextColor3 = Theme.Accent
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
                kb.TextColor3 = bind.key and Theme.Text or Theme.Sub
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

    -- opts = { bind = bool, risk = "local"|"visible"|"server" }
    function UI.toggle(page, title, desc, default, callback, opts)
        local hasBind = opts and opts.bind
        local card, right = UI.card(page, title, desc, hasBind and 124 or 54, opts and opts.risk)
        local hit = new("TextButton", {
            Name = "Toggle",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 2,
        }, card)
        local switch = new("Frame", {
            Name = "Switch",
            Size = UDim2.fromOffset(44, 24),
            BackgroundColor3 = Theme.Off,
            BorderSizePixel = 0,
            LayoutOrder = 2,
            ZIndex = 4,
        }, right)
        corner(switch, 12)
        local grad = accentGradient(switch, 0)
        grad.Enabled = false
        local knob = new("Frame", {
            Size = UDim2.fromOffset(18, 18),
            Position = UDim2.fromOffset(3, 3),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 5,
        }, switch)
        corner(knob, 9)
        local switchHit = new("TextButton", {
            Name = "SwitchHit",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 6,
        }, switch)

        local state = default and true or false
        local api = { card = card }
        local function render()
            grad.Enabled = state
            tween(switch, { BackgroundColor3 = state and Color3.new(1, 1, 1) or Theme.Off })
            tween(knob, { Position = state and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3) })
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
        local function flip()
            api.Set(not state)
        end
        connect(hit.MouseButton1Click, flip)
        connect(switchHit.MouseButton1Click, flip)
        if hasBind then
            api.bind = UI.bind(flip)
            UI.keyChip(right, api.bind, 1)
        end
        render()
        return api
    end

    -- opts = { bind = bool, risk = ..., action = "Run" }
    function UI.button(page, title, desc, callback, opts)
        local hasBind = opts and opts.bind
        local card, right = UI.card(page, title, desc, hasBind and 168 or 96, opts and opts.risk)
        local pill = new("TextButton", {
            Name = "Action",
            Size = UDim2.fromOffset(88, 30),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = Color3.new(1, 1, 1),
            Text = (opts and opts.action) or "Run",
            AutoButtonColor = false,
            LayoutOrder = 2,
            ZIndex = 4,
        }, right)
        corner(pill, 8)
        accentGradient(pill, 0)
        connect(pill.MouseEnter, function()
            tween(pill, { BackgroundTransparency = 0.15 })
        end)
        connect(pill.MouseLeave, function()
            tween(pill, { BackgroundTransparency = 0 })
        end)
        local function fire()
            task.spawn(safe, callback)
        end
        connect(pill.MouseButton1Click, fire)
        local bind
        if hasBind then
            bind = UI.bind(fire)
            UI.keyChip(right, bind, 1)
        end
        return pill, bind, card
    end

    function UI.slider(page, title, desc, min, max, default, callback, decimals)
        local card, right, left = UI.card(page, title, desc, 64, nil)
        local valueChip = text({
            Name = "Value",
            Size = UDim2.fromOffset(56, 24),
            BackgroundTransparency = 0,
            BackgroundColor3 = Theme.Chip,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = Theme.Accent,
            TextXAlignment = Enum.TextXAlignment.Center,
            Text = tostring(default),
            ZIndex = 4,
        }, right)
        corner(valueChip, 6)
        local barHolder = new("Frame", {
            Name = "BarHolder",
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            LayoutOrder = 3,
        }, left)
        local bar = new("Frame", {
            Name = "Bar",
            Position = UDim2.new(0, 0, 0.5, -3),
            Size = UDim2.new(1, 0, 0, 6),
            BackgroundColor3 = Theme.Off,
            BorderSizePixel = 0,
        }, barHolder)
        corner(bar, 3)
        local fill = new("Frame", {
            Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
        }, bar)
        corner(fill, 3)
        accentGradient(fill, 0)
        local knob = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 3,
        }, bar)
        corner(knob, 7)
        local hit = new("TextButton", {
            Name = "SliderHit",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 4,
        }, barHolder)

        local dragging, value = false, default
        local api = {}
        local function apply(v, silent)
            value = v
            local rel = (v - min) / (max - min)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            knob.Position = UDim2.new(rel, 0, 0.5, 0)
            valueChip.Text = tostring(v)
            if callback and not silent then
                callback(v)
            end
        end
        local function round(v)
            if decimals and decimals > 0 then
                return tonumber(string.format("%." .. decimals .. "f", v))
            end
            return math.floor(v + 0.5)
        end
        local function fromX(x)
            local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            local v = round(min + (max - min) * rel)
            if v ~= value then
                apply(v)
            end
        end
        function api.Set(v, silent)
            apply(math.clamp(round(v), min, max), silent)
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
        return api
    end

    -- getOptions() -> { {label=, value=, color=}, ... } (dipanggil tiap dibuka)
    function UI.dropdown(page, title, desc, getOptions, onSelect, opts)
        local card, right = UI.card(page, title, desc, 190, opts and opts.risk)
        local valueBtn = new("TextButton", {
            Name = "Dropdown",
            Size = UDim2.fromOffset(186, 30),
            BackgroundColor3 = Theme.Chip,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "None",
            AutoButtonColor = false,
            ZIndex = 4,
        }, right)
        corner(valueBtn, 8)
        stroke(valueBtn, Theme.Stroke, 1, 0)
        pad(valueBtn, 0, 26, 0, 10)
        text({
            Name = "Arrow",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(1, 6, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            TextSize = 12,
            TextColor3 = Theme.Sub,
            Text = "v",
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 5,
        }, valueBtn)

        local list = new("Frame", {
            Name = "DropdownList",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Side,
            BorderSizePixel = 0,
            Visible = false,
            LayoutOrder = UI.nextOrder(page),
        }, page)
        corner(list, 10)
        stroke(list, Theme.Stroke, 1, 0)
        pad(list, 6, 6, 6, 6)
        new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)

        local api = { list = list, button = valueBtn }
        function api.SetLabel(label)
            valueBtn.Text = tostring(label)
        end
        local function close()
            list.Visible = false
            for _, c in ipairs(list:GetChildren()) do
                if c:IsA("TextButton") then
                    c:Destroy()
                end
            end
        end
        api.Close = close
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
                options = { { label = "Nobody available", empty = true } }
            end
            for i, opt in ipairs(options) do
                local ob = new("TextButton", {
                    Name = "Option",
                    Size = UDim2.new(1, 0, 0, 30),
                    BackgroundColor3 = Theme.Card,
                    BorderSizePixel = 0,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 13,
                    TextColor3 = opt.color or Theme.Text,
                    Text = opt.label,
                    AutoButtonColor = false,
                    LayoutOrder = i,
                }, list)
                corner(ob, 7)
                connect(ob.MouseEnter, function()
                    tween(ob, { BackgroundColor3 = Theme.CardHover })
                end)
                connect(ob.MouseLeave, function()
                    tween(ob, { BackgroundColor3 = Theme.Card })
                end)
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

    -- Kartu berisi baris-baris teks. api.Set({ {text=, color=}, ... })
    function UI.feed(page, title, maxLines, emptyText)
        local card = UI.card(page, title, nil, 0, nil)
        local holder = new("Frame", {
            Name = "Lines",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = 3,
        }, card:FindFirstChild("Left"))
        new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
        local lines = {}
        for i = 1, maxLines do
            lines[i] = text({
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                TextSize = 12,
                TextWrapped = true,
                RichText = true,
                TextColor3 = Theme.Sub,
                Text = "",
                Visible = false,
                LayoutOrder = i,
            }, holder)
        end
        local api = {}
        function api.Set(items)
            if #items == 0 and emptyText then
                items = { { text = emptyText, color = Theme.Muted } }
            end
            for i = 1, maxLines do
                local item, l = items[i], lines[i]
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

    -- Kartu keybind murni (mis. menu key).
    function UI.keyCard(page, title, desc, bind)
        local _, right = UI.card(page, title, desc, 70, nil)
        return UI.keyChip(right, bind, 1)
    end

    ------------------------------------------------------------------
    -- Toast
    ------------------------------------------------------------------
    local toastHolder = new("Frame", {
        Name = "Toasts",
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 310, 1, -24),
        Position = UDim2.new(1, -322, 0, 12),
    }, screen)
    new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
    }, toastHolder)
    UI.toastHolder = toastHolder
    local toastCount = 0

    function UI.notify(title, body_text, color, duration)
        if not S.alive then
            return
        end
        toastCount = toastCount + 1
        local accent = color or Theme.Accent
        local toast = new("CanvasGroup", {
            Name = "Toast",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Card,
            BorderSizePixel = 0,
            GroupTransparency = 1,
            LayoutOrder = toastCount,
        }, toastHolder)
        corner(toast, 10)
        stroke(toast, Theme.Stroke, 1, 0)
        new("Frame", {
            Name = "Bar",
            Size = UDim2.new(0, 4, 1, 0),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
        }, toast)
        local body = new("Frame", {
            Name = "Body",
            Position = UDim2.fromOffset(4, 0),
            Size = UDim2.new(1, -4, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, toast)
        pad(body, 10, 12, 10, 12)
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, body)
        text({
            Name = "Title",
            Size = UDim2.new(1, 0, 0, 16),
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = accent,
            Text = tostring(title),
            LayoutOrder = 1,
        }, body)
        text({
            Name = "Text",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextWrapped = true,
            Text = tostring(body_text or ""),
            LayoutOrder = 2,
        }, body)
        tween(toast, { GroupTransparency = 0 }, 0.2)

        local toasts = {}
        for _, c in ipairs(toastHolder:GetChildren()) do
            if c.Name == "Toast" then
                toasts[#toasts + 1] = c
            end
        end
        if #toasts > 5 then
            table.sort(toasts, function(a, b)
                return a.LayoutOrder < b.LayoutOrder
            end)
            for i = 1, #toasts - 5 do
                toasts[i]:Destroy()
            end
        end
        task.delay(duration or 4, function()
            if toast and toast.Parent then
                tween(toast, { GroupTransparency = 1 }, 0.25)
                task.delay(0.3, function()
                    if toast and toast.Parent then
                        toast:Destroy()
                    end
                end)
            end
        end)
        return toast
    end

    function UI.report(title, ok, msg)
        UI.notify(title, msg or (ok and "Done" or "Failed"), ok and Theme.Good or Theme.Bad, ok and 3 or 4.5)
    end

    ------------------------------------------------------------------
    -- Visibilitas, minimize, dan perbaikan kursor
    ------------------------------------------------------------------
    function UI.setVisible(v)
        main.Visible = v and true or false
    end

    function UI.setMinimized(v)
        UI.minimized = v and true or false
        sidebar.Visible = not UI.minimized
        contentArea.Visible = not UI.minimized
        glow.Visible = not UI.minimized
        tween(main, { Size = UI.minimized and UDim2.fromOffset(WIN_W, HEADER_H) or UDim2.fromOffset(WIN_W, WIN_H) }, 0.2)
    end
    connect(UI.minButton.MouseButton1Click, function()
        UI.setMinimized(not UI.minimized)
    end)

    -- Halo kursor: digambar sendiri, karena game ini menyembunyikan kursor sistem lewat cursorController.
    local cursorGui = env.cursorGui
    local halo = new("Frame", {
        Name = "CursorHalo",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        Visible = false,
    }, cursorGui)
    corner(halo, 10)
    stroke(halo, Theme.Accent, 2, 0.1)
    local dot = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, halo)
    corner(dot, 3)
    UI.halo = halo

    -- v2.2: JANGAN pernah sentuh MouseBehavior. Game membidik stab / tembak lewat posisi kursor
    -- (ScreenPointToRay); dulu waktu menu ditutup kita "memulihkan" MouseBehavior ke nilai lama
    -- (snapshot saat script di-load, sering Default di lobby) sehingga mouse nggak terkunci lagi
    -- dan tombol ability (T / G / R) nggak pernah kena target. Sekarang:
    --   * mouse dilepas cuma lewat tombol Modal (engine yang mengunci lagi dengan benar),
    --   * MouseIconEnabled dipaksa true HANYA saat mouse di atas window, lalu dikembalikan ke
    --     nilai yang dibaca TEPAT sebelum dipaksa (bukan snapshot lama).
    local cursor = { forcing = false, savedIcon = nil }

    local function overWindow(m)
        local p, s = main.AbsolutePosition, main.AbsoluteSize
        return m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y
    end

    local function releaseIcon()
        if cursor.forcing then
            cursor.forcing = false
            local icon = cursor.savedIcon
            cursor.savedIcon = nil
            if icon ~= nil then
                pcall(function()
                    UserInputService.MouseIconEnabled = icon
                end)
            end
        end
    end

    function UI.cursorStep()
        local visible = S.alive and main.Visible
        UI.modal.Visible = visible and S.freeMouse ~= false
        local okM, m = pcall(UserInputService.GetMouseLocation, UserInputService)
        local over = visible and okM and m and overWindow(m) or false
        if over then
            if not cursor.forcing then
                cursor.forcing = true
                cursor.savedIcon = UserInputService.MouseIconEnabled
            end
            if UserInputService.MouseIconEnabled ~= true then
                UserInputService.MouseIconEnabled = true
            end
        else
            releaseIcon()
        end
        halo.Visible = over and S.cursorHalo ~= false
        if halo.Visible then
            halo.Position = UDim2.fromOffset(m.X, m.Y)
        end
    end

    function UI.restoreCursor()
        releaseIcon()
        halo.Visible = false
        UI.modal.Visible = false
    end

    -- BindToRenderStep dengan prioritas paling akhir supaya jalan SETELAH cursorController game.
    local bindName = "NoctisENIX_Cursor_" .. tostring(math.random(1000, 9999))
    local bound = pcall(function()
        RunService:BindToRenderStep(bindName, Enum.RenderPriority.Last.Value + 50, function()
            env.safeOnce(UI.cursorStep)
        end)
    end)
    if bound then
        track(function()
            pcall(function()
                RunService:UnbindFromRenderStep(bindName)
            end)
        end)
    else
        connect(RunService.RenderStepped, function()
            env.safeOnce(UI.cursorStep)
        end)
    end

    return UI
end
