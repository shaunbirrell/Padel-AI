--!strict
--[[ v71 money (M2): Rebirth expansion.
	Zones that open with rebirth, per-rebirth perks, base trims, titles, and the Robux hook keys. Geometry lives in
	BaseLayoutConfig (M7b, using the waterways PlotCFrame / PlotLocalCFrame helpers, J18); each rebirth structure
	names its zone in BaseConfig.Structures[id].Zone (M7a).

	Pure helpers only. The server is the authority (RebirthExpansionService, PrestigeService, BaseService);
	the client calls the same helpers for display and never trusts them for grants.
	Config only: nothing reads this file yet. ZonesLive / WeaponsLive stay false until the M7b + M7d publish.

	Judge rulings applied (money/plan.md §1):
	- J12: the Expansion Permit and Rebirth Skip products are cut this round (no config entries, no
	  NextPermitZone, no profile counters). Revisit after 2 weeks of rebirth KPIs.
	  Superseded in part by the owner's 11 features (F7, ASSUMPTIONS): the 50 R$ Keep-Base Rebirth
	  (MonetizationConfig.DevProducts.RebirthKeepBase) is a consumable token counted in profile.KeepBaseRebirths and
	  spent by PrestigeService (PrestigeConfig.KeepBase); the rebirth runs after the receipt is saved, never inside it.
	  The Expansion Permit stays cut.
	- J13: Rebirth Boost is +15% cash per rebirth (instead of +10%) and 1.5x starting cash. Gold stays x1
	  (Boost.GoldMult = 1) until a Gold sink ships; then raise it together with the pass description. ]]

export type ZoneDef = {
	Id: string,
	Tier: number, -- opens at Prestige >= Tier
	DisplayName: string,
	Structures: { string },
	Parent: string?, -- nested zone (DroneBay sits inside StrategicYard)
}

export type TrimDef = {
	Id: string,
	DisplayName: string,
	MinPrestige: number,
	Trim: Color3, -- building trim, gate lintel, fence posts, flag finials
	Accent: Color3, -- banner field, sign text
	Gold: Color3, -- parapet caps / edge bands (HollowBuildingBuilder Colors.Gold)
	GoldCapAllLevels: boolean, -- gold parapet on every walk-in from L1 (not only L5)
	NeonEdge: boolean, -- thin neon strip along the plot pad edge
}

