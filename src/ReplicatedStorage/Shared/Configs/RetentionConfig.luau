--!strict
--[[
	claude-bud JOB 29 (2026-09-30): retention. The first-minute, offline and streak switches live beside the systems they
	change (TutorialConfig.FastStart, EconomyConfig.OfflineEarnings, DailyRewardConfig.ShowTomorrow). This file holds:
	  * the shared rollout rule;
	  * the onboarding timing log;
	  * the experience-notification opt-in, plus the state an external sender reads (docs/NOTIFICATIONS.md).
]]

local RunService = game:GetService("RunService")

local RetentionConfig = {
	--[[ Onboarding timing: seconds from join to each first-session step, once per session, NEW players only (the
		profile's first join within AnalyticsConfig.Roblox.FunnelNewPlayerSeconds). The steps are Joined,
		CharacterSpawned, BaseClaimed, Step1..7, FirstCash, FirstPurchase, FirstRecruit, FirstRobux and SessionEnd.
		Sent as the Roblox custom event "OnboardingSeconds" (value = seconds, field = step). In Studio it also prints
		"[FUNNEL] <step> t=<s>" for EVERY player, so a fresh-profile Studio run shows the times. Analytics only: it never
		changes the game. ]]
	Funnel = {
		Enabled = true,
		PrintInStudio = true,
	},
	--[[ Experience notifications (Roblox ExperienceNotificationService, a client API). Asked at a calm moment only:
		  * TutorialDelaySeconds after the tutorial ends (finished or skipped), on foot, with no panel open;
		  * or when the player taps TURN ON in Settings (NOTIFICATIONS row).
		The automatic ask (never on join, never every join):
		  * never in the first NotBeforeSeconds of a session;
		  * at most once per session;
		  * not again for DeclineCooldownDays after a decline (profile.NotifOptIn, saved);
		  * never after an accept.
		The client asks CanPromptOptInAsync, prompts, and reports the result on RequestNotifOptInResult (accepted /
		declined / unavailable; analytics NotificationOptIn).
		StateStore: one DataStore write per leave, with the fields an external sender reads (docs/NOTIFICATIONS.md). ]]
	Notifications = {
		Enabled = true,
		OwnerFirst = false, -- codebot_v136 launch (owner 2026-09-30 14:17): everyone
		NotBeforeSeconds = 60,
		TutorialDelaySeconds = 25, -- after the Starter Pack offer's slot (3 s after the tutorial)
		DeclineCooldownDays = 7,
		Moments = { TutorialComplete = true } :: { [string]: boolean },
		StateStore = "WE_NotifyState_v1",
		MaxPerDay = 1, -- enforced by the sender (docs/NOTIFICATIONS.md); LastSentDay is its field
	},
}

--[[ One owner-first rule for JOB 29's switches (a block with Enabled + OwnerFirst):
	  * Enabled ~= true: off for everyone (the kill switch; the game exactly as before);
	  * OwnerFirst == true: only AdminConfig.IsPlaytestOwner (UserId 470626172), plus every player in a Studio test
	    session (so a fresh-profile Studio run sees it);
	  * OwnerFirst == false: everyone.
	(A boolean, not an old-style owner rollout string, which codebot_v101 keeps out of Configs; this
	flag is new and Code Bot flips it when the owner is happy.) ]]
function RetentionConfig.Live(block: any, userId: any): boolean
	if typeof(block) ~= "table" or block.Enabled ~= true then
		return false
	end
	if block.OwnerFirst ~= true then
		return true
	end
	if RunService:IsStudio() then
		return true
	end
	return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)
end

function RetentionConfig.NotificationsLiveFor(userId: any): boolean
	return RetentionConfig.Live(RetentionConfig.Notifications, userId)
end

function RetentionConfig.OfflineLiveFor(userId: any): boolean
	return RetentionConfig.Live((require(script.Parent.EconomyConfig) :: any).OfflineEarnings, userId)
end

return RetentionConfig
