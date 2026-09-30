--!strict
--[[
	claude-bud JOB 39 (2026-09-30): ENDGAME PROGRESSION ("always a next goal"), docs/claude-queue/JOB39-endgame-progression.md.
	Owner-first (Live: Enabled + OwnerFirst = true -> UserId 470626172 and Studio). Every system also has its own Parts
	switch, turned on phase by phase (§10). Live.Enabled = false (or a Part false) = today's game exactly: nothing reads
	profile.Endgame, prices are the raw BaseConfig tables and cashMultFor has no Empire factor.

	Phase 1 (this build): Rebirth (the base / business price grows with rebirths) + EmpireLevel (the long +2 %/level
	cash track, bought at the Command Office in the plaza). The later systems' numbers are here already (config
	first); their Parts stay false until their phase ships.

	Pure helpers (no Instances, no services): LiveFor, EmpireCost, EmpireMult, DefenceCost, WorkshopCost, MasteryCost,
	IncomeMinutesPrice, RebirthCostScale, ScaleStructureCost, LifeCost, BlackMarketStock, WeekIndex.
	Every price stays below EconomyConfig.MaxCash (1,000,000,000): tools/sim/run_endgame_test.py checks it.
]]

local RetentionConfig = require(script.Parent.RetentionConfig)
local BaseConfig = require(script.Parent.BaseConfig)

local EndgameConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = true, -- only UserId 470626172 (+ Studio test players) until Code Bot sets false = everyone
	},
	-- one switch per system (§4); a phase turns its own on
	Parts = {
		Rebirth = true, -- phase 1: §2.1 the base price scale
		EmpireLevel = true, -- phase 1: §2.2 + the Command Office
		BaseTier = true, -- phase 2: §2.3 + the HQ UPGRADE console
		Defence = true, -- phase 2: §2.5 + the Engineering Bureau + instant rebuild
		Elite = true, -- phase 3: §2.4 + the Recruitment Office + re-train fees
		Hospital = false, -- phase 4
		Mastery = false, -- phase 4
		Workshop = false, -- phase 4
		Warheads = false, -- phase 5
		Heist = false, -- phase 5
		Contracts = false, -- phase 5
		BlackMarket = false, -- phase 5
		RewardScaling = false, -- phase 5
	} :: { [string]: boolean },

	-- §2.1 price(structure or business, level) = Costs[level] x (1 + 0.20 x min(rebirths, 20)). Income is unchanged
	-- (BalanceConfig.StructureIncomePerTick reads the raw Costs). Rebirth-zone structures (def.Zone) and Gold-priced
	-- rows are kept through rebirth, so they are never scaled.
	Rebirth = {
		CostScalePerRebirth = 0.20,
		CostScaleMaxRebirths = 20,
	},

	-- §2.2 EMPIRE LEVEL: 1..30 in order, kept through both rebirth paths. Cost(L) = round(5M x 1.17^(L-1), to 100k).
	Empire = {
		MaxLevel = 30,
		BaseCost = 5_000_000,
		Growth = 1.17,
		RoundTo = 100_000,
		CashPctPerLevel = 2, -- +2 % cash per level on non-exempt reasons (its own factor in cashMultFor)
		-- the cosmetic milestone every 5 levels (StarLevel / MarshalLevel show on the base sign in phase 1)
		StarLevel = 5,
		MarshalLevel = 30,
		MarshalTitle = "Empire Marshal",
		Milestones = {
			[5] = "Gold star on your base sign",
			[10] = "Gate banner",
			[15] = "HQ roof flag",
			[20] = "Nameplate chevron",
			[25] = "Gold flag finial",
			[30] = "Empire Marshal title",
		} :: { [number]: string },
	},

	-- §2.3 BASE TIER (phase 2)
	BaseTier = {
		Tiers = {
			{ Name = "Fort", Cost = 10_000_000, NeedRebirths = 2, NeedCC = 5, GateHpPct = 10, SoldierCap = 5 },
			{ Name = "Citadel", Cost = 25_000_000, NeedRebirths = 3, GateHpPct = 10, AutoGunNests = 1 },
			{ Name = "Stronghold", Cost = 60_000_000, NeedRebirths = 5, RebuildSeconds = -10, SoldierCap = 5 },
			{ Name = "Bastion", Cost = 150_000_000, NeedRebirths = 8, GateHpPct = 10, AutoGunNests = 1 },
			{ Name = "Capital", Cost = 400_000_000, NeedRebirths = 12, SoldierCap = 10 },
		} :: { any },
		MaxPartsPerTier = 120,
		MaxLightsPerTier = 2,
		NestExtraX = 9, -- an extra AutoGun nest stands this far past the outer gate gun (T2 left, T4 right)
		MinRebuildSeconds = 10, -- the gate never rebuilds faster than this (T3 -10 s, Gate track -3 s / level)
	},

	-- §2.4 ELITE TRAINING (phase 3)
	Elite = {
		Types = { "Infantry", "Heavy", "SpecialForces" },
		Tiers = {
			{ Name = "Veteran", Cost = 2_000_000, RetrainFee = 5_000, Scale = 1.05 },
			{ Name = "Elite", Cost = 8_000_000, RetrainFee = 15_000, Scale = 1.10 },
			{ Name = "Legendary", Cost = 30_000_000, RetrainFee = 40_000, Scale = 1.18 },
			{ Name = "Mythic", Cost = 100_000_000, RetrainFee = 100_000, Scale = 1.28, NeedRebirths = 30 },
		},
		PctPerTier = 8, -- +8 % HP and damage per tier
		HeavyEvery = 5, -- every 5th field slot is Heavy (+20 % HP) ...
		SpecialForcesEvery = 10, -- ... every 10th Special Forces (+10 % damage) once the SF Facility is L3+
		SpecialForcesNeedFacility = 3,
		HeavyHpMult = 1.2,
		SpecialForcesDmgMult = 1.1,
		Names = { Infantry = "Infantry", Heavy = "Heavy", SpecialForces = "Special Forces" } :: { [string]: string },
		-- the tier look: helmet trim colour, chevrons (4 = the Mythic star), the Mythic aura (client, quality >= 4)
		Trim = { Color3.fromRGB(150, 154, 160), Color3.fromRGB(70, 150, 70), Color3.fromRGB(214, 178, 64), Color3.fromRGB(28, 26, 22) },
		TrimAccent = Color3.fromRGB(214, 178, 64),
		MaxFreeRetrains = 200,
	},

	-- §2.5 DEFENCE TREE (phase 2): Cost(L) = round(1M x 1.6^(L-1), to 100k)
	Defence = {
		Tracks = { "Plating", "Guns", "Gate", "Vault" },
		MaxLevel = 10,
		BaseCost = 1_000_000,
		Growth = 1.6,
		RoundTo = 100_000,
		NeedTier = { [5] = 1, [6] = 1, [7] = 2, [8] = 2, [9] = 3, [10] = 4 } :: { [number]: number },
		PlatingPct = 15,
		GunsPct = 6,
		GatePct = 12,
		GateRebuildPerLevel = 3,
		VaultArmyPerLevel = 0.05, -- army loot x (1 - 0.05 x L): L10 = 2.5 %
		VaultAtmPerLevel = 0.03, -- ATM raid x (1 - 0.03 x L): L10 = 7 %
		InstantRebuildSeconds = 30,
		InstantRebuildMin = 25_000,
	},

	-- §2.6 VEHICLE WORKSHOP (phase 4): Cost(L) = 1M x 2.2^(L-1)
	Workshop = {
		Classes = { "Ground", "Air", "Naval" },
		MaxLevel = 5,
		BaseCost = 1_000_000,
		Growth = 2.2,
		RoundTo = 100_000,
		HpPct = 6,
		SpeedPct = 3,
	},

	-- §2.7 SUPER-WEAPONS (phase 5)
	Warheads = {
		Tactical = { Cost = 5_000_000, NeedRebirths = 2 },
		Heavy = { Cost = 25_000_000, NeedRebirths = 25, RadiusMult = 1.3, DamageMult = 1.2, Hold = 1 },
	},

	-- §2.8 HOSPITAL (phase 4)
	Hospital = {
		HealCooldown = 60,
		MedKit = { Max = 3, Heal = 50, Seconds = 3, Floor = 25_000, IncomeSeconds = 30 },
		Medicine = { Costs = { 2_000_000, 5_000_000, 12_000_000, 30_000_000, 75_000_000 }, HpPerLevel = 10, MedicLevel = 3 },
		Revive = { Floor = 250_000, IncomeSeconds = 180, WithinSeconds = 10, HpFraction = 0.5 },
		MaxEffectiveHp = 400,
	},

	-- §2.9 MASTERY + ATTACHMENTS + CAMOS (phase 4): Cost = TierBase x 2^(L-1)
	Mastery = {
		MaxLevel = 5,
		TierBase = { Shop = 1_000_000, Rebirth = 2_000_000, Premium = 3_000_000 },
		PerLevel = { DamagePct = 3, RatePct = 2, RangePct = 4, MagPct = 6, ReloadPct = -5 },
		Attachments = {
			RedDot = { Cost = 1_000_000, RangePct = 10 },
			Grip = { Cost = 1_500_000, SpreadPct = -15 },
			ExtendedMag = { Cost = 2_000_000, MagPct = 25 },
			Suppressor = { Cost = 3_000_000 },
		},
		Camos = { Olive = 50, Urban = 100, Tiger = 150, Gold = 250 } :: { [string]: number },
	},

	-- §2.10 BLACK MARKET (phase 5): Monday 00:00 UTC weeks, the same stock on every server
	BlackMarket = {
		EpochMondayUnix = 345600, -- 1970-01-05 00:00 UTC, a Monday
		Slots = {
			{ Minutes = 20, Floor = 1_000_000 },
			{ Minutes = 45, Floor = 3_000_000 },
			{ Minutes = 90, Floor = 8_000_000 },
		},
		Pool = { "PaintSand", "PaintNight", "PaintArctic", "BannerStripes", "BannerChevron", "BeretRed", "BeretBlue", "CamoUrban", "CamoTiger", "TrophyCannon" },
		GoldPool = { "CamoGold", "BeretGold", "BannerGold" },
		GoldPrices = { 100, 150, 250 },
	},

	-- §2.11 CONTRACTS (phase 5)
	Contracts = { Daily = 3, Floor = 50_000, Minutes = 8, HvtMinutes = 20, HvtGold = 50, ScoutMinutes = 1, RaidedByKeep = 5 },

	-- §2.12 HEIST (phase 5)
	Heist = {
		Kits = {
			{ Name = "Drill", Cost = 2_000_000, Minutes = 4, Floor = 35_000, Guards = 3, Hold = 8 },
			{ Name = "Thermal Lance", Cost = 8_000_000, Minutes = 8, Floor = 35_000, Guards = 5, Hold = 10 },
			{ Name = "Vault Cracker", Cost = 25_000_000, Minutes = 15, Floor = 35_000, Guards = 7, Hold = 14, Cooldown = 1800 },
		},
		BountyMinutes = 3,
		BountyFloor = 15_000,
	},

	-- the plaza stations (PlazaServicesConfig says where); these are the server's rules for all of them
	Station = {
		BuyRange = 16, -- the server's reach check (the prompt is 12; a little slack for latency)
		HurtLockSeconds = 6, -- = HudConfig.Health.RecentCombatSeconds: no buying just after taking damage
		RatePerSec = 2,
		Burst = 4,
		CloseRange = 22, -- the client closes the panel when you walk this far from the station
	},

	Text = {
		EmpireBought = "EMPIRE %d!  +%d%% cash",
		NotHere = "Go to the Command Office in the plaza",
		Hurt = "You're in combat",
		TierBought = "BASE TIER %d: %s!",
		DefenceBought = "%s level %d!",
		Rebuilt = "Defences rebuilt",
		NothingDown = "Nothing to rebuild",
		NotAtHQ = "Use the HQ console at your base",
		NeedTier = "Needs Base Tier %d",
		NeedRebirths = "Needs %d rebirths",
		NeedCC = "Needs Command Center L%d",
		EliteBought = "%s trained: %s!",
		Retrained = "Soldiers re-trained",
		RetrainShort = "%d soldier(s) back untrained: re-train at the Recruitment Office",
		Short = "Need $%s",
		Max = "Empire Level maxed",
		NotLive = "Not open yet",
	},
}

