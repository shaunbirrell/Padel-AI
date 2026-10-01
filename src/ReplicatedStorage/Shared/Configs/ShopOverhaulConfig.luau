--!strict
--[[
	claude-bud JOB 36 (2026-09-30): the SHOP OVERHAUL (docs/claude-queue/JOB35-36-shop-and-guns.md). Prices and Ids stay
	in MonetizationConfig; this file says what changes while the overhaul is live for a player.
	  1. Shop order (Order, below) and PERMANENT on every pass row; "BEST VALUE" on 2x Cash.
	  2. Cash packs scale: grant = max(Floor, Minutes x the buyer's passive $/min), computed in ProcessReceipt before
	     any mutation (MonetizationService). The Shop rows and offers show the same live amount (the server publishes
	     WE_PassivePerMin; ShopOverhaulService).
	  3. Duplicates: the Speed Pass and Army Expansion leave the Shop (HideWhenLive); the Speed stand and the death offer
	     sell Speed Boost; the army-wiped offer sells Bigger Army. Owners keep what they bought (SpeedMultFor / the army
	     cap read ownership, not the Shop).
	  4. VIP (199 R$ — codebot_v142: owner has NOT approved 349; MonetizationConfig VIP.OverhaulRobuxPrice = 199): +50 % Cash (was 25 %), a daily VIP supply crate (~10 min of income, profile.VipSupplyAt), the lounge,
	     the [VIP] chat tag and a gold chat name. Every current VIP owner gets it.
	  5. New passes (Id 0 until the owner creates them): War Chest (counts as 2x Cash + Auto Collect + VIP + Bigger
	     Army; hidden once all four are owned), Super Soldiers (+25 % army damage and soldier HP), Double HP (x2 MaxHealth).
	Kill switch: Live (RetentionConfig.Live rule: OwnerFirst = UserId 470626172 + Studio). Off = the old shop exactly.
]]

export type Pack = { Floor: number, Minutes: number }

local ShopOverhaulConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = false, -- codebot_v142 launch (owner 2026-09-30 16:24): everyone
	},

	--[[ SUPPLY tab order: each Shop row name ("ShopRow_<key>") takes the first matching pattern's place; rows in the
		same place keep their old order. FREE rows -> War Chest -> 2x Cash -> VIP -> Auto Collect -> Starter Pack ->
		BP Premium -> Bigger Army -> Super Soldiers -> Double HP -> Speed Boost -> (other passes) -> Armory guns ->
		premium vehicles -> cash packs -> consumables. ]]
	Order = {
		"^ShopRow_fr_",
		"^ShopRow_RecruitPack$", -- claude-bud JOB 41 B: the Recruit Pack on top (shown only once its Id is set)
		"^ShopRow_Pass_WarChest$",
		"^ShopRow_Pass_DoubleCash$",
		"^ShopRow_Pass_VIP$",
		"^ShopRow_Pass_AutoCollect$",
		"^ShopRow_StarterBundle$",
		"^ShopRow_PremiumPass$",
		"^ShopRow_Pass_BiggerArmy$",
		"^ShopRow_Pass_SuperSoldiers$",
		"^ShopRow_Pass_DoubleHP$",
		"^ShopRow_SpeedBoost$",
		"^ShopRow_Pass_DoubleXP$",
		"^ShopRow_Pass_PG_",
		"^ShopRow_Pass_PV_",
		"^ShopRow_Pass_ExtraGarageSlot$",
		"^ShopRow_Pass_",
		-- claude-bud JOB 42: the time packs take the cash place (only built while shown); the old four stay for OFF
		"^ShopRow_Cash4h$",
		"^ShopRow_Cash2h$",
		"^ShopRow_Cash1h$",
		"^ShopRow_Cash30m$",
		"^ShopRow_Cash15m$",
		"^ShopRow_CashMega$",
		"^ShopRow_CashLarge$",
		"^ShopRow_CashMedium$",
		"^ShopRow_CashSmall$",
		"^ShopRow_",
	} :: { string },
	BestValueKey = "DoubleCash",
	BestValueLabel = "BEST VALUE",
	PermanentPrefix = "PERMANENT · ",

	-- grant = max(Floor, Minutes x passive $/min) — Ids and prices unchanged (MonetizationConfig)
	CashPacks = {
		CashSmall = { Floor = 10000, Minutes = 5 },
		CashMedium = { Floor = 50000, Minutes = 20 },
		CashLarge = { Floor = 200000, Minutes = 60 },
		CashMega = { Floor = 2000000, Minutes = 180 },
	} :: { [string]: Pack },
	PerMinAttribute = "WE_PassivePerMin", -- server -> the buyer's client (display only; ProcessReceipt recomputes)
	PerMinPublishSeconds = 10,

	--[[ claude-bud JOB 42: TIME-based cash packs ("buy X minutes of your cash"), owner-first. Grant = max(Floor, Minutes x
		his income) at RECEIPT time (ProcessReceipt). Live in the Shop = TimePacksLiveFor AND TimePacksReady (all five Ids
		set); until then the old JOB 36 rows stay. The Floors are a proposed minimum for new players, chosen so both the
		minutes per R$ and the floor $ per R$ rise with the price (15m 0.60 / 400 -> 4h 0.86 / 717): a bigger pack is always
		the better deal, so BEST VALUE on 4h is honest. ExcludeTimedBoosts: the income leaves out the TIMED multipliers
		(profile.CashBoost, the Double Cash event) so the pack does not double while a boost runs. NO 1-day / 7-day pack. ]]
	TimePacks = {
		Enabled = true,
		OwnerFirst = true,
		Order = { "Cash4h", "Cash2h", "Cash1h", "Cash30m", "Cash15m" }, -- Shop order, biggest first
		Packs = {
			Cash4h = { Minutes = 240, Floor = 200000, Title = "4 HOURS OF CASH", Label = "4 hours of cash" },
			Cash2h = { Minutes = 120, Floor = 100000, Title = "2 HOURS OF CASH", Label = "2 hours of cash" },
			Cash1h = { Minutes = 60, Floor = 50000, Title = "1 HOUR OF CASH", Label = "1 hour of cash" },
			Cash30m = { Minutes = 30, Floor = 25000, Title = "30 MIN OF CASH", Label = "30 minutes of cash" },
			Cash15m = { Minutes = 15, Floor = 10000, Title = "15 MIN OF CASH", Label = "15 minutes of cash" },
		},
		BestValueKey = "Cash4h",
		BestValueLabel = "BEST VALUE",
		ExcludeTimedBoosts = true,
		HideOldKeys = { CashSmall = true, CashMedium = true, CashLarge = true, CashMega = true },
		PerMinAttribute = "WE_TimePackPerMin", -- display only, from the same publish tick as WE_PassivePerMin
		MinimumText = "(minimum)", -- the amount line while the floor is what he gets
		-- the income bucket on RobuxPurchase (never the exact income)
		PerMinBuckets = { { Min = 100000, Text = "100k+" }, { Min = 10000, Text = "10k+" }, { Min = 1000, Text = "1k+" }, { Min = 100, Text = "100+" }, { Min = 0, Text = "0-99" } },
	},

	-- duplicates
	HideWhenLive = { ImpulseSpeed = true, ExtraSoldierSlot = true } :: { [string]: boolean },
	SpeedStandProduct = "SpeedBoost", -- the base Speed stand sells this dev product (was the first live: the Speed Pass)
	DeathOfferProduct = "SpeedBoost",
	ArmyWipedPass = "BiggerArmy",

	Vip = {
		CashBonusMult = 0.5, -- +50 % (MonetizationConfig VIP.CashBonusMult stays 0.25 for the old path)
		SupplyMinutes = 10, -- the daily crate = this many minutes of passive income
		SupplyFloor = 5000,
		SupplyEveryHours = 20, -- once a day (20 h so a daily player never misses one)
		GoldName = true, -- WE_VIPGold: the chat name is gold too
	},
	SuperSoldiers = { PassKey = "SuperSoldiers", Mult = 1.25 }, -- army damage and soldier HP (the player DPS cap stays)
	DoubleHP = { PassKey = "DoubleHP", Mult = 2 }, -- player MaxHealth (ArmourService base)
}

