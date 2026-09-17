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

local CombatService = {}

local DataService: any = nil
local EconomyService: any = nil
local XPService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local AntiExploitService: any = nil
local NotificationService: any = nil
local RemoteSetup: any = nil

local combatStates: { [number]: CombatState } = {}
local npcRecords: { [string]: NPCRecord } = {}
local npcFolder: Folder? = nil
local npcSerial = 1
local firstPvpLogged: { [number]: boolean } = {}

local function clock(): number
	return os.clock()
end

local function weaponDef(id: string): WeaponDef?
	return WeaponConfig.Weapons[id]
end

local function ensureStarter(profile: PlayerProfile)
	local starter = WeaponConfig.DefaultWeapon
	if typeof(profile.Weapons) ~= "table" then
		profile.Weapons = {}
	end
	if not profile.Weapons[starter] then
		profile.Weapons[starter] = true
	end
	if not profile.EquippedWeapon or not profile.Weapons[profile.EquippedWeapon] then
		profile.EquippedWeapon = starter
	end
end

local function owns(profile: PlayerProfile, weaponId: string): boolean
	return profile.Weapons ~= nil and profile.Weapons[weaponId] == true
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

local function pushState(player: Player)
	local state = combatStates[player.UserId]
	local _, humanoid = characterParts(player)
	local weaponId = if state then state.WeaponId else nil
	local def = if weaponId then weaponDef(weaponId) else nil
	local payload: Types.CombatStatePayload = {
		Health = if humanoid then humanoid.Health else 0,
		MaxHealth = if humanoid then humanoid.MaxHealth else CombatConfig.PlayerMaxHealth,
		WeaponId = weaponId,
		Ammo = if state then state.Ammo else 0,
		MagazineSize = if def then def.MagazineSize else 0,
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
		Ammo = if def then def.MagazineSize else 30,
		ReloadingUntil = 0,
		LastFireAt = 0,
		InvulnerableUntil = 0,
		Alive = true,
		FirstPvpLogged = firstPvpLogged[player.UserId] == true,
	}
	combatStates[player.UserId] = state
	return state
end

local function damageFor(def: WeaponDef): number
	return def.Damage * (def.Pellets or 1)
end

local function tagCreator(humanoid: Humanoid, attacker: Player)
	local existing = humanoid:FindFirstChild("creator")
	if existing then
		existing:Destroy()
	end
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = attacker
	tag.Parent = humanoid
	task.delay(2, function()
		if tag.Parent then
			tag:Destroy()
		end
	end)
end

local function raycast(origin: Vector3, direction: Vector3, range: number, ignore: { Instance }): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local unit = if direction.Magnitude > 1e-4 then direction.Unit else Vector3.new(0, 0, -1)
	return Workspace:Raycast(origin, unit * range, params)
end

function CombatService.GetPlotSpawnCFrame(plotId: number): CFrame?
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			local folder = inst.Parent
			if folder then
				local spawn = folder:FindFirstChild("PlayerSpawn")
				if spawn and spawn:IsA("BasePart") then
					return spawn.CFrame + Vector3.new(0, 3, 0)
				end
			end
			return inst.CFrame + Vector3.new(0, 5, 30)
		end
	end
	local pos = BaseConfig.PlotPositions[plotId]
	if pos then
		return CFrame.new(pos + Vector3.new(0, 5, 30))
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
	if aliveNPCCount() >= CombatConfig.MaxActiveNPCs then
		return nil
	end
	local tid = typeId or CombatConfig.DefaultNPCType
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
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = at
	root.Anchored = false
	root.CanCollide = true
	root.Color = def.Color
	root.Material = Enum.Material.SmoothPlastic
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = at * CFrame.new(0, 1.6, 0)
	head.CanCollide = false
	head.Color = Color3.fromRGB(
		math.clamp(math.floor(def.Color.R * 255) + 20, 0, 255),
		math.clamp(math.floor(def.Color.G * 255), 0, 255),
		math.clamp(math.floor(def.Color.B * 255), 0, 255)
	)
	head.Material = Enum.Material.SmoothPlastic
	head.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = def.Health
	humanoid.Health = def.Health
	humanoid.WalkSpeed = def.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.Parent = model

	model.PrimaryPart = root
	CollectionService:AddTag(model, Constants.Tags.NPC)
	model.Parent = ensureNPCFolder()

	local gyro = Instance.new("BodyGyro")
	gyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	gyro.P = 3000
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

local function nearestPlayer(position: Vector3, maxRange: number): (Player?, number)
	local best: Player? = nil
	local bestDist = maxRange
	for _, player in ipairs(Players:GetPlayers()) do
		local _, hum, root = characterParts(player)
		if hum and root and hum.Health > 0 then
			local d = (root.Position - position).Magnitude
			if d < bestDist then
				bestDist = d
				best = player
			end
		end
	end
	return best, bestDist
end

