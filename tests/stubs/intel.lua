return function(ctx)
    local Intel = {}
    local feed = {}
    function Intel.start() end
    function Intel.step() end
    function Intel.info(p)
        if p.Name == "Alice" then
            return { role = "Mafia", team = "EVIL", confidence = "confirmed", reason = "stub", status = { downed = true }, disguise = "Mask" }
        end
        return { status = {} }
    end
    function Intel.self() return "Doctor", "TOWN" end
    function Intel.reset() feed = {} end
    function Intel.feed() return { { t = os.clock(), text = "stub event" } } end
    function Intel.votes() return {} end
    function Intel.stop() end
    return Intel
end
