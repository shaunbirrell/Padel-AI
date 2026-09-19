--!strict
--[[
	Optional free Creator Store Model asset IDs for InsertService / AssetService.
	Part kits remain the authoritative fallback (always). Never use paid / MT-branded assets.

	Studio PERF: when DevConfig.StudioSkipWorldDressing and not StudioForceDress,
	VisualAssetService skips catalog inserts (8GB laptop). Live servers may load.

	IDs researched as Free on Creator Store (verify in Studio; enable
	Game Settings → Security → Allow Loading Third Party Assets for third-party models).
]]

export type AssetRef = {
	ModelAssetId: number?, -- InsertService / AssetService:LoadAssetAsync catalog Model
	MeshId: number?, -- optional SpecialMesh / MeshPart MeshId (0 = unused)
	Note: string?,
}

local VisualAssetConfig = {
	Enabled = true,
	StripScripts = true,
	MaxLoadAttempts = 24,
	VehicleVisualScale = 1.0,
	CharacterVisualScale = 1.0,

	Vehicles = {
		-- Free Jeep family
		MilitaryJeep = { ModelAssetId = 59524622, Note = "Free Jeep (Creator Store)" } :: AssetRef,
		ArmedJeep = { ModelAssetId = 59524622, Note = "Jeep reuse" } :: AssetRef,
		UtilityQuad = { ModelAssetId = 59524622, Note = "Jeep reuse (scaled by kit)" } :: AssetRef,
		ScoutCar = { ModelAssetId = 59524622, Note = "Jeep reuse" } :: AssetRef,
		ReconBuggy = { ModelAssetId = 59524622, Note = "Jeep reuse" } :: AssetRef,
		-- Free tank family
		LightTank = { ModelAssetId = 26007709, Note = "Free tank (Creator Store)" } :: AssetRef,
		MediumTank = { ModelAssetId = 26007709, Note = "Tank reuse" } :: AssetRef,
		BattleTank = { ModelAssetId = 1379706428, Note = "Panzer IV free port" } :: AssetRef,
		HeavyTank = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		SuperHeavyTank = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		TankDestroyer = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		AssaultGun = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		-- Free heli family
		TransportHeli = { ModelAssetId = 9337454, Note = "UH-60 free helicopter" } :: AssetRef,
		AttackHelicopter = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		LightTransportHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		NightAttackHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		LightScoutHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		GunshipHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		HeavyLiftHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		RescueHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		StealthHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		-- Classic free pack (trucks / APC fallback)
		_FallbackWheeled = { ModelAssetId = 28912351, Note = "Military Vehicle Meshes pack (free)" } :: AssetRef,
		PatrolTruck = { ModelAssetId = 28912351, Note = "Mesh pack" } :: AssetRef,
		ArmoredTruck = { ModelAssetId = 28912351, Note = "Mesh pack" } :: AssetRef,
		APC = { ModelAssetId = 28912351, Note = "Mesh pack" } :: AssetRef,
	} :: { [string]: AssetRef },

	Characters = {
		-- Official Roblox Soldier NPC kit (free)
		Soldier = { ModelAssetId = 3924234975, Note = "Official Roblox Soldier (Rthro)" } :: AssetRef,
		Guard = { ModelAssetId = 3924234975, Note = "Soldier reuse for guards" } :: AssetRef,
		BankGuard = { ModelAssetId = 3924234975, Note = "Soldier reuse" } :: AssetRef,
		OilRigGuard = { ModelAssetId = 3924234975, Note = "Soldier reuse" } :: AssetRef,
		FortGuard = { ModelAssetId = 3924234975, Note = "Soldier reuse" } :: AssetRef,
	} :: { [string]: AssetRef },

	Buildings = {
		CommandCenter = { ModelAssetId = 0, Note = "Part kit primary — set free HQ model when chosen" } :: AssetRef,
		Barracks = { ModelAssetId = 0, Note = "Part kit primary" } :: AssetRef,
		VehicleDepot = { ModelAssetId = 0, Note = "Part kit primary" } :: AssetRef,
	} :: { [string]: AssetRef },

	KitFamilyFallback = {
		WheeledLight = "MilitaryJeep",
		WheeledTruck = "_FallbackWheeled",
		WheeledAPC = "APC",
		TrackedIFV = "LightTank",
		TrackedMBT = "BattleTank",
		TrackedSPAAG = "LightTank",
		TrackedArtillery = "LightTank",
		HeliTransport = "TransportHeli",
		HeliAttack = "AttackHelicopter",
		HeliLight = "TransportHeli",
	} :: { [string]: string },
}

return VisualAssetConfig
