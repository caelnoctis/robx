return function(ctx)
    local A = { target = nil }
    function A.setFakeCrawl(on) return true, "crawl " .. tostring(on) end
    function A.fakeStab() return true, "Played KnifeSwing" end
    function A.fakeShot() return false, "Gun animation not found" end
    function A.setGhost(on) return false, "Get out of your seat first." end
    function A.livingPlayers()
        local out = {}
        for _, p in ipairs(ctx.Players:GetPlayers()) do if p ~= ctx.LocalPlayer then out[#out + 1] = p end end
        return out
    end
    function A.setTarget(p) A.target = p return true, "ok" end
    function A.getTarget() return A.target end
    function A.toTarget() return A.target ~= nil, A.target and "ok" or "Pick a living player in Target first." end
    function A.toDowned() return false, "Nobody is downed right now." end
    function A.toDetained() return false, "Nobody is detained right now." end
    function A.tpStabReturn() return false, "The stab handler has not loaded yet -- try again in a second." end
    function A.tpHealReturn() return false, "Doctor only." end
    function A.setBring(on) return true, "Only you see them move." end
    function A.status() return {} end
    function A.stop() end
    return A
end