local RebirthConfig = {
	Enabled = true,
	-- Publish switches (M7b / M7d flip them in the release that ships the world and the guns)
	ZonesLive = false, -- locked-zone fences, rebirth structures and zone gating in BaseService
	WeaponsLive = false, -- the 7 rebirth guns (WeaponConfig RequiresPrestige rows)

	Zones = {
		WestYard = { Id = "WestYard", Tier = 1, DisplayName = "West Yard", Structures = { "TankFactory" } },
		StrategicYard = { Id = "StrategicYard", Tier = 2, DisplayName = "Strategic Yard", Structures = { "NuclearSilo" } },
		WestStrip = { Id = "WestStrip", Tier = 3, DisplayName = "West Battery", Structures = { "ArtilleryBattery" } },
		DroneBay = {
			Id = "DroneBay",
			Tier = 4,
			DisplayName = "Drone Bay",
			Structures = { "DroneHangar" },
			Parent = "StrategicYard",
		},
		EastYard = { Id = "EastYard", Tier = 5, DisplayName = "East Yard", Structures = { "EliteBarracks" } },
		EastStrip = { Id = "EastStrip", Tier = 6, DisplayName = "Refinery Row", Structures = { "OilRefinery" } },
		WestFlank = { Id = "WestFlank", Tier = 8, DisplayName = "West Flank", Structures = { "BunkerComplex" } },
	} :: { [string]: ZoneDef },
	ZoneOrder = { "WestYard", "StrategicYard", "WestStrip", "DroneBay", "EastYard", "EastStrip", "WestFlank" },

	Perks = {
		-- Army cap: +2 soldiers per rebirth (cap +40). Elite Barracks adds +5 per level on top (BaseConfig Effects).
		SoldiersPerPrestige = 2,
		MaxPrestigeSoldierBonus = 40,
		-- Cash you start each new run with: highest key <= Prestige wins (replaces the flat 10,000).
		StartingCashSteps = {
			{ AtPrestige = 1, Cash = 25_000 },
			{ AtPrestige = 2, Cash = 35_000 },
			{ AtPrestige = 3, Cash = 50_000 },
			{ AtPrestige = 4, Cash = 65_000 },
			{ AtPrestige = 5, Cash = 80_000 },
			{ AtPrestige = 6, Cash = 100_000 },
			{ AtPrestige = 10, Cash = 150_000 },
			{ AtPrestige = 20, Cash = 250_000 },
		},
		-- Gold on each rebirth: 50 + 10 per rebirth, max 250 (was a flat 50).
		GoldBase = 50,
		GoldPerPrestige = 10,
		GoldMax = 250,
		-- Rebirth grants in PrestigeConfig.RebirthUnlocks (GrantOwned vehicles) can be spawned at any Level /
		-- structure level: a reward you cannot use until you re-level is not a reward.
		GrantedVehiclesIgnoreRunGates = true,
	},

	-- Robux hooks. Keys point at MonetizationConfig entries; every one is hidden while its Id is 0.
	Boost = {
		GamePassKey = "RebirthBoost", -- NEW game pass (M1 adds the key with Id = 0; created OFF sale, J3)
		ExtraCashPerPrestige = 0.05, -- +15% per rebirth instead of +10% (retroactive: applies to past rebirths)
		GoldMult = 1, -- J13: Gold has no sink yet; x2 only with a Gold sink + a pass description update
		StartingCashMult = 1.5,
	},
	EliteThemePassKey = "ExtraPlotCosmetic", -- EXISTING live pass "Elite Base Theme" (Id 1983357731), finally implemented

	Trims = {
		{
			Id = "Standard",
			DisplayName = "Standard",
			MinPrestige = 0,
			Trim = Color3.fromRGB(78, 92, 62),
			Accent = Color3.fromRGB(230, 196, 70),
			Gold = Color3.fromRGB(240, 196, 64),
			GoldCapAllLevels = false,
			NeonEdge = false,
		},
		{
			Id = "Bronze",
			DisplayName = "Bronze",
			MinPrestige = 1,
			Trim = Color3.fromRGB(150, 98, 52),
			Accent = Color3.fromRGB(214, 150, 86),
			Gold = Color3.fromRGB(205, 127, 50),
			GoldCapAllLevels = false,
			NeonEdge = false,
		},
		{
			Id = "Silver",
			DisplayName = "Silver",
			MinPrestige = 3,
			Trim = Color3.fromRGB(150, 156, 164),
			Accent = Color3.fromRGB(222, 228, 236),
			Gold = Color3.fromRGB(196, 202, 210),
			GoldCapAllLevels = false,
			NeonEdge = false,
		},
		{
			Id = "Gold",
			DisplayName = "Gold",
			MinPrestige = 5,
			Trim = Color3.fromRGB(176, 140, 44),
			Accent = Color3.fromRGB(255, 214, 90),
			Gold = Color3.fromRGB(240, 196, 64),
			GoldCapAllLevels = true,
			NeonEdge = false,
		},
		{
			Id = "Platinum",
			DisplayName = "Platinum",
			MinPrestige = 10,
			Trim = Color3.fromRGB(200, 210, 220),
			Accent = Color3.fromRGB(120, 220, 255),
			Gold = Color3.fromRGB(226, 234, 242),
			GoldCapAllLevels = true,
			NeonEdge = true,
		},
		{
			Id = "Obsidian",
			DisplayName = "Obsidian",
			MinPrestige = 20,
			Trim = Color3.fromRGB(34, 34, 40),
			Accent = Color3.fromRGB(255, 196, 64),
			Gold = Color3.fromRGB(255, 196, 64),
			GoldCapAllLevels = true,
			NeonEdge = true,
		},
	} :: { TrimDef },
	-- Elite Base Theme pass: at least Gold at any Prestige; Platinum+ players keep their higher trim.
	EliteThemeMinTrim = "Gold",

	-- Cosmetic dressing unlocked by rebirth count (all Part-built, <= 40 parts per plot in total).
	Dressing = {
		GateBannersAt = 1, -- two vertical banners either side of the main gate: "★ n"
		CommandCenterBannerAt = 3,
		WalkInBannersAt = 5, -- one banner on every walk-in facade
		EmpireBeaconAt = 10, -- a tall light beam from the Command Center roof, visible across the map
		JoinFireworksAt = 25,
		CommanderStatueAt = 50,
	},

	Titles = {
		{ AtPrestige = 1, Title = "Veteran" },
		{ AtPrestige = 3, Title = "Commander" },
		{ AtPrestige = 5, Title = "General" },
		{ AtPrestige = 10, Title = "Marshal" },
		{ AtPrestige = 20, Title = "Legend" },
		{ AtPrestige = 30, Title = "Mythic" },
		{ AtPrestige = 50, Title = "Supreme Commander" },
	},
	LeaderstatName = "Rebirths",

	-- How a locked zone looks (StructureKitBuilder.SyncExpansionZones)
	LockedLook = {
		FenceHeight = 8,
		PostSpacing = 16,
		PostColor = Color3.fromRGB(58, 60, 58),
		MeshColor = Color3.fromRGB(40, 42, 40),
		MeshTransparency = 0.55,
		HazardColor = Color3.fromRGB(230, 196, 70),
		SignColor = Color3.fromRGB(170, 28, 28),
		HologramColor = Color3.fromRGB(88, 200, 255),
		HologramTransparency = 0.7,
		LabelMaxDistance = 60, -- WorldLabelPolicy
	},
}

