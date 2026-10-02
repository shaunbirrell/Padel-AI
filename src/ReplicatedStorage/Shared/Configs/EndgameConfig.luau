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
	Every price stays below EconomyConfig.MaxCash (1e15; was 1,000,000,000 before Code Bot v194): tools/sim/run_endgame_test.py checks it.
]]

local RetentionConfig = require(script.Parent.RetentionConfig)
local BaseConfig = require(script.Parent.BaseConfig)

local EndgameConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = false, -- codebot_v166 flip-all-live (owner 2026-10-01 10:31): everyone (every endgame part)
	},
	-- Code Bot v157 (owner-approved 2026-10-01): a part listed here is live for EVERY player while Live.OwnerFirst keeps
	-- every other part owner-only. It still needs Live.Enabled and its own Parts switch (either false = off for all).
	PublicParts = {
		BlackMarket = true, -- the weekly Black Market (cosmetics only; Cash + Gold, never Robux)
	} :: { [string]: boolean },
	-- one switch per system (§4); a phase turns its own on
	Parts = {
		Rebirth = true, -- phase 1: §2.1 the base price scale
		EmpireLevel = true, -- phase 1: §2.2 + the Command Office
		BaseTier = true, -- phase 2: §2.3 + the HQ UPGRADE console
		Defence = true, -- phase 2: §2.5 + the Engineering Bureau + instant rebuild
		Elite = true, -- phase 3: §2.4 + the Recruitment Office + re-train fees
		Hospital = true, -- phase 4: §2.8 the Field Hospital (heal, Med Kits, Combat Medicine, Field Surgeon, army medic)
		Mastery = true, -- phase 4: §2.9 the Armory Workshop (mastery, attachments, camos)
		Workshop = true, -- phase 4: §2.6 the Vehicle Workshop (the Vehicle Depot console)
		Warheads = true, -- phase 5: §2.7 Tactical / Heavy Warheads at the Nuclear Silo
		Heist = true, -- phase 5: §2.12 the bank heist kits + the Fixer's desk
		Contracts = true, -- phase 5: §2.11 the Intel Office (daily contracts, the weekly HVT, scouting, raided-by)
		BlackMarket = true, -- phase 5: §2.10 the weekly Black Market (cosmetics only; Cash + Gold, never Robux)
		RewardScaling = true, -- phase 5: the plaza bounty scales with income
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
	-- claude-bud JOB 55: honest Defence text + the exploit fixes, keyed by the BASE OWNER (OFF = the old rules / text):
	--   * Turret Plating needs Walls L<AutoGunMinWallsLevel> (no turrets before that: it did nothing)
	--   * Turret Guns also arms the gate / tower guards (the text said "turret damage"; the post guards had it, the gate
	--     and tower guards did not)
	--   * the text names what each track really does (the gate guards' HP comes from Gate & Walls; walls have no HP)
	--   * a mid-raid Defence purchase keeps the gate's / turrets' damage (it used to rebuild them at full HP)
	DefenceFix = {
		Enabled = true,
		OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST (claude-bud JOB 55): Code Bot flips it after Shaun's phone test
	},
	-- claude-bud JOB 53: the Defence levels you can SEE (Server/Modules/DefenceVisuals). Visual tier by level: TierAt[t]
	-- is the first level of tier t (L1-3 = 1, L4-6 = 2, L7-9 = 3, L10 = 4). Gate damage states at DamageStages (HP
	-- fraction). OFF = no visuals, the gate's old look exactly.
	DefenceVisuals = {
		Enabled = true,
		OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST (claude-bud JOB 53): Code Bot flips it after Shaun's phone test
		TierAt = { 1, 4, 7, 10 },
		DamageStages = { 0.6, 0.3 }, -- <= 60 %: dents + scorch; <= 30 %: sagging bands + smoke
		SmokeRate = 4, -- one capped emitter on the gate at <= 30 % / breached
		MaxParts = { Turret = 12, Gate = 30, Vault = 12 }, -- per piece (the budget test)
	},

	-- §2.6 VEHICLE WORKSHOP (phase 4): Cost(L) = 1M x 2.2^(L-1)
	Workshop = {
		Classes = { "Ground", "Air", "Naval" },
		PlateLevel = 3, -- bolt-on armour plates from this level
		TrimLevel = 5, -- the gold nameplate trim at this level
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
		CamoOrder = { "Olive", "Urban", "Tiger", "Gold" },
		-- a camo recolours the gun's body parts: base colour + the second tone on every other part (Tiger / Urban)
		CamoLook = {
			Olive = { A = Color3.fromRGB(86, 96, 60), B = Color3.fromRGB(70, 80, 50), Mat = "Fabric" },
			Urban = { A = Color3.fromRGB(128, 132, 138), B = Color3.fromRGB(72, 76, 82), Mat = "Fabric" },
			Tiger = { A = Color3.fromRGB(196, 140, 60), B = Color3.fromRGB(40, 36, 30), Mat = "Fabric" },
			Gold = { A = Color3.fromRGB(214, 178, 64), B = Color3.fromRGB(190, 150, 50), Mat = "Metal" },
		} :: { [string]: { A: Color3, B: Color3, Mat: string } },
		SlotNames = { RedDot = "Red-dot sight", Grip = "Grip", ExtendedMag = "Extended Mag", Suppressor = "Suppressor" } :: { [string]: string },
		AttachOrder = { "RedDot", "Grip", "ExtendedMag", "Suppressor" },
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
		-- every item is cosmetic (never power): Kind = what it recolours / adds; one of each per player
		Items = {
			PaintSand = { Name = "Desert Sand paint", Kind = "Paint", Color = Color3.fromRGB(196, 170, 120) },
			PaintNight = { Name = "Night Ops paint", Kind = "Paint", Color = Color3.fromRGB(40, 44, 52) },
			PaintArctic = { Name = "Arctic paint", Kind = "Paint", Color = Color3.fromRGB(220, 226, 230) },
			BannerStripes = { Name = "Striped banners", Kind = "Banner", Color = Color3.fromRGB(150, 40, 36) },
			BannerChevron = { Name = "Chevron banners", Kind = "Banner", Color = Color3.fromRGB(30, 60, 110) },
			BannerGold = { Name = "Gold banners", Kind = "Banner", Color = Color3.fromRGB(214, 178, 64) },
			BeretRed = { Name = "Red berets", Kind = "Beret", Color = Color3.fromRGB(150, 30, 30) },
			BeretBlue = { Name = "Blue berets", Kind = "Beret", Color = Color3.fromRGB(30, 60, 140) },
			BeretGold = { Name = "Gold berets", Kind = "Beret", Color = Color3.fromRGB(214, 178, 64) },
			CamoUrban = { Name = "Urban camo", Kind = "Camo", Camo = "Urban" },
			CamoTiger = { Name = "Tiger camo", Kind = "Camo", Camo = "Tiger" },
			CamoGold = { Name = "Gold camo", Kind = "Camo", Camo = "Gold" },
			TrophyCannon = { Name = "Trophy cannon", Kind = "Trophy" },
		} :: { [string]: any },
	},

	-- §2.11 CONTRACTS (phase 5)
	Contracts = {
		Daily = 3,
		Floor = 50_000,
		Minutes = 8,
		HvtMinutes = 20,
		HvtGold = 50,
		ScoutMinutes = 1,
		ScoutFloor = 10_000,
		RaidedByKeep = 5,
		-- the pool: Kind = the event that counts (EndgameService.NoteContract), Need = how many
		Pool = {
			{ Kind = "Garrison", Need = 2, Text = "Clear %d site garrisons" },
			{ Kind = "Outpost", Need = 2, Text = "Capture %d outposts" },
			{ Kind = "CheckpointGuard", Need = 10, Text = "Kill %d checkpoint guards" },
			{ Kind = "DefendRaid", Need = 1, Text = "Defend your base from a raid" },
			{ Kind = "WinSend", Need = 1, Text = "Win a SEND ARMY raid" },
			{ Kind = "Warhead", Need = 1, Text = "Launch a warhead" },
		},
		Hvt = {
			{ Kind = "WinSend", Need = 3, Text = "HIGH-VALUE: win %d SEND ARMY raids" },
			{ Kind = "Outpost", Need = 6, Text = "HIGH-VALUE: capture %d outposts" },
			{ Kind = "Garrison", Need = 6, Text = "HIGH-VALUE: clear %d site garrisons" },
		},
		DayEpochUnix = 0, -- days are UTC days (os.time() // 86400)
	},

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
		--[[ claude-bud JOB A (2026-10-01, P0 "the Recruitment Office closes by itself ~0.5 s after it opens"): the
			Recruitment Office opens from TWO interaction points: the plaza NPC (prompt 12 studs) and the DRILL kiosk on
			the player's own Elite Barracks zone (prompt 10 studs, JOB 46). The walk-away close is measured from the
			point it was OPENED from, with hysteresis: open inside the prompt range, close only past RecruitCloseRange. ]]
		RecruitCloseRange = 17,
	},

	Text = {
		EmpireBought = "EMPIRE %d!  +%d%% cash",
		NotHere = "Go to the Command Office in the plaza",
		Hurt = "You're in combat",
		TierBought = "BASE TIER %d: %s!",
		DefenceBought = "%s level %d!",
		DefenceNewLook = "New on your base: %s", -- claude-bud JOB 53 (a new visual tier)
		NeedWalls = "Needs Walls L%d (turrets)", -- claude-bud JOB 55: Turret Plating before the turrets exist
		GateName = "Gate Armour", -- claude-bud JOB 55: "Gate & Walls" promised walls; walls have no HP
		DefenceLook = { -- claude-bud JOB 53: what each visual tier adds (DefenceVisuals), short for a phone toast
			Plating = { "turret side plates", "turret front shields", "dark steel turret armour", "gold-edged turret armour" },
			Guns = { "ammo crates", "a shell rack", "heavy ammo boxes", "belt-fed guns" },
			Gate = { "steel gate bands", "gate corner plates", "gate braces", "a gold gate beam" },
			Vault = { "vault brackets", "vault side plates", "a vault cage", "a vault armour cap" },
		},
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

-- claude-bud JOB 53: the visual tier (0..4) of a Defence level (pure)
function EndgameConfig.DefenceVisualTier(level: number): number
	local at: any = EndgameConfig.DefenceVisuals.TierAt
	local t = 0
	for i, l in ipairs(at) do
		if (tonumber(level) or 0) >= l then
			t = i
		end
	end
	return t
end

-- claude-bud JOB 53: the gate's damage stage (pure): 0 clean, 1 <= 60 %, 2 <= 30 %, 3 breached
function EndgameConfig.GateDamageStage(frac: number, breached: boolean): number
	if breached then
		return 3
	end
	local st: any = EndgameConfig.DefenceVisuals.DamageStages
	local f = tonumber(frac) or 1
	if f <= st[2] then
		return 2
	elseif f <= st[1] then
		return 1
	end
	return 0
end

-- claude-bud JOB 55: the honest Defence rules on for this base owner (the Defence tree live AND the fix flag)
function EndgameConfig.DefenceFixLive(userId: any): boolean
	return EndgameConfig.LiveFor(userId, "Defence") and RetentionConfig.Live(EndgameConfig.DefenceFix, userId)
end

-- claude-bud JOB 55: the HP after a max-HP change that must NOT heal (a mid-raid Defence buy): the damage already taken
-- stays (new max - damage, at least 1); a broken thing (hp <= 0: a breached gate, a dead turret) stays broken (pure)
function EndgameConfig.KeepDamage(oldMax: number, oldHp: number, newMax: number): number
	if oldHp <= 0 then
		return 0
	end
	return math.clamp(newMax - (oldMax - oldHp), 1, newMax)
end

-- claude-bud JOB 55: what a Defence track gives at level L, honestly (pure; the Engineering Bureau rows + tests)
function EndgameConfig.DefenceText(track: string, L: number): string
	local D = EndgameConfig.Defence
	if track == "Plating" then
		return string.format("+%d%% turret HP", D.PlatingPct * L)
	elseif track == "Guns" then
		return string.format("+%d%% turret + guard dmg", D.GunsPct * L)
	elseif track == "Gate" then
		return string.format("+%d%% gate + guard HP, -%d s rebuild", D.GatePct * L, D.GateRebuildPerLevel * L)
	end
	return string.format("-%d%% ATM, -%d%% army raid loot", math.floor(D.VaultAtmPerLevel * L * 100 + 0.5), math.floor(D.VaultArmyPerLevel * L * 100 + 0.5))
end

-- claude-bud JOB 53: Defence visuals on for this base owner (the Defence tree live AND the visuals flag)
function EndgameConfig.DefenceVisualsLive(userId: any): boolean
	return EndgameConfig.LiveFor(userId, "Defence") and RetentionConfig.Live(EndgameConfig.DefenceVisuals, userId)
end

function EndgameConfig.LiveFor(userId: any, part: string): boolean
	local parts: any = EndgameConfig.Parts
	if parts[part] ~= true then
		return false
	end
	-- v157: a PublicParts part skips the owner-first rule only (Live.Enabled is still the kill switch)
	local pub: any = EndgameConfig.PublicParts
	if typeof(pub) == "table" and pub[part] == true and EndgameConfig.Live.Enabled == true then
		return true
	end
	return RetentionConfig.Live(EndgameConfig.Live, userId)
end

-- true when any part is live for this player (the client's stations and panels; the EMPIRE button)
function EndgameConfig.AnyLiveFor(userId: any): boolean
	for part in pairs(EndgameConfig.Parts) do
		if EndgameConfig.LiveFor(userId, part) then
			return true
		end
	end
	return false
end

-- v157: the gun camo path (wear / put on / take off a camo you own). The Armory (Mastery) sells camos, the Black
-- Market sells Urban / Tiger / Gold: a player the Black Market is live for can wear what he bought there even while
-- the Armory is still owner-only. Buying at the Armory stays Mastery-only.
function EndgameConfig.CamoLiveFor(userId: any): boolean
	return EndgameConfig.LiveFor(userId, "Mastery") or EndgameConfig.LiveFor(userId, "BlackMarket")
end

-- v157: the camos the Black Market sells (Items of Kind "Camo" -> [camo id] = item id)
function EndgameConfig.MarketCamos(): { [string]: string }
	local out: { [string]: string } = {}
	for id, it in pairs(EndgameConfig.BlackMarket.Items :: any) do
		if typeof(it) == "table" and it.Kind == "Camo" and typeof(it.Camo) == "string" then
			out[it.Camo] = id
		end
	end
	return out
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

-- §2.9 a gun's stats after its mastery level (0..5) and attachments: damage +3 %, fire rate +2 %, range +4 %,
-- magazine +6 %, reload -5 % a level; Red-dot range +10 %, Grip spread -15 %, Extended Mag +25 %. Every multiplier
-- is capped at MaxMult 3 (the reload never under a third). `def` is a WeaponConfig row; returns a new table.
function EndgameConfig.GunStats(def: any, mastery: number, att: { [string]: boolean }?): { [string]: number }
	local Ma = EndgameConfig.Mastery
	local L = math.clamp(level(mastery), 0, Ma.MaxLevel)
	local a: { [string]: boolean } = att or {}
	local pl = Ma.PerLevel
	local cap = 3
	local function m(pct: number): number
		return math.min(1 + pct / 100, cap)
	end
	local rangePct = pl.RangePct * L + (if a.RedDot then Ma.Attachments.RedDot.RangePct else 0)
	local magPct = pl.MagPct * L + (if a.ExtendedMag then Ma.Attachments.ExtendedMag.MagPct else 0)
	return {
		Damage = (tonumber(def.Damage) or 0) * m(pl.DamagePct * L),
		FireRate = (tonumber(def.FireRate) or 0) * m(pl.RatePct * L),
		Range = (tonumber(def.Range) or 0) * m(rangePct),
		MagazineSize = math.floor((tonumber(def.MagazineSize) or 0) * m(magPct) + 0.5),
		ReloadTime = (tonumber(def.ReloadTime) or 0) * math.max(1 + pl.ReloadPct * L / 100, 1 / cap),
		Spread = (tonumber(def.Spread) or 0) * (if a.Grip then 1 + Ma.Attachments.Grip.SpreadPct / 100 else 1),
	}
end

-- §2.9 the mastery price base for a gun: shop 1M, rebirth 2M, premium (Robux) 3M
function EndgameConfig.MasteryBase(def: any): number
	local T = EndgameConfig.Mastery.TierBase
	if typeof(def) == "table" and def.Premium == true then
		return T.Premium
	elseif typeof(def) == "table" and def.RebirthOnly == true then
		return T.Rebirth
	end
	return T.Shop
end

-- §2.6 the vehicle workshop factors at level L: HP (and armour) +6 %, speed +3 % a level
function EndgameConfig.WorkshopMults(L: number): (number, number)
	local W = EndgameConfig.Workshop
	local l = math.clamp(level(L), 0, W.MaxLevel)
	return 1 + W.HpPct * l / 100, 1 + W.SpeedPct * l / 100
end

-- §2.8 the Combat Medicine max-HP bonus at level L (+10 a level)
function EndgameConfig.MedicineHp(L: number): number
	return math.clamp(level(L), 0, #EndgameConfig.Hospital.Medicine.Costs) * EndgameConfig.Hospital.Medicine.HpPerLevel
end

-- §2.5 the Base Tier a Defence level needs (0 = none)
function EndgameConfig.DefenceNeedTier(L: number): number
	return tonumber((EndgameConfig.Defence.NeedTier :: any)[level(L)]) or 0
end

-- §2.1 the endgame's own rebirth unlocks (granted by EndgameService while the Rebirth part is live; the shared
-- PrestigeConfig track is untouched, so players the job is not live for see exactly today's rebirth screen)
EndgameConfig.RebirthUnlocks = {
	{ At = 25, Flag = "HeavyWarhead", Name = "Heavy Warhead" },
	{ At = 30, Flag = "MythicTraining", Name = "Mythic Training" },
	{ At = 35, Flag = "BastionCrest", Name = "Bastion Crest" },
	{ At = 40, Flag = "LegendParade", Name = "Legend Parade" },
}

-- §2.11 today's 3 contracts for a player: a pure function of (UserId, UTC day) over the pool, no repeats
function EndgameConfig.DailyContracts(userId: number, day: number): { any }
	local Ct = EndgameConfig.Contracts
	local pool = Ct.Pool
	local n = #pool
	local out = {}
	local seed = (math.floor(tonumber(userId) or 0) % 9973) * 31 + math.floor(tonumber(day) or 0) * 7
	local order = {}
	for k = 1, n do
		local x = (seed + k * 7919) % 1000003
		table.insert(order, { K = k, H = (x * x * 31 + x * 17 + k) % 1000003 }) -- a non-linear mix: each day reshuffles
	end
	table.sort(order, function(a, b)
		return a.H < b.H
	end)
	for j = 1, math.min(Ct.Daily, n) do
		table.insert(out, pool[order[j].K])
	end
	return out
end

-- §2.11 this week's High-Value Target (the same for everyone in a week)
function EndgameConfig.WeeklyHvt(week: number): any
	local h = EndgameConfig.Contracts.Hvt
	return h[(math.floor(tonumber(week) or 0) % #h) + 1]
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

-- claude-bud JOB A: the Recruitment Office's walk-away rule (pure): close only past RecruitCloseRange from the point it
-- was opened from (the hysteresis band between the prompt's 10-12 studs and 17)
function EndgameConfig.RecruitShouldClose(distFromAnchor: number?): boolean
	if distFromAnchor == nil or distFromAnchor ~= distFromAnchor then
		return false -- no anchor known (state still loading): never a close
	end
	return distFromAnchor > (tonumber(EndgameConfig.Station.RecruitCloseRange) or 17)
end

return EndgameConfig
