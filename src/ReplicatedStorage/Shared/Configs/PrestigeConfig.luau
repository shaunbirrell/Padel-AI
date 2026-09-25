--!strict
--[[ Prestige / Rebirth reset rules.
	Cash mult at runtime uses EconomyConfig.PrestigeCashMultiplierPerLevel (+10%/prestige).
	RebirthUnlocks: applied when Prestige reaches AtPrestige (stacking permanent flags + optional grants).
	Owner's 11 features (lane K1, spec_f11 §2):
	  F7  KeepBase + ResetOnPrestigeKeepBase: the 50 R$ keep-base rebirth (MonetizationConfig.DevProducts
	      .RebirthKeepBase adds a token to profile.KeepBaseRebirths; PrestigeService.DoPrestige(p, { KeepBase = true })
	      spends it). ResetFor(path) is the reset table each path applies.
	  F11 ProgressPct (rebirth progress %, XP-based) and RebirthSummary(path, ctx): the KEEP / RESET / GAIN lines of
	      the Rebirth confirm modal, built from the same reset tables the server applies (single source).
]]

local LevelConfig = require(script.Parent.LevelConfig)

export type RebirthUnlockDef = {
	AtPrestige: number,
	Flag: string,
	DisplayName: string,
	Kind: "Flag" | "Vehicle" | "Weapon" | "Structure",
	Id: string?, -- Vehicle/Weapon/Structure id when Kind is not Flag-only
	GrantOwned: boolean?, -- auto-grant Vehicles[Id] / Weapons[Id]
}

-- F7 / F11: the two rebirth paths. "Cash" = the free rebirth; "KeepBase" = the 50 R$ keep-base rebirth (token).
export type RebirthPath = "Cash" | "KeepBase"

export type ResetRules = {
	Cash: boolean,
	Level: boolean,
	XP: boolean,
	BaseUpgrades: boolean,
	KeepVehicles: boolean,
	KeepWeapons: boolean,
	KeepGold: boolean,
	KeepRebirthUnlocks: boolean,
}

-- F11: what the Rebirth confirm modal needs to fill the lines (the server sends it in PrestigeStateUpdate.Summary).
export type RebirthSummaryCtx = {
	Built: number, -- structure levels bought (the "Base buildings (N built)" line)
	Prestige: number, -- the CURRENT prestige (before this rebirth)
	NextUnlock: string?, -- DisplayName of the rebirth unlock this rebirth gives (NextUnlockName), if any
	BusinessesOn: boolean, -- BusinessConfig is live (its businesses reset with the base on the Cash path)
}

export type RebirthSummary = { Keep: { string }, Reset: { string }, Gain: { string } }

