--!strict
--[[
	v72 pure tycoon math (configs only: no services, no Instances, never yields). ONE source for
	  server  BaseService.ComputePassiveIncomePerTick (what is PAID), the WE_NextBuy pick (BusinessService)
	  client  BUY button / console tag / Base panel / guide chip / cash pill (what is SHOWN)
	so the "+$3.3/s" a player reads is the number the server pays (x the server-stamped WE_IncomeMult), floored.

	Income is the TOTAL base $ per passive tick at a level (EconomyConfig.PassiveIncome.TickSeconds = 5):
	  building  PerLevelRates[id] * level (unchanged from before v72)
	  business  BusinessConfig IncomePerTick[level] (only while BusinessConfig.Enabled)
	Plot oil pumps: DefensiveWalls reaching PlotOilPumpConfig.MinWallsLevel adds the plot pumps (paid by
	PlotOilPumpService, exempt from multipliers); StepGainPerTick adds them unscaled so Walls L2 shows its real gain.

	Display rules (spec v72 section 3): RateText floors (one decimal below 10, whole numbers from 10 up, ".0" dropped),
	ShortCash gives "$600", "$1,240", "$25K", "$1.9M", and every string comes from TycoonGuideConfig.Text.
]]

local Configs = script.Parent.Parent.Configs -- ReplicatedStorage.Shared is replicated before any script runs
local BaseConfig = require(Configs.BaseConfig)
local EconomyConfig = require(Configs.EconomyConfig)
local BusinessConfig = require(Configs.BusinessConfig)
local PlotOilPumpConfig = require(Configs.PlotOilPumpConfig)
local SoldierConfig = require(Configs.SoldierConfig)
local TycoonGuideConfig = require(Configs.TycoonGuideConfig)

local TycoonMath = {}

export type Requirement = { StructureId: string, Level: number }

export type Candidate = {
	Id: string, -- structure / business id, or TycoonGuideConfig.SoldierCandidateId
	Level: number, -- target level (0 for soldiers)
	Cost: number,
	GainPerTick: number, -- base $ per tick this buy adds (pre-multiplier; Walls L2 includes the unscaled oil)
	Unlock: string?, -- UnlockText for that level
}

export type PickContext = {
	Upgrades: { [string]: any }?, -- profile.BaseUpgrades
	Cash: number, -- wallet
	Pending: number, -- ATM (PendingCash)
	IncomePerSec: number, -- what the ATM receives now (WE_IncomePerSec)
	Soldiers: number?, -- nil = soldiers are not offered
	SoldierCap: number?,
	Current: string?, -- current WE_NextBuy (sticky)
}

export type MoneyState = "Buy" | "Collect" | "Earn"

-- NaN / inf / non-numbers -> 0
local function num(v: any): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return n
end

-- float guard for the floor rules (8.4 stored as 8.3999999 must still read 8.4)
local EPS = 1e-6

function TycoonMath.TickSeconds(): number
	return EconomyConfig.PassiveIncome.TickSeconds
end

-- true only while BusinessConfig.Enabled and `id` is a business
function TycoonMath.IsBusiness(id: string): boolean
	return BusinessConfig.IsBusiness(id)
end

function TycoonMath.MaxLevel(id: string): number
	local def = BaseConfig.Structures[id]
	return if def then def.MaxLevel else 0
end

-- Saved level, whole and clamped to 0..MaxLevel (DataStore junk never throws or overpays; unknown id -> 0).
function TycoonMath.Level(upgrades: { [string]: any }?, id: string): number
	if upgrades == nil then
		return 0
	end
	return math.clamp(math.floor(num(upgrades[id])), 0, TycoonMath.MaxLevel(id))
end

