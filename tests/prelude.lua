-- Mock Roblox environment (cukup buat smoke test logika NoctisENIX)
__G = {}
getgenv = function() return __G end
__warns = {}
__out = {}
print = function(...) local t = {} for i = 1, select('#', ...) do t[#t+1] = tostring((select(i, ...))) end __out[#__out+1] = table.concat(t, ' ') end
__clip = nil
__delays = {}
__hookFn = nil

warn = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    __warns[#__warns + 1] = table.concat(t, " ")
end

local function newSignal()
    local sig = { handlers = {} }
    function sig:Connect(fn)
        local conn = { Connected = true, __rbxtype = "RBXScriptConnection" }
        function conn:Disconnect()
            conn.Connected = false
            for i, h in ipairs(sig.handlers) do
                if h == fn then table.remove(sig.handlers, i) break end
            end
        end
        table.insert(sig.handlers, fn)
        return conn
    end
    function sig:Wait() end
    function sig:Fire(...)
        local copy = {}
        for i, h in ipairs(sig.handlers) do copy[i] = h end
        for _, h in ipairs(copy) do h(...) end
    end
    return sig
end

local V3 = {}
V3.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    if k == "Unit" then
        local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
        return setmetatable({ X = t.X / m, Y = t.Y / m, Z = t.Z / m }, V3)
    end
    return nil
end
V3.__add = function(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V3) end
V3.__sub = function(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V3) end
V3.__mul = function(a, b)
    if type(b) == "number" then return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, V3) end
    if type(a) == "number" then return setmetatable({ X = b.X * a, Y = b.Y * a, Z = b.Z * a }, V3) end
    return setmetatable({ X = a.X * b.X, Y = a.Y * b.Y, Z = a.Z * b.Z }, V3)
end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end }

local V2 = {}
V2.__index = V2
V2.__sub = function(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y }, V2) end
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2) end }

Color3 = {
    new = function(r, g, b) return { R = r, G = g, B = b } end,
    fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
}

UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
UDim2 = {
    new = function(xs, xo, ys, yo)
        return { X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }
    end,
    fromOffset = function(x, y) return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } } end,
    fromScale = function(x, y) return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } } end,
}

local CF = {}
CF.__index = CF
CF.__mul = function(a, b)
    if getmetatable(b) == V3 then return b end
    return a
end
CFrame = {
    new = function(x, y, z)
        return setmetatable({
            Position = Vector3.new(x, y, z),
            LookVector = Vector3.new(0, 0, -1),
            RightVector = Vector3.new(1, 0, 0),
        }, CF)
    end,
}

Enum = setmetatable({}, {
    __index = function(t, k)
        local sub = setmetatable({}, {
            __index = function(s, n)
                local v = { Name = n, EnumType = k }
                rawset(s, n, v)
                return v
            end,
        })
        rawset(t, k, sub)
        return sub
    end,
})

TweenInfo = { new = function() return {} end }

local realTypeof = typeof
typeof = function(v)
    if type(v) == "table" then
        local t = rawget(v, "__rbxtype")
        if t then return t end
    end
    return type(v)
end

