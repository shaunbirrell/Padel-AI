--!strict
--[[
	NotificationConfig — toast lane + offer toast tunables that are NOT layout (layout, colours, holds, the
	Reroute / Drop tables and the offer throttle numbers live in HudConfig.Toast / HudConfig.Offer).

	v70 "clean screen": NotificationController draws plain outlined text lines in the top-centre stack (max 2,
	coalesced, prioritised) — no cards. Money moves at the cash pill (HudLayout.CashFloat), not mid-screen.
	The Purchase SUCCESSFUL line stays the green Success type (HIGH_CONTRAST_SUCCESS marker in the controller).

	Order a message goes through (NotificationController.route):
	  1. Rewrite      text / type fixes for today's server lines (glyphs FredokaOne lacks, type upgrades)
	     AlertEcho    strike-result lines are dropped while the Alert banner already shows them
	  2. Reroute      HudConfig.Toast.Reroute (Collected → float, kills → float, DEF HIT → one BASE UNDER ATTACK)
	  3. Drop         HudConfig.Toast.Drop (+ LocalExemptDrop for server-sent lines only)
	  4. Throttle     per-pattern minimum gaps / once-per-text for recurring server lines
	  5. PurchaseFailure echo dedupe (one failed buy = one line)
	  6. the lane (coalesce "×N", max 2, priority)
]]

export type RewriteRule = { Match: string, Replace: string?, Type: string? }
export type ThrottleRule = { Match: string, MinGapSeconds: number?, OncePerText: boolean? }

