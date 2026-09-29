--!strict
--[[
	claude-bud JOB 14 (2026-09-29): game-feel polish from the phone tests (Server/Services/GameFeelService +
	Client/Modules/GameFeelClient). Owner-only first (Rollout per feature); OFF = the old behaviour, exactly.
	  * KillFeed: PvP kills and vehicle kills by a player, 2 short lines in the HUD top stack under the toasts (never a
	    fixed corner: the stack cannot overlap anything), 4 s each. DisplayNames only (never a nation). Blast deaths
	    stay quiet (nuke §15.2). The server drops lines over MaxPerSecond (never queued).
	  * VehicleNumbers: every hit on a vehicle shows a number at the hit (attacker: a gun / missile hit without a hit
	    point now uses the vehicle's position; splash that damages vehicles gets a hit marker too); the driver / owner
	    of the damaged vehicle sees a red number over it and a metal hit sound (merged per AggregateSeconds).
	  * RaidReport: an attack on your base (gate / guard hits, a breach, an ATM hold) opens a raid; QuietSeconds after
	    the last event you get ONE clear banner: "YOU WERE RAIDED -$N" (the ATM was robbed) or "BASE DEFENDED".
	  * SoundPass: every sound's volume kept inside its bus band (SoundConfig.Mix.Bands), and the actions that were
	    silent now make a sound (Sounds below; existing sound ids only, no new assets).
]]

local GameFeelConfig = {
	Rollout = {
		KillFeed = "owner",
		VehicleNumbers = "owner",
		RaidReport = "owner",
		SoundPass = "owner",
	} :: { [string]: string },

	KillFeed = {
		Lines = 2, -- at most this many lines at once (one short message area, never a list)
		Seconds = 4,
		MaxPerSecond = 4, -- server-wide; extra kill lines in the same second are dropped
		TextSize = 20, -- code px (14 real px under the phone HUD scale)
		Order = 47, -- HudConfig.TopStack.Order: after Toasts (40) and the event banner (45), before Offer (50)
		Width = 330,
	},

	VehicleNumbers = {
		AggregateSeconds = 0.25, -- the victim's numbers per vehicle are merged over this (≤ 4 pushes / s)
		Max = 4, -- live numbers on the client
		Seconds = 0.9,
		TextSize = 20,
	},

	RaidReport = {
		QuietSeconds = 20, -- no new hit / hold for this long = the raid is over
		BannerSeconds = 5,
		Order = 12, -- just under the Alert (10): the report is the one message on screen
	},

	Sounds = {
		KillFeedMine = "Hit.Kill", -- a feed line where you are the killer (the kill cue already plays: silent here)
		KillFeedVictim = "Toast.Error", -- a feed line where you died
		RaidLost = "Capture.Lost",
		RaidDefended = "Capture.Secured",
		VehicleHurt = "Impact.Metal",
		PremiumGun = "Weapon.AssaultRifle.Fire",
		PremiumMissile = "Weapon.RocketLauncher.Fire",
		Marker = "Capture.Start", -- the airdrop / bounty marker appears
		Tap = "UI.Click", -- the AIRSTRIKE button
		EventStart = "Toast.Reward", -- the weekly event banner appears
	},
}

function GameFeelConfig.LiveFor(feature: string, userId: any): boolean
	local mode = GameFeelConfig.Rollout[feature]
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)
	end
	return false
end

return GameFeelConfig
