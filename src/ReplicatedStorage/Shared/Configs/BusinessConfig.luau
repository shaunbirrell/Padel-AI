--!strict
--[[
	v72 war businesses (owner: "businesses which pay money to you, all war related. Weapons dropper etc").

	A business is a production line on your plot, bought and upgraded ONLY at its own console (console-only buying,
	same path as every structure: BaseService.PurchaseUpgrade). While Enabled, BaseConfig merges these defs into
	BaseConfig.Structures (Kind = "Business") and appends them to StructureOrder, so saving (profile.BaseUpgrades),
	requirements, the Base panel row, the BUY button, rebirth reset and the tutorial hooks need no new money code.

	Money: a business adds IncomePerTick[level] (the TOTAL base $ per passive tick at that level, before multipliers)
	to the passive tick through Shared/Util/TycoonMath.BasePassivePerTick. It is paid into the ATM (PendingCash) on
	the existing 5 s tick with reason "passive", so the same multipliers apply and ATM raids take 10% as usual.
	There is NO new money path, remote or client-sent amount.

	Look: the server builds the static line (<= PartsPerBusinessL5 parts, 0 lights, 0 SurfaceGuis, 0 Neon) and its
	console. The moving crates and the "+$N" pops are CLIENT-ONLY and owner-only (Visual / Crates below).
	Sites live in BaseLayoutConfig.Structures (one line each, plot-local, same format as the kiosks).
	No real-world brand, weapon or country names.

	Enabled = false until integration (the lead flips it together with TycoonGuideConfig.Enabled). While false:
	nothing is merged into BaseConfig, TycoonMath pays nothing for a saved business level, tutorial step 6 stays
	the Barracks buy, and the game behaves exactly as before v72.

	Droppers v1a (lines and looks; spec_droppers.md §3, §10.1). Every key below is cosmetic: the server never reads
	ProductsPerTick, Machine, Products, Machines or Visual, and no price, income or save field changes.
	  ProductsPerTick  per def: k products land in the bin per 5 s income beat at level 1..5 (the client locks the
	                   line to WE_PassiveTick; CrateEverySec stays the fallback while ProductsPerTick is nil).
	  Machine          per def: its Machines key (one pooled local part per own line, one reused Tween).
	  LookTiers        server look tiers (BusinessService, property-only, 0 new parts) on LookTierRoles; a part that
	                   carries WE_CatalogAssetId (a hooks dress) is never written. Tier names key Products and
	                   MachineColors. BusinessConfig.LookTierFor(level) is the one tier rule (server and client).
	  Products         per business and tier: raw look at spawn, done look after the machine hit (Color + Material).
	  Visual           client lines, heap, clock, FX and the flags (BeltFx OFF in v1a; Ghost / Ambient are v1.1).
	No stencils, insignia, flags, brands or real weapon names on any product.

	bizlook (owner 2026-09-27: "The dropper should look like a legit high-end business"). The same part count per level
	(L0 4 / L1 10 / L2 12 / L3 14 / L4 15 / L5 16, console included), rebuilt as a small branded company site: a brick
	workshop with a brand-coloured cornice and a product sign on its roof (L1), a roller-shutter loading unit behind the
	bin (L2), a two-storey head office behind the belt start (L3), a corrugated canopy over the belt and a taller office
	(L4), a three-storey glass-front office with a brand band round its top (L5). The unit, the office and the canopy
	are Roblox-made building pieces (VisualAssetConfig.BusinessPieces) that take the place of Part-kit roles one for
	one; the Part kit (Dock / DockFront / Hall / HallFront / Canopy) is their fallback look. Belt / BeltFrame / Bin and
	the Housing's +X wall keep their v1a boxes, so the machines, products, heap and "+$N" pop run exactly as in v1a.
	Brand = the business Accent colour; no text, logo or insignia anywhere (no SurfaceGui).
]]

export type Requirement = { StructureId: string, Level: number }

export type BusinessDef = {
	Id: string,
	DisplayName: string,
	ShortName: string, -- <= 10 characters: console tag / BUY button / guide chip on an 800x360 phone
	Description: string, -- Base panel row (<= 42 characters)
	Costs: { number }, -- cash for level 1..5 (index = target level)
	IncomePerTick: { number }, -- TOTAL base $ per passive tick at level 1..5 (not a per-level delta)
	Requires: { Requirement }?,
	Palette: { Body: Color3, Roof: Color3, Accent: Color3 },
	Signature: string, -- per-business signature part (Signatures)
	Product: string, -- crate look (Crates)
	CrateEverySec: { number }, -- client visual cadence at level 1..5 (cosmetic only, never money)
	ProductsPerTick: { number }?, -- droppers v1a: products landing per 5 s income beat at level 1..5 (cosmetic)
	Machine: string?, -- droppers v1a: BusinessConfig.Machines key of this line's machine (cosmetic)
}

