--!strict
--[[ v69 Research Lab tree — shared by ResearchService (server, authoritative) and ResearchController (display only).

	Research is PERMANENT: PrestigeService never touches profile.Research, so bonuses keep applying after a
	Rebirth (the Lab resets, so buying NEW levels needs the Lab again). Cash only; prices here are read by the
	server — the client only displays payload.Costs.

	Gating: target level L needs Research Lab >= L (LabLevels overrides, e.g. Squad Expansion 2/4/5), and each
	track needs its building (Tracks[*].Requires). All effects are additive per level:
	  Kind "Mult": ResearchService.GetBonus(player, Stat) = 1 + Σ PerLevel × level   (always >= 1, bigger = stronger;
	               time-like stats divide by it, e.g. reload time = base ÷ mult)
	  Kind "Add" : ResearchService.GetAdd(player, Stat)   = Σ PerLevel × level        (>= 0)
	An upgrade whose game hook is missing ships with Enabled = false (card shows SOON, server refuses "Disabled").
	Full tree: $4,048,000.
]]

export type TrackDef = {
	Id: string,
	DisplayName: string,
	Order: number,
	Blurb: string,
	Requires: { StructureId: string, Level: number, Text: string, Short: string }?,
}

export type UpgradeDef = {
	Id: string,
	Track: string,
	Order: number,
	DisplayName: string,
	Badge: string,
	Stat: string, -- statId for ResearchService.GetBonus (Kind "Mult") / GetAdd (Kind "Add")
	Kind: string, -- "Mult" | "Add"
	PerLevel: number,
	MaxLevel: number,
	Costs: { number }, -- Cash for target level 1..MaxLevel (index = target level)
	LabLevels: { number }?, -- Research Lab level needed per target level; nil = target level
	EffectText: string, -- string.format(EffectText, FormatAmount(...)) e.g. "%s weapon damage"
	Note: string?,
	Enabled: boolean,
}

export type ResearchLock = { Code: string, Text: string } -- Code: "Disabled" | "Maxed" | "NeedStructure" | "NeedLab"

export type ResearchStatePayload = {
	LabLevel: number,
	Levels: { [string]: number }, -- EVERY upgrade id (0 = none)
	Costs: { [string]: number }, -- next-level Cash price; id absent when maxed
	Locks: { [string]: ResearchLock }, -- id present only when the next level is blocked for a non-cash reason
	Tracks: { [string]: ResearchLock }, -- track id present only when the whole track is locked
}

local ResearchConfig = {}

ResearchConfig.StructureId = "ResearchLab"

-- RequestResearch rate limits (per player): Buy taps and Sync requests. Over-limit taps are dropped with a
-- throttled toast — never an AntiExploit strike.
ResearchConfig.BuyRate = 2
ResearchConfig.BuyBurst = 4
ResearchConfig.SyncRate = 1
ResearchConfig.SyncBurst = 3

ResearchConfig.MaxMult = 3 -- sanity clamp on any Mult stat

ResearchConfig.Roman = { "I", "II", "III", "IV", "V" }

-- Also the WE_OpenTab values on Research Lab terminals.
ResearchConfig.TrackOrder = { "Weapons", "Soldiers", "Vehicles", "Defenses" }

ResearchConfig.StatIds = {
	"WeaponDamage",
	"WeaponFireRate",
	"WeaponMagazine",
	"WeaponReload",
	"SoldierHealth",
	"SoldierDamage",
	"VehicleSpeed",
	"VehicleArmor",
	"TurretDamage",
	"SquadSize",
}

ResearchConfig.Tracks = {
	Weapons = {
		Id = "Weapons",
		DisplayName = "Weapons",
		Order = 1,
		Blurb = "Upgrades every gun you carry.",
		Requires = nil,
	},
	Soldiers = {
		Id = "Soldiers",
		DisplayName = "Soldiers",
		Order = 2,
		Blurb = "Upgrades the squad that follows your orders.",
		Requires = {
			StructureId = "Barracks",
			Level = 1,
			Text = "Build the Barracks to unlock soldier research",
			Short = "NEEDS BARRACKS",
		},
	},
	Vehicles = {
		Id = "Vehicles",
		DisplayName = "Vehicles",
		Order = 3,
		Blurb = "Upgrades every vehicle you deploy.",
		Requires = {
			StructureId = "VehicleDepot",
			Level = 1,
			Text = "Build the Vehicle Depot to unlock vehicle research",
			Short = "NEEDS DEPOT",
		},
	},
	Defenses = {
		Id = "Defenses",
		DisplayName = "Defenses",
		Order = 4,
		Blurb = "Upgrades your gate guards and machine-gun nests.",
		Requires = {
			StructureId = "DefensiveWalls",
			Level = 1,
			Text = "Build Defensive Walls to unlock defense research",
			Short = "NEEDS WALLS",
		},
	},
} :: { [string]: TrackDef }