task = {
    spawn = function(f, ...) f(...) end,
    delay = function(t, f) __delays[#__delays + 1] = f end,
    wait = function() return 0 end,
}

setclipboard = function(text) __clip = text end

-- Instance mock ------------------------------------------------------
local Inherit = {
    Part = "BasePart", MeshPart = "BasePart", UnionOperation = "BasePart",
    StringValue = "ValueBase", IntValue = "ValueBase", BoolValue = "ValueBase", ObjectValue = "ValueBase", NumberValue = "ValueBase",
    TextLabel = "GuiObject", TextButton = "GuiObject", Frame = "GuiObject", ScrollingFrame = "GuiObject",
}
local SignalNames = {}
for _, n in ipairs({
    "MouseButton1Click", "MouseEnter", "MouseLeave", "InputBegan", "InputChanged", "InputEnded",
    "Heartbeat", "Stepped", "RenderStepped", "PlayerAdded", "PlayerRemoving", "CharacterAdded", "Idled",
    "JumpRequest", "PromptShown", "Loaded", "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded",
}) do SignalNames[n] = true end

local Methods = {}
local function setParent(self, parent)
    local old = rawget(self, "_parent")
    if old then
        local ch = rawget(old, "_children")
        for i, c in ipairs(ch) do if c == self then table.remove(ch, i) break end end
    end
    rawset(self, "_parent", parent)
    if parent then table.insert(rawget(parent, "_children"), self) end
end

function Methods.GetChildren(self)
    local out = {}
    for i, c in ipairs(rawget(self, "_children")) do out[i] = c end
    return out
end
function Methods.GetDescendants(self)
    local out = {}
    local function walk(n)
        for _, c in ipairs(rawget(n, "_children")) do out[#out + 1] = c walk(c) end
    end
    walk(self)
    return out
end
function Methods.FindFirstChild(self, name)
    for _, c in ipairs(rawget(self, "_children")) do if c.Name == name then return c end end
    return nil
end
function Methods.FindFirstChildOfClass(self, cls)
    for _, c in ipairs(rawget(self, "_children")) do if rawget(c, "_class") == cls then return c end end
    return nil
end
function Methods.WaitForChild(self, name) return Methods.FindFirstChild(self, name) end
function Methods.IsA(self, cls)
    local c = rawget(self, "_class")
    if c == cls or cls == "Instance" then return true end
    local p = Inherit[c]
    while p do
        if p == cls then return true end
        p = Inherit[p]
    end
    if cls == "BasePart" and Inherit[c] == "BasePart" then return true end
    return false
end
function Methods.Destroy(self)
    for _, c in ipairs(Methods.GetChildren(self)) do Methods.Destroy(c) end
    setParent(self, nil)
    rawset(self, "_destroyed", true)
end
function Methods.GetAttribute(self, k) return rawget(self, "_attrs")[k] end
function Methods.SetAttribute(self, k, v) rawget(self, "_attrs")[k] = v end
function Methods.GetAttributes(self)
    local out = {}
    for k, v in pairs(rawget(self, "_attrs")) do out[k] = v end
    return out
end
function Methods.GetFullName(self)
    local parts = {}
    local n = self
    while n do
        table.insert(parts, 1, n.Name)
        n = rawget(n, "_parent")
    end
    return table.concat(parts, ".")
end
function Methods.Clone(self) return self end
function Methods.GetPlayers(self) return rawget(self, "_players") or {} end
function Methods.GetFocusedTextBox() return nil end
function Methods.IsKeyDown() return false end
function Methods.ChangeState(self, state) rawget(self, "_props").__state = state end
function Methods.Play() end
function Methods.Create() return { Play = function() end } end
function Methods.GenerateGUID() return "GUID-" .. tostring(math.random(1, 1e9)) end
function Methods.Teleport() end
function Methods.CaptureController() end
function Methods.ClickButton2() end
function Methods.GetProductInfo() return { Name = "MAFIA [V2.3] - ACT II" } end
function Methods.IsLoaded() return true end

local InstMT = {}
InstMT.__index = function(self, k)
    local m = Methods[k]
    if m then return m end
    local props = rawget(self, "_props")
    local v = props[k]
    if v ~= nil then return v end
    if k == "ClassName" then return rawget(self, "_class") end
    if k == "Parent" then return rawget(self, "_parent") end
    for _, c in ipairs(rawget(self, "_children")) do if c.Name == k then return c end end
    if SignalNames[k] then
        local sigs = rawget(self, "_signals")
        sigs[k] = sigs[k] or newSignal()
        return sigs[k]
    end
    return nil
end
InstMT.__newindex = function(self, k, v)
    if k == "Parent" then setParent(self, v) return end
    rawget(self, "_props")[k] = v
end

local Defaults = {
    Humanoid = { Health = 100, WalkSpeed = 16, JumpPower = 50, PlatformStand = false, UseJumpPower = false },
    Part = { CanCollide = true, Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) },
    Frame = { AbsolutePosition = Vector2.new(0, 0), AbsoluteSize = Vector2.new(200, 10) },
    TextButton = { AbsolutePosition = Vector2.new(0, 0), AbsoluteSize = Vector2.new(200, 10), Text = "" },
    TextLabel = { Text = "" },
    ProximityPrompt = { HoldDuration = 1 },
    Lighting = { Brightness = 1, ClockTime = 6, FogEnd = 900, GlobalShadows = true, Ambient = Color3.new(0, 0, 0), OutdoorAmbient = Color3.new(0, 0, 0) },
    Camera = { FieldOfView = 70, CFrame = CFrame.new(0, 10, 0) },
}

local function mk(class, props, parent)
    local self = setmetatable({}, InstMT)
    rawset(self, "__rbxtype", "Instance")
    rawset(self, "_class", class)
    local p = { Name = class }
    for k, v in pairs(Defaults[class] or {}) do p[k] = v end
    for k, v in pairs(props or {}) do p[k] = v end
    rawset(self, "_props", p)
    rawset(self, "_children", {})
    rawset(self, "_attrs", {})
    rawset(self, "_signals", {})
    if parent then setParent(self, parent) end
    return self
end
__mk = mk

Instance = { new = function(class, parent) return mk(class, nil, parent) end }

-- Services -----------------------------------------------------------
local services = {}
game = mk("DataModel", { Name = "Game", PlaceId = 123 })
Methods.GetService = function(self, name)
    local s = services[name]
    if not s then
        s = mk(name)
        services[name] = s
    end
    return s
end
workspace = mk("Workspace", { Name = "Workspace" })
workspace.CurrentCamera = mk("Camera")
services.Workspace = workspace
services.Players = mk("Players")
services.Lighting = mk("Lighting")
rawget(services.Players, "_players")
rawset(services.Players, "_players", {})
__services = services

-- World ----------------------------------------------------------------
local function buildPlayer(name, opts)
    opts = opts or {}
    local plr = mk("Player", { Name = name, DisplayName = name .. "D", UserId = 1 })
    mk("Backpack", nil, plr)
    local char = mk("Model", { Name = name })
    local hum = mk("Humanoid", { Health = opts.health or 100 }, char)
    mk("Part", { Name = "HumanoidRootPart", Position = Vector3.new(opts.x or 10, 0, 0) }, char)
    mk("Part", { Name = "Head", Position = Vector3.new(opts.x or 10, 3, 0) }, char)
    plr.Character = char
    if opts.charTool then mk("Tool", { Name = opts.charTool }, char) end
    if opts.backpackTool then mk("Tool", { Name = opts.backpackTool }, plr:FindFirstChildOfClass("Backpack")) end
    if opts.attr then plr:SetAttribute(opts.attr[1], opts.attr[2]) end
    if opts.value then mk("StringValue", { Name = opts.value[1], Value = opts.value[2] }, plr) end
    return plr
end
__buildPlayer = buildPlayer

local me = buildPlayer("Me", { backpackTool = "Knife", x = 0 })
local P = services.Players
P.LocalPlayer = me
local others = {
    buildPlayer("Alice", { charTool = "Steel Knife", x = 15 }),
    buildPlayer("Bob", { charTool = "Revolver", x = 25 }),
    buildPlayer("Cara", { attr = { "Role", "Doctor" }, x = 35 }),
    buildPlayer("Dan", { value = { "Role", "Civilian" }, x = 45 }),
    buildPlayer("Eve", { x = 55 }),
    buildPlayer("Frank", { charTool = "Knife", health = 0, x = 65 }),
}
local list = { me }
for _, o in ipairs(others) do list[#list + 1] = o end
rawset(P, "_players", list)
__players = list

-- ===== Extensions (dipakai test modul) =====
__Methods = Methods
__SignalNames = SignalNames
__Defaults = Defaults
__newSignal = newSignal
__setParent = setParent
__animLog = {}
__tags = {}
__tagSignals = {}
for _, n in ipairs({ "AttributeChanged", "AnimationPlayed", "MessageReceived", "Stopped", "Activated", "Triggered",
    "Died", "Equipped", "Unequipped", "OnClientEvent", "PromptTriggered", "Destroying" }) do SignalNames[n] = true end

tick = os.clock
time = os.clock
Random = { new = function() return { NextNumber = function(_, a) return a or 0 end, NextInteger = function(_, a) return a or 0 end } end }
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
V3.__unm = function(a) return setmetatable({ X = -a.X, Y = -a.Y, Z = -a.Z }, V3) end
V3.__div = function(a, b) return setmetatable({ X = a.X / b, Y = a.Y / b, Z = a.Z / b }, V3) end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
local v3index = V3.__index
V3.__index = function(t, k)
    if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
    if k == "Lerp" then return function(a, b, alpha) return a + (b - a) * alpha end end
    return v3index(t, k)
end

local function mkCF(pos, look)
    return setmetatable({
        Position = pos,
        p = pos,
        LookVector = look or Vector3.new(0, 0, -1),
        RightVector = Vector3.new(1, 0, 0),
        UpVector = Vector3.new(0, 1, 0),
    }, CF)
end
CFrame.new = function(a, b, c)
    if type(a) == "table" then
        local look
        if type(b) == "table" then
            local d = b - a
            if d.Magnitude > 0 then look = d.Unit end
        end
        return mkCF(a, look)
    end
    return mkCF(Vector3.new(a or 0, b or 0, c or 0))
end
CFrame.lookAt = function(a, b) return CFrame.new(a, b) end
CFrame.Angles = function() return mkCF(Vector3.new(0, 0, 0)) end
CFrame.identity = mkCF(Vector3.new(0, 0, 0))
CF.__mul = function(a, b)
    if getmetatable(b) == V3 then return a.Position + b end
    if getmetatable(b) == CF then return mkCF(a.Position + b.Position, a.LookVector) end
    return a
end
CF.__add = function(a, b) return mkCF(a.Position + b, a.LookVector) end
CF.__sub = function(a, b) return mkCF(a.Position - b, a.LookVector) end
CF.__index = function(t, k)
    if k == "Inverse" then return function(s) return s end end
    if k == "ToWorldSpace" or k == "ToObjectSpace" then return function(s, o) return o end end
    return rawget(CF, k)
end

function Methods.SetAttribute(self, k, v)
    local attrs = rawget(self, "_attrs")
    local old = attrs[k]
    attrs[k] = v
    if old ~= v then
        local sigs = rawget(self, "_signals")
        local s = sigs["AttrChanged:" .. k]
        if s then s:Fire() end
        local a = sigs.AttributeChanged
        if a then a:Fire(k) end
    end
end
function Methods.GetAttributeChangedSignal(self, k)
    local sigs = rawget(self, "_signals")
    local key = "AttrChanged:" .. k
    sigs[key] = sigs[key] or newSignal()
    return sigs[key]
end
function Methods.GetPropertyChangedSignal(self, k)
    local sigs = rawget(self, "_signals")
    local key = "Prop:" .. k
    sigs[key] = sigs[key] or newSignal()
    return sigs[key]
end
local plainFind = Methods.FindFirstChild
function Methods.FindFirstChild(self, name, recursive)
    if recursive then
        for _, d in ipairs(Methods.GetDescendants(self)) do if d.Name == name then return d end end
        return nil
    end
    return plainFind(self, name)
end
function Methods.FindFirstChildWhichIsA(self, cls)
    for _, c in ipairs(rawget(self, "_children")) do if c:IsA(cls) then return c end end
    return nil
end
function Methods.FindFirstAncestorOfClass(self, cls)
    local p = rawget(self, "_parent")
    while p do if rawget(p, "_class") == cls then return p end p = rawget(p, "_parent") end
    return nil
end
function Methods.FindFirstAncestor(self, name)
    local p = rawget(self, "_parent")
    while p do if p.Name == name then return p end p = rawget(p, "_parent") end
    return nil
end
function Methods.IsDescendantOf(self, other)
    local p = rawget(self, "_parent")
    while p do if p == other then return true end p = rawget(p, "_parent") end
    return false
end
function Methods.GetPlayerFromCharacter(self, char)
    for _, p in ipairs(rawget(self, "_players") or {}) do if p.Character == char then return p end end
    return nil
end
function Methods.GetPlayerByUserId(self, id)
    for _, p in ipairs(rawget(self, "_players") or {}) do if p.UserId == id then return p end end
    return nil
end
function Methods.PivotTo(self, cf) rawget(self, "_props").CFrame = cf end
function Methods.GetPivot(self) return rawget(self, "_props").CFrame or CFrame.new(0, 0, 0) end
function Methods.GetState() return Enum.HumanoidStateType.Running end
function Methods.MoveTo() end
function Methods.Activate(self)
    local s = rawget(self, "_signals").Activated
    if s then s:Fire() end
    __animLog[#__animLog + 1] = { "activate", self.Name }
end
function Methods.EquipTool(self, tool)
    local char = rawget(self, "_parent")
    tool.Parent = char
end
function Methods.UnequipTools() end
function Methods.LoadAnimation(self, anim)
    local owner = self
    local track = { Animation = anim, IsPlaying = false, Looped = false, Speed = 1, TimePosition = 0, Length = 1, __rbxtype = "Instance", Name = anim and anim.Name or "Track" }
    track.Stopped = newSignal()
    function track.Play(t)
        t.IsPlaying = true
        __animLog[#__animLog + 1] = { "play", anim and anim.Name or "?" }
        local s = rawget(owner, "_signals").AnimationPlayed
        if s then s:Fire(t) end
    end
    function track.Stop(t)
        t.IsPlaying = false
        __animLog[#__animLog + 1] = { "stop", anim and anim.Name or "?" }
        t.Stopped:Fire()
    end
    function track.AdjustSpeed(t, s) t.Speed = s end
    function track.Destroy() end
    return track
end
function Methods.GetPlayingAnimationTracks() return {} end
function Methods.HasTag(self, inst, tag)
    if rawget(self, "_class") ~= "CollectionService" then inst, tag = self, inst end
    return (__tags[inst] and __tags[inst][tag]) and true or false
end
function Methods.AddTag(self, inst, tag)
    if rawget(self, "_class") ~= "CollectionService" then inst, tag = self, inst end
    __tags[inst] = __tags[inst] or {}
    __tags[inst][tag] = true
    local s = __tagSignals[tag]
    if s then s:Fire(inst) end
end
function Methods.RemoveTag(self, inst, tag)
    if rawget(self, "_class") ~= "CollectionService" then inst, tag = self, inst end
    if __tags[inst] then __tags[inst][tag] = nil end
end
function Methods.GetTagged(self, tag)
    local out = {}
    for inst, tags in pairs(__tags) do if tags[tag] then out[#out + 1] = inst end end
    return out
end
function Methods.GetInstanceAddedSignal(self, tag)
    __tagSignals[tag] = __tagSignals[tag] or newSignal()
    return __tagSignals[tag]
end
function Methods.GetInstanceRemovedSignal(self, tag)
    local key = "rm:" .. tag
    __tagSignals[key] = __tagSignals[key] or newSignal()
    return __tagSignals[key]
end
function Methods.FireServer(self, ...)
    __remoteLog = __remoteLog or {}
    __remoteLog[#__remoteLog + 1] = { self.Name, ... }
end
function Methods.InvokeServer(self, ...)
    __remoteLog = __remoteLog or {}
    __remoteLog[#__remoteLog + 1] = { self.Name, ... }
    return true
end
function Methods.GetTextChannels() return {} end
Defaults.Humanoid.MoveDirection = Vector3.new(0, 0, 0)
Defaults.Part.Size = Vector3.new(2, 2, 1)
Defaults.Part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
Defaults.Animation = { AnimationId = "rbxassetid://0" }
-- Karakter yang sudah dibangun di atas: lengkapi CFrame & Animator.
for _, plr in ipairs(__players) do
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and not hum:FindFirstChildOfClass("Animator") then mk("Animator", nil, hum) end
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then root.CFrame = CFrame.new(root.Position) end
end
__mkPlayer = function(name, opts)
    local plr = __buildPlayer(name, opts)
    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
    mk("Animator", nil, hum)
    local root = plr.Character:FindFirstChild("HumanoidRootPart")
    root.CFrame = CFrame.new(root.Position)
    local list = rawget(services.Players, "_players")
    list[#list + 1] = plr
    return plr
end

-- ===== UI v2 mocks =====
ColorSequence = { new = function(a, b) return { Keypoints = { a, b or a } } end }
ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end }
NumberSequence = { new = function(a) return { Keypoints = a } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
__renderBinds = {}
function Methods.BindToRenderStep(self, name, priority, fn) __renderBinds[name] = fn end
function Methods.UnbindFromRenderStep(self, name) __renderBinds[name] = nil end
__mouse = Vector2.new(5, 5)
function Methods.GetMouseLocation() return __mouse end
__services.UserInputService = __services.UserInputService or game:GetService("UserInputService")
__services.UserInputService.MouseIconEnabled = false
__services.UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
Defaults.Frame.AbsoluteSize = Vector2.new(200, 10)
function __runRenderBinds() for _, fn in pairs(__renderBinds) do fn() end end
Enum.RenderPriority.First.Value = 0
Enum.RenderPriority.Input.Value = 100
Enum.RenderPriority.Camera.Value = 200
Enum.RenderPriority.Character.Value = 300
Enum.RenderPriority.Last.Value = 2000
