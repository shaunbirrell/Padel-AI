--!strict
--[[ v71 money (M2): Nuke — consumable 19 R$ DevProduct (profile.Nukes) + post-rebirth Tactical Nuke (profile.TacticalNukes).
	ONE balance file. Server: NukeService (M5). Client: NukeController / NukeFx (radii, timings, copy).
	Paid grants ONLY via MonetizationService.ProcessReceipt (DevProducts.Nuke / NukeBundle3 → GrantNukes, added by M1
	with Id = 0). Config only: nothing reads this file yet and nothing is sold from it.

	Judge rulings applied (money/plan.md §1):
	- J1: a nuke can never open a base for raiding. Base mode gives kills, XP and scorch only, then puts a fallout
	  shield on the target (Base.FalloutShieldSeconds → Raid.ShieldUntil / WE_ShieldUntil). No defenses-down,
	  no ATM, cash or structure loss.
	- J5 / J6: the Nuclear Silo has 5 levels and one site only (Strategic Yard, Rebirth 2). No fallback site.
	- J8: any non-immune vehicle inside CoreRadius is destroyed; the edge ring deals DamageAt × EdgeDamageMult.
	- J17: own Fx remote (FxRemote = "NukeFx"), not MissileStrikeFx.
	- J24: world billboards and pads use the text "NUKE"; icons use IconImage once it is set.
	- J26: keep ServerCooldownSeconds = 180; raise to 300 here if the victim-leave KPI rises > 5 points. ]]

export type KindDef = {
	DisplayName: string,
	InventoryField: string,
	Radius: number,
	CoreRadius: number,
	CoreDamage: number,
	EdgeDamageMax: number,
	EdgeDamageMin: number,
	FlashRadius: number,
	LaunchXPFactor: number,
	LaunchXPMin: number,
	LaunchXPMax: number,
	KillBonusScale: number,
	CloudHeight: number,
	CloudScale: number,
}

