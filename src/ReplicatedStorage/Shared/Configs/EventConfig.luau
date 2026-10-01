--!strict
--[[
	Code Bot v185: DOUBLE WEEKEND (one central config for the time-gated event). Server-authoritative: the grants read
	os.time() (UTC) on the server through Server/Modules/DoubleEvent; nothing a client sends can switch it on.

	Window: StartUnix 1790971200 = Fri 2 Oct 2026 20:00 UTC (21:00 Dublin IST) .. EndUnix 1791144000 = Sun 4 Oct 2026
	20:00 UTC (21:00 Dublin IST). Inside the window it is LIVE FOR EVERYONE, whatever OwnerFirst says.
	OwnerFirst gates ONLY the preview BEFORE StartUnix: while it is true (or the owner's /eventpreview on), the owner
	(OwnerUserId, shaunie6) has the event active early so he can test it. OwnerFirst = false -> no preview; the event
	still runs for everyone, only inside the window. After EndUnix it is off for everyone (preview included).

	What it multiplies (Server/Modules/DoubleEvent):
	  * CashMult: EconomyService.cashMultFor, the NON-exempt stack only (the same reasons the 2x Cash pass multiplies),
	    minus CashExemptReasons below. AccruePendingCash multiplies at accrue time, so passive income that accrues in the
	    window is doubled (the collector pays what accrued). Offline cash: only the share of the counted offline span that
	    lies inside the window (RetentionService).
	  * XPMult: XPService.AddXP, the reasons the 2x XP pass multiplies (MonetizationConfig.XPMultExemptReasons), minus
	    XPExemptReasons below.
	  * KillMult: the kill rewards (KillReasons: their cash AND xp take KillMult instead of CashMult / XPMult, so a kill
	    pays 2x, not 4x) and the kill COUNT toward missions (KillPlayer / KillNPC) and the MOST KILLS / ARMY KILLS boards.
	  * ExtraCashReasons (Code Bot v197): fixed payouts that are 2x-pass EXEMPT (MonetizationConfig.CashMultExemptReasons)
	    but the event still doubles: EconomyService.cashMultFor's exempt branch applies ONLY CashMult for these (no pass,
	    prestige, tax, ...). Each is doubled once, at its grant: oil pumps at AccruePendingCash (the collect is
	    "collector", never multiplied), jobs, supply drops / airdrops, a bank raid WITHOUT a heist kit (a kit's payout
	    is minutes of WE_IncomePerSec, already doubled, so it is paid as "bank_raid_kit", not listed) and clan war cash.
	    Codes, battle pass, onboarding, invite / friends / comeback, spinner, clicker dropper, Robux, admin and refunds
	    are NOT listed (never doubled).
	Stacking: multiplicative on top of everything already there (2x Cash / 2x XP pass, prestige, empire tax, season,
	code CashBoost, the EngagementConfig weekly event). Robux purchases, refunds, admin grants and sell-backs are exempt.
]]