-- droppers v1a: server look tier (BusinessService) on the LookTierRoles parts; tier = the last one with FromLevel <= level
export type LookTier = {
	FromLevel: number,
	Name: string, -- "Field" | "Works" | "Arsenal": also the key of Products[id] and MachineColors
	Material: Enum.Material, -- every tier role
	HousingMaterial: Enum.Material?, -- the Housing role only (Field: CorrodedMetal)
	Shade: number, -- the role's HEAD colour (Palette / SharedColors key) x Shade, rounded to whole RGB
	PaintFrame: string?, -- Palette key painted on the BeltFrame (Arsenal: "Accent")
	RoofReflectance: number?, -- Roof Reflectance (nil = 0)
}

-- droppers v1a: a product look per business and tier (client pooled parts; raw at spawn, done after the machine hit)
export type ProductLook = {
	Size: Vector3,
	Shape: Enum.PartType?, -- nil = Block
	RawColor: Color3,
	RawMaterial: Enum.Material,
	Color: Color3, -- done look (after the hit; the heap wears it)
	Material: Enum.Material,
	HeapMaterial: Enum.Material?, -- the heap's material when it differs from Material (nil = Material)
}

-- droppers v1a: a machine (business-local studs, the Kit frame; see Machines below)
export type MachineDef = {
	Size: Vector3, -- hinge machines: X is the arm length, the hinge sits at the arm's -X end
	Pos: Vector3?, -- slide machines: rest centre
	HitPos: Vector3?, -- slide machines: hit centre when it is fixed (PlateStamp)
	HitOnProduct: boolean?, -- slide machines: hit centre = (Pos.X, belt top + product height + Size.Y / 2, Pos.Z)
	Hinge: Vector3?, -- hinge machines: pivot
	Yaw: number?, -- hinge machines: degrees, the arm turned from +X toward +Z
	RestPitch: number?, -- hinge machines: degrees, + = tip up
	HitPitch: number?,
	HitAlong: number, -- studs from the belt start (x -2.5) to where the product is hit
	StrokeDown: number, -- seconds the stroke starts before the hit
	Sparks: boolean?, -- ProductionFx.Sparks at the tip on the hit
}

-- bizlook: a kit part's box from FromLevel on (the last row with FromLevel <= level wins; below the first row the
-- KitPart's own Size / Offset). BusinessService writes Size / CFrame only when they differ (property-only growth).
export type KitGrow = { FromLevel: number, Size: Vector3, Offset: Vector3 }

export type KitPart = {
	Role: string,
	MinLevel: number, -- built when level >= MinLevel (0 = the empty slab before the first buy)
	Size: Vector3,
	Offset: Vector3, -- business-local: +X along the line (machine at -X, bin at +X), +Z = front (console side), Y up from the pad top
	Material: Enum.Material,
	ColorKey: string, -- a Palette key ("Body" | "Roof" | "Accent") or a SharedColors key
	Shape: Enum.PartType?,
	Collide: boolean?,
	Grow: { KitGrow }?, -- bizlook: the box grows with the level (a stretched piece in it is refitted by BusinessService)
	Reflectance: number?, -- bizlook: set once at build (the window band)
}

