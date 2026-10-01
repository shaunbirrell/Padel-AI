--!strict
--[[
	claude-bud JOB 29 (2026-09-30): retention, server side. Everything here is decided on the server; the client only
	shows cards and reports an opt-in result. Each part has a kill switch and ships OwnerFirst (RetentionConfig.Live).

	1. FAST START (TutorialConfig.FastStart)
	   * FastStartCFrame: BaseService.TeleportToPlot lands a new player StandStuds in front of his OWN Command Center
	     console. "New" = the Command Center is not bought and the tutorial is not done.
	   * The onboarding hold: the player attribute WE_Onboarding = true until the tutorial is past the Command Center
	     step, or HoldMaxSeconds. While it is on, the daily-streak card, the welcome-back card, the nation picker and
	     promos wait (WaitOnboarding).
	   * The starter payout: the first Command Center L1 of a profile still in the tutorial pays StarterPayout
	     (reason "onboarding", once per profile: StarterPayoutDone) and a FeaturePush "StarterPayout" (the coin burst).
	2. OFFLINE EARNINGS (EconomyConfig.OfflineEarnings), on load, with the live passive tick's formula:
	   * away = os.time() - PrevSeenUnix (the save's last write), capped at CapSeconds;
	   * no payout on a first join, a negative gap, or a gap under MinSeconds;
	   * pay = ComputePassiveIncomePerTick x GetCashMult("passive") / TickSeconds x away x Share, x Premium bonus;
	   * paid straight into PendingCash (the ATM), reason "offline" (never multiplied twice);
	   * then FeaturePush "WelcomeBack" (the "Welcome back: +$X while away" card) after ShowDelaySeconds and the hold.
	3. NOTIFICATIONS (RetentionConfig.Notifications)
	   * GoodMoment(player, "TutorialComplete") sends FeaturePush "NotifOptIn":
	     - TutorialDelaySeconds after the tutorial ends;
	     - at most once per session;
	     - never in the first NotBeforeSeconds;
	     - never within DeclineCooldownDays of a decline;
	     - never after an accept.
	   * Settings' TURN ON asks the client directly; it reports with source "settings".
	   * RequestNotifOptInResult records the answer in profile.NotifOptIn (analytics NotificationOptIn).
	   * On leave, one DataStore write (StateStore) with what an external sender reads (docs/NOTIFICATIONS.md), only
	     for a player who accepted.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TutorialConfig = require(Shared.Configs.TutorialConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local DailyRewardConfig = require(Shared.Configs.DailyRewardConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)
local ConsoleLocator = require(Shared.Util.ConsoleLocator)

local RetentionService = {}

local DataService: any = nil
local EconomyService: any = nil
local BaseService: any = nil
local RemoteSetup: any = nil
local RateLimitService: any = nil
local AnalyticsService: any = nil

local sessionAt: { [number]: number } = {} -- userId -> os.clock() at join
local promptedThisSession: { [number]: boolean } = {}
local awaitingResult: { [number]: boolean } = {}
local holdToken: { [number]: number } = {}

local ONBOARD_ATTR = "WE_Onboarding"

local function push(player: Player, kind: string, data: any)
	local ev = RemoteSetup and RemoteSetup.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, kind, data)
	end
end

local function log(player: Player, eventName: string, props: { [string]: any }?)
	if AnalyticsService and AnalyticsService.Log then
		pcall(AnalyticsService.Log, eventName, player.UserId, props)
	end
end

local function offlineCfg(): any
	return (EconomyConfig :: any).OfflineEarnings
end

-- ── 1. FAST START ──────────────────────────────────────────────────────────────────────────────────────────────────
local function isNewPlayer(profile: any): boolean
	if typeof(profile) ~= "table" or profile.TutorialComplete == true then
		return false
	end
	local cc = if typeof(profile.BaseUpgrades) == "table" then tonumber(profile.BaseUpgrades.CommandCenter) or 0 else 0
	return cc < 1
end

--[[ Where BaseService.TeleportToPlot puts a new player: StandStuds in front of the face of HIS plot's Command Center
	console, facing it, at the height ConsoleLocator.StandCFrame uses. nil = the normal plot spawn (FastStart off or not
	live for him, not a new player, or no console found on the plot yet). Pure reads; no yield. ]]
function RetentionService.FastStartCFrame(player: Player, profile: any, plotId: number?): CFrame?
	if plotId == nil or not TutorialConfig.FastStartLiveFor(player.UserId) or not isNewPlayer(profile) then
		return nil
	end
	local part = ConsoleLocator.Find(plotId, "CommandCenter")
	if part == nil then
		return nil
	end
	local stand = math.clamp(tonumber(TutorialConfig.FastStart.StandStuds) or 7, 3, 9)
	local at = (part.CFrame * CFrame.new(0, 1.3, -stand)).Position + Vector3.new(0, 1.5, 0)
	local look = Vector3.new(part.Position.X, at.Y, part.Position.Z)
	if (look - at).Magnitude < 0.5 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, look)
end

local function setHold(player: Player, on: boolean)
	pcall(function()
		if (player:GetAttribute(ONBOARD_ATTR) == true) ~= on then
			player:SetAttribute(ONBOARD_ATTR, if on then true else nil)
		end
	end)
end

-- true while this player's screen must stay clear (FastStart hold)
function RetentionService.IsOnboarding(player: Player): boolean
	return player:GetAttribute(ONBOARD_ATTR) == true
end

--[[ Yields until the onboarding hold is off (or maxSeconds, or the player left). Returns false when the player left. ]]
function RetentionService.WaitOnboarding(player: Player, maxSeconds: number?): boolean
	local left = math.max(0, tonumber(maxSeconds) or 90)
	while player.Parent and player:GetAttribute(ONBOARD_ATTR) == true and left > 0 do
		task.wait(0.5)
		left -= 0.5
	end
	return player.Parent ~= nil
end

-- claude-bud JOB 41: the step the hold lasts until, and its cap. A Guided profile (OrderVersion 4) is held for the
-- whole chain up to the Reward (Guided.HoldMaxSeconds); everyone else exactly as JOB 29 (HoldPopupsUntilStep, 60 s).
local function holdUntil(profile: any): (number, number)
	local G: any = (TutorialConfig :: any).Guided
	-- claude-bud JOB 48: both Guided orders (4, and the Hook's 5) hold up to their own Reward step
	if G and profile and TutorialConfig.IsGuidedVersion(profile.TutorialOrderVersion) then
		local r = TutorialConfig.IndexOf("Reward", TutorialConfig.StepsFor(profile.TutorialOrderVersion))
		if r then
			return r + 1, math.max(5, tonumber(G.HoldMaxSeconds) or 300)
		end
	end
	return tonumber(TutorialConfig.FastStart.HoldPopupsUntilStep) or 3, math.max(5, tonumber(TutorialConfig.FastStart.HoldMaxSeconds) or 60)
end
RetentionService._HoldUntil = holdUntil

-- TutorialService tells us each step change (after it is saved)
function RetentionService.OnTutorialStep(player: Player, step: number, complete: boolean)
	local until_ = holdUntil(DataService and DataService.GetProfile(player))
	if player:GetAttribute(ONBOARD_ATTR) == true and (complete or step >= until_) then
		setHold(player, false)
	end
	if complete then
		-- the calm moment for the notification ask: after the Starter Pack offer's slot, once he is on foot
		local delaySec = math.max(5, tonumber(RetentionConfig.Notifications.TutorialDelaySeconds) or 25)
		task.delay(delaySec, function()
			if player.Parent then
				RetentionService.GoodMoment(player, "TutorialComplete")
			end
		end)
	end
end

local function startHold(player: Player, profile: any)
	if not TutorialConfig.FastStartLiveFor(player.UserId) or profile.TutorialComplete == true then
		return
	end
	local untilStep, maxSeconds = holdUntil(profile) -- claude-bud JOB 41: the Guided chain holds longer
	if (tonumber(profile.TutorialStep) or 1) >= untilStep then
		return
	end
	setHold(player, true)
	local uid = player.UserId
	local my = (holdToken[uid] or 0) + 1
	holdToken[uid] = my
	task.delay(maxSeconds, function()
		if holdToken[uid] == my and player.Parent then
			setHold(player, false)
		end
	end)
end

local function onUpgrade(player: Player, structureId: string, level: number)
	if structureId ~= "CommandCenter" or level ~= 1 or not TutorialConfig.FastStartLiveFor(player.UserId) then
		return
	end
	local profile = DataService and DataService.GetProfile(player)
	if profile == nil or profile.StarterPayoutDone == true or profile.TutorialComplete == true then
		return
	end
	local amount = math.max(0, math.floor(tonumber(TutorialConfig.FastStart.StarterPayout) or 0))
	profile.StarterPayoutDone = true
	DataService.MarkDirty(player)
	if amount <= 0 then
		return
	end
	local ok = EconomyService and EconomyService.AddCash(player, amount, "onboarding")
	if ok then
		push(player, "StarterPayout", { Cash = amount, Text = TutorialConfig.FastStart.PayoutText })
	end
end

-- ── 2. OFFLINE EARNINGS ────────────────────────────────────────────────────────────────────────────────────────────
-- the live passive tick's rate, per second: ComputePassiveIncomePerTick x the "passive" cash multiplier / TickSeconds
local function incomePerSecond(player: Player, profile: any): number
	if BaseService == nil or BaseService.ComputePassiveIncomePerTick == nil then
		return 0
	end
	local ok, perTick = pcall(BaseService.ComputePassiveIncomePerTick, profile, player)
	if not ok or typeof(perTick) ~= "number" or perTick ~= perTick or perTick <= 0 then
		return 0
	end
	local mult = 1
	if EconomyService and EconomyService.GetCashMult then
		local okM, m = pcall(EconomyService.GetCashMult, player, "passive")
		if okM and typeof(m) == "number" and m == m and m > 0 then
			mult = m
		end
	end
	return perTick * mult / math.max(1, tonumber(EconomyConfig.PassiveIncome.TickSeconds) or 5)
end

local function premiumMult(player: Player): number
	local isPremium = false
	pcall(function()
		isPremium = player.MembershipType == Enum.MembershipType.Premium
	end)
	return if isPremium then 1 + math.max(0, tonumber(offlineCfg().PremiumBonus) or 0) else 1
end

--[[ Pure: the offline payout for the gap prevSeen -> now at `perSec` income, `mult` (Premium), with config `o`.
	Returns (cash, secondsCounted). First join (prevSeen <= 0), negative or short gaps -> 0. ]]
function RetentionService.ComputeOffline(prevSeen: number, now: number, perSec: number, mult: number, o: any): (number, number)
	if prevSeen <= 0 or perSec <= 0 or perSec ~= perSec then
		return 0, 0
	end
	local away = now - prevSeen
	if away ~= away or away < math.max(0, tonumber(o.MinSeconds) or 0) then
		return 0, 0
	end
	local counted = math.min(away, math.max(0, tonumber(o.CapSeconds) or 0))
	local share = math.clamp(tonumber(o.Share) or 0, 0, 1)
	return math.floor(perSec * counted * share * mult), math.floor(counted)
end

-- claude-bud JOB 49 B: this player's cap in seconds: CapSeconds, x CapBoost.CapMult only with the OfflineCap2x
-- entitlement while CapBoost is live (it is DISABLED until Shaun approves a price). Never touches Share.
local function capSecondsFor(player: Player, profile: any): number
	local o = offlineCfg()
	local cap = math.max(0, tonumber(o.CapSeconds) or 0)
	local b = o.CapBoost
	if typeof(b) == "table" and RetentionConfig.Live(b, player.UserId) and typeof(profile) == "table"
		and typeof(profile.Entitlements) == "table" and profile.Entitlements[b.ProductKey] == true then
		cap *= math.max(1, tonumber(b.CapMult) or 1)
	end
	return cap
end

function RetentionService.OfflineCapSeconds(player: Player): number
	local profile = DataService and DataService.GetProfile(player)
	return if profile then capSecondsFor(player, profile) else math.max(0, tonumber(offlineCfg().CapSeconds) or 0)
end

-- what a full cap pays at this player's income now (the Missions "tomorrow" line and the sender state)
local function offlineCapCash(player: Player, profile: any): number
	local o = offlineCfg()
	return math.floor(incomePerSecond(player, profile) * capSecondsFor(player, profile) * math.clamp(tonumber(o.Share) or 0, 0, 1) * premiumMult(player))
end

function RetentionService.OfflineCapCash(player: Player): number
	local profile = DataService and DataService.GetProfile(player)
	if profile == nil or not RetentionConfig.OfflineLiveFor(player.UserId) then
		return 0
	end
	return offlineCapCash(player, profile)
end

local function onLoadOffline(player: Player, profile: any)
	if not RetentionConfig.OfflineLiveFor(player.UserId) then
		return
	end
	local o = offlineCfg()
	local capSec = capSecondsFor(player, profile) -- claude-bud JOB 49 B: CapSeconds (x CapMult with the disabled hook)
	local oc = table.clone(o)
	oc.CapSeconds = capSec
	local cash, seconds = RetentionService.ComputeOffline(
		tonumber(profile.PrevSeenUnix) or 0,
		os.time(),
		incomePerSecond(player, profile),
		premiumMult(player),
		oc
	)
	profile.PrevSeenUnix = nil -- paid once per load: a later call in this session finds nothing
	-- claude-bud JOB 49 D: the return sequence: the Comeback cash (EngagementService, already paid) rides on this card
	local seq = typeof(RetentionConfig.ReturnSequence) == "table" and RetentionConfig.Live(RetentionConfig.ReturnSequence, player.UserId)
	if cash <= 0 or not EconomyService or not EconomyService.AccruePendingCash(player, cash, "offline") then
		if seq then
			task.delay(math.max(1, tonumber(o.ShowDelaySeconds) or 6), function()
				local comeback = tonumber(player:GetAttribute("WE_ComebackCash")) or 0
				if comeback > 0 and player.Parent and RetentionService.WaitOnboarding(player, 90) then
					player:SetAttribute("WE_ComebackCash", nil)
					push(player, "WelcomeBack", { Cash = 0, Seconds = 0, Comeback = comeback, Collect = nil })
				end
			end)
		end
		return
	end
	log(player, "OFFLINE_EARNED", { cash = cash, hours = string.format("%.1f", seconds / 3600) })
	log(player, "OFFLINE_COLLECTED", { cash = cash, capped = if seconds >= capSec then "yes" else "no" }) -- claude-bud JOB 49
	task.delay(math.max(1, tonumber(o.ShowDelaySeconds) or 6), function()
		if player.Parent and RetentionService.WaitOnboarding(player, 90) then
			local card = typeof(o.Card) == "table" and RetentionConfig.Live(o.Card, player.UserId)
			local comeback = if seq then tonumber(player:GetAttribute("WE_ComebackCash")) or 0 else 0
			if comeback > 0 then
				player:SetAttribute("WE_ComebackCash", nil)
			end
			push(player, "WelcomeBack", {
				Comeback = if comeback > 0 then comeback else nil, -- claude-bud JOB 49 D: one card for both
				Cash = cash,
				Seconds = seconds,
				Capped = seconds >= capSec,
				Premium = premiumMult(player) > 1,
				CapHours = if card then math.floor(capSec / 3600 + 0.5) else nil, -- claude-bud JOB 49 B: "(capped at N h)"
				Collect = if card then true else nil, -- claude-bud JOB 49 B: COLLECT draws the gold line to his ATM
			})
		end
	end)
end

-- ── 3. NOTIFICATIONS ───────────────────────────────────────────────────────────────────────────────────────────────
--[[ A calm moment to ask for notifications ("TutorialComplete"). Sends the client the ask when every rule passes; the
	client decides with CanPromptOptInAsync whether Roblox lets it prompt. ]]
function RetentionService.GoodMoment(player: Player, moment: string)
	local N = RetentionConfig.Notifications
	if not RetentionConfig.NotificationsLiveFor(player.UserId) or N.Moments[moment] ~= true then
		return
	end
	local uid = player.UserId
	if promptedThisSession[uid] or RetentionService.IsOnboarding(player) then
		return
	end
	local at = sessionAt[uid]
	if at == nil or os.clock() - at < (tonumber(N.NotBeforeSeconds) or 60) then
		return
	end
	local profile = DataService and DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local n = if typeof(profile.NotifOptIn) == "table" then profile.NotifOptIn else {}
	if n.Result == "accepted" then
		return
	end
	local declined = tonumber(n.DeclinedAt) or 0
	if declined > 0 and os.time() - declined < (tonumber(N.DeclineCooldownDays) or 7) * 86400 then
		return
	end
	promptedThisSession[uid] = true
	awaitingResult[uid] = true
	push(player, "NotifOptIn", { Moment = moment })
end

-- the client's answer: to our ask (awaitingResult) or to the player's own Settings tap (source "settings")
local function onOptInResult(player: Player, result: any, source: any)
	local uid = player.UserId
	local fromSettings = source == "settings"
	if (not awaitingResult[uid] and not fromSettings) or (result ~= "accepted" and result ~= "declined" and result ~= "unavailable") then
		return
	end
	awaitingResult[uid] = nil
	promptedThisSession[uid] = true
	local profile = DataService and DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local n = if typeof(profile.NotifOptIn) == "table" then profile.NotifOptIn else {}
	n.PromptedAt = os.time()
	if result ~= "unavailable" then
		n.Result = result
	end
	if result == "declined" then
		n.DeclinedAt = os.time()
	end
	profile.NotifOptIn = n
	DataService.MarkDirty(player)
	log(player, "NOTIF_OPTIN", { result = result .. (if fromSettings then "_settings" else "") })
end

--[[ docs/NOTIFICATIONS.md: the record an external sender reads, written once when an opted-in player leaves. Fields are
	os.time() seconds (0 = never / not applicable). LastSentDay belongs to the sender (it writes it back). ]]
function RetentionService.NotifyState(player: Player, profile: any, now: number): { [string]: any }
	local o = offlineCfg()
	local live = RetentionConfig.OfflineLiveFor(player.UserId)
	local perSec = incomePerSecond(player, profile)
	local daily = if typeof(profile.DailyLogin) == "table" then profile.DailyLogin else {}
	local streak = math.max(0, math.floor(tonumber(daily.Streak) or 0))
	return {
		UserId = player.UserId,
		LastSeen = now,
		OfflineCapFullAt = if live and perSec > 0 then now + math.floor(tonumber(o.CapSeconds) or 0) else 0,
		OfflineCapCash = if live then offlineCapCash(player, profile) else 0,
		LastRaidedAt = math.max(0, math.floor(tonumber(profile.LastRaidedAt) or 0)),
		StreakDay = streak,
		NextStreakDay = (streak % DailyRewardConfig.StreakResetsAfterDay) + 1,
		LastClaimDay = math.max(0, math.floor(tonumber(daily.LastClaimDay) or 0)), -- UTC yyyymmdd
	}
end

local function writeNotifyState(player: Player)
	if not RetentionConfig.NotificationsLiveFor(player.UserId) then
		return
	end
	local profile = DataService and DataService.GetProfile(player)
	local n = profile and profile.NotifOptIn
	if typeof(n) ~= "table" or n.Result ~= "accepted" then
		return
	end
	local rec = RetentionService.NotifyState(player, profile, os.time())
	profile.OfflineCapFullAt = rec.OfflineCapFullAt
	task.spawn(function()
		local ok, err = pcall(function()
			local store = DataStoreService:GetDataStore(RetentionConfig.Notifications.StateStore)
			store:UpdateAsync("u_" .. tostring(player.UserId), function(old: any)
				-- keep the sender's own bookkeeping (LastSentDay)
				if typeof(old) == "table" and old.LastSentDay ~= nil then
					rec.LastSentDay = old.LastSentDay
				end
				return rec
			end)
		end)
		if not ok and not RunService:IsStudio() then
			warn("[RetentionService] notify state write failed:", err)
		end
	end)
end

-- ── Init ───────────────────────────────────────────────────────────────────────────────────────────────────────────
local function onPlayerAdded(player: Player)
	sessionAt[player.UserId] = os.clock()
	if AnalyticsService and AnalyticsService.Onboard then
		pcall(AnalyticsService.Onboard, player, "Joined")
	end
	local function spawned()
		if AnalyticsService and AnalyticsService.Onboard then
			pcall(AnalyticsService.Onboard, player, "CharacterSpawned")
		end
	end
	if player.Character then
		spawned()
	else
		local conn: RBXScriptConnection? = nil
		conn = player.CharacterAdded:Connect(function()
			if conn then
				conn:Disconnect()
				conn = nil
			end
			spawned()
		end)
	end
end

function RetentionService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	BaseService = deps.BaseService
	RemoteSetup = deps.RemoteSetup
	RateLimitService = deps.RateLimitService
	AnalyticsService = deps.AnalyticsService

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		if sessionAt[p.UserId] == nil then
			onPlayerAdded(p)
		end
	end

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		startHold(player, profile)
		-- claude-bud JOB 49 D: ReturnDay (UTC days since the first join, guided done) once per session, so D1 ties to JOB 48
		if typeof(RetentionConfig.ReturnSequence) == "table" and RetentionConfig.Live(RetentionConfig.ReturnSequence, player.UserId) then
			local first = tonumber(profile.FirstJoinUnix) or 0
			if first > 0 then
				local days = math.max(0, math.floor(os.time() / 86400) - math.floor(first / 86400))
				log(player, "RETURN_DAY", { days = days, guidedDone = if profile.TutorialComplete == true then "yes" else "no" })
			end
		end
		-- after the other load hooks (BaseService's plot / income state), in its own thread
		task.defer(onLoadOffline, player, profile)
		-- a day-7 army boost still running from before (DailyRewardConfig.Day7Boost)
		local boost = tonumber(profile.ArmyBoostUntil) or 0
		if boost > os.time() then
			player:SetAttribute("WE_ArmyBoostUntil", boost)
		end
	end)

	if BaseService and BaseService.GetUpgradeChangedEvent then
		BaseService.GetUpgradeChangedEvent().Event:Connect(function(userId: number, _plotId: any, structureId: string, level: number)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				onUpgrade(player, structureId, level)
			end
		end)
	end

	local optIn = RemoteSetup.Get(Constants.RemoteNames.RequestNotifOptInResult) :: RemoteEvent
	optIn.OnServerEvent:Connect(function(player: Player, result: any, source: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestNotifOptInResult", result, source) then
			return
		end
		if RateLimitService and not RateLimitService.Allow(player, "notif_optin", 1, 2) then
			return
		end
		onOptInResult(player, result, source)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		pcall(writeNotifyState, player)
		local uid = player.UserId
		sessionAt[uid] = nil
		promptedThisSession[uid] = nil
		awaitingResult[uid] = nil
		holdToken[uid] = nil
	end)
	print(string.format("[WAR EMPIRE] RetentionService Init: FastStart=%s Offline=%s Notifications=%s",
		tostring(TutorialConfig.FastStart.Enabled), tostring(offlineCfg().Enabled), tostring(RetentionConfig.Notifications.Enabled)))
end

return RetentionService
