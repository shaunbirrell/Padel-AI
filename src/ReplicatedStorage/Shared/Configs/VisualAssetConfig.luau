--!strict
--[[
	Optional free Creator Store Model / MeshPart asset IDs for InsertService / AssetService.
	Part kits remain the authoritative fallback (always). Never use paid / MT-branded assets.
	AssetId = 0 means skip the insert (Part kit only).

	Owner default D1 (roadmap §8): Game Settings → Security → "Allow Loading Third Party Assets" stays OFF.
	With it OFF, LoadAssetAsync loads Roblox-owned assets and assets in the inventory of the game's owner (the user
	who owns the experience); any other ID fails (a "not authorized / not trusted" error is final at once; any other
	error is retried in the background, LoadRetry* below, then cached) and the Part kit stays.

	Owner asset list (2026-09-25, docs/ASSET_WIRING.md): the owner's Creator Store picks are wired in two ways.
	  • Roblox-owned picks (creator Roblox, User 1) load with the switch OFF and are wired here directly.
	  • A third-party pick is recorded as PendingAssetId next to the live field, with its store name and creator in
	    Note. VisualAssetService NEVER reads PendingAssetId: no load attempt, no MaxLoadAttempts cost, no change on
	    screen. tools/wire-asset-ids.py moves it to ModelAssetId after its gates (in the owner's inventory, store
	    re-check, the owner's yes/no, a Studio WE_CHECK with <= 40 parts and no Humanoid, the load budget) and writes
	    its docs/ASSET_LICENSES.md row in the same commit.
	  • Owner rule 5: the three heavy building models are cleared (0) and never come back (BuyPathStatic pins).

	W1 CFG (roadmap §1.4, §2.2 item 5): these entries are set to 0 and fall back to the Part kit
	(vehicles first try their KitFamilyFallback body):
	  • paid, or no longer distributed on the Creator Store;
	  • a copy of a named real-world or franchise design (vehicle, ship, weapon, unit, brand or country);
	  • provenance not OK (the upload says it is from another game or is someone else's work).
	Every remaining ID with its owner, terms and why it is allowed: docs/ASSET_LICENSES.md.
	A new ID must be free, the uploader's own work, no real-world/franchise design and no brand text,
	and gets its row in docs/ASSET_LICENSES.md in the same commit.

	Studio PERF: when DevConfig.StudioSkipWorldDressing and not StudioForceDress,
	VisualAssetService skips catalog inserts (8GB laptop). Live servers may load.

	Design P0 REJECT: JeepFallback 59524622; SWAT/police; blocky soldiers; 107381 as vehicle.
	Design P0 REJECT primary: 3924234975 plastic Rthro; 91299598767068 Respawn Soldiers pack.

	W3 LOOK (roadmap §2.4, asset shortlist §6.2 C1/C7): Roblox-owned packs (creator Roblox, User 1) load with the
	third-party switch OFF. One pack serves many keys: `ChildName` picks one piece (pack:FindFirstChild(ChildName, true),
	never split on "/"), `SubModel` a descendant of that piece. Each pack loads once; the chosen pieces are kept as
	templates in ServerStorage and the rest is dropped. Every inserted template is <= MaxPartsPerModel parts and has no
	Humanoid, or it is refused and the Part kit stays.
]]

export type AssetRef = {
	ModelAssetId: number?, -- InsertService / AssetService:LoadAssetAsync catalog Model
	MeshId: number?, -- optional SpecialMesh / MeshPart MeshId (0 = unused)
	Note: string?,
	-- W3 LOOK: one piece of a (Roblox-owned) pack
	ChildName: string?, -- found with pack:FindFirstChild(ChildName, true); names contain "/" (never split)
	SubModel: string?, -- then this descendant of the piece (e.g. "Body": drops Chassis / Scripts / Effects)
	Color: Color3?, -- single-part pieces: flat colour (with ClearTexture)
	Material: Enum.Material?, -- single-part pieces
	ClearTexture: boolean?, -- TextureID = "" and no SurfaceAppearance: flat desert palette, no stray text
	StripDecals: boolean?, -- drop Decals / Textures (phone draw calls; the LUV camo decals are not Roblox-owned images)
	Fit: string?, -- "Kit": vehicle body scaled to the kit chassis length, tyres on the physics-wheel bottoms
	Yaw: number?, -- Fit: degrees from the piece's front (-Z) to the kit's front (-Z)
	HideKit: boolean?, -- Fit: hide the Part-kit visuals under the body (physics, seats and hitboxes unchanged)
	KeepVisible: { string }?, -- HideKit: kit part names that stay visible (the Armed 4x4 keeps its Part turret)
	-- Owner asset list (2026-09-25)
	PendingAssetId: number?, -- the owner's third-party pick; NEVER loaded (VisualAssetService ignores it); tools/wire-asset-ids.py promotes it
	OmitParts: { string }?, -- pack piece: BaseParts with these names are removed before the part count (Pickup Truck tail-light glass)
	NoFamilyFallback: boolean?, -- vehicle ref at 0: keep the Part kit, never take the KitFamilyFallback body
}

local VisualAssetConfig = {
	Enabled = true,
	StripScripts = true,
	MaxLoadAttempts = 48, -- per server, first tries + retries; an id asked for after that keeps its Part kit (one Output line)
	-- A LoadAsset that fails with a transient error (HTTP 5xx / 429 / timeout) is retried in the background, never in
	-- the caller's thread (boot and spawns never wait): up to LoadRetryCount more tries, LoadRetryDelay seconds after
	-- the failure, x LoadRetryBackoff after each (20 s, 40 s). Every retry counts toward MaxLoadAttempts. An error
	-- containing any LoadRetryPermanentErrors text (lower-case) is final: no retry. Until a retry succeeds the Part kit
	-- look stays; hosts dressed before it keep their Part kit, later ones get the model.
	LoadRetryCount = 2,
	LoadRetryDelay = 20,
	LoadRetryBackoff = 2,
	-- the last LoadRetryReserve attempts of MaxLoadAttempts are kept for FIRST loads (a later spawn's model): a retry
	-- that would use one is not made (the id is final, one line). Keeps a full outage at boot from using up the
	-- budget later ids need (fix57 census: <= 19 ids at boot, <= 6 later, fallbacks included).
	LoadRetryReserve = 12,
	-- Owner asset list (2026-09-25): 48 / 12 stay. tools/wire-asset-ids.py refuses a promote batch that would take the
	-- distinct live ids past MaxLoadAttempts - 8 (= 40). PendingAssetId ids are never loaded, so they cost 0.
	LoadRetryPermanentErrors = {
		"not trusted",
		"not authorized",
		"not authorised",
		"permission",
		"forbidden",
		"http 403",
		"http 400",
		"http 404",
		"does not exist",
		"not found",
		"moderated",
		"not approved",
		"archived",
		"invalid",
	},
	MaxPartsPerModel = 40, -- CLAUDE.md catalog budget: an inserted template with more BaseParts is refused (Part kit stays)
	-- Whole models whose Fire / Smoke / Sparkles / ParticleEmitter / Light / Beam / Trail are removed when the template
	-- is prepared (phone cost). 23153991 = Roblox "Smoking Barrel" (the training-yard oil drum, smoke removed).
	StripEffectsAssetIds = { 23153991 },
	FitShadowShare = 0.5, -- fitted vehicle bodies: only parts at least this share of the chassis length cast a shadow
	VehicleVisualScale = 1.0, -- Design clamp 0.85–1.2 (dress mesh only)
	CharacterVisualScale = 1.0,
	BuildingVisualScale = 1.0, -- ScaleTo uses TargetFootprint; do NOT squash to plinth
	PropVisualScale = 1.0,

	Vehicles = {
		-- Owner asset list (2026-09-25): Roblox-owned car bodies (Dune Buggy, Pickup Truck, Van) are wired below the
		-- same way as the Light Utility Vehicle; third-party picks wait in PendingAssetId (never loaded).
		-- Light 4x4 family (KitFamilyFallback.WheeledLight = MilitaryJeep): W3 LOOK wires Roblox's own Light Utility
		-- Vehicle 6418221666 (creator Roblox, User 1; verified 2026-09-24, docs/ASSET_LICENSES.md §3). Only the green camo
		-- "Body" sub-model (39 MeshParts) is kept; its Chassis, scripts, seats and sounds are never used. The Part kit
		-- stays the physics body; the Armed 4x4 keeps its Part turret. 0 here = Part kit only (one-line revert).
		MilitaryJeep = {
			ModelAssetId = 6418221666,
			ChildName = "Light Utility Vehicle (green camo)",
			SubModel = "Body",
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			KeepVisible = { "GunMount", "Barrel" },
			StripDecals = true,
			Note = "W3 LOOK: Roblox Light Utility Vehicle body (NO JeepFallback); dress-only, Part kit drives",
		} :: AssetRef,
		ArmedJeep = { ModelAssetId = 0, Note = "W1 CFG drop (real-world design) → WheeledLight family body (MilitaryJeep: Roblox LUV body + our Part turret), else Part kit" } :: AssetRef,
		UtilityQuad = {
			ModelAssetId = 6433272094,
			ChildName = "Dune Buggy (beige)",
			SubModel = "Body",
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			StripDecals = true,
			Note = "owner list: Roblox Dune Buggy (beige) Body (23 MeshParts, no decals), fitted to the kit; dress-only, the Part kit drives. 0 = the WheeledLight family body",
		} :: AssetRef,
		ScoutCar = { ModelAssetId = 0, Note = "0 → WheeledLight family body (MilitaryJeep)" } :: AssetRef,
		ReconBuggy = {
			ModelAssetId = 6433272094,
			ChildName = "Dune Buggy (beige)",
			SubModel = "Body",
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			StripDecals = true,
			Note = "owner list: Roblox Dune Buggy (beige) Body (23 MeshParts, no decals), fitted to the kit; dress-only, the Part kit drives. 0 = the WheeledLight family body",
		} :: AssetRef,
		-- Free tank family
		LightTank = { ModelAssetId = 0, Note = "owner list: [WEAK] low-poly tank declined, our Part kit reads better - Part kit" } :: AssetRef,
		MediumTank = { ModelAssetId = 0, Note = "owner list: [WEAK] low-poly tank declined, our Part kit reads better - Part kit" } :: AssetRef,
		-- W1 CFG drop (franchise design): TrackedMBT family → BattleTank = 0 → Part kit
		BattleTank = { ModelAssetId = 0, Note = "owner list: [WEAK] low-poly tank declined, our Part kit reads better - Part kit" } :: AssetRef,
		HeavyTank = { ModelAssetId = 0, Note = "owner list: [WEAK] low-poly tank declined, our Part kit reads better - Part kit" } :: AssetRef,
		SuperHeavyTank = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
		TankDestroyer = { ModelAssetId = 0, Note = "owner list: [WEAK] low-poly tank declined, our Part kit reads better - Part kit" } :: AssetRef,
		AssaultGun = { ModelAssetId = 0, Note = "owner list: [WEAK] low-poly tank declined, our Part kit reads better - Part kit" } :: AssetRef,
		-- Free heli family
		TransportHeli = { ModelAssetId = 0, PendingAssetId = 2627182035, Note = "owner pick transport helicopter (blokkere): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		AttackHelicopter = { ModelAssetId = 0, Note = "owner list: pick rejected (franchise copy) - family body / Part kit" } :: AssetRef,
		LightTransportHeli = { ModelAssetId = 0, PendingAssetId = 2627182035, Note = "owner pick transport helicopter (blokkere): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		NightAttackHeli = { ModelAssetId = 0, Note = "owner list: pick rejected (franchise copy) - family body / Part kit" } :: AssetRef,
		LightScoutHeli = { ModelAssetId = 0, PendingAssetId = 2474869838, Note = "owner pick Low poly helicopter (Azarth): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		GunshipHeli = { ModelAssetId = 0, Note = "owner list: pick rejected (franchise copy) - family body / Part kit" } :: AssetRef,
		HeavyLiftHeli = { ModelAssetId = 0, PendingAssetId = 2627182035, Note = "owner pick transport helicopter (blokkere): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		RescueHeli = { ModelAssetId = 0, PendingAssetId = 11357157285, Note = "owner pick Rescue Helicopter (KiboSprite): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		StealthHeli = { ModelAssetId = 0, Note = "Gunship/stealth heli" } :: AssetRef,
		-- Classic free pack (trucks / APC fallback)
		_FallbackWheeled = { ModelAssetId = 0, Note = "Military Vehicle Meshes pack (free)" } :: AssetRef,
		PatrolTruck = {
			ModelAssetId = 6418225759,
			ChildName = "Pickup Truck (bronze)",
			SubModel = "Body",
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			StripDecals = true,
			OmitParts = { "light_tail_glass" },
			Note = "owner list: Roblox Pickup Truck (bronze) Body (41 MeshParts; the overlapping tail-light glass is omitted = 40), fitted to the kit; dress-only, the Part kit drives. 0 = Part kit",
		} :: AssetRef,
		ArmoredTruck = { ModelAssetId = 0, PendingAssetId = 8546141386, Note = "owner pick Military Truck (LouBrawlerStars): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		APC = { ModelAssetId = 0, PendingAssetId = 9076240315, Note = "owner pick APC (CorzCringe): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		-- Free jet family (classic + named free fighter)
		_FallbackJet = { ModelAssetId = 0, Note = "Classic free fighter jet" } :: AssetRef,
		FighterJet = { ModelAssetId = 0, PendingAssetId = 3553891209, Note = "owner pick Fighter Jet concept (PlanesFun56): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		InterceptorJet = { ModelAssetId = 0, PendingAssetId = 3553891209, Note = "owner pick Fighter Jet concept (PlanesFun56): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		TrainerJet = { ModelAssetId = 0, PendingAssetId = 3553891209, Note = "owner pick Fighter Jet concept (PlanesFun56): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		ReconPlane = { ModelAssetId = 0, PendingAssetId = 4954987035, Note = "owner pick Old propeller plane (Deadex40_Extra): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		LightFighter = { ModelAssetId = 0, PendingAssetId = 3553891209, Note = "owner pick Fighter Jet concept (PlanesFun56): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		StrikeJet = { ModelAssetId = 0, Note = "owner list: pick rejected (real-world aircraft copy) - family body / Part kit" } :: AssetRef,
		CASJet = { ModelAssetId = 0, Note = "owner list: pick rejected (real-world aircraft copy) - family body / Part kit" } :: AssetRef,
		StealthStrikeJet = { ModelAssetId = 0, Note = "Strike/CAS jet" } :: AssetRef,
		StrikeBomber = { ModelAssetId = 0, Note = "owner list: pick rejected (national-style insignia, not the uploader's own work) - family body / Part kit" } :: AssetRef,
		CargoPlane = { ModelAssetId = 0, Note = "owner list: pick rejected (47 parts > 40 and a real-world look) - family body / Part kit" } :: AssetRef,
		AWACSPlane = { ModelAssetId = 0, Note = "owner list: pick rejected (47 parts > 40 and a real-world look) - family body / Part kit" } :: AssetRef,
		TankerPlane = { ModelAssetId = 0, Note = "owner list: pick rejected (47 parts > 40 and a real-world look) - family body / Part kit" } :: AssetRef,
		-- Free naval family
		_FallbackNaval = { ModelAssetId = 0, Note = "Free Boat (Creator Store)" } :: AssetRef,
		PatrolBoat = { ModelAssetId = 0, PendingAssetId = 5177695483, Note = "owner pick Patrol Boat (pirateparty1234): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		FastAttackCraft = { ModelAssetId = 0, PendingAssetId = 5177695483, Note = "owner pick Patrol Boat (pirateparty1234): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		RiverBoat = { ModelAssetId = 0, Note = "owner list: pick rejected (wrong item: a theme-park raft; provenance) - family body / Part kit" } :: AssetRef,
		CoastCutter = { ModelAssetId = 0, PendingAssetId = 5177695483, Note = "owner pick Patrol Boat (pirateparty1234): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		TorpedoBoat = { ModelAssetId = 0, PendingAssetId = 5177695483, Note = "owner pick Patrol Boat (pirateparty1234): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		Gunboat = { ModelAssetId = 0, PendingAssetId = 15838664806, Note = "owner pick Basic Gunboat (Confused Giants Studio): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		MissileBoat = { ModelAssetId = 0, PendingAssetId = 15838664806, Note = "owner pick Basic Gunboat (Confused Giants Studio): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		MineLayer = { ModelAssetId = 0, PendingAssetId = 15838664806, Note = "owner pick Basic Gunboat (Confused Giants Studio): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		CoastalMonitor = { ModelAssetId = 0, PendingAssetId = 15838664806, Note = "owner pick Basic Gunboat (Confused Giants Studio): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		LandingCraft = { ModelAssetId = 0, Note = "Part-kit barge — REJECT 13195201090 template; owner list: pick rejected (wrong item: a space lander)" } :: AssetRef,
		AssaultLanding = { ModelAssetId = 0, Note = "Part-kit — REJECT 13195201090; owner list: pick rejected (wrong item: a space lander)" } :: AssetRef,
		HoverTransport = { ModelAssetId = 0, PendingAssetId = 43773162, Note = "owner pick HoverCraft (Fractality): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		HospitalShip = { ModelAssetId = 0, Note = "owner list: pick rejected (protected emblem and a named real ship) - family body / Part kit" } :: AssetRef,
		SupplyShip = { ModelAssetId = 0, PendingAssetId = 11756438288, Note = "owner pick Cargo Ship (Yorsiur): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		AmphibAssault = { ModelAssetId = 0, Note = "Part-kit capital stub — REJECT 13195201090; owner list: pick rejected (wrong item: a space lander)" } :: AssetRef,
		Corvette = { ModelAssetId = 0, Note = "owner list: [WEAK] plain warship hull declined, our NavalCapital kit reads better - Part kit" } :: AssetRef,
		Destroyer = { ModelAssetId = 0, Note = "W1 CFG drop (real-world ship) — NavalCapital → Part kit; owner list: [WEAK] warship pick declined" } :: AssetRef,
		Frigate = { ModelAssetId = 0, Note = "owner list: [WEAK] plain warship hull declined, our NavalCapital kit reads better - Part kit" } :: AssetRef,
		CarrierEscort = { ModelAssetId = 0, Note = "owner list: [WEAK] plain warship hull declined, our NavalCapital kit reads better - Part kit" } :: AssetRef,
		Battleship = { ModelAssetId = 0, Note = "W1 CFG drop (real-world ship) — NavalCapital → Part kit" } :: AssetRef,
		AircraftCarrier = { ModelAssetId = 0, Note = "Part-kit capital — REJECT 13195201090" } :: AssetRef,
		SubSurfaceRunner = { ModelAssetId = 0, Note = "Boat reuse (surface stub)" } :: AssetRef,
		AttackSub = { ModelAssetId = 0, Note = "Boat reuse (surface stub)" } :: AssetRef,
		-- Explicit aliases for depth-pass IDs (KitFamilyFallback also covers these)
		SupplyTruck = { ModelAssetId = 0, PendingAssetId = 8546141386, Note = "owner pick Military Truck (LouBrawlerStars): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		FuelTanker = { ModelAssetId = 0, PendingAssetId = 5318635087, Note = "owner pick fuel truck (asp307): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		EngineeringTruck = { ModelAssetId = 0, Note = "owner list: pick rejected (cannot be checked from the store) - family body / Part kit" } :: AssetRef,
		FlatbedHauler = { ModelAssetId = 0, PendingAssetId = 8455894899, Note = "owner pick FlatBed Truck (YourBoi_JonnyBoi): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		AmmoCarrier = { ModelAssetId = 0, PendingAssetId = 8546141386, Note = "owner pick Military Truck (LouBrawlerStars): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		MissileTruck = { ModelAssetId = 0, PendingAssetId = 3304171953, Note = "owner pick missile truck (KlassicKanadian): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		AntiAirTruck = { ModelAssetId = 0, PendingAssetId = 8546141386, Note = "owner pick Military Truck (LouBrawlerStars): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		RadarTruck = { ModelAssetId = 0, PendingAssetId = 31538715, Note = "owner pick RMAR truck radar (Armour_Fox): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		CargoVan = {
			ModelAssetId = 6433316269,
			ChildName = "Van (white)",
			SubModel = "Body",
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			StripDecals = true,
			Note = "owner list: Roblox Van (white) Body (26 MeshParts, no decals), fitted to the kit; dress-only, the Part kit drives. 0 = Part kit",
		} :: AssetRef,
		TroopTransport = { ModelAssetId = 0, PendingAssetId = 8546141386, Note = "owner pick Military Truck (LouBrawlerStars): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		RecoveryTruck = { ModelAssetId = 0, PendingAssetId = 8546141386, Note = "owner pick Military Truck (LouBrawlerStars): pending, P3 (owner yes/no, Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		EscortTruck = {
			ModelAssetId = 6418225759,
			ChildName = "Pickup Truck (bronze)",
			SubModel = "Body",
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			StripDecals = true,
			OmitParts = { "light_tail_glass" },
			Note = "owner list: Roblox Pickup Truck (bronze) Body (41 MeshParts; the overlapping tail-light glass is omitted = 40), fitted to the kit; dress-only, the Part kit drives. 0 = Part kit",
		} :: AssetRef,
		InfantryCarrier = { ModelAssetId = 0, PendingAssetId = 9076240315, Note = "owner pick APC (CorzCringe): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		CommandVehicle = { ModelAssetId = 0, PendingAssetId = 9076240315, Note = "owner pick APC (CorzCringe): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		WheeledIFV = { ModelAssetId = 0, PendingAssetId = 9076240315, Note = "owner pick APC (CorzCringe): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		AmphibiousAPC = { ModelAssetId = 0, PendingAssetId = 9076240315, Note = "owner pick APC (CorzCringe): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		CombatIFV = { ModelAssetId = 0, PendingAssetId = 11552687660, Note = "owner pick Fiction IFV (spookstiy): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		AssaultIFV = { ModelAssetId = 0, PendingAssetId = 11552687660, Note = "owner pick Fiction IFV (spookstiy): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		BridgeLayer = { ModelAssetId = 0, NoFamilyFallback = true, Note = "owner list: no good match, keep the current build (Part kit; NoFamilyFallback: never a TrackedIFV family body)" } :: AssetRef,
		MineClearer = { ModelAssetId = 0, Note = "owner list: pick rejected (wrong item, provenance unverified) - family body / Part kit" } :: AssetRef,
		FlameCarrier = { ModelAssetId = 0, PendingAssetId = 11552687660, Note = "owner pick Fiction IFV (spookstiy): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		SPAAG = { ModelAssetId = 0, PendingAssetId = 10069416832, Note = "owner pick anti aircraft Tank (XCX1001): pending, P3 (Studio WE_CHECK, [WEAK]); family body / Part kit until promoted" } :: AssetRef,
		MobileSAM = { ModelAssetId = 0, PendingAssetId = 10069416832, Note = "owner pick anti aircraft Tank (XCX1001): pending, P3 (Studio WE_CHECK, [WEAK]); family body / Part kit until promoted" } :: AssetRef,
		MortarCarrier = { ModelAssetId = 0, Note = "owner list: [WEAK] a stand-alone mortar, no vehicle - Part kit" } :: AssetRef,
		MobileArtillery = { ModelAssetId = 0, Note = "owner list: [WEAK] crude towed gun declined, our Part kit reads better - Part kit" } :: AssetRef,
		RocketArtillery = { ModelAssetId = 0, PendingAssetId = 3304171953, Note = "owner pick missile truck (KlassicKanadian): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		HowitzerTruck = { ModelAssetId = 0, Note = "owner list: [WEAK] crude towed gun declined, our Part kit reads better - Part kit" } :: AssetRef,
		SiegeMortar = { ModelAssetId = 0, Note = "owner list: [WEAK] crude towed gun declined, our Part kit reads better - Part kit" } :: AssetRef,
		LightScoutTank = { ModelAssetId = 0, Note = "owner list: [WEAK] low-poly tank declined, our Part kit reads better - Part kit" } :: AssetRef,
		FortressTank = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
		RailgunCarrier = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) → TrackedArtillery family body, else Part kit" } :: AssetRef,
		DispatchCar = { ModelAssetId = 0, Note = "0 → WheeledLight family body (MilitaryJeep, fitted to the smaller kit)" } :: AssetRef,
		UtilityHeli = { ModelAssetId = 0, PendingAssetId = 2474869838, Note = "owner pick Low poly helicopter (Azarth): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		MedevacHeli = { ModelAssetId = 0, PendingAssetId = 11357157285, Note = "owner pick Helicopter (Rescue) (KiboSprite): pending, P3 (Studio WE_CHECK); family body / Part kit until promoted" } :: AssetRef,
		EscortHeli = { ModelAssetId = 0, Note = "owner list: pick rejected (franchise copy) - family body / Part kit" } :: AssetRef,
		VTOLTransport = { ModelAssetId = 0, Note = "owner list: pick rejected (provenance) - family body / Part kit" } :: AssetRef,
		HeavyBomber = { ModelAssetId = 0, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
		StealthStrike = { ModelAssetId = 0, Note = "Strike/CAS jet" } :: AssetRef,
		-- Depth-pass capital / bomber IDs previously missing from catalog map
		Cruiser = { ModelAssetId = 0, Note = "W1 CFG drop (real-world ship) — NavalCapital → Part kit" } :: AssetRef,
		MissileCruiser = { ModelAssetId = 0, Note = "W1 CFG drop (real-world ship) — NavalCapital → Part kit" } :: AssetRef,
		FleetCarrier = { ModelAssetId = 0, Note = "Part-kit capital — REJECT 13195201090" } :: AssetRef,
		StrategicBomber = { ModelAssetId = 0, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
	} :: { [string]: AssetRef },

	Characters = {
		-- Design Bot 2026-09-20: realistic human mesh. REJECT plastic 3924234975 + Respawn 91299598767068.
		Soldier = { ModelAssetId = 100212659702941, Note = "Realistic soldier StarterCharacter (gas-mask/spec-ops)" } :: AssetRef,
		Infantry = { ModelAssetId = 9104381136, Note = "Layered clothing realistic soldier (helmet+MOLLE)" } :: AssetRef,
		Worker = { ModelAssetId = 16134469614, Note = "v41 distinct Worker (Rigged Soldier NVG)" } :: AssetRef,
		WorkerFallback = { ModelAssetId = 9104381136, Note = "Worker fallback Infantry mesh if Guard insert fails" } :: AssetRef,
		HeavyInfantry = { ModelAssetId = 0, Note = "Army of Soldiers Rthro swarm pack" } :: AssetRef,
		Guard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		BankGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		OilRigGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		FortGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		GateGuard = { ModelAssetId = 16134469614, Note = "Gate patrol — Rigged Soldier NVG/balaclava" } :: AssetRef,
		-- W1 CFG drop (country / real-world weapon in the source): 0 → CharacterAlt (0) → Part kit
		SpecialForces = { ModelAssetId = 0, Note = "W1 CFG drop (real-world unit) — Part kit" } :: AssetRef,
		SpecialForcesAlt = { ModelAssetId = 0, Note = "W1 CFG drop (real-world weapon) — unused key" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- No plastic CharacterAlt — primary insert failure falls back to Part kit / olive drab.
	CharacterAlt = { ModelAssetId = 0, Note = "DISABLED — Design Bot rejected plastic Rthro alts" } :: AssetRef,

	Buildings = {
		-- Free Barracks / HQ / hangar / dock (Get Model). Part kits remain primary fallback.
		CommandCenter = { ModelAssetId = 0, PendingAssetId = 43803492, Note = "owner rule 5: heavy HQ model cleared (Part kit / walk-in shell); owner pick Command Center (Firebrand1): pending, P2 (owner yes/no, inert while PreferMesh is off)" } :: AssetRef,
		Barracks = { ModelAssetId = 0, PendingAssetId = 8637034739, Note = "owner rule 5: heavy barracks model cleared; owner pick Military Barracks /Hostel (AviGaTro): pending, P1i (inert while PreferMesh is off)" } :: AssetRef,
		VehicleDepot = { ModelAssetId = 12208876851, PendingAssetId = 4005471827, Note = "owner pick Military garage (TamasdztYT): pending, P2 (Studio WE_CHECK, inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		WeaponsFacility = { ModelAssetId = 4120970784, PendingAssetId = 11850705638, Note = "owner pick Armory (DISPLAYMODELS): pending, P2 (owner yes/no, inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Warehouse = { ModelAssetId = 15942568272, PendingAssetId = 8076230849, Note = "owner pick Warehouse (sydneycrosby_875): pending, P1i (inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Hangar = { ModelAssetId = 0, PendingAssetId = 5343886540, Note = "owner rule 5: heavy hangar model cleared (the Airfield composite builds its Part shed); owner pick plane hangar (Hyperalis): pending, P2 (owner yes/no, Studio WE_CHECK, inert while PreferMesh is off)" } :: AssetRef,
		HangarAlt = { ModelAssetId = 12208876851, Note = "Hangar insert fallback" } :: AssetRef,
		BaseGate = { ModelAssetId = 85138026, Note = "Gate arch prop ONLY — DisplayName Base Gate" } :: AssetRef,
		ResearchLab = { ModelAssetId = 17725725, Note = "Research lab" } :: AssetRef,
		SpecialForcesFacility = { ModelAssetId = 0, PendingAssetId = 10112923897, Note = "owner rule 5: heavy barracks model cleared; owner pick Military defense outpost (Roseaity): pending, P1i ([WEAK], inert while PreferMesh is off)" } :: AssetRef,
		Watchtowers = { ModelAssetId = 108525417345747, PendingAssetId = 52154909, Note = "owner pick guard tower (Morniratu): pending, P2 (Studio WE_CHECK, inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Radar = { ModelAssetId = 9559610195, PendingAssetId = 856258654, Note = "owner pick Radar Station (VexHavoc): pending, P1i (inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		-- W1 CFG drop (real-world system). NOTE: ResolveBuildingAssetId then reads StructureVisualConfig.Palettes
		-- .MissileDefense.MeshAssetId — that file must be 0 too for a Part kit (see docs/ASSET_LICENSES.md).
		MissileDefense = { ModelAssetId = 0, PendingAssetId = 3461514733, Note = "owner pick Missile Launcher (cwd30): pending, P1i (inert while PreferMesh is off); W1 CFG drop (real-world system): Part kit until promoted" } :: AssetRef,
		DefensiveWalls = { ModelAssetId = 0, PendingAssetId = 6980242709, Note = "owner pick Military Wall (SMehmetaga): pending, P2 (Studio WE_CHECK); perimeter-wall fallback (L3+ walls read DefensiveWallsL3 first)" } :: AssetRef,
		DefensiveWallsL3 = { ModelAssetId = 0, PendingAssetId = 8333853928, Note = "owner pick T WALL (steveaut): pending, P2 (Studio WE_CHECK); L3+ perimeter walls" } :: AssetRef,
		PowerStation = { ModelAssetId = 14000967030, PendingAssetId = 6869290892, Note = "owner pick Power Station (bossmanjesus101): pending, P1i (inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Bunker = { ModelAssetId = 0, Note = "W1 CFG drop (off the Creator Store) — Part kit" } :: AssetRef,
		Helipad = { ModelAssetId = 14313845338, PendingAssetId = 45369635, Note = "owner pick Helipad (sleitnick): pending, P1i (inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Airfield = { ModelAssetId = 0, Note = "COMPOSITE runway + Buildings.Hangar (0 = Part shed); REJECT 12370174722" } :: AssetRef,
		Dock = { ModelAssetId = 17701461178, PendingAssetId = 13183571527, Note = "owner pick boat dock (tihi2): pending, P2 (Studio WE_CHECK, inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		-- Anti-heli Base Ceiling: Part-kit only (no invented / paid roof IDs)
		BaseCeiling = { ModelAssetId = 0, Note = "Part-kit anti-heli roof — no free dedicated Model" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- JeepFallback 59524622 DELETED (Design P0 REJECT). Part kit physics if mesh fails.

	-- Gate defense (Design Bot GATE_DEFENSE_WIRE 2026-09-20)
	GateDefense = {
		Guard = { ModelAssetId = 16134469614, Note = "Rigged Soldier — gate patrol" } :: AssetRef,
		AutoGun = { ModelAssetId = 0, PendingAssetId = 114570602, Note = "0 = Part-built gate gun (4923345827 Machine Gun Nest dropped 2026-09-25: WWII MG 34-like silhouette, no part cap on this loader, loaded on live once the owner took it); owner pick Tripod Mounted Machine Gun (GuestCapone): pending, P1 (no gate)" } :: AssetRef,
		-- L2 elevated ONLY (not door flanks):
		AutoGunElevated = { ModelAssetId = 0, Note = "W1 CFG drop (uploader not the author) — unused key" } :: AssetRef,
		AutoGunElevatedAlt = { ModelAssetId = 10354803684, Note = "Military turret — L2/corner only" } :: AssetRef,
		SandbagNest = { ModelAssetId = 0, Note = "Circular sandbag ring under HMG" } :: AssetRef,
		Sandbags = { ModelAssetId = 3525056989, Note = "Realistic Sandbag scatter at posts" } :: AssetRef,
	},

	-- ATM / collect presentation (StripScripts on insert) — Design Bot prefer free IDs
	-- W1 CFG drop (paid): 0 is skipped, so TryAttachCollectorVisual tries the fallback, then the alts, then the Part kit
	MoneyCollector = { ModelAssetId = 0, PendingAssetId = 18220523228, Note = "owner pick ATM (0GColt): pending, P1 (no gate); W1 CFG drop (paid); until then MoneyCollectorFallback, then the alts" } :: AssetRef,
	MoneyCollectorFallback = { ModelAssetId = 175462478, Note = "ATM fallback classic" } :: AssetRef,
	MoneyCollectorAlts = {
		{ ModelAssetId = 90362241548850, Note = "ATM alt A" } :: AssetRef,
		{ ModelAssetId = 76846072091295, Note = "ATM alt B" } :: AssetRef,
		{ ModelAssetId = 35409899, Note = "ATM alt C" } :: AssetRef,
	},
	MoneyBagFX = { ModelAssetId = 38451313, Note = "Collect cash burst VFX (StripScripts)" } :: AssetRef,
	VfxSparkles = { ModelAssetId = 4221608224, Note = "Collect/upgrade sparkles VFX" } :: AssetRef,
	CashCrate = { ModelAssetId = 16803204916, Note = "Cash crate alt overlay" } :: AssetRef,
	UpgradeFlag = { ModelAssetId = 1679839739, Note = "L5 structure flag pop" } :: AssetRef,
	FloodlightTower = { ModelAssetId = 107381977457431, Note = "Floodlight tower PROP (not vehicle)" } :: AssetRef,
	-- VehicleDepot showroom catalog (Part-kit podium remains fallback)
	ShowroomPodium = { ModelAssetId = 5267267960, Note = "Showroom podium mesh" } :: AssetRef,
	ShowroomPedestal = { ModelAssetId = 130578088310000, Note = "Showroom pedestal" } :: AssetRef,
	ShowroomRotator = { ModelAssetId = 5389482912, Note = "Showroom rotator / turntable" } :: AssetRef,
	-- Tutorial guidance
	TutorialArrow = { ModelAssetId = 1143305733, PendingAssetId = 632958370, Note = "Tutorial arrow prefer; alt 6333395014; owner pick Arrow (isaacbeyo): pending, P1 (no gate); replaces this id at promote" } :: AssetRef,
	TutorialArrowAlt = { ModelAssetId = 6333395014, Note = "Tutorial arrow alt" } :: AssetRef,
	TutorialBeam = { ModelAssetId = 88687072714005, Note = "Tutorial neon beam mesh/texture" } :: AssetRef,

	-- KEY LABELS fixed (IDs unchanged); legacy aliases kept for callers
	WarzoneProps = {
		Sandbag = { ModelAssetId = 3525056989, PendingAssetId = 15271872710, Note = "owner pick SandBag Wall (Herbie778811): pending, P1 (no gate); replaces this id at promote" } :: AssetRef,
		SandbagBarrier = { ModelAssetId = 12651656400, Note = "Warzone SandbagBarrier" } :: AssetRef,
		SandbagWall = { ModelAssetId = 25733125, Note = "Warzone SandbagWall" } :: AssetRef,
		ConcreteBarrier = { ModelAssetId = 91071319, PendingAssetId = 2766525411, Note = "owner pick road barrier (SiameseMouse): pending, P1 (no gate); replaces this id at promote" } :: AssetRef,
		Crate = { ModelAssetId = 53591587, Note = "Warzone Crate" } :: AssetRef,
		MilitaryCrate = { ModelAssetId = 976333542, PendingAssetId = 2930926216, Note = "owner pick Military Crates (XIArchangel): pending, P1 (no gate); replaces this id at promote" } :: AssetRef,
		AmmoBox = { ModelAssetId = 16382915010, Note = "Warzone AmmoBox" } :: AssetRef,
		OilBarrel = { ModelAssetId = 23153991, Note = "owner list: Roblox Smoking Barrel, whole model (4 parts), smoke removed (StripEffectsAssetIds)" } :: AssetRef,
		BarbedWire = { ModelAssetId = 1291725699, Note = "Warzone BarbedWire" } :: AssetRef,
		Tent = { ModelAssetId = 6883609157, PendingAssetId = 182529039, Note = "owner pick Military Canvas Tent (Quenty): pending, P1 (no gate); replaces this id at promote" } :: AssetRef,
		RadioAntenna = { ModelAssetId = 19277831, PendingAssetId = 1439808070, Note = "owner pick Antenna (Sereinmachy): pending, P1i (inert while PreferMesh is off); StructureDress only" } :: AssetRef,
		Floodlight = { ModelAssetId = 116763933, Note = "Warzone Floodlight" } :: AssetRef,
		FloodlightTower = { ModelAssetId = 107381977457431, Note = "Floodlight tower prefer" } :: AssetRef,
		Flag = { ModelAssetId = 1679839739, Note = "L5 upgrade flag" } :: AssetRef,
		Lantern = { ModelAssetId = 0, Note = "W1 CFG drop (extracted from another game) — Part kit host" } :: AssetRef,
		TentAlt = { ModelAssetId = 3133150032, Note = "Tent alt if primary Tent fails" } :: AssetRef,
		RadioAntennaAlt = { ModelAssetId = 42209845, Note = "HQ roof antenna alt" } :: AssetRef,
		FloodlightAlt = { ModelAssetId = 4893998573, Note = "Depot bay floodlight" } :: AssetRef,
		FuelCans = { ModelAssetId = 1160141839, PendingAssetId = 112426091, Note = "owner pick Gas Can (Maximum_ADHD): pending, P1i (inert while PreferMesh is off); StructureDress only" } :: AssetRef,
		FlagPole = { ModelAssetId = 1679839739, PendingAssetId = 172755983, Note = "owner pick Flagpole (Quenty): pending, P1i (inert while PreferMesh is off); StructureDress only" } :: AssetRef,
		FlagPoleHD = { ModelAssetId = 1454179642, Note = "HQ prestige flag pole" } :: AssetRef,
		-- Map densify P0/P1 (Design MAP_BUILD_OUT_WIRE 2026-09-21)
		JerseyBarrier = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; WorldKits Jersey is our Part kit) — Part kit" } :: AssetRef,
		JerseyBarrierAlt = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		RoadBarriers = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		Hesco = { ModelAssetId = 0, Note = "W1 CFG drop (brand name in the source) — Part kit host" } :: AssetRef,
		TankWreck = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller after the W3 rewrite) — Part kit" } :: AssetRef,
		RuinedBuilding = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		RuinedWall = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		FuelTanks = { ModelAssetId = 0, Note = "W1 CFG drop (country name in the source) — Part kit host" } :: AssetRef,
		AmmoShed = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party, 117 MeshParts > MaxPartsPerModel) — Dockside Part-kit host" } :: AssetRef,
		SupplyShed = { ModelAssetId = 0, Note = "W3 LOOK drop (shortlist §4 keyword-spam listing, 9 scripts; no caller) — Part kit" } :: AssetRef,
		PortableLightTower = { ModelAssetId = 0, Note = "W3 LOOK drop (shortlist §4 real-world listing text; no caller) — Part kit" } :: AssetRef,
		StreetLamp = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; WorldKits StreetLamp is our Part kit) — Part kit" } :: AssetRef,
		StreetLampAlt = { ModelAssetId = 0, Note = "W3 LOOK drop (shortlist §4 provenance, 8 scripts; no caller) — Part kit" } :: AssetRef,
		MilitaryCratePack = { ModelAssetId = 16540055496, Note = "Military Crates pack variety" } :: AssetRef,
		-- Legacy key aliases (same IDs)
		Sandbags = { ModelAssetId = 3525056989, PendingAssetId = 15271872710, Note = "owner pick SandBag Wall (Herbie778811): pending, P1 (no gate); alias of Sandbag" } :: AssetRef,
		Barrier = { ModelAssetId = 25733125, Note = "alias → SandbagWall" } :: AssetRef,
		Cone = { ModelAssetId = 91071319, PendingAssetId = 2766525411, Note = "owner pick road barrier (SiameseMouse): pending, P1 (no gate); alias of ConcreteBarrier" } :: AssetRef,
		Drum = { ModelAssetId = 53591587, Note = "alias → Crate" } :: AssetRef,
		Pallet = { ModelAssetId = 976333542, PendingAssetId = 2930926216, Note = "owner pick Military Crates (XIArchangel): pending, P1 (no gate); alias of MilitaryCrate" } :: AssetRef,
		CamoNet = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		CamoNetAlt = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		Fence = { ModelAssetId = 25623924, Note = "legacy alias of the old OilBarrel id (no caller; WarzoneProps.OilBarrel is the Roblox barrel now)" } :: AssetRef,
		Radio = { ModelAssetId = 19277831, PendingAssetId = 1439808070, Note = "owner pick Antenna (Sereinmachy): pending, P1i (inert while PreferMesh is off); alias of RadioAntenna" } :: AssetRef,
		Lamp = { ModelAssetId = 116763933, Note = "alias → Floodlight" } :: AssetRef,
	} :: { [string]: AssetRef },

	DesertProps = {
		Cactus = { ModelAssetId = 0, Note = "W1 CFG drop (uploader not the author) — Part kit" } :: AssetRef,
		CactusBase = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		DesertPlants = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit" } :: AssetRef,
		-- Dead config (contracts §8.4): no caller after the W3 rewrite; the literal stays because BuyPathStatic pins it.
		Palm = { ModelAssetId = 96059329869678, Note = "DEAD CONFIG since W3 (no TryAttachPropVisual caller); BPS-pinned literal" } :: AssetRef,
		PalmAlt = { ModelAssetId = 0, Note = "W3 LOOK drop (shortlist §4 keyword-spam listing, 1 script; no caller) — Part kit" } :: AssetRef,
		-- MeshPart AssetType 40 — VisualAssetService MeshPart pipeline (not InsertService Model)
		DesertRock = { ModelAssetId = 0, MeshId = 0, Note = "Low Poly Rocks MeshPart (MeshId pipeline)" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- MapDressing keys (Decal / non-Model assets)
	MapDressing = {
		AsphaltDecal = { ModelAssetId = 0, MeshId = 0, Note = "Asphalt road Decal Texture on road Parts" } :: AssetRef,
		ChevronArrow = { ModelAssetId = 0, Note = "Part-kit floor chevrons (no free Model)" } :: AssetRef,
		DesertRock = { ModelAssetId = 0, MeshId = 0, Note = "alias → DesertProps.DesertRock MeshPart" } :: AssetRef,
		Palm = { ModelAssetId = 0, Note = "W3 LOOK drop (alias; no caller) — DesertProps.Palm is dead config" } :: AssetRef,
		PalmAlt = { ModelAssetId = 0, Note = "W3 LOOK drop (alias → DesertProps.PalmAlt; no caller)" } :: AssetRef,
		DesertPlants = { ModelAssetId = 0, Note = "alias → DesertProps.DesertPlants (W1 CFG drop)" } :: AssetRef,
		Cactus = { ModelAssetId = 0, Note = "alias → DesertProps.Cactus (W1 CFG drop)" } :: AssetRef,
		JerseyBarrier = { ModelAssetId = 0, Note = "W3 LOOK drop (alias → WarzoneProps.JerseyBarrier; no caller)" } :: AssetRef,
		JerseyBarrierAlt = { ModelAssetId = 0, Note = "W3 LOOK drop (alias → WarzoneProps.JerseyBarrierAlt; no caller)" } :: AssetRef,
		DesertMesa = { ModelAssetId = 0, Note = "Desert Mountain mesa horizon" } :: AssetRef,
		Hesco = { ModelAssetId = 0, Note = "alias → WarzoneProps.Hesco (W1 CFG drop)" } :: AssetRef,
	} :: { [string]: AssetRef },


	-- Tier 2: oil spectacle + map landmarks (REJECT Ultrapump 1837698074)
	IndustrialProps = {
		IndustrialPack = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit (oil spectacle)" } :: AssetRef,
		OilPumpjack = { ModelAssetId = 13525922265, PendingAssetId = 15192621369, Note = "owner pick Oil Rig / Pumpjack (sadfiacs): pending, P1 (no gate); promote also sets OilPumpjackAlt = 0 (same id)" } :: AssetRef,
		OilPumpjackAlt = { ModelAssetId = 15192621369, Note = "Oil Rig / Pumpjack alt" } :: AssetRef,
		RustyPipes = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit" } :: AssetRef,
		OilBarrel = { ModelAssetId = 25623924, Note = "Oil barrel ring" } :: AssetRef,
		FuelCans = { ModelAssetId = 1160141839, Note = "Fuel cans cluster" } :: AssetRef,
		-- GasStation 5149705639 OPTIONAL heavy — not default
		-- Ultrapump 1837698074 REJECT
	} :: { [string]: AssetRef },

	Landmarks = {
		RadioTower = { ModelAssetId = 119021509, Note = "Map ridge radio tower POI" } :: AssetRef,
		Bunker = { ModelAssetId = 0, Note = "W1 CFG drop (off the Creator Store) — Part kit" } :: AssetRef,
		SpyBunker = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world landmark; POIs use our Part kits) — Part kit" } :: AssetRef,
		SmallFort = { ModelAssetId = 67444725, Note = "Mid-map small fort landmark" } :: AssetRef,
		DesertMesa = { ModelAssetId = 0, Note = "alias → MapDressing.DesertMesa horizon" } :: AssetRef,
		-- P2 registered (dress deferred if perf risk)
		DesertHouse = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world landmark; WorldKits AdobeHouse) — Part kit" } :: AssetRef,
		Pier = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world landmark; no caller) — Part kit" } :: AssetRef,
		PierAlt = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit" } :: AssetRef,
		CheckpointBridge = { ModelAssetId = 0, Note = "W3 LOOK drop (shortlist §4 real-world theme; WorldKits Checkpoint v2) — Part kit" } :: AssetRef,
	} :: { [string]: AssetRef },

	--[[ W3 LOOK: World v2 kit meshes (contracts §8.2; keys = WorldKits.Specs[kit].Mesh). One MeshPart from a Roblox-owned
		Synty pack (creator Roblox, User 1; "completely free to use in anything you want to create on Roblox", DevForum
		1283755): 6933438443 Nature, 6933556508 City, 6933790012 Dungeon. WorldKits asks VisualAssetService.CloneKitMesh(key)
		in a deferred task and stretches the piece into the Part-kit fallback's box, so a piece is wired only when its
		proportions fit that box (distortion = max/min of the per-axis stretch, <= 2.2). ModelAssetId = 0 keeps the Part kit.
		Colours match WorldConfig.Kits.Palette; ClearTexture gives the flat desert palette and keeps pack text off-screen.
		Yaw (degrees) turns a piece onto the kit box's long axis before the stretch (Driftwood, CarWreck). ]]
	DesertKit = {
		-- Kit DeadTree (1.1 x 11 pole, leaning): a thin dead pine snag, stretch 2.11 (the shortlist pick
		-- branches_tree_dead02 is 2.75)
		DeadTree = { ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Tree_Pine_Dead_01", Color = Color3.fromRGB(122, 106, 86), Material = Enum.Material.Wood, ClearTexture = true, Note = "Synty Nature: dead pine snag (310 tris)" } :: AssetRef,
		-- Kit Stump (2.4 x 1.6 x 2.4): Stump_01, stretch 1.47 (Stump_03 is a tall stump, 2.73)
		Stump = { ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Tree_Stump_01", Color = Color3.fromRGB(95, 78, 52), Material = Enum.Material.Wood, ClearTexture = true, Note = "Synty Nature: stump (114 tris)" } :: AssetRef,
		-- Kit FallenLog (long axis Z): Tree_Log_01, stretch 1.10. Driftwood has its own key below (WorldKits
		-- Specs.Driftwood Mesh = "Driftwood"), so this piece is never squashed onto the X-long driftwood box.
		Log = { ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Tree_Log_01", Color = Color3.fromRGB(122, 106, 86), Material = Enum.Material.Wood, ClearTexture = true, Note = "Synty Nature: fallen log (306 tris)" } :: AssetRef,
		-- Kit Driftwood (long axis X): the pack has no driftwood; Tree_Twig_02 fits (1.29) only turned 90 degrees (Yaw:
		-- the overlay turns the piece onto the kit's long axis).
		Driftwood = { ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Tree_Twig_02", Yaw = 90, Color = Color3.fromRGB(122, 106, 86), Material = Enum.Material.Wood, ClearTexture = true, Note = "Synty Nature: twig as driftwood (110 tris), turned 90 degrees" } :: AssetRef,
		-- Kit Reeds clumps (1.9 x 3.2 x 1.9): stretch 1.11
		Reeds = { ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Plant_Reeds_01", Color = Color3.fromRGB(122, 128, 70), Material = Enum.Material.Grass, ClearTexture = true, Note = "Synty Nature: reeds (135 tris)" } :: AssetRef,
		-- Kit DuneGrass tufts (2.6 x 1.1 x 2.6): a low plant, stretch 1.22 (the shortlist's Grass_04 is 4.35)
		DuneGrass = { ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Plant_01", Color = Color3.fromRGB(178, 152, 92), Material = Enum.Material.Grass, ClearTexture = true, Note = "Synty Nature: low dry plant (416 tris)" } :: AssetRef,
		-- Kit CrateStack crates (2.4 cube; WorldKits "skin" mode keeps the Part's colour): stretch 1.00
		CrateWood = { ModelAssetId = 6933790012, ChildName = "Meshes/PolygonDungeon_Props_SM_Prop_Crate_Wood_04", Color = Color3.fromRGB(118, 94, 60), Material = Enum.Material.Wood, ClearTexture = true, Note = "Synty Dungeon: wooden crate (598 tris)" } :: AssetRef,
		-- NOT WIRED: the kit Bench box is 6 x 1.2 x 1.8 (seat only); the park bench with its backrest is 3.65 tall
		-- (stretch 2.52: a flattened bench). Wire when the kit box covers the backrest.
		Bench = { ModelAssetId = 0, ChildName = "Meshes/PolygonCity_Props_SM_Prop_ParkBench_01", Color = Color3.fromRGB(105, 82, 55), Material = Enum.Material.Wood, ClearTexture = true, Note = "Synty City: park bench (552 tris) — waits on the kit box" } :: AssetRef,
		-- Kit wreck (long axis X): the sedan lies along Z, so Yaw = 90 turns it onto the kit's long axis (fit 1.42).
		-- Recoloured as a burnt wreck (ClearTexture drops the pack paint).
		CarWreck = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Props_SM_Veh_Car_Sedan_01", Yaw = 90, Color = Color3.fromRGB(45, 42, 40), Material = Enum.Material.CorrodedMetal, ClearTexture = true, Note = "Synty City: burnt sedan (5,524 tris; <= 6 per 512-stud circle), turned 90 degrees" } :: AssetRef,
		-- Optional keys (contracts §8.2; no WorldKits caller yet)
		VanWreck = { ModelAssetId = 0, ChildName = "Meshes/PolygonCity_Props_SM_Veh_Car_Van_01", Color = Color3.fromRGB(45, 42, 40), Material = Enum.Material.CorrodedMetal, ClearTexture = true, Note = "Synty City: burnt van (5,665 tris) — no caller" } :: AssetRef,
		Pebbles = { ModelAssetId = 0, ChildName = "Meshes/PolygonNature_Terrain_Rubble_Pebbles_01", Color = Color3.fromRGB(150, 135, 110), Material = Enum.Material.Ground, ClearTexture = true, Note = "Synty Nature: pebbles (168 tris) — no caller" } :: AssetRef,
		Skip = { ModelAssetId = 0, ChildName = "Meshes/PolygonCity_Props_SM_Prop_Skip_02", Color = Color3.fromRGB(70, 85, 55), Material = Enum.Material.Metal, ClearTexture = true, Note = "Synty City: skip (1,352 tris) — no caller" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- HQ / Barracks interior dress keys (hosts in StructureKitBuilder)
	StructureDress = {
		CommandCenter = { "RadioAntenna", "RadioAntennaAlt", "AmmoBox", "Crate", "MilitaryCrate", "Lantern", "Floodlight", "FuelCans" },
		Barracks = { "Crate", "MilitaryCrate", "AmmoBox", "Lantern", "Sandbag" },
		WeaponsFacility = { "AmmoBox", "MilitaryCrate", "Lantern", "Sandbag" },
		VehicleDepot = { "FloodlightAlt", "Floodlight", "FlagPole", "FuelCans" },
		PowerStation = { "FuelCans" },
	} :: { [string]: { string } },

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
		JetFighter = "_FallbackJet",
		JetStrike = "StrikeJet",
		JetBomber = "StrikeBomber",
		JetTransport = "CargoPlane",
		NavalPatrol = "_FallbackNaval",
		NavalGun = "_FallbackNaval",
		NavalLanding = "LandingCraft",
		NavalCapital = "LandingCraft",
		NavalSub = "_FallbackNaval",
	} :: { [string]: string },
}

return VisualAssetConfig