local PrestigeConfig = {
	-- P0 competitive: earlier first rebirth feel (was 100). Reversible — bump back if economy too fast.
	-- See ASSUMPTIONS #108. AdminPlaytestCash 50M unchanged.
	MinLevelToPrestige = 40,
	-- v38: soft rebirth CTA when Level >= Min - NearPrestigeLevels
	NearPrestigeLevels = 2,
	MaxPrestige = 50,
	-- +10% cash earnings per prestige (stacking). Keep in sync with EconomyConfig.PrestigeCashMultiplierPerLevel.
	CashBonusPerPrestige = 0.10,
	GoldBonusOnPrestige = 50,
	-- Upfront cash fee to prestige (0 = none). Cash still resets to StartingCashAfterPrestige when ResetOnPrestige.Cash.
	CashFee = 0,
	ResetOnPrestige = {
		Cash = true,
		Level = true,
		XP = true,
		BaseUpgrades = true,
		KeepVehicles = true,
		KeepWeapons = true,
		KeepGold = true,
		KeepRebirthUnlocks = true,
		-- KeepTerritories / KeepOutpostIncomeStacks: implicit (fields never cleared in PrestigeService)
	} :: ResetRules,
	-- F7: the keep-base path = ResetOnPrestige with BaseUpgrades kept (structures, businesses, walls and pumps).
	-- Cash must equal (not KeepBase.KeepCash): with KeepCash = false the cash still goes back to
	-- StartingCashAfterPrestige. PendingCash is kept on both paths, as today (owner decision, ASSUMPTIONS).
	ResetOnPrestigeKeepBase = {
		Cash = true,
		Level = true,
		XP = true,
		BaseUpgrades = false,
		KeepVehicles = true,
		KeepWeapons = true,
		KeepGold = true,
		KeepRebirthUnlocks = true,
	} :: ResetRules,
	StartingCashAfterPrestige = 10000,

	-- F7: 50 R$ keep-base rebirth (a consumable token, MonetizationConfig.DevProducts[ProductKey]). Same gate as the
	-- free rebirth (MinLevelToPrestige, not MaxPrestige). AutoUseOnGrant: a token bought from the Rebirth panel within
	-- IntentWindowSeconds (the purchase-intent map) is spent right after the receipt is saved, when the player can
	-- rebirth; otherwise it is banked for the next rebirth and never expires. Enabled = false hides the path.
	KeepBase = {
		Enabled = true,
		ProductKey = "RebirthKeepBase",
		AutoUseOnGrant = true,
		IntentWindowSeconds = 180,
		KeepCash = false,
	},

	-- F11: the rebirth progress % (Rebirth panel bar, HUD level tooltip). "XP" = share of the total XP from Lv 1 to
	-- MinLevelToPrestige (Lv 20 = 17 %, Lv 30 = 48 %, Lv 39 = 93 %); "Level" = Level / MinLevelToPrestige.
	ProgressMode = "XP",
	-- F11: RebirthSummary line rules (the modal columns are narrow on an 800x360 phone)
	SummaryMaxLineChars = 30,

	--[[
		Unlock track (shown in K panel). Flags land in profile.RebirthUnlocks.
		GrantOwned vehicles/weapons are given permanently (kept through further prestiges).
	]]
	RebirthUnlocks = {
		{
			AtPrestige = 1,
			Flag = "RebirthScout",
			DisplayName = "Scout Car (owned)",
			Kind = "Vehicle",
			Id = "ScoutCar",
			GrantOwned = true,
		},
		{
			AtPrestige = 2,
			Flag = "NavalAccess",
			DisplayName = "Naval Access + Patrol Boat",
			Kind = "Vehicle",
			Id = "PatrolBoat",
			GrantOwned = true,
		},
		{
			AtPrestige = 3,
			Flag = "SupplyLine",
			DisplayName = "Supply Truck (owned)",
			Kind = "Vehicle",
			Id = "SupplyTruck",
			GrantOwned = true,
		},
		{
			AtPrestige = 4,
			Flag = "MissileBoatGrant",
			DisplayName = "Missile Boat (owned)",
			Kind = "Vehicle",
			Id = "MissileBoat",
			GrantOwned = true,
		},
		{
			AtPrestige = 5,
			Flag = "AirLift",
			DisplayName = "Transport Heli (owned)",
			Kind = "Vehicle",
			Id = "TransportHeli",
			GrantOwned = true,
		},
		{
			AtPrestige = 7,
			Flag = "GunboatFleet",
			DisplayName = "Gunboat (owned)",
			Kind = "Vehicle",
			Id = "Gunboat",
			GrantOwned = true,
		},
		{
			AtPrestige = 8,
			Flag = "AssaultArmor",
			DisplayName = "Assault IFV (owned)",
			Kind = "Vehicle",
			Id = "AssaultIFV",
			GrantOwned = true,
		},
		{
			AtPrestige = 10,
			Flag = "EmpireElite",
			DisplayName = "Empire Elite (unlocks Super Heavy)",
			Kind = "Flag",
			Id = nil,
			GrantOwned = false,
		},
		{
			AtPrestige = 12,
			Flag = "EmpireFleet",
			DisplayName = "Empire Fleet (Battleship gate)",
			Kind = "Flag",
			Id = nil,
			GrantOwned = false,
		},
		{
			AtPrestige = 15,
			Flag = "DestroyerGrant",
			DisplayName = "Destroyer (owned)",
			Kind = "Vehicle",
			Id = "Destroyer",
			GrantOwned = true,
		},
		{
			AtPrestige = 18,
			Flag = "CruiserGrant",
			DisplayName = "Cruiser (owned)",
			Kind = "Vehicle",
			Id = "Cruiser",
			GrantOwned = true,
		},
		{
			AtPrestige = 16,
			Flag = "FrigateGrant",
			DisplayName = "Frigate (owned)",
			Kind = "Vehicle",
			Id = "Frigate",
			GrantOwned = true,
		},
		{
			AtPrestige = 20,
			Flag = "StrikeWing",
			DisplayName = "Strike Jet + Heavy Bomber gate",
			Kind = "Vehicle",
			Id = "StrikeJet",
			GrantOwned = true,
		},
	} :: { RebirthUnlockDef },
}

