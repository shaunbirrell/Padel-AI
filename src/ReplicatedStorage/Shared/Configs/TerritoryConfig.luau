--!strict
--[[ Territories + coastal oil platforms with capture stipends.
	F10 (owner's 11 features, lane K1): Starter = one owner-only Home Outpost per plot at plot-local (LocalX, LocalZ),
	about 100 studs out of the gate. While Starter.Enabled, the loop at the bottom appends Starter_P1 .. Starter_P6 to
	Territories (IsStarter = true, PlotId = n, BonusType "EmpireTax", BonusValue 0; worth
	EconomyConfig.OutpostIncomeBuff.StarterPct, never a stack, no stipend, cannot be stolen, evicted or nuked).
	Off = no rows, nothing changes. No require cycle: this file requires only BaseConfig and Shared/Util/PlotFrame
	(EconomyConfig, LevelConfig and OilRigConfig mention TerritoryConfig in comments only). ]]

local BaseConfig = require(script.Parent.BaseConfig)
local PlotFrame = require(script.Parent.Parent.Util.PlotFrame)

export type TerritoryDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	CaptureTimeSeconds: number,
	BonusType: string,
	BonusValue: number,
	Position: Vector3,
	Radius: number,
	Color: Color3,
	StipendCash: number?,
	IsOilRig: boolean?,
	IsFortress: boolean?,
	GuardNPCType: string?,
	GuardCount: number?,
	-- F10 Home Outposts (TerritoryConfig.Starter)
	IsStarter: boolean?, -- true only on the Starter_P<n> rows
	PlotId: number?, -- the plot whose owner alone can capture it (OwnerOnly)
	OwnerOnly: boolean?, -- only BaseService.GetOwnerUserId(PlotId) captures or contests
	Light: boolean?, -- false = no WE_OwnerLight / stripe on the marker
}

