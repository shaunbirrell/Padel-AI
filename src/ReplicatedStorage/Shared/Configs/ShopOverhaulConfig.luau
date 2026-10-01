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
