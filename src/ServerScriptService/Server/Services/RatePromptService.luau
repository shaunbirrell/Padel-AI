--!strict
--[[
	claude-bud JOB 40 part D (2026-09-30): WHEN the "Enjoying WAR EMPIRE?" card may show. The server decides; the
	client only shows it and reports which button was tapped. NO REWARD: this service never touches money, items, XP or
	anything else (pinned in tools/checks/claude_bud_job40.py). There is no API for likes and nothing here claims one.

	Rules (RatePromptConfig), all on the server:
	  * live for the player (Enabled + OwnerFirst), the profile loaded, the tutorial done and the onboarding hold off;
	  * never after "Don't show again" (profile.RatePrompt.Never, across servers);
	  * at most once per session; never in the first NotBeforeSessionSeconds of a session;
	  * at least MinGapSeconds (3 days) since the last show;
	  * no damage taken for CombatQuietSeconds (Humanoid.HealthChanged); the client also waits out its own
	    RecentCombat / driving / open-panel flags before it draws the card;
	  * then EITHER PlaySecondsBeforeShow of total play (profile.RatePrompt.PlaySeconds) OR a trigger: a rebirth
	    (PrestigeService) or a big-banner achievement (AchievementService.Shout big), after TriggerDelaySeconds.
	The show goes out as FeaturePush "RatePrompt" { Trigger } and is saved at once (LastShownUnix, Shows). The answer
	comes back on RequestRatePromptAnswer (RemoteGate schema + a 2 / min limit) as one of "later" | "never" |
	"favorite" | "timeout". Telemetry: rate_prompt_shown { trigger } and rate_prompt_answer { answer } only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Cfg = require(Shared.Configs.RatePromptConfig)

local RatePromptService = {}

type Session = {
	JoinedAt: number, -- clock at join
	LastHurt: number, -- clock of the last damage taken
	LastAccrue: number, -- clock of the last play-time accrual
	Unsaved: number, -- accrued seconds since the last MarkDirty
	Shown: boolean, -- shown this session
	Awaiting: boolean, -- a show is out, waiting for its answer
	Trigger: string?, -- a pending trigger
	TriggerAt: number, -- clock from which the trigger may show
	Conn: RBXScriptConnection?,
}

local deps: { [string]: any } = {}
local sessions: { [number]: Session } = {}

RatePromptService._clock = os.clock -- tests replace these
RatePromptService._unix = os.time

-- the saved record, repaired in place (ProfileSchema.Migrate does the same on load)
function RatePromptService.Record(profile: any): { LastShownUnix: number, Shows: number, Never: boolean, PlaySeconds: number }
	local r = if typeof(profile.RatePrompt) == "table" then profile.RatePrompt else {}
	local function n(v: any): number
		local x = tonumber(v) or 0
		return if x == x and x > 0 and x < 1e12 then math.floor(x) else 0
	end
	local rec = { LastShownUnix = n(r.LastShownUnix), Shows = n(r.Shows), Never = r.Never == true, PlaySeconds = n(r.PlaySeconds) }
	profile.RatePrompt = rec
	return rec
end

--[[ The pure rule (tests call it). s = { Live, Loaded, TutorialDone, Onboarding, Never, ShownThisSession, Awaiting,
	SessionSeconds, PlaySeconds, SinceLastShow, SinceHurt, Trigger? } -> (show, why). `why` is the trigger on a show
	("playtime" | "rebirth" | "achievement") or the reason it waits. ]]
function RatePromptService.Decide(s: any): (boolean, string)
	if s.Live ~= true then
		return false, "not_live"
	elseif s.Loaded ~= true then
		return false, "no_profile"
	elseif s.Never == true then
		return false, "never"
	elseif s.ShownThisSession == true or s.Awaiting == true then
		return false, "session"
	elseif s.TutorialDone ~= true or s.Onboarding == true then
		return false, "tutorial"
	elseif (tonumber(s.SessionSeconds) or 0) < Cfg.NotBeforeSessionSeconds then
		return false, "session_start"
	elseif (tonumber(s.SinceLastShow) or math.huge) < Cfg.MinGapSeconds then
		return false, "gap"
	elseif (tonumber(s.SinceHurt) or math.huge) < Cfg.CombatQuietSeconds then
		return false, "combat"
	end
	if typeof(s.Trigger) == "string" and (Cfg.Triggers :: any)[s.Trigger] == true then
		return true, s.Trigger
	end
	if (tonumber(s.PlaySeconds) or 0) >= Cfg.PlaySecondsBeforeShow then
		return true, "playtime"
	end
	return false, "playtime_short"
end

local function logEvent(player: Player, name: string, props: { [string]: any })
	local A = deps.AnalyticsService
	if A and A.Log then
		pcall(A.Log, name, player.UserId, props)
	end
end

local function push(player: Player, data: any)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "RatePrompt", data)
	end
end

local function sessionOf(player: Player): Session
	local s = sessions[player.UserId]
	if s == nil then
		local now = RatePromptService._clock()
		s = { JoinedAt = now, LastHurt = -math.huge, LastAccrue = now, Unsaved = 0, Shown = false, Awaiting = false, TriggerAt = 0 }
		sessions[player.UserId] = s
	end
	return s :: Session
end

local function watchHealth(player: Player, char: Model)
	local s = sessionOf(player)
	if s.Conn then
		(s.Conn :: RBXScriptConnection):Disconnect()
		s.Conn = nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if hum == nil or not hum:IsA("Humanoid") then
		return
	end
	local h = hum :: Humanoid
	local last = h.Health
	s.Conn = h.HealthChanged:Connect(function(hp: number)
		if hp < last - 0.01 then
			s.LastHurt = RatePromptService._clock()
		end
		last = hp
	end)
end

-- a trigger moment (rebirth / big achievement): shows early, still under every other rule
function RatePromptService.Trigger(player: Player, reason: string)
	if (Cfg.Triggers :: any)[reason] ~= true or not Cfg.LiveFor(player.UserId) then
		return
	end
	local s = sessionOf(player)
	if s.Shown or s.Trigger ~= nil then
		return
	end
	s.Trigger = reason
	s.TriggerAt = RatePromptService._clock() + Cfg.TriggerDelaySeconds
end

-- one player's check (the tick calls it; tests call it with a fake clock)
function RatePromptService.Step(player: Player, accrueOnly: boolean?): (boolean, string)
	local s = sessionOf(player)
	local now = RatePromptService._clock()
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	local rec = if profile then RatePromptService.Record(profile) else nil
	-- play time accrues for everyone it is live for, saved about once a minute (and at the show / the answer)
	local dt = math.clamp(now - s.LastAccrue, 0, 60)
	s.LastAccrue = now
	if rec and Cfg.LiveFor(player.UserId) then
		rec.PlaySeconds += dt
		s.Unsaved += dt
		if s.Unsaved >= 60 then
			s.Unsaved = 0
			deps.DataService.MarkDirty(player)
		end
	end
	if accrueOnly then
		return false, "leaving"
	end
	local RS = deps.RetentionService
	local trig = if s.Trigger ~= nil and now >= s.TriggerAt then s.Trigger else nil
	local show, why = RatePromptService.Decide({
		Live = Cfg.LiveFor(player.UserId),
		Loaded = rec ~= nil,
		TutorialDone = profile ~= nil and (profile :: any).TutorialComplete == true,
		Onboarding = RS ~= nil and RS.IsOnboarding ~= nil and RS.IsOnboarding(player) == true,
		Never = rec ~= nil and rec.Never,
		ShownThisSession = s.Shown,
		Awaiting = s.Awaiting,
		SessionSeconds = now - s.JoinedAt,
		PlaySeconds = if rec then rec.PlaySeconds else 0,
		SinceLastShow = if rec and rec.LastShownUnix > 0 then RatePromptService._unix() - rec.LastShownUnix else math.huge,
		SinceHurt = now - s.LastHurt,
		Trigger = trig,
	})
	if not show or rec == nil then
		return false, why
	end
	s.Shown = true
	s.Awaiting = true
	s.Trigger = nil
	rec.LastShownUnix = RatePromptService._unix()
	rec.Shows += 1
	deps.DataService.MarkDirty(player)
	push(player, { Trigger = why })
	logEvent(player, "RATE_PROMPT_SHOWN", { trigger = why })
	return true, why
end

-- the client's button (already through RemoteGate + the rate limit): later | never | favorite | timeout
function RatePromptService.Answer(player: Player, answer: any): boolean
	local s = sessions[player.UserId]
	if s == nil or not s.Awaiting or typeof(answer) ~= "string" or (Cfg.Answers :: any)[answer] ~= true then
		return false
	end
	s.Awaiting = false
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local rec = RatePromptService.Record(profile)
	if answer == "never" then
		rec.Never = true
	end
	deps.DataService.MarkDirty(player)
	logEvent(player, "RATE_PROMPT_ANSWER", { answer = answer })
	return true
end

-- seconds since this player last took damage (math.huge = not this session); RecruitPackService reads it (JOB 41 B)
function RatePromptService.SinceHurt(player: Player): number
	local s = sessions[player.UserId]
	return if s then RatePromptService._clock() - s.LastHurt else math.huge
end

function RatePromptService._Session(player: Player): Session
	return sessionOf(player)
end

local function onPlayer(player: Player)
	sessionOf(player)
	if player.Character then
		task.spawn(watchHealth, player, player.Character)
	end
	player.CharacterAdded:Connect(function(char: Model)
		watchHealth(player, char)
	end)
end

function RatePromptService.Init(d: { [string]: any })
	deps = d
	if Cfg.Enabled ~= true then
		print("[WAR EMPIRE] RatePromptService: off (RatePromptConfig.Enabled = false)")
		return
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local s = sessions[player.UserId]
		if s then
			pcall(RatePromptService.Step, player, true) -- the last play seconds into the save (never shows: the player is leaving)
			if s.Conn then
				(s.Conn :: RBXScriptConnection):Disconnect()
			end
			if s.Unsaved > 0 and deps.DataService then
				pcall(deps.DataService.MarkDirty, player)
			end
		end
		sessions[player.UserId] = nil
	end)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.RequestRatePromptAnswer)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent).OnServerEvent:Connect(function(player: Player, answer: any)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestRatePromptAnswer", answer) then
				return
			end
			if deps.RateLimitService and not deps.RateLimitService.Allow(player, "rate_prompt", 2 / 60, 2) then
				return
			end
			RatePromptService.Answer(player, answer)
		end)
	end
	-- one light loop for everyone (0.2 Hz; no per-frame work)
	task.spawn(function()
		while true do
			task.wait(Cfg.TickSeconds)
			for _, p in ipairs(Players:GetPlayers()) do
				if sessions[p.UserId] and p.Parent then
					pcall(RatePromptService.Step, p)
				end
			end
		end
	end)
	print(string.format("[WAR EMPIRE] RatePromptService Init (OwnerFirst=%s)", tostring(Cfg.OwnerFirst)))
end

return RatePromptService