--[[ Build player-facing fee / confirm copy from config (client + server toasts). ]]
function PrestigeConfig.BuildFeeSummary(opts: { BaseCompletionPercent: number? }?): string
	local fee = tonumber(PrestigeConfig.CashFee) or 0
	local startCash = tonumber(PrestigeConfig.StartingCashAfterPrestige) or 0
	local gold = tonumber(PrestigeConfig.GoldBonusOnPrestige) or 0
	local feePart = if fee > 0 then string.format("Fee $%s", tostring(fee)) else "Fee: none"
	local parts = {
		feePart,
		string.format("Cash → $%s after", tostring(startCash)),
		string.format("+%d Gold", gold),
		"+10% cash forever",
		"resets Level/XP/Base",
		"keeps Robux items + vehicles/weapons/gold/unlocks/outposts",
	}
	local pct = opts and tonumber(opts.BaseCompletionPercent)
	if pct ~= nil then
		table.insert(parts, 1, string.format("Base %d%% complete", math.floor(pct)))
	end
	return table.concat(parts, " · ")
end

-- F7: the reset rules a rebirth path applies (anything but "KeepBase" is the free path).
function PrestigeConfig.ResetFor(path: string?): ResetRules
	if path == "KeepBase" then
		return PrestigeConfig.ResetOnPrestigeKeepBase
	end
	return PrestigeConfig.ResetOnPrestige
end

--[[ F11: rebirth progress 0..100 (whole number). "XP" mode:
	floor(100 * min(1, (GetTotalXPForLevel(level) + xp) / GetTotalXPForLevel(MinLevelToPrestige)))
	Lv 1 = 0, Lv 20 = 17, Lv 30 = 48, Lv 39 = 93, Lv 40+ = 100 (xp 0). Junk input counts as Lv 1 / 0 XP. ]]
function PrestigeConfig.ProgressPct(level: number, xp: number?): number
	local lv = math.max(1, math.floor(tonumber(level) or 1))
	local x = math.max(0, tonumber(xp) or 0)
	if x ~= x or x == math.huge then
		x = 0
	end
	local minLv = math.max(1, tonumber(PrestigeConfig.MinLevelToPrestige) or 40)
	if lv >= minLv then
		return 100
	end
	if PrestigeConfig.ProgressMode == "Level" then
		return math.clamp(math.floor(100 * lv / minLv), 0, 100)
	end
	local goal = LevelConfig.GetTotalXPForLevel(minLv)
	if goal <= 0 then
		return 100
	end
	return math.clamp(math.floor(100 * math.min(1, (LevelConfig.GetTotalXPForLevel(lv) + x) / goal)), 0, 100)
end

-- F11: DisplayName of the rebirth unlock that the NEXT rebirth gives (AtPrestige == prestige + 1), or nil.
function PrestigeConfig.NextUnlockName(prestige: number): string?
	local target = math.floor(tonumber(prestige) or 0) + 1
	for _, u in ipairs(PrestigeConfig.RebirthUnlocks) do
		if u.AtPrestige == target then
			return u.DisplayName
		end
	end
	return nil
end

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local sign = ""
	if string.sub(s, 1, 1) == "-" then
		sign, s = "-", string.sub(s, 2)
	end
	local out = s
	while true do
		local nextOut, k = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = nextOut
		if k == 0 then
			break
		end
	end
	return sign .. out
end

-- One modal line: at most SummaryMaxLineChars characters (hard cut with "..." if a caller string is too long).
local function fitLine(text: string): string
	local maxChars = math.max(4, math.floor(tonumber(PrestigeConfig.SummaryMaxLineChars) or 30))
	if #text <= maxChars then
		return text
	end
	return string.sub(text, 1, maxChars - 3) .. "..."