-- TOTAL base $ per tick that `id` pays at `level` (pre-multiplier). Buildings: rate x level. Businesses: table.
function TycoonMath.LevelIncomePerTick(id: string, level: number): number
	local lvl = math.floor(num(level))
	if lvl <= 0 then
		return 0
	end
	local biz = BusinessConfig.Get(id)
	if biz then
		if not BusinessConfig.Enabled then
			return 0
		end
		return biz.IncomePerTick[math.clamp(lvl, 1, #biz.IncomePerTick)]
	end
	local rate = EconomyConfig.PassiveIncome.PerLevelRates[id]
	return if rate then rate * lvl else 0
end

-- The passive tick before multipliers: BaseCashPerTick + every owned level of every known structure.
-- For buildings this equals the pre-v72 BaseService formula (rate x level for each saved level > 0).
function TycoonMath.BasePassivePerTick(upgrades: { [string]: any }?): number
	local total = EconomyConfig.PassiveIncome.BaseCashPerTick
	if upgrades == nil then
		return total
	end
	for id in pairs(upgrades) do
		if typeof(id) == "string" and BaseConfig.Structures[id] ~= nil then
			total += TycoonMath.LevelIncomePerTick(id, TycoonMath.Level(upgrades, id))
		end
	end
	return total
end

-- Plot oil pumps' $ per tick once DefensiveWalls reaches MinWallsLevel (unscaled: PlotOilPumpService pays it exempt)
function TycoonMath.OilPerTick(): number
	if not PlotOilPumpConfig.Enabled then
		return 0
	end
	return (PlotOilPumpConfig.PumpsPerPlot or 2) * (PlotOilPumpConfig.CashPerTick or 18)
end

local function oilOwnedPerTick(upgrades: { [string]: any }?): number
	if TycoonMath.Level(upgrades, "DefensiveWalls") >= (PlotOilPumpConfig.MinWallsLevel or 2) then
		return TycoonMath.OilPerTick()
	end
	return 0
end

-- $ per tick gained by buying `fromLevel + 1`. `mult` scales structure / business income only (oil is exempt), so
-- pass WE_IncomeMult here and NOT again to PerSecText (StepPerSecText does both).
function TycoonMath.StepGainPerTick(id: string, fromLevel: number, mult: number?): number
	local from = math.floor(num(fromLevel))
	local m = if mult == nil then 1 else num(mult)
	local gain = (TycoonMath.LevelIncomePerTick(id, from + 1) - TycoonMath.LevelIncomePerTick(id, from)) * m
	if id == "DefensiveWalls" and from + 1 == (PlotOilPumpConfig.MinWallsLevel or 2) then
		gain += TycoonMath.OilPerTick()
	end
	return gain
end

-- Price of level `level + 1`, or nil at max level / unknown id
function TycoonMath.NextCost(id: string, level: number): number?
	local def = BaseConfig.Structures[id]
	local lvl = math.floor(num(level))
	if not def or lvl >= def.MaxLevel then
		return nil
	end
	return def.Costs[math.max(lvl, 0) + 1]
end

-- (ok, first unmet requirement). Unknown id -> (false, nil).
function TycoonMath.MeetsRequirements(id: string, upgrades: { [string]: any }?): (boolean, Requirement?)
	local def = BaseConfig.Structures[id]
	if not def then
		return false, nil
	end
	for _, req in ipairs(def.Requires or {}) do
		if TycoonMath.Level(upgrades, req.StructureId) < req.Level then
			return false, req
		end
	end
	return true, nil
end

-- "6 new buildings" for CommandCenter L1, etc. (business-only lines while BusinessConfig.Enabled)
function TycoonMath.UnlockText(id: string, level: number): string?
	local t = TycoonGuideConfig.Unlocks[id]
	local s = if t then t[level] else nil
	if s == nil and BusinessConfig.Enabled then
		local b = TycoonGuideConfig.BusinessUnlocks[id]
		s = if b then b[level] else nil
	end
	return s
end

function TycoonMath.DisplayName(id: string): string
	local def = BaseConfig.Structures[id]
	if def then
		return def.DisplayName
	end
	local biz = BusinessConfig.Get(id)
	return if biz then biz.DisplayName else id
end

-- <= 10 upper-case characters: business ShortName, TycoonGuideConfig.ShortNames, else the upper-case DisplayName
function TycoonMath.ShortName(id: string): string
	local biz = BusinessConfig.Get(id)
	if biz then
		return biz.ShortName
	end
	return TycoonGuideConfig.ShortNames[id] or string.upper(TycoonMath.DisplayName(id))
end

function TycoonMath.SoldierGainPerTick(): number
	return num(SoldierConfig.TrainingIncome.CashPerSoldierPerTick)
end

-- Training income's share of the total base income per tick (passive + training + oil), 0..1, pre-multiplier.
function TycoonMath.TrainingShare(upgrades: { [string]: any }?, soldiers: number): number
	local n = math.max(0, math.floor(num(soldiers)))
	local training = if n >= (SoldierConfig.TrainingIncome.MinSoldiersForIncome or 1) then n * TycoonMath.SoldierGainPerTick() else 0
	local total = TycoonMath.BasePassivePerTick(upgrades) + oilOwnedPerTick(upgrades) + training
	return if total > 0 then training / total else 0
end

-- Every console buy that is open now (requirements met, below max), plus soldiers when configured and while the
-- training share is below SoldierMaxShare.
function TycoonMath.Candidates(ctx: PickContext): { Candidate }
	local out: { Candidate } = {}
	for _, id in ipairs(BaseConfig.StructureOrder) do
		local lv = TycoonMath.Level(ctx.Upgrades, id)
		local cost = TycoonMath.NextCost(id, lv)
		if cost ~= nil and (TycoonMath.MeetsRequirements(id, ctx.Upgrades)) then
			table.insert(out, {
				Id = id,
				Level = lv + 1,
				Cost = cost,
				GainPerTick = TycoonMath.StepGainPerTick(id, lv),
				Unlock = TycoonMath.UnlockText(id, lv + 1),
			})
		end
	end
	local soldiers, cap = ctx.Soldiers, ctx.SoldierCap
	if TycoonGuideConfig.IncludeSoldiers and soldiers ~= nil and cap ~= nil and num(soldiers) < num(cap) then
		local gain = TycoonMath.SoldierGainPerTick()
		if gain > 0 and TycoonMath.TrainingShare(ctx.Upgrades, soldiers) < TycoonGuideConfig.SoldierMaxShare then
			table.insert(out, {
				Id = TycoonGuideConfig.SoldierCandidateId,
				Level = 0,
				Cost = num(SoldierConfig.RecruitCostCash),
				GainPerTick = gain,
				Unlock = nil,
			})
		end
	end
	return out
end

-- Lower is better: WaitWeight x seconds until affordable (wallet + ATM) + payback seconds (unlock value counted).
function TycoonMath.Score(c: Candidate, ctx: PickContext): number
	local unlock = TycoonGuideConfig.UnlockValuePerTick[c.Id]
	local value = c.GainPerTick + (if unlock then (unlock[c.Level] or 0) else 0)
	local perSec = value / TycoonMath.TickSeconds()
	local payback = c.Cost / math.max(perSec, 0.01)
	local have = math.max(0, num(ctx.Cash)) + math.max(0, num(ctx.Pending))
	local wait = math.max(0, c.Cost - have) / math.max(num(ctx.IncomePerSec), 0.1)
	return TycoonGuideConfig.WaitWeight * wait + payback
end

-- "Id:Level" | "Soldier:0" | "" (nil)
function TycoonMath.Encode(c: Candidate?): string
	if c == nil then
		return ""
	end
	return c.Id .. ":" .. tostring(c.Level)
end

-- (id, level) from a WE_NextBuy value; (nil, 0) for "" or junk
function TycoonMath.Decode(s: any): (string?, number)
	if typeof(s) ~= "string" or s == "" then
		return nil, 0
	end
	local id, lv = string.match(s, "^([%w_]+):(%d+)$")
	if id == nil then
		return nil, 0
	end
	return id, tonumber(lv) or 0
end

--[[ The one next buy: the first Opening entry that is a candidate now, else the best Score. Sticky: while
	ctx.Current is still a candidate, a challenger must score below Hysteresis x the current score. Deterministic
	(ties -> cheaper, then StructureOrder). nil when nothing is left. Callers check TycoonGuideConfig.Enabled. ]]
function TycoonMath.PickNext(ctx: PickContext): Candidate?
	local cands = TycoonMath.Candidates(ctx)
	if #cands == 0 then
		return nil
	end
	local byKey: { [string]: Candidate } = {}
	for _, c in ipairs(cands) do
		byKey[TycoonMath.Encode(c)] = c
	end
	for _, key in ipairs(TycoonGuideConfig.Opening) do
		local c = byKey[key]
		if c then
			return c
		end
	end
	local best: Candidate? = nil
	local bestScore = math.huge
	for _, c in ipairs(cands) do
		local s = TycoonMath.Score(c, ctx)
		if s < bestScore or (s == bestScore and best ~= nil and c.Cost < best.Cost) then
			best, bestScore = c, s
		end
	end
	local cur = if ctx.Current then byKey[ctx.Current] else nil
	if cur and best and cur ~= best then
		if bestScore >= TycoonGuideConfig.Hysteresis * TycoonMath.Score(cur, ctx) then
			return cur
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------------------
-- display
---------------------------------------------------------------------------------------------------------------

-- "3.3" / "24" from dollars per second: floored (never over-promises), one decimal below 10, whole from 10 up,
-- a trailing ".0" dropped ("3"). Negative / junk -> "0".
function TycoonMath.RateText(perSec: number): string
	local v = math.max(0, num(perSec))
	if v >= 10 then
		return tostring(math.floor(v + EPS))
	end
	local tenths = math.floor(v * 10 + EPS)
	if tenths >= 100 then
		return "10"
	end
	if tenths % 10 == 0 then
		return tostring(tenths // 10)
	end
	return string.format("%d.%d", tenths // 10, tenths % 10)
end

-- "+$3.3/s" from a per-tick amount x mult (e.g. IncomePerTick x WE_IncomeMult)
function TycoonMath.PerSecText(perTick: number, mult: number?): string
	local m = if mult == nil then 1 else num(mult)
	return string.format(TycoonGuideConfig.Text.PerSec, TycoonMath.RateText(num(perTick) * m / TycoonMath.TickSeconds()))
end

-- "+$24/s" from a rate already in dollars per second (WE_IncomePerSec: the cash pill suffix)
function TycoonMath.RatePerSecText(perSec: number): string
	return string.format(TycoonGuideConfig.Text.PerSec, TycoonMath.RateText(perSec))
end

-- "+$3.3/s" for buying `fromLevel + 1` of `id` at WE_IncomeMult `mult` (oil counted unscaled). Soldiers: pass
-- TycoonGuideConfig.SoldierCandidateId (one recruit's training income x mult).
function TycoonMath.StepPerSecText(id: string, fromLevel: number, mult: number?): string
	if id == TycoonGuideConfig.SoldierCandidateId then
		return TycoonMath.PerSecText(TycoonMath.SoldierGainPerTick(), mult)
	end
	return TycoonMath.PerSecText(TycoonMath.StepGainPerTick(id, fromLevel, mult))
end

-- What the buy surfaces say about money (client: wallet = cash, pending = ATM, rate = WE_IncomePerSec):
--   "Buy"      wallet >= cost
--   "Collect"  wallet < cost <= wallet + ATM   (shortBy = cost - wallet: collect that much at your ATM)
--   "Earn"     not enough yet                  (shortBy = cost - wallet - ATM; eta seconds = shortBy / rate, nil at 0)
function TycoonMath.MoneyState(cost: number, wallet: number, pending: number, incomePerSec: number): (MoneyState, number, number?)
	local c = num(cost)
	local w = math.max(0, num(wallet))
	local p = math.max(0, num(pending))
	if w >= c then
		return "Buy", 0, nil
	end
	if w + p >= c then
		return "Collect", c - w, nil
	end
	local short = c - w - p
	local rate = num(incomePerSec)
	return "Earn", short, if rate > 0 then short / rate else nil
end

-- "0:42", "12:05", "1h 05m" (seconds rounded up)
function TycoonMath.FormatEta(seconds: number): string
	local s = math.max(0, math.ceil(num(seconds)))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

-- "13,594" (whole dollars, floored)
function TycoonMath.Commas(n: number): string
	local v = math.floor(num(n))
	local neg = v < 0
	local str = tostring(math.abs(v))
	local out = string.reverse((string.gsub(string.reverse(str), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return if neg then "-" .. out else out
end

-- thousands: "$3.2K", "$12.5K", "$25K", "$150K" (tenths of a K rounded; whole K from $100K up)
local function kText(v: number): string
	local tenths = math.floor(v / 100 + 0.5)
	if tenths >= 10000 then
		return "$1M"
	end
	if tenths >= 1000 or tenths % 10 == 0 then
		return string.format("$%dK", tenths // 10)
	end
	return string.format("$%d.%dK", tenths // 10, tenths % 10)
end

--[[ Prices: "$600", "$1,240", "$12.5K", "$25K", "$1.9M" (close to the console price label's rules). tight = true
	(the 2.3-stud console screen) abbreviates from $1,000: "$3.2K". ]]
function TycoonMath.ShortCash(n: number, tight: boolean?): string
	local v = math.max(0, math.floor(num(n)))
	if v >= 1_000_000 then
		return "$" .. (string.gsub(string.format("%.1f", v / 1_000_000), "%.0$", "")) .. "M"
	elseif v >= 10_000 or (tight == true and v >= 1000) then
		return kText(v)
	end
	return "$" .. TycoonMath.Commas(v)
end

-- "+$16" over a business bin on a passive tick: floor(IncomePerTick[level] x mult)
function TycoonMath.PopText(id: string, level: number, mult: number?): string
	local m = if mult == nil then 1 else num(mult)
	return string.format(TycoonGuideConfig.Text.Pop, TycoonMath.Commas(math.floor(TycoonMath.LevelIncomePerTick(id, level) * m + EPS)))
end

--[[ BUY lane (spec v72 F3): how far (v) to shift a horizontally centred action button of width widthV to the right so
	its left edge clears the thumb zone (the left `frac` of the safe-area width) by clearPx REAL px.
	viewportV: the safe content size in v (HudLayout.ContentSizeV()); scale: HudLayout.Scale() (real = v x scale).
	= max(0, W x frac + clearPx / scale - (W / 2 - widthV / 2)), W = viewportV.X. Pure; 0 on junk input. ]]
function TycoonMath.ActionLaneShiftV(viewportV: Vector2, widthV: number, frac: number, clearPx: number, scale: number): number
	local w = num(viewportV.X)
	local s = num(scale)
	if w <= 0 or s <= 0 then
		return 0
	end
	return math.max(0, w * num(frac) + num(clearPx) / s - (w / 2 - num(widthV) / 2))
end

return TycoonMath