local EventConfig = {
	Id = "DoubleWeekend1",
	Name = "DOUBLE WEEKEND",
	StartUnix = 1790971200, -- Fri 2 Oct 2026 20:00 UTC = 21:00 Dublin
	EndUnix = 1791144000, -- Sun 4 Oct 2026 20:00 UTC = 21:00 Dublin
	XPMult = 2,
	CashMult = 2,
	KillMult = 2,
	OwnerFirst = true, -- NEW-OWNER-FIRST (Code Bot v185): owner preview BEFORE StartUnix only; never gates the real window
	OwnerUserId = 470626172, -- shaunie6
	BannerLeadSeconds = 24 * 3600, -- everyone sees "starts in ..." from 24 h before the start
	-- Roblox experience event (Creator Hub) for the banner's NOTIFY ME (SocialService RSVP). "" = no button.
	EventId = "5990901055452480269", -- a string: event ids do not fit a Luau number
	BannerText = "DOUBLE WEEKEND · 2x XP · 2x CASH · 2x KILLS",
	-- Code Bot v192 (owner: "the banner stays stuck on screen, ugly and blocking"): the top-centre banner is gone.
	--   BEFORE the start: a ONE-TIME centred pop-up (once per player per Id: profile.EventPopupSeen[Id], a new profile
	--   field; replicated as the PopupSeenAttr player attribute), a few seconds after spawn, never over the tutorial /
	--   onboarding hold / another panel or first-join card; skipped when GetEventRsvpStatusAsync says Going.
	--   DURING the live window (or the owner preview): only a small chip under the TARGETS card ("2x WEEKEND · 1d 4h");
	--   tap = the details card. After EndUnix: nothing.
	PopupTitle = "DOUBLE WEEKEND",
	PopupWhen = "Fri 9pm – Sun 9pm (Irish time)",
	PopupPerks = "2x XP · 2x Cash · 2x Kills",
	PopupAsk = "Get notified when it starts?",
	PopupDelaySeconds = 6, -- after the character spawns (and the screen has been free for PopupQuietSeconds)
	PopupQuietSeconds = 2,
	PopupSeenAttr = "WE_EventPopupSeen", -- player attribute (server-written on profile load): true = already shown
	PopupTestAttr = "WE_EventPopupTest", -- player attribute: the owner's /eventpopup bumps it -> show the pop-up now
	ChipText = "2x WEEKEND",

	KillReasons = {
		pvp_kill = true,
		npc_kill = true,
		npc_kill_squad = true,
		guard_kill = true,
		guard_unit_kill = true,
		army_unit_kill = true,
		vehicle_kill = true,
		nuke_kill = true,
	} :: { [string]: boolean },
	-- on top of EconomyService NEVER_MULTIPLIED + MonetizationConfig.CashMultExemptReasons (devproduct, purchase_refund,
	-- admin, code, collector, offline, ...): perk / fixed / test payouts the 2x pass happens to multiply
	CashExemptReasons = {
		devproduct = true,
		purchase_refund = true,
		admin = true,
		dismiss_soldiers = true,
		premium_daily = true,
		group_reward = true,
		vip_lounge = true,
		vip_supply = true,
		studio_smoke_buy = true,
		studio_smoke_buy_barracks = true,
	} :: { [string]: boolean },
	-- Code Bot v197: 2x-pass-exempt cash reasons the event doubles anyway (see the header); the pass still skips them
	ExtraCashReasons = {
		plot_oil = true, -- oil pumps (PendingCash, at accrue)
		ops = true, -- jobs (OpsConfig.Rewards.CashReason)
		supply_drop = true, -- supply drops + airdrops
		bank_raid = true, -- bank raid without a heist kit (a kit pays "bank_raid_kit": income-scaled, not listed)
		clan_war_win = true,
		clan_war_participate = true,
	} :: { [string]: boolean },
	XPExemptReasons = {
		admin = true,
		build_backfill = true,
	} :: { [string]: boolean },
	KillObjectives = { KillPlayer = true, KillNPC = true } :: { [string]: boolean },
}

-- the real window (everyone)
function EventConfig.InWindow(now: number): boolean
	return now >= EventConfig.StartUnix and now < EventConfig.EndUnix
end

-- is the event active for userId at `now` (UTC seconds); previewOn = the server's owner preview switch
function EventConfig.ActiveFor(userId: any, now: number, previewOn: boolean): boolean
	if EventConfig.InWindow(now) then
		return true
	end
	if now < EventConfig.StartUnix and previewOn == true and tonumber(userId) == EventConfig.OwnerUserId then
		return true
	end
	return false
end

-- banner state: "live" (active for him: show "ends in"), "soon" (within BannerLeadSeconds of the start: "starts in"),
-- or nil (hidden; after EndUnix always nil)
function EventConfig.BannerState(userId: any, now: number, previewOn: boolean): string?
	if now >= EventConfig.EndUnix then
		return nil
	end
	if EventConfig.ActiveFor(userId, now, previewOn) then
		return "live"
	end
	if now < EventConfig.StartUnix and EventConfig.StartUnix - now <= EventConfig.BannerLeadSeconds then
		return "soon"
	end
	return nil
end

-- "1d 4h" / "3h 12m" / "4m 09s"
function EventConfig.FormatLeft(sec: number): string
	sec = math.max(0, math.floor(sec))
	local d = sec // 86400
	local h = (sec % 86400) // 3600
	local m = (sec % 3600) // 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm %02ds", m, sec % 60)
end

-- seconds of [a, b) inside the window (offline pay)
function EventConfig.OverlapSeconds(a: number, b: number): number
	local lo = math.max(a, EventConfig.StartUnix)
	local hi = math.min(b, EventConfig.EndUnix)
	return math.max(0, hi - lo)
end

EventConfig.PreviewAttr = "WE_EventPreview" -- ReplicatedStorage attribute, written by the server only

return EventConfig