end

-- "Unlocks <name>": drops a "(...)" note, then a "+ second item", before cutting (keeps the line readable).
local function unlockLine(name: string): string
	local maxChars = math.max(4, math.floor(tonumber(PrestigeConfig.SummaryMaxLineChars) or 30))
	local line = "Unlocks " .. name
	if #line > maxChars then
		local short = string.gsub(name, "%s*%b()%s*$", "")
		line = "Unlocks " .. short
		if #line > maxChars then
			local first = string.match(short, "^(.-)%s+%+%s+")
			if first and #first > 0 then
				line = "Unlocks " .. first
			end
		end
	end
	return fitLine(line)
end

--[[ F11 (and F7): the Rebirth confirm modal columns. Built from ResetFor(path), so the lines always say what the
	server's DoPrestige does on that path. Lines are at most SummaryMaxLineChars (30) characters, use two spaces as the
	separator and never contain a middle dot or an arrow (phone fonts, short labels).
	  KEEP  (both) Robux items and passes / Gold (+50 Gold) / Vehicles and weapons / Soldiers and research /
	              Outposts and Empire Tax / Rebirth unlocks / Battle Pass progress;  KeepBase adds Base buildings and levels
	  RESET (both) Cash back to $10,000 / Level 1 and XP 0;  Cash adds Base buildings (N built) and, while
	              ctx.BusinessesOn, War businesses
	  GAIN  +10% cash forever / Total now +N% / Unlocks <next rebirth unlock> (when this rebirth gives one)
	PendingCash (the ATM) is kept on both paths and is not listed (owner decision). ]]
function PrestigeConfig.RebirthSummary(path: RebirthPath, ctx: RebirthSummaryCtx): RebirthSummary
	local reset = PrestigeConfig.ResetFor(path)
	local keep: { string } = {}
	local resetLines: { string } = {}
	local gain: { string } = {}
	local function add(list: { string }, text: string)
		table.insert(list, fitLine(text))
	end

	local goldBonus = math.max(0, math.floor(tonumber(PrestigeConfig.GoldBonusOnPrestige) or 0))
	add(keep, "Robux items and passes")
	if reset.KeepGold then
		add(keep, if goldBonus > 0 then string.format("Gold (+%d Gold)", goldBonus) else "Gold")
	end
	if reset.KeepVehicles and reset.KeepWeapons then
		add(keep, "Vehicles and weapons")
	elseif reset.KeepVehicles then
		add(keep, "Vehicles")
	elseif reset.KeepWeapons then
		add(keep, "Weapons")
	end
	add(keep, "Soldiers and research")
	add(keep, "Outposts and Empire Tax")
	if reset.KeepRebirthUnlocks then
		add(keep, "Rebirth unlocks")
	end
	add(keep, "Battle Pass progress")
	if not reset.BaseUpgrades then
		add(keep, "Base buildings and levels")
	end

	if reset.Cash then
		add(resetLines, "Cash back to $" .. withCommas(tonumber(PrestigeConfig.StartingCashAfterPrestige) or 0))
	else
		add(keep, "Your Cash")
	end
	if reset.Level and reset.XP then
		add(resetLines, "Level 1 and XP 0")
	elseif reset.Level then
		add(resetLines, "Level 1")
	elseif reset.XP then
		add(resetLines, "XP 0")
	end
	if reset.BaseUpgrades then
		add(resetLines, string.format("Base buildings (%d built)", math.max(0, math.floor(tonumber(ctx.Built) or 0))))
		if ctx.BusinessesOn == true then
			add(resetLines, "War businesses")
		end
	end

	local perPct = math.floor((tonumber(PrestigeConfig.CashBonusPerPrestige) or 0.10) * 100 + 0.5)
	local after = math.max(0, math.floor(tonumber(ctx.Prestige) or 0)) + 1
	add(gain, string.format("+%d%% cash forever", perPct))
	add(gain, string.format("Total now +%d%%", after * perPct))
	if typeof(ctx.NextUnlock) == "string" and ctx.NextUnlock ~= "" then
		table.insert(gain, unlockLine(ctx.NextUnlock))
	end

	return { Keep = keep, Reset = resetLines, Gain = gain }
end

return PrestigeConfig
