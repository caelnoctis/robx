-- NoctisENIX UI library: window, sidebar, cards, toasts, keybinds, cursor fix.
-- Dipanggil sebagai: local UI = (<isi file ini>)(env)
-- env = { screen, cursorGui, connect, track, safe, safeOnce, UserInputService, RunService, TweenService,
--         LocalPlayer, Config, S }
return function(env)
    local UI = {
        tabs = {},
        binds = {},
        bindsById = {},
        capturing = false,
        lastCapture = -1,
        minimized = false,
    }
    local connect, track, safe = env.connect, env.track, env.safe
    local UserInputService, RunService, TweenService = env.UserInputService, env.RunService, env.TweenService
    local S, Config = env.S, env.Config

    -- Tema "Phantom": merah-hitam-putih ala menu Persona 5 Royal (fan-inspired). Semua bentuk
    -- digambar dari Frame/UIStroke/UIGradient, nggak ada gambar atau aset game.
    local Theme = {
        Bg = Color3.fromRGB(15, 15, 15),
        Side = Color3.fromRGB(23, 6, 7),
        Card = Color3.fromRGB(26, 23, 23),
        CardHover = Color3.fromRGB(42, 17, 18),
        Stroke = Color3.fromRGB(58, 51, 51),
        Accent = Color3.fromRGB(229, 25, 28),
        Accent2 = Color3.fromRGB(30, 203, 225),
        Text = Color3.fromRGB(253, 253, 253),
        Sub = Color3.fromRGB(201, 194, 194),
        Muted = Color3.fromRGB(140, 130, 130),
        Off = Color3.fromRGB(59, 52, 52),
        Chip = Color3.fromRGB(38, 32, 32),
        Good = Color3.fromRGB(59, 227, 160),
        Warn = Color3.fromRGB(242, 193, 78),
        Bad = Color3.fromRGB(255, 51, 70),
        Ink = Color3.fromRGB(0, 0, 0),
        Paper = Color3.fromRGB(253, 253, 253),
        RedDeep = Color3.fromRGB(158, 15, 20),
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

    local function tweenEx(inst, props, t, style, dir)
        local info = TweenInfo.new(t or 0.16, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
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
    UI.tweenEx = tweenEx

    local function tween(inst, props, t)
        tweenEx(inst, props, t)
    end
    UI.tween = tween

    local function stroke(inst, color, thickness, transparency)
        return new("UIStroke", {
            Color = color or Theme.Stroke,
            Thickness = thickness or 1,
            Transparency = transparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, inst)
    end

    -- Garis tegas: sudut tajam (Miter), ciri khas menu P5.
    local function sharp(inst, color, thickness, transparency)
        local st = stroke(inst, color, thickness, transparency)
        st.LineJoinMode = Enum.LineJoinMode.Miter
        return st
    end

    -- Potongan dekorasi: nggak pernah nangkep input, cuma hiasan.
    local function slab(parent, props)
        props.BorderSizePixel = 0
        props.Active = false
        return new("Frame", props, parent)
    end
    UI.slab = slab

    -- Bintang bergerigi: beberapa kotak yang diputar di titik tengah yang sama.
    local function burst(parent, size, pos, colors, z)
        local holder = new("Frame", {
            Name = "Burst",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = pos,
            Size = UDim2.fromOffset(size, size),
            BackgroundTransparency = 1,
            ZIndex = z or 1,
        }, parent)
        for layer, c in ipairs(colors) do
            local s = size - (layer - 1) * 6
            for k = 0, 2 do
                slab(holder, {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(s * 0.72, s * 0.72),
                    Rotation = k * 30 + layer * 7,
                    BackgroundColor3 = c,
                    ZIndex = (z or 1) + layer,
                })
            end
        end
        return holder
    end
    UI.burst = burst

    -- Judul "surat kaleng": tiap huruf kotak sendiri, miring & selang-seling hitam/putih.
    -- Deterministik (seed dari teksnya), jadi tampilannya sama tiap kali di-load.
    local RANSOM_FONTS = {
        Enum.Font.GothamBlack, Enum.Font.Bangers, Enum.Font.GothamBlack, Enum.Font.Oswald,
        Enum.Font.Bodoni, Enum.Font.GothamBlack, Enum.Font.SpecialElite, Enum.Font.RobotoCondensed,
    }
    local function ransom(parent, word, size, pos, z)
        local h = 7
        for i = 1, #word do
            h = (h * 31 + string.byte(word, i)) % 2147483647
        end
        local function rnd()
            h = (h * 1103515245 + 12345) % 2147483648
            return h / 2147483648
        end
        local holder = new("Frame", {
            Name = "Ransom",
            Position = pos,
            Size = UDim2.fromOffset(0, size + 8),
            BackgroundTransparency = 1,
            ZIndex = z or 1,
        }, parent)
        local x, lastInk, run = 0, nil, 0
        for i = 1, #word do
            local ch = string.sub(word, i, i)
            local first = i == 1
            local scale = first and 1.18 or (0.84 + rnd() * 0.16)
            local s = math.floor(size * scale)
            local w = math.floor(s * ((ch == "W" or ch == "M") and 0.95 or (ch == "I" and 0.52 or 0.78)))
            local ink
            if first or (i % 5 == 0) then
                ink = "red"
            else
                ink = rnd() < 0.5 and "black" or "white"
                if ink == lastInk then
                    run = run + 1
                    if run >= 2 then
                        ink = ink == "black" and "white" or "black"
                        run = 0
                    end
                else
                    run = 0
                end
            end
            lastInk = ink
            local bg = ink == "red" and Theme.Accent or (ink == "black" and Theme.Ink or Theme.Paper)
            local fg = ink == "white" and Theme.Ink or Theme.Paper
            local box = new("TextLabel", {
                Name = "Letter",
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, x, 0.5, math.floor((rnd() - 0.5) * 5)),
                Size = UDim2.fromOffset(w, s),
                Rotation = first and -6 or math.floor((rnd() - 0.5) * 18),
                BackgroundColor3 = bg,
                BorderSizePixel = 0,
                Font = first and Enum.Font.GothamBlack or RANSOM_FONTS[1 + math.floor(rnd() * #RANSOM_FONTS)],
                TextSize = math.floor(s * 0.82),
                TextColor3 = fg,
                Text = ch,
                ZIndex = (z or 1) + 1,
            }, holder)
            sharp(box, ink == "white" and Theme.Ink or Theme.Paper, first and 2 or 1.5, 0)
            x = x + w - 1
        end
        holder.Size = UDim2.fromOffset(x, size + 8)
        return holder, x
    end
    UI.ransom = ransom

    local function pad(inst, t, r, b, l)
        return new("UIPadding", {
            PaddingTop = UDim.new(0, t),
            PaddingRight = UDim.new(0, r),
            PaddingBottom = UDim.new(0, b),
            PaddingLeft = UDim.new(0, l),
        }, inst)
    end

    local function text(props, parent)
        props.BackgroundTransparency = props.BackgroundTransparency or 1
        props.Font = props.Font or Enum.Font.GothamMedium
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
            BackgroundTransparency = 0.78,
            BackgroundColor3 = color,
            TextColor3 = color,
            Font = Enum.Font.GothamBlack,
            TextSize = 10,
            Text = label,
            LayoutOrder = order or 0,
            Rotation = -2,
            TextXAlignment = Enum.TextXAlignment.Center,
        }, parent)
        sharp(c, color, 1, 0.45)
        pad(c, 0, 7, 0, 7)
        return c
    end
    UI.chip = chip

    ------------------------------------------------------------------
    -- Window
    ------------------------------------------------------------------
    local screen = env.screen
    local WIN_W, WIN_H, HEADER_H, SIDE_W = 780, 520, 58, 200

    -- Main = wadah transparan (posisi, drag, ukuran). Di dalamnya: bayangan merah, badan hitam,
    -- lalu header / sidebar / konten di ZIndex lebih tinggi (ZIndexBehavior = Sibling).
    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.fromOffset(WIN_W, WIN_H),
        Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = true,
    }, screen)
    UI.main = main
    UI.scale = new("UIScale", { Scale = 1 }, main)

    slab(main, {
        Name = "Shadow",
        Position = UDim2.fromOffset(9, 9),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Accent,
        ZIndex = 0,
    })
    local body = slab(main, {
        Name = "Body",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Bg,
        ZIndex = 1,
    })
    sharp(body, Theme.Paper, 2, 0)

    -- Hiasan latar: garis-garis miring tipis di pojok kanan atas.
    local glow = new("Frame", {
        Name = "Glow",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 2,
    }, main)
    do
        local stripes = slab(glow, {
            Name = "Stripes",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.fromOffset(300, HEADER_H),
            BackgroundColor3 = Theme.Paper,
            BackgroundTransparency = 0.9,
            ZIndex = 2,
        })
        -- 4 garis keras = 16 keypoint (batasnya 20).
        local kp = {}
        for i = 0, 3 do
            local a0 = i / 4
            kp[#kp + 1] = NumberSequenceKeypoint.new(a0, 1)
            kp[#kp + 1] = NumberSequenceKeypoint.new(a0 + 0.12, 1)
            kp[#kp + 1] = NumberSequenceKeypoint.new(a0 + 0.121, 0)
            kp[#kp + 1] = NumberSequenceKeypoint.new(math.min(a0 + 0.2, 1), 0)
        end
        kp[#kp + 1] = NumberSequenceKeypoint.new(1, 0)
        new("UIGradient", { Rotation = -60, Transparency = NumberSequence.new(kp) }, stripes)
    end

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
        ZIndex = 4,
    }, main)
    slab(header, {
        Name = "Divider",
        Position = UDim2.new(0, 0, 1, -4),
        Size = UDim2.new(1, 0, 0, 4),
        BackgroundColor3 = Theme.Accent,
        ZIndex = 4,
    })
    slab(header, {
        Name = "Divider2",
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme.Paper,
        ZIndex = 4,
    })

    -- Slab merah miring di belakang judul (sengaja keluar sedikit dari window).
    slab(header, {
        Name = "TitleSlabBack",
        Position = UDim2.fromOffset(-10, 4),
        Size = UDim2.fromOffset(268, 50),
        Rotation = -3,
        BackgroundColor3 = Theme.Paper,
        ZIndex = 4,
    })
    slab(header, {
        Name = "TitleSlab",
        Position = UDim2.fromOffset(-14, 2),
        Size = UDim2.fromOffset(262, 50),
        Rotation = -3,
        BackgroundColor3 = Theme.Accent,
        ZIndex = 5,
    })

    -- Logo: bintang bergerigi + N.
    local logo = burst(header, 38, UDim2.fromOffset(30, HEADER_H / 2 - 1), { Theme.Paper, Theme.Ink }, 6)
    logo.Name = "Logo"
    text({
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.Bangers,
        TextSize = 22,
        Text = "N",
        Rotation = -8,
        TextColor3 = Theme.Paper,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 10,
    }, logo)

    local title = ransom(header, "NOCTISENIX", 25, UDim2.new(0, 54, 0.5, -19), 7)
    title.Name = "Title"

    local chips = new("Frame", {
        Position = UDim2.fromOffset(268, 0),
        Size = UDim2.new(0, 260, 1, -4),
        BackgroundTransparency = 1,
        ZIndex = 6,
    }, header)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, chips)
    local actTag = text({
        Name = "Tag",
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 0, 20),
        BackgroundTransparency = 0,
        BackgroundColor3 = Theme.Paper,
        TextColor3 = Theme.Ink,
        Font = Enum.Font.GothamBlack,
        TextSize = 11,
        Text = "MAFIA  ACT II",
        Rotation = -4,
        LayoutOrder = 1,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 6,
    }, chips)
    pad(actTag, 0, 8, 0, 8)
    text({
        Name = "Version",
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 0, 20),
        Font = Enum.Font.SpecialElite,
        TextSize = 13,
        TextColor3 = Theme.Sub,
        Text = "v" .. tostring(Config.Version),
        LayoutOrder = 2,
        ZIndex = 6,
    }, chips)

    local function headerButton(label, x, hoverColor)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(30, 30),
            Position = UDim2.new(1, x, 0.5, -17),
            BackgroundColor3 = Theme.Ink,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBlack,
            TextSize = 15,
            TextColor3 = Theme.Paper,
            Text = label,
            AutoButtonColor = false,
            ZIndex = 6,
        }, header)
        local st = sharp(b, Theme.Paper, 2, 0)
        connect(b.MouseEnter, function()
            tweenEx(b, { BackgroundColor3 = hoverColor or Theme.Accent, Rotation = -8 }, 0.12, Enum.EasingStyle.Back)
            st.Color = Theme.Paper
        end)
        connect(b.MouseLeave, function()
            tweenEx(b, { BackgroundColor3 = Theme.Ink, Rotation = 0 }, 0.1)
        end)
        return b
    end
    UI.closeButton = headerButton("X", -46, Theme.Bad)
    UI.closeButton.Name = "Close"
    UI.minButton = headerButton("-", -84, Theme.Accent)
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

    -- Sidebar: hitam kemerahan, garis putih di kanan, serpihan merah samar di bawah.
    local sidebar = new("Frame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(2, HEADER_H + 2),
        Size = UDim2.new(0, SIDE_W - 2, 1, -HEADER_H - 4),
        BackgroundColor3 = Theme.Side,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, main)
    slab(sidebar, {
        Name = "Edge",
        Position = UDim2.new(1, -2, 0, 0),
        Size = UDim2.new(0, 2, 1, 0),
        BackgroundColor3 = Theme.Paper,
        BackgroundTransparency = 0.6,
        ZIndex = 3,
    })
    slab(sidebar, {
        Name = "Shard",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 1, -112),
        Size = UDim2.fromOffset(170, 30),
        Rotation = -18,
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.86,
        ZIndex = 3,
    })
    slab(sidebar, {
        Name = "Shard2",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 14, 1, -92),
        Size = UDim2.fromOffset(120, 4),
        Rotation = -18,
        BackgroundColor3 = Theme.Paper,
        BackgroundTransparency = 0.85,
        ZIndex = 3,
    })
    UI.sidebar = sidebar

    local nav = new("ScrollingFrame", {
        Name = "Nav",
        Position = UDim2.fromOffset(0, 8),
        Size = UDim2.new(1, -2, 1, -84),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 4,
    }, sidebar)
    new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, nav)
    pad(nav, 4, 12, 8, 10)

    -- Profil di bawah sidebar.
    local profile = new("Frame", {
        Name = "Profile",
        Position = UDim2.new(0, 0, 1, -70),
        Size = UDim2.new(1, -2, 0, 70),
        BackgroundTransparency = 1,
        ZIndex = 4,
    }, sidebar)
    slab(profile, {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 0, 2),
        BackgroundColor3 = Theme.Accent,
        ZIndex = 4,
    })
    slab(profile, {
        Position = UDim2.fromOffset(19, 19),
        Size = UDim2.fromOffset(38, 38),
        Rotation = -6,
        BackgroundColor3 = Theme.Accent,
        ZIndex = 4,
    })
    local avatar = new("ImageLabel", {
        Position = UDim2.fromOffset(15, 15),
        Size = UDim2.fromOffset(38, 38),
        Rotation = 3,
        BackgroundColor3 = Theme.Ink,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(env.LocalPlayer.UserId) .. "&w=48&h=48",
        ZIndex = 5,
    }, profile)
    sharp(avatar, Theme.Paper, 2, 0)
    text({
        Position = UDim2.fromOffset(66, 17),
        Size = UDim2.new(1, -78, 0, 18),
        Font = Enum.Font.GothamBlack,
        TextSize = 14,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = env.LocalPlayer.DisplayName,
        ZIndex = 5,
    }, profile)
    text({
        Position = UDim2.fromOffset(66, 35),
        Size = UDim2.new(1, -78, 0, 16),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = "@" .. env.LocalPlayer.Name,
        ZIndex = 5,
    }, profile)

    local contentArea = new("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(SIDE_W, HEADER_H + 2),
        Size = UDim2.new(1, -SIDE_W - 2, 1, -HEADER_H - 4),
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, main)
    UI.contentArea = contentArea

    ------------------------------------------------------------------
    -- Navigasi
    ------------------------------------------------------------------
    function UI.group(name)
        local g = text({
            Name = "Group",
            Size = UDim2.new(1, 0, 0, 28),
            Font = Enum.Font.GothamBlack,
            TextSize = 11,
            TextColor3 = Theme.Accent,
            TextYAlignment = Enum.TextYAlignment.Bottom,
            Text = "  //  " .. string.upper(name),
            LayoutOrder = UI.nextOrder(nav),
        }, nav)
        pad(g, 0, 0, 3, 0)
        return g
    end

    -- Tab aktif: slab putih miring di atas slab merah, teks hitam. Hover: slab hitam.
    function UI.selectTab(target)
        for _, t in ipairs(UI.tabs) do
            local active = t == target
            t.page.Visible = active
            t.bar.Visible = active
            t.hover.Visible = false
            tween(t.label, { TextColor3 = active and Theme.Ink or Theme.Sub })
            t.icon.TextColor3 = active and Theme.Ink or Theme.Text
            t.label.Font = active and Enum.Font.GothamBlack or Enum.Font.GothamBold
            if active then
                t.front.Rotation = -6
                tweenEx(t.front, { Rotation = -2 }, 0.22, Enum.EasingStyle.Back)
                -- Judul halaman masuk dari kanan, menyentak sedikit.
                t.heading.Position = UDim2.fromOffset(t.headingX + 34, t.headingY)
                t.heading.Rotation = -9
                tweenEx(t.heading, { Position = UDim2.fromOffset(t.headingX, t.headingY), Rotation = -3 }, 0.26, Enum.EasingStyle.Back)
            end
        end
        UI.current = target
    end

    function UI.tab(name, icon, subtitle)
        local button = new("TextButton", {
            Name = "Nav_" .. name,
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = UI.nextOrder(nav),
        }, nav)
        local hover = slab(button, {
            Name = "Hover",
            Position = UDim2.fromOffset(2, 3),
            Size = UDim2.new(1, -4, 1, -6),
            BackgroundColor3 = Theme.Ink,
            Visible = false,
        })
        sharp(hover, Theme.Accent, 1, 0.3)
        local bar = new("Frame", {
            Name = "Selected",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
        }, button)
        slab(bar, {
            Name = "Back",
            Position = UDim2.fromOffset(5, 5),
            Size = UDim2.new(1, -4, 1, -6),
            Rotation = -4,
            BackgroundColor3 = Theme.Accent,
        })
        local front = slab(bar, {
            Name = "Front",
            Position = UDim2.fromOffset(0, 2),
            Size = UDim2.new(1, -4, 1, -6),
            Rotation = -2,
            BackgroundColor3 = Theme.Paper,
        })
        -- Ujung cyan kecil: satu-satunya warna dingin, penanda "dipilih".
        slab(bar, {
            Name = "Tip",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, -8, 0.5, -1),
            Size = UDim2.fromOffset(9, 9),
            Rotation = 45,
            BackgroundColor3 = Theme.Accent2,
        })
        local iconLabel = text({
            Position = UDim2.fromOffset(10, 0),
            Size = UDim2.new(0, 22, 1, 0),
            TextSize = 15,
            Text = icon or "",
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 2,
        }, button)
        local label = text({
            Position = UDim2.fromOffset(40, 0),
            Size = UDim2.new(1, -56, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme.Sub,
            Text = string.upper(name),
            ZIndex = 2,
        }, button)

        local page = new("Frame", {
            Name = "Page_" .. name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
        }, contentArea)
        -- Judul halaman: label putih di slab merah miring, bayangan hitam.
        local headingX, headingY = 22, 12
        local heading = new("Frame", {
            Name = "Heading",
            Position = UDim2.fromOffset(headingX, headingY),
            Size = UDim2.fromOffset(0, 34),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Rotation = -3,
        }, page)
        sharp(heading, Theme.Paper, 2, 0)
        pad(heading, 0, 14, 0, 12)
        text({
            Name = "Title",
            Size = UDim2.fromScale(0, 1),
            AutomaticSize = Enum.AutomaticSize.X,
            Font = Enum.Font.GothamBlack,
            TextSize = 22,
            TextColor3 = Theme.Paper,
            Text = string.upper(name),
        }, heading)
        text({
            Name = "Subtitle",
            Position = UDim2.fromOffset(26, 54),
            Size = UDim2.new(1, -52, 0, 18),
            TextSize = 13,
            TextColor3 = Theme.Sub,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = subtitle or "",
        }, page)
        local scroll = new("ScrollingFrame", {
            Name = "Scroll",
            Position = UDim2.fromOffset(0, 80),
            Size = UDim2.new(1, 0, 1, -80),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 5,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollBarImageTransparency = 0,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
        }, page)
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
        pad(scroll, 4, 22, 18, 26)

        local tab = {
            name = name, button = button, page = page, scroll = scroll, label = label, bar = bar,
            hover = hover, front = front, icon = iconLabel, heading = heading, headingX = headingX, headingY = headingY,
        }
        UI.tabs[#UI.tabs + 1] = tab
        connect(button.MouseEnter, function()
            if UI.current ~= tab then
                hover.Visible = true
                hover.Position = UDim2.fromOffset(-10, 3)
                tweenEx(hover, { Position = UDim2.fromOffset(2, 3) }, 0.12, Enum.EasingStyle.Quint)
                tween(label, { TextColor3 = Theme.Text }, 0.1)
            end
        end)
        connect(button.MouseLeave, function()
            hover.Visible = false
            if UI.current ~= tab then
                tween(label, { TextColor3 = Theme.Sub }, 0.1)
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
    -- Header seksi: tag putih miring dengan teks hitam + garis merah sampai ujung kanan.
    function UI.section(page, label)
        local row = new("Frame", {
            Name = "Section",
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
            LayoutOrder = UI.nextOrder(page),
        }, page)
        slab(row, {
            Name = "Rule",
            Position = UDim2.new(0, 0, 1, -7),
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = Theme.Accent,
        })
        local tag = text({
            Name = "Label",
            Position = UDim2.fromOffset(2, 7),
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.new(0, 0, 0, 20),
            BackgroundTransparency = 0,
            BackgroundColor3 = Theme.Paper,
            Font = Enum.Font.GothamBlack,
            TextSize = 12,
            TextColor3 = Theme.Ink,
            Rotation = -3,
            Text = string.upper(label),
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 2,
        }, row)
        pad(tag, 0, 10, 0, 10)
        return tag
    end

    function UI.note(page, body)
        local card = new("Frame", {
            Name = "Note",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Color3.fromRGB(34, 12, 13),
            BorderSizePixel = 0,
            LayoutOrder = UI.nextOrder(page),
        }, page)
        sharp(card, Theme.Accent, 1, 0.5)
        pad(card, 10, 14, 10, 20)
        slab(card, {
            Name = "Bar",
            Position = UDim2.new(0, -20, 0, -10),
            Size = UDim2.new(0, 4, 1, 20),
            BackgroundColor3 = Theme.Accent,
        })
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
        local cardStroke = sharp(card, Theme.Stroke, 1, 0)
        pad(card, 12, 14, 12, 18)
        -- Strip merah di kiri; melebar & stroke memerah waktu hover.
        local strip = slab(card, {
            Name = "Strip",
            Position = UDim2.new(0, -18, 0, -12),
            Size = UDim2.new(0, 3, 1, 24),
            BackgroundColor3 = Theme.Accent,
        })
        connect(card.MouseEnter, function()
            tween(card, { BackgroundColor3 = Theme.CardHover }, 0.1)
            tween(strip, { Size = UDim2.new(0, 6, 1, 24) }, 0.1)
            cardStroke.Color = Theme.Accent
        end)
        connect(card.MouseLeave, function()
            tween(card, { BackgroundColor3 = Theme.Card }, 0.12)
            tween(strip, { Size = UDim2.new(0, 3, 1, 24) }, 0.12)
            cardStroke.Color = Theme.Stroke
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
            Font = Enum.Font.GothamBlack,
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

    ------------------------------------------------------------------
    -- Keybind: chip, registry, simpan / muat (workspace/NoctisENIX/settings.json)
    ------------------------------------------------------------------
    local STORE_DIR, STORE_FILE = "NoctisENIX", "NoctisENIX/settings.json"

    function UI.renderChip(bind)
        local kb = bind.chip
        if not kb then
            return
        end
        kb.Text = bind.key and bind.key.Name or "NONE"
        kb.TextColor3 = bind.key and Theme.Paper or Theme.Muted
        kb.BackgroundColor3 = Theme.Ink
    end

    function UI.saveSettings()
        if type(writefile) ~= "function" then
            return false, "writefile missing"
        end
        local data = { version = 1, binds = {} }
        for id, b in pairs(UI.bindsById) do
            data.binds[id] = b.key and b.key.Name or false
        end
        local okJ, json = pcall(function()
            return env.HttpService:JSONEncode(data)
        end)
        if not okJ then
            return false, tostring(json)
        end
        pcall(function()
            if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(STORE_DIR) then
                makefolder(STORE_DIR)
            end
        end)
        local okW, err = pcall(writefile, STORE_FILE, json)
        return okW, okW and STORE_FILE or tostring(err)
    end

    function UI.loadSettings()
        if type(readfile) ~= "function" then
            return false
        end
        if type(isfile) == "function" then
            local okF, exists = pcall(isfile, STORE_FILE)
            if not okF or not exists then
                return false
            end
        end
        local okR, raw = pcall(readfile, STORE_FILE)
        if not okR or type(raw) ~= "string" or raw == "" then
            return false
        end
        local okD, data = pcall(function()
            return env.HttpService:JSONDecode(raw)
        end)
        if not okD or type(data) ~= "table" or type(data.binds) ~= "table" then
            return false
        end
        for id, name in pairs(data.binds) do
            local b = UI.bindsById[id]
            if b then
                if name == false then
                    if not b.required then
                        b.key = nil
                    end
                elseif type(name) == "string" then
                    local okK, kc = pcall(function()
                        return Enum.KeyCode[name]
                    end)
                    if okK and kc then
                        b.key = kc
                    end
                end
                UI.renderChip(b)
            end
        end
        return true
    end

    -- Tombol yang sama nggak boleh dipakai dua fitur: ikatan lama dilepas.
    local function claimKey(bind, key)
        for _, other in ipairs(UI.binds) do
            if other ~= bind and other.key == key then
                if other.required then
                    return false
                end
                other.key = nil
                UI.renderChip(other)
            end
        end
        bind.key = key
        return true
    end

    local function clearBind(bind)
        if bind.required then
            bind.key = bind.default
        else
            bind.key = nil
        end
        UI.renderChip(bind)
        UI.saveSettings()
    end

    function UI.clearAllBinds()
        for _, b in ipairs(UI.binds) do
            if not b.required then
                b.key = nil
                UI.renderChip(b)
            end
        end
        return UI.saveSettings()
    end

    -- Chip keybind. Klik lalu tekan tombol; Escape / Backspace / klik kanan = hapus.
    function UI.keyChip(parent, bind, order)
        local kb = new("TextButton", {
            Name = "Key",
            Size = UDim2.fromOffset(64, 26),
            BackgroundColor3 = Theme.Ink,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBlack,
            TextSize = 11,
            TextColor3 = Theme.Muted,
            Text = "NONE",
            AutoButtonColor = false,
            LayoutOrder = order or 1,
            ZIndex = 4,
        }, parent)
        local kbStroke = sharp(kb, Theme.Paper, 1, 0.55)
        connect(kb.MouseEnter, function()
            kbStroke.Transparency = 0
        end)
        connect(kb.MouseLeave, function()
            kbStroke.Transparency = 0.55
        end)
        bind.chip = kb
        UI.renderChip(bind)
        connect(kb.MouseButton2Click, function()
            if not UI.capturing then
                clearBind(bind)
            end
        end)
        connect(kb.MouseButton1Click, function()
            if UI.capturing then
                return
            end
            UI.capturing = true
            kb.Text = "PRESS"
            kb.TextColor3 = Theme.Paper
            kb.BackgroundColor3 = Theme.Accent
            local conn
            conn = UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.Keyboard then
                    return
                end
                conn:Disconnect()
                UI.capturing = false
                UI.lastCapture = os.clock()
                if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
                    clearBind(bind)
                    return
                end
                if not claimKey(bind, input.KeyCode) then
                    UI.notify("Keybind", input.KeyCode.Name .. " is the menu key. Pick another key.", Theme.Bad, 3)
                elseif UI.keyConflict then
                    -- Tombol yang sama dengan ability game: dua-duanya jalan, jadi kasih tahu.
                    local okC, clash = pcall(UI.keyConflict, input.KeyCode)
                    if okC and type(clash) == "string" then
                        UI.notify("Keybind", input.KeyCode.Name .. " is also your in-game " .. clash .. " key. Pressing it does both.", Theme.Warn, 5)
                    end
                end
                UI.renderChip(bind)
                UI.saveSettings()
            end)
            track(conn)
        end)
        return kb
    end

    -- id = nama fitur (stabil antar sesi) buat simpan / muat.
    function UI.bind(fire, id)
        local bind = { key = nil, fire = fire }
        UI.binds[#UI.binds + 1] = bind
        if id then
            local key, n = id, 1
            while UI.bindsById[key] do
                n = n + 1
                key = id .. "#" .. n
            end
            bind.id = key
            UI.bindsById[key] = bind
        end
        return bind
    end

    -- Bind yang wajib ada (menu key): dihapus = balik ke default.
    function UI.registerBind(bind, id, required)
        bind.id = id
        bind.required = required and true or false
        bind.default = bind.key
        UI.bindsById[id] = bind
        local found = false
        for _, b in ipairs(UI.binds) do
            if b == bind then
                found = true
            end
        end
        if not found then
            UI.binds[#UI.binds + 1] = bind
        end
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
        -- Saklar tajam: OFF = rel abu + kotak gelap; ON = rel merah + kotak putih diputar jadi wajik.
        local switch = new("Frame", {
            Name = "Switch",
            Size = UDim2.fromOffset(46, 24),
            BackgroundColor3 = Theme.Off,
            BorderSizePixel = 0,
            LayoutOrder = 2,
            ZIndex = 4,
        }, right)
        local swStroke = sharp(switch, Theme.Paper, 1, 0.7)
        local knob = new("Frame", {
            Name = "Knob",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(14, 14),
            Position = UDim2.fromOffset(12, 12),
            BackgroundColor3 = Theme.Muted,
            BorderSizePixel = 0,
            ZIndex = 5,
        }, switch)
        local knobStroke = sharp(knob, Theme.Ink, 2, 0)
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
            tween(switch, { BackgroundColor3 = state and Theme.Accent or Theme.Off }, 0.12)
            swStroke.Transparency = state and 0 or 0.7
            knobStroke.Transparency = state and 0 or 1
            tweenEx(knob, {
                Position = state and UDim2.fromOffset(34, 12) or UDim2.fromOffset(12, 12),
                Rotation = state and 45 or 0,
                BackgroundColor3 = state and Theme.Paper or Theme.Muted,
            }, 0.2, Enum.EasingStyle.Back)
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
            api.bind = UI.bind(flip, title)
            UI.keyChip(right, api.bind, 1)
        end
        render()
        return api
    end

    -- opts = { bind = bool, risk = ..., action = "Run" }
    function UI.button(page, title, desc, callback, opts)
        local hasBind = opts and opts.bind
        local card, right = UI.card(page, title, desc, hasBind and 168 or 96, opts and opts.risk)
        -- Tombol merah teks putih; hover = dibalik putih/hitam + miring, klik = sentak.
        local pill = new("TextButton", {
            Name = "Action",
            Size = UDim2.fromOffset(88, 30),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBlack,
            TextSize = 12,
            TextColor3 = Theme.Paper,
            Text = string.upper((opts and opts.action) or "Run"),
            AutoButtonColor = false,
            LayoutOrder = 2,
            ZIndex = 4,
        }, right)
        local pillStroke = sharp(pill, Theme.Paper, 2, 0)
        connect(pill.MouseEnter, function()
            tweenEx(pill, { BackgroundColor3 = Theme.Paper, TextColor3 = Theme.Ink, Rotation = -4 }, 0.14, Enum.EasingStyle.Back)
            pillStroke.Color = Theme.Accent
        end)
        connect(pill.MouseLeave, function()
            tweenEx(pill, { BackgroundColor3 = Theme.Accent, TextColor3 = Theme.Paper, Rotation = 0 }, 0.12)
            pillStroke.Color = Theme.Paper
        end)
        local function fire()
            pill.Rotation = 3
            tweenEx(pill, { Rotation = pill.BackgroundColor3 == Theme.Paper and -4 or 0 }, 0.18, Enum.EasingStyle.Back)
            task.spawn(safe, callback)
        end
        connect(pill.MouseButton1Click, fire)
        local bind
        if hasBind then
            bind = UI.bind(fire, title)
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
            BackgroundColor3 = Theme.Paper,
            Font = Enum.Font.GothamBlack,
            TextSize = 13,
            TextColor3 = Theme.Ink,
            TextXAlignment = Enum.TextXAlignment.Center,
            Text = tostring(default),
            Rotation = -3,
            ZIndex = 4,
        }, right)
        sharp(valueChip, Theme.Accent, 2, 0)
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
        local fill = new("Frame", {
            Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
        }, bar)
        local knob = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
            Size = UDim2.fromOffset(12, 12),
            Rotation = 45,
            BackgroundColor3 = Theme.Paper,
            BorderSizePixel = 0,
            ZIndex = 3,
        }, bar)
        sharp(knob, Theme.Ink, 2, 0)
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
            BackgroundColor3 = Theme.Ink,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "None",
            AutoButtonColor = false,
            ZIndex = 4,
        }, right)
        local ddStroke = sharp(valueBtn, Theme.Stroke, 1, 0)
        pad(valueBtn, 0, 28, 0, 10)
        local arrowBox = slab(valueBtn, {
            Name = "ArrowBox",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(1, 4, 0.5, 0),
            Size = UDim2.fromOffset(20, 20),
            Rotation = -6,
            BackgroundColor3 = Theme.Accent,
            ZIndex = 5,
        })
        text({
            Name = "Arrow",
            Size = UDim2.fromScale(1, 1),
            Font = Enum.Font.GothamBlack,
            TextSize = 11,
            TextColor3 = Theme.Paper,
            Text = "V",
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 6,
        }, arrowBox)
        connect(valueBtn.MouseEnter, function()
            ddStroke.Color = Theme.Paper
        end)
        connect(valueBtn.MouseLeave, function()
            ddStroke.Color = Theme.Stroke
        end)

        local list = new("Frame", {
            Name = "DropdownList",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Ink,
            BorderSizePixel = 0,
            Visible = false,
            LayoutOrder = UI.nextOrder(page),
        }, page)
        sharp(list, Theme.Accent, 2, 0)
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
                    BackgroundColor3 = i % 2 == 0 and Theme.Bg or Theme.Card,
                    BorderSizePixel = 0,
                    Font = Enum.Font.GothamBold,
                    TextSize = 13,
                    TextColor3 = opt.color or Theme.Text,
                    Text = opt.label,
                    AutoButtonColor = false,
                    LayoutOrder = i,
                }, list)
                local rowBg = ob.BackgroundColor3
                connect(ob.MouseEnter, function()
                    tween(ob, { BackgroundColor3 = Theme.Accent }, 0.08)
                end)
                connect(ob.MouseLeave, function()
                    tween(ob, { BackgroundColor3 = rowBg }, 0.1)
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
        Position = UDim2.new(1, -326, 0, 12),
        ZIndex = 10,
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
        -- Kartu "calling card": badan hitam, garis putih, tag judul miring warna aksen,
        -- serpihan merah di pojok kanan (CanvasGroup selalu nge-clip, jadi aman diputar).
        local toast = new("CanvasGroup", {
            Name = "Toast",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Ink,
            BorderSizePixel = 0,
            GroupTransparency = 1,
            LayoutOrder = toastCount,
        }, toastHolder)
        sharp(toast, Theme.Paper, 2, 0)
        new("Frame", {
            Name = "Bar",
            Size = UDim2.new(0, 6, 1, 0),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
        }, toast)
        slab(toast, {
            Name = "Shard",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, -18, 0, 4),
            Size = UDim2.fromOffset(90, 16),
            Rotation = -28,
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.25,
        })
        slab(toast, {
            Name = "Shard2",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, -4, 0, 22),
            Size = UDim2.fromOffset(70, 3),
            Rotation = -28,
            BackgroundColor3 = Theme.Paper,
            BackgroundTransparency = 0.4,
        })
        local body = new("Frame", {
            Name = "Body",
            Position = UDim2.fromOffset(6, 0),
            Size = UDim2.new(1, -6, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            ZIndex = 2,
        }, toast)
        pad(body, 9, 14, 11, 12)
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
        local tag = text({
            Name = "Title",
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.new(0, 0, 0, 20),
            BackgroundTransparency = 0,
            BackgroundColor3 = accent,
            Font = Enum.Font.GothamBlack,
            TextSize = 12,
            TextColor3 = Theme.Ink,
            Rotation = -3,
            Text = tostring(title),
            LayoutOrder = 1,
        }, body)
        pad(tag, 0, 8, 0, 8)
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
        -- Masuk: miring lalu menyentak lurus.
        local tscale = new("UIScale", { Scale = 0.9 }, toast)
        tween(toast, { GroupTransparency = 0 }, 0.16)
        tweenEx(tscale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back)

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
        tweenEx(main, { Size = UI.minimized and UDim2.fromOffset(WIN_W, HEADER_H + 2) or UDim2.fromOffset(WIN_W, WIN_H) }, 0.22, Enum.EasingStyle.Quint)
    end
    connect(UI.minButton.MouseButton1Click, function()
        UI.setMinimized(not UI.minimized)
    end)

    -- Halo kursor: digambar sendiri, karena game ini menyembunyikan kursor sistem lewat cursorController.
    local cursorGui = env.cursorGui
    local halo = new("Frame", {
        Name = "CursorHalo",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(18, 18),
        Rotation = 45,
        BackgroundTransparency = 1,
        Visible = false,
    }, cursorGui)
    sharp(halo, Theme.Accent, 2, 0)
    new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(5, 5),
        BackgroundColor3 = Theme.Paper,
        BorderSizePixel = 0,
    }, halo)
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