local function stepValue(steps: { { AtPrestige: number, Cash: number } }, prestige: number, default: number): number
	local best = default
	for _, s in ipairs(steps) do
		if prestige >= s.AtPrestige then
			best = s.Cash
		end
	end
	return best
end

-- Zone id for a structure, or nil for the 15 base structures.
function RebirthConfig.ZoneOfStructure(structureId: string): string?
	for id, z in pairs(RebirthConfig.Zones) do
		for _, sid in ipairs(z.Structures) do
			if sid == structureId then
				return id
			end
		end
	end
	return nil
end

-- A zone is open when Prestige reached its tier. `extraOpen` is a session-only override (the admin `openzone`
-- command); the Expansion Permit that used to feed it was cut (J12). A nested zone also needs its parent open.
function RebirthConfig.IsZoneOpen(prestige: number, extraOpen: { [string]: boolean }?, zoneId: string): boolean
	if not RebirthConfig.Enabled then
		return false
	end
	local z = RebirthConfig.Zones[zoneId]
	if not z then
		return false
	end
	local open = prestige >= z.Tier or (extraOpen ~= nil and extraOpen[zoneId] == true)
	if open and z.Parent ~= nil then
		return RebirthConfig.IsZoneOpen(prestige, extraOpen, z.Parent)
	end
	return open
end

-- Structures outside every zone are always "open".
function RebirthConfig.IsStructureOpen(prestige: number, extraOpen: { [string]: boolean }?, structureId: string): boolean
	local zoneId = RebirthConfig.ZoneOfStructure(structureId)
	if zoneId == nil then
		return true
	end
	return RebirthConfig.IsZoneOpen(prestige, extraOpen, zoneId)
end

function RebirthConfig.StartingCash(prestige: number, boosted: boolean): number
	local cash = stepValue(RebirthConfig.Perks.StartingCashSteps, prestige, 10_000)
	if boosted then
		cash = math.floor(cash * RebirthConfig.Boost.StartingCashMult)
	end
	return cash
end

function RebirthConfig.GoldBonus(prestige: number, boosted: boolean): number
	local p = RebirthConfig.Perks
	local gold = math.min(p.GoldMax, p.GoldBase + p.GoldPerPrestige * math.max(0, prestige - 1))
	if boosted then
		gold *= RebirthConfig.Boost.GoldMult
	end
	return math.floor(gold)
end

-- +cash per rebirth as a fraction (0.10, or 0.15 with Rebirth Boost). Callers apply 1 + prestige * this.
function RebirthConfig.CashBonusPerPrestige(baseBonus: number, boosted: boolean): number
	if boosted then
		return baseBonus + RebirthConfig.Boost.ExtraCashPerPrestige
	end
	return baseBonus
end

function RebirthConfig.PrestigeSoldierBonus(prestige: number): number
	local p = RebirthConfig.Perks
	return math.min(p.MaxPrestigeSoldierBonus, math.max(0, prestige) * p.SoldiersPerPrestige)
end

function RebirthConfig.TrimFor(prestige: number, eliteThemePass: boolean): TrimDef
	local best = RebirthConfig.Trims[1]
	for _, t in ipairs(RebirthConfig.Trims) do
		if prestige >= t.MinPrestige then
			best = t
		end
	end
	if eliteThemePass then
		local floorIdx = 1
		local bestIdx = 1
		for i, t in ipairs(RebirthConfig.Trims) do
			if t.Id == RebirthConfig.EliteThemeMinTrim then
				floorIdx = i
			end
			if t.Id == best.Id then
				bestIdx = i
			end
		end
		if bestIdx < floorIdx then
			best = RebirthConfig.Trims[floorIdx]
		end
	end
	return best
end

function RebirthConfig.TitleFor(prestige: number): string?
	local title: string? = nil
	for _, t in ipairs(RebirthConfig.Titles) do
		if prestige >= t.AtPrestige then
			title = t.Title
		end
	end
	return title
end

return RebirthConfig