local NukeConfig = {
	Enabled = true,
	CountdownSeconds = 10,
	TerminalDiveSeconds = 3,
	IconImage = "", -- owner: rbxassetid of a trefoil decal ("" → the text "NUKE"; J24)
	WorldLabel = "NUKE", -- billboards / pads (J24: no glyph that can fall back in FredokaOne)
	FxRemote = "NukeFx", -- Constants.RemoteNames.NukeFx (J17)

	KindOrder = { "Nuke", "TacticalNuke" },
	Kinds = {
		Nuke = {
			DisplayName = "Nuke",
			InventoryField = "Nukes",
			Radius = 150,
			CoreRadius = 75,
			CoreDamage = 1000,
			EdgeDamageMax = 200,
			EdgeDamageMin = 40,
			FlashRadius = 600,
			LaunchXPFactor = 0.30,
			LaunchXPMin = 400,
			LaunchXPMax = 6000,
			KillBonusScale = 1.0,
			CloudHeight = 220,
			CloudScale = 1.0,
		},
		TacticalNuke = {
			DisplayName = "Tactical Nuke",
			InventoryField = "TacticalNukes",
			Radius = 100,
			CoreRadius = 50,
			CoreDamage = 1000,
			EdgeDamageMax = 160,
			EdgeDamageMin = 30,
			FlashRadius = 400,
			LaunchXPFactor = 0.15,
			LaunchXPMin = 200,
			LaunchXPMax = 3000,
			KillBonusScale = 0.6,
			CloudHeight = 150,
			CloudScale = 0.7,
		},
	} :: { [string]: KindDef },

	Rules = {
		ServerCooldownSeconds = 180, -- J26
		PlayerCooldownSeconds = 300,
		MaxLaunchesPerPlayerPerHour = 6,
		BaseTargetCooldownSeconds = 900, -- the same base cannot be nuked again for 15 min
		VictimGraceSeconds = 600,
		SessionJoinGraceSeconds = 120,
		NewPlayerProtectionSeconds = 600, -- mirror RaidConfig.Raid.NewPlayerProtectionSeconds
		MinVictimLevelIfNoPrestige = 5,
		ProtectNewPlayersInStudio = false,
		SpawnSafeRadius = 24,
		AlliesImmune = true,
		BaseTargetMinPowerRatio = 0.35,
		PowerPerPrestige = 40,
		RefundIfTargetLeaves = true,
		InFlightRefundAfterSeconds = 30, -- J19: a younger marker at load is re-checked at At + 30 while online
		LaunchRate = 0.5,
		LaunchBurst = 2,
		StateRate = 1,
		StateBurst = 2,
	},

	Targeting = {
		-- plot-local, converted through the pad CFrame. Nations: on MainRoad (BaseLayoutConfig), 48 studs in front of the
		-- flagpole (Courtyard.Flagpole Z = 8), so a player's nation flag is never the aim point (BuyPathStatic: >= 30 studs)
		BaseAimPoint = { X = 0, Z = 56 },
		PlotClearance = 25,
		MapHalfExtent = 2350,
		GroundRayTop = 600,
		IncludeBank = true, -- + every TerritoryConfig.Territories entry except the Home Outposts (below)
		-- F10 (owner's 11 features): a Home Outpost (TerritoryConfig row with IsStarter = true) is never a nuke target
		-- (NukeConfig.IsTerritoryTargetable)
		SkipStarterOutposts = true,
	},

	Rewards = {
		PlayerKillBonusXP = 260,
		PlayerKillBonusCash = 350,
		NPCKillBonusMult = 1.0,
		SquadKillXP = 30,
		SquadKillCash = 40,
		MaxKillBonusXP = 6000,
		MaxKillBonusCash = 12000,
		XPReason = "nuke",
		CashReason = "nuke_kill",
	},

	-- J1: kills + XP + scorch, then a fallout shield on the target base. There are deliberately NO defenses-down
	-- fields: NukeService must never call GateDefenseService / MissileStrikeService for a base.
	Base = {
		FalloutShieldSeconds = 300, -- Raid.ShieldUntil = max(current, now + 300) (+ WE_ShieldUntil); blocks raids + strikes
		ScorchSeconds = 30, -- client-only ground scorch
	},

	-- J8: vehicles in the core are destroyed outright (so a 4,200 HP tank cannot survive ground zero). The edge ring
	-- deals NukeConfig.DamageAt × EdgeDamageMult through VehicleHealth.ApplyRadiusDamage(..., "Nuke"), ignoring armor.
	-- Occupant cover applies only in the edge ring.
	Vehicles = {
		CoreDestroys = true,
		EdgeDamageMult = 4,
		CoverMult = 0.6,
		PremiumCoverMult = 0.35,
	},

	-- J5: 5 levels (costs, online build time, capacity). J6: one site only, the Strategic Yard (Rebirth 2); the Silo
	-- waits for the rebirth world workflow (M7b), which owns the geometry (BaseLayoutConfig).
	Silo = {
		Enabled = true,
		UnlockPrestige = 2,
		Zone = "StrategicYard", -- RebirthConfig.Zones.StrategicYard
		Site = { X = 0, Z = -124, YawDeg = 0, Footprint = 22 }, -- plot-local (rebirth spec §2); no fallback site
		Requires = { CommandCenter = 3, MissileDefense = 1 } :: { [string]: number },
		Costs = { 250_000, 750_000, 2_000_000, 3_500_000, 6_000_000 },
		BuildSeconds = { 5400, 4200, 3000, 2400, 1800 }, -- 90 / 70 / 50 / 40 / 30 online minutes
		Capacity = { 1, 1, 2, 2, 3 },
		TickSeconds = 5,
	},

	Gift = { Enabled = true, AtLevel = 10, Kind = "TacticalNuke", Count = 1 },

	Offers = { RevengeCooldownSeconds = 600, RevengeMinVictimLevel = 5, RevengeDelaySeconds = 3 },

	Fx = {
		ArcApex = 500,
		FireballMaxSize = 110,
		ShockwaveMult = 1.6,
		CloudHoldSeconds = 12,
		CloudFadeSeconds = 6,
		CleanupSeconds = 25,
		PartBudget = 48,
		PartBudgetLow = 24,
		ShakeMaxStuds = 2.2,
		ShakeSeconds = 1.8,
		ShakeFalloffStuds = 1200,
		SoundSpeed = 1100,
		MaxBoomDelay = 2,
		MarkerTransparency = 0.8,
		InterceptorRange = 350, -- cosmetic interceptors that miss (a nuke is never intercepted)
	},

	Audio = { SirenId = "", BoomId = "", LaunchId = "", SirenVolume = 0.5, BoomVolume = 1.0 },

	Text = {
		Incoming = "☢ NUKE INCOMING · %s · %s",
		InZone = "YOU'RE IN THE BLAST ZONE: RUN ➜",
		Protected = "🛡 You're protected (%s)",
		YourBase = "☢ YOUR BASE IS BEING NUKED by %s: run or get to your spawn pad!",
		Away = "☢ NUKE AWAY → %s · impact %s",
		Aborted = "NUKE ABORTED (%s)",
		Report = "☢ NUKE REPORT · Enemies %d · Hostiles %d · Squads %d · +%s XP · +$%s",
		Broadcast = "☢ %s's NUKE hit %s: %d eliminated",
		Revenge = "Nuked by %s. Strike back? ☢ Nuke",
		Ready = "☢ NUKE READY",
		AirspaceClear = "☢ Airspace clear: launch your Nuke",
		Refunded = "Your unfinished nuke launch was refunded",
		TargetLeft = "%s left: nuke returned",
		BaseNuked = "☢ Your base was nuked by %s. Nuke-proof for %s",
		SiloReady = "☢ Tactical Nuke ready in your Silo",
		Gift = "☢ First strike's on us: 1 Tactical Nuke. Tap ☢ to launch!",
		Reasons = {
			Disabled = "Nukes are switched off",
			Loading = "Your save is still loading",
			Dead = "Respawn first",
			NoInventory = "No nukes: get one (19 R$)",
			NoTactical = "No Tactical Nukes: build a Silo (Rebirth 2)",
			InFlight = "Airspace busy: a nuke is already inbound",
			ServerCooldown = "Airspace clears in %s",
			PlayerCooldown = "Launcher reloading %s",
			HourlyCap = "Launch limit: next in %s",
			Self = "That's your base",
			Ally = "Clan ally",
			TargetOffline = "Player left",
			TargetLoading = "Their save is still loading",
			NewPlayer = "New player protection: %s",
			Shielded = "🛡 Shielded %s",
			RecentlyNuked = "Recently nuked: %s",
			TooWeak = "Too weak to target",
			TooCloseToBase = "Too close to a base",
			OffMap = "Off the map",
			NoGround = "No ground there",
		} :: { [string]: string },
	},
}

function NukeConfig.DamageAt(def: KindDef, distance: number): number
	if distance <= def.CoreRadius then
		return def.CoreDamage
	end
	if distance > def.Radius then
		return 0
	end
	local t = (distance - def.CoreRadius) / math.max(1, def.Radius - def.CoreRadius)
	return math.floor(def.EdgeDamageMax - (def.EdgeDamageMax - def.EdgeDamageMin) * t + 0.5)
end

-- J8: damage to a (non-immune) vehicle at this distance; math.huge inside the core (destroyed outright).
function NukeConfig.VehicleDamageAt(def: KindDef, distance: number): number
	if distance > def.Radius then
		return 0
	end
	if distance <= def.CoreRadius and NukeConfig.Vehicles.CoreDestroys then
		return math.huge
	end
	return NukeConfig.DamageAt(def, distance) * NukeConfig.Vehicles.EdgeDamageMult
end

function NukeConfig.LaunchXP(def: KindDef, xpToNext: number): number
	local raw = (tonumber(xpToNext) or 0) * def.LaunchXPFactor
	if raw ~= raw or raw == math.huge then
		return def.LaunchXPMax
	end
	return math.clamp(math.floor(raw + 0.5), def.LaunchXPMin, def.LaunchXPMax)
end

function NukeConfig.Power(level: number, prestige: number): number
	return math.max(1, math.floor(level)) + math.max(0, math.floor(prestige)) * NukeConfig.Rules.PowerPerPrestige
end

-- Silo level 1..5 → build seconds / capacity (nil outside the table).
function NukeConfig.SiloBuildSeconds(level: number): number?
	return NukeConfig.Silo.BuildSeconds[math.floor(level)]
end

function NukeConfig.SiloCapacity(level: number): number
	return NukeConfig.Silo.Capacity[math.floor(level)] or 0
end

-- F10: the nuke target filter for a TerritoryConfig.Territories row (Home Outposts are skipped).
function NukeConfig.IsTerritoryTargetable(def: { IsStarter: boolean? }?): boolean
	if def == nil then
		return false
	end
	if NukeConfig.Targeting.SkipStarterOutposts and def.IsStarter == true then
		return false
	end
	return true
end

function NukeConfig.FormatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return NukeConfig