local BusinessConfig = {
	Enabled = true,
	Kind = "Business", -- BaseConfig.Structures[id].Kind for a merged business (nil = building / installation)
	FolderName = "WE_Businesses",
	ModelPrefix = "WE_Business_",
	Tag = "WE_Business", -- CollectionService tag on each business Model (client visuals find lines through it)
	Order = { "AmmoWorks", "ArmsCrateLine", "ArmorPlatePress", "RocketAssembly" },
	-- Parts per business: L0 4 (slab + 3-part console), L1 10, L2 12, L3 14, L4 15, L5 16. Hard cap incl. the console;
	-- BuyPathStatic checks the Kit table against it (Kit + 3 <= PartsPerBusinessL5).
	PartsPerBusinessL5 = 16,
	ConsoleNeon = false, -- business consoles use a SmoothPlastic button (world Neon is over its 300 target)
	ConsoleScreenGui = false, -- no SurfaceGui (SurfaceGui headroom is ~20 world-wide); the client price tag says it

	Businesses = {
		AmmoWorks = {
			Id = "AmmoWorks",
			DisplayName = "Ammo Works",
			ShortName = "AMMO",
			Description = "Makes ammo boxes. Pays into your ATM.",
			Costs = { 600, 2000, 6000, 18000, 55000 },
			IncomePerTick = { 16, 36, 70, 125, 200 }, -- $/s at x1: 3.2 / 7.2 / 14 / 25 / 40
			Requires = nil, -- buyable from the first second (tutorial step 6)
			Palette = { Body = Color3.fromRGB(150, 88, 66), Roof = Color3.fromRGB(58, 60, 64), Accent = Color3.fromRGB(226, 160, 40) }, -- bizlook brand: amber
			Signature = "Hopper",
			Product = "AmmoBox",
			CrateEverySec = { 2.5, 2.2, 1.8, 1.5, 1.2 },
			ProductsPerTick = { 2, 3, 3, 4, 5 }, -- droppers v1a: one every 2.50 / 1.67 / 1.67 / 1.25 / 1.00 s (GQ 1-3: 2 per beat)
			Machine = "ShellPress",
		},
		ArmsCrateLine = {
			Id = "ArmsCrateLine",
			DisplayName = "Arms Crate Line",
			ShortName = "ARMS",
			Description = "Packs rifle crates. Pays into your ATM.",
			Costs = { 2000, 6500, 19000, 57000, 170000 },
			IncomePerTick = { 40, 85, 160, 280, 450 }, -- $/s at x1: 8 / 17 / 32 / 56 / 90
			-- v72: the Weapons Facility gates it (Weapons Facility itself needs Command Center 1)
			Requires = { { StructureId = "AmmoWorks", Level = 1 }, { StructureId = "WeaponsFacility", Level = 1 } },
			Palette = { Body = Color3.fromRGB(138, 92, 72), Roof = Color3.fromRGB(58, 60, 64), Accent = Color3.fromRGB(58, 150, 84) }, -- bizlook brand: green
			Signature = "RackBar",
			Product = "RifleCrate",
			CrateEverySec = { 2.5, 2.2, 1.8, 1.5, 1.2 },
			ProductsPerTick = { 2, 2, 3, 4, 4 }, -- droppers v1a: one every 2.50 / 2.50 / 1.67 / 1.25 / 1.25 s (GQ 1-3: 2 per beat)
			Machine = "LoaderBoom",
		},
		ArmorPlatePress = {
			Id = "ArmorPlatePress",
			DisplayName = "Armor Plate Press",
			ShortName = "ARMOR",
			Description = "Presses armor plates. Pays into your ATM.",
			Costs = { 8000, 25000, 75000, 220000, 650000 },
			-- v72 Lane K econ tune (x1.2 of the spec's 100/180/300/480/720): with the 34% soldier share rule the guided
			-- run earned 274 $/s at 30 min (target 280-380); this gives 295 (353 without the rule), <= 531 at 60 min
			IncomePerTick = { 120, 220, 360, 580, 860 }, -- $/s at x1: 24 / 44 / 72 / 116 / 172
			Requires = { { StructureId = "CommandCenter", Level = 2 }, { StructureId = "ArmsCrateLine", Level = 2 } },
			Palette = { Body = Color3.fromRGB(126, 96, 84), Roof = Color3.fromRGB(58, 60, 64), Accent = Color3.fromRGB(46, 112, 196) }, -- bizlook brand: blue
			Signature = "PressRam",
			Product = "ArmorPlate",
			CrateEverySec = { 2.5, 2.2, 1.8, 1.5, 1.2 },
			ProductsPerTick = { 2, 2, 3, 3, 4 }, -- droppers v1a: one every 2.50 / 2.50 / 1.67 / 1.67 / 1.25 s (GQ 1-3: 2 per beat)
			Machine = "PlateStamp",
		},
		RocketAssembly = {
			Id = "RocketAssembly",
			DisplayName = "Rocket Assembly",
			ShortName = "ROCKETS",
			Description = "Builds rockets. Pays into your ATM.",
			Costs = { 30000, 90000, 270000, 800000, 2400000 },
			IncomePerTick = { 260, 440, 700, 1050, 1500 }, -- $/s at x1: 52 / 88 / 140 / 210 / 300
			Requires = { { StructureId = "CommandCenter", Level = 3 }, { StructureId = "ArmorPlatePress", Level = 2 } },
			Palette = { Body = Color3.fromRGB(156, 100, 76), Roof = Color3.fromRGB(58, 60, 64), Accent = Color3.fromRGB(204, 58, 48) }, -- bizlook brand: red
			Signature = "RocketBody",
			Product = "Rocket",
			CrateEverySec = { 2.5, 2.2, 1.8, 1.5, 1.2 },
			ProductsPerTick = { 2, 2, 2, 3, 3 }, -- droppers v1a: one every 2.50 / 2.50 / 2.50 / 1.67 / 1.67 s (GQ 1-3: 2 per beat)
			Machine = "FinWelder",
		},
	} :: { [string]: BusinessDef },

	-- Shared line kit (business-local). bizlook: the same count per level as v1a (L1 6, L2 +2, L3 +2, L4 +1, L5 +1 ->
	-- 12 + slab 1 + console 3 = 16). Belt / BeltFrame / Bin and the Housing's +X wall (x = -3) keep their v1a boxes (the
	-- machines, products, heap and pop read them). Layout: the brick workshop front-left (L1); a loading unit behind the
	-- bin (L2: Dock, the collider, and DockFront, its shutter); the head office behind the belt start (L3: Hall, the
	-- collider, and HallFront, its window band; the office grows L4 / L5 by Grow rows); a canopy over the belt (L4); a
	-- brand band round the office top (L5). With the Roblox-made pieces of VisualAssetConfig.BusinessPieces on, DockFront
	-- / HallFront / Canopy wear real building meshes fitted into the Dock / Hall / Canopy boxes and the Dock / Hall
	-- colliders turn invisible (their collision stays); without them this Part kit is the look. The unit stays 6 studs
	-- high and the office stands at x <= 4, so the ATM behind Ammo Works stays in sight from its kiosk; the canopy stops
	-- at x 6, so the bin, heap and "+$N" pop stay open to the sky.
	Kit = {
		{ Role = "Slab", MinLevel = 0, Size = Vector3.new(22, 0.3, 12), Offset = Vector3.new(0, 0.15, 0), Material = Enum.Material.Concrete, ColorKey = "Slab", Collide = true, Grow = { { FromLevel = 2, Size = Vector3.new(26, 0.3, 16), Offset = Vector3.new(0, 0.15, -2) } } },
		{ Role = "Housing", MinLevel = 1, Size = Vector3.new(7, 7, 8), Offset = Vector3.new(-6.5, 3.5, 0), Material = Enum.Material.Brick, ColorKey = "Body", Collide = true },
		{ Role = "Roof", MinLevel = 1, Size = Vector3.new(8, 0.7, 10.1), Offset = Vector3.new(-6.5, 7.35, 1.05), Material = Enum.Material.Metal, ColorKey = "Accent" },
		{ Role = "Signature", MinLevel = 1, Size = Vector3.new(3, 2.5, 3), Offset = Vector3.new(-6.5, 8.9, 0), Material = Enum.Material.Metal, ColorKey = "Accent" },
		{ Role = "Belt", MinLevel = 1, Size = Vector3.new(9, 0.4, 2.6), Offset = Vector3.new(2, 2.4, 0), Material = Enum.Material.Fabric, ColorKey = "Belt" },
		{ Role = "BeltFrame", MinLevel = 1, Size = Vector3.new(9, 2.2, 2.2), Offset = Vector3.new(2, 1.1, 0), Material = Enum.Material.Metal, ColorKey = "Frame", Collide = true },
		{ Role = "Bin", MinLevel = 1, Size = Vector3.new(4, 2.2, 5), Offset = Vector3.new(8.5, 1.1, 0), Material = Enum.Material.Metal, ColorKey = "Dark", Collide = true },
		{ Role = "Dock", MinLevel = 2, Size = Vector3.new(8.5, 6, 5.5), Offset = Vector3.new(8.25, 3, -6.75), Material = Enum.Material.Brick, ColorKey = "Body", Collide = true },
		{ Role = "DockFront", MinLevel = 2, Size = Vector3.new(4.4, 4.6, 0.3), Offset = Vector3.new(8.5, 2.3, -3.9), Material = Enum.Material.Metal, ColorKey = "Shutter" },
		{ Role = "Hall", MinLevel = 3, Size = Vector3.new(16, 9, 6), Offset = Vector3.new(-4, 4.5, -7), Material = Enum.Material.Metal, ColorKey = "Hall", Collide = true, Grow = { { FromLevel = 4, Size = Vector3.new(16, 10, 6), Offset = Vector3.new(-4, 5, -7) }, { FromLevel = 5, Size = Vector3.new(16, 14, 6), Offset = Vector3.new(-4, 7, -7) } } },
		{ Role = "HallFront", MinLevel = 3, Size = Vector3.new(16.3, 2, 6.3), Offset = Vector3.new(-4, 6.2, -7), Material = Enum.Material.Glass, ColorKey = "Glass", Reflectance = 0.25, Grow = { { FromLevel = 4, Size = Vector3.new(16.3, 2.2, 6.3), Offset = Vector3.new(-4, 6.8, -7) }, { FromLevel = 5, Size = Vector3.new(16.3, 4.4, 6.3), Offset = Vector3.new(-4, 9, -7) } } },
		{ Role = "Canopy", MinLevel = 4, Size = Vector3.new(9.4, 0.4, 6.2), Offset = Vector3.new(1.3, 6.4, -1), Material = Enum.Material.Metal, ColorKey = "Canopy" },
		{ Role = "Fascia", MinLevel = 5, Size = Vector3.new(16.4, 1.4, 6.4), Offset = Vector3.new(-4, 14.5, -7), Material = Enum.Material.SmoothPlastic, ColorKey = "Accent" },
	} :: { KitPart },
	-- Signature overrides the Signature slot's size / offset / shape per business (still one part). bizlook: each line
	-- wears its product on the workshop roof as a big "product sign" (Ammo: a brass casing standing up; Arms: an army
	-- crate; Rocket: the Roblox Rocket dress); the Armor press keeps its ram over the belt (the stamp rests inside it).
	-- Rot = degrees (X, Y, Z) applied after the offset; Material overrides the kit row's.
	Signatures = {
		Hopper = { Size = Vector3.new(3.4, 2.2, 2.2), Offset = Vector3.new(-6.5, 9.4, -0.5), Shape = Enum.PartType.Cylinder, Rot = Vector3.new(0, 0, 90) },
		RackBar = { Size = Vector3.new(3.6, 2, 2.4), Offset = Vector3.new(-6.5, 8.7, -0.5), Material = Enum.Material.WoodPlanks },
		PressRam = { Size = Vector3.new(3, 1.6, 3), Offset = Vector3.new(2, 4.4, 0) },
		RocketBody = { Size = Vector3.new(7, 1.6, 1.6), Offset = Vector3.new(-6.5, 8.6, 0), Shape = Enum.PartType.Cylinder },
	} :: { [string]: { Size: Vector3, Offset: Vector3, Shape: Enum.PartType?, Rot: Vector3?, Material: Enum.Material? } },
	SharedColors = {
		Slab = Color3.fromRGB(176, 174, 168), -- bizlook: a clean light forecourt
		Belt = Color3.fromRGB(36, 38, 36),
		Frame = Color3.fromRGB(70, 72, 68),
		Dark = Color3.fromRGB(52, 54, 50),
		Hall = Color3.fromRGB(206, 208, 206), -- bizlook: the office's Part-kit cladding (hidden while the office piece is on)
		Canopy = Color3.fromRGB(58, 60, 64), -- bizlook: charcoal canopy over the belt (Part-kit fallback of the canopy piece)
		Glass = Color3.fromRGB(70, 118, 150), -- bizlook: the office's Part-kit window band
		Shutter = Color3.fromRGB(196, 198, 196), -- bizlook: the loading bay's Part-kit shutter panel
	} :: { [string]: Color3 },

	--[[ Droppers v1a: server look tiers (spec §3.4; BusinessService applyLook). Property-only, 0 new parts: Material,
		Color and the Roof Reflectance of the LookTierRoles kit parts. A new part is built with its tier look; an existing
		one is written only where a value differs (a level-down / rebirth reapplies the lower tier; an idle re-sync
		writes nothing). A part that carries WE_CatalogAssetId (hooks dress) is never written.
		bizlook: Chimney is gone (Hall takes its slot). No rust tier any more: OD-2's CorrodedMetal Field housing read as a
		shed and the owner now asks for "a legit high-end business", so the workshop is brick at every tier (Field and
		Works look the same); Arsenal paints the belt frame in the brand colour and gives the cornice a slight sheen. ]]
	LookTierRoles = { "Housing", "Roof", "BeltFrame", "Bin", "Hall" },
	LookTiers = {
		{ FromLevel = 1, Name = "Field", Material = Enum.Material.Metal, HousingMaterial = Enum.Material.Brick, Shade = 1, RoofReflectance = 0 },
		{ FromLevel = 3, Name = "Works", Material = Enum.Material.Metal, HousingMaterial = Enum.Material.Brick, Shade = 1, RoofReflectance = 0 },
		{ FromLevel = 5, Name = "Arsenal", Material = Enum.Material.Metal, HousingMaterial = Enum.Material.Brick, Shade = 1, PaintFrame = "Accent", RoofReflectance = 0.08 },
	} :: { LookTier },

	-- Client-only visuals (Client/Modules/BusinessVisuals + ProductionFx). Cosmetic: the server never reads these.
	Visual = {
		ActiveRadius = 80, -- products run only on YOUR lines within this many studs of your character
		MaxCratesPerLine = 3, -- pooled products per line (LowQualityPool on Graphics Quality 1..LowQualityLevel)
		LowQualityLevel = 3,
		LowQualityPool = 2, -- droppers v1a: pooled products per line at Graphics Quality 1..LowQualityLevel (HEAD 1)
		LowQualityMaxK = 2, -- ... and k = min(ProductsPerTick[L], LowQualityMaxK) there (<= LowQualityPool)
		AutomaticTouchIsLow = false, -- OD-13 lever: true = Automatic quality on touch uses the low pool and k as well
		BeltSpeed = 4, -- studs / s along the belt (fallback while BeltSpeedByLevel is nil)
		BeltSpeedByLevel = { 3.2, 3.6, 4.0, 4.5, 5.0 },
		UpdateHz = 20, -- one shared loop for all lines (BulkMoveTo); CLAUDE.md: no per-frame allocations
		PopRadius = 28, -- "+$N" owner pop only within this range
		MaxPopsPerTick = 2, -- world labels <= 3 at a base
		PopTextPx = 18,
		-- droppers v1a production clock (feel §8): k products land per WE_PassiveTick window, the last one
		-- LandLeadSeconds before the tick; k = clamp(want, 1, floor(pool x period / travelTotal)), re-evaluated per tick
		LandLeadSeconds = 0.6,
		PhaseGain = 0.3,
		PeriodEma = 0.25,
		ResyncSeconds = 1,
		PathHz = 20, -- path table resolution (CFrames per second of travel, built in measure(), never in the step)
		InstantFirstProduct = true, -- a real level-up (a rise of a seen line) drops one product straight onto the heap
		-- BusinessVisuals module locals moved here (POP_EVERY stays a pinned local: the 10 Hz UI cap)
		ScanHz = 4,
		DropFrac = 0.25, -- the drop into the bin lasts this share of the belt time
		PopSeconds = 1.2,
		PopHold = 0.5,
		PopRise = 1.5,
		-- y 4.2 -> 5.5 (v1a fix round 1): the title is fixed 18 px text, wider than its 3 x 1.2 stud box on a phone, so
		-- at 4.2 its "+" slid behind the L3+ awning when it appeared. Lower it only after a phone check.
		PopOffset = Vector3.new(1, 5.5, 0), -- from the bin centre: +1 along the line toward the bin end, above the L3+ awning
		-- v1a fix round 2: the top-centre chip (NEXT / tutorial step, a ScreenGui) draws over world billboards. While it is
		-- up, a pop whose title would land under it steps down the segment PopOffset -> LowOffset: the first of Steps + 1
		-- anchors whose title (at the top of its opaque rise) projects clear of the chip wins, else LowOffset. At a
		-- console the chip is hidden (BUY button up), so the pop stays at PopOffset there.
		PopDodge = {
			Enabled = true,
			LowOffset = Vector3.new(5, 2, 0), -- 3 studs past the bin end, 1 over its rim: clear of the awning, beside the heap
			Steps = 8,
			MarginPx = 6, -- real px kept clear around the chip
			CharWidth = 0.62, -- title width estimate: CharWidth x PopTextPx per character (+2 px stroke)
			TutorialFlag = "Tutorial", -- HudLayout flag: the tutorial's step chip holds the same top-centre slot
		},
		Heap = {
			Enabled = true, -- false = HEAD: products sink into the bin (the tick lock and pops stay)
			Size = Vector3.new(3.2, 2.4, 4.2),
			RestSink = 0.05, -- hidden at rest: its top sits this far under the bin top
			RiseByLevel = { 1.0, 1.2, 1.4, 1.6, 1.8 }, -- studs a full heap rises at level 1..5 (full top 3.15..3.95)
			SinkSteps = 3,
		},
		Machines = { Enabled = true, WeldRadius = 40 },
		-- OD-7: code built, OFF until the owner's 2-minute Studio check (texture on a Transparency-1 part, arrow
		-- direction, no double stripe). 40101352 is the conveyor texture the hooks belt already loads (0 load slots).
		BeltFx = {
			Enabled = false,
			Image = "rbxassetid://40101352",
			Tint = Color3.fromRGB(150, 165, 130),
			TileStuds = 2.6,
			ScrollAxis = "U",
			ScrollSign = 1,
			Lift = 0.02,
			HideDressDecal = true,
		},
		Fx = {
			Enabled = true,
			ShipEmit = 4,
			ShipEmitLow = 2,
			LevelEmit = 10,
			LevelEmitLow = 5,
			AtmEmit = 8, -- v1b (ATM collect sparkle)
			AtmEmitLow = 5,
			AtmRadius = 16,
			WeldSparks = 2,
			MaxParticlesPerSecond = 16, -- module token bucket across every emitter
			LevelBurstGap = 0.5,
			-- the engine's own particle textures (0 load slots), pooled emitters with Rate = 0 (Emit only), no lights
			SparkleTexture = "rbxasset://textures/particles/sparkles_main.dds",
			SparkTexture = "rbxasset://textures/particles/fire_sparks_main.dds",
			SparkleColor = Color3.fromRGB(255, 214, 72),
			SparkleLifetime = 0.6, -- seconds (<= 0.6: with 16 per second at most 16 alive)
			SparkLifetime = 0.25, -- welder sparks
			LightEmission = 0.3, -- <= 0.3 (no glow floods)
			HideWhen = { "Driving", "Dead", "Modal", "RecentCombat" }, -- HudLayout flags: no pops, sparkles or sounds
		},
		Ghost = { Enabled = false, Transparency = 0.7, ConsoleRadius = 14, MaxParts = 6, Inflate = 0.1 }, -- v1.1
		Ambient = { Enabled = false, Radius = 50, MaxLines = 2 }, -- v1.1
	},
	Crates = {
		AmmoBox = { Size = Vector3.new(1.2, 0.8, 0.9), Color = Color3.fromRGB(92, 104, 64), Material = Enum.Material.Metal },
		RifleCrate = { Size = Vector3.new(2.2, 0.7, 0.9), Color = Color3.fromRGB(110, 92, 60), Material = Enum.Material.WoodPlanks },
		ArmorPlate = { Size = Vector3.new(1.6, 0.3, 1.6), Color = Color3.fromRGB(150, 154, 160), Material = Enum.Material.Metal },
		Rocket = { Size = Vector3.new(2.4, 0.6, 0.6), Color = Color3.fromRGB(220, 220, 214), Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Cylinder },
	} :: { [string]: { Size: Vector3, Color: Color3, Material: Enum.Material, Shape: Enum.PartType? } },
	-- (Crates: HEAD looks, kept as an alias for one release; Products below replaces it.)

	-- Droppers v1a (spec §3.3): product looks per business and tier (Field L1-2, Works L3-4, Arsenal L5). A product
	-- spawns raw and turns done at the machine hit (<= 2 writes: Color, Material when it differs); Size / Shape change
	-- only on a tier change (the pool is re-skinned in place). All generic: no stencil, insignia, flag or brand.
	Products = {
		AmmoWorks = {
			Field = { Size = Vector3.new(1.2, 0.6, 0.6), Shape = Enum.PartType.Cylinder, RawColor = Color3.fromRGB(150, 122, 70), RawMaterial = Enum.Material.Metal, Color = Color3.fromRGB(205, 165, 80), Material = Enum.Material.Metal },
			Works = { Size = Vector3.new(1.2, 0.8, 0.9), RawColor = Color3.fromRGB(120, 122, 118), RawMaterial = Enum.Material.Metal, Color = Color3.fromRGB(92, 104, 64), Material = Enum.Material.Metal },
			Arsenal = { Size = Vector3.new(1.2, 0.8, 0.9), RawColor = Color3.fromRGB(92, 104, 64), RawMaterial = Enum.Material.Metal, Color = Color3.fromRGB(196, 150, 60), Material = Enum.Material.Metal },
		},
		ArmsCrateLine = {
			Field = { Size = Vector3.new(2.2, 0.7, 0.9), RawColor = Color3.fromRGB(150, 118, 72), RawMaterial = Enum.Material.WoodPlanks, Color = Color3.fromRGB(110, 92, 60), Material = Enum.Material.WoodPlanks },
			Works = { Size = Vector3.new(2.2, 0.7, 0.9), RawColor = Color3.fromRGB(110, 92, 60), RawMaterial = Enum.Material.WoodPlanks, Color = Color3.fromRGB(96, 104, 70), Material = Enum.Material.WoodPlanks },
			Arsenal = { Size = Vector3.new(2.2, 0.7, 0.9), RawColor = Color3.fromRGB(96, 104, 70), RawMaterial = Enum.Material.WoodPlanks, Color = Color3.fromRGB(70, 76, 64), Material = Enum.Material.Metal },
		},
		ArmorPlatePress = {
			Field = { Size = Vector3.new(1.6, 0.3, 1.6), RawColor = Color3.fromRGB(150, 140, 128), RawMaterial = Enum.Material.CorrodedMetal, Color = Color3.fromRGB(150, 154, 160), Material = Enum.Material.Metal },
			Works = { Size = Vector3.new(1.6, 0.3, 1.6), RawColor = Color3.fromRGB(150, 140, 128), RawMaterial = Enum.Material.CorrodedMetal, Color = Color3.fromRGB(170, 174, 180), Material = Enum.Material.DiamondPlate },
			Arsenal = { Size = Vector3.new(1.6, 0.3, 1.6), RawColor = Color3.fromRGB(150, 140, 128), RawMaterial = Enum.Material.CorrodedMetal, Color = Color3.fromRGB(104, 112, 92), Material = Enum.Material.DiamondPlate },
		},
		RocketAssembly = {
			Field = { Size = Vector3.new(2.4, 0.6, 0.6), Shape = Enum.PartType.Cylinder, RawColor = Color3.fromRGB(150, 150, 146), RawMaterial = Enum.Material.Metal, Color = Color3.fromRGB(200, 200, 196), Material = Enum.Material.Metal, HeapMaterial = Enum.Material.Metal },
			Works = { Size = Vector3.new(2.4, 0.6, 0.6), Shape = Enum.PartType.Cylinder, RawColor = Color3.fromRGB(150, 150, 146), RawMaterial = Enum.Material.Metal, Color = Color3.fromRGB(220, 220, 214), Material = Enum.Material.SmoothPlastic, HeapMaterial = Enum.Material.Metal },
			Arsenal = { Size = Vector3.new(2.4, 0.6, 0.6), Shape = Enum.PartType.Cylinder, RawColor = Color3.fromRGB(150, 150, 146), RawMaterial = Enum.Material.Metal, Color = Color3.fromRGB(190, 70, 56), Material = Enum.Material.SmoothPlastic, HeapMaterial = Enum.Material.Metal },
		},
	} :: { [string]: { [string]: ProductLook } },

	--[[ Droppers v1a (spec §3.5): one pooled local part per own line, placed in the Kit_Belt frame:
		belt.CFrame * CFrame.new(M.Pos - KitBeltOffset), KitBeltOffset = the Kit "Belt" Offset (2, 2.4, 0), with the +-X
		sign measure() derives from the bin. Hinge arms run from Hinge along +X, turned Yaw degrees toward +Z, pitched
		+up; a hinge tween is a CFrame lerp (<= 0.04 stud off the arc). Belt top y 2.6, belt start x -2.5; hit time =
		spawn + HitAlong / BeltSpeedByLevel[L]; the tween starts StrokeDown earlier. No machine face is coplanar with
		an overlapping kit face (ShellPress 0.05 into the Housing wall; PlateStamp rests at y 4.25 inside the PressRam). ]]
	Machines = {
		ShellPress = { Size = Vector3.new(1.6, 0.8, 1.8), Pos = Vector3.new(-2.25, 4.4, 0), HitOnProduct = true, HitAlong = 0.25, StrokeDown = 0.15 },
		LoaderBoom = { Size = Vector3.new(3.0, 0.6, 0.6), Hinge = Vector3.new(-2.6, 4.6, 0), Yaw = 0, RestPitch = 0, HitPitch = -20, HitAlong = 2.72, StrokeDown = 0.25 },
		PlateStamp = { Size = Vector3.new(1.2, 1.2, 1.2), Pos = Vector3.new(2, 4.25, 0), HitPos = Vector3.new(2, 3.5, 0), HitAlong = 4.5, StrokeDown = 0.12 },
		FinWelder = { Size = Vector3.new(2.2, 0.6, 0.6), Hinge = Vector3.new(-3.0, 4.2, -0.9), Yaw = 20, RestPitch = 10, HitPitch = -20, HitAlong = 1.44, StrokeDown = 0.25, Sparks = true },
	} :: { [string]: MachineDef },
	-- machine colour per look tier: a Color3, or a Palette key (Arsenal: the business Accent); Metal throughout
	MachineColors = {
		Field = Color3.fromRGB(44, 46, 43),
		Works = Color3.fromRGB(52, 54, 50),
		Arsenal = "Accent",
	} :: { [string]: Color3 | string },
	MachineMaterial = Enum.Material.Metal,
}

-- The def for `id` (whether or not Enabled; use IsBusiness to ask "is this a live business").
function BusinessConfig.Get(id: string): BusinessDef?
	return BusinessConfig.Businesses[id]
end

-- true only while Enabled and `id` is one of the businesses
function BusinessConfig.IsBusiness(id: string): boolean
	return BusinessConfig.Enabled and BusinessConfig.Businesses[id] ~= nil
end

-- Parts a business owns at `level` (console 3 + kit parts with MinLevel <= level, the slab included).
function BusinessConfig.PartCount(level: number): number
	local n = 3
	for _, p in ipairs(BusinessConfig.Kit) do
		if p.MinLevel <= level then
			n += 1
		end
	end
	return n
end

-- Droppers v1a: the look tier at `level` (the last LookTiers row with FromLevel <= level; below the first row, the
-- first row). The one tier rule for the server look (BusinessService) and the client products / machines.
function BusinessConfig.LookTierFor(level: number): LookTier
	local tiers = BusinessConfig.LookTiers
	local pick = tiers[1]
	for _, t in ipairs(tiers) do
		if t.FromLevel <= level then
			pick = t
		end
	end
	return pick
end

return BusinessConfig
