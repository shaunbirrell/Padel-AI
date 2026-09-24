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
}

export type KitPart = {
	Role: string,
	MinLevel: number, -- built when level >= MinLevel (0 = the empty slab before the first buy)
	Size: Vector3,
	Offset: Vector3, -- business-local: +X along the line (machine at -X, bin at +X), +Z = front (console side), Y up from the pad top
	Material: Enum.Material,
	ColorKey: string, -- "Body" | "Roof" | "Accent" | "Slab" | "Belt" | "Frame" | "Hazard" | "Gold" | "Dark"
	Shape: Enum.PartType?,
	Collide: boolean?,
}

local BusinessConfig = {
	Enabled = false,
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
			Palette = { Body = Color3.fromRGB(122, 128, 92), Roof = Color3.fromRGB(78, 84, 60), Accent = Color3.fromRGB(196, 150, 60) },
			Signature = "Hopper",
			Product = "AmmoBox",
			CrateEverySec = { 2.5, 2.2, 1.8, 1.5, 1.2 },
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
			Palette = { Body = Color3.fromRGB(96, 104, 84), Roof = Color3.fromRGB(62, 66, 58), Accent = Color3.fromRGB(170, 120, 70) },
			Signature = "RackBar",
			Product = "RifleCrate",
			CrateEverySec = { 2.5, 2.2, 1.8, 1.5, 1.2 },
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
			Palette = { Body = Color3.fromRGB(120, 124, 128), Roof = Color3.fromRGB(70, 74, 78), Accent = Color3.fromRGB(200, 170, 70) },
			Signature = "PressRam",
			Product = "ArmorPlate",
			CrateEverySec = { 2.5, 2.2, 1.8, 1.5, 1.2 },
		},
		RocketAssembly = {
			Id = "RocketAssembly",
			DisplayName = "Rocket Assembly",
			ShortName = "ROCKETS",
			Description = "Builds rockets. Pays into your ATM.",
			Costs = { 30000, 90000, 270000, 800000, 2400000 },
			IncomePerTick = { 260, 440, 700, 1050, 1500 }, -- $/s at x1: 52 / 88 / 140 / 210 / 300
			Requires = { { StructureId = "CommandCenter", Level = 3 }, { StructureId = "ArmorPlatePress", Level = 2 } },
			Palette = { Body = Color3.fromRGB(176, 170, 150), Roof = Color3.fromRGB(88, 90, 86), Accent = Color3.fromRGB(190, 70, 56) },
			Signature = "RocketBody",
			Product = "Rocket",
			CrateEverySec = { 2.5, 2.2, 1.8, 1.5, 1.2 },
		},
	} :: { [string]: BusinessDef },

	-- Shared line kit (business-local). Level parts: L1 6, L2 +2, L3 +2, L4 +1, L5 +1 -> 12 + slab 1 + console 3 = 16.
	Kit = {
		{ Role = "Slab", MinLevel = 0, Size = Vector3.new(22, 0.3, 12), Offset = Vector3.new(0, 0.15, 0), Material = Enum.Material.Concrete, ColorKey = "Slab", Collide = true },
		{ Role = "Housing", MinLevel = 1, Size = Vector3.new(7, 7, 8), Offset = Vector3.new(-6.5, 3.5, 0), Material = Enum.Material.Metal, ColorKey = "Body", Collide = true },
		{ Role = "Roof", MinLevel = 1, Size = Vector3.new(8, 0.6, 9), Offset = Vector3.new(-6.5, 7.3, 0), Material = Enum.Material.Metal, ColorKey = "Roof" },
		{ Role = "Signature", MinLevel = 1, Size = Vector3.new(3, 2.5, 3), Offset = Vector3.new(-6.5, 8.9, 0), Material = Enum.Material.Metal, ColorKey = "Accent" },
		{ Role = "Belt", MinLevel = 1, Size = Vector3.new(9, 0.4, 2.6), Offset = Vector3.new(2, 2.4, 0), Material = Enum.Material.Fabric, ColorKey = "Belt" },
		{ Role = "BeltFrame", MinLevel = 1, Size = Vector3.new(9, 2.2, 2.2), Offset = Vector3.new(2, 1.1, 0), Material = Enum.Material.Metal, ColorKey = "Frame", Collide = true },
		{ Role = "Bin", MinLevel = 1, Size = Vector3.new(4, 2.2, 5), Offset = Vector3.new(8.5, 1.1, 0), Material = Enum.Material.Metal, ColorKey = "Dark", Collide = true },
		{ Role = "Chimney", MinLevel = 2, Size = Vector3.new(1.4, 6, 1.4), Offset = Vector3.new(-8.6, 10.6, -2.6), Material = Enum.Material.Metal, ColorKey = "Dark" },
		{ Role = "Stock", MinLevel = 2, Size = Vector3.new(2.4, 2.4, 2.4), Offset = Vector3.new(-1, 1.2, -4), Material = Enum.Material.WoodPlanks, ColorKey = "Accent", Collide = true },
		{ Role = "Awning", MinLevel = 3, Size = Vector3.new(10, 0.3, 4), Offset = Vector3.new(2.5, 5.2, 0), Material = Enum.Material.Metal, ColorKey = "Roof" },
		{ Role = "Hazard", MinLevel = 3, Size = Vector3.new(22, 0.05, 0.8), Offset = Vector3.new(0, 0.33, 5.4), Material = Enum.Material.SmoothPlastic, ColorKey = "Hazard" },
		{ Role = "Pallet", MinLevel = 4, Size = Vector3.new(3.5, 1.6, 3.5), Offset = Vector3.new(8.5, 0.8, -4.2), Material = Enum.Material.WoodPlanks, ColorKey = "Accent", Collide = true },
		{ Role = "GoldTrim", MinLevel = 5, Size = Vector3.new(8.2, 0.3, 9.2), Offset = Vector3.new(-6.5, 6.9, 0), Material = Enum.Material.Metal, ColorKey = "Gold" },
	} :: { KitPart },
	-- Signature overrides the Signature slot's size / offset / shape per business (still one part)
	Signatures = {
		Hopper = { Size = Vector3.new(3, 2.5, 3), Offset = Vector3.new(-6.5, 8.9, 0) },
		RackBar = { Size = Vector3.new(0.5, 3.2, 6.5), Offset = Vector3.new(-2.8, 5.2, 0) },
		PressRam = { Size = Vector3.new(3, 1.6, 3), Offset = Vector3.new(2, 4.4, 0) },
		RocketBody = { Size = Vector3.new(7, 1.6, 1.6), Offset = Vector3.new(-6.5, 8.6, 0), Shape = Enum.PartType.Cylinder },
	} :: { [string]: { Size: Vector3, Offset: Vector3, Shape: Enum.PartType? } },
	SharedColors = {
		Slab = Color3.fromRGB(128, 124, 112),
		Belt = Color3.fromRGB(36, 38, 36),
		Frame = Color3.fromRGB(70, 72, 68),
		Hazard = Color3.fromRGB(214, 178, 64),
		Gold = Color3.fromRGB(240, 196, 64),
		Dark = Color3.fromRGB(52, 54, 50),
	} :: { [string]: Color3 },

	-- Client-only visuals (Client/Modules/BusinessVisuals). Cosmetic: the server never reads these.
	Visual = {
		ActiveRadius = 80, -- crates run only on YOUR lines within this many studs of your character
		MaxCratesPerLine = 3, -- pooled parts per line (1 on Graphics Quality <= LowQualityLevel)
		LowQualityLevel = 3,
		BeltSpeed = 4, -- studs / s along the belt
		UpdateHz = 20, -- one shared loop for all lines (BulkMoveTo); CLAUDE.md: no per-frame allocations
		PopRadius = 28, -- "+$N" owner pop only within this range
		MaxPopsPerTick = 2, -- world labels <= 3 at a base
		PopTextPx = 18,
	},
	Crates = {
		AmmoBox = { Size = Vector3.new(1.2, 0.8, 0.9), Color = Color3.fromRGB(92, 104, 64), Material = Enum.Material.Metal },
		RifleCrate = { Size = Vector3.new(2.2, 0.7, 0.9), Color = Color3.fromRGB(110, 92, 60), Material = Enum.Material.WoodPlanks },
		ArmorPlate = { Size = Vector3.new(1.6, 0.3, 1.6), Color = Color3.fromRGB(150, 154, 160), Material = Enum.Material.Metal },
		Rocket = { Size = Vector3.new(2.4, 0.6, 0.6), Color = Color3.fromRGB(220, 220, 214), Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Cylinder },
	} :: { [string]: { Size: Vector3, Color: Color3, Material: Enum.Material, Shape: Enum.PartType? } },
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

return BusinessConfig