local TerritoryConfig = {
	-- Balance knobs
	MaxPersonalTerritories = 6, -- oil + fortresses + land POIs
	ProtectionPeriodSeconds = 45,
	CaptureTickSeconds = 0.5,
	ProgressDecayPerSecond = 0.35,
	ContestedProgressMult = 0,
	ContestedDecayMult = 0.5,
	ProtectedCaptureMult = 0.25,
	RadarRevealRadius = 550,
	NPCOwnerId = -1,
	NeutralOwnerId = 0,
	-- v70 waterways: vehicle passengers neither capture nor contest (only the driver of a vehicle counts), so a crewed
	-- boat or jeep no longer contests its own capture. Naval outposts (oil rigs): WaterConfig.NavalOutposts.
	VehiclePassengersCount = false,

	-- F10: owner-only Home Outpost per plot (see the header). Flag ships OFF; lane Z switches it on.
	Starter = {
		Enabled = false,
		LocalX = 38, -- plot-local; +Z = out of the main gate (PlotFrame / BaseLayout frame)
		LocalZ = 252,
		Radius = 20,
		CaptureTimeSeconds = 10,
		StipendCash = 0,
		DisplayName = "Home Outpost",
		Description = "Your own outpost: +5% Empire Tax while you hold it.",
		Color = Color3.fromRGB(90, 200, 120),
		OwnerOnly = true,
		Light = false,
		IdPrefix = "Starter_P", -- row ids Starter_P1 .. Starter_P<MaxPlots>
		GroundY = 1, -- world Y of the marker centre (same as the land outposts)
	},

	-- Periodic stipend for owned territories (MT-style ~every 90s)
	CaptureStipend = {
		TickSeconds = 90,
		DefaultCash = 4000,
		OilRigCash = 14000,
		FortressCash = 10000,
		NotifyOnPayout = false, -- v71 (HUD v70 spec §4.2): silent — the cash pill counts up; no toast every 90 s
	},

	OwnerTypes = {
		Neutral = "Neutral",
		Player = "Player",
		NPC = "NPC",
		Clan = "Clan",
		Contested = "Contested",
	},

	Territories = {
		CentralPlaza = {
			Id = "CentralPlaza",
			DisplayName = "Central Plaza",
			Description = "+10% Cash from passive income while controlled.",
			CaptureTimeSeconds = 20,
			BonusType = "PassiveCashMult",
			BonusValue = 0.10,
			Position = Vector3.new(0, 1, 0),
			Radius = 70,
			Color = Color3.fromRGB(200, 200, 80),
			StipendCash = 5000,
		},
		NorthRidge = {
			Id = "NorthRidge",
			DisplayName = "North Ridge",
			Description = "+5% XP from all sources.",
			CaptureTimeSeconds = 25,
			BonusType = "XPMult",
			BonusValue = 0.05,
			Position = Vector3.new(0, 1, -1300),
			Radius = 60,
			Color = Color3.fromRGB(80, 160, 220),
			StipendCash = 4000,
		},
		SouthDocks = {
			Id = "SouthDocks",
			DisplayName = "South Docks",
			Description = "+15% mission cash rewards.",
			CaptureTimeSeconds = 25,
			BonusType = "MissionCashMult",
			BonusValue = 0.15,
			Position = Vector3.new(0, 1, 1300),
			Radius = 60,
			Color = Color3.fromRGB(70, 140, 180),
			StipendCash = 4000,
		},
		EastArmory = {
			Id = "EastArmory",
			DisplayName = "East Armory",
			Description = "+10% weapon damage.",
			CaptureTimeSeconds = 30,
			BonusType = "DamageMult",
			BonusValue = 0.10,
			Position = Vector3.new(1300, 1, 0),
			Radius = 55,
			Color = Color3.fromRGB(200, 80, 80),
			StipendCash = 4500,
		},
		WestDepot = {
			Id = "WestDepot",
			DisplayName = "West Depot",
			Description = "Vehicle spawn cooldown -20%.",
			CaptureTimeSeconds = 30,
			BonusType = "VehicleCooldownMult",
			BonusValue = -0.20,
			Position = Vector3.new(-1300, 1, 0),
			Radius = 55,
			Color = Color3.fromRGB(100, 180, 100),
			StipendCash = 4500,
		},
		OilFields = {
			Id = "OilFields",
			DisplayName = "Oil Fields",
			Description = "+50 Cash per passive tick.",
			CaptureTimeSeconds = 35,
			BonusType = "FlatPassiveCash",
			BonusValue = 50,
			Position = Vector3.new(950, 1, 950),
			Radius = 65,
			Color = Color3.fromRGB(180, 140, 60),
			StipendCash = 6000,
		},
		RadarHill = {
			Id = "RadarHill",
			DisplayName = "Radar Hill",
			Description = "Enemy radar: highlight nearby hostile players within range.",
			CaptureTimeSeconds = 40,
			BonusType = "MinimapReveal",
			BonusValue = 1,
			Position = Vector3.new(-950, 1, -950),
			Radius = 60,
			Color = Color3.fromRGB(160, 100, 200),
			StipendCash = 5500,
		},
		-- Coastal oil platforms (MT-inspired ×2 oil; WAR EMPIRE naming)
		CoastalOilAlpha = {
			Id = "CoastalOilAlpha",
			DisplayName = "Coastal Oil Alpha",
			Description = "Offshore oil platform — take it by boat (drive into the lagoon) or from the deck. Harder guards.",
			CaptureTimeSeconds = 50,
			BonusType = "FlatPassiveCash",
			BonusValue = 100,
			Position = Vector3.new(1800, 28, -750), -- deck height matches MapSetup platform
			Radius = 48,
			Color = Color3.fromRGB(190, 145, 45),
			StipendCash = 14000,
			IsOilRig = true,
			GuardNPCType = "OilRigGuard",
			GuardCount = 4,
		},
		CoastalOilBravo = {
			Id = "CoastalOilBravo",
			DisplayName = "Coastal Oil Bravo",
			Description = "Offshore oil platform — take it by boat (drive into the lagoon) or from the deck. Harder guards.",
			CaptureTimeSeconds = 50,
			BonusType = "FlatPassiveCash",
			BonusValue = 100,
			Position = Vector3.new(-1800, 28, 750),
			Radius = 48,
			Color = Color3.fromRGB(170, 125, 40),
			StipendCash = 14000,
			IsOilRig = true,
			GuardNPCType = "OilRigGuard",
			GuardCount = 4,
		},
		-- Named fortresses (MT-inspired desert forts; higher stipend)
		FortIronclad = {
			Id = "FortIronclad",
			DisplayName = "Fort Ironclad",
			Description = "Fortress stronghold — high capture stipend. Fort guards.",
			CaptureTimeSeconds = 40,
			BonusType = "PassiveCashMult",
			BonusValue = 0.08,
			Position = Vector3.new(1450, 1, -1450),
			Radius = 55,
			Color = Color3.fromRGB(140, 145, 155),
			StipendCash = 10000,
			IsFortress = true,
			GuardNPCType = "FortGuard",
			GuardCount = 4,
		},
		FortSandhold = {
			Id = "FortSandhold",
			DisplayName = "Fort Sandhold",
			Description = "Desert fortress — high capture stipend. Fort guards.",
			CaptureTimeSeconds = 40,
			BonusType = "PassiveCashMult",
			BonusValue = 0.08,
			Position = Vector3.new(-1450, 1, 1450),
			Radius = 55,
			Color = Color3.fromRGB(190, 155, 90),
			StipendCash = 10000,
			IsFortress = true,
			GuardNPCType = "FortGuard",
			GuardCount = 4,
		},
	} :: { [string]: TerritoryDef },
}

-- F10: the Home Outpost rows, built only while Starter.Enabled (require time; pure math, no instances).
if TerritoryConfig.Starter.Enabled then
	local st = TerritoryConfig.Starter
	for n = 1, BaseConfig.MaxPlots do
		local p = PlotFrame.LocalToWorld(n, st.LocalX, st.LocalZ)
		local id = st.IdPrefix .. tostring(n)
		TerritoryConfig.Territories[id] = {
			Id = id,
			DisplayName = st.DisplayName,
			Description = st.Description,
			CaptureTimeSeconds = st.CaptureTimeSeconds,
			BonusType = "EmpireTax",
			BonusValue = 0,
			Position = Vector3.new(p.X, st.GroundY, p.Z),
			Radius = st.Radius,
			Color = st.Color,
			StipendCash = st.StipendCash,
			IsStarter = true,
			PlotId = n,
			OwnerOnly = st.OwnerOnly,
			Light = st.Light,
		}
	end
end

-- F10: true for a Home Outpost row (TerritoryService.IsStarterId, NukeConfig target filter, radar, lists).
function TerritoryConfig.IsStarterDef(def: TerritoryDef?): boolean
	return def ~= nil and def.IsStarter == true
end

return TerritoryConfig
