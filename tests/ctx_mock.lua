-- ctx palsu untuk test modul
__notes = {}
__conns = {}
__tracked = {}
local _Players = game:GetService("Players")
ctx = {
    Players = _Players,
    RunService = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    CollectionService = game:GetService("CollectionService"),
    TextChatService = game:GetService("TextChatService"),
    Lighting = game:GetService("Lighting"),
    Workspace = workspace,
    LocalPlayer = _Players.LocalPlayer,
    service = function(n) return game:GetService(n) end,
    connect = function(sig, fn)
        local c = sig:Connect(fn)
        __conns[#__conns + 1] = c
        return c
    end,
    track = function(x)
        __tracked[#__tracked + 1] = x
        return x
    end,
    notify = function(t, x) __notes[#__notes + 1] = tostring(t) .. ": " .. tostring(x) end,
    warnf = function(...) warn(...) end,
    getChar = function(p) return p and p.Character end,
    getHum = function(p) local c = p and p.Character return c and c:FindFirstChildOfClass("Humanoid") end,
    getRoot = function(p) local c = p and p.Character return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart) end,
    S = {},
    alive = function() return true end,
}
ctx.Game = __GameFactory(ctx)