local function thinkNPCs()
	for _, rec in pairs(npcRecords) do
		if rec.Alive and rec.Humanoid.Health > 0 and rec.Root.Parent then
			local target, dist = nearestPlayer(rec.Root.Position, rec.Def.AggroRange)
			if target then
				local _, th, troot = characterParts(target)
				if th and troot then
					local look = CFrame.lookAt(
						rec.Root.Position,
						Vector3.new(troot.Position.X, rec.Root.Position.Y, troot.Position.Z)
					)
					rec.Root.CFrame = look
					local gyro = rec.Root:FindFirstChildOfClass("BodyGyro")
					if gyro then
						gyro.CFrame = look
					end
					if dist > rec.Def.Range * 0.85 then
						rec.Humanoid:MoveTo(troot.Position)
					else
						rec.Humanoid:MoveTo(rec.Root.Position)
						local interval = 1 / math.max(rec.Def.FireRate, 0.1)
						if clock() - rec.LastFireAt >= interval and dist <= rec.Def.Range then
							rec.LastFireAt = clock()
							local tState = combatStates[target.UserId]
							if not (tState and clock() < tState.InvulnerableUntil) then
								th:TakeDamage(rec.Def.Damage)
								hitFeedback(target, {
									Kind = if th.Health <= 0 then "Death" else "Damaged",
									Damage = rec.Def.Damage,
									TargetName = rec.Def.DisplayName,
								})
								pushState(target)
							end
						end
					end
				end
			end
		end
	end
end

local function gatherSpawns(): { CFrame }
	local list: { CFrame } = {}
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.NPCSpawn)) do
		if inst:IsA("BasePart") then
			table.insert(list, inst.CFrame + Vector3.new(0, 3, 0))
		end
	end
	if CombatConfig.NPCAlsoSpawnNearTerritories then
		local added = 0
		for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.Territory)) do
			if inst:IsA("BasePart") and added < CombatConfig.MaxTerritoryNPCSpawns then
				local offset = Vector3.new(math.random(-20, 20), 3, math.random(-20, 20))
				table.insert(list, inst.CFrame + offset)
				added += 1
			end
		end
	end
	if #list == 0 then
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			table.insert(list, CFrame.new(100 + math.cos(angle) * 60, 4, 100 + math.sin(angle) * 60))
		end
	end
	return list
end

function CombatService.BootstrapNPCs()
	local points = gatherSpawns()
	local types = { "Infantry", "Infantry", "HeavyInfantry" }
	local spawned = 0
	for i, cf in ipairs(points) do
		if spawned >= CombatConfig.MaxActiveNPCs then
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
	if typeof(weaponId) ~= "string" then
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
		state.Ammo = def.MagazineSize
		state.ReloadingUntil = 0
	end
	pushState(player)
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.WEAPON_EQUIPPED, player.UserId, { weapon = weaponId })
	end
	return true, nil
end

function CombatService.PurchaseWeapon(player: Player, weaponId: any): (boolean, string?)
	if typeof(weaponId) ~= "string" then
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
	local cost = def.CostCash or 0
	if cost > 0 then
		local ok, err = EconomyService.SpendCash(player, cost, "weapon_" .. weaponId)
		if not ok then
			return false, err or "SpendFailed"
		end
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
	return true, nil
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
	if state.Ammo >= def.MagazineSize then
		return false, "FullMag"
	end
	local reloadTime = def.ReloadTime
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
		s.Ammo = def.MagazineSize
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

	local minInterval = 1 / math.max(def.FireRate, 0.1)
	if clock() - state.LastFireAt < minInterval * 0.9 then
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
	state.LastFireAt = clock()
	pushState(player)

	local range = def.Range + CombatConfig.HitPositionSlopStuds
	local damage = damageFor(def)
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
			state.Ammo = def.MagazineSize
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
	RemoteSetup = deps.RemoteSetup

	local equipRemote = RemoteSetup.Get(Constants.RemoteNames.RequestEquipWeapon) :: RemoteEvent
	equipRemote.OnServerEvent:Connect(function(player: Player, weaponId: any)
		if not RateLimitService.Allow(player, "equip_weapon", CombatConfig.EquipRemoteRate, CombatConfig.EquipRemoteBurst) then
			return
		end
		local ok, err = CombatService.EquipWeapon(player, weaponId)
		if not ok and NotificationService and err then
			NotificationService.Notify(player, "Cannot equip: " .. tostring(err), "Warn")
		end
	end)

	local purchaseRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseWeapon) :: RemoteEvent
	purchaseRemote.OnServerEvent:Connect(function(player: Player, weaponId: any)
		if not RateLimitService.Allow(player, "buy_weapon", CombatConfig.PurchaseWeaponRate, CombatConfig.PurchaseWeaponBurst) then
			return
		end
		local ok, err = CombatService.PurchaseWeapon(player, weaponId)
		if not ok and NotificationService and err then
			NotificationService.Notify(player, "Cannot buy weapon: " .. tostring(err), "Warn")
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
	local damage = damageFor(def)
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
