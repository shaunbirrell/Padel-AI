--!strict
--[[
	claude-bud JOB 40 part D (2026-09-30): the "Enjoying WAR EMPIRE?" reminder. NO REWARD of any kind: Roblox forbids
	rewarding a like / favourite, there is no API to see a like, and nothing here claims or checks one.
	The server decides when (Services/RatePromptService); the client only shows the card and reports the button
	(Controllers/RatePromptController). OFF (Enabled = false, or not live for the player) = nothing shows; the Shop's
	"Favorite WAR EMPIRE" row is unchanged either way.
]]

local RatePromptConfig = {
	Enabled = true, -- kill switch
	OwnerFirst = false, -- codebot_v166 flip-all-live (owner 2026-10-01 10:31): everyone

	PlaySecondsBeforeShow = 900, -- 15 min of total play (RatePrompt.PlaySeconds, across sessions)
	MinGapSeconds = 259200, -- 3 days between shows
	CombatQuietSeconds = 20, -- no damage taken for this long (server); the client also waits out its RecentCombat
	NotBeforeSessionSeconds = 60, -- never in the first minute of a session
	-- a TRIGGER shows it early (still under every other rule): every rebirth, and the achievements that already
	-- show a big banner (AchievementConfig Big = true: $100M, Plaza capture, nuke, weekly #1, ...)
	Triggers = { rebirth = true, achievement = true, FirstCapture = true, RaidWin = true },
	-- claude-bud JOB 41 part D: these big wins bring it forward ONCE per profile (RatePrompt.Triggered[<name>] = true
	-- when it showed for that reason); FirstCapture = the Guided reward capture or any first territory, RaidWin = the
	-- first raid that looted (a SEND or an in-person ATM raid)
	OneTimeTriggers = { FirstCapture = true, RaidWin = true },
	AfterOtherCardSeconds = 20, -- never two cards at once: wait this long after the Recruit Pack card closed
	WaitForPackMaxSeconds = 180, -- a Recruit Pack still due at the capture goes first; the rate card waits at most this
	TriggerDelaySeconds = 8, -- after the rebirth screen / the banner has had its moment
	TickSeconds = 5, -- the server check (all players together)
	AutoHideSeconds = 20, -- the card hides itself (counts as shown)
	ClientWaitMaxSeconds = 90, -- the client waits for a free screen at most this long, then drops it ("timeout")

	Answers = { later = true, never = true, favorite = true, timeout = true }, -- the only RequestRatePromptAnswer values

	Text = {
		Title = "Enjoying WAR EMPIRE?",
		Body = "Tap 👍 on the game page. It really helps!",
		Favorite = "⭐ Favorite",
		Later = "Maybe later",
		Never = "Don't show again",
	},
}

function RatePromptConfig.LiveFor(userId: any): boolean
	return (require(script.Parent.RetentionConfig) :: any).Live(RatePromptConfig, userId)
end

return RatePromptConfig
