--!strict
--[[
	Phase 3 — Server-authoritative combat.
	Clients request fire/reload/equip/purchase; server validates and applies WeaponConfig damage.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local CombatConfig = require(Shared.Configs.CombatConfig)
local GameConfig = require(Shared.Configs.GameConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local ResearchConfig = require(Shared.Configs.ResearchConfig) -- v69 research

local CombatDamage = require(script.CombatDamage)
local CombatNPC = require(script.CombatNPC)
local CombatWeaponLogic = require(script.CombatWeaponLogic)
local VisualAssetService = require(script.Parent.VisualAssetService)

-- Cached CollectionService:GetTagged results (invalidated on TTL)
local _tagCache: { [string]: { at: number, list: { Instance } } } = {}
local TAG_CACHE_TTL = 2.0
local function getTaggedCached(tag: string): { Instance }
	local now = os.clock()
	local entry = _tagCache[tag]
	if entry and (now - entry.at) < TAG_CACHE_TTL then
		return entry.list
	end
	local list = CollectionService:GetTagged(tag)
	_tagCache[tag] = { at = now, list = list }
	return list
end

type WeaponDef = WeaponConfig.WeaponDef
type NPCTypeDef = CombatConfig.NPCTypeDef
type PlayerProfile = Types.PlayerProfile

type CombatState = {
	WeaponId: string,
	Ammo: number,
	ReloadingUntil: number,
	LastFireAt: number,
	InvulnerableUntil: number,
	Alive: boolean,
	FirstPvpLogged: boolean,
}

type NPCRecord = {
	Id: string,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	TypeId: string,
	Def: NPCTypeDef,
	LastFireAt: number,
	SpawnCFrame: CFrame,
	Alive: boolean,
}

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local BaseLayout = require(script.Parent.Parent.Modules.BaseLayout) -- v70: plot frame

local CombatService = {}

local DataService: any = nil
local EconomyService: any = nil
local XPService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local AntiExploitService: any = nil
local NotificationService: any = nil
local MonetizationService: any = nil
local GateDefenseService: any = nil
local MonetizationConfig: any = nil
local RemoteSetup: any = nil
local MissionService: any = nil
local TerritoryService: any = nil
local ResearchService: any = nil -- v69 research (deps.ResearchService; Init may run after ours)

local combatStates: { [number]: CombatState } = {}
local gunSchedule: { [number]: { [string]: number } } = {} -- v69 research: per-gun GCRA time (swaps can't skip a slow gun's cooldown)
local npcRecords: { [string]: NPCRecord } = {}
local npcFolder: Folder? = nil
local npcSerial = 1
local firstPvpLogged: { [number]: boolean } = {}

local function clock(): number
	return os.clock()
end

local function weaponDef(id: string): WeaponDef?
	return CombatWeaponLogic.WeaponDef(id)
end

local function researchMult(player: Player?, statId: string): number -- v69 research: ≥1, 1 when absent
	if player == nil or ResearchService == nil or ResearchService.GetBonus == nil then
		return 1
	end
	local ok, m = pcall(ResearchService.GetBonus, player, statId)
	if ok and typeof(m) == "number" and m == m and m >= 1 and m <= 5 then
		return m
	end
	return 1
end

local function magSize(player: Player?, def: WeaponDef): number -- v69 research: upgraded magazine
	return ResearchConfig.EffectiveMagazine(def.MagazineSize, researchMult(player, "WeaponMagazine"))
end

local function ensureStarter(profile: PlayerProfile)
	CombatWeaponLogic.EnsureStarter(profile)
end

local function owns(profile: PlayerProfile, weaponId: string): boolean
	return CombatWeaponLogic.Owns(profile, weaponId)
end

local function characterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

--[[ v69: replicate weapon ownership for the client UI — the Shop WEAPONS tab (BUY / EQUIP / EQUIPPED)
	and the Q/E + mobile ◀ ▶ cycle, which must only offer weapons the player owns. Display only: every
	equip / purchase is still validated in EquipWeapon / PurchaseWeapon.
	  WE_Weapons        = sorted comma list of owned WeaponConfig ids ("Pistol,StarterRifle")
	  WE_EquippedWeapon = equipped weapon id
	  WE_Level          = profile level (weapon unlock levels; XPUpdate refreshes it on the client between pushes)
	Runs from pushState (profile load, respawn, equip, purchase, fire, health change); only writes on change. ]]
local function syncWeaponAttributes(player: Player)
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return
	end
	local ids: { string } = {}
	local weapons: any = profile.Weapons
	if typeof(weapons) == "table" then
		for id, owned in pairs(weapons) do
			if owned == true and typeof(id) == "string" and WeaponConfig.Weapons[id] ~= nil then
				table.insert(ids, id)
			end
		end
	end
	table.sort(ids)
	local csv = table.concat(ids, ",")
	if player:GetAttribute("WE_Weapons") ~= csv then
		player:SetAttribute("WE_Weapons", csv)
	end
	local state = combatStates[player.UserId]
	local equipped: any = if state then state.WeaponId else profile.EquippedWeapon
	if typeof(equipped) == "string" and player:GetAttribute("WE_EquippedWeapon") ~= equipped then
		player:SetAttribute("WE_EquippedWeapon", equipped)
	end
	local level = tonumber(profile.Level)
	if level and player:GetAttribute("WE_Level") ~= level then
		player:SetAttribute("WE_Level", level)
	end
end

local function pushState(player: Player)
	pcall(syncWeaponAttributes, player)
	local state = combatStates[player.UserId]
	local _, humanoid = characterParts(player)
	local weaponId = if state then state.WeaponId else nil
	local def = if weaponId then weaponDef(weaponId) else nil
	local payload: Types.CombatStatePayload = {
		Health = if humanoid then humanoid.Health else 0,
		MaxHealth = if humanoid then humanoid.MaxHealth else CombatConfig.PlayerMaxHealth,
		WeaponId = weaponId,
		Ammo = if state then state.Ammo else 0,
		MagazineSize = if def then magSize(player, def) else 0, -- v69 research
		Reloading = if state then clock() < state.ReloadingUntil else false,
		Alive = if state then state.Alive else (humanoid ~= nil and humanoid.Health > 0),
	}
	local remote = RemoteSetup.Get(Constants.RemoteNames.CombatStateUpdate) :: RemoteEvent
	remote:FireClient(player, payload)
end

local function hitFeedback(player: Player, payload: Types.CombatHitFeedbackPayload)
	local remote = RemoteSetup.Get(Constants.RemoteNames.CombatHitFeedback) :: RemoteEvent
	remote:FireClient(player, payload)
end

local function getState(player: Player): CombatState?
	local profile = DataService.GetProfile(player)
	if not profile then
		return nil
	end
	ensureStarter(profile)
	local existing = combatStates[player.UserId]
	if existing then
		return existing
	end
	local weaponId = profile.EquippedWeapon or WeaponConfig.DefaultWeapon
	local def = weaponDef(weaponId)
	local state: CombatState = {
		WeaponId = weaponId,
		Ammo = if def then magSize(player, def) else 30, -- v69 research
		ReloadingUntil = 0,
		LastFireAt = 0,
		InvulnerableUntil = 0,
		Alive = true,
		FirstPvpLogged = firstPvpLogged[player.UserId] == true,
	}
	combatStates[player.UserId] = state
	return state
end

local function damageFor(def: WeaponDef, attacker: Player?): number
	local base = CombatDamage.DamageFor(def, attacker)
	local boosted = base * researchMult(attacker, "WeaponDamage") -- v69 research
	local lethal = CombatConfig.PlayerMaxHealth or 100 -- v69 research: the bonus never creates a one-shot (Sniper 85 x 1.2)
	if base < lethal and boosted >= lethal then -- v69 research
		return math.max(base, lethal - 1) -- v69 research
	end
	return boosted
end

local function tagCreator(humanoid: Humanoid, attacker: Player)
	CombatDamage.TagCreator(humanoid, attacker)
end

local function raycast(origin: Vector3, direction: Vector3, range: number, ignore: { Instance }): RaycastResult?
	return CombatDamage.Raycast(origin, direction, range, ignore)
end

-- v70: plot-local PlayerSpawn offset (same choice as MapSetup); the pad CFrame carries the plot yaw
local function plotSpawnOffset(): { X: number, Z: number }
	return if BaseLayout.Enabled() then BaseLayout.Config().SpawnOffset else { X = 0, Z = 55 }
end

function CombatService.GetPlotSpawnCFrame(plotId: number): CFrame?
	for _, inst in ipairs(getTaggedCached(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			local folder = inst.Parent
			if folder then
				local spawn = folder:FindFirstChild("PlayerSpawn")
				if spawn and spawn:IsA("BasePart") then
					return spawn.CFrame + Vector3.new(0, 3, 0)
				end
			end
			local sp = plotSpawnOffset()
			return inst.CFrame * CFrame.new(sp.X, 5, sp.Z)
		end
	end
	local pos = BaseConfig.PlotPositions[plotId]
	if pos then
		local sp = plotSpawnOffset()
		return BaseLayout.PlotCFrame(pos) * CFrame.new(sp.X, 5, sp.Z)
	end
	return nil
end

function CombatService.TeleportToBase(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile or not profile.BasePlotId then
		return
	end
	local cf = CombatService.GetPlotSpawnCFrame(profile.BasePlotId)
	local character = player.Character
	if cf and character then
		character:PivotTo(cf)
	end
end

local function markFirstPvp(attacker: Player)
	if firstPvpLogged[attacker.UserId] then
		local state = combatStates[attacker.UserId]
		if state then
			state.FirstPvpLogged = true
		end
		return
	end
	firstPvpLogged[attacker.UserId] = true
	local state = combatStates[attacker.UserId]
	if state then
		state.FirstPvpLogged = true
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.FIRST_PVP, attacker.UserId, {})
	end
end

local function grantRewards(attacker: Player, cash: number, xp: number, reason: string)
	if cash > 0 then
		EconomyService.AddCash(attacker, cash, reason)
	end
	if xp > 0 then
		XPService.AddXP(attacker, xp, reason)
	end
end

function CombatService.RegisterPlayerKill(attacker: Player, victim: Player)
	local profile = DataService.GetProfile(attacker)
	if profile then
		profile.Stats.Kills += 1
		DataService.MarkDirty(attacker)
	end
	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(attacker, "KillPlayer", 1)
	end
	local vProfile = DataService.GetProfile(victim)
	if vProfile then
		vProfile.Stats.Deaths += 1
		DataService.MarkDirty(victim)
	end
	markFirstPvp(attacker)
	grantRewards(attacker, CombatConfig.PlayerKill.Cash, CombatConfig.PlayerKill.XP, "pvp_kill")
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.PLAYER_KILL, attacker.UserId, {
			victim = victim.UserId,
			cash = CombatConfig.PlayerKill.Cash,
			xp = CombatConfig.PlayerKill.XP,
		})
	end
	if NotificationService then
		NotificationService.Notify(
			attacker,
			string.format("Eliminated %s (+$%d)", victim.DisplayName, CombatConfig.PlayerKill.Cash),
			"Reward"
		)
	end
end

local function damagePlayer(attacker: Player, victim: Player, damage: number, weaponId: string): boolean
	if not GameConfig.PvPEnabled then
		return false
	end
	if attacker == victim and not GameConfig.FriendlyFire then
		return false
	end
	local vState = combatStates[victim.UserId]
	if vState and clock() < vState.InvulnerableUntil then
		return false
	end
	local _, humanoid = characterParts(victim)
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	tagCreator(humanoid, attacker)
	local before = humanoid.Health
	humanoid:TakeDamage(damage)
	local dealt = math.max(0, before - humanoid.Health)
	if dealt <= 0 then
		return false
	end
	local killed = humanoid.Health <= 0
	hitFeedback(attacker, {
		Kind = if killed then "Kill" else "Hit",
		Damage = dealt,
		TargetName = victim.DisplayName,
		WeaponId = weaponId,
		IsHeadshot = false,
	})
	hitFeedback(victim, {
		Kind = if killed then "Death" else "Damaged",
		Damage = dealt,
		WeaponId = weaponId,
	})
	pushState(victim)
	return true
end

local function ensureNPCFolder(): Folder
	if npcFolder and npcFolder.Parent then
		return npcFolder
	end
	local existing = Workspace:FindFirstChild("WarEmpireNPCs")
	if existing and existing:IsA("Folder") then
		npcFolder = existing
		return npcFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "WarEmpireNPCs"
	folder.Parent = Workspace
	npcFolder = folder
	return folder
end

local function aliveNPCCount(): number
	local n = 0
	for _, rec in pairs(npcRecords) do
		if rec.Alive then
			n += 1
		end
	end
	return n
end

local function destroyNPC(rec: NPCRecord)
	rec.Alive = false
	npcRecords[rec.Id] = nil
	if rec.Model and rec.Model.Parent then
		rec.Model:Destroy()
	end
end

function CombatService.OnNPCKilled(attacker: Player, rec: NPCRecord)
	if not rec.Alive then
		return
	end
	rec.Alive = false
	local cash = rec.Def.CashReward
	local xp = rec.Def.XPReward
	grantRewards(attacker, cash, xp, "npc_kill")
	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(attacker, "KillNPC", 1)
	end
	local profile = DataService.GetProfile(attacker)
	if profile then
		profile.Stats.Kills += 1
		DataService.MarkDirty(attacker)
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.NPC_KILL, attacker.UserId, {
			npcType = rec.TypeId,
			cash = cash,
			xp = xp,
		})
	end
	if NotificationService then
		NotificationService.Notify(attacker, string.format("%s down (+$%d)", rec.Def.DisplayName, cash), "Reward")
	end
	hitFeedback(attacker, { Kind = "Kill", Damage = 0, TargetName = rec.Def.DisplayName, WeaponId = nil })
	local spawnCf = rec.SpawnCFrame
	local typeId = rec.TypeId
	task.delay(0.35, function()
		destroyNPC(rec)
	end)
	task.delay(CombatConfig.NPCRespawnSeconds, function()
		CombatService.SpawnNPC(typeId, spawnCf)
	end)
end

local function damageNPC(attacker: Player, npcId: string, damage: number, weaponId: string): boolean
	local rec = npcRecords[npcId]
	if not rec or not rec.Alive or rec.Humanoid.Health <= 0 then
		return false
	end
	tagCreator(rec.Humanoid, attacker)
	local before = rec.Humanoid.Health
	rec.Humanoid:TakeDamage(damage)
	local dealt = math.max(0, before - rec.Humanoid.Health)
	if dealt <= 0 then
		return false
	end
	local killed = rec.Humanoid.Health <= 0
	hitFeedback(attacker, {
		Kind = if killed then "Kill" else "Hit",
		Damage = dealt,
		TargetName = rec.Def.DisplayName,
		WeaponId = weaponId,
	})
	if killed then
		CombatService.OnNPCKilled(attacker, rec)
	end
	return true
end

function CombatService.SpawnNPC(typeId: string?, at: CFrame): NPCRecord?
	local tid = typeId or CombatConfig.DefaultNPCType
	local isSpecial = tid == "BankGuard" or tid == "OilRigGuard" or tid == "FortGuard"
	local cap = CombatConfig.MaxActiveNPCs or 18
	-- Special guards may exceed soft field pool by +4 so bank always gets guards
	if aliveNPCCount() >= (if isSpecial then cap + 4 else cap) then
		print(string.format("[CombatService] SpawnNPC blocked at cap alive=%d tid=%s", aliveNPCCount(), tostring(tid)))
		return nil
	end
	local def = CombatConfig.NPCTypes[tid]
	if not def then
		tid = CombatConfig.DefaultNPCType
		def = CombatConfig.NPCTypes[tid]
	end
	if not def then
		return nil
	end

	local id = string.format("npc_%d", npcSerial)
	npcSerial += 1

	local model = Instance.new("Model")
	model.Name = def.DisplayName
	model:SetAttribute("NPCId", id)
	model:SetAttribute("NPCType", tid)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	-- Classic R6 torso proportions (2×2×1)
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = at
	root.Anchored = false
	root.CanCollide = true
	root.Color = def.Color
	root.Material = Enum.Material.Fabric
	root.Parent = model

	local function weldPart(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = at * offset
		p.Anchored = false
		p.CanCollide = false
		p.Massless = true
		p.Color = color
		p.Material = material
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = root
		return p
	end

	-- Visual kits v2 infantry: helmet, vest, legs, rifle silhouette
	local skin = Color3.fromRGB(
		math.clamp(math.floor(def.Color.R * 255) + 30, 0, 255),
		math.clamp(math.floor(def.Color.G * 255) + 15, 0, 255),
		math.clamp(math.floor(def.Color.B * 255) + 10, 0, 255)
	)
	local helmCol = Color3.fromRGB(
		math.clamp(math.floor(def.Color.R * 255) - 20, 20, 255),
		math.clamp(math.floor(def.Color.G * 255) - 10, 20, 255),
		math.clamp(math.floor(def.Color.B * 255) - 15, 20, 255)
	)
	local isHeavy = tid == "HeavyInfantry" or tid == "OilRigGuard" or tid == "FortGuard"
	local isBank = tid == "BankGuard"
	-- R6-ish: head +1.5, arms ±1.5, legs ±0.5 @ -2
	local headPart = weldPart("Head", Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 1.55, 0), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = headPart
	weldPart("Helmet", Vector3.new(1.2, 0.5, 1.2), CFrame.new(0, 1.95, 0), helmCol, Enum.Material.Metal, nil)
	weldPart("Visor", Vector3.new(0.95, 0.2, 0.3), CFrame.new(0, 1.75, -0.5), Color3.fromRGB(30, 35, 40), Enum.Material.Glass, nil)
	weldPart("Vest", Vector3.new(2.1, 1.2, 1.15), CFrame.new(0, 0.15, 0), Color3.fromRGB(
		math.clamp(math.floor(def.Color.R * 255) - 25, 25, 255),
		math.clamp(math.floor(def.Color.G * 255) - 15, 25, 255),
		math.clamp(math.floor(def.Color.B * 255) - 10, 25, 255)
	), Enum.Material.Metal, nil)
	weldPart("LegL", Vector3.new(1, 2, 1), CFrame.new(-0.5, -2, 0), def.Color, Enum.Material.Fabric, nil)
	weldPart("LegR", Vector3.new(1, 2, 1), CFrame.new(0.5, -2, 0), def.Color, Enum.Material.Fabric, nil)
	weldPart("BootL", Vector3.new(1.05, 0.35, 1.15), CFrame.new(-0.5, -3.1, 0.1), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic, nil)
	weldPart("BootR", Vector3.new(1.05, 0.35, 1.15), CFrame.new(0.5, -3.1, 0.1), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic, nil)
	weldPart("ArmL", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), def.Color, Enum.Material.Fabric, nil)
	weldPart("ArmR", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), def.Color, Enum.Material.Fabric, nil)
	weldPart("Rifle", Vector3.new(0.26, 0.26, 2.4), CFrame.new(1.15, 0.15, -0.85), Color3.fromRGB(28, 28, 30), Enum.Material.Metal, nil)
	weldPart("Stock", Vector3.new(0.28, 0.35, 0.7), CFrame.new(1.15, 0.2, 0.55), Color3.fromRGB(45, 40, 32), Enum.Material.Wood, nil)
	weldPart("BarrelTip", Vector3.new(0.18, 0.18, 0.35), CFrame.new(1.15, 0.15, -2.05), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil)
	local accent = if isBank
		then Color3.fromRGB(90, 140, 220)
		elseif isHeavy then Color3.fromRGB(230, 160, 50)
		else Color3.fromRGB(200, 80, 60)
	weldPart("Accent", Vector3.new(1.9, 0.12, 0.35), CFrame.new(0, 0.95, -0.6), accent, Enum.Material.Metal, nil)
	if isHeavy then
		weldPart("Pack", Vector3.new(1.4, 1.5, 0.7), CFrame.new(0, 0.4, 0.85), Color3.fromRGB(40, 42, 38), Enum.Material.Metal, nil)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = def.Health
	humanoid.Health = def.Health
	humanoid.WalkSpeed = def.WalkSpeed
	humanoid.AutoRotate = true
	humanoid.HipHeight = 2 -- R6-ish Part kit (root mid-torso; legs welded massless)
	-- Kill double nametags: Humanoid nameplate OFF; one clean Billboard only
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
	humanoid.Parent = model

	-- Single clean nameplate
	local bb = Instance.new("BillboardGui")
	bb.Name = "NPCLabel"
	bb.Size = UDim2.fromOffset(140, 28)
	bb.StudsOffset = Vector3.new(0, 3.6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Parent = root
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
	lbl.BackgroundTransparency = 0.25
	lbl.Text = def.DisplayName
	lbl.TextColor3 = Color3.fromRGB(230, 235, 255)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = lbl

	model.PrimaryPart = root
	-- Optional free catalog character visual (scripts stripped); Part kit stays authoritative.
	-- Resolve by NPC type id (Infantry/BankGuard/…); VisualAssetService falls back to Soldier.
	pcall(function()
		VisualAssetService.TryAttachCharacterVisual(model, tid)
	end)
	CollectionService:AddTag(model, Constants.Tags.NPC)
	model.Parent = ensureNPCFolder()
	-- Server owns physics so MoveTo works reliably
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- Yaw-only BodyGyro so Humanoid:MoveTo can walk (full XYZ torque pins feet)
	local gyro = Instance.new("BodyGyro")
	gyro.Name = "NPCFaceGyro"
	gyro.MaxTorque = Vector3.new(0, 4e5, 0)
	gyro.P = 5000
	gyro.D = 500
	gyro.CFrame = at
	gyro.Parent = root

	local rec: NPCRecord = {
		Id = id,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		TypeId = tid,
		Def = def,
		LastFireAt = 0,
		SpawnCFrame = at,
		Alive = true,
	}
	npcRecords[id] = rec

	humanoid.Died:Connect(function()
		if not rec.Alive then
			return
		end
		local killer: Player? = nil
		local tag = humanoid:FindFirstChild("creator")
		if tag and tag:IsA("ObjectValue") and tag.Value and tag.Value:IsA("Player") then
			killer = tag.Value :: Player
		end
		if killer then
			CombatService.OnNPCKilled(killer, rec)
		else
			local spawnCf = rec.SpawnCFrame
			local t = rec.TypeId
			task.delay(0.35, function()
				destroyNPC(rec)
			end)
			task.delay(CombatConfig.NPCRespawnSeconds, function()
				CombatService.SpawnNPC(t, spawnCf)
			end)
		end
	end)

	return rec
end

local function thinkNPCs()
	CombatNPC.Think()
end

local function gatherSpawns(): { CFrame }
	return CombatNPC.GatherSpawns()
end

function CombatService.BootstrapNPCs()
	local points = gatherSpawns()
	local types = { "Infantry", "Infantry", "HeavyInfantry" }
	local spawned = 0
	-- Reserve slots for BankGuard / special spawns (BankRaidService)
	local fieldCap = math.max(4, (CombatConfig.MaxActiveNPCs or 18) - 6)
	for i, cf in ipairs(points) do
		if spawned >= fieldCap then
			break
		end
		local typeId = types[((i - 1) % #types) + 1]
		if CombatService.SpawnNPC(typeId, cf) then
			spawned += 1
		end
	end
	if RunService:IsStudio() then
		print(string.format("[CombatService] Spawned %d NPCs (cap %d)", spawned, CombatConfig.MaxActiveNPCs))
	end
end

function CombatService.EquipWeapon(player: Player, weaponId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(weaponId, 48) then
		return false, "InvalidWeapon"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	ensureStarter(profile)
	if not owns(profile, weaponId) then
		return false, "NotOwned"
	end
	local def = weaponDef(weaponId)
	if not def then
		return false, "UnknownWeapon"
	end
	if profile.Level < def.UnlockLevel then
		return false, "LevelTooLow"
	end
	profile.EquippedWeapon = weaponId
	DataService.MarkDirty(player)
	local state = getState(player)
	if state then
		state.WeaponId = weaponId
		state.Ammo = magSize(player, def) -- v69 research
		state.ReloadingUntil = 0
	end
	pushState(player)
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.WEAPON_EQUIPPED, player.UserId, { weapon = weaponId })
	end
	return true, nil
end

function CombatService.PurchaseWeapon(player: Player, weaponId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(weaponId, 48) then
		return false, "InvalidWeapon"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local def = weaponDef(weaponId)
	if not def then
		return false, "UnknownWeapon"
	end
	ensureStarter(profile)
	if owns(profile, weaponId) then
		return false, "AlreadyOwned"
	end
	if profile.Level < def.UnlockLevel then
		return false, "LevelTooLow"
	end
	-- v69: price comes from the server's WeaponConfig only (the remote carries just the id). A weapon with no
	-- positive CostCash is not sold — the starter is granted by ensureStarter, anything else by other systems.
	local cost = math.floor(tonumber(def.CostCash) or 0)
	if cost <= 0 then
		return false, "NotForSale"
	end
	local ok, err = EconomyService.SpendCash(player, cost, "weapon_" .. weaponId)
	if not ok then
		return false, err or "SpendFailed"
	end
	profile.Weapons[weaponId] = true
	DataService.MarkDirty(player)
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.WEAPON_PURCHASED, player.UserId, { weapon = weaponId, cost = cost })
	end
	if NotificationService then
		NotificationService.Notify(player, "Acquired " .. def.DisplayName, "Reward")
	end
	CombatService.EquipWeapon(player, weaponId)
	pcall(syncWeaponAttributes, player)
	return true, nil
end

--[[ v69: player-facing text for weapon BUY / EQUIP refusals (was "Cannot buy weapon: InsufficientCash"). ]]
local function formatCash(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

local function weaponRefusalText(action: string, weaponId: any, err: string): string
	local def = if typeof(weaponId) == "string" then weaponDef(weaponId) else nil
	local name = if def then def.DisplayName else "that weapon"
	if err == "InsufficientCash" and def then
		return string.format("Not enough Cash — %s costs $%s", name, formatCash(tonumber(def.CostCash) or 0))
	elseif err == "LevelTooLow" and def then
		return string.format("%s unlocks at Lv %d", name, def.UnlockLevel)
	elseif err == "AlreadyOwned" then
		return string.format("You already own %s — tap EQUIP in Shop › WEAPONS", name)
	elseif err == "NotOwned" then
		return string.format("You don't own %s yet — buy it in Shop › WEAPONS", name)
	elseif err == "NotForSale" then
		return string.format("%s is not for sale", name)
	elseif err == "NoProfile" then
		return "Your save is still loading — try again in a moment"
	end
	return string.format("Cannot %s weapon: %s", action, err)
end

function CombatService.Reload(player: Player): (boolean, string?)
	local state = getState(player)
	if not state or not state.Alive then
		return false, "Dead"
	end
	local def = weaponDef(state.WeaponId)
	if not def then
		return false, "NoWeapon"
	end
	if clock() < state.ReloadingUntil then
		return false, "AlreadyReloading"
	end
	if state.Ammo >= magSize(player, def) then -- v69 research
		return false, "FullMag"
	end
	local reloadTime = def.ReloadTime / researchMult(player, "WeaponReload") -- v69 research
	state.ReloadingUntil = clock() + reloadTime
	local weaponId = state.WeaponId
	pushState(player)
	task.delay(reloadTime, function()
		local s = combatStates[player.UserId]
		if not s or s.WeaponId ~= weaponId then
			return
		end
		if clock() + 0.05 < s.ReloadingUntil then
			return
		end
		s.Ammo = magSize(player, def) -- v69 research
		s.ReloadingUntil = 0
		if player.Parent then
			pushState(player)
		end
	end)
	return true, nil
end

function CombatService.RequestFire(player: Player, payload: any): boolean
	if typeof(payload) ~= "table" then
		AntiExploitService.Strike(player, "fire_bad_payload")
		return false
	end
	if not RateLimitService.Allow(player, "combat_fire", CombatConfig.FireRemoteRate, CombatConfig.FireRemoteBurst) then
		return false
	end

	local state = getState(player)
	if not state or not state.Alive then
		return false
	end
	if clock() < state.ReloadingUntil then
		return false
	end

	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	ensureStarter(profile)
	if not owns(profile, state.WeaponId) then
		AntiExploitService.Strike(player, "fire_unowned_weapon")
		return false
	end

	local def = weaponDef(state.WeaponId)
	if not def then
		return false
	end

	local minInterval = 1 / math.max(def.FireRate * researchMult(player, "WeaponFireRate"), 0.1) -- v69 research
	if state.LastFireAt > clock() + minInterval * 0.5 then -- v69 research: after a switch from a slower gun,
		state.LastFireAt = clock() + minInterval * 0.5 -- cap its schedule to this gun (no-op for one gun)
	end
	local guns = gunSchedule[player.UserId] or {} -- v69 research
	gunSchedule[player.UserId] = guns -- v69 research
	local gunAt = guns[state.WeaponId] or -math.huge -- v69 research: this gun's own schedule (never capped)
	if clock() - state.LastFireAt < minInterval * 0.5 or clock() - gunAt < minInterval * 0.5 then -- v69: GCRA
		return false
	end
	if state.Ammo <= 0 then
		return false
	end

	local character, humanoid, root = characterParts(player)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return false
	end

	local direction = payload.Direction
	if typeof(direction) ~= "Vector3" or direction.Magnitude < CombatConfig.MaxAimDirectionError then
		AntiExploitService.Strike(player, "fire_bad_direction")
		return false
	end
	if not AntiExploitService.IsFiniteNumber(direction.X) then
		AntiExploitService.Strike(player, "fire_nan_direction")
		return false
	end
	direction = direction.Unit

	local origin = payload.Origin
	if typeof(origin) ~= "Vector3" then
		origin = root.Position + Vector3.new(0, 1.5, 0)
	else
		if (origin - root.Position).Magnitude > CombatConfig.MaxOriginDeltaStuds then
			AntiExploitService.Strike(player, "fire_origin_desync")
			origin = root.Position + Vector3.new(0, 1.5, 0)
		end
	end

	state.Ammo -= 1
	state.LastFireAt = math.max(state.LastFireAt + minInterval, clock()) -- v69 research: was = clock()
	guns[state.WeaponId] = math.max(gunAt + minInterval, clock()) -- v69 research
	pushState(player)

	local range = def.Range + CombatConfig.HitPositionSlopStuds
	local damage = damageFor(def, player)
	local result = raycast(origin, direction, range, { character })

	local hitSomething = false
	if result then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model then
			local hitPlayer = Players:GetPlayerFromCharacter(model)
			if hitPlayer then
				hitSomething = damagePlayer(player, hitPlayer, damage, state.WeaponId)
			elseif CollectionService:HasTag(model, Constants.Tags.NPC) then
				local npcId = model:GetAttribute("NPCId")
				if typeof(npcId) == "string" and (result.Position - origin).Magnitude <= range then
					hitSomething = damageNPC(player, npcId, damage, state.WeaponId)
				end
			end
		end
		-- Siegeable plot gate barrier (server-validated)
		if not hitSomething then
			local hitInst = result.Instance
			if hitInst and hitInst:IsA("BasePart") and hitInst:GetAttribute("GateBarrier") == true then
				if GateDefenseService and GateDefenseService.ApplyDamage then
					hitSomething = GateDefenseService.ApplyDamage(player, hitInst, damage, state.WeaponId) == true
				end
			end
		end
	else
		local targetUserId = payload.TargetUserId
		local targetNpcId = payload.TargetNpcId
		if typeof(targetUserId) == "number" then
			local targetPlayer = Players:GetPlayerByUserId(targetUserId)
			if targetPlayer then
				local _, _, troot = characterParts(targetPlayer)
				if troot and (troot.Position - origin).Magnitude <= range then
					hitSomething = damagePlayer(player, targetPlayer, damage, state.WeaponId)
				end
			end
		elseif typeof(targetNpcId) == "string" then
			local rec = npcRecords[targetNpcId]
			if rec and rec.Alive and (rec.Root.Position - origin).Magnitude <= range then
				hitSomething = damageNPC(player, targetNpcId, damage, state.WeaponId)
			end
		end
	end

	if not hitSomething then
		local hitPosition = payload.HitPosition
		if typeof(hitPosition) == "Vector3" and (hitPosition - origin).Magnitude > range * 1.25 then
			AntiExploitService.Strike(player, "fire_hitpos_oor")
		end
	end

	return true
end

local lastDeathShopAt: { [number]: number } = {}
local DEATH_SHOP_DEBOUNCE = 12

local function resolveDeathOfferLive(MonetizationConfig: any, key: string): (boolean, string?)
	-- Prefer GamePass Id (DoubleCash), then DevProduct Id (SpeedBoost)
	local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses[key]
	if gp and typeof(gp.Id) == "number" and gp.Id ~= 0 then
		return true, gp.DisplayName or key
	end
	local dp = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts[key]
	if dp and typeof(dp.Id) == "number" and dp.Id ~= 0 then
		return true, dp.DisplayName or key
	end
	return false, nil
end

local function onPlayerDeath(victim: Player, killer: Player?)
	local state = combatStates[victim.UserId]
	if state then
		state.Alive = false
	end
	pushState(victim)
	if killer and killer ~= victim then
		CombatService.RegisterPlayerKill(killer, victim)
	else
		local vProfile = DataService.GetProfile(victim)
		if vProfile then
			vProfile.Stats.Deaths += 1
			DataService.MarkDirty(victim)
		end
	end
	
	-- v30: PvP death → DeathShopOffer toast (DoubleCash GP + SpeedBoost DP; live Ids only; debounced)
	if killer and killer ~= victim and NotificationService then
		local now = os.clock()
		local prev = lastDeathShopAt[victim.UserId] or 0
		if now - prev >= DEATH_SHOP_DEBOUNCE then
			lastDeathShopAt[victim.UserId] = now
			local MonetizationConfig = require(ReplicatedStorage.Shared.Configs.MonetizationConfig)
			local offers = (MonetizationConfig :: any).DeathShopOffers or { "DoubleCash", "SpeedBoost" }
			local liveOffers = {}
			local labels = {}
			for _, key in ipairs(offers) do
				local live, label = resolveDeathOfferLive(MonetizationConfig, key)
				if live and label then
					table.insert(liveOffers, key)
					table.insert(labels, label)
				end
			end
			if #liveOffers > 0 then
				NotificationService.Notify(
					victim,
					"Boost? " .. table.concat(labels, " / ") .. " — tap toast",
					"Info",
					5
				)
				if RemoteSetup then
					local remote = RemoteSetup.Get(Constants.RemoteNames.DeathShopOffer)
					if remote then
						(remote :: RemoteEvent):FireClient(victim, { Offers = liveOffers })
					end
				end
			end
			-- v37: CashMega soft offer on death path if not already offered (existing Id only)
			if MonetizationService and MonetizationService.TrySoftOfferCashMega then
				pcall(function()
					MonetizationService.TrySoftOfferCashMega(victim, "death", 0)
				end)
			end
		end
	end

	task.delay(GameConfig.RespawnTimeSeconds, function()
		if victim.Parent then
			victim:LoadCharacter()
		end
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.MaxHealth = CombatConfig.PlayerMaxHealth
	humanoid.Health = CombatConfig.PlayerMaxHealth

	local state = getState(player)
	if state then
		state.Alive = true
		local invuln = GameConfig.SpawnInvulnerabilitySeconds or CombatConfig.SpawnInvulnerabilitySeconds
		state.InvulnerableUntil = clock() + invuln
		local def = weaponDef(state.WeaponId)
		if def then
			state.Ammo = magSize(player, def) -- v69 research
			state.ReloadingUntil = 0
		end
	end

	task.defer(function()
		CombatService.TeleportToBase(player)
		pushState(player)
	end)

	humanoid.Died:Connect(function()
		local killer: Player? = nil
		local tag = humanoid:FindFirstChild("creator")
		if tag and tag:IsA("ObjectValue") and tag.Value and tag.Value:IsA("Player") then
			killer = tag.Value :: Player
		end
		onPlayerDeath(player, killer)
	end)

	humanoid.HealthChanged:Connect(function()
		pushState(player)
	end)
end

function CombatService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	AntiExploitService = deps.AntiExploitService
	NotificationService = deps.NotificationService
	MonetizationService = deps.MonetizationService
	GateDefenseService = deps.GateDefenseService
	RemoteSetup = deps.RemoteSetup
	MissionService = deps.MissionService
	TerritoryService = deps.TerritoryService
	ResearchService = deps.ResearchService -- v69 research

	CombatDamage.Bind({ TerritoryService = TerritoryService })
	CombatNPC.Bind({
		npcRecords = npcRecords,
		combatStates = combatStates,
		clock = clock,
		characterParts = characterParts,
		hitFeedback = hitFeedback,
		pushState = pushState,
		spawnNPC = function(typeId: string?, at: CFrame)
			return CombatService.SpawnNPC(typeId, at)
		end,
		getTagged = getTaggedCached,
	})


	local equipRemote = RemoteSetup.Get(Constants.RemoteNames.RequestEquipWeapon) :: RemoteEvent
	equipRemote.OnServerEvent:Connect(function(player: Player, weaponId: any)
		if not RateLimitService.Allow(player, "equip_weapon", CombatConfig.EquipRemoteRate, CombatConfig.EquipRemoteBurst) then
			return
		end
		local ok, err = CombatService.EquipWeapon(player, weaponId)
		if not ok and NotificationService and err then
			NotificationService.Notify(player, weaponRefusalText("equip", weaponId, tostring(err)), "Warn")
		end
	end)

	-- Shop › WEAPONS BUY (ShopController). Client sends only the weapon id; PurchaseWeapon checks id, loaded
	-- profile, ownership, UnlockLevel and spends WeaponConfig.CostCash via EconomyService.SpendCash.
	local purchaseRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseWeapon) :: RemoteEvent
	purchaseRemote.OnServerEvent:Connect(function(player: Player, weaponId: any)
		if not RateLimitService.Allow(player, "buy_weapon", CombatConfig.PurchaseWeaponRate, CombatConfig.PurchaseWeaponBurst) then
			return
		end
		local ok, err = CombatService.PurchaseWeapon(player, weaponId)
		if not ok and NotificationService and err then
			NotificationService.Notify(player, weaponRefusalText("buy", weaponId, tostring(err)), "Warn")
		end
	end)

	local fireRemote = RemoteSetup.Get(Constants.RemoteNames.RequestFire) :: RemoteEvent
	fireRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		CombatService.RequestFire(player, payload)
	end)

	local reloadRemote = RemoteSetup.Get(Constants.RemoteNames.RequestReload) :: RemoteEvent
	reloadRemote.OnServerEvent:Connect(function(player: Player)
		if not RateLimitService.Allow(player, "reload", CombatConfig.ReloadRemoteRate, CombatConfig.ReloadRemoteBurst) then
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		CombatService.Reload(player)
	end)

	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	DataService.OnProfileLoaded(function(player: Player, profile: PlayerProfile)
		ensureStarter(profile)
		DataService.MarkDirty(player)
		getState(player)
		local wid = profile.EquippedWeapon or WeaponConfig.DefaultWeapon
		CombatService.EquipWeapon(player, wid)
		pushState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		combatStates[player.UserId] = nil
		gunSchedule[player.UserId] = nil -- v69 research
	end)

	task.spawn(function()
		task.wait(1)
		CombatService.BootstrapNPCs()
		while true do
			task.wait(CombatConfig.NPCThinkInterval)
			thinkNPCs()
		end
	end)
end

function CombatService.GetPlayerCombatState(player: Player): CombatState?
	return combatStates[player.UserId]
end

function CombatService.PushState(player: Player)
	pushState(player)
end

function CombatService.ApplyDamage(attacker: Player, target: Humanoid, weaponId: string, _ignored: number)
	local def = weaponDef(weaponId)
	if not def then
		return
	end
	local damage = damageFor(def, attacker)
	local model = target.Parent
	if model and model:IsA("Model") then
		local victim = Players:GetPlayerFromCharacter(model)
		if victim then
			damagePlayer(attacker, victim, damage, weaponId)
			return
		end
		if CollectionService:HasTag(model, Constants.Tags.NPC) then
			local npcId = model:GetAttribute("NPCId")
			if typeof(npcId) == "string" then
				damageNPC(attacker, npcId, damage, weaponId)
			end
		end
	end
end

function CombatService.RegisterKill(attacker: Player, victim: Player)
	CombatService.RegisterPlayerKill(attacker, victim)
end

return CombatService