ResearchConfig.Upgrades = {
	-- ── Weapons (every gun the player carries; CombatService) ──────────────────────────────────────────
	Ballistics = {
		Id = "Ballistics",
		Track = "Weapons",
		Order = 1,
		DisplayName = "Ballistics",
		Badge = "DMG",
		Stat = "WeaponDamage",
		Kind = "Mult",
		PerLevel = 0.04,
		MaxLevel = 5,
		Costs = { 3000, 12000, 40000, 110000, 300000 },
		EffectText = "%s weapon damage",
		Enabled = true,
	},
	FireControl = {
		Id = "FireControl",
		Track = "Weapons",
		Order = 2,
		DisplayName = "Fire Control",
		Badge = "ROF",
		Stat = "WeaponFireRate",
		Kind = "Mult",
		PerLevel = 0.03,
		MaxLevel = 5,
		Costs = { 2500, 10000, 35000, 95000, 260000 },
		EffectText = "%s fire rate",
		Enabled = true,
	},
	ExtendedMags = {
		Id = "ExtendedMags",
		Track = "Weapons",
		Order = 3,
		DisplayName = "Extended Mags",
		Badge = "MAG",
		Stat = "WeaponMagazine",
		Kind = "Mult",
		PerLevel = 0.08,
		MaxLevel = 5,
		Costs = { 2000, 8000, 28000, 80000, 220000 },
		EffectText = "%s magazine size",
		Note = "Rockets and grenades stay single-shot",
		Enabled = true,
	},
	ReloadDrills = {
		Id = "ReloadDrills",
		Track = "Weapons",
		Order = 4,
		DisplayName = "Reload Drills",
		Badge = "RLD",
		Stat = "WeaponReload",
		Kind = "Mult",
		PerLevel = 0.06,
		MaxLevel = 5,
		Costs = { 2000, 8000, 28000, 80000, 220000 },
		EffectText = "%s reload speed",
		Enabled = true,
	},
	-- ── Soldiers (field squad; SquadOrdersService) ─────────────────────────────────────────────────────
	BodyArmor = {
		Id = "BodyArmor",
		Track = "Soldiers",
		Order = 1,
		DisplayName = "Body Armor",
		Badge = "HP",
		Stat = "SoldierHealth",
		Kind = "Mult",
		PerLevel = 0.10,
		MaxLevel = 5,
		Costs = { 2500, 10000, 32000, 90000, 240000 },
		EffectText = "%s squad health",
		Enabled = true,
	},
	MarksmanTraining = {
		Id = "MarksmanTraining",
		Track = "Soldiers",
		Order = 2,
		DisplayName = "Marksman Training",
		Badge = "AIM",
		Stat = "SoldierDamage",
		Kind = "Mult",
		PerLevel = 0.10,
		MaxLevel = 5,
		Costs = { 2500, 10000, 32000, 90000, 240000 },
		EffectText = "%s squad damage",
		Enabled = true,
	},
	SquadExpansion = {
		Id = "SquadExpansion",
		Track = "Soldiers",
		Order = 3,
		DisplayName = "Squad Expansion",
		Badge = "SQD",
		Stat = "SquadSize",
		Kind = "Add",
		PerLevel = 1,
		MaxLevel = 3,
		Costs = { 15000, 90000, 250000 },
		LabLevels = { 2, 4, 5 },
		EffectText = "%s soldiers in your field squad",
		Note = "Needs 1 recruited soldier per unit",
		Enabled = true,
	},
	-- ── Vehicles (VehicleService, vehicles workflow; read at deploy time) ──────────────────────────────
	EngineTuning = {
		Id = "EngineTuning",
		Track = "Vehicles",
		Order = 1,
		DisplayName = "Engine Tuning",
		Badge = "SPD",
		Stat = "VehicleSpeed",
		Kind = "Mult",
		PerLevel = 0.04,
		MaxLevel = 5,
		Costs = { 3000, 12000, 38000, 100000, 280000 },
		EffectText = "%s vehicle speed",
		Note = "Applies when you deploy a vehicle",
		Enabled = false -- v69: turned on together with the vehicles workflow (VehicleSpeed hook in VehicleService),
	},
	CompositeArmor = {
		Id = "CompositeArmor",
		Track = "Vehicles",
		Order = 2,
		DisplayName = "Composite Armor",
		Badge = "AMR",
		Stat = "VehicleArmor",
		Kind = "Mult",
		PerLevel = 0.08,
		MaxLevel = 5,
		Costs = { 3500, 14000, 45000, 120000, 320000 },
		EffectText = "%s vehicle armor",
		Note = "Your vehicles take less damage",
		-- OFF until vehicles can take damage: VehicleService only stores WE_ArmorMult and nothing reads it, so
		-- a level would be a paid no-op (spec §7). Turn on once vehicle damage divides by WE_ArmorMult.
		Enabled = false,
	},
	-- ── Defenses (GateDefenseService, raids/defenses workflow) ─────────────────────────────────────────
	TargetingSystems = {
		Id = "TargetingSystems",
		Track = "Defenses",
		Order = 1,
		DisplayName = "Targeting Systems",
		Badge = "DEF",
		Stat = "TurretDamage",
		Kind = "Mult",
		PerLevel = 0.08,
		MaxLevel = 5,
		Costs = { 3000, 12000, 40000, 110000, 300000 },
		EffectText = "%s gate guard and auto-gun damage",
		Enabled = true,
	},
} :: { [string]: UpgradeDef }

