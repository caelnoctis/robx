-- Escape meeting seat + Stand on the table (kursi di Workspace.Map.Seats, dari log game asli)
local fails = {}
local function check(c, m) if not c then fails[#fails + 1] = m end end
local me
for _, p in ipairs(__players) do if p.Name == "Me" then me = p end end
local map = __mk("Model", { Name = "Map" }, workspace)
local seats = __mk("Folder", { Name = "Seats" }, map)
local positions = { Vector3.new(10, 2, 0), Vector3.new(-10, 2, 0), Vector3.new(0, 2, 10), Vector3.new(0, 2, -10) }
local seatList = {}
for i, pos in ipairs(positions) do
    seatList[i] = __mk("Seat", { Name = "Seat", Position = pos, Disabled = false }, seats)
end
__Methods.IsA = (function(old)
    return function(self, cls)
        if rawget(self, "_class") == "Seat" and cls == "BasePart" then return true end
        if rawget(self, "_class") == "Weld" and cls == "JointInstance" then return true end
        return old(self, cls)
    end
end)(__Methods.IsA)
local hum = me.Character:FindFirstChildOfClass("Humanoid")
local root = me.Character:FindFirstChild("HumanoidRootPart")
local function sitOn(seat)
    hum.SeatPart = seat
    hum.Sit = true
    __mk("Weld", { Name = "SeatWeld", Part0 = seat, Part1 = root }, seat)
end
sitOn(seatList[1])

local A = ActionsFactory(ctx)
local ok, msg = A.setEscapeSeat(true)
check(ok == true and string.find(msg, "out of your seat", 1, true) ~= nil, "escape on: " .. tostring(msg))
check(seatList[1]:FindFirstChild("SeatWeld") == nil, "seat weld removed")
check(hum.Sit == false, "humanoid no longer sitting")
check(seatList[2].Disabled == true, "meeting seats disabled locally")
-- game men-seat-kan lagi -> Heartbeat berikutnya lepas lagi
sitOn(seatList[3])
rawget(ctx.RunService, "_signals").Heartbeat:Fire(0.016)
check(seatList[3]:FindFirstChild("SeatWeld") == nil, "re-seat undone on next frame")
-- Stand on the table: tengah lingkaran kursi (0, 2, 0) + 3.2
hum.SeatPart = nil
ok, msg = A.toTable()
local pos = me.Character:GetPivot().Position
local rp = root.CFrame and root.CFrame.Position
local at = (rp and (rp - Vector3.new(0, 5.2, 0)).Magnitude < 0.01) or ((pos - Vector3.new(0, 5.2, 0)).Magnitude < 0.01)
check(ok == true and at, "standing on table center: " .. tostring(msg))
-- off: kursi dipulihkan
ok, msg = A.setEscapeSeat(false)
check(ok == true and seatList[2].Disabled == false, "seats restored on off")
check(A.status().escapeSeat == false, "status off")
-- stop() juga mematikan
A.setEscapeSeat(true)
A.stop()
check(seatList[2].Disabled == false and A.status().escapeSeat == false, "stop restores seats")
for _, w in ipairs(__warns) do fails[#fails + 1] = "WARN " .. w end
if #fails == 0 then print("PASS actions-seat") else for _, f in ipairs(fails) do print("FAIL " .. f) end end