local RetentionConfig = require(script.Parent.RetentionConfig)

function ShopOverhaulConfig.LiveFor(userId: any): boolean
	return RetentionConfig.Live(ShopOverhaulConfig.Live, userId)
end

-- a cash pack's grant for a passive income of perMin $/min (nil = not a scaling pack)
function ShopOverhaulConfig.CashPackAmount(key: string, perMin: number): number?
	local p = ShopOverhaulConfig.CashPacks[key]
	if p == nil then
		return nil
	end
	local rate = if typeof(perMin) == "number" and perMin == perMin and perMin > 0 and perMin < 1e12 then perMin else 0
	return math.max(p.Floor, math.floor(p.Minutes * rate))
end

-- claude-bud JOB 42: the time packs
function ShopOverhaulConfig.TimePacksLiveFor(userId: any): boolean
	return RetentionConfig.Live(ShopOverhaulConfig.TimePacks, userId)
end

-- a time pack's grant for an income of perMin $/min (nil = not a time pack); an integer, at most 2^53
function ShopOverhaulConfig.TimePackAmount(key: string, perMin: number): number?
	local p = ShopOverhaulConfig.TimePacks.Packs[key]
	if p == nil then
		return nil
	end
	local rate = if typeof(perMin) == "number" and perMin == perMin and perMin > 0 and perMin < 1e12 then perMin else 0
	return math.min(math.max(p.Floor, math.floor(p.Minutes * rate)), 2 ^ 53)
end

-- all five time-pack Ids are set in MonetizationConfig (the Shop swap waits for every one)
function ShopOverhaulConfig.TimePacksReady(): boolean
	local MC: any = require(script.Parent.MonetizationConfig)
	for _, key in ipairs(ShopOverhaulConfig.TimePacks.Order) do
		local def = MC.DevProducts[key]
		if typeof(def) ~= "table" or (tonumber(def.Id) or 0) == 0 then
			return false
		end
	end
	return true
end

-- LIVE for the Shop / the offers: the flag AND all five Ids
function ShopOverhaulConfig.TimePacksShown(userId: any): boolean
	return ShopOverhaulConfig.TimePacksLiveFor(userId) and ShopOverhaulConfig.TimePacksReady()
end

function ShopOverhaulConfig.PerMinBucket(perMin: number): string
	local n = tonumber(perMin) or 0
	for _, b in ipairs(ShopOverhaulConfig.TimePacks.PerMinBuckets) do
		if n >= b.Min then
			return b.Text
		end
	end
	return "0-99"
end

-- the VIP supply crate for a passive income of perMin $/min
function ShopOverhaulConfig.VipSupplyAmount(perMin: number): number
	local v = ShopOverhaulConfig.Vip
	local rate = if typeof(perMin) == "number" and perMin == perMin and perMin > 0 and perMin < 1e12 then perMin else 0
	return math.max(v.SupplyFloor, math.floor(v.SupplyMinutes * rate))
end

-- the place of a Shop row (1 = first); rows matching nothing go last
function ShopOverhaulConfig.Rank(rowName: string): number
	for i, pattern in ipairs(ShopOverhaulConfig.Order) do
		if string.find(rowName, pattern) ~= nil then
			return i
		end
	end
	return #ShopOverhaulConfig.Order + 1
end

return ShopOverhaulConfig
