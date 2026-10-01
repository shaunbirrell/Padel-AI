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

-- air-looks (2026-09-28): one spinning rotor of a store aircraft body (AssetRef.RotorParts; AirBodyRig + AircraftBodyClient)
export type AirRotor = {
	Parts: { string }, -- BasePart names in the body (every descendant with one of these names spins with this rotor)
	-- air fix2: store models often name every rotor piece alike ("MeshPart", hubs "Spinner"; main and tail rotor told apart
	-- only by their parent Model). Under = an ancestor Model name ("Rotor1"): only Parts inside such a Model spin, each
	-- such Model is its own rotor (its own Hub / centre), and Hub is looked up inside it. A part already on a rotor joint
	-- is never jointed twice.
	Under: string?,
	Hub: string?, -- the spin centre is this part's centre (default: the average centre of Parts)
	Axis: string, -- the spin axis in the kit chassis frame after the fit: "Y" up (main rotor), "X" sideways (tail rotor), "Z"
	Rps: number, -- turns per second at full speed (drawn with RotorSpin.Steps precomputed angles)
	Kit: boolean?, -- true: the names are Part-kit parts (the kit rotor, kept visible with KeepVisible) instead of body parts
}

-- air2 fix1 (2026-09-28): one invisible hit plate over a fitted store aircraft body (AssetRef.BodyHitBoxes; AirBodyRig)
-- v87: the Part-kit rotor on a store helicopter body (AssetRef.KitRotor; AirBodyRig). Every named kit part moves by the
-- same offset so Hub's centre lands on At (unscaled body frame like BodySeats); the blades' longest side becomes Span x
-- BodyScale. List the parts in KeepVisible and spin them with a RotorParts entry (Kit = true).
export type KitRotorSpec = {
	Parts: { string },
	Hub: string,
	At: Vector3,
	Span: number?,
}

export type AirHitBox = {
	At: Vector3, -- box centre, unscaled body frame like BodySeats (x / z from the body box centre, y above its lowest point, before Yaw)
	Size: Vector3, -- box size, unscaled (x across, y up, z along the body before Yaw)
}

-- air2 fix1: drawn landing gear under a fitted store aircraft body that has none (AssetRef.BodyGear; AirBodyRig). Drawn
-- only: never collides, massless; the hidden kit gear still stands and rolls the aircraft (physics unchanged).
export type AirGearLeg = {
	At: Vector3, -- the wheel's x / z, unscaled body frame like BodySeats (y unused: the wheel stands on the kit's floor)
	Wheel: number, -- wheel diameter, studs
}
export type AirGear = {
	Legs: { AirGearLeg },
	Strut: number, -- strut thickness, studs; the strut runs from the wheel centre up into the body underside above it
	Into: number, -- studs the strut reaches into the body box above the leg (it never ends in the air under a round belly)
	WheelColor: Color3?, -- air2 fix2: the look (config first); nil = near-black SmoothPlastic wheels, grey Metal struts
	WheelMaterial: Enum.Material?,
	StrutColor: Color3?,
	StrutMaterial: Enum.Material?,
}

