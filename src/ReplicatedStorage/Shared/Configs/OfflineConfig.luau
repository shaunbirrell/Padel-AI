--!strict
--[[
	Code Bot (owner Shaun, 2026-10-01): THE one place for the offline ("Away") cash rule. Everything that pays or shows
	offline earnings reads it: the server grant (RetentionService onLoadOffline / ComputeOffline), the Missions panel
	"Away N h: earn up to $X" line and the D7★ tile (MissionService Streak7 / Day7Cash), the "Welcome back" card
	(RetentionService WelcomeBack push) and the notification sender state (RetentionService NotifyState).

	Rule (Shaun): offline = min(awaySeconds, MaxSeconds) x incomePerSecond x Rate
	  MaxSeconds = 7200 (2 h of income at most), Rate = 0.10 (10 % of the normal rate).
	  Example: earning $1M in 2 h of play -> $100k while away.
	incomePerSecond = the live passive tick rate (BaseService.ComputePassiveIncomePerTick x the "passive" cash
	multiplier / TickSeconds) with the DOUBLE WEEKEND divided out (RetentionService incomePerSecond); the event still
	doubles only the part of the counted span that lay inside the real event window (DoubleEvent.OfflineFactor, as
	since v185). "offline" is NOT in EventConfig.ExtraCashReasons and must not be added.

	PassCapMult: the "2x Offline Cash" game pass (MonetizationConfig.GamePasses.OfflineCap2x, a paid product) still
	doubles the cap TIME for its owners (2 h -> 4 h) while EconomyConfig.OfflineEarnings.CapBoost is live; it never
	touches Rate. Set PassCapMult = 1 to hold pass owners to 2 h as well.
	PremiumBonus: 0 (Shaun's formula has no Premium bonus; was +10 %).
	Save keys untouched (LastSeenUnix / PrevSeenUnix).
]]

local OfflineConfig = {
	MaxSeconds = 7200,
	Rate = 0.10,
	PassCapMult = 2,
	PremiumBonus = 0,
}

-- the counted seconds: min(away, cap); cap defaults to MaxSeconds. NaN / negative -> 0
function OfflineConfig.CountedSeconds(awaySeconds: number, capSeconds: number?): number
	local away = tonumber(awaySeconds) or 0
	local cap = tonumber(capSeconds) or OfflineConfig.MaxSeconds
	if away ~= away or away <= 0 or cap ~= cap or cap <= 0 then
		return 0
	end
	return math.min(away, cap)
end

-- offline = min(awaySeconds, cap) x incomePerSecond x Rate (x mult, 1 by default). Floored, never negative / NaN
function OfflineConfig.Earnings(awaySeconds: number, incomePerSecond: number, capSeconds: number?, mult: number?): number
	local perSec = tonumber(incomePerSecond) or 0
	if perSec ~= perSec or perSec <= 0 then
		return 0
	end
	local m = tonumber(mult) or 1
	if m ~= m or m <= 0 then
		m = 1
	end
	local v = OfflineConfig.CountedSeconds(awaySeconds, capSeconds) * perSec * math.clamp(OfflineConfig.Rate, 0, 1) * m
	return if v == v and v > 0 then math.floor(v + 1e-6) else 0 -- +1e-6: $1M / 2 h x 10 % is $100,000, never $99,999
end

-- what a FULL cap pays at this income (the "Away N h: earn up to $X" line, the D7 tile)
function OfflineConfig.FullCapCash(incomePerSecond: number, capSeconds: number?): number
	local cap = tonumber(capSeconds) or OfflineConfig.MaxSeconds
	return OfflineConfig.Earnings(cap, incomePerSecond, cap)
end

return OfflineConfig
