--!strict
--[[
	XP rebalance (spec_xp.md, lane X1): one-time XP for cash purchases, plus the one-time backfill for old saves.
	The cheaper level curve is NOT here: it lives in LevelConfig.CurveV2, because LevelConfig must require nothing.

	Build XP: every successful EconomyService.SpendCash whose reason starts with one of Build.ReasonPrefixes pays
	  BuildXP(price) = min(Build.Cap, floor(Build.A * price ^ Build.P)) base XP through XPService.AddXP (reason
	  Build.Reason; the season, territory and DoubleXP multipliers apply like any gameplay XP). Soldiers, missile
	  strikes, gate repair and raid losses are not in the list and pay nothing. It is one-time per item and life:
	  nothing that pays can be sold, or bought twice in one life (spec_xp.md §5.1; a rebirth resets base levels, and
	  their rebuild pays again at Build.RebirthRebuildMult). Pool over the live catalogue: 56,073 base.
	Snapshot (lead decision XP-L1): the first time a save that predates this build loads with purchase XP on,
	  ProfileSchema.Migrate stores the build XP of what it already owns in BuildXP.Owed (capped at that pool) and gives
	  the save its BuildXP block, WHETHER OR NOT the backfill switch is on. From then on its purchases pay live, like a
	  new player's, and the snapshot never grows, so a purchase is paid by the snapshot or live, not both.
	Backfill switch: pays that snapshot, once (XPService.Push: quiet grant, one toast), and only in the life it was
	  taken in: after a rebirth it is dropped unpaid (BuildXP.AtPrestige, H1). A rebirth rebuild pays again, live, at
	  Build.RebirthRebuildMult. Ships OFF; the owner turns it on. The grant is exempt from the DoubleXP and territory
	  multipliers (lead decision XP-L2; the season x1.1 still applies), so it never waits on a game-pass check inside
	  the join routine.
	Revert: Enabled = false -> no purchase XP, no snapshot and no backfill (Build.Enabled / Backfill.Enabled switch
	  each half). Levels, XP already paid and an unpaid snapshot are kept. The curve reverts separately
	  (LevelConfig.CurveV2.Enabled = false).
	Tuning: do not change A, P or Cap until the backfill has been paid. A snapshot is counted with the formula of the
	  day it is taken, and the payment is capped at the pool of the day it is paid (a stored Owed is never re-capped at
	  load). A formula that pays nothing for the whole catalogue (Cap 0, A 0) counts as broken: X1 OFF, Owed kept.
	This module requires nothing (BuyPathStatic pin). ProfileSchema loads it in a pcall and checks every field and the
	three functions (validXPBalanceConfig); XPService uses ProfileSchema's checked copy. A broken edit here turns
	purchase XP, the snapshot and the backfill off in both; it never stops a profile from loading. The check needs
	"upgrade_" to stay a paying prefix and "recruit_soldiers" to pay nothing: turn purchase XP off with Build.Enabled.
]]

local XPBalanceConfig = {
	-- master switch for purchase XP, the snapshot and the backfill (not the curve)
	Enabled = true,

	-- base XP per purchase = min(Cap, floor(A * price ^ P)); $500 -> 17, $5,000 -> 56, $480,000 -> 554, cap from $1,562,500
	Build = { Enabled = true, A = 0.8, P = 0.5, Cap = 1000,
		ReasonPrefixes = { "upgrade_", "research_", "vehicle_", "weapon_" },
		Reason = "build",
		-- base-level purchases after a rebirth pay this share (1 = the same as the first time). Owner decision.
		RebirthRebuildMult = 1 },

	-- XP-L1: the snapshot is taken with this OFF; turning it ON pays each snapshot once, on that player's next join.
	-- (tools/BuyPathStatic.py pins Enabled = false: change that pin in the same edit that turns this on.)
	Backfill = { Enabled = false, Reason = "build_backfill", Toast = "★ LEVEL %d! Rank matches your base." },

	-- AddXP reasons that do not feed the battle-pass mirror (the pass is kill and daily paced)
	NoBattlePassMirror = { build = true, build_backfill = true } :: { [string]: boolean },
}

-- The purchase-XP formula alone, whatever the switches say (the backfill cap pool uses it: G5 must hold even when
-- purchase XP is switched off). 0 when price <= 0 or not a real number.
function XPBalanceConfig.BuildXPFormula(price: number): number
	if typeof(price) ~= "number" or price ~= price or price <= 0 or price == math.huge then
		return 0
	end
	local b = XPBalanceConfig.Build
	return math.min(b.Cap, math.floor(b.A * price ^ b.P))
end

-- Base build XP for one cash purchase of `price` (before the season / territory / DoubleXP multipliers).
-- 0 when purchase XP is off, when price <= 0, or when price is not a real number.
function XPBalanceConfig.BuildXP(price: number): number
	if not (XPBalanceConfig.Enabled and XPBalanceConfig.Build.Enabled) then
		return 0
	end
	return XPBalanceConfig.BuildXPFormula(price)
end

-- True when a SpendCash reason is a paying purchase ("upgrade_CommandCenter", "vehicle_ScoutCar", ...).
function XPBalanceConfig.IsBuildReason(reason: string?): boolean
	if typeof(reason) ~= "string" then
		return false
	end
	for _, prefix in ipairs(XPBalanceConfig.Build.ReasonPrefixes) do
		if string.sub(reason, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

return XPBalanceConfig