export type AssetRef = {
	ModelAssetId: number?, -- InsertService / AssetService:LoadAssetAsync catalog Model
	FallbackAssetId: number?, -- v119 rig rows: loaded instead when ModelAssetId fails for good (not authorized / not an R6 rig)
	MeshId: number?, -- optional SpecialMesh / MeshPart MeshId (0 = unused)
	Note: string?,
	-- W3 LOOK: one piece of a (Roblox-owned) pack
	ChildName: string?, -- found with pack:FindFirstChild(ChildName, true); names contain "/" (never split)
	SubModel: string?, -- then this descendant of the piece (e.g. "Body": drops Chassis / Scripts / Effects)
	Color: Color3?, -- single-part pieces: flat colour (with ClearTexture)
	Material: Enum.Material?, -- single-part pieces
	ClearTexture: boolean?, -- TextureID = "" and no SurfaceAppearance: flat desert palette, no stray text
	StripDecals: boolean?, -- drop Decals / Textures (phone draw calls; the LUV camo decals are not Roblox-owned images)
	Fit: string?, -- "Kit": vehicle body scaled to the kit chassis length, tyres on the physics-wheel bottoms; "Ground": a prop
	-- stands upright at the host's centre, lowest point on the host's lowest point, scale 1; "Box": a one-part business model
	-- is stretched into the kit part it replaces (block parts only; default: one uniform scale onto the parts' long side)
	Yaw: number?, -- Fit: degrees from the piece's front (-Z) to the kit's front (-Z); GateDefense.AutoGun: degrees that
	-- turn the model's barrel onto -Z (turned once in the template at load)
	HideKit: boolean?, -- Fit: hide the Part-kit visuals under the body (physics, seats and hitboxes unchanged)
	KeepVisible: { string }?, -- HideKit: kit part names that stay visible (the Armed 4x4 keeps its Part turret)
	-- vscale (owner: the avatar sat above the buggy / through the jeep roof): Fit bodies at a set scale over the same kit
	BodyScale: number?, -- Fit: body scale (1 = Roblox size); nil = as long as the kit chassis. The kit still drives
	BodySeats: { [string]: Vector3 }?, -- BodyScale: kit seat -> body seat top (unscaled studs: x/z from the body box centre, y above its lowest point)
	BodyRoofParts: { string }?, -- BodyScale: kit parts lifted onto the body roof (the Armed 4x4 keeps its Part turret)
	-- air-looks (2026-09-28): store aircraft bodies (VisualAssetService + Server/Modules/AirBodyRig, AircraftBodyClient)
	BodyAnchor: string?, -- BodyScale: a BodySeats name; the body moves (kit X / Z) so that seat is over the kit seat of that name
	BodyFloor: string?, -- BodyScale: "Collide" = the body's lowest point on the kit's lowest collidable part (skids, gear)
	BodyMounts: { [string]: Vector3 }?, -- BodyScale: kit weapon mount part -> where its front face sits on the body (unscaled, like BodySeats)
	RotorParts: { AirRotor }?, -- BodyScale: body (or kit) parts that spin on each client while the driver seat is taken
	ChaseCamera: boolean?, -- BodyScale: a seated player's camera stays at least AirBody.ChaseCameraMargin past the body's far end
	BodyHitBoxes: { AirHitBox }?, -- BodyScale (air2 fix1): invisible hit plates over the body, so shots hit what players see (AirBody.BodyHitBoxes)
	BodyLift: number?, -- BodyScale (air2 fix1): studs the fitted body stands over the kit's chassis bottom (drawn gear under it)
	BodyGear: AirGear?, -- BodyScale (air2 fix1): drawn landing gear from the kit's floor up into the body
	TailGuard: boolean?, -- BodyScale (air2 fix1): near the ground the plane law eases nose-up pitch and bank so the body never dips into it (AirBody.TailGuard)
	-- v87 (Code Bot, 2026-09-28): store bodies for helicopters, bombers, transports and ships (owner-only rollout)
	Rollout: string?, -- "Body" = this body obeys VisualAssetConfig.BodyRollout ("owner": only the playtest owner's vehicles wear it)
	BodyMinScale: number?, -- BodyScale floor for this ref (default 0.05; the gunboat store model is 2048 studs long, fitted at 0.027)
	BodyWaterline: number?, -- BodyScale (ships): studs of the fitted hull that sit under the kit's waterline (the body sinks this far)
	BodyColor: Color3?, -- recolour every body part (a plain grey store mesh gets the game's military tone)
	BodyMaterial: Enum.Material?, -- with BodyColor: the body's material
	BodyClearTexture: boolean?, -- MeshPart TextureID cleared (a store mesh whose texture path is dead draws its BodyColor)
	BodyColorParts: { string }?, -- v90: with BodyColor, only the body parts with these names take it (nil = every part)
	BodyDeck: { AirHitBox }?, -- invisible collidable deck plates (unscaled body boxes, like BodyHitBoxes): players / aircraft stand on the fitted deck
	BodyKitNoCollide: { string }?, -- kit parts that stop colliding under the body (the carrier's kit deck / island would stand over the fitted deck)
	KitRotor: KitRotorSpec?, -- helicopters: the kit rotor (kept visible) moved onto the body's mast and stretched to the body's rotor span
	BodyMaxScale: number?, -- v88: BodyScale cap for this ref (default 4; the 2-stud airliner mesh fits at 30)
	BodyAnchorX: boolean?, -- v88: BodyAnchor also moves the body across the kit (a bridge on an off-centre island)
	-- Owner asset list (2026-09-25)
	PendingAssetId: number?, -- the owner's third-party pick; NEVER loaded (VisualAssetService ignores it); tools/wire-asset-ids.py promotes it
	OmitParts: { string }?, -- pack piece: BaseParts with these names are removed before the part count (Pickup Truck tail-light glass)
	NoFamilyFallback: boolean?, -- vehicle ref at 0: keep the Part kit, never take the KitFamilyFallback body
	-- Owner asset list hooks (2026-09-25: business / Home Outpost / dropper / turret dress). OmitParts also works on
	-- whole-model props, businesses and vehicle weapons (the parts are dropped from each clone).
	KeepHost: boolean?, -- props: the host part keeps its look (no fade under the model)
	FitLong: number?, -- props: one uniform scale so the model's longest side is this many studs (default: scale 1)
	ReplacesRoles: { string }?, -- Businesses: model part i takes over kit role i's part (named Kit_<Role>); one MinLevel
	Mount: string?, -- VehicleWeapons: the vehicle kit part the weapon model sits on
	FitScale: number?, -- VehicleWeapons: the model's longest side = the mount part's longest side x FitScale
	KitFamilies: { string }?, -- VehicleWeapons: only vehicles of these VehicleConfig KitFamily values wear it
	Vehicles: { string }?, -- VehicleWeapons: and / or only these vehicle ids
	HideParts: { string }?, -- VehicleWeapons: kit parts made invisible once the dress attaches (the kit barrel)
	-- bizlook (2026-09-27): BusinessPieces (Fit = "Stretch": a building piece turned by Yaw, then stretched to fill a box)
	Into: string?, -- BusinessPieces: the kit role whose box the piece fills (default: the replaced role's own box)
	HideRoles: { string }?, -- BusinessPieces: kit roles made invisible once the piece is on (their collision stays)
	FromLevel: number?, -- BusinessPieces: worn from this business level (nil = from the role's first level)
	ToLevel: number?, -- BusinessPieces: worn up to this business level (nil = to the top)
	Rig: string?, -- R-RIG: "R6" = animated rig (RigBuilder); the template holds no Humanoid
	Headwear: string?, -- R-RIG: "Beret" | "KitHelmet" | "None"
}

-- air2 fix1 (2026-09-28): the owner's jet 14589101870 (Vehicles.FighterJet / InterceptorJet / TrainerJet / LightFighter)
-- shares these two tables. Unscaled body frame like BodySeats: x / z from the body box centre, y over its lowest point,
-- before the Yaw (its nose is +Z). Hit plates = the boxes of the owner's WE_CHECK2 P lines (a mesh never leaves its box):
-- fuselage (its nose cone narrower), belly block, wings with the wing-tip missiles, strakes, tailplanes and fin. The
-- drawn gear stands where a real jet's does: two main wheels under the wing roots, level with the kit's main wheels (the
-- aircraft rolls and rotates on those), one nose wheel under the canopy's front.
local JET_HIT_BOXES: { AirHitBox } = {
	{ At = Vector3.new(0.07, 1.485, -1.4), Size = Vector3.new(2, 1.97, 13.69) }, -- fuselage, tail to the canopy front
	{ At = Vector3.new(0.07, 1.485, 7.1), Size = Vector3.new(1.2, 1.2, 3.29) }, -- nose cone
	{ At = Vector3.new(0.04, 1.115, -1.93), Size = Vector3.new(1.56, 2.23, 10.53) }, -- belly block under the fuselage
	{ At = Vector3.new(0, 1.338, -1.34), Size = Vector3.new(11.52, 0.745, 4.96) }, -- wings with the wing-tip missiles
	{ At = Vector3.new(0.07, 1.335, 1.68), Size = Vector3.new(3.95, 0.4, 5.23) }, -- strakes by the cockpit
	{ At = Vector3.new(0.07, 1.47, -6.19), Size = Vector3.new(6.07, 0.5, 5.11) }, -- tailplanes
	{ At = Vector3.new(0.07, 3.245, -6.19), Size = Vector3.new(0.4, 3.05, 5.11) }, -- fin
}
-- v90 (owner 2026-09-28: "every jet gets its own distinct colour"): the jet's grey panels (WE_CHECK2 on live v85: Cube,
-- Cube.001, Cube.003 SmoothPlastic 99,95,98 and Cylinder.003 82,81,83) take each key's BodyColor; the black fuselage
-- tube, wings and trim (Cylinder, Cylinder.001, Cube.002) and the Glass canopy (Cylinder.002) keep the approved look.
local JET_PAINT_PARTS = { "Cube", "Cube.001", "Cube.003", "Cylinder.003" }
local JET_GEAR: AirGear = {
	Legs = {
		{ At = Vector3.new(1.23, 0, 0.7), Wheel = 1.6 }, -- main wheel, under the wing root
		{ At = Vector3.new(-1.09, 0, 0.7), Wheel = 1.6 }, -- main wheel, the other side (both 1.16 off the fuselage axis)
		{ At = Vector3.new(0.07, 0, 5.5), Wheel = 1.2 }, -- nose wheel, under the canopy's front
	},
	Strut = 0.35,
	Into = 0.6,
	WheelColor = Color3.fromRGB(28, 28, 30), -- black tyres
	WheelMaterial = Enum.Material.SmoothPlastic,
	StrutColor = Color3.fromRGB(120, 122, 126), -- grey legs
	StrutMaterial = Enum.Material.Metal,
}

-- v87 (Code Bot, 2026-09-28): owner-picked store bodies for the helicopters, bombers, transports and ships, OWNER-ONLY
-- (Rollout = "Body" + VisualAssetConfig.BodyRollout = "owner": only vehicles spawned by the playtest owner, AdminConfig
-- .IsPlaytestOwner, wear them; every other player keeps the Part kit). Same system as the jets (air-looks 4e07fc2):
-- Fit = "Kit" at BodyScale, HideKit, BodySeats (unscaled body frame: x / z from the body box centre, y above its lowest
-- point, before the Yaw) put every kit seat INSIDE the cockpit / cabin / bridge, BodyAnchor moves the body so its
-- cockpit is over the kit pilot seat. Body parts never collide and are massless (weldCloneToPrimary), so handling is the
-- kit's. Ships sink BodyWaterline studs into the water. Seat points come from the owner's load check (wc5, Open Cloud
-- raycast grids grid87, 2026-09-28). Each table is shallow-copied per vehicle (bodyRef) so every vehicle keeps its Note.
local function bodyRef(base: { [string]: any }, note: string): AssetRef
	local r: { [string]: any } = {}
	for k, v in pairs(base) do
		r[k] = v
	end
	r.Note = note
	return r :: any
end

-- 3130894523 light helicopter (7 parts; its two transparent rotor discs, both named "Part", are dropped: the kit rotor
-- spins on the body's mast instead). Front -Z. Pilot and co-pilot in the cockpit glass, the rest in the cabin.
local BODY_LIGHT_HELI = {
	ModelAssetId = 3130894523,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 1.15,
	OmitParts = { "Part" },
	BodySeats = {
		DriverSeat = Vector3.new(-1.3, 2.8, -8.5),
		PassengerSeat1 = Vector3.new(1.3, 2.8, -8.5),
		PassengerSeat2 = Vector3.new(-1.3, 2.8, -4.5),
		PassengerSeat3 = Vector3.new(1.3, 2.8, -4.5),
		PassengerSeat4 = Vector3.new(0, 2.8, -1),
	},
	BodyAnchor = "DriverSeat",
	BodyFloor = "Collide",
	KitRotor = { Parts = { "RotorHub", "RotorA", "RotorB" }, Hub = "RotorHub", At = Vector3.new(0, 8.7, -3.3), Span = 25.5 },
	RotorParts = { { Parts = { "RotorHub", "RotorA", "RotorB" }, Hub = "RotorHub", Axis = "Y", Rps = 5, Kit = true } },
	KeepVisible = { "RotorHub", "RotorA", "RotorB" },
	ChaseCamera = true,
	StripDecals = true,
}

-- 109615982233602 transport helicopter (1 mesh, no rotor: the kit rotor, stretched to 13 x 3 = 39 studs). Front -Z.
local BODY_TRANSPORT_HELI = {
	ModelAssetId = 109615982233602,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 3,
	BodySeats = {
		DriverSeat = Vector3.new(-0.5, 1.0, -4.8),
		PassengerSeat1 = Vector3.new(0.6, 1.0, -4.8),
		PassengerSeat2 = Vector3.new(-0.6, 1.0, -2.5),
		PassengerSeat3 = Vector3.new(0.6, 1.0, -2.5),
		PassengerSeat4 = Vector3.new(0, 1.0, -0.8),
	},
	BodyAnchor = "DriverSeat",
	BodyFloor = "Collide",
	KitRotor = { Parts = { "RotorHub", "RotorA", "RotorB" }, Hub = "RotorHub", At = Vector3.new(0, 4.4, -1.2), Span = 13 },
	RotorParts = { { Parts = { "RotorHub", "RotorA", "RotorB" }, Hub = "RotorHub", Axis = "Y", Rps = 4, Kit = true } },
	KeepVisible = { "RotorHub", "RotorA", "RotorB" },
	ChaseCamera = true,
	StripDecals = true,
}

-- 14669079591 delta-wing bomber (1 plain grey mesh: recoloured dark military). 73 span at 0.05. Nose -Z. Crew in the
-- fuselage (head under the canopy line); the kit bomb bay (AirWeaponService muzzle "Bay") moves under the centre.
local BODY_BOMBER = {
	ModelAssetId = 14669079591,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 0.05,
	BodySeats = {
		DriverSeat = Vector3.new(0, 90, -400),
		PassengerSeat1 = Vector3.new(0, 90, -330),
		PassengerSeat2 = Vector3.new(0, 90, -260),
		PassengerSeat3 = Vector3.new(0, 90, -190),
		PassengerSeat4 = Vector3.new(0, 90, -120),
	},
	BodyAnchor = "DriverSeat",
	BodyFloor = "Collide",
	BodyMounts = { Bay = Vector3.new(0, 2, 0) },
	BodyColor = Color3.fromRGB(58, 62, 66),
	BodyMaterial = Enum.Material.Metal,
	TailGuard = true,
	ChaseCamera = true,
	StripDecals = true,
}

-- 473576954 frigate hull (1 mesh; its texture path is dead, so it is recoloured naval grey). Bow +Z (Yaw 180). Captain
-- inside the bridge, crew on the foredeck.
local BODY_FRIGATE = {
	ModelAssetId = 473576954,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 180,
	HideKit = true,
	BodyScale = 2.7,
	BodyWaterline = 4.1,
	BodyColor = Color3.fromRGB(112, 118, 124),
	BodyMaterial = Enum.Material.Metal,
	BodyClearTexture = true,
	BodySeats = {
		DriverSeat = Vector3.new(0, 5.0, 1.5),
		PassengerSeat1 = Vector3.new(-1.2, 4.9, 4.0),
		PassengerSeat2 = Vector3.new(1.2, 4.9, 4.0),
		PassengerSeat3 = Vector3.new(-1.2, 4.9, 5.0),
		PassengerSeat4 = Vector3.new(1.2, 4.9, 5.0),
	},
	BodyAnchor = "DriverSeat",
	StripDecals = true,
}

-- 7941124517 aircraft carrier (1 mesh). Bow +Z (the long narrow flight-deck end, Yaw 180); the island is on -X aft of
-- midships. Captain inside the island, crew on the flight deck. BodyDeck: invisible collidable plates on the flight
-- deck (the kit's own deck / island stop colliding) so players and aircraft stand on the deck they see.
local BODY_CARRIER = {
	ModelAssetId = 7941124517,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 180,
	HideKit = true,
	BodyScale = 3.6,
	BodyWaterline = 2.6,
	BodySeats = {
		DriverSeat = Vector3.new(-6.5, 2.0, -5),
		PassengerSeat1 = Vector3.new(0, 1.8, -10),
		PassengerSeat2 = Vector3.new(3, 1.8, -10),
		PassengerSeat3 = Vector3.new(0, 1.8, -13),
		PassengerSeat4 = Vector3.new(3, 1.8, -13),
	},
	BodyAnchor = "DriverSeat",
	BodyAnchorX = true, -- v88: the island bridge is off the centre line; the body moves across too, so the seat stays in it
	BodyDeck = {
		{ At = Vector3.new(0.65, 1.6, -3), Size = Vector3.new(11.3, 0.4, 28) }, -- main deck, island side to the starboard edge
		{ At = Vector3.new(-1.25, 1.6, 17.5), Size = Vector3.new(7.5, 0.4, 13) }, -- the narrow bow run
		{ At = Vector3.new(-1.5, 1.6, -19.5), Size = Vector3.new(12, 0.4, 5) }, -- the stern
	},
	BodyKitNoCollide = { "Deck", "Superstructure", "Bridge" },
	StripDecals = true,
}

-- 5545544418 amphibious assault ship (24 parts, decals stripped). Bow +Z (Yaw 180). Captain in the island (-X), crew on
-- the flight deck.
local BODY_AMPHIB = {
	ModelAssetId = 5545544418,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 180,
	HideKit = true,
	BodyScale = 0.85,
	BodyWaterline = 6,
	BodySeats = {
		DriverSeat = Vector3.new(-8.5, 17.3, -12),
		PassengerSeat1 = Vector3.new(2, 17.7, 10),
		PassengerSeat2 = Vector3.new(6, 17.7, 10),
		PassengerSeat3 = Vector3.new(2, 17.7, 20),
		PassengerSeat4 = Vector3.new(6, 17.7, 20),
	},
	BodyAnchor = "DriverSeat",
	BodyAnchorX = true, -- v88: the island bridge is off the centre line; the body moves across too, so the seat stays in it
	StripDecals = true,
}

-- 116924692473761 submarine (22 parts). Bow +Z (the propeller is at -Z, Yaw 180). Surface runner: the hull rides 11 studs
-- deep, the sail stands clear; the commander stands in the sail hatch, crew on the hull casing. The propeller spins.
local BODY_SUB = {
	ModelAssetId = 116924692473761,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 180,
	HideKit = true,
	BodyScale = 0.3,
	BodyWaterline = 11,
	BodySeats = {
		DriverSeat = Vector3.new(0, 50, 2),
		PassengerSeat1 = Vector3.new(-5, 42.5, -30),
		PassengerSeat2 = Vector3.new(5, 42.5, -30),
		PassengerSeat3 = Vector3.new(-5, 42.5, 40),
		PassengerSeat4 = Vector3.new(5, 42.5, 40),
	},
	BodyAnchor = "DriverSeat",
	RotorParts = { { Parts = { "Meshes/newsubmarine_Propellor Blades", "Meshes/newsubmarine_Propellor Cap" }, Axis = "Z", Rps = 3 } },
	StripDecals = true,
}

-- v88 (Code Bot, 2026-09-28): the wc6 winners, owner-only, same system (owner: "add them all in"). Seat points from the
-- Open Cloud raycast grids grid88.
-- 80886282228822 ev41 tilt-rotor (37 MeshParts, dark olive). Nose -Z. Pilots in the tandem cockpit seats, troops in the cabin.
local BODY_VTOL = {
	ModelAssetId = 80886282228822,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 0.55,
	BodySeats = {
		DriverSeat = Vector3.new(0, 8.0, -30),
		PassengerSeat1 = Vector3.new(0, 8.0, -25.6),
		PassengerSeat2 = Vector3.new(-2.5, 3.2, -15),
		PassengerSeat3 = Vector3.new(2.5, 3.2, -15),
		PassengerSeat4 = Vector3.new(-2.5, 3.2, -8),
	},
	BodyAnchor = "DriverSeat",
	BodyFloor = "Collide",
	RotorParts = {
		{ Parts = { "Resolution 1.292" }, Hub = "Resolution 1.021", Axis = "Y", Rps = 4 }, -- right proprotor, about its hub
		{ Parts = { "Resolution 1.273" }, Hub = "Resolution 1.015", Axis = "Y", Rps = 4 }, -- left proprotor
	},
	ChaseCamera = true,
	StripDecals = true,
}

-- 11240665977 attack helicopter (10 MeshParts, dark navy; tail rotor baked in, main Blades spin). Nose -Z. Crew in the front seats under the glass.
local BODY_ATTACK_HELI = {
	ModelAssetId = 11240665977,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 0.45,
	BodySeats = {
		DriverSeat = Vector3.new(-4, 6.0, -30),
		PassengerSeat1 = Vector3.new(4, 6.0, -30),
		PassengerSeat2 = Vector3.new(-3.5, 5.5, -13),
		PassengerSeat3 = Vector3.new(3.5, 5.5, -13),
		PassengerSeat4 = Vector3.new(0, 5.5, -8),
	},
	BodyAnchor = "DriverSeat",
	BodyFloor = "Collide",
	RotorParts = { { Parts = { "Blades" }, Hub = "Thing for Blades", Axis = "Y", Rps = 5 } },
	BodyMounts = { StubWingL = Vector3.new(-8.5, 11, -8) }, -- rocket pods (AirWeaponService, mirrored right) beside the cabin
	ChaseCamera = true,
	StripDecals = true,
}

-- v91 (owner 2026-09-28): every helicopter key wears the attack heli 11240665977 (10 parts, every part by its uploader),
-- each in its own military colour on the body panels only (the glass, seats, blades, wheels and engines keep theirs;
-- measured live on v86: BAP 1 / Body / Doors / Thing for Blades are the navy 27,42,53 panels). Owner-only like every
-- heli body (Rollout "Body"). Transport keys: a bigger BodyScale for their bigger kit, and the middle cabin seat
-- (PassengerSeat4) between the cockpit and the rear bench (live v86 raycasts: 4.1-5.1 studs of headroom). The main
-- Blades spin through the v90 rotor lookup. Revert one key: put its old bodyRef line back (BODY_LIGHT_HELI /
-- BODY_TRANSPORT_HELI are kept, unused).
local HELI_PAINT_PARTS = { "BAP 1", "Body", "Doors", "Thing for Blades" }
local function heliRef(scale: number, color: Color3?, cabin: boolean, note: string): AssetRef
	local r: { [string]: any } = {}
	for k, v in pairs(BODY_ATTACK_HELI) do
		r[k] = v
	end
	r.BodyScale = scale
	if color then
		r.BodyColor = color
		r.BodyColorParts = HELI_PAINT_PARTS
	end
	-- v91 live check (v87 place): at z -13 the rear pair stuck out of the tapered tail (no hull beside their heads), and on
	-- the narrow kits (LightScout / Utility / Rescue: seats clamped 1.3-1.6 studs off centre) the crew heads were 2.5
	-- studs under the cockpit roof. Every heli key therefore gets the cockpit a little lower (3.5-4.8 studs under the glass)
	-- and the passengers in the cabin: rear pair beside each other at z -21, the middle seat at z -25 (hull both sides,
	-- roof over them). `cabin` only marks the transport keys (bigger kit, bigger BodyScale).
	local _ = cabin
	local seats: { [string]: Vector3 } = {}
	for k, v in pairs(BODY_ATTACK_HELI.BodySeats) do
		seats[k] = v
	end
	seats.DriverSeat = Vector3.new(-4, 5.4, -30)
	seats.PassengerSeat1 = Vector3.new(4, 5.4, -30)
	seats.PassengerSeat2 = Vector3.new(-3.5, 5.0, -21) -- the cabin
	seats.PassengerSeat3 = Vector3.new(3.5, 5.0, -21)
	seats.PassengerSeat4 = Vector3.new(0, 5.0, -25)
	r.BodySeats = seats
	r.Note = note
	return r :: any
end

-- StealthHeli: the attack-heli body recoloured near-black.
local BODY_STEALTH_HELI = {
	ModelAssetId = 11240665977,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 0.45,
	BodySeats = {
		DriverSeat = Vector3.new(-4, 6.0, -30),
		PassengerSeat1 = Vector3.new(4, 6.0, -30),
		PassengerSeat2 = Vector3.new(-3.5, 5.5, -13),
		PassengerSeat3 = Vector3.new(3.5, 5.5, -13),
		PassengerSeat4 = Vector3.new(0, 5.5, -8),
	},
	BodyAnchor = "DriverSeat",
	BodyFloor = "Collide",
	RotorParts = { { Parts = { "Blades" }, Hub = "Thing for Blades", Axis = "Y", Rps = 5 } },
	BodyMounts = { StubWingL = Vector3.new(-8.5, 11, -8) }, -- rocket pods (AirWeaponService, mirrored right) beside the cabin
	ChaseCamera = true,
	BodyColor = Color3.fromRGB(20, 22, 26), -- near-black (owner: not the Little Bird look-alike 11839207737)
	StripDecals = true,
}

-- 3553891209 Fighter Jet concept (1 MeshPart after the gear goes). Nose +X (Yaw 90). Pilot under the canopy hump.
local BODY_STRIKE_JET = {
	ModelAssetId = 3553891209,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 90,
	HideKit = true,
	BodyScale = 0.9,
	BodySeats = {
		DriverSeat = Vector3.new(10, 0.8, 0),
	},
	BodyAnchor = "DriverSeat",
	OmitParts = { "Part" }, -- its 24 landing-gear Parts (the kit gear still stands it)
	BodyFloor = "Collide",
	BodyColor = Color3.fromRGB(44, 48, 54), -- dark; its texture (the earlier registry note: another artist's paint) is cleared
	BodyClearTexture = true,
	TailGuard = true,
	ChaseCamera = true,
	StripDecals = true,
}

-- 7976374439 stealth delta (4 MeshParts; its red neon strip / exhausts stay as a glow). Nose -Z.
local BODY_STEALTH_STRIKE = {
	ModelAssetId = 7976374439,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 0.9,
	BodySeats = {
		DriverSeat = Vector3.new(0, 1.0, -2),
	},
	BodyAnchor = "DriverSeat",
	BodyFloor = "Collide",
	TailGuard = true,
	ChaseCamera = true,
	StripDecals = true,
}

-- v89: 10649792198 cargo plane mesh (yulikemir; high-wing 4-engine airlifter, 1 mesh; replaces 17033079003). Nose -X
-- (Yaw -90). Pilot in the nose, crew in the cargo bay.
local BODY_AIRLIFTER = {
	ModelAssetId = 10649792198,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = -90,
	HideKit = true,
	BodyScale = 2.1,
	BodySeats = {
		DriverSeat = Vector3.new(-10.5, 2.0, 0),
		PassengerSeat1 = Vector3.new(-7, 1.9, -1.2),
		PassengerSeat2 = Vector3.new(-7, 1.9, 1.2),
		PassengerSeat3 = Vector3.new(-4, 1.9, -1.2),
		PassengerSeat4 = Vector3.new(-4, 1.9, 1.2),
	},
	BodyAnchor = "DriverSeat",
	BodyFloor = "Collide",
	BodyColor = Color3.fromRGB(70, 74, 80), -- dark grey (untextured default grey mesh)
	BodyMaterial = Enum.Material.Metal,
	TailGuard = true,
	ChaseCamera = true,
	StripDecals = true,
}

-- 12235335847 ramp barge (27 parts, 24 kept). Ramp / bow -Z. Helmsman in the forward deckhouse, troops on the cargo deck.
local BODY_BARGE = {
	ModelAssetId = 12235335847,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 0.25,
	BodySeats = {
		DriverSeat = Vector3.new(1.2, 35.2, -45),
		PassengerSeat1 = Vector3.new(-8, 35.3, -10),
		PassengerSeat2 = Vector3.new(8, 35.3, -10),
		PassengerSeat3 = Vector3.new(-8, 35.3, 10),
		PassengerSeat4 = Vector3.new(8, 35.3, 10),
	},
	BodyAnchor = "DriverSeat",
	BodyWaterline = 5.7,
	OmitParts = { "Meshes/bargepiece12_Cylinder.051", "Meshes/bargepiece12_Cube.130", "Meshes/bargepiece12_Cylinder.080" }, -- hanging anchor + chain
	StripDecals = true,
}

-- 2625253037 tanker (10 MeshParts, the creator's own textures). Bow -Z. Captain inside the aft bridge, crew on the deck.
local BODY_SUPPORT_SHIP = {
	ModelAssetId = 2625253037,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 1,
	BodySeats = {
		DriverSeat = Vector3.new(0, 15.5, 36),
		PassengerSeat1 = Vector3.new(-3, 14.6, 5),
		PassengerSeat2 = Vector3.new(3, 14.6, 5),
		PassengerSeat3 = Vector3.new(-3, 14.6, 10),
		PassengerSeat4 = Vector3.new(3, 14.6, 10),
	},
	BodyAnchor = "DriverSeat",
	BodyWaterline = 6.2,
	StripDecals = true,
}

-- 3626114334 hovercraft (1 textured mesh). Nose -Z. Driver in the forward cabin, riders inside behind.
local BODY_HOVER = {
	ModelAssetId = 3626114334,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 0.8,
	BodySeats = {
		DriverSeat = Vector3.new(0, 4.5, -9),
		PassengerSeat1 = Vector3.new(-3, 4.5, -3),
		PassengerSeat2 = Vector3.new(3, 4.5, -3),
		PassengerSeat3 = Vector3.new(-3, 4.5, 3),
		PassengerSeat4 = Vector3.new(3, 4.5, 3),
	},
	BodyAnchor = "DriverSeat",
	BodyWaterline = 2.9,
	StripDecals = true,
}

-- v89 (Code Bot, 2026-09-28): the wc7 winners for the capital ships (owner-only, same system). Outlines / bows from the
-- Open Cloud raycast grids grid89 + side89.
-- 6860896505 Stud Class Cruiser (flipper_b, fictional class; 1 mesh). Bow +Z (Yaw 180): the pointed end with the full-depth
-- stem; -Z is the rounded overhanging cruiser stern with the superfiring aft turrets. Captain inside the bridge block
-- (body z 65, forward of the tall tower), crew on the foredeck.
local BODY_DESTROYER = {
	ModelAssetId = 6860896505,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 180,
	HideKit = true,
	BodyScale = 0.2,
	BodyWaterline = 2.5,
	BodyColor = Color3.fromRGB(58, 62, 68), -- dark naval grey (the store mesh is untextured default grey)
	BodyMaterial = Enum.Material.Metal,
	BodySeats = {
		DriverSeat = Vector3.new(0, 55, 65),
		PassengerSeat1 = Vector3.new(-4, 55.6, 94),
		PassengerSeat2 = Vector3.new(4, 55.6, 94),
		PassengerSeat3 = Vector3.new(-4, 55.3, 108),
		PassengerSeat4 = Vector3.new(4, 55.3, 108),
	},
	BodyAnchor = "DriverSeat",
	BodyMounts = { -- the kit's forward / aft turret points onto the body's own turrets (body frame, like BodySeats)
		TurretF = Vector3.new(0, 50, 140),
		BarrelF = Vector3.new(0, 42, 185),
		TurretA = Vector3.new(0, 50, -100),
	},
	StripDecals = true,
}

-- Cruiser: the same Stud Class hull, a little larger.
local BODY_CRUISER = {
	ModelAssetId = 6860896505,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 180,
	HideKit = true,
	BodyScale = 0.22,
	BodyWaterline = 2.8,
	BodyColor = Color3.fromRGB(58, 62, 68), -- dark naval grey (the store mesh is untextured default grey)
	BodyMaterial = Enum.Material.Metal,
	BodySeats = {
		DriverSeat = Vector3.new(0, 55, 65),
		PassengerSeat1 = Vector3.new(-4, 55.6, 94),
		PassengerSeat2 = Vector3.new(4, 55.6, 94),
		PassengerSeat3 = Vector3.new(-4, 55.3, 108),
		PassengerSeat4 = Vector3.new(4, 55.3, 108),
	},
	BodyAnchor = "DriverSeat",
	BodyMounts = { -- the kit's forward / aft turret points onto the body's own turrets (body frame, like BodySeats)
		TurretF = Vector3.new(0, 50, 140),
		BarrelF = Vector3.new(0, 42, 185),
		TurretA = Vector3.new(0, 50, -100),
	},
	StripDecals = true,
}

-- 104820847233642 Missile_boat (someonejamhoss; 1 mesh). Bow -Z: the fine prow with the forward gun, square transom aft.
-- Captain inside the forward bridge, crew on the aft deck.
local BODY_MISSILE_CRUISER = {
	ModelAssetId = 104820847233642,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 18,
	BodyMaxScale = 18, -- authored 5.7 studs long: fitted at 18 (102 long)
	BodyWaterline = 4.3,
	BodyColor = Color3.fromRGB(58, 62, 68), -- dark naval grey (the store mesh is untextured default grey)
	BodyMaterial = Enum.Material.Metal,
	BodySeats = {
		DriverSeat = Vector3.new(0, 0.73, -0.6),
		PassengerSeat1 = Vector3.new(-0.12, 0.62, 1.3),
		PassengerSeat2 = Vector3.new(0.12, 0.62, 1.3),
		PassengerSeat3 = Vector3.new(-0.12, 0.62, 1.6),
		PassengerSeat4 = Vector3.new(0.12, 0.62, 1.6),
	},
	BodyAnchor = "DriverSeat",
	BodyMounts = { -- the kit's forward / aft turret points onto the body's own turrets (body frame, like BodySeats)
		TurretF = Vector3.new(0, 0.72, -1.9),
		BarrelF = Vector3.new(0, 0.72, -2.2),
		TurretA = Vector3.new(0, 0.62, 1.0),
	},
	StripDecals = true,
}

-- 12442299148 Battleship (poopori_guy, no nation; 1 mesh). Bow -Z: the fine raked end with three stepped turrets
-- facing it. Captain inside the overhanging bridge block, crew on the aft superstructure deck.
local BODY_BATTLESHIP = {
	ModelAssetId = 12442299148,
	Rollout = "Body",
	Fit = "Kit",
	Yaw = 0,
	HideKit = true,
	BodyScale = 2.0,
	BodyWaterline = 4.0,
	BodyColor = Color3.fromRGB(58, 62, 68), -- dark naval grey (the store mesh is untextured default grey)
	BodyMaterial = Enum.Material.Metal,
	BodySeats = {
		DriverSeat = Vector3.new(0, 11.8, 0.3),
		PassengerSeat1 = Vector3.new(-1.8, 8.25, 10),
		PassengerSeat2 = Vector3.new(1.8, 8.25, 10),
		PassengerSeat3 = Vector3.new(-1.8, 8.15, 12.5),
		PassengerSeat4 = Vector3.new(1.8, 8.15, 12.5),
	},
	BodyAnchor = "DriverSeat",
	BodyMounts = { -- the kit's forward / aft turret points onto the body's own turrets (body frame, like BodySeats)
		TurretF = Vector3.new(0, 8.5, -12),
		BarrelF = Vector3.new(0, 8.0, -17),
		TurretA = Vector3.new(0, 7.0, 17),
	},
	StripDecals = true,
}

-- v119 (owner pick 2026-09-29): the soldier body of the player's army (Squad + escorts) and the base / tower guards.
-- "Army Soldier" 7703684779 (Creator Store, @Ca_zr, free; owned by the place creator so LoadAsset works live): a
-- block-limb R6 body dressed by a camo Shirt / Pants and a FAST helmet. Its 6 scripts, 9 remotes, weapons (26 unions,
-- 8 MeshParts) and sounds never reach a template (VisualAssetService strips every script / remote first; RigBuilder keeps
-- only Torso, 4 limbs, the helmet and the clothing template ids). A failed load or a refused rig falls back to the Roblox
-- "Soldier" 187790284 (the v118 body). Set SOLDIER_ASSET_ID = 187790284 to go back to the old body everywhere.
local SOLDIER_ASSET_ID = 7703684779
local SOLDIER_FALLBACK_ID = 187790284

local VisualAssetConfig = {
	Enabled = true,
	SoldierAssetId = SOLDIER_ASSET_ID, -- v119: Characters.Squad / Guard / GateGuard
	SoldierFallbackAssetId = SOLDIER_FALLBACK_ID,
	StripScripts = true,
	-- v87 (Code Bot): who wears the Rollout = "Body" store bodies (helicopters, bombers, transports, ships): "owner" = only
	-- vehicles spawned by the playtest owner (AdminConfig.IsPlaytestOwner), "all" = everyone, "off" = nobody (Part kit).
	BodyRollout = "owner",
	MaxLoadAttempts = 64, -- per server, first tries + retries; an id asked for after that keeps its Part kit (one Output line)
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
	LoadRetryReserve = 24,
	-- Owner asset list hooks (2026-09-25): 48 / 12 -> 64 / 24. Retries still stop at 40 attempts (64 - 24, as before);
	-- the first-load reserve doubles, so a full outage keeps 24 first loads for the plot / later ids (walls, vehicle
	-- bodies, turret dress, businesses). Healthy servers load the same ids as before; an outage costs at most 16 more
	-- failed LoadAsset calls. tools/wire-asset-ids.py refuses a promote batch that takes the distinct live ids
	-- past MaxLoadAttempts - 8 (= 56), or whose outage count (every id a plot / later chain can ask for, fallbacks
	-- included) passes LoadRetryReserve. PendingAssetId ids are never loaded, so they cost 0.
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
	-- is prepared (phone cost). 23153991 = Roblox "Smoking Barrel" (the training-yard oil drum, smoke removed);
	-- 31603741 = Roblox "Rocket" (Rocket Assembly: Fire + Smoke removed); 4362642898 = the owner's pending Armor Plate
	-- Press pick (its Smoke goes when it is promoted).
	StripEffectsAssetIds = { 23153991, 31603741, 4362642898 },
	FitShadowShare = 0.5, -- fitted vehicle bodies: only parts at least this share of the chassis length cast a shadow
	-- vscale R2.1: a BodySeats seat's centre stays at least this far inside the kit's collidable box (the Cargo Van's
	-- front row moves back, the Dispatch Car's back seat forward), so no seat and no seated rider is ever past the kit's
	-- nose or tail, inside a wall the kit touches. 0 = on the kit's face.
	BodySeatKitInset = 0.25,
	-- vscale R2.3 (review M2): a fitted body's label (WE_LabelY: the owner nameplate; the HP bar sits 0.75 under it)
	-- stands Base + PerStud x (the body top's height over the ground - EyeHeight) over the top, so a player on foot
	-- beside a tall van or truck sees them over the roof (R2.2's flat 1 left the bar 0.08 over the roof, hidden by it).
	-- Van / trucks about 3.1, 4x4 2.4, Quad 2.6. { Base = 1, PerStud = 0 } = R2.2.
	BodyLabelMargin = { Base = 1, PerStud = 0.4, EyeHeight = 4.5 },
	-- air-looks (2026-09-28): store aircraft bodies. ChaseCamera refs: the seated player's minimum camera zoom is the body's
	-- far end (WE_VisualHalfLength) + ChaseCameraMargin, at most ChaseCameraMax and never past the player's own max zoom,
	-- restored on exit (AircraftBodyClient). RotorSpin: RotorParts joints (tag WE_RotorJoint) turn on each client, cheap:
	-- one Stepped loop at Hz, Steps precomputed angles (no allocation per frame), only while someone sits in the driver
	-- seat (WE_DriverUserId), spun up / down over SpinUpSeconds, only the MaxAircraft nearest within MaxDistance of the
	-- camera (re-picked every Refresh seconds). Enabled = false: every rotor stands still (the body still loads).
	-- air2 (2026-09-28): margin 6 -> 18. With the owner's 44-stud jet (the only ChaseCamera refs) 6 put the phone camera
	-- 5 studs behind the tail, where its fin fills the screen; 18 gives a 46-stud chase (fix1 seat) that shows the whole jet and the
	-- sky ahead (fb4/air2 renders). The player can still zoom out to his own maximum.
	-- air2 fix1: BodyHitBoxes = true: a ref's BodyHitBoxes become invisible hit plates (CanQuery, never collide, massless,
	-- welded) over the fitted body, and the kit's hidden parts stop taking shots, so a gun or missile hits the jet players
	-- see (44 long) instead of the hidden 12-stud kit under its nose. false = shots hit the kit as before (one switch).
	-- TailGuard (refs with TailGuard = true): the fitted body reaches far behind the kit's wheels (the owner's jet: 24 studs)
	-- and never collides, so a 6-15 degree lift-off or a flare near the ground would sink its tail into the runway (and a
	-- dive its nose, a low turn a wing tip). The server writes the body's lowest box corners (WE_TailGuard, each Margin
	-- studs lower); near the ground the plane law (VehicleDriveClient Laws.TailGuard) eases pitch and bank back toward
	-- level together until every corner clears the ground, looking LeadSeconds ahead while sinking; a lift-off keeps at
	-- least MinPitch (a climb, over the touchdown line). Enabled = false: the law is exactly as before.
	AirBody = {
		ChaseCameraMargin = 18,
		ChaseCameraMax = 60,
		-- air fix2: while seated, the minimum zoom stays at least ChaseCameraSpan studs under the maximum zoom, so pinch
		-- zoom still works when another module (the vehicle-kit chase cap) lowers the maximum
		ChaseCameraSpan = 8,
		BodyHitBoxes = true,
		TailGuard = { Enabled = true, Margin = 0.3, MinPitch = 3.5, LeadSeconds = 0.15 },
		RotorSpin = {
			Enabled = true,
			Hz = 30,
			Steps = 24,
			MaxAircraft = 6,
			MaxDistance = 400,
			SpinUpSeconds = 2.5,
			Refresh = 0.5,
		},
	},
	-- claude-bud JOB 56: the rotor spins about ITS OWN disc, not the chassis Y. rigRotor used the chassis axis through
	-- the Hub's box centre: a blade disc tilted against the chassis wobbles ("tilted rotor") and a hub box that is not
	-- on the blades' centre makes them orbit ("detached rotor"). With this on (owner-first by the vehicle owner) the
	-- spin axis is the blades' thinnest box axis (within MaxCorrectionDeg of the configured axis, only when clearly
	-- thin: ThinRatio) and the centre is the blades' own centre. Every rotor logs [RotorRig] tilt / offset.
	-- claude-bud JOB 67: the asset upgrade switch (owner-first by the BASE OWNER; OFF = today's models)
	Job67 = {
		Enabled = true,
		OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 67): Code Bot flips it with the public flip
		-- the turret tier by the owner's Turret Guns level (EndgameConfig.Defence, 0..10): 0 = T1, 1-3 = T2, 4-6 = T3,
		-- 7-9 = T4, 10 = T5
		TurretTierAt = { 1, 4, 7, 10 }, -- the first level of T2 / T3 / T4 / T5
		TurretTierKeys = { "AutoGunT1", "AutoGunT2", "AutoGunT3", "AutoGunT4", "AutoGunT5" },
	},
	AirRotorDisc = {
		Enabled = true,
		OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 56): Code Bot flips it after Shaun's phone test
		MinTiltDeg = 1, -- below this the configured axis is kept
		MinOffset = 0.05, -- studs: below this the configured centre is kept
		MaxCorrectionDeg = 25, -- a larger "tilt" means the box guess is wrong: keep the configured axis
		ThinRatio = 0.5, -- the thinnest box side must be under half the next one (a flat blade disc)
	},
	-- air-looks fix1 (2026-09-28): the phone cost of ONE store vehicle body, in Creator Store triangles (the whole model;
	-- a pack counts in full). tools/wire-asset-ids.py promote refuses a vehicle body above it unless the lead accepts it
	-- (--heavy-ok / HEAVY_OK); the owner's phone test then checks the frame rate with two or more in view at Graphics
	-- Quality 3 or on a mid-range Android. A tool gate only: a script cannot read a mesh's triangle count. Live bodies:
	-- Recon Plane 738, APC 3,314; the jet pick 11,460 passes, the rescue helicopter pick 65,837 does not.
	VehicleBodyMaxTriangles = 20000,
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
			-- vscale: Roblox size (the kit is 8.5 long; a seated avatar's head is 0.5 under the glass). Seats: the body's own.
			BodyScale = 1,
			BodySeats = {
				DriverSeat = Vector3.new(-1.216, 3.387, -0.496), -- VehicleSeat
				PassengerSeat1 = Vector3.new(1.2, 3.388, -0.496), -- SeatFR
				PassengerSeat2 = Vector3.new(-1.216, 3.387, 3.504), -- SeatRL
				PassengerSeat3 = Vector3.new(1.2, 3.388, 3.504), -- SeatRR
			},
			BodyRoofParts = { "GunMount", "Barrel" },
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
			-- vscale: 1.2 x Roblox size (R2.2; R2.1 1.0, R2 0.95). Seats: over the body's own VehicleSeat, the passenger
			-- on its mirror (the model's SeatFR is posed for its own Passenger_Seated animation, which the game does not
			-- play), both seat tops 0.25 (unscaled) over the VehicleSeat's. At 1.0 no seat height fits a default-pose
			-- avatar: feet on the floor put the head up in the roll cage's top rails (R2.1). At 1.2 the feet are on the
			-- floor and the head is 0.6 under the top rails (a 0.5 taller avatar: 0.1 under). buggy_metrics, vscale R2.2.
			BodyScale = 1.2,
			BodySeats = {
				DriverSeat = Vector3.new(-1.349, 2.434, 1.223), -- VehicleSeat + 0.25
				PassengerSeat1 = Vector3.new(1.349, 2.434, 1.223), -- mirror of the VehicleSeat (right-hand seat) + 0.25
			},
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
			-- vscale: 1.2 x Roblox size (R2.2; R2.1 1.0, R2 0.95). Seats: over the body's own VehicleSeat, the passenger
			-- on its mirror (the model's SeatFR is posed for its own Passenger_Seated animation, which the game does not
			-- play), both seat tops 0.25 (unscaled) over the VehicleSeat's. At 1.0 no seat height fits a default-pose
			-- avatar: feet on the floor put the head up in the roll cage's top rails (R2.1). At 1.2 the feet are on the
			-- floor and the head is 0.6 under the top rails (a 0.5 taller avatar: 0.1 under). buggy_metrics, vscale R2.2.
			BodyScale = 1.2,
			BodySeats = {
				DriverSeat = Vector3.new(-1.349, 2.434, 1.223), -- VehicleSeat + 0.25
				PassengerSeat1 = Vector3.new(1.349, 2.434, 1.223), -- mirror of the VehicleSeat (right-hand seat) + 0.25
			},
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
		TransportHeli = heliRef(0.52, Color3.fromRGB(54, 78, 56), true, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (forest green)"),
		AttackHelicopter = bodyRef(BODY_ATTACK_HELI, "v88 owner pick 11240665977 attack helicopter (wc6), owner-only rollout"),
		LightTransportHeli = heliRef(0.48, Color3.fromRGB(118, 134, 112), true, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (sage green)"),
		NightAttackHeli = heliRef(0.45, Color3.fromRGB(58, 62, 40), false, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (dark olive)"),
		LightScoutHeli = heliRef(0.45, Color3.fromRGB(100, 108, 68), false, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (olive drab)"),
		GunshipHeli = heliRef(0.45, Color3.fromRGB(74, 80, 88), false, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (gunmetal grey)"),
		HeavyLiftHeli = heliRef(0.6, Color3.fromRGB(116, 92, 66), true, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (earth brown)"),
		RescueHeli = heliRef(0.45, Color3.fromRGB(190, 168, 122), false, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (desert sand)"),
		StealthHeli = bodyRef(BODY_STEALTH_HELI, "v88 owner pick 11240665977 attack helicopter, near-black (wc6), owner-only rollout"),
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
			-- vscale: Roblox size (a seated avatar's head is 0.4 under the glass). Seats: the body's own.
			BodyScale = 1,
			BodySeats = {
				DriverSeat = Vector3.new(-1.708, 5.075, -2.092), -- VehicleSeat
				PassengerSeat1 = Vector3.new(1.708, 5.075, -2.091), -- SeatFR
				PassengerSeat2 = Vector3.new(-1.708, 5.075, 2.158), -- SeatRL
				PassengerSeat3 = Vector3.new(1.708, 5.075, 2.159), -- SeatRR
			},
			Note = "owner list: Roblox Pickup Truck (bronze) Body (41 MeshParts; the overlapping tail-light glass is omitted = 40), fitted to the kit; dress-only, the Part kit drives. 0 = Part kit",
		} :: AssetRef,
		ArmoredTruck = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store picks retired: 8546141386 (stencilled military unit markings) / 8455894899 (53 parts > 40)" } :: AssetRef,
		-- wc3 (second check, live place v75): front at -Z (white lights and the grey plate at -Z, red lights at +Z), Yaw 0.
		-- 0.55 of Roblox size (27.5 long, 11 wide, antennas to 10.4). The hull mesh's box top (12.43) is its cupola, not
		-- the roof: the flat roof is at or below 10.12, where the cupola's blue band starts (antenna bases 10.88), so 5.57
		-- at 0.55. The hull is one mesh with no seats, so every seat is placed by eye at y 2.2: a seated head (seat top +
		-- 3.7) is 4.91, 0.66 under that roof; the feet end 0.21 over the ground, inside the hull. Riders hidden, as in a
		-- closed APC: phone check. The same body on the four WheeledAPC variants below.
		APC = {
			ModelAssetId = 9076240315,
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			BodyScale = 0.55,
			BodySeats = {
				DriverSeat = Vector3.new(-2.5, 2.2, -4), -- no body seat: inside the hull, behind the cupola, under the roof (placed by eye)
				PassengerSeat1 = Vector3.new(2.5, 2.2, -4),
				PassengerSeat2 = Vector3.new(-2.5, 2.2, 2),
				PassengerSeat3 = Vector3.new(2.5, 2.2, 2),
				PassengerSeat4 = Vector3.new(-2.5, 2.2, 6),
			},
			StripDecals = true,
			Note = "owner pick: APC by CorzCringe (promoted 2026-09-27 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		-- Free jet family (classic + named free fighter)
		_FallbackJet = { ModelAssetId = 0, Note = "Classic free fighter jet" } :: AssetRef,
		-- air2 (owner's raw v83 lines, 2026-09-28): 8 MeshParts, 11.52 x 4.77 x 17.5, no paint images, 0 scripts; every mesh
		-- uploaded by the seller (origin check). Nose at +Z (the fuselage tip at z 8.74, the tail fins at z -8.75), so Yaw
		-- 180. BodyScale 2.5 (the owner's number): 43.7 long, 28.8 wide, 11.9 tall, about a real fighter next to a 5-stud
		-- avatar. The kit (12 long) still flies it: physics, collisions and drive are the kit's; shots hit JET_HIT_BOXES.
		-- air2 fix1 (review): the whole seated pilot is inside the body. Seat z 3.3 (round 0) left the shins and feet under
		-- the fuselage, ahead of the belly block Cube.001 (z -7.2..3.34, the only part that reaches below the round
		-- fuselage); at z 2.35 the legs (up to 2.05 ahead of the seat, 0.82 unscaled) end 0.41 studs short of its front.
		-- fix2 (review): x 0.04 = the belly block's centre line, seat top 0.72 over the lowest point (1.8 at 2.5). Checked
		-- against a rounder proxy (the canopy a half tube, the fuselage a round tube of radius 0.80 by the cockpit, where the
		-- canopy's bottom edges meet it): the head top (seat top + 3.7, VS-A5) 0.68 under the canopy top, a +0.5 avatar's
		-- head inside the canopy's curve; hips, legs, body and arms in the belly block, the arms' outer edges at most 0.05
		-- studs past its sides (a seated avatar is 4.0 wide, the block 3.9). BodyLift 1: the body
		-- stands 1 stud higher (belly 2 over the runway) on JET_GEAR, drawn gear the size of a real jet's (the kit's 0.9-stud
		-- wheels stay hidden under it and still carry the jet); TailGuard keeps its tail out of the runway at lift-off.
		FighterJet = {
			ModelAssetId = 14589101870,
			Fit = "Kit",
			Yaw = 180,
			HideKit = true,
			BodyScale = 2.5,
			BodyLift = 1,
			BodySeats = {
				DriverSeat = Vector3.new(0.04, 0.72, 2.35), -- over the belly block's centre line, head inside the canopy (air2 fix2)
			},
			BodyAnchor = "DriverSeat", -- the body moves back along the kit so the cockpit is over the kit's pilot seat
			BodyMounts = {
				Nose = Vector3.new(0.07, 1.49, 8.74), -- gun: the fuselage's nose tip
				WingL = Vector3.new(5.48, 1.24, 0.18), -- missiles: the front of the wing-tip missile (mirrored right)
			},
			BodyHitBoxes = JET_HIT_BOXES,
			BodyGear = JET_GEAR,
			TailGuard = true,
			ChaseCamera = true,
			BodyColor = Color3.fromRGB(118, 126, 136), -- v90: air-superiority grey (one colour per jet)
			BodyColorParts = JET_PAINT_PARTS,
			StripDecals = true,
			Note = "owner pick: Basic Fighter jet by Alecose1 (promoted 2026-09-28 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		InterceptorJet = {
			ModelAssetId = 14589101870,
			Fit = "Kit",
			Yaw = 180,
			HideKit = true,
			BodyScale = 2.5,
			BodyLift = 1,
			BodySeats = {
				DriverSeat = Vector3.new(0.04, 0.72, 2.35), -- over the belly block's centre line, head inside the canopy (air2 fix2)
			},
			BodyAnchor = "DriverSeat", -- the body moves back along the kit so the cockpit is over the kit's pilot seat
			BodyMounts = {
				Nose = Vector3.new(0.07, 1.49, 8.74), -- gun: the fuselage's nose tip
				WingL = Vector3.new(5.48, 1.24, 0.18), -- missiles: the front of the wing-tip missile (mirrored right)
			},
			BodyHitBoxes = JET_HIT_BOXES,
			BodyGear = JET_GEAR,
			TailGuard = true,
			ChaseCamera = true,
			BodyColor = Color3.fromRGB(64, 82, 108), -- v90: navy blue-grey (one colour per jet)
			BodyColorParts = JET_PAINT_PARTS,
			StripDecals = true,
			Note = "owner pick: Basic Fighter jet by Alecose1 (promoted 2026-09-28 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		-- air2: the same jet as a two-seat trainer (unarmed). fix1: both riders inside the body: the front seat where the
		-- fighters' pilot sits, the rear one 2.75 studs behind it (1.1 unscaled: a seated avatar reaches 2.05 forward and 0.55
		-- back). fix2 (review): its head sits at the canopy's flat back end, where only the belly block and the fuselage
		-- tube cover it, so the rear seat is 0.5 studs lower (0.55): the whole head inside the belly block, a +0.5 avatar's
		-- head top level with it. The passenger boards with the Ride prompt (Drive.Ride.BodyModes).
		TrainerJet = {
			ModelAssetId = 14589101870,
			Fit = "Kit",
			Yaw = 180,
			HideKit = true,
			BodyScale = 2.5,
			BodyLift = 1,
			BodySeats = {
				DriverSeat = Vector3.new(0.04, 0.72, 2.35), -- tandem: front seat, over the belly block's centre line (air2 fix2)
				PassengerSeat1 = Vector3.new(0.04, 0.55, 1.25), -- tandem: rear seat, 2.75 studs behind and 0.43 lower (air2 fix2)
			},
			BodyAnchor = "DriverSeat", -- the body moves back along the kit so the cockpit is over the kit's pilot seat
			BodyHitBoxes = JET_HIT_BOXES,
			BodyGear = JET_GEAR,
			TailGuard = true,
			ChaseCamera = true,
			BodyColor = Color3.fromRGB(184, 162, 118), -- v90: desert sand (one colour per jet)
			BodyColorParts = JET_PAINT_PARTS,
			StripDecals = true,
			Note = "owner pick: Basic Fighter jet by Alecose1 (promoted 2026-09-28 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		-- wc3 (owner yes 2026-09-27; second check, live place v75): nose at -X (propeller blade and ball nose at -X, fin and
		-- tail plane at +X), so Yaw -90. Roblox size: 18 long, 25.3 wide. The pilot sits just behind the wing, sunk in the
		-- solid fuselage (the model has no cockpit opening): seat top 1.2 over the lowest point (unscaled), seated head top
		-- 4.9 against a fuselage top of 3.89, so only the top of the head shows; the shoulders stay about 0.3 under. The
		-- model has no wheels, so the kit's landing gear stays visible under it. Its fuselage is a Cylinder part:
		-- VisualAssetService fits the box Roblox draws (3.88 round), not the 11.26-tall Size.
		ReconPlane = {
			ModelAssetId = 4954987035,
			Fit = "Kit",
			Yaw = -90,
			HideKit = true,
			KeepVisible = { "GearF", "WheelF", "GearL", "GearR", "WheelL", "WheelR" },
			BodyScale = 1,
			BodySeats = {
				DriverSeat = Vector3.new(-1, 1.2, 0), -- 1.4 behind the wing's trailing edge; only the head top clears the body
			},
			StripDecals = true,
			Note = "owner pick: Old propeller plane by Deadex40_Extra (promoted 2026-09-27 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		LightFighter = {
			ModelAssetId = 14589101870,
			Fit = "Kit",
			Yaw = 180,
			HideKit = true,
			BodyScale = 2.5,
			BodyLift = 1,
			BodySeats = {
				DriverSeat = Vector3.new(0.04, 0.72, 2.35), -- over the belly block's centre line, head inside the canopy (air2 fix2)
			},
			BodyAnchor = "DriverSeat", -- the body moves back along the kit so the cockpit is over the kit's pilot seat
			BodyMounts = {
				Nose = Vector3.new(0.07, 1.49, 8.74), -- gun: the fuselage's nose tip
				WingL = Vector3.new(5.48, 1.24, 0.18), -- missiles: the front of the wing-tip missile (mirrored right)
			},
			BodyHitBoxes = JET_HIT_BOXES,
			BodyGear = JET_GEAR,
			TailGuard = true,
			ChaseCamera = true,
			BodyColor = Color3.fromRGB(96, 104, 66), -- v90: olive drab (one colour per jet)
			BodyColorParts = JET_PAINT_PARTS,
			StripDecals = true,
			Note = "owner pick: Basic Fighter jet by Alecose1 (promoted 2026-09-28 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		-- v90 (owner 2026-09-28): the owner's jet 14589101870 replaces the v88 body on this key, pilot inside like the
		-- other jets (the FighterJet layout); Rollout "Body" keeps it owner-only like the v88 body it replaces.
		StrikeJet = {
			ModelAssetId = 14589101870,
			Rollout = "Body",
			Fit = "Kit",
			Yaw = 180,
			HideKit = true,
			BodyScale = 2.5,
			BodyLift = 1,
			BodySeats = {
				DriverSeat = Vector3.new(0.04, 0.72, 2.35), -- over the belly block's centre line, head inside the canopy (air2 fix2)
			},
			BodyAnchor = "DriverSeat", -- the body moves back along the kit so the cockpit is over the kit's pilot seat
			BodyMounts = {
				Nose = Vector3.new(0.07, 1.49, 8.74), -- gun: the fuselage's nose tip
				WingL = Vector3.new(5.48, 1.24, 0.18), -- missiles: the front of the wing-tip missile (mirrored right)
			},
			BodyHitBoxes = JET_HIT_BOXES,
			BodyGear = JET_GEAR,
			TailGuard = true,
			ChaseCamera = true,
			BodyColor = Color3.fromRGB(62, 82, 60), -- v90: dark green (one colour per jet)
			BodyColorParts = JET_PAINT_PARTS,
			StripDecals = true,
			Note = "v90 owner pick: Basic Fighter jet by Alecose1 14589101870 (replaces the v88 body), owner-only rollout",
		} :: AssetRef,
		-- v90 (owner 2026-09-28): the owner's jet 14589101870 replaces the v88 body on this key, pilot inside like the
		-- other jets (the FighterJet layout); Rollout "Body" keeps it owner-only like the v88 body it replaces.
		CASJet = {
			ModelAssetId = 14589101870,
			Rollout = "Body",
			Fit = "Kit",
			Yaw = 180,
			HideKit = true,
			BodyScale = 2.5,
			BodyLift = 1,
			BodySeats = {
				DriverSeat = Vector3.new(0.04, 0.72, 2.35), -- over the belly block's centre line, head inside the canopy (air2 fix2)
			},
			BodyAnchor = "DriverSeat", -- the body moves back along the kit so the cockpit is over the kit's pilot seat
			BodyMounts = {
				Nose = Vector3.new(0.07, 1.49, 8.74), -- gun: the fuselage's nose tip
				WingL = Vector3.new(5.48, 1.24, 0.18), -- missiles: the front of the wing-tip missile (mirrored right)
			},
			BodyHitBoxes = JET_HIT_BOXES,
			BodyGear = JET_GEAR,
			TailGuard = true,
			ChaseCamera = true,
			BodyColor = Color3.fromRGB(126, 100, 72), -- v90: earth brown (one colour per jet)
			BodyColorParts = JET_PAINT_PARTS,
			StripDecals = true,
			Note = "v90 owner pick: Basic Fighter jet by Alecose1 14589101870 (replaces the v88 body), owner-only rollout",
		} :: AssetRef,
		-- v90 (owner 2026-09-28): the owner's jet 14589101870 replaces the v88 body on this key, pilot inside like the
		-- other jets (the FighterJet layout); Rollout "Body" keeps it owner-only like the v88 body it replaces.
		StealthStrikeJet = {
			ModelAssetId = 14589101870,
			Rollout = "Body",
			Fit = "Kit",
			Yaw = 180,
			HideKit = true,
			BodyScale = 2.5,
			BodyLift = 1,
			BodySeats = {
				DriverSeat = Vector3.new(0.04, 0.72, 2.35), -- over the belly block's centre line, head inside the canopy (air2 fix2)
			},
			BodyAnchor = "DriverSeat", -- the body moves back along the kit so the cockpit is over the kit's pilot seat
			BodyMounts = {
				Nose = Vector3.new(0.07, 1.49, 8.74), -- gun: the fuselage's nose tip
				WingL = Vector3.new(5.48, 1.24, 0.18), -- missiles: the front of the wing-tip missile (mirrored right)
			},
			BodyHitBoxes = JET_HIT_BOXES,
			BodyGear = JET_GEAR,
			TailGuard = true,
			ChaseCamera = true,
			BodyColor = Color3.fromRGB(46, 48, 54), -- v90: charcoal (same as StealthStrike: an alias ref, not a vehicle key) (one colour per jet)
			BodyColorParts = JET_PAINT_PARTS,
			StripDecals = true,
			Note = "v90 owner pick: Basic Fighter jet by Alecose1 14589101870 (replaces the v88 body), owner-only rollout",
		} :: AssetRef,
		StrikeBomber = bodyRef(BODY_BOMBER, "v87 owner pick 14669079591 delta-wing bomber (wc5), owner-only rollout"),
		CargoPlane = bodyRef(BODY_AIRLIFTER, "v89 owner pick 10649792198 4-engine airlifter, dark grey (wc7; replaces 17033079003), owner-only rollout"),
		AWACSPlane = bodyRef(BODY_AIRLIFTER, "v89 owner pick 10649792198 4-engine airlifter, dark grey (wc7; replaces 17033079003), owner-only rollout"),
		TankerPlane = bodyRef(BODY_AIRLIFTER, "v89 owner pick 10649792198 4-engine airlifter, dark grey (wc7; replaces 17033079003), owner-only rollout"),
		-- Free naval family
		_FallbackNaval = { ModelAssetId = 0, Note = "Free Boat (Creator Store)" } :: AssetRef,
		PatrolBoat = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 16692908395 retired: a real-world WW2 PT-boat design (ASSET_LICENSES; CLAUDE.md no real-world copies)" } :: AssetRef,
		FastAttackCraft = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 16692908395 retired: a real-world WW2 PT-boat design (ASSET_LICENSES; CLAUDE.md no real-world copies)" } :: AssetRef,
		RiverBoat = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 16692908395 retired: a real-world WW2 PT-boat design (ASSET_LICENSES; CLAUDE.md no real-world copies)" } :: AssetRef,
		CoastCutter = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 16692908395 retired: a real-world WW2 PT-boat design (ASSET_LICENSES; CLAUDE.md no real-world copies)" } :: AssetRef,
		TorpedoBoat = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 16692908395 retired: a real-world WW2 PT-boat design (ASSET_LICENSES; CLAUDE.md no real-world copies)" } :: AssetRef,
		Gunboat = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 15838664806 retired: HELD in the owner's check (never promoted; ASSET_WIRING)" } :: AssetRef,
		MissileBoat = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 15838664806 retired: HELD in the owner's check (never promoted; ASSET_WIRING)" } :: AssetRef,
		MineLayer = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 15838664806 retired: HELD in the owner's check (never promoted; ASSET_WIRING)" } :: AssetRef,
		CoastalMonitor = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store body 15838664806 retired: HELD in the owner's check (never promoted; ASSET_WIRING)" } :: AssetRef,
		LandingCraft = bodyRef(BODY_BARGE, "v88 owner pick 12235335847 Barge (wc6), owner-only rollout"),
		AssaultLanding = bodyRef(BODY_BARGE, "v88 owner pick 12235335847 Barge (wc6), owner-only rollout"),
		HoverTransport = bodyRef(BODY_HOVER, "v88 owner pick 3626114334 Hover craft (wc6), owner-only rollout"),
		HospitalShip = bodyRef(BODY_SUPPORT_SHIP, "v88 owner pick 2625253037 Civillian tanker (wc6), owner-only rollout"),
		SupplyShip = bodyRef(BODY_SUPPORT_SHIP, "v88 owner pick 2625253037 Civillian tanker (wc6), owner-only rollout"),
		AmphibAssault = bodyRef(BODY_AMPHIB, "v87 owner pick 5545544418 amphibious assault ship (wc5), owner-only rollout"),
		Corvette = bodyRef(BODY_FRIGATE, "v87 owner pick 473576954 frigate hull (wc5), owner-only rollout"),
		Destroyer = bodyRef(BODY_DESTROYER, "v89 owner pick 6860896505 Stud Class hull, bow +Z (Yaw 180), naval grey (wc7), owner-only rollout"),
		Frigate = bodyRef(BODY_FRIGATE, "v87 owner pick 473576954 frigate hull (wc5), owner-only rollout"),
		CarrierEscort = bodyRef(BODY_FRIGATE, "v87 owner pick 473576954 frigate hull (wc5), owner-only rollout"),
		Battleship = bodyRef(BODY_BATTLESHIP, "v89 owner pick 12442299148 battleship, naval grey (wc7), owner-only rollout"),
		AircraftCarrier = { ModelAssetId = 0, Note = "Part-kit capital — REJECT 13195201090" } :: AssetRef,
		SubSurfaceRunner = bodyRef(BODY_SUB, "v87 owner pick 116924692473761 submarine (wc5), owner-only rollout"),
		AttackSub = bodyRef(BODY_SUB, "v87 owner pick 116924692473761 submarine (wc5), owner-only rollout"),
		-- Explicit aliases for depth-pass IDs (KitFamilyFallback also covers these)
		SupplyTruck = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store picks retired: 8546141386 (stencilled military unit markings) / 8455894899 (53 parts > 40)" } :: AssetRef,
		FuelTanker = { ModelAssetId = 0, Note = "claude-bud J9: FINISHED as the Part kit (olive tank body, VehicleService kitWheeledTruck fuel). Store picks rejected: 5318635087 (55 parts), 1578555399 (meshes by another user), 3284598659 (real-vehicle copy)" } :: AssetRef,
		EngineeringTruck = { ModelAssetId = 0, Note = "owner list: pick rejected (cannot be checked from the store) - family body / Part kit" } :: AssetRef,
		FlatbedHauler = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store picks retired: 8546141386 (stencilled military unit markings) / 8455894899 (53 parts > 40)" } :: AssetRef,
		AmmoCarrier = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store picks retired: 8546141386 (stencilled military unit markings) / 8455894899 (53 parts > 40)" } :: AssetRef,
		MissileTruck = { ModelAssetId = 0, Note = "owner pick missile truck (KlassicKanadian) not used: owner check 2026-09-25 (Open Cloud, v75), 219 parts > 40 - family body / Part kit" } :: AssetRef,
		AntiAirTruck = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store picks retired: 8546141386 (stencilled military unit markings) / 8455894899 (53 parts > 40)" } :: AssetRef,
		RadarTruck = { ModelAssetId = 0, Note = "owner pick RMAR truck radar (Armour_Fox) not used: owner check 2026-09-25 (Open Cloud, v75), 93 parts > 40 - family body / Part kit" } :: AssetRef,
		CargoVan = {
			ModelAssetId = 6433316269,
			ChildName = "Van (white)",
			SubModel = "Body",
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			StripDecals = true,
			-- vscale: Roblox size (R2: at 0.8 every rider's arms showed 0.33-0.45 through the doors and cargo panels, at 0.95
			-- 0.04-0.05 and the front row's feet 0.15 through the floor; at 1 nothing, like Roblox's own van). Seats: the
			-- body's own; head 2.0 under the roof. R2.1: the front row lands 0.84 further back (z -4.43), because
			-- BodySeatKitInset keeps every seat centre inside the kit's collidable box (the kit nose is at z -4.67).
			BodyScale = 1,
			BodySeats = {
				DriverSeat = Vector3.new(-2.247, 4.004, -5.267), -- VehicleSeat
				PassengerSeat1 = Vector3.new(2.255, 4.004, -5.267), -- SeatFR
				-- no body seat: the cargo bay behind the cab (the kit seats' heads were 0.5 through the roof), seat tops 1 lower
				-- than the cab's so the feet reach the cargo floor (2.0 under the cab seat line)
				PassengerSeat2 = Vector3.new(2.255, 3.05, -1.4),
				PassengerSeat3 = Vector3.new(-2.247, 3.05, 0.6),
				PassengerSeat4 = Vector3.new(2.255, 3.05, 0.6),
			},
			Note = "owner list: Roblox Van (white) Body (26 MeshParts, no decals), fitted to the kit; dress-only, the Part kit drives. 0 = Part kit",
		} :: AssetRef,
		TroopTransport = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store picks retired: 8546141386 (stencilled military unit markings) / 8455894899 (53 parts > 40)" } :: AssetRef,
		RecoveryTruck = { ModelAssetId = 0, Note = "claude-bud J9: Part kit. Store picks retired: 8546141386 (stencilled military unit markings) / 8455894899 (53 parts > 40)" } :: AssetRef,
		EscortTruck = {
			ModelAssetId = 6418225759,
			ChildName = "Pickup Truck (bronze)",
			SubModel = "Body",
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			StripDecals = true,
			OmitParts = { "light_tail_glass" },
			-- vscale: Roblox size (a seated avatar's head is 0.4 under the glass). Seats: the body's own.
			BodyScale = 1,
			BodySeats = {
				DriverSeat = Vector3.new(-1.708, 5.075, -2.092), -- VehicleSeat
				PassengerSeat1 = Vector3.new(1.708, 5.075, -2.091), -- SeatFR
				PassengerSeat2 = Vector3.new(-1.708, 5.075, 2.158), -- SeatRL
				PassengerSeat3 = Vector3.new(1.708, 5.075, 2.159), -- SeatRR
			},
			Note = "owner list: Roblox Pickup Truck (bronze) Body (41 MeshParts; the overlapping tail-light glass is omitted = 40), fitted to the kit; dress-only, the Part kit drives. 0 = Part kit",
		} :: AssetRef,
		InfantryCarrier = {
			ModelAssetId = 9076240315,
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			BodyScale = 0.55,
			BodySeats = {
				DriverSeat = Vector3.new(-2.5, 2.2, -4), -- no body seat: inside the hull, behind the cupola, under the roof (placed by eye)
				PassengerSeat1 = Vector3.new(2.5, 2.2, -4),
				PassengerSeat2 = Vector3.new(-2.5, 2.2, 2),
				PassengerSeat3 = Vector3.new(2.5, 2.2, 2),
				PassengerSeat4 = Vector3.new(-2.5, 2.2, 6),
			},
			StripDecals = true,
			Note = "owner pick: APC by CorzCringe (promoted 2026-09-27 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		CommandVehicle = {
			ModelAssetId = 9076240315,
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			BodyScale = 0.55,
			BodySeats = {
				DriverSeat = Vector3.new(-2.5, 2.2, -4), -- no body seat: inside the hull, behind the cupola, under the roof (placed by eye)
				PassengerSeat1 = Vector3.new(2.5, 2.2, -4),
				PassengerSeat2 = Vector3.new(-2.5, 2.2, 2),
				PassengerSeat3 = Vector3.new(2.5, 2.2, 2),
				PassengerSeat4 = Vector3.new(-2.5, 2.2, 6),
			},
			StripDecals = true,
			Note = "owner pick: APC by CorzCringe (promoted 2026-09-27 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		WheeledIFV = {
			ModelAssetId = 9076240315,
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			BodyScale = 0.55,
			BodySeats = {
				DriverSeat = Vector3.new(-2.5, 2.2, -4), -- no body seat: inside the hull, behind the cupola, under the roof (placed by eye)
				PassengerSeat1 = Vector3.new(2.5, 2.2, -4),
				PassengerSeat2 = Vector3.new(-2.5, 2.2, 2),
				PassengerSeat3 = Vector3.new(2.5, 2.2, 2),
				PassengerSeat4 = Vector3.new(-2.5, 2.2, 6),
			},
			StripDecals = true,
			Note = "owner pick: APC by CorzCringe (promoted 2026-09-27 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		AmphibiousAPC = {
			ModelAssetId = 9076240315,
			Fit = "Kit",
			Yaw = 0,
			HideKit = true,
			BodyScale = 0.55,
			BodySeats = {
				DriverSeat = Vector3.new(-2.5, 2.2, -4), -- no body seat: inside the hull, behind the cupola, under the roof (placed by eye)
				PassengerSeat1 = Vector3.new(2.5, 2.2, -4),
				PassengerSeat2 = Vector3.new(-2.5, 2.2, 2),
				PassengerSeat3 = Vector3.new(2.5, 2.2, 2),
				PassengerSeat4 = Vector3.new(-2.5, 2.2, 6),
			},
			StripDecals = true,
			Note = "owner pick: APC by CorzCringe (promoted 2026-09-27 by tools/wire-asset-ids.py)",
		} :: AssetRef,
		CombatIFV = { ModelAssetId = 0, Note = "owner pick Fiction IFV (spookstiy) not used: owner check 2026-09-25 (Open Cloud, v75), 321 parts > 40 - family body / Part kit" } :: AssetRef,
		AssaultIFV = { ModelAssetId = 0, Note = "owner pick Fiction IFV (spookstiy) not used: owner check 2026-09-25 (Open Cloud, v75), 321 parts > 40 - family body / Part kit" } :: AssetRef,
		BridgeLayer = { ModelAssetId = 0, NoFamilyFallback = true, Note = "owner list: no good match, keep the current build (Part kit; NoFamilyFallback: never a TrackedIFV family body)" } :: AssetRef,
		MineClearer = { ModelAssetId = 0, Note = "owner list: pick rejected (wrong item, provenance unverified) - family body / Part kit" } :: AssetRef,
		FlameCarrier = { ModelAssetId = 0, Note = "owner pick Fiction IFV (spookstiy) not used: owner check 2026-09-25 (Open Cloud, v75), 321 parts > 40 - family body / Part kit" } :: AssetRef,
		SPAAG = { ModelAssetId = 0, Note = "owner pick anti aircraft Tank (XCX1001) not used: owner check 2026-09-25 (Open Cloud, v75), 301 parts > 40 - family body / Part kit" } :: AssetRef,
		MobileSAM = { ModelAssetId = 0, Note = "owner pick anti aircraft Tank (XCX1001) not used: owner check 2026-09-25 (Open Cloud, v75), 301 parts > 40 - family body / Part kit" } :: AssetRef,
		MortarCarrier = { ModelAssetId = 0, Note = "owner list: [WEAK] a stand-alone mortar, no vehicle - Part kit" } :: AssetRef,
		MobileArtillery = { ModelAssetId = 0, Note = "owner list: [WEAK] crude towed gun declined, our Part kit reads better - Part kit" } :: AssetRef,
		RocketArtillery = { ModelAssetId = 0, Note = "owner pick missile truck (KlassicKanadian) not used: owner check 2026-09-25 (Open Cloud, v75), 219 parts > 40 - family body / Part kit" } :: AssetRef,
		HowitzerTruck = { ModelAssetId = 0, Note = "owner list: [WEAK] crude towed gun declined, our Part kit reads better - Part kit" } :: AssetRef,
		SiegeMortar = { ModelAssetId = 0, Note = "owner list: [WEAK] crude towed gun declined, our Part kit reads better - Part kit" } :: AssetRef,
		LightScoutTank = { ModelAssetId = 0, Note = "owner list: [WEAK] low-poly tank declined, our Part kit reads better - Part kit" } :: AssetRef,
		FortressTank = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
		RailgunCarrier = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) → TrackedArtillery family body, else Part kit" } :: AssetRef,
		DispatchCar = { ModelAssetId = 0, Note = "0 → WheeledLight family body (MilitaryJeep, fitted to the smaller kit)" } :: AssetRef,
		UtilityHeli = heliRef(0.45, Color3.fromRGB(150, 138, 100), false, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (khaki)"),
		MedevacHeli = heliRef(0.48, Color3.fromRGB(160, 164, 168), true, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (light grey)"),
		EscortHeli = heliRef(0.45, Color3.fromRGB(78, 98, 124), false, "v91 owner pick: attack heli 11240665977 for every heli key, own colour, owner-only rollout (slate blue)"),
		VTOLTransport = bodyRef(BODY_VTOL, "v88 owner pick 80886282228822 ev41 tilt-rotor (wc6), owner-only rollout"),
		HeavyBomber = bodyRef(BODY_BOMBER, "v87 owner pick 14669079591 delta-wing bomber (wc5), owner-only rollout"),
		-- v90 (owner 2026-09-28): the owner's jet 14589101870 replaces the v88 body on this key, pilot inside like the
		-- other jets (the FighterJet layout); Rollout "Body" keeps it owner-only like the v88 body it replaces.
		StealthStrike = {
			ModelAssetId = 14589101870,
			Rollout = "Body",
			Fit = "Kit",
			Yaw = 180,
			HideKit = true,
			BodyScale = 2.5,
			BodyLift = 1,
			BodySeats = {
				DriverSeat = Vector3.new(0.04, 0.72, 2.35), -- over the belly block's centre line, head inside the canopy (air2 fix2)
			},
			BodyAnchor = "DriverSeat", -- the body moves back along the kit so the cockpit is over the kit's pilot seat
			BodyMounts = {
				Nose = Vector3.new(0.07, 1.49, 8.74), -- gun: the fuselage's nose tip
				WingL = Vector3.new(5.48, 1.24, 0.18), -- missiles: the front of the wing-tip missile (mirrored right)
			},
			BodyHitBoxes = JET_HIT_BOXES,
			BodyGear = JET_GEAR,
			TailGuard = true,
			ChaseCamera = true,
			BodyColor = Color3.fromRGB(46, 48, 54), -- v90: charcoal (one colour per jet)
			BodyColorParts = JET_PAINT_PARTS,
			StripDecals = true,
			Note = "v90 owner pick: Basic Fighter jet by Alecose1 14589101870 (replaces the v88 body), owner-only rollout",
		} :: AssetRef,
		-- Depth-pass capital / bomber IDs previously missing from catalog map
		Cruiser = bodyRef(BODY_CRUISER, "v89 owner pick 6860896505 Stud Class hull at 0.22, bow +Z (Yaw 180), naval grey (wc7), owner-only rollout"),
		MissileCruiser = bodyRef(BODY_MISSILE_CRUISER, "v89 owner pick 104820847233642 missile destroyer at 18, naval grey (wc7), owner-only rollout"),
		FleetCarrier = bodyRef(BODY_CARRIER, "v87 owner pick 7941124517 aircraft carrier (wc5), owner-only rollout"),
		StrategicBomber = bodyRef(BODY_BOMBER, "v87 owner pick 14669079591 delta-wing bomber (wc5), owner-only rollout"),
	} :: { [string]: AssetRef },

	Characters = {
		-- R-RIG: owner rule 9 + decision #8 default: the Roblox "Soldier" 187790284 (creator Roblox) for every soldier kind
		Soldier = { ModelAssetId = 187790284, Rig = "R6", Headwear = "Beret", Note = "Roblox Soldier (rule 9)" } :: AssetRef,
		Squad = { ModelAssetId = SOLDIER_ASSET_ID, FallbackAssetId = SOLDIER_FALLBACK_ID, Rig = "R6", Headwear = "Beret", Note = "v119 Army Soldier 7703684779: friendly squad units (the army escorts copy it on each phone)" } :: AssetRef,
		Infantry = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet", Note = "hostile infantry" } :: AssetRef,
		Worker = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet", Note = "#9 default: Roblox soldier body" } :: AssetRef,
		WorkerFallback = { ModelAssetId = 0, Note = "R-RIG: unused (rig kinds keep the Part kit on a failed load)" } :: AssetRef,
		HeavyInfantry = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet" } :: AssetRef,
		Guard = { ModelAssetId = SOLDIER_ASSET_ID, FallbackAssetId = SOLDIER_FALLBACK_ID, Rig = "R6", Headwear = "Beret", Note = "v119 Army Soldier 7703684779" } :: AssetRef,
		BankGuard = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet" } :: AssetRef,
		OilRigGuard = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet" } :: AssetRef,
		FortGuard = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet" } :: AssetRef,
		CheckpointGuard = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet", Note = "claude-bud JOB 37: the bank guards' rig" } :: AssetRef,
		CampCommander = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet" } :: AssetRef,
		GateGuard = { ModelAssetId = SOLDIER_ASSET_ID, FallbackAssetId = SOLDIER_FALLBACK_ID, Rig = "R6", Headwear = "Beret", Note = "v119 Army Soldier 7703684779: base gate / tower guards" } :: AssetRef,
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
		VehicleDepot = { ModelAssetId = 12208876851, Note = "owner pick Military garage (TamasdztYT) not used: owner check 2026-09-25 (Open Cloud, v75), 113 parts > 40 - the current id stays (inert while PreferMesh is off)" } :: AssetRef,
		WeaponsFacility = { ModelAssetId = 4120970784, PendingAssetId = 11850705638, Note = "owner pick Armory (DISPLAYMODELS): pending, P2 (owner yes/no, inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Warehouse = { ModelAssetId = 15942568272, PendingAssetId = 8076230849, Note = "owner pick Warehouse (sydneycrosby_875): pending, P1i (inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Hangar = { ModelAssetId = 0, Note = "owner rule 5: heavy hangar model cleared (the Airfield composite builds its Part shed); owner pick plane hangar (Hyperalis) not used: owner check 2026-09-25 (Open Cloud, v75), 871 parts > 40 - Part kit" } :: AssetRef,
		HangarAlt = { ModelAssetId = 12208876851, Note = "Hangar insert fallback" } :: AssetRef,
		BaseGate = { ModelAssetId = 85138026, Note = "Gate arch prop ONLY — DisplayName Base Gate" } :: AssetRef,
		ResearchLab = { ModelAssetId = 17725725, Note = "Research lab" } :: AssetRef,
		SpecialForcesFacility = { ModelAssetId = 0, PendingAssetId = 10112923897, Note = "owner rule 5: heavy barracks model cleared; owner pick Military defense outpost (Roseaity): pending, P1i ([WEAK], inert while PreferMesh is off)" } :: AssetRef,
		Watchtowers = { ModelAssetId = 108525417345747, Note = "owner pick guard tower (Morniratu) not used: owner check 2026-09-25 (Open Cloud, v75), 135 parts > 40 - the current id stays (inert while PreferMesh is off)" } :: AssetRef,
		Radar = { ModelAssetId = 9559610195, PendingAssetId = 856258654, Note = "owner pick Radar Station (VexHavoc): pending, P1i (inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		-- W1 CFG drop (real-world system). NOTE: ResolveBuildingAssetId then reads StructureVisualConfig.Palettes
		-- .MissileDefense.MeshAssetId — that file must be 0 too for a Part kit (see docs/ASSET_LICENSES.md).
		MissileDefense = { ModelAssetId = 0, PendingAssetId = 3461514733, Note = "owner pick Missile Launcher (cwd30): pending, P1i (inert while PreferMesh is off); W1 CFG drop (real-world system): Part kit until promoted" } :: AssetRef,
		DefensiveWalls = { ModelAssetId = 0, PendingAssetId = 6980242709, Note = "owner pick Military Wall (SMehmetaga): pending, P2; passed the owner check 2026-09-25 (20 parts) but held (tools/wire-asset-ids.py HOLD): its only caller, StructureKitBuilder at walls L3+, would leave it buried in the wall, because weldScaledBuilding re-pivots the clone to the wall centre (weldCloneToPrimary without keepPlace) after scaling a Z-long model into the 24x8x3 X-long footprint; needs that VisualAssetService fit fix, then the second check. L3+ walls read this ref (DefensiveWallsL3 is 0)" } :: AssetRef,
		DefensiveWallsL3 = { ModelAssetId = 0, Note = "owner pick T WALL (steveaut) not used: owner check 2026-09-25 (Open Cloud, v75), 46 parts > 40 - L3+ walls read DefensiveWalls next, else the Part kit" } :: AssetRef,
		PowerStation = { ModelAssetId = 14000967030, PendingAssetId = 6869290892, Note = "owner pick Power Station (bossmanjesus101): pending, P1i (inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Bunker = { ModelAssetId = 0, Note = "W1 CFG drop (off the Creator Store) — Part kit" } :: AssetRef,
		Helipad = { ModelAssetId = 14313845338, PendingAssetId = 45369635, Note = "owner pick Helipad (sleitnick): pending, P1i (inert while PreferMesh is off); the current id stays until promoted" } :: AssetRef,
		Airfield = { ModelAssetId = 0, Note = "COMPOSITE runway + Buildings.Hangar (0 = Part shed); REJECT 12370174722" } :: AssetRef,
		Dock = { ModelAssetId = 13183571527, Note = "owner pick: boat dock by tihi2 (promoted 2026-09-27 by tools/wire-asset-ids.py; recorded only: not loaded while PreferMesh is off, fit not reviewed)" } :: AssetRef,
		-- Anti-heli Base Ceiling: Part-kit only (no invented / paid roof IDs)
		BaseCeiling = { ModelAssetId = 0, Note = "Part-kit anti-heli roof — no free dedicated Model" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- JeepFallback 59524622 DELETED (Design P0 REJECT). Part kit physics if mesh fails.

	-- Gate defense (Design Bot GATE_DEFENSE_WIRE 2026-09-20)
	GateDefense = {
		Guard = { ModelAssetId = 16134469614, Note = "Rigged Soldier — gate patrol" } :: AssetRef,
		-- Yaw 90: the store file's barrel points along +X (headless parse: the barrel cylinders ahead of the receiver, the single
		-- tripod leg reaching forward, the rear grips behind, the ammo box on the left); GateDefenseService turns the template
		-- once so it aims -Z, stands it on the ground and welds it to its aim part (only that part is anchored)
		AutoGun = { ModelAssetId = 114570602, Yaw = 90, Note = "owner pick: Tripod Mounted Machine Gun by GuestCapone (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		-- claude-bud JOB 67 (1): the turret TIERS from Shaun's paid Minigun Turret Pack (Lvl 1-10, 109072907337393; its
		-- one script is stripped by the loader). Pack levels 1 / 3 / 5 / 8 / 10 = T1..T5 (ChildName = the pack's model
		-- name for that level, read from the WE_CHECK2 probe). PendingAssetId until tools/wire-asset-ids.py promotes it
		-- (WE_CHECK2: <= 40 parts per piece, <= 20k tris); a tier with ModelAssetId 0 = the AutoGun above (today).
		AutoGunT1 = { ModelAssetId = 0, PendingAssetId = 109072907337393, Yaw = 0, ChildName = nil, Note = "Minigun Turret Pack Lvl 1 (paid, shaunie6) - JOB 67 T1" } :: AssetRef,
		AutoGunT2 = { ModelAssetId = 0, PendingAssetId = 109072907337393, Yaw = 0, ChildName = nil, Note = "Minigun Turret Pack Lvl 3 - JOB 67 T2" } :: AssetRef,
		AutoGunT3 = { ModelAssetId = 0, PendingAssetId = 109072907337393, Yaw = 0, ChildName = nil, Note = "Minigun Turret Pack Lvl 5 - JOB 67 T3" } :: AssetRef,
		AutoGunT4 = { ModelAssetId = 0, PendingAssetId = 109072907337393, Yaw = 0, ChildName = nil, Note = "Minigun Turret Pack Lvl 8 - JOB 67 T4" } :: AssetRef,
		AutoGunT5 = { ModelAssetId = 0, PendingAssetId = 109072907337393, Yaw = 0, ChildName = nil, Note = "Minigun Turret Pack Lvl 10 - JOB 67 T5" } :: AssetRef,
		-- L2 elevated ONLY (not door flanks):
		AutoGunElevated = { ModelAssetId = 0, Note = "W1 CFG drop (uploader not the author) — unused key" } :: AssetRef,
		AutoGunElevatedAlt = { ModelAssetId = 10354803684, Note = "Military turret — L2/corner only" } :: AssetRef,
		SandbagNest = { ModelAssetId = 0, Note = "Circular sandbag ring under HMG" } :: AssetRef,
		Sandbags = { ModelAssetId = 0, Note = "v147: was 3525056989 (not authorized: live LoadAsset 2026-09-30; never loaded, a wasted LoadAsset per server) - sandbag scatter at posts" } :: AssetRef,
	},

	-- Owner asset list hooks (2026-09-25): war-business line dress. BusinessService.SyncBusiness defers
	-- VisualAssetService.TryAttachBusinessVisual(model, id, level) after its kit loop. Model part i takes over the built
	-- kit part of ReplacesRoles[i] (named Kit_<Role>, fitted into that part's own box), so a business never goes over
	-- BusinessConfig.PartsPerBusinessL5 and the client's Kit_Belt crates keep working (a Belt part is always stretched
	-- into the kit belt's box, block parts only). Refused (one warn, Part kit stays): more model parts than roles, roles
	-- with different kit MinLevels, a colliding role. Anchored, non-colliding; a re-sync or level-up that finds every
	-- built role dressed does nothing, and a role rebuilt after a level-down is dressed again.
	Businesses = {
		AmmoWorks = { ModelAssetId = 41324890, Fit = "Box", ReplacesRoles = { "Belt" }, Note = "owner list: Roblox Conveyor Belt (1 part + its stripe decal; script stripped) as the belt" } :: AssetRef,
		ArmsCrateLine = { ModelAssetId = 41324890, Fit = "Box", ReplacesRoles = { "Belt" }, Note = "owner list: Roblox Conveyor Belt as the belt (same model as Ammo Works: one load)" } :: AssetRef,
		ArmorPlatePress = { ModelAssetId = 0, PendingAssetId = 4362642898, Note = "0 = Part-kit press; owner pick Metal Factory (Press) (Ghosttony503): pending, P4 (Studio check: WE_CHECK, then OmitParts for its translucent bounds box and ReplacesRoles so it fits PartsPerBusinessL5)" } :: AssetRef,
		RocketAssembly = { ModelAssetId = 31603741, OmitParts = { "Particles" }, ReplacesRoles = { "Signature" }, Note = "owner list: Roblox Rocket as the rocket body (its empty effects part dropped; Fire + Smoke removed, StripEffectsAssetIds)" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- bizlook (2026-09-27, owner: "The dropper should look like a legit high-end business"): Roblox-made building pieces
	-- every war-business line wears (VisualAssetService.TryAttachBusinessVisual, after the line's own dress). All come
	-- from Roblox's Synty City pack 6933556508 (creator Roblox, User 1; already loaded for DesertKit.CarWreck, so 0 new
	-- load attempts), keep the pack's atlas texture (no text on these pieces: UV-checked) and replace a non-colliding kit
	-- role one for one, so PartsPerBusinessL5 and the per-level counts hold. A piece with Into fills that kit role's box
	-- (Fit = "Stretch": turned by Yaw, then stretched to the box; the front keeps its proportions, the depth is squashed)
	-- and hides the HideRoles colliders (their collision stays); FromLevel / ToLevel pick the office piece by level, and
	-- BusinessService refits a stretched piece when its box grows. 0 = the Part kit (the fallback look).
	BusinessPieces = {
		-- L2+: the loading unit behind the bin: a roller-shutter unit (Shop_06, 264 tris) in the 8.5 x 6 x 5.5 Dock box
		DockFront = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Shop_06", ReplacesRoles = { "DockFront" }, Into = "Dock", Fit = "Stretch", Yaw = 180, HideRoles = { "Dock" }, Note = "Synty City: roller-shutter unit as the loading bay" } :: AssetRef,
		-- L3-4: the head office behind the belt start: a two-storey stone office (Station_03, 1,984 tris) in the Hall box
		HallFront = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Station_03", ReplacesRoles = { "HallFront" }, Into = "Hall", Fit = "Stretch", Yaw = 180, HideRoles = { "Hall" }, ToLevel = 4, Note = "Synty City: two-storey office (L3-4)" } :: AssetRef,
		-- L5: the head office grows into a three-storey glass-front block (Station_02, 1,527 tris) in the taller Hall box
		HallFrontL5 = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Station_02", ReplacesRoles = { "HallFront" }, Into = "Hall", Fit = "Stretch", Yaw = 180, HideRoles = { "Hall" }, FromLevel = 5, Note = "Synty City: three-storey glass-front office (L5)" } :: AssetRef,
		-- L4+: a corrugated lean-to canopy with tie rods over the belt (Shop_Cover_03, 122 tris), fitted uniformly
		Canopy = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Shop_Cover_03", ReplacesRoles = { "Canopy" }, Note = "Synty City: corrugated canopy over the belt" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- Owner asset list hooks (2026-09-25): turret dress. VehicleService calls VisualAssetService.TryAttachVehicleWeaponVisual
	-- only for a vehicle on the ref's allow-list (KitFamilies and / or Vehicles) whose kit has the Mount part. Dress only:
	-- massless, non-colliding, welded to the mount (never anchored); HideParts turns the kit gun invisible once the dress is
	-- on (its parts, collisions and combat stay). 0 = no load, no change.
	VehicleWeapons = {
		VehicleMG = { ModelAssetId = 0, PendingAssetId = 5589684833, Mount = "GunMount", FitScale = 3, Vehicles = { "ArmedJeep" }, HideParts = { "Barrel" }, Note = "0 = Part-kit gun; owner pick Mounted Machine Gun (ifyouaremethaniamyou): pending, P4 (Studio check); Armed 4x4 only" } :: AssetRef,
		VehicleCannon = { ModelAssetId = 0, PendingAssetId = 3322196012, Mount = "Turret", FitScale = 1.6, KitFamilies = { "TrackedMBT" }, HideParts = { "Turret", "Barrel", "Mantlet" }, Note = "0 = Part-kit turret; owner pick Tank Turret (Nierse217): pending, P4 (Studio check; the store page says it may be asymmetrical); battle tanks only" } :: AssetRef,
		-- aircraft weapons (AircraftWeaponConfig Weapons[].Hook): no dress yet (0 = no load). AirWeaponService uses each
		-- ref's Mount kit part as the muzzle / bomb bay, and its allow-list must hold every aircraft that carries it.
		AirNoseGun = { ModelAssetId = 0, Mount = "Cockpit", FitScale = 0.5, KitFamilies = { "HeliAttack" }, Note = "0 = no dress; attack / gunship helicopter chin gun (muzzle under the cockpit)" } :: AssetRef,
		AirRocketPods = { ModelAssetId = 0, Mount = "StubWingL", FitScale = 0.6, KitFamilies = { "HeliAttack" }, Note = "0 = no dress; helicopter rocket pods (left stub wing, mirrored right)" } :: AssetRef,
		AirJetCannon = { ModelAssetId = 0, Mount = "Nose", FitScale = 0.5, Vehicles = { "FighterJet", "InterceptorJet", "LightFighter" }, Note = "0 = no dress; fighter nose cannon (trainer / recon jets stay unarmed)" } :: AssetRef,
		AirMissileRails = { ModelAssetId = 0, Mount = "WingL", FitScale = 0.4, Vehicles = { "FighterJet", "InterceptorJet", "LightFighter" }, Note = "0 = no dress; fighter missile rails (left wing, mirrored right)" } :: AssetRef,
		AirStrikeBombs = { ModelAssetId = 0, Mount = "Chassis", FitScale = 0.4, KitFamilies = { "JetStrike" }, Note = "0 = no dress; strike jet bombs under the fuselage" } :: AssetRef,
		AirBombBay = { ModelAssetId = 0, Mount = "Bay", FitScale = 1, KitFamilies = { "JetBomber" }, Note = "0 = no dress; bomber bomb bay" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- ATM / collect presentation (StripScripts on insert) — Design Bot prefer free IDs
	-- W1 CFG drop (paid): 0 is skipped, so TryAttachCollectorVisual tries the fallback, then the alts, then the Part kit
	MoneyCollector = { ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 18220523228 (75 parts > the 40-part cap (live); the Part kit look stays) - owner pick: ATM by 0GColt (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
	MoneyCollectorFallback = { ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 175462478 (not authorized (live LoadAsset); the Part kit look stays) - ATM fallback classic" } :: AssetRef,
	MoneyCollectorAlts = {
		{ ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 90362241548850 (not authorized (live LoadAsset); the Part kit look stays) - ATM alt A" } :: AssetRef,
		{ ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 76846072091295 (not authorized (live LoadAsset); the Part kit look stays) - ATM alt B" } :: AssetRef,
		{ ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 35409899 (not authorized (live LoadAsset); the Part kit look stays) - ATM alt C" } :: AssetRef,
	},
	MoneyBagFX = { ModelAssetId = 38451313, Note = "Collect cash burst VFX (StripScripts)" } :: AssetRef,
	VfxSparkles = { ModelAssetId = 4221608224, Note = "Collect/upgrade sparkles VFX" } :: AssetRef,
	CashCrate = { ModelAssetId = 16803204916, Note = "Cash crate alt overlay" } :: AssetRef,
	UpgradeFlag = { ModelAssetId = 0, Note = "v147: was 1679839739 (not authorized: live LoadAsset 2026-09-30; the Part kit look stays) - L5 structure flag pop" } :: AssetRef,
	FloodlightTower = { ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 107381977457431 (not authorized (live LoadAsset); the Part kit look stays) - Floodlight tower PROP (not vehicle)" } :: AssetRef,
	-- VehicleDepot showroom catalog (Part-kit podium remains fallback)
	ShowroomPodium = { ModelAssetId = 5267267960, Note = "Showroom podium mesh" } :: AssetRef,
	ShowroomPedestal = { ModelAssetId = 130578088310000, Note = "Showroom pedestal" } :: AssetRef,
	ShowroomRotator = { ModelAssetId = 5389482912, Note = "Showroom rotator / turntable" } :: AssetRef,
	-- Tutorial guidance
	TutorialArrow = { ModelAssetId = 632958370, Note = "owner pick: Arrow by isaacbeyo (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
	TutorialArrowAlt = { ModelAssetId = 6333395014, Note = "Tutorial arrow alt" } :: AssetRef,
	TutorialBeam = { ModelAssetId = 88687072714005, Note = "Tutorial neon beam mesh/texture" } :: AssetRef,

	-- KEY LABELS fixed (IDs unchanged); legacy aliases kept for callers
	WarzoneProps = {
		Sandbag = { ModelAssetId = 15271872710, Note = "owner pick: SandBag Wall by Herbie778811 (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		SandbagBarrier = { ModelAssetId = 12651656400, Note = "Warzone SandbagBarrier" } :: AssetRef,
		SandbagWall = { ModelAssetId = 25733125, Note = "Warzone SandbagWall" } :: AssetRef,
		ConcreteBarrier = { ModelAssetId = 2766525411, Note = "owner pick: road barrier by SiameseMouse (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		Crate = { ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 53591587 (not authorized (live LoadAsset); the Part kit look stays) - Warzone Crate" } :: AssetRef,
		MilitaryCrate = { ModelAssetId = 2930926216, Note = "owner pick: Military Crates by XIArchangel (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		AmmoBox = { ModelAssetId = 16382915010, Note = "Warzone AmmoBox" } :: AssetRef,
		OilBarrel = { ModelAssetId = 23153991, Note = "owner list: Roblox Smoking Barrel, whole model (4 parts), smoke removed (StripEffectsAssetIds)" } :: AssetRef,
		BarbedWire = { ModelAssetId = 1291725699, Note = "Warzone BarbedWire" } :: AssetRef,
		Tent = { ModelAssetId = 182529039, Note = "owner pick: Military Canvas Tent by Quenty (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		RadioAntenna = { ModelAssetId = 19277831, PendingAssetId = 1439808070, Note = "owner pick Antenna (Sereinmachy): pending, P1i (inert while PreferMesh is off); StructureDress only" } :: AssetRef,
		Floodlight = { ModelAssetId = 0, Note = "v147: was 116763933 (not authorized: live LoadAsset in place 97112936860418, 2026-09-30; the Part kit look stays) - Warzone Floodlight" } :: AssetRef,
		FloodlightTower = { ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 107381977457431 (not authorized (live LoadAsset); the Part kit look stays) - Floodlight tower prefer" } :: AssetRef,
		Flag = { ModelAssetId = 0, Note = "v147: was 1679839739 (not authorized: live LoadAsset 2026-09-30; the Part kit flag stays) - L5 upgrade flag" } :: AssetRef,
		Lantern = { ModelAssetId = 0, Note = "W1 CFG drop (extracted from another game) — Part kit host" } :: AssetRef,
		TentAlt = { ModelAssetId = 3133150032, Note = "Tent alt if primary Tent fails" } :: AssetRef,
		RadioAntennaAlt = { ModelAssetId = 42209845, Note = "HQ roof antenna alt" } :: AssetRef,
		FloodlightAlt = { ModelAssetId = 4893998573, Note = "Depot bay floodlight" } :: AssetRef,
		FuelCans = { ModelAssetId = 1160141839, PendingAssetId = 112426091, Note = "owner pick Gas Can (Maximum_ADHD): pending, P1i (inert while PreferMesh is off); StructureDress only" } :: AssetRef,
		FlagPole = { ModelAssetId = 0, PendingAssetId = 172755983, Note = "owner pick Flagpole (Quenty): pending, P1i (inert while PreferMesh is off); StructureDress only" } :: AssetRef,
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
		Sandbags = { ModelAssetId = 15271872710, Note = "owner pick: SandBag Wall by Herbie778811 (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		Barrier = { ModelAssetId = 25733125, Note = "alias → SandbagWall" } :: AssetRef,
		Cone = { ModelAssetId = 2766525411, Note = "owner pick: road barrier by SiameseMouse (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		Drum = { ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 53591587 (not authorized (live LoadAsset); the Part kit look stays) - alias → Crate" } :: AssetRef,
		Pallet = { ModelAssetId = 2930926216, Note = "owner pick: Military Crates by XIArchangel (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		CamoNet = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		CamoNetAlt = { ModelAssetId = 0, Note = "W3 LOOK drop (third-party world-dressing host; no caller) — Part kit" } :: AssetRef,
		Fence = { ModelAssetId = 25623924, Note = "legacy alias of the old OilBarrel id (no caller; WarzoneProps.OilBarrel is the Roblox barrel now)" } :: AssetRef,
		Radio = { ModelAssetId = 19277831, PendingAssetId = 1439808070, Note = "owner pick Antenna (Sereinmachy): pending, P1i (inert while PreferMesh is off); alias of RadioAntenna" } :: AssetRef,
		Lamp = { ModelAssetId = 0, Note = "v147: was 116763933 (not authorized) - alias → Floodlight" } :: AssetRef,
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
		OilPumpjack = { ModelAssetId = 0, Note = "claude-bud JOB 24 §4c: was 15192621369 (68 parts > the 40-part cap (live); the Part kit look stays) - owner pick: Oil Rig / Pumpjack by sadfiacs (promoted 2026-09-25 by tools/wire-asset-ids.py)" } :: AssetRef,
		OilPumpjackAlt = { ModelAssetId = 0, Note = "0 since 2026-09-25: 15192621369 (PlotOilPump) is the primary now (tools/wire-asset-ids.py)" } :: AssetRef,
		RustyPipes = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit" } :: AssetRef,
		OilBarrel = { ModelAssetId = 25623924, Note = "Oil barrel ring" } :: AssetRef,
		FuelCans = { ModelAssetId = 1160141839, Note = "Fuel cans cluster" } :: AssetRef,
		-- Owner asset list hook (2026-09-25): ManualDropperService dresses each dropper plate (TryAttachPropVisual)
		ManualDropper = { ModelAssetId = 0, PendingAssetId = 14408455045, Fit = "Ground", FitLong = 4, KeepHost = true, Note = "0 = Part-kit plate; owner pick Tycoon Dropper (tinghang77): pending, P4 (Studio check; neon trim counts in the neon budget); at most 4 studs, the tap plate stays as it is" } :: AssetRef,
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
		-- Owner asset list hook (2026-09-25): MapSetup dresses each Home Outpost ring (TryAttachPropVisual, deferred)
		HomeOutpost = { ModelAssetId = 80566030, Fit = "Ground", KeepHost = true, OmitParts = { "Height", "Highlight" }, Note = "owner list: Roblox Capture Points (2 scripts stripped) as the outpost pad: 4 parts, its translucent Height beam and invisible Highlight dropped" } :: AssetRef,
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
		--[[ Crossroads Town buildings (owner feedback 2026-09-27: "need to be actual Roblox buildings"). WorldKits
			TownHouse stacks these pieces per WorldConfig.Kits.TownHouse.Styles, at scale 1. Same Roblox-made pack as
			CarWreck (6933556508, creator Roblox, User 1): 0 new load attempts. The texture atlas STAYS (no ClearTexture:
			it draws the windows, brick and stone); these pieces sample none of the atlas's text regions (UV check,
			ownervis assets.md §2.3). Every piece is one MeshPart with no glass child (the loader drops children). ]]
		TownShop = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Shop_06", Note = "Synty City: one-storey shop, rolled shutter (264 tris)" } :: AssetRef,
		TownAptDoorA = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Apartment_Door_01", Note = "Synty City: brick ground floor with a stoop door (629 tris)" } :: AssetRef,
		TownAptDoorB = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Apartment_Door_02", Note = "Synty City: brick ground floor, plain door (616 tris)" } :: AssetRef,
		TownAptFloorA = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Apartment_02", Note = "Synty City: brick upper floor, arched windows (1,032 tris)" } :: AssetRef,
		TownAptFloorB = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Apartment_03", Note = "Synty City: brick upper floor, bay window (500 tris)" } :: AssetRef,
		TownAptStack = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Apartment_Stack_01", Note = "Synty City: three brick floors in one piece (1,360 tris)" } :: AssetRef,
		TownAptRoofA = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Apartment_Roof_01", Note = "Synty City: flat roof (140 tris)" } :: AssetRef,
		TownAptRoofB = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_Apartment_Roof_02", Note = "Synty City: cornice roof (164 tris)" } :: AssetRef,
		TownOfficeBase = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_OfficeOld_Small_Base_01", Note = "Synty City: sandstone hall, 2 storeys (4,756 tris)" } :: AssetRef,
		TownOfficeTop = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Buildings_SM_Bld_OfficeOld_Small_Roof_01", Note = "Synty City: sandstone hall top storey (1,882 tris)" } :: AssetRef,
		-- Training Yard (owner feedback 2026-09-27; TrainingYardBuilder, TrainingYardConfig): pieces of the live Dungeon
		-- pack (0 new load attempts), fitted by the builder, the pack texture KEPT (one shared atlas: planks, metal bands,
		-- rungs; no text or emblem on these pieces, ownervis/assets.md §3.4). ClearTexture = true + Color turns any of them
		-- into a flat colour (no atlas on phones). The hurdles reuse the live Log key above.
		YardCrate = { ModelAssetId = 6933790012, ChildName = "Meshes/PolygonDungeon_Props_SM_Prop_Crate_Wood_04", Note = "Synty Dungeon: wooden supply crate (598 tris), textured; training-yard crate stack" } :: AssetRef,
		YardAmmoCrate = { ModelAssetId = 6933790012, ChildName = "Meshes/PolygonDungeon_Props_SM_Prop_Crate_Metal_01", Note = "Synty Dungeon: metal-bound crate (662 tris), textured; training-yard ammo crate" } :: AssetRef,
		YardRack = { ModelAssetId = 6933790012, ChildName = "Meshes/PolygonDungeon_Props_SM_Prop_WeaponRack_01", Note = "Synty Dungeon: empty wooden rack (213 tris, no weapons modelled), textured; training-yard rifle rack (mesh only)" } :: AssetRef,
		YardLadder = { ModelAssetId = 6933790012, ChildName = "Meshes/PolygonDungeon_Props_SM_Prop_Ladder_01", Note = "Synty Dungeon: ladder (268 tris), textured; leans on the training-yard jump wall (mesh only)" } :: AssetRef,
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

-- claude-bud JOB 67: the turret tier (1..5) for a Turret Guns level 0..10 (pure; Job67.TurretTierAt)
function VisualAssetConfig.TurretTierFor(level: number): number
	local J: any = (VisualAssetConfig :: any).Job67
	local t = 1
	for i, l in ipairs(if J then J.TurretTierAt else {}) do
		if (tonumber(level) or 0) >= l then
			t = i + 1
		end
	end
	return t
end

return VisualAssetConfig