function EndgameConfig.LiveFor(userId: any, part: string): boolean
	local parts: any = EndgameConfig.Parts
	return parts[part] == true and RetentionConfig.Live(EndgameConfig.Live, userId)
end

-- true when any part is live for this player (the client's stations and panels)
function EndgameConfig.AnyLiveFor(userId: any): boolean
	if not RetentionConfig.Live(EndgameConfig.Live, userId) then
		return false
	end
	for _, on in pairs(EndgameConfig.Parts) do
		if on == true then
			return true
		end
	end
	return false
end

-- round to the nearest `step`, halves to the even step (the spec's tables: 5M x 1.17 = 5.85M -> 5.8M)
local function roundTo(x: number, step: number): number
	local q = x / step
	local f = math.floor(q)
	local d = q - f
	if d > 0.5 + 1e-9 or (math.abs(d - 0.5) <= 1e-9 and f % 2 == 1) then
		f += 1
	end
	return f * step
end

local function level(n: any): number
	local v = tonumber(n) or 0
	if v ~= v then
		return 0
	end
	return math.max(0, math.floor(v))
end

-- the price of Empire Level L (1..MaxLevel); nil outside the track
function EndgameConfig.EmpireCost(L: number): number?
	local E = EndgameConfig.Empire
	local l = level(L)
	if l < 1 or l > E.MaxLevel then
		return nil
	end
	return roundTo(E.BaseCost * E.Growth ^ (l - 1), E.RoundTo)
end

-- the Empire cash factor at level L: 1 + 2 % x L (L30 = 1.60)
function EndgameConfig.EmpireMult(L: number): number
	local E = EndgameConfig.Empire
	local l = math.min(level(L), E.MaxLevel)
	return 1 + l * E.CashPctPerLevel / 100
end

function EndgameConfig.DefenceCost(L: number): number?
	local D = EndgameConfig.Defence
	local l = level(L)
	if l < 1 or l > D.MaxLevel then
		return nil
	end
	return roundTo(D.BaseCost * D.Growth ^ (l - 1), D.RoundTo)
end

function EndgameConfig.WorkshopCost(L: number): number?
	local W = EndgameConfig.Workshop
	local l = level(L)
	if l < 1 or l > W.MaxLevel then
		return nil
	end
	return roundTo(W.BaseCost * W.Growth ^ (l - 1), W.RoundTo)
end

function EndgameConfig.MasteryCost(tierBase: number, L: number): number?
	local l = level(L)
	if l < 1 or l > EndgameConfig.Mastery.MaxLevel then
		return nil
	end
	return math.floor(tierBase * 2 ^ (l - 1))
end

-- max(floor, N minutes of YOUR passive income) (perSec = WE_IncomePerSec)
function EndgameConfig.IncomeMinutesPrice(floor: number, minutes: number, perSec: number): number
	local ps = tonumber(perSec) or 0
	if ps ~= ps or ps < 0 then
		ps = 0
	end
	return math.max(math.floor(floor), math.floor(minutes * 60 * ps))
end

-- §2.1 the price factor for a player with `rebirths` rebirths: 1 + 0.20 x min(p, 20)
function EndgameConfig.RebirthCostScale(rebirths: number): number
	local R = EndgameConfig.Rebirth
	return 1 + R.CostScalePerRebirth * math.min(level(rebirths), R.CostScaleMaxRebirths)
end

-- a structure / business price after the scale (zone and Gold rows are never scaled; scale 1 = the raw price)
function EndgameConfig.ScaleStructureCost(structureId: string, cost: number, scale: number): number
	local s = tonumber(scale) or 1
	if s == 1 or s ~= s or s < 1 then
		return cost
	end
	local def: any = (BaseConfig.Structures :: any)[structureId]
	if def == nil or def.Zone ~= nil or def.Currency == "Gold" then
		return cost
	end
	return math.floor(cost * s + 0.5)
end

-- what one life (every scaled structure and business, level 1 to max) costs at `scale`
function EndgameConfig.LifeCost(scale: number): number
	local total = 0
	for id, def in pairs(BaseConfig.Structures :: any) do
		if typeof(def) == "table" and def.Zone == nil and def.Currency ~= "Gold" and typeof(def.Costs) == "table" then
			for i = 1, math.min(def.MaxLevel or #def.Costs, #def.Costs) do
				total += EndgameConfig.ScaleStructureCost(id, tonumber(def.Costs[i]) or 0, scale)
			end
		end
	end
	return total
end

-- §2.3 the summed Base Tier effects for tier t (1..5): gate HP %, soldier cap, AutoGun nests, rebuild seconds
function EndgameConfig.TierEffects(t: number): { GateHpPct: number, SoldierCap: number, Nests: number, RebuildSeconds: number }
	local out = { GateHpPct = 0, SoldierCap = 0, Nests = 0, RebuildSeconds = 0 }
	local tiers: any = EndgameConfig.BaseTier.Tiers
	for i = 1, math.min(level(t), #tiers) do
		local r = tiers[i]
		out.GateHpPct += tonumber(r.GateHpPct) or 0
		out.SoldierCap += tonumber(r.SoldierCap) or 0
		out.Nests += tonumber(r.AutoGunNests) or 0
		out.RebuildSeconds += tonumber(r.RebuildSeconds) or 0
	end
	return out
end

-- §2.4 one soldier type's multipliers at a training tier (0 = untrained): HP, damage, rig scale
function EndgameConfig.EliteStats(kind: string, tier: number): { Hp: number, Dmg: number, Scale: number }
	local El = EndgameConfig.Elite
	local t = math.clamp(level(tier), 0, #El.Tiers)
	local m = 1 + El.PctPerTier * t / 100
	local hp = m * (if kind == "Heavy" then El.HeavyHpMult else 1)
	local dmg = m * (if kind == "SpecialForces" then El.SpecialForcesDmgMult else 1)
	local row: any = El.Tiers[t]
	return { Hp = hp, Dmg = dmg, Scale = if row then tonumber(row.Scale) or 1 else 1 }
end

-- §2.4 the field slot's soldier type
function EndgameConfig.SlotKind(slot: number, sfFacilityLevel: number): string
	local El = EndgameConfig.Elite
	local s = level(slot)
	if s > 0 and s % El.SpecialForcesEvery == 0 and level(sfFacilityLevel) >= El.SpecialForcesNeedFacility then
		return "SpecialForces"
	elseif s > 0 and s % El.HeavyEvery == 0 then
		return "Heavy"
	end
	return "Infantry"
end

-- §2.5 the Base Tier a Defence level needs (0 = none)
function EndgameConfig.DefenceNeedTier(L: number): number
	return tonumber((EndgameConfig.Defence.NeedTier :: any)[level(L)]) or 0
end

-- §2.10 the week number since the first Monday 00:00 UTC (every server agrees)
function EndgameConfig.WeekIndex(unix: number): number
	return math.floor((unix - EndgameConfig.BlackMarket.EpochMondayUnix) / 604800)
end

-- §2.10 this week's stock: 3 Cash item ids and 1 Gold item, a pure function of the week (no randomness state)
function EndgameConfig.BlackMarketStock(week: number): { Cash: { string }, Gold: string, GoldPrice: number }
	local B = EndgameConfig.BlackMarket
	local w = math.floor(tonumber(week) or 0)
	local pool = B.Pool
	local n = #pool
	local out: { string } = {}
	local start = (w * 7) % n
	local stride = 3 -- coprime with the pool size (10), so 3 picks never repeat
	for i = 0, #B.Slots - 1 do
		table.insert(out, pool[((start + i * stride) % n) + 1])
	end
	local gi = (w % #B.GoldPool) + 1
	return { Cash = out, Gold = B.GoldPool[gi], GoldPrice = B.GoldPrices[gi] or B.GoldPrices[1] }
end

return EndgameConfig