--[[ Upgrades of one track sorted by Order (disabled ones included — the card shows SOON). ]]
function ResearchConfig.UpgradesForTrack(trackId: string): { UpgradeDef }
	local out: { UpgradeDef } = {}
	if typeof(trackId) ~= "string" then
		return out
	end
	for _, def in pairs(ResearchConfig.Upgrades) do
		if def.Track == trackId then
			table.insert(out, def)
		end
	end
	table.sort(out, function(a: UpgradeDef, b: UpgradeDef): boolean
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Id < b.Id
	end)
	return out
end

--[[ Owned level of an upgrade from a profile.Research table. Junk (non-table research, non-number / NaN
	level, unknown id) → 0; otherwise floor, clamped to 0..MaxLevel. ]]
function ResearchConfig.LevelOf(research: any, id: string): number
	if typeof(research) ~= "table" or typeof(id) ~= "string" then
		return 0
	end
	local def = ResearchConfig.Upgrades[id]
	if def == nil then
		return 0
	end
	local v = rawget(research, id)
	if typeof(v) ~= "number" or v ~= v then
		return 0
	end
	return math.clamp(math.floor(v), 0, def.MaxLevel)
end

--[[ Research Lab level needed to buy `targetLevel` of `def`. ]]
function ResearchConfig.LabLevelFor(def: UpgradeDef, targetLevel: number): number
	if typeof(def) ~= "table" then
		return targetLevel
	end
	local labLevels = def.LabLevels
	if labLevels ~= nil and typeof(labLevels) == "table" then
		local v = labLevels[targetLevel]
		if typeof(v) == "number" then
			return v
		end
	end
	return targetLevel
end

--[[ 1 + Σ PerLevel × level over Kind "Mult" upgrades of `statId`, clamped to [1, MaxMult]. ]]
function ResearchConfig.MultFor(research: any, statId: string): number
	if typeof(research) ~= "table" or typeof(statId) ~= "string" then
		return 1
	end
	local sum = 0
	for id, def in pairs(ResearchConfig.Upgrades) do
		if def.Kind == "Mult" and def.Stat == statId then
			sum += def.PerLevel * ResearchConfig.LevelOf(research, id)
		end
	end
	local m = 1 + sum
	if m ~= m then
		return 1
	end
	return math.clamp(m, 1, ResearchConfig.MaxMult)
end

--[[ Σ PerLevel × level over Kind "Add" upgrades of `statId` (>= 0). ]]
function ResearchConfig.AddFor(research: any, statId: string): number
	if typeof(research) ~= "table" or typeof(statId) ~= "string" then
		return 0
	end
	local sum = 0
	for id, def in pairs(ResearchConfig.Upgrades) do
		if def.Kind == "Add" and def.Stat == statId then
			sum += def.PerLevel * ResearchConfig.LevelOf(research, id)
		end
	end
	if sum ~= sum or sum < 0 then
		return 0
	end
	return sum
end

--[[ Upgraded magazine: single-shot weapons (base <= 1: rockets, grenades) stay as they are; otherwise
	round(base × mult), never below base. ]]
function ResearchConfig.EffectiveMagazine(base: number, mult: number): number
	if typeof(base) ~= "number" or base ~= base then
		return 0
	end
	if base <= 1 then
		return base
	end
	local m = if typeof(mult) == "number" and mult == mult then math.clamp(mult, 1, ResearchConfig.MaxMult) else 1
	return math.max(base, math.floor(base * m + 0.5))
end

--[[ "+12%" (Mult) or "+2" (Add) for `level` levels of `def`. ]]
function ResearchConfig.FormatAmount(def: UpgradeDef, level: number): string
	if typeof(def) ~= "table" or typeof(def.PerLevel) ~= "number" then
		return ""
	end
	local lv = if typeof(level) == "number" and level == level then level else 0
	if def.Kind == "Add" then
		return "+" .. tostring(def.PerLevel * lv)
	end
	return string.format("+%d%%", math.floor(def.PerLevel * lv * 100 + 0.5))
end

--[[ "+12% weapon damage" ]]
function ResearchConfig.FormatEffect(def: UpgradeDef, level: number): string
	if typeof(def) ~= "table" or typeof(def.EffectText) ~= "string" then
		return ""
	end
	local ok, s = pcall(string.format, def.EffectText, ResearchConfig.FormatAmount(def, level))
	if ok and typeof(s) == "string" then
		return s
	end
	return ResearchConfig.FormatAmount(def, level)
end

--[[ "$12,000" (comma thousands, floored). ]]
function ResearchConfig.FormatCash(n: number): string
	local v = if typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge then math.floor(n) else 0
	local neg = v < 0
	local digits = string.format("%d", math.abs(v))
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if neg then "-$" else "$") .. out
end

return ResearchConfig