local NotificationConfig = {
	-- legacy fields (kept for any caller that still reads them)
	DefaultDuration = 4,
	MaxStacked = 4,
	Types = {
		Info = { Color = Color3.fromRGB(90, 160, 220), Fill = Color3.fromRGB(18, 28, 40) },
		-- High-contrast success (competitor "Purchase SUCCESSFUL!" readability)
		Success = { Color = Color3.fromRGB(40, 255, 120), Fill = Color3.fromRGB(8, 48, 22) },
		Collect = { Color = Color3.fromRGB(60, 255, 140), Fill = Color3.fromRGB(6, 42, 20) },
		Warn = { Color = Color3.fromRGB(255, 200, 60), Fill = Color3.fromRGB(40, 32, 10) },
		Error = { Color = Color3.fromRGB(255, 80, 80), Fill = Color3.fromRGB(48, 12, 12) },
		Reward = { Color = Color3.fromRGB(255, 210, 90), Fill = Color3.fromRGB(40, 32, 12) },
	},

	-- lane --------------------------------------------------------------------------------------------------
	-- A caller's Duration may lengthen a line up to this (server lines ask 3.5-7 s; the lane is meant to be brief)
	MaxHoldSeconds = 4,
	MinHoldSeconds = 1.2,
	-- When 2 lines are up and a new one arrives, the oldest line of the LOWEST priority goes first
	-- (a gold level-up line outlives an "Outposts held" Info line). Equal priority → oldest goes.
	Priority = { Error = 4, Reward = 4, Warn = 4, Success = 3, Info = 1 },
	-- Coalesce "×N" suffix (HudConfig.Toast.CoalesceWindow / CoalesceKey = digits stripped)
	CoalesceSuffix = " ×%d",
	-- measured text box padding in v (UIStroke is drawn outside the glyphs)
	LinePadX = 8,
	LinePadY = 2,

	-- 1. Rewrite: first match wins; Replace is a string.gsub replacement for Match (nil = keep text).
	Rewrite = ({
		-- XPService "★ LEVEL 9! — Sniper Rifle unlocked" (Success today) → the gold Reward line of the spec
		{ Match = "^(★ LEVEL %d+!) — ", Replace = "%1 ", Type = "Reward" },
		{ Match = "^★ LEVEL %d+!", Type = "Reward" },
		-- "Purchase SUCCESSFUL! Helipad → Lv 2": FredokaOne has no "→" (spec risk #5)
		{ Match = " → Lv (%d+)", Replace = " Lv %1" },
		-- server purchase-failure echo uses the competitor wording the client uses
		{ Match = "^Not enough cash$", Replace = "You need more Money!", Type = "Warn" },
		-- raids (RaidConfig.Text): short lines, no "→" / emoji (FredokaOne lacks them); the shield chip shows the timer
		{ Match = "^ATM RAIDED by (.-) (−%$[%d,%.KMB]+).*$", Replace = "ATM raided by %1! %2", Type = "Error" },
		{ Match = "^ATM RAID %+(%$[%d,%.KMB]+) from (.-) → your ATM$", Replace = "Raided %2's ATM! +%1", Type = "Success" },
	} :: { RewriteRule }),

	-- Server lines that repeat what the Alert slot banner already says (MissileController's INCOMING MISSILE
	-- banner shows the strike result for a few seconds) — dropped only while an alert banner is visible.
	AlertEcho = {
		"Missile hit! Defenses down",
		"Your Missile Defense shot down",
		"^Direct hit! ",
		"^Intercepted by ",
		"INCOMING MISSILE",
	},

	-- 3. Drop patterns that apply ONLY to server-sent lines (a local NotificationController.Show of the same
	-- words is intended: OrdersController's T-key "Squad: FOLLOW" Info line while the Army popover is closed).
	LocalExemptDrop = { "^Squad: " },

	-- 4. Throttle recurring server lines on the client (the §4.2 server fixes are deferred)
	Throttle = ({
		{ Match = "^Rebirth almost ready", OncePerText = true }, -- every 90 s today; once per level per session
		{ Match = "^REBIRTH READY", MinGapSeconds = 600 },
		{ Match = "^Raid cooldown", MinGapSeconds = 10 }, -- ATM raid cooldown Warn while standing at the ATM
		{ Match = "is robbing your ATM", MinGapSeconds = 15 },
		{ Match = "^Nothing to collect yet", MinGapSeconds = 20 },
		{ Match = "^Cash drop is recharging", MinGapSeconds = 30 },
	} :: { ThrottleRule }),

	-- 5. One failed purchase = one line. WorldPromptController shows the failure first (WE_BuyAck / PurchaseResult,
	-- via NotificationController.ShowPurchaseFailure); any other purchase-failure line within WindowSeconds —
	-- the second client path or the server's own Warn echo (BaseService / UpgradePadService) — is skipped.
	PurchaseFailure = {
		WindowSeconds = 1.5,
		Patterns = {
			"^You need more Money!$",
			"^Not enough gold$",
			"^Already at MAX level$",
			"^Missing prerequisite structure$",
			"^Unknown structure$",
			"^Buying too fast",
			"^Profile still loading",
			"^Buy failed",
			"^Purchase failed: ",
			"^Not your base — walk your plot pads to buy$",
			"^Claim a base first",
			"^Go to your .+ console to buy it$", -- v71 NotAtConsole (ConsoleBuyConfig.Text.NotAtConsole)
		},
	},

	-- offer toast (the numbers — MaxPerSession 3, MinGapSeconds 240, FirstAfterJoinSeconds 90, death 600 s,
	-- queue 60 s — are in HudConfig.Offer so the money plan tunes them in one place)
	Offer = {
		DeathKeyPattern = "^Death", -- ShopController.DeathShopToast's Key → HudConfig.Offer.DeathOfferMinGapSeconds
		QueueMax = 3, -- deferred offers waiting for a calm moment (one per Key)
		TickSeconds = 0.5, -- queue / expiry check
		IconSize = Vector2.new(36, 28), -- v, HudIcons "Cash"
		-- touch: GET / ✕ hit areas are 64 v (44.8 px) instead of the desktop 44 v, so the pill may grow this much
		-- past HudConfig.Offer.MaxWidth (still capped at the stack's 0.62 × content) to keep the Sub line readable
		TouchExtraWidth = 120,
		GetText = "GET", -- fallback CTA
		CloseText = "✕",
	},
}

return NotificationConfig
