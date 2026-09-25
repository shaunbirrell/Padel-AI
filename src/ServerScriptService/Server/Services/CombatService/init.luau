--!strict
--[[
	Phase 3 — Server-authoritative combat.
	Clients request fire/reload/equip/purchase; server validates and applies WeaponConfig damage.

	W2 Combat Core (contracts §1–§3; money plan M4; mobile plan §4.1, P1-5):
	  - RequestFire resolves a hitscan shot in order: exact server ray (player / NPC / registered vehicle / gate;
	    a "Head" part is a headshot x CombatFeelConfig.HeadshotMult) → the P0-7 claim (unchanged lag tolerance) →
	    server aim assist (CombatAssist, AimAssistConfig class limits; the client never names the target) → miss.
	    Damage falls off with distance (WeaponConfig.Falloff). The shot filter leaves out the shooter, the vehicle
	    they sit in and every squad unit. Seat rules come first (drivers per VehicleCombatConfig.SeatFire, open-seat
	    passengers fire from the head, mount and enclosed seats refuse).
	  - Rocket / grenade (WeaponConfig.Projectile) launch a server projectile (Server/Modules/Projectile): direct
	    vehicle / gate hit, then ApplyRadiusDamage (humanoids) + VehicleHealth.ApplyRadiusDamage (vehicles).
	  - WeaponFx (UnreliableRemoteEvent, CombatFx): one bullet event per accepted shot within 250 studs, <= 20 Hz per
	    shooter; projectile launch / explosion events.
	  - Server APIs for other services: ApplyHit, ApplyRadiusDamage, ApplyBlastDamage, IsSpawnInvulnerable,
	    OnPlayerDeath (the DeathShopOffer toast is built-in listener #1).

	F6 novice shield (owner's 11 features, CombatFairnessConfig.NoviceShield; off until lane Z):
	  - A player whose save says the tutorial is not complete and NoviceShieldDone is false is shielded for this
	    session: InvulnerableUntil = math.huge (so every damage path here, CombatNPC's hit roll and the assist skip
	    them), the replicated character attribute WE_ShieldUntil and a visible server ForceField "WE_NoviceShield".
	    It survives respawns. GateDefenseService guards skip them (SetShieldCheck, injected from Init).
	  - It ends for good (profile.NoviceShieldDone = true, one Text.Off toast) on the first of: drawing a weapon, the
	    first accepted shot (before any hit resolves), an accepted squad order or missile strike, contesting a zone,
	    tutorial complete or skip, holding an ATM raid or entering the Empire Bank's guard ring (1 Hz sweep), or
	    MaxSeconds of play this session. Never re-granted.
	  - A shielded player deals no damage to other players, their vehicles or gates: such a hit ends the shield first.
	  - APIs: IsNoviceShielded(player) -> boolean, EndNoviceShield(player, reason) -> boolean (true = it ended now).

	W3 step 2 Phase B, lane N NPC core (contract §5): SpawnNPC(type, at, opts?) takes NPCSpawnOpts (GroupId,
	NoRespawn, Home, Leash, Stance, ProvokeRadius, OverCap, Static); with no opts every call behaves as before.
	The cap is MaxActiveNPCs regular, + SpecialOverCap for CombatConfig.SpecialNPCTypes and opts.OverCap. A player
	hurting a grouped NPC provokes its group. APIs: OnNPCDeath(fn) (once per death, after rewards; listeners
	deferred, each in its own pcall), DespawnNPC(id) (silent), ProvokeGroup / CalmGroup / GroupNPCs(groupId),
	NPCCounts(). CombatConfig.FieldBootstrap == false skips BootstrapNPCs. Stances live in CombatNPC.Think.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local CombatConfig = require(Shared.Configs.CombatConfig)
local GameConfig = require(Shared.Configs.GameConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local ResearchConfig = require(Shared.Configs.ResearchConfig) -- v69 research
local CombatFairnessConfig = require(Shared.Configs.CombatFairnessConfig) -- mobile plan P0-7 / P1-2 / P1-4
local AimAssistConfig = require(Shared.Configs.AimAssistConfig) -- W2
local CombatFeelConfig = require(Shared.Configs.CombatFeelConfig) -- W2
local VehicleCombatConfig = require(Shared.Configs.VehicleCombatConfig) -- W2 (M4)
local VehicleConfig = require(Shared.Configs.VehicleConfig) -- W2: vehicle names in hit feedback
local BankRaidConfig = require(Shared.Configs.BankRaidConfig) -- F6: the guarded bank ends a novice shield

local CombatDamage = require(script.CombatDamage)
local CombatNPC = require(script.CombatNPC)
local CombatWeaponLogic = require(script.CombatWeaponLogic)
local VisualAssetService = require(script.Parent.VisualAssetService)
local CombatAssist = require(script.CombatAssist) -- W2
local CombatFx = require(script.CombatFx) -- W2
local VehicleHealth = require(script.Parent.Parent.Modules.VehicleHealth) -- W2 (CC-2; every call pcall'd)
local Projectile = require(script.Parent.Parent.Modules.Projectile) -- W2
local WeaponAssetLoader = require(script.Parent.Parent.Modules.WeaponAssetLoader) -- W2

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
	AimTarget: Player?, -- P1-2: the player this NPC is aiming at (CombatNPC reaction delay)
	AimSince: number,
	AimBlocked: boolean, -- P1-2: the last line-of-sight check failed (the reaction delay restarts on regaining sight)
	KillCtx: { Quiet: boolean?, NoKillMarker: boolean? }?, -- W2: set around TakeDamage so an immediate Died pays quietly
	-- W3 step 2 Phase B, lane N (SpawnNPC opts; a 2-argument spawn gets the defaults, i.e. today's NPC)
	GroupId: string?, -- an Ops site id; ProvokeGroup / CalmGroup / GroupNPCs / OnNPCDeath carry it
	NoRespawn: boolean, -- never respawned
	Home: CFrame, -- leash home and calm-down point (default: the spawn CFrame)
	Leash: number?, -- flat studs from Home (nil: no leash)
	Stance: string, -- "Aggressive" (default) | "Passive" | "Post"
	ProvokeRadius: number?, -- Passive: an on-foot player this close to Home provokes the group
	Static: boolean, -- WE_Static: never MoveTo (implies Post)
	OverCap: boolean, -- may use the SpecialOverCap headroom
	SpawnOpts: NPCSpawnOpts?, -- a copy of the opts, reused by a respawn (nil for a 2-argument spawn)
	Returning: boolean, -- walking back past the leash (targets ignored until home)
	DeathFired: boolean, -- OnNPCDeath fired (or silenced by DespawnNPC): once per death
}

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local BaseLayout = require(script.Parent.Parent.Modules.BaseLayout) -- v70: plot frame

local CombatService = {}

-- W2 (contracts §3): server damage API types
export type HitOpts = {
	WeaponId: string, -- WeaponConfig id | "V_<MountId>" (M6 vehicle guns) | a source id ("VehicleWreck", "Missile", "Nuke")
	Class: string?, -- VehicleCombatConfig.DamageClasses key for VEHICLE damage (default by WeaponId)
	WeaponMult: number?, -- vehicle WeaponMult (default InfantryWeapons[WeaponId].Mult or 1)
	VsInfantryMult: number?, -- x against players and NPCs (default 1)
	HitPos: Vector3?, -- world point (feedback Pos)
	Vehicle: Model?, -- the FIRING vehicle (M6): never damaged; its occupants never hit; rookie protection vs players
	Headshot: boolean?, -- only RequestFire's exact-ray Head hit sets this
	Quiet: boolean?, -- no attacker hitFeedback, no per-kill toast (NPC rewards still paid)
	UnitShot: boolean?, -- creator tag carries WE_UnitShot (squad credit share)
	Assist: boolean?, -- feedback only: the server assist chose this target (RequestFire)
}
export type HitResult = { Kind: string, Dealt: number, Killed: boolean, Target: Instance? }
export type RadiusOpts = {
	WeaponId: string,
	MinMult: number?,
	VsInfantryMult: number?,
	Vehicle: Model?,
	RequireLos: boolean?,
	Quiet: boolean?,
	IgnoreModel: Model?,
}
export type RadiusResult = { Players: number, Npcs: number, Killed: number, Dealt: number }
export type DeathInfo = { WeaponId: string?, BlastSource: string?, Quiet: boolean }
-- W3 step 2 Phase B, lane N (contract §5.2)
export type NPCSpawnOpts = {
	GroupId: string?, -- an Ops site id ("Town.Bank"); ProvokeGroup / CalmGroup / GroupNPCs / OnNPCDeath carry it
	NoRespawn: boolean?, -- never respawned (neither after a kill nor after a death with no killer)
	Home: CFrame?, -- leash home and calm-down point (default: the spawn CFrame `at`)
	Leash: number?, -- studs from Home; nil = no leash (today)
	Stance: string?, -- "Aggressive" (nil = today) | "Passive" | "Post"
	ProvokeRadius: number?, -- Passive only (default: never provoked by proximity)
	OverCap: boolean?, -- may use the SpecialOverCap headroom like a special type (event NPCs)
	Static: boolean?, -- model attribute WE_Static = true; never MoveTo (tower deck, interior); implies Stance "Post"
}
export type NPCInfo = { Id: string, TypeId: string, GroupId: string?, Alive: boolean, Position: Vector3, Provoked: boolean, Stance: string }
export type NPCDeathInfo = { Id: string, TypeId: string, GroupId: string?, Killer: Player?, ByUnit: boolean, Position: Vector3 }

-- feedback / credit switches for one damage call (internal)
type FbOpts = {
	Headshot: boolean?,
	Pos: Vector3?,
	Assist: boolean?,
	Quiet: boolean?, -- no attacker feedback and no kill toast (rewards still paid)
	NoAttackerFb: boolean?, -- no per-target attacker feedback (splash sends one aggregate)
	NoKillMarker: boolean?, -- no per-NPC "Kill" marker (splash)
	UnitShot: boolean?,
}

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
local ClanService: any = nil -- W2: clan allies are never assisted / splashed (deps.ClanService; pcall)

local combatStates: { [number]: CombatState } = {}
local gunSchedule: { [number]: { [string]: number } } = {} -- v69 research: per-gun GCRA time (swaps can't skip a slow gun's cooldown)
local npcRecords: { [string]: NPCRecord } = {}
local npcFolder: Folder? = nil
local npcSerial = 1
local firstPvpLogged: { [number]: boolean } = {}
-- W2 per-player / per-humanoid state, grouped in one table (keeps the module's local count low)
local W2 = {
	inputClass = {} :: { [number]: string }, -- accepted AimAssistConfig class (mirrors Player.WE_InputClass)
	inputClassAt = {} :: { [number]: number },
	deathListeners = {} :: { { Fn: (Player, Player?, DeathInfo) -> () } },
	deathHandled = (setmetatable({}, { __mode = "k" }) :: any) :: { [Humanoid]: boolean }, -- once per death
	aimStats = {} :: { [string]: { [string]: number } }, -- class -> { Exact, Claim, Assist, Miss }
	aimStatsLoggedAt = 0,
}
-- F6 novice shield: per-player session state and helpers, grouped in one table like W2 (functions further down)
local NS = {
	ForceField = "WE_NoviceShield", -- the server ForceField's name
	Active = {} :: { [number]: { Deadline: number, OnToasted: boolean } }, -- userId -> shielded this session
	SweepRunning = false,
	-- EndNoviceShield reason -> the CombatFairnessConfig.NoviceShield switch that allows it (other reasons always end it)
	ReasonFlag = {
		draw = "EndOnDraw",
		fire = "EndOnFire",
		order = "EndOnSquadOrder",
		strike = "EndOnSquadOrder",
		contest = "EndOnContestedCapture",
		tutorial = "EndOnTutorialComplete",
	} :: { [string]: string },
}

-- W3 step 2 Phase B, lane N: NPC death listeners (OnNPCDeath)
local NPCCore = {
	deathListeners = {} :: { { Fn: (NPCDeathInfo) -> () } },
}

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
	-- W2: the client shows damage numbers unless Settings.ShowDamageNumbers is false
	local settings: any = profile.Settings
	local showNumbers = not (typeof(settings) == "table" and settings.ShowDamageNumbers == false)
	local attr = CombatFeelConfig.DamageNumbersAttribute
	if player:GetAttribute(attr) ~= showNumbers then
		player:SetAttribute(attr, showNumbers)
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
	pcall(remote.FireClient, remote, player, payload) -- W2: a player who just left never breaks the shot
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

-- ── F6 novice shield (owner's 11 features; CombatFairnessConfig.NoviceShield) ─────────────────────────────────
function NS.cfg(): any
	return (CombatFairnessConfig :: any).NoviceShield
end

function NS.serverNow(): number
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	return if ok and typeof(t) == "number" then t else os.time()
end

-- one character (idempotent): the replicated end time (the MaxSeconds cap; client bubble fallback and AimTargets
-- read it) and the visible server ForceField
function NS.dress(player: Player, character: Model?)
	local rec = NS.Active[player.UserId]
	if rec == nil or character == nil or character.Parent == nil then
		return
	end
	character:SetAttribute(CombatFeelConfig.ShieldAttribute, NS.serverNow() + math.max(0, rec.Deadline - clock()))
	if character:FindFirstChild(NS.ForceField) == nil then
		local ff = Instance.new("ForceField")
		ff.Name = NS.ForceField
		ff.Visible = true
		ff.Parent = character
	end
end

-- (re)apply to the combat state and the current character; the Text.On toast once per session
function NS.apply(player: Player, character: Model?)
	local rec = NS.Active[player.UserId]
	if rec == nil then
		return
	end
	local state = combatStates[player.UserId]
	if state then
		state.InvulnerableUntil = math.huge
	end
	NS.dress(player, character)
	local cfg = NS.cfg()
	if not rec.OnToasted and NotificationService and typeof(cfg) == "table" and typeof(cfg.Text) == "table" then
		rec.OnToasted = true
		-- a short delay so the client's toast stack is listening on a fresh join (optional config key)
		task.delay(tonumber(cfg.OnToastDelaySeconds) or 3, function()
			if NS.Active[player.UserId] == rec and player.Parent ~= nil then
				NotificationService.Notify(player, cfg.Text.On, "Info")
			end
		end)
	end
end

-- A shielded player who holds an ATM raid (WE_RaidingPlot) or walks inside the Empire Bank's guard ring: the
-- bank vault is guarded only by NPCs, whose shots skip InvulnerableUntil = math.huge, so an unended shield would
-- loot the vault for free (every rejoin re-grants the shield). Ends it for good (reason "raid", no config switch).
function NS.engaging(player: Player): boolean
	if player:GetAttribute("WE_RaidingPlot") ~= nil then
		return true
	end
	if BankRaidConfig.Enabled ~= true then
		return false
	end
	local _, _, root = characterParts(player)
	if root == nil then
		return false
	end
	local r = math.max(tonumber(BankRaidConfig.VaultRadius) or 12, tonumber(BankRaidConfig.GuardRingRadius) or 18)
	for _, inst in ipairs(getTaggedCached(Constants.Tags.BankVault)) do
		if inst:IsA("BasePart") and (inst.Position - root.Position).Magnitude <= r then
			return true
		end
	end
	return false
end

-- 1 Hz while anyone is shielded: the MaxSeconds cap, and the tutorial ending (complete or skip) even when no
-- other service calls EndNoviceShield
function NS.sweep()
	local t = clock()
	for uid, rec in pairs(NS.Active) do
		local player = Players:GetPlayerByUserId(uid)
		if player == nil then
			NS.Active[uid] = nil
		elseif t >= rec.Deadline then
			CombatService.EndNoviceShield(player, "timeout")
		elseif NS.engaging(player) then
			CombatService.EndNoviceShield(player, "raid")
		else
			local profile = DataService and DataService.GetProfile(player)
			if profile and profile.TutorialComplete == true then
				CombatService.EndNoviceShield(player, "tutorial")
			end
		end
	end
end

function NS.startSweep()
	if NS.SweepRunning then
		return
	end
	NS.SweepRunning = true
	task.spawn(function()
		while next(NS.Active) ~= nil do
			task.wait(1)
			local ok, err = pcall(function()
				NS.sweep()
			end)
			if not ok then
				warn("[CombatService] novice shield sweep:", err)
			end
		end
		NS.SweepRunning = false
	end)
end

-- the real save is in: shielded this session iff the flag is on, the tutorial is not complete and it never ended
function NS.onLoad(player: Player, profile: any)
	local cfg = NS.cfg()
	if typeof(cfg) ~= "table" or cfg.Enabled ~= true or typeof(profile) ~= "table" then
		return
	end
	if profile.TutorialComplete == true or profile.NoviceShieldDone == true or NS.Active[player.UserId] ~= nil then
		return
	end
	NS.Active[player.UserId] = { Deadline = clock() + math.max(0, tonumber(cfg.MaxSeconds) or 900), OnToasted = false }
	NS.apply(player, player.Character)
	NS.startSweep()
end

-- May `attacker` hurt another player, a vehicle or a gate? A shielded attacker's hit ends the shield first
-- (reason "fire", EndOnFire); with that switch off nothing lands. nil (no attacker) is always allowed.
function NS.allowsAttack(attacker: Player?): boolean
	return attacker == nil or NS.Active[attacker.UserId] == nil or CombatService.EndNoviceShield(attacker, "fire")
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

local function tagCreator(humanoid: Humanoid, attacker: Player, unitShot: boolean?)
	CombatDamage.TagCreator(humanoid, attacker, unitShot)
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

-- W2: opts.Quiet (a blast death, nuke §15.2) keeps stats, missions and rewards but sends no "Eliminated" toast
function CombatService.RegisterPlayerKill(attacker: Player, victim: Player, opts: { Quiet: boolean? }?)
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
	if NotificationService and not (opts and opts.Quiet == true) then
		NotificationService.Notify(
			attacker,
			string.format("Eliminated %s (+$%d)", victim.DisplayName, CombatConfig.PlayerKill.Cash),
			"Reward"
		)
	end
end

--[[ Damage one player. With an attacker: PvP, self (FriendlyFire) and the spawn shield apply, and the creator tag
	credits the kill. With no attacker (a wreck with no killer): only the spawn shield applies and nobody is credited.
	Returns (dealt, killed). W2: also records WE_LastWeapon (DeathInfo) and the richer feedback fields. ]]
local function hurtPlayer(attacker: Player?, victim: Player, damage: number, weaponId: string, fb: FbOpts?): (number, boolean)
	if attacker ~= nil then
		if not GameConfig.PvPEnabled then
			return 0, false
		end
		if attacker == victim and not GameConfig.FriendlyFire then
			return 0, false
		end
		if attacker ~= victim and not NS.allowsAttack(attacker) then -- F6: a shielded player deals no PvP damage
			return 0, false
		end
	end
	local vState = combatStates[victim.UserId]
	if vState and clock() < vState.InvulnerableUntil then
		return 0, false
	end
	local _, humanoid = characterParts(victim)
	if not humanoid or humanoid.Health <= 0 then
		return 0, false
	end
	if not (damage > 0) then -- NaN / negative never heal or poison a humanoid
		return 0, false
	end
	if attacker then
		tagCreator(humanoid, attacker, fb and fb.UnitShot)
	end
	humanoid:SetAttribute("WE_LastWeapon", weaponId)
	local before = humanoid.Health
	humanoid:TakeDamage(damage)
	local dealt = math.max(0, before - humanoid.Health)
	if dealt <= 0 then
		return 0, false
	end
	local killed = humanoid.Health <= 0
	local from: Vector3? = nil
	if attacker then
		local _, _, aroot = characterParts(attacker)
		from = if aroot then aroot.Position else nil
		if not (fb and (fb.Quiet == true or fb.NoAttackerFb == true)) then
			hitFeedback(attacker, {
				Kind = if killed then "Kill" else "Hit",
				Damage = dealt,
				TargetName = victim.DisplayName,
				WeaponId = weaponId,
				IsHeadshot = fb ~= nil and fb.Headshot == true,
				Target = victim.Character, -- W2 (display only)
				TargetKind = "Player",
				Pos = if fb then fb.Pos else nil,
				Assist = if fb and fb.Assist then true else nil,
			})
		end
	end
	hitFeedback(victim, {
		Kind = if killed then "Death" else "Damaged",
		Damage = dealt,
		WeaponId = weaponId,
		From = from, -- W2: direction cue
	})
	pushState(victim)
	return dealt, killed
end

local function damagePlayer(attacker: Player, victim: Player, damage: number, weaponId: string): boolean
	local dealt = hurtPlayer(attacker, victim, damage, weaponId, nil)
	return dealt > 0
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
	CombatFx.Forget(rec.Id) -- W2 verify: its WeaponFx shooter bucket goes too (NPC ids never repeat)
	CombatNPC.ForgetRecord(npcRecords, rec) -- lane N: its group's stance state goes with the last member
	if rec.Model and rec.Model.Parent then
		rec.Model:Destroy()
	end
end

--[[ Lane N: OnNPCDeath, once per death (DeathFired), after rewards. The listeners run deferred (a death can happen
	inside a damage loop over the NPC records, and a listener may spawn or despawn NPCs), each in its own pcall.
	Nothing is scheduled while no listener is registered. ]]
local function fireNPCDeath(rec: NPCRecord, killer: Player?, byUnit: boolean)
	if rec.DeathFired then
		return
	end
	rec.DeathFired = true
	if #NPCCore.deathListeners == 0 then
		return
	end
	local info: NPCDeathInfo = {
		Id = rec.Id,
		TypeId = rec.TypeId,
		GroupId = rec.GroupId,
		Killer = killer,
		ByUnit = byUnit,
		Position = rec.Root.Position,
	}
	local list = table.clone(NPCCore.deathListeners)
	task.defer(function()
		for _, entry in ipairs(list) do
			xpcall(entry.Fn, function(err: any)
				warn("[CombatService] OnNPCDeath listener error:", err)
			end, info)
		end
	end)
end

-- W2 (F hand-off): per-type respawn time (CombatConfig.NPCTypes[*].RespawnSeconds), else the global one
local function npcRespawnSeconds(rec: NPCRecord): number
	local t = tonumber((rec.Def :: any).RespawnSeconds)
	return if t and t > 0 then t else CombatConfig.NPCRespawnSeconds
end

-- `byUnit` (P1-4): the killing hit came from the attacker's squad unit — CombatFairnessConfig.UnitKillCashShare
-- W2: `quiet` (blast kills, nuke §15.2) pays rewards, missions and stats with no toast and no kill marker;
-- `noMarker` (splash) keeps the toast but leaves the kill marker to the one aggregated splash feedback.
function CombatService.OnNPCKilled(attacker: Player, rec: NPCRecord, byUnit: boolean?, quiet: boolean?, noMarker: boolean?)
	if not rec.Alive then
		return
	end
	rec.Alive = false
	local cash = rec.Def.CashReward
	local xp = rec.Def.XPReward
	if byUnit then
		cash = math.floor(cash * math.clamp(CombatFairnessConfig.UnitKillCashShare, 0, 1) + 0.5)
		xp = math.floor(xp * math.clamp(CombatFairnessConfig.UnitKillXPShare, 0, 1) + 0.5)
	end
	grantRewards(attacker, cash, xp, if byUnit then "npc_kill_squad" else "npc_kill")
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
			squad = byUnit == true,
		})
	end
	if NotificationService and quiet ~= true then
		local fmt = if byUnit then "Squad: %s down (+$%d)" else "%s down (+$%d)"
		NotificationService.Notify(attacker, string.format(fmt, rec.Def.DisplayName, cash), "Reward")
	end
	if not byUnit and quiet ~= true and noMarker ~= true then -- the kill marker belongs to the player's own shot
		hitFeedback(attacker, { Kind = "Kill", Damage = 0, TargetName = rec.Def.DisplayName, WeaponId = nil })
	end
	local spawnCf = rec.SpawnCFrame
	local typeId = rec.TypeId
	task.delay(0.35, function()
		destroyNPC(rec)
	end)
	fireNPCDeath(rec, attacker, byUnit == true) -- lane N
	if rec.NoRespawn then
		return -- lane N: an Ops garrison NPC is never respawned
	end
	local spawnOpts = rec.SpawnOpts
	task.delay(npcRespawnSeconds(rec), function()
		CombatService.SpawnNPC(typeId, spawnCf, spawnOpts)
	end)
end

--[[ Damage one NPC record. Returns (dealt, killed). With no attacker nobody is credited (the Died handler respawns
	it). W2: fb carries the feedback / credit switches (quiet blast kills, splash aggregation, squad unit shots). ]]
local function hurtNPC(attacker: Player?, npcId: string, damage: number, weaponId: string, fb: FbOpts?): (number, boolean)
	local rec = npcRecords[npcId]
	if not rec or not rec.Alive or rec.Humanoid.Health <= 0 then
		return 0, false
	end
	if not (damage > 0) then
		return 0, false
	end
	if attacker then
		tagCreator(rec.Humanoid, attacker, fb and fb.UnitShot)
	end
	local before = rec.Humanoid.Health
	-- W2: Died may fire inside TakeDamage (immediate signals); its handler reads this to pay the kill quietly
	rec.KillCtx = if fb then { Quiet = fb.Quiet, NoKillMarker = fb.NoKillMarker } else nil
	rec.Humanoid:TakeDamage(damage)
	rec.KillCtx = nil
	local dealt = math.max(0, before - rec.Humanoid.Health)
	if dealt <= 0 then
		return 0, false
	end
	local killed = rec.Humanoid.Health <= 0
	local quiet = fb ~= nil and fb.Quiet == true
	if attacker and (rec.GroupId ~= nil or rec.Stance ~= "Aggressive") then
		-- lane N: a player (or their squad unit) hurting a grouped / Passive NPC provokes its whole group
		CombatNPC.ProvokeGroup(npcRecords, rec.GroupId or rec.Id, nil, clock())
	end
	if attacker and not quiet and not (fb and fb.NoAttackerFb == true) then
		hitFeedback(attacker, {
			Kind = if killed then "Kill" else "Hit",
			Damage = dealt,
			TargetName = rec.Def.DisplayName,
			WeaponId = weaponId,
			IsHeadshot = if fb and fb.Headshot then true else nil, -- W2
			Target = rec.Model,
			TargetKind = "NPC",
			Pos = if fb then fb.Pos else nil,
			Assist = if fb and fb.Assist then true else nil,
		})
	end
	if killed and attacker then
		CombatService.OnNPCKilled(attacker, rec, if fb and fb.UnitShot then true else nil, quiet, fb ~= nil and fb.NoKillMarker == true)
	end
	return dealt, killed
end

local function damageNPC(attacker: Player, npcId: string, damage: number, weaponId: string): boolean
	local dealt = hurtNPC(attacker, npcId, damage, weaponId, nil)
	return dealt > 0
end

--[[ Lane N: SpawnNPC opts, sanitised (server callers only, but never trusted blindly). nil / not a table = today's
	NPC: Aggressive, no leash, no group, respawns at `at`. ]]
local function npcSpawnOpts(opts: any, at: CFrame)
	local o = if typeof(opts) == "table" then opts else nil
	local static = o ~= nil and o.Static == true
	local stance = "Aggressive"
	if static then
		stance = "Post" -- Static implies Post
	elseif o ~= nil and (o.Stance == "Passive" or o.Stance == "Post") then
		stance = o.Stance
	end
	local function posNum(v: any, max: number): number?
		return if typeof(v) == "number" and v > 0 and v < max then v else nil
	end
	local gid = if o ~= nil and typeof(o.GroupId) == "string" and #o.GroupId > 0 and #o.GroupId <= 64 then o.GroupId else nil
	return {
		GroupId = gid :: string?,
		NoRespawn = o ~= nil and o.NoRespawn == true,
		Home = if o ~= nil and typeof(o.Home) == "CFrame" then o.Home :: CFrame else at,
		Leash = if o ~= nil then posNum(o.Leash, 1e5) else nil,
		Stance = stance,
		ProvokeRadius = if o ~= nil then posNum(o.ProvokeRadius, 1e4) else nil,
		OverCap = o ~= nil and o.OverCap == true,
		Static = static,
		Copy = if o ~= nil then (table.clone(o) :: any) :: NPCSpawnOpts else nil,
	}
end

function CombatService.SpawnNPC(typeId: string?, at: CFrame, opts: NPCSpawnOpts?): NPCRecord?
	local tid = typeId or CombatConfig.DefaultNPCType
	local o = npcSpawnOpts(opts, at)
	-- lane N: the special list comes from config (BankGuard / OilRigGuard / FortGuard); opts.OverCap counts as special
	local isSpecial = table.find(CombatConfig.SpecialNPCTypes, tid) ~= nil or o.OverCap
	local cap = CombatConfig.MaxActiveNPCs or 18
	-- Special guards may exceed soft field pool by SpecialOverCap (+4) so bank always gets guards
	if aliveNPCCount() >= (if isSpecial then cap + CombatConfig.SpecialOverCap else cap) then
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
	if o.Static then
		model:SetAttribute("WE_Static", true) -- lane N: a tower-deck / interior post that never walks
	end

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
	local isHeavy = tid == "HeavyInfantry" or tid == "OilRigGuard" or tid == "FortGuard" or tid == "CampCommander"
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
	-- Kill double nametags: Humanoid nameplate OFF (W2: and no server Billboard; see below)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
	humanoid.Parent = model

	-- W2 (agent F hand-off): no server name card (was an AlwaysOnTop BillboardGui per NPC, MaxDistance 90). The
	-- client target bar (WeaponVisuals) shows the name and HP for 2.5 s after your hit.

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
		AimTarget = nil,
		AimSince = 0,
		AimBlocked = false,
		KillCtx = nil,
		GroupId = o.GroupId,
		NoRespawn = o.NoRespawn,
		Home = o.Home,
		Leash = o.Leash,
		Stance = o.Stance,
		ProvokeRadius = o.ProvokeRadius,
		Static = o.Static,
		OverCap = o.OverCap,
		SpawnOpts = o.Copy,
		Returning = false,
		DeathFired = false,
	}
	npcRecords[id] = rec
	CombatNPC.JoinGroup(npcRecords, rec) -- lane N (no-op for a 2-argument spawn)

	humanoid.Died:Connect(function()
		if not rec.Alive then
			return
		end
		local killer: Player? = nil
		local byUnit = false
		local tag = humanoid:FindFirstChild("creator")
		if tag and tag:IsA("ObjectValue") and tag.Value and tag.Value:IsA("Player") then
			killer = tag.Value :: Player
			byUnit = tag:GetAttribute("WE_UnitShot") == true -- P1-4: a squad unit's hit, credited to its owner
		end
		if killer then
			local ctx = rec.KillCtx -- W2: a quiet / splash hit that is still inside TakeDamage
			CombatService.OnNPCKilled(killer, rec, byUnit, ctx ~= nil and ctx.Quiet == true, ctx ~= nil and ctx.NoKillMarker == true)
		else
			local spawnCf = rec.SpawnCFrame
			local t = rec.TypeId
			task.delay(0.35, function()
				destroyNPC(rec)
			end)
			fireNPCDeath(rec, nil, false) -- lane N: no killer
			if not rec.NoRespawn then
				local spawnOpts = rec.SpawnOpts
				task.delay(npcRespawnSeconds(rec), function()
					CombatService.SpawnNPC(t, spawnCf, spawnOpts)
				end)
			end
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

--[[ Lane N (contract §5.2): `fn(info)` once per NPC death (grouped or not, with or without a killer), after the
	kill rewards. Listeners run deferred, in registration order, each in its own pcall. Returns a disconnect. ]]
function CombatService.OnNPCDeath(fn: (info: NPCDeathInfo) -> ()): () -> ()
	local entry = { Fn = fn }
	table.insert(NPCCore.deathListeners, entry)
	return function()
		local i = table.find(NPCCore.deathListeners, entry)
		if i then
			table.remove(NPCCore.deathListeners, i)
		end
	end
end

-- Lane N: silent removal (sleeping garrisons, site resets): no reward, no respawn, no OnNPCDeath. false if unknown.
function CombatService.DespawnNPC(id: string): boolean
	if typeof(id) ~= "string" then
		return false
	end
	local rec = npcRecords[id]
	if not rec then
		return false
	end
	rec.DeathFired = true -- never reported as a death
	rec.Alive = false -- a Died fired by the removal pays nothing and respawns nothing
	destroyNPC(rec)
	return true
end

--[[ Lane N: provoke a group: its Passive (and passive-group Post) members fight until `seconds` (default
	CombatConfig.NPCStance.CalmSeconds) after the group's last contact. Returns how many living members it has. ]]
function CombatService.ProvokeGroup(groupId: string, seconds: number?): number
	if typeof(groupId) ~= "string" then
		return 0
	end
	return CombatNPC.ProvokeGroup(npcRecords, groupId, seconds, clock())
end

-- Lane N: a provoked group calms now; its Passive members walk Home. Returns how many were calmed.
function CombatService.CalmGroup(groupId: string): number
	if typeof(groupId) ~= "string" then
		return 0
	end
	return CombatNPC.CalmGroup(npcRecords, groupId)
end

-- Lane N: the group's living NPCs, as a copy (never call it per frame)
function CombatService.GroupNPCs(groupId: string): { NPCInfo }
	local out: { NPCInfo } = {}
	if typeof(groupId) ~= "string" then
		return out
	end
	for _, rec in pairs(npcRecords) do
		if rec.Alive and rec.GroupId == groupId and rec.Humanoid.Health > 0 then
			table.insert(out, {
				Id = rec.Id,
				TypeId = rec.TypeId,
				GroupId = rec.GroupId,
				Alive = true,
				Position = rec.Root.Position,
				Provoked = CombatNPC.IsProvoked(rec),
				Stance = rec.Stance,
			})
		end
	end
	return out
end

-- Lane N: living NPCs against the cap (Special = CombatConfig.SpecialNPCTypes + OverCap; Regular <= 18, Total <= 22)
function CombatService.NPCCounts(): { Regular: number, Special: number, Total: number }
	local regular, special = 0, 0
	for _, rec in pairs(npcRecords) do
		if rec.Alive then
			if rec.OverCap or table.find(CombatConfig.SpecialNPCTypes, rec.TypeId) ~= nil then
				special += 1
			else
				regular += 1
			end
		end
	end
	return { Regular = regular, Special = special, Total = regular + special }
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
	local char = player.Character -- W2: a drawn gun switches to the new weapon (WE_GunOut)
	if char and char:GetAttribute(CombatFeelConfig.Drawn.Attribute) ~= nil then
		char:SetAttribute(CombatFeelConfig.Drawn.Attribute, weaponId)
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

-- ── P0-7 (mobile plan): the server never trusts a client-named target on its own ───────────────────────────
local claimRefusals: { [number]: { At: number, Suppressed: number } } = {}

local function logClaimRefusal(player: Player, reason: string, target: string)
	local t = clock()
	local entry = claimRefusals[player.UserId]
	if entry and t - entry.At < CombatFairnessConfig.RefusalLogSeconds then
		entry.Suppressed += 1
		return
	end
	local suppressed = if entry then entry.Suppressed else 0
	claimRefusals[player.UserId] = { At = t, Suppressed = 0 }
	print(string.format("[CombatService] claimed target refused: %s (%d) -> %s: %s (+%d not logged)", player.Name, player.UserId, target, reason, suppressed))
end

local function torsoOf(model: Model, root: BasePart): BasePart
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return root
end

--[[ A claimed target counts only if its torso is in front of the fire ray (0 < along <= maxAlong), within `range` of
	the origin, at most CombatFairnessConfig.MissTolerance studs sideways of the ray, and a server ray from the origin
	to that torso (the shot's own filter: only the shooter is excluded) touches the target before anything else. ]]
local function validateClaim(
	shooter: Model,
	origin: Vector3,
	direction: Vector3,
	range: number,
	maxAlong: number,
	target: Model,
	torsoPos: Vector3
): (boolean, string)
	local v = torsoPos - origin
	local along = v:Dot(direction)
	if not (along > 0) then -- NaN-safe: a NaN along fails here (and would pass every check below)
		return false, "behind the shot"
	end
	if v.Magnitude > range then
		return false, string.format("out of range %.0f > %.0f", v.Magnitude, range)
	end
	if along > maxAlong then
		return false, "beyond what the shot hit"
	end
	local lateral = (v - direction * along).Magnitude
	if lateral > CombatFairnessConfig.MissTolerance then
		return false, string.format("%.1f studs off the ray", lateral)
	end
	if not CombatDamage.LineOfSight(origin, torsoPos, { shooter }, target, false, CombatFairnessConfig.ClaimLosPastTorsoStuds) then
		return false, "no line of sight"
	end
	return true, "ok"
end

-- ── W2 Combat Core: target resolution, seat rules, damage APIs ─────────────────────────────────────────────

local FX_KIND: { [string]: string } = { Player = "P", NPC = "N", Vehicle = "V", Gate = "G" }

-- The registered vehicle a part belongs to (and its VehicleHealth record), or nil. Every call is pcall'd.
local function registeredVehicle(inst: Instance): (Model?, any)
	local ok, model = pcall(VehicleHealth.FindVehicleModel, inst)
	if not ok or typeof(model) ~= "Instance" then
		return nil, nil
	end
	local okRec, rec = pcall(VehicleHealth.Get, model :: Model)
	if not okRec or rec == nil then
		return nil, nil
	end
	return model :: Model, rec
end

-- (seated vehicle model, seat part) of a player, pcall'd
local function seatedVehicle(player: Player): (Model?, BasePart?)
	local ok, veh, seat = pcall(VehicleHealth.GetSeatedVehicle, player)
	if not ok then
		return nil, nil
	end
	local v: Model? = if typeof(veh) == "Instance" and (veh :: Instance):IsA("Model") then veh :: Model else nil
	local s: BasePart? = if typeof(seat) == "Instance" and (seat :: Instance):IsA("BasePart") then seat :: BasePart else nil
	return v, s
end

-- true while the player sits in an ENCLOSED seat (WE_Exposed == false) of a live registered vehicle
local function inEnclosedSeat(veh: Model?, seat: BasePart?): boolean
	if veh == nil or seat == nil or seat:GetAttribute("WE_Exposed") ~= false then
		return false
	end
	local _, rec = registeredVehicle(seat)
	return rec ~= nil and rec.Destroyed ~= true
end

--[[ What a ray / hit part belongs to, first match wins (contracts §3.1):
	"Player" (ancestor character), "NPC" (WE_NPC model with an NPCId), "Vehicle" (registered), "Gate" (GateBarrier
	part), "NPC" with no id (a tagged model outside the NPC records: decides the shot, takes no damage), "None". ]]
local function resolveTarget(inst: Instance): (string, any, Model?)
	local node: Instance? = inst
	local taggedNoId: Model? = nil
	while node ~= nil and node ~= Workspace do
		if node:IsA("Model") then
			local plr = Players:GetPlayerFromCharacter(node)
			if plr then
				return "Player", plr, node :: Model
			end
			if CollectionService:HasTag(node, Constants.Tags.NPC) then
				local npcId = node:GetAttribute("NPCId")
				if typeof(npcId) == "string" then
					return "NPC", npcId, node :: Model
				end
				taggedNoId = taggedNoId or node :: Model
			end
		end
		node = node.Parent
	end
	local veh = registeredVehicle(inst)
	if veh then
		return "Vehicle", veh, veh
	end
	if inst:IsA("BasePart") and inst:GetAttribute("GateBarrier") == true then
		return "Gate", inst, nil
	end
	if taggedNoId then
		return "NPC", nil, taggedNoId
	end
	return "None", nil, nil
end

-- VehicleCombatConfig damage class + WeaponMult for a weapon id (explicit values win)
local function vehicleClassFor(weaponId: string, class: string?, mult: number?): (string, number)
	local iw = VehicleCombatConfig.InfantryWeapons[weaponId]
	local c = class or (if iw then iw.Class else nil) or VehicleCombatConfig.DefaultInfantryClass
	local m = mult or (if iw then iw.Mult else nil) or 1
	return c, m
end

local function vehicleName(model: Model): string
	local id = model:GetAttribute("VehicleId")
	local def = if typeof(id) == "string" then (VehicleConfig.Vehicles :: any)[id] else nil
	return if def and typeof(def.DisplayName) == "string" then def.DisplayName else model.Name
end

-- same clan (both in one, pcall'd; no ClanService = never allies)
local function isClanAlly(a: Player, b: Player): boolean
	if a == b or ClanService == nil or ClanService.GetClanId == nil then
		return false
	end
	local okA, ca = pcall(ClanService.GetClanId, a)
	local okB, cb = pcall(ClanService.GetClanId, b)
	return okA and okB and ca ~= nil and ca == cb
end

-- true during the spawn shield and the whole F6 novice shield (InvulnerableUntil = math.huge)
function CombatService.IsSpawnInvulnerable(player: Player): boolean
	local s = combatStates[player.UserId]
	return s ~= nil and clock() < s.InvulnerableUntil
end

-- F6 (spec §2 cross-lane API): is this player under the novice shield this session?
function CombatService.IsNoviceShielded(player: Player): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and NS.Active[player.UserId] ~= nil
end

--[[ F6 (spec §2 cross-lane API): end the novice shield for good. reason: "draw" | "fire" | "order" | "strike" |
	"contest" | "tutorial" | "timeout" (any other string always ends it). A reason whose NoviceShield switch
	(NS.ReasonFlag) is false is ignored. Returns true when the shield ended now: InvulnerableUntil back to 0, the
	ForceField and WE_ShieldUntil removed, profile.NoviceShieldDone = true (saved), one Text.Off toast. Callers in other
	services wrap it in pcall and a nil check. ]]
function CombatService.EndNoviceShield(player: Player, reason: string): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	local uid = player.UserId
	if NS.Active[uid] == nil then
		return false
	end
	local cfg = NS.cfg()
	local flag = NS.ReasonFlag[if typeof(reason) == "string" then reason else ""]
	if flag ~= nil and typeof(cfg) == "table" and cfg[flag] == false then
		return false
	end
	NS.Active[uid] = nil
	local state = combatStates[uid]
	if state and state.InvulnerableUntil == math.huge then
		state.InvulnerableUntil = 0
	end
	local char = player.Character
	if char then
		local ff = char:FindFirstChild(NS.ForceField)
		if ff then
			ff:Destroy()
		end
		if char:GetAttribute(CombatFeelConfig.ShieldAttribute) ~= nil then
			char:SetAttribute(CombatFeelConfig.ShieldAttribute, nil)
		end
	end
	local profile = DataService and DataService.GetProfile(player)
	if profile then
		profile.NoviceShieldDone = true
		DataService.MarkDirty(player)
	end
	if NotificationService and typeof(cfg) == "table" and typeof(cfg.Text) == "table" then
		NotificationService.Notify(player, cfg.Text.Off, "Warn")
	end
	return true
end

--[[ W2 (contracts §3.1): one hit on whatever `hit` belongs to (player > NPC > registered vehicle > gate).
	Players / NPCs take amount x VsInfantryMult x (Headshot and HeadshotMult); vehicles go to VehicleHealth
	(class maths there); gates need an attacker. Unless opts.Quiet the attacker gets CombatHitFeedback. ]]
function CombatService.ApplyHit(attacker: Player?, hit: Instance, amount: number, opts: HitOpts): HitResult
	if typeof(hit) ~= "Instance" or typeof(amount) ~= "number" or not (amount > 0) or typeof(opts) ~= "table" then
		return { Kind = "None", Dealt = 0, Killed = false, Target = nil }
	end
	local weaponId = if typeof(opts.WeaponId) == "string" then opts.WeaponId else "?"
	local quiet = opts.Quiet == true
	local firing = opts.Vehicle
	local kind, ref, model = resolveTarget(hit)
	if kind == "Player" then
		local victim = ref :: Player
		if firing then
			local vVeh = seatedVehicle(victim)
			if vVeh == firing then -- a vehicle's own gun never hits its occupants
				return { Kind = "Player", Dealt = 0, Killed = false, Target = model }
			end
		end
		local dmg = amount * (tonumber(opts.VsInfantryMult) or 1) * (if opts.Headshot == true then CombatFeelConfig.HeadshotMult else 1)
		if firing then
			local rp = VehicleCombatConfig.RookieProtection
			local vp = DataService and DataService.GetProfile(victim)
			if vp and (tonumber(vp.Level) or 1) < rp.BelowLevel then
				dmg *= rp.VehicleWeaponMult
			end
		end
		local dealt, killed = hurtPlayer(attacker, victim, dmg, weaponId, {
			Headshot = opts.Headshot,
			Pos = opts.HitPos,
			Assist = opts.Assist,
			Quiet = quiet,
			UnitShot = opts.UnitShot,
		})
		return { Kind = "Player", Dealt = dealt, Killed = killed, Target = model }
	elseif kind == "NPC" then
		if typeof(ref) ~= "string" then
			return { Kind = "NPC", Dealt = 0, Killed = false, Target = model }
		end
		local dmg = amount * (tonumber(opts.VsInfantryMult) or 1) * (if opts.Headshot == true then CombatFeelConfig.HeadshotMult else 1)
		local dealt, killed = hurtNPC(attacker, ref, dmg, weaponId, {
			Headshot = opts.Headshot,
			Pos = opts.HitPos,
			Assist = opts.Assist,
			Quiet = quiet,
			UnitShot = opts.UnitShot,
		})
		return { Kind = "NPC", Dealt = dealt, Killed = killed, Target = model }
	elseif kind == "Vehicle" then
		local veh = ref :: Model
		if veh == firing or not NS.allowsAttack(attacker) then -- F6: a shielded attacker's hit ends the shield first
			return { Kind = "Vehicle", Dealt = 0, Killed = false, Target = veh }
		end
		local class, mult = vehicleClassFor(weaponId, opts.Class, opts.WeaponMult)
		local ok, d, destroyedNow = pcall(VehicleHealth.ApplyDamage, veh, {
			Attacker = attacker,
			Amount = amount,
			Class = class,
			WeaponId = weaponId,
			WeaponMult = mult,
			HitPos = opts.HitPos,
		})
		local dealt = if ok then tonumber(d) or 0 else 0
		local killed = ok and destroyedNow == true
		if attacker and dealt > 0 and not quiet then
			hitFeedback(attacker, {
				Kind = if killed then "Kill" else "Hit",
				Damage = dealt,
				TargetName = vehicleName(veh),
				WeaponId = weaponId,
				IsHeadshot = false,
				Target = veh,
				TargetKind = "Vehicle",
				Pos = opts.HitPos,
				Assist = if opts.Assist then true else nil,
			})
		end
		return { Kind = "Vehicle", Dealt = dealt, Killed = killed, Target = veh }
	elseif kind == "Gate" then
		local part = ref :: BasePart
		local landed = false
		if attacker and GateDefenseService and GateDefenseService.ApplyDamage and NS.allowsAttack(attacker) then
			local ok, res = pcall(GateDefenseService.ApplyDamage, attacker, part, amount, weaponId)
			landed = ok and res == true
		end
		if attacker and landed and not quiet then
			hitFeedback(attacker, {
				Kind = "Hit",
				Damage = amount,
				TargetName = "Gate",
				WeaponId = weaponId,
				IsHeadshot = false,
				Target = part,
				TargetKind = "Gate",
				Pos = opts.HitPos,
			})
		end
		return { Kind = "Gate", Dealt = if landed then amount else 0, Killed = false, Target = part }
	end
	return { Kind = "None", Dealt = 0, Killed = false, Target = nil }
end

--[[ W2 (contracts §3.2): area damage to humanoids (players + NPC records; vehicles are NOT included: pair it with
	VehicleHealth.ApplyRadiusDamage). maxAmount x VsInfantryMult x lerp(1, MinMult, d / radius) to each torso within
	radius, with a line of sight from the blast (lifted LosLiftStuds) unless RequireLos == false. Players follow the
	usual rules (PvP, self, spawn shield) and clan allies of the attacker are spared (Splash.ExcludeClanAllies).
	Skipped: the firing vehicle's occupants, IgnoreModel, occupants of enclosed seats (the vehicle takes it) and
	squad units. Unless Quiet, the attacker gets ONE aggregated feedback (Splash = true). ]]
function CombatService.ApplyRadiusDamage(attacker: Player?, center: Vector3, radius: number, maxAmount: number, opts: RadiusOpts): RadiusResult
	local res: RadiusResult = { Players = 0, Npcs = 0, Killed = 0, Dealt = 0 }
	if typeof(center) ~= "Vector3" or not (center.Magnitude < 1e7) then
		return res
	end
	if typeof(radius) ~= "number" or not (radius > 0 and radius < 1e4) or typeof(maxAmount) ~= "number" or not (maxAmount > 0) then
		return res
	end
	local o: any = if typeof(opts) == "table" then opts else {}
	local weaponId = if typeof(o.WeaponId) == "string" then o.WeaponId else "?"
	local splash = CombatFeelConfig.Splash
	local minMult = if typeof(o.MinMult) == "number" then o.MinMult else splash.DefaultMinMult
	local vsInf = tonumber(o.VsInfantryMult) or 1
	local requireLos = if o.RequireLos == nil then splash.RequireLos else o.RequireLos == true
	local quiet = o.Quiet == true
	local firing: Model? = if typeof(o.Vehicle) == "Instance" then (o.Vehicle :: any) :: Model else nil
	local ignoreModel: Model? = if typeof(o.IgnoreModel) == "Instance" then (o.IgnoreModel :: any) :: Model else nil
	local losFrom = center + Vector3.new(0, splash.LosLiftStuds, 0)
	local ignore: { Instance }? = nil -- built once, on the first line-of-sight check
	local function clear(to: Vector3, ownVeh: Model?): boolean
		if not requireLos then
			return true
		end
		local list = ignore
		if list == nil then
			local l: { Instance } = {}
			local npcs = Workspace:FindFirstChild("WarEmpireNPCs")
			if npcs then
				table.insert(l, npcs)
			end
			local squads = Workspace:FindFirstChild("WarEmpireSquads")
			if squads then
				table.insert(l, squads)
			end
			for _, plr in ipairs(Players:GetPlayers()) do
				local c = plr.Character
				if c then
					table.insert(l, c)
				end
			end
			ignore = l
			list = l
		end
		local ll = list :: { Instance }
		if ownVeh then
			table.insert(ll, ownVeh)
		end
		local ok = CombatDamage.LineOfSight(losFrom, to, ll, nil, false)
		if ownVeh then
			table.remove(ll)
		end
		return ok
	end
	local r2 = radius * radius
	local seen: { [Instance]: boolean } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char, hum, root = characterParts(plr)
		if char and hum and root and hum.Health > 0 and not seen[char] and char ~= ignoreModel then
			seen[char] = true
			local torso = torsoOf(char, root).Position
			local dv = torso - center
			if dv:Dot(dv) <= r2 then
				local veh, seat = seatedVehicle(plr)
				local skip = (firing ~= nil and veh == firing)
					or inEnclosedSeat(veh, seat)
					or (attacker ~= nil and splash.ExcludeClanAllies == true and isClanAlly(attacker, plr))
				if not skip and clear(torso, veh) then
					local amt = maxAmount * vsInf * CombatDamage.SplashMult(dv.Magnitude, radius, minMult)
					local dealt, killed = hurtPlayer(attacker, plr, amt, weaponId, { NoAttackerFb = true, Pos = center, Quiet = quiet })
					if dealt > 0 then
						res.Players += 1
						res.Dealt += dealt
						if killed then
							res.Killed += 1
						end
					end
				end
			end
		end
	end
	for id, rec in pairs(npcRecords) do
		local model = rec.Model
		if rec.Alive and rec.Humanoid.Health > 0 and model.Parent ~= nil and not seen[model] and model ~= ignoreModel then
			seen[model] = true
			local torso = torsoOf(model, rec.Root).Position
			local dv = torso - center
			if dv:Dot(dv) <= r2 and clear(torso, nil) then
				local amt = maxAmount * vsInf * CombatDamage.SplashMult(dv.Magnitude, radius, minMult)
				local dealt, killed = hurtNPC(attacker, id, amt, weaponId, { NoAttackerFb = true, NoKillMarker = true, Quiet = quiet, Pos = center })
				if dealt > 0 then
					res.Npcs += 1
					res.Dealt += dealt
					if killed then
						res.Killed += 1
					end
				end
			end
		end
	end
	if attacker and not quiet and res.Dealt > 0 then
		hitFeedback(attacker, {
			Kind = if res.Killed > 0 then "Kill" else "Hit",
			Damage = res.Dealt,
			WeaponId = weaponId,
			IsHeadshot = false,
			Pos = center,
			Splash = true,
		})
	end
	return res
end

--[[ W2 (contracts §3.3, nuke §15.2): blast damage to one humanoid, always quiet for the attacker. Players: PvP, not
	self, no spawn shield, alive; tags WE_BlastSource / WE_BlastAt (a death within CombatFeelConfig.BlastSourceSeconds
	is a quiet "blast death"). NPCs: quiet kill (rewards, missions, stats; no toast, no feedback).
	Returns (dealt, killed) with killed read right after TakeDamage. ]]
function CombatService.ApplyBlastDamage(attacker: Player?, humanoid: Humanoid, damage: number, sourceId: string): (number, boolean)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then
		return 0, false
	end
	if typeof(damage) ~= "number" or not (damage > 0) then
		return 0, false
	end
	local src = if typeof(sourceId) == "string" then sourceId else "Blast"
	local model = humanoid.Parent
	if model == nil or not model:IsA("Model") then
		return 0, false
	end
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		if attacker ~= nil and (not GameConfig.PvPEnabled or attacker == victim) then
			return 0, false
		end
		if not NS.allowsAttack(attacker) then -- F6: a shielded attacker deals no PvP damage
			return 0, false
		end
		if CombatService.IsSpawnInvulnerable(victim) or humanoid.Health <= 0 then
			return 0, false
		end
		if attacker then
			tagCreator(humanoid, attacker)
		end
		humanoid:SetAttribute("WE_BlastSource", src)
		humanoid:SetAttribute("WE_BlastAt", clock())
		humanoid:SetAttribute("WE_LastWeapon", src)
		local before = humanoid.Health
		humanoid:TakeDamage(damage)
		local dealt = math.max(0, before - humanoid.Health)
		local killed = humanoid.Health <= 0
		if dealt > 0 then
			hitFeedback(victim, { Kind = if killed then "Death" else "Damaged", Damage = dealt, WeaponId = src })
			pushState(victim)
		end
		return dealt, killed
	end
	if CollectionService:HasTag(model, Constants.Tags.NPC) then
		local npcId = model:GetAttribute("NPCId")
		if typeof(npcId) == "string" then
			return hurtNPC(attacker, npcId, damage, src, { Quiet = true })
		end
	end
	return 0, false
end

--[[ W2 (contracts §3.7): `fn(victim, killer, info)` after every player death (once per death; after stats, rewards
	and RegisterPlayerKill; before the respawn delay). Each listener runs in its own pcall, in registration order.
	Returns a disconnect function. ]]
function CombatService.OnPlayerDeath(fn: (victim: Player, killer: Player?, info: DeathInfo) -> ()): () -> ()
	local entry = { Fn = fn }
	table.insert(W2.deathListeners, entry)
	return function()
		local i = table.find(W2.deathListeners, entry)
		if i then
			table.remove(W2.deathListeners, i)
		end
	end
end

--[[ W2 (contracts §1.2 step 2): may this player fire from where they sit? Returns (allowed, seated vehicle model,
	fires from the head). A seat outside a registered vehicle keeps today's rules. ]]
local function seatFireRule(player: Player): (boolean, Model?, boolean)
	local veh, seat = seatedVehicle(player)
	if seat == nil or veh == nil then
		return true, nil, false
	end
	local _, rec = registeredVehicle(seat)
	if rec == nil then
		return true, veh, false -- not a registered vehicle: today's rules (its hull still stays out of the shot)
	end
	if seat:IsA("VehicleSeat") or seat:GetAttribute("WE_SeatRole") == "Driver" then
		-- J10 lets drivers of OPEN vehicles fire; an enclosed driver seat never shoots out through its own hull
		-- (W2 verify: the shot filter leaves the vehicle out, and enclosed occupants cannot be hit back)
		return VehicleCombatConfig.SeatFire.DriverCanUseInfantryWeapons == true and seat:GetAttribute("WE_Exposed") ~= false, veh, false
	end
	if seat:GetAttribute("WE_MountId") ~= nil then
		return false, veh, false
	end
	if seat:GetAttribute("WE_CanFireFromSeat") == true then
		return true, veh, true
	end
	return false, veh, false
end

-- the shot's Exclude list: the shooter, the vehicle they sit in, every squad unit (units are not player targets)
local function shotFilterFor(character: Model, veh: Model?): { Instance }
	local f: { Instance } = { character }
	if veh then
		table.insert(f, veh)
	end
	local squads = Workspace:FindFirstChild("WarEmpireSquads")
	if squads then
		table.insert(f, squads)
	end
	return f
end

-- W2 (contracts §1.1): the fire payload's Input field sets the assist class (first valid one at once, then at most
-- one change per ClassChangeSeconds); anything else is ignored without a strike
local function noteInputClass(player: Player, input: any)
	if typeof(input) ~= "string" or string.len(input) > 16 or AimAssistConfig.Classes[input] == nil then
		return
	end
	local uid = player.UserId
	local cur = W2.inputClass[uid]
	if cur == input then
		return
	end
	local t = clock()
	if cur ~= nil and t - (W2.inputClassAt[uid] or -math.huge) < AimAssistConfig.ClassChangeSeconds then
		return
	end
	W2.inputClass[uid] = input
	W2.inputClassAt[uid] = t
	player:SetAttribute(AimAssistConfig.ClassAttribute, input)
end

function CombatService.InputClass(player: Player): string
	return W2.inputClass[player.UserId] or AimAssistConfig.DefaultClass
end

-- W2 (contracts §2.3): character attribute WE_GunOut = the drawn weapon id (other clients show the gun)
local function setGunOut(player: Player, weaponId: string?)
	local char = player.Character
	if char == nil then
		return
	end
	local attr = CombatFeelConfig.Drawn.Attribute
	if char:GetAttribute(attr) ~= weaponId then
		char:SetAttribute(attr, weaponId)
	end
end

function CombatService.SetDrawn(player: Player, drawn: boolean)
	if drawn == true and NS.Active[player.UserId] ~= nil then
		CombatService.EndNoviceShield(player, "draw") -- F6: drawing a weapon ends the novice shield (EndOnDraw)
	end
	local state = combatStates[player.UserId]
	local _, hum = characterParts(player)
	local alive = state ~= nil and state.Alive and hum ~= nil and hum.Health > 0
	setGunOut(player, if drawn and alive and state then state.WeaponId else nil)
end

-- W2 (contracts §1.5): per-class counts of how hitscan shots resolved; one summary log line per AimStatsLogSeconds
local function noteAim(cls: string, how: string)
	local s = W2.aimStats[cls]
	if s == nil then
		s = { Exact = 0, Claim = 0, Assist = 0, Miss = 0 }
		W2.aimStats[cls] = s
	end
	s[how] = (s[how] or 0) + 1
	local t = clock()
	if t - W2.aimStatsLoggedAt >= CombatFeelConfig.AimStatsLogSeconds then
		W2.aimStatsLoggedAt = t
		local parts: { string } = {}
		for name, c in pairs(W2.aimStats) do
			table.insert(parts, string.format("%s exact %d claim %d assist %d miss %d", name, c.Exact, c.Claim, c.Assist, c.Miss))
		end
		table.sort(parts)
		print("[CombatService] aim: " .. table.concat(parts, " | "))
	end
end

function CombatService._AimStats(): { [string]: { [string]: number } }
	local out: { [string]: { [string]: number } } = {}
	for name, c in pairs(W2.aimStats) do
		out[name] = table.clone(c)
	end
	return out
end

-- W2: one WeaponFx bullet event (pcall'd: a missing remote drops the effect, never the shot)
local function sendBulletFx(player: Player, weaponId: string, origin: Vector3, landed: Vector3, kind: string)
	pcall(CombatFx.Bullet, player.UserId, player.UserId, weaponId, origin, landed, kind)
end

--[[ W2 (contracts §3.4): rocket / grenade impact. Direct vehicle or gate hit first, then humanoid splash, then vehicle
	splash (the directly hit vehicle is not hit twice), then the "X" WeaponFx event. A shooter who left deals nothing. ]]
local function projectileImpact(
	attacker: Player,
	weaponId: string,
	pd: WeaponConfig.ProjectileDef,
	amount: number,
	launchedAt: Vector3,
	pos: Vector3,
	hit: RaycastResult?,
	id: number
)
	local center = pos
	if hit then
		center = hit.Position + hit.Normal * 0.5 -- just off the surface (the splash line-of-sight starts outside it)
	end
	if attacker.Parent ~= nil then
		local direct: Model? = nil
		if hit then
			local veh, vrec = registeredVehicle(hit.Instance)
			if veh and vrec and vrec.Destroyed ~= true then
				CombatService.ApplyHit(attacker, hit.Instance, amount, { WeaponId = weaponId, HitPos = hit.Position })
				direct = veh
			elseif hit.Instance:IsA("BasePart") and hit.Instance:GetAttribute("GateBarrier") == true then
				CombatService.ApplyHit(attacker, hit.Instance, amount, { WeaponId = weaponId, HitPos = hit.Position })
			end
		end
		CombatService.ApplyRadiusDamage(attacker, center, pd.Splash, amount, { WeaponId = weaponId, MinMult = pd.SplashMinMult })
		local class, mult = vehicleClassFor(weaponId, nil, nil)
		if NS.allowsAttack(attacker) then -- F6: no vehicle splash from a shielded attacker
			pcall(VehicleHealth.ApplyRadiusDamage, center, pd.Splash, amount, attacker, class, {
				MinMult = pd.SplashMinMult,
				WeaponMult = mult,
				IgnoreModel = direct,
				WeaponId = weaponId,
			})
		end
	end
	pcall(CombatFx.Explode, attacker.UserId, weaponId, launchedAt, center, pd.Splash, id)
end

local function launchProjectile(player: Player, def: WeaponDef, weaponId: string, origin: Vector3, dir: Vector3, filter: { Instance }): boolean
	local pd = def.Projectile :: WeaponConfig.ProjectileDef
	local amount = damageFor(def, player)
	local spawnAt = origin + dir * CombatFeelConfig.Projectile.SpawnForwardStuds
	local vel = dir * pd.Speed
	local rec = Projectile.Launch({
		OwnerUserId = player.UserId,
		Origin = spawnAt,
		From = origin, -- W2 verify: the first ray starts at the shot origin (no tunnelling through a wall 1 stud ahead)
		Velocity = vel,
		GravityFactor = pd.GravityFactor,
		MaxSeconds = pd.MaxSeconds,
		Filter = filter,
		OnImpact = function(pos: Vector3, hit: RaycastResult?, r: Projectile.Record)
			projectileImpact(player, weaponId, pd, amount, spawnAt, pos, hit, r.Id)
		end,
	})
	if rec == nil then
		return false
	end
	pcall(CombatFx.Launch, player.UserId, weaponId, spawnAt, vel, pd.MaxSeconds, rec.Id)
	return true
end

--[[ W2 (contracts §1.3 step 3): the assist candidate for this shot, or nil. Candidates are alive players (PvP on) and
	live NPC records; never the shooter, clan allies, spawn-shielded players, anyone in the shooter's vehicle or in an
	enclosed seat, vehicles, gates or squad units. ]]
local function assistPick(
	player: Player,
	shooterVeh: Model?,
	origin: Vector3,
	dir: Vector3,
	cls: string,
	assistRange: number,
	maxAlong: number,
	filter: { Instance }
): CombatAssist.Pick?
	CombatAssist.Begin(origin, dir, cls, assistRange, maxAlong)
	if GameConfig.PvPEnabled then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player then
				local char, hum, root = characterParts(plr)
				local torso = if char and root then torsoOf(char, root) else nil
				if char and hum and torso and hum.Health > 0 and CombatAssist.InCone(torso.Position) and not CombatService.IsSpawnInvulnerable(plr) then
					local veh, seat = seatedVehicle(plr)
					local excluded = (shooterVeh ~= nil and veh == shooterVeh)
						or inEnclosedSeat(veh, seat)
						or (AimAssistConfig.ExcludeClanAllies and isClanAlly(player, plr))
					if not excluded then
						CombatAssist.Offer(char, torso, plr, nil)
					end
				end
			end
		end
	end
	for id, rec in pairs(npcRecords) do
		if rec.Alive and rec.Humanoid.Health > 0 and rec.Model.Parent ~= nil then
			CombatAssist.Offer(rec.Model, torsoOf(rec.Model, rec.Root), nil, id)
		end
	end
	return CombatAssist.Finish(filter)
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

	-- W2 (contracts §1.2 step 2): seat rule before any ammo or schedule is spent (a refusal is not a strike)
	local seatVeh, seatAllowed, fromSeat = nil, true, false
	do
		local allowed, veh, fromHead = seatFireRule(player)
		seatAllowed, seatVeh, fromSeat = allowed, veh, fromHead
	end
	if not seatAllowed then
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
	-- P0-7: every component (a NaN Y or Z made .Unit NaN, which slipped past the claim checks below)
	local finite = AntiExploitService.IsFiniteNumber
	if not (finite(direction.X) and finite(direction.Y) and finite(direction.Z)) then
		AntiExploitService.Strike(player, "fire_nan_direction")
		return false
	end
	direction = direction.Unit

	local origin = payload.Origin
	if fromSeat then
		-- W2: an open-seat passenger fires from the head (the seat moves under them: no desync check)
		local head = character:FindFirstChild("Head")
		origin = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	elseif typeof(origin) ~= "Vector3" then
		origin = root.Position + Vector3.new(0, 1.5, 0)
	else
		if not ((origin - root.Position).Magnitude <= CombatConfig.MaxOriginDeltaStuds) then -- P0-7: NaN snaps too
			AntiExploitService.Strike(player, "fire_origin_desync")
			origin = root.Position + Vector3.new(0, 1.5, 0)
		else
			-- W2 verify: an Origin up to 12 studs out may not sit on the far side of a wall (wall-banging, rockets
			-- spawned inside a base). No strike: the shot simply starts at the head.
			local head = character:FindFirstChild("Head")
			local eye = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
			if (origin - eye).Magnitude > 0.25 and not CombatDamage.LineOfSight(eye, origin, shotFilterFor(character, seatVeh), nil, true) then
				origin = eye
			end
		end
	end

	-- W2 (contracts §1.2 step 5): projectile caps refuse the shot before any ammo is spent
	local isProjectile = def.Projectile ~= nil
	if isProjectile and Projectile.AtCap(player.UserId) then
		return false
	end

	state.Ammo -= 1
	state.LastFireAt = math.max(state.LastFireAt + minInterval, clock()) -- v69 research: was = clock()
	guns[state.WeaponId] = math.max(gunAt + minInterval, clock()) -- v69 research
	-- F6: the first accepted shot ends the novice shield before any hit is resolved (EndOnFire)
	if NS.Active[player.UserId] ~= nil then
		CombatService.EndNoviceShield(player, "fire")
	end
	pushState(player)

	-- W2 (contracts §1.1, §2.3): input class for the assist; an accepted shot means the gun is out
	noteInputClass(player, payload.Input)
	if character:GetAttribute(CombatFeelConfig.Drawn.Attribute) == nil then
		setGunOut(player, state.WeaponId)
	end
	local shotFilter = shotFilterFor(character, seatVeh)

	if isProjectile then
		launchProjectile(player, def, state.WeaponId, origin, direction, shotFilter)
		return true
	end

	local range = def.Range + CombatConfig.HitPositionSlopStuds
	local damage = damageFor(def, player)
	local result = raycast(origin, direction, range, shotFilter)
	local cls = CombatService.InputClass(player)

	local hitSomething = false
	local how = "Miss" -- W2 aim stats: "Exact" | "Claim" | "Assist" | "Miss"
	local fxKind, fxAt = "M", origin + direction * def.Range -- W2 WeaponFx: where the shot landed
	-- P0-7: how far along the fire ray a client-named target may stand (nil = the exact ray decided the shot)
	local claimMaxAlong: number? = nil
	local sceneryAlong: number? = nil -- W2: the exact ray hit scenery this far along (bounds the assist too)
	if result then
		-- W2 (contracts §1.3 step 1): a player, an NPC, a registered vehicle (cover, even when protected) or a gate
		-- decides the shot. A part named "Head" of a player or NPC is a headshot.
		local kind = resolveTarget(result.Instance)
		if kind ~= "None" then
			how = "Exact"
			local isHead = (kind == "Player" or kind == "NPC") and result.Instance.Name == "Head"
			local amount = if kind == "Gate"
				then damage
				else damage * CombatDamage.FalloffMult(def, (result.Position - origin).Magnitude)
			local hit = CombatService.ApplyHit(player, result.Instance, amount, {
				WeaponId = state.WeaponId,
				HitPos = result.Position,
				Headshot = isHead,
			})
			hitSomething = hit.Dealt > 0
			fxKind = FX_KIND[kind] or "W"
			fxAt = result.Position
		else
			-- the ray only hit scenery (ground, a wall far behind the target): a named target in front of that point may
			-- still take the hit under the same checks (on flat ground the camera ray almost always ends in the ground)
			sceneryAlong = (result.Position - origin).Magnitude
			if CombatFairnessConfig.ClaimAfterSceneryHit then
				claimMaxAlong = (result.Position - origin).Magnitude + CombatFairnessConfig.ClaimBeyondHitStuds
			end
			fxKind = "W"
			fxAt = result.Position
		end
	else
		claimMaxAlong = range
	end
	if claimMaxAlong ~= nil then
		-- P0-7: the server ray missed. The target the client named still takes the hit when the target moved a
		-- little after the phone's ray hit it (cellular lag), never through walls or with the gun pointed elsewhere.
		-- W2: a validated claim decides the shot (no headshot, no assist); a refused one falls through to the assist.
		local maxAlong = math.min(range, claimMaxAlong)
		local targetUserId = payload.TargetUserId
		local targetNpcId = payload.TargetNpcId
		if typeof(targetUserId) == "number" then
			local targetPlayer: Player? = nil
			if targetUserId == targetUserId and targetUserId > 0 and targetUserId < 2 ^ 53 and targetUserId % 1 == 0 then
				targetPlayer = Players:GetPlayerByUserId(targetUserId)
			end
			if targetPlayer == nil or targetPlayer == player then
				logClaimRefusal(player, "no such target", "user " .. tostring(targetUserId))
			else
				local tchar, thum, troot = characterParts(targetPlayer)
				if tchar == nil or thum == nil or troot == nil or thum.Health <= 0 then
					logClaimRefusal(player, "target dead or absent", "user " .. tostring(targetPlayer.UserId))
				else
					local torso = torsoOf(tchar, troot)
					local ok, why = validateClaim(character, origin, direction, range, maxAlong, tchar, torso.Position)
					if ok then
						how = "Claim"
						local amount = damage * CombatDamage.FalloffMult(def, (torso.Position - origin).Magnitude)
						local hit = CombatService.ApplyHit(player, torso, amount, { WeaponId = state.WeaponId, HitPos = torso.Position })
						hitSomething = hit.Dealt > 0
						fxKind, fxAt = "P", torso.Position
					else
						logClaimRefusal(player, why, "user " .. tostring(targetPlayer.UserId))
					end
				end
			end
		elseif typeof(targetNpcId) == "string" then
			local rec = if #targetNpcId <= 64 then npcRecords[targetNpcId] else nil
			if rec == nil or not rec.Alive or rec.Humanoid.Health <= 0 or rec.Model.Parent == nil then
				logClaimRefusal(player, "target dead or absent", "npc " .. string.sub(targetNpcId, 1, 64))
			else
				local ok, why = validateClaim(character, origin, direction, range, maxAlong, rec.Model, rec.Root.Position)
				if ok then
					how = "Claim"
					local amount = damage * CombatDamage.FalloffMult(def, (rec.Root.Position - origin).Magnitude)
					local hit = CombatService.ApplyHit(player, rec.Root, amount, { WeaponId = state.WeaponId, HitPos = rec.Root.Position })
					hitSomething = hit.Dealt > 0
					fxKind, fxAt = "N", rec.Root.Position
				else
					logClaimRefusal(player, why, "npc " .. targetNpcId)
				end
			end
		end
	end

	-- W2 (contracts §1.3 step 3): server aim assist (the client's target hints are never read here)
	if how == "Miss" and AimAssistConfig.Enabled then
		local assistRange = math.min(def.Range, AimAssistConfig.MaxRangeStuds)
		local maxAlong = if sceneryAlong ~= nil then sceneryAlong + CombatFairnessConfig.ClaimBeyondHitStuds else assistRange
		local pick = assistPick(player, seatVeh, origin, direction, cls, assistRange, maxAlong, shotFilter)
		if pick then
			how = "Assist"
			local amount = damage * CombatDamage.FalloffMult(def, pick.Distance)
			local hit = CombatService.ApplyHit(player, pick.Torso, amount, {
				WeaponId = state.WeaponId,
				HitPos = pick.Torso.Position,
				Assist = true,
			})
			hitSomething = hit.Dealt > 0
			fxKind = if pick.Player then "P" else "N"
			fxAt = pick.Torso.Position
		end
	end

	if not hitSomething then
		local hitPosition = payload.HitPosition
		if typeof(hitPosition) == "Vector3" and (hitPosition - origin).Magnitude > range * 1.25 then
			AntiExploitService.Strike(player, "fire_hitpos_oor")
		end
	end

	noteAim(cls, how)
	sendBulletFx(player, state.WeaponId, origin, fxAt, fxKind)
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

-- W2 (contracts §3.7): what killed the player (WE_LastWeapon, and a recent blast marks a quiet "blast death")
local function deathInfoOf(humanoid: Humanoid?): DeathInfo
	local weaponId: string? = nil
	local blast: string? = nil
	if humanoid then
		local w = humanoid:GetAttribute("WE_LastWeapon")
		if typeof(w) == "string" then
			weaponId = w
		end
		local src = humanoid:GetAttribute("WE_BlastSource")
		local at = humanoid:GetAttribute("WE_BlastAt")
		if typeof(src) == "string" and typeof(at) == "number" and clock() - at <= CombatFeelConfig.BlastSourceSeconds then
			blast = src
		end
	end
	return { WeaponId = weaponId, BlastSource = blast, Quiet = blast ~= nil }
end

--[[ Built-in OnPlayerDeath listener #1 (moved as-is from onPlayerDeath; skipped for blast deaths, nuke §15.2).
	v30: PvP death → DeathShopOffer toast (MonetizationConfig.DeathShopOffers; live Ids only; debounced).
	F8 (owner's 11 features): PvP non-blast death → MonetizationService.TryDeathSpeedOffer (one Speed Pass offer per
	session; it checks the live Id, ownership, the tutorial and the soft-offer slot). No separate "Boost?" text toast:
	the offer toast itself is the message. ]]
local function deathShopOfferListener(victim: Player, killer: Player?, info: DeathInfo)
	if info.BlastSource ~= nil then
		return
	end
	if killer and killer ~= victim then
		local now = os.clock()
		local prev = lastDeathShopAt[victim.UserId] or 0
		if now - prev >= DEATH_SHOP_DEBOUNCE then
			lastDeathShopAt[victim.UserId] = now
			local MonetizationConfig = require(ReplicatedStorage.Shared.Configs.MonetizationConfig)
			local offers = (MonetizationConfig :: any).DeathShopOffers or { "DoubleCash", "SpeedBoost" }
			local liveOffers = {}
			for _, key in ipairs(offers) do
				local live = resolveDeathOfferLive(MonetizationConfig, key)
				if live then
					table.insert(liveOffers, key)
				end
			end
			if #liveOffers > 0 and RemoteSetup then
				local remote = RemoteSetup.Get(Constants.RemoteNames.DeathShopOffer)
				if remote then
					(remote :: RemoteEvent):FireClient(victim, { Offers = liveOffers })
				end
			end
			-- F8: the Speed Pass death offer (before the Cash Mega soft offer, so it gets the soft-offer slot)
			if MonetizationService and MonetizationService.TryDeathSpeedOffer then
				pcall(MonetizationService.TryDeathSpeedOffer, victim)
			end
			-- v37: CashMega soft offer on death path if not already offered (existing Id only)
			if MonetizationService and MonetizationService.TrySoftOfferCashMega then
				pcall(function()
					MonetizationService.TrySoftOfferCashMega(victim, "death", 0)
				end)
			end
		end
	end
end
CombatService.OnPlayerDeath(deathShopOfferListener) -- registered at load: always listener #1

local function onPlayerDeath(victim: Player, killer: Player?, humanoid: Humanoid?)
	if humanoid then -- W2: once per death, whatever fires Died
		if W2.deathHandled[humanoid] then
			return
		end
		W2.deathHandled[humanoid] = true
	end
	local state = combatStates[victim.UserId]
	if state then
		state.Alive = false
	end
	pcall(setGunOut, victim, nil) -- W2: the gun goes away with the body
	pushState(victim)
	local info = deathInfoOf(humanoid)
	if killer and killer ~= victim then
		CombatService.RegisterPlayerKill(killer, victim, if info.Quiet then { Quiet = true } else nil)
	else
		local vProfile = DataService.GetProfile(victim)
		if vProfile then
			vProfile.Stats.Deaths += 1
			DataService.MarkDirty(victim)
		end
	end

	-- W2: OnPlayerDeath listeners (listener #1 = the DeathShopOffer toast), each in its own pcall
	for _, entry in ipairs(table.clone(W2.deathListeners)) do
		xpcall(entry.Fn, function(err: any)
			warn("[CombatService] OnPlayerDeath listener error:", err)
		end, victim, killer, info)
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
		-- W2 (contracts §3.6): replicated spawn shield end (client bubble, AimTargets); server time, not os.clock
		local okNow, serverNow = pcall(function()
			return Workspace:GetServerTimeNow()
		end)
		local base = if okNow and typeof(serverNow) == "number" then serverNow else os.time()
		character:SetAttribute(CombatFeelConfig.ShieldAttribute, base + invuln)
		local def = weaponDef(state.WeaponId)
		if def then
			state.Ammo = magSize(player, def) -- v69 research
			state.ReloadingUntil = 0
		end
		NS.apply(player, character) -- F6: a novice shield survives respawns (no-op when not shielded)
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
		onPlayerDeath(player, killer, humanoid)
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
	ClanService = deps.ClanService -- W2: ally exclusion (optional)

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
		fx = function(rec: any, origin: Vector3, landed: Vector3, kind: string) -- W2: NPC WeaponFx (S = 0)
			CombatFx.Bullet(rec.Id, 0, "NPC", origin, landed, kind)
		end,
	})
	-- W2: WeaponFx fan-out (UnreliableRemoteEvent; every send pcall'd)
	CombatFx.Bind({
		getRemote = function(): Instance?
			return RemoteSetup.GetUnreliable(Constants.RemoteNames.WeaponFx)
		end,
		clock = clock,
	})
	W2.aimStatsLoggedAt = clock()
	-- F6: gate guards and AutoGuns skip a novice-shielded player. Injected: GateDefenseService takes no CombatService
	-- dep and never requires it (join-hotfix pins).
	if GateDefenseService and GateDefenseService.SetShieldCheck then
		pcall(GateDefenseService.SetShieldCheck, CombatService.IsNoviceShielded)
	end
	-- W2: optional gun meshes (nothing to load while every WeaponConfig VisualAssetId is 0)
	task.spawn(function()
		xpcall(WeaponAssetLoader.Start, function(err: any)
			warn("[CombatService] WeaponAssetLoader:", err)
		end, WeaponConfig.Weapons)
	end)


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

	-- W2 (contracts §2.3): drawn / holstered (WE_GunOut); a non-boolean is ignored without a strike
	local drawnRemote = RemoteSetup.Get(Constants.RemoteNames.RequestSetDrawn) :: RemoteEvent
	drawnRemote.OnServerEvent:Connect(function(player: Player, drawn: any)
		if not RateLimitService.Allow(player, "set_drawn", CombatFeelConfig.Drawn.RemoteRate, CombatFeelConfig.Drawn.RemoteBurst) then
			return
		end
		if typeof(drawn) ~= "boolean" then
			return
		end
		CombatService.SetDrawn(player, drawn)
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
		if player:GetAttribute(AimAssistConfig.ClassAttribute) == nil then -- W2: assist class until the first shot says
			player:SetAttribute(AimAssistConfig.ClassAttribute, AimAssistConfig.DefaultClass)
		end
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
		NS.onLoad(player, profile) -- F6: novice shield for this session (flag, tutorial, NoviceShieldDone)
		local wid = profile.EquippedWeapon or WeaponConfig.DefaultWeapon
		CombatService.EquipWeapon(player, wid)
		pushState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		combatStates[player.UserId] = nil
		gunSchedule[player.UserId] = nil -- v69 research
		claimRefusals[player.UserId] = nil -- P0-7
		CombatNPC.ForgetPlayer(player.UserId) -- P1-2 speed samples
		W2.inputClass[player.UserId] = nil -- W2
		W2.inputClassAt[player.UserId] = nil
		CombatFx.Forget(player.UserId)
		Projectile.ForgetOwner(player.UserId)
		NS.Active[player.UserId] = nil -- F6: an unfinished shield is not saved as done (the next session grants it)
	end)

	task.spawn(function()
		task.wait(1)
		-- lane N: false at the Ops cutover (the camps' garrisons come from OpsService, never two on the same posts)
		if CombatConfig.FieldBootstrap ~= false then
			CombatService.BootstrapNPCs()
		end
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
