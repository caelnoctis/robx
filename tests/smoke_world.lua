-- Dunia game palsu yang dibuat SEBELUM script dimuat: aset animasi + jaringan game
-- (nama-nama diambil dari scan remote game asli).
do
    local RS = game:GetService("ReplicatedStorage")
    local assets = __mk("Folder", { Name = "assets" }, RS)
    local anims = __mk("Folder", { Name = "animations" }, assets)
    local p1 = __mk("Folder", { Name = "player1" }, anims)
    __world = {}
    __world.knifeAnim = __mk("Animation", { Name = "KnifeSwing", AnimationId = "rbxassetid://222" }, p1)
    __mk("Animation", { Name = "gunShot", AnimationId = "rbxassetid://333" }, p1)
    __mk("Animation", { Name = "Wounded Crawling", AnimationId = "rbxassetid://111" }, p1)
    __mk("Animation", { Name = "Wounded Idle", AnimationId = "rbxassetid://112" }, p1)

    local SN = __mk("Folder", { Name = "ServiceNetworks" }, RS)
    local RN = __mk("Folder", { Name = "RoleNetworks" }, RS)
    local function folder(parent, name) return __mk("Folder", { Name = name }, parent) end
    local gameSvc = folder(SN, "gameService")
    local roleSvc = folder(SN, "roleService")
    local chatSvc = folder(SN, "chatService")
    local teamSvc = folder(SN, "teamService")
    __world.revealRoles = __mk("RemoteEvent", { Name = "revealRoles" }, gameSvc)
    __world.topbar = __mk("RemoteEvent", { Name = "setTopbarText" }, gameSvc)
    __world.deathCut = __mk("RemoteEvent", { Name = "playDeathCutscene" }, gameSvc)
    __world.gamePhase = __mk("RemoteFunction", { Name = "gamePhase" }, gameSvc)
    __world.roleRF = __mk("RemoteFunction", { Name = "role" }, roleSvc)
    __world.getRoleNetwork = __mk("RemoteEvent", { Name = "getRoleNetwork" }, roleSvc)
    __world.sysMsg = __mk("RemoteEvent", { Name = "onSystemMessage" }, chatSvc)
    __world.teamRF = __mk("RemoteFunction", { Name = "teamMembers" }, teamSvc)
    local mafia = folder(RN, "mafia")
    __world.onStab = __mk("RemoteFunction", { Name = "onStab" }, mafia)
    __world.mafiaTeam = __mk("RemoteFunction", { Name = "teamMembers" }, mafia)
    local doctor = folder(RN, "doctor")
    __world.onHeal = __mk("RemoteFunction", { Name = "onHeal" }, doctor)

    -- Respon server palsu per remote.
    __world.responses = {}
    __Methods.InvokeServer = function(self, ...)
        __remoteLog = __remoteLog or {}
        __remoteLog[#__remoteLog + 1] = { self.Name, ... }
        local fn = __world.responses[self]
        if fn then return fn(...) end
        return nil
    end
end
