--!strict
--[[
	claude-bud JOB 41 part B (2026-10-01): WHEN the Recruit Pack card is offered (MonetizationConfig.RecruitPackOffer,
	owner-first). The server decides; the client (Controllers/RecruitPackController) only draws the card, reports
	"shown" / "dropped", and prompts Roblox when he taps the price (the grant stays MonetizationService.ProcessReceipt).

	Once per profile (profile.RecruitPackOffered, set when the client confirms the card SHOWED), at the FIRST of:
	  * his first capture (TerritoryService calls OnCapture: the Guided reward capture or any first territory), or
	  * RecruitPackOffer.OfferAfterPlaySeconds of total play (profile.Stats.PlayTimeSeconds, accrued here).
	Never: before either, with Id 0, owned, during the Guided / onboarding hold, within CombatQuietSeconds of damage
	taken, while seated, or while another card is out. It goes through MonetizationService.ClaimSoftOfferSlot (the
	existing budget); a busy slot or a dropped card retries every RetrySeconds (MaxTriesPerSession). Telemetry:
	RecruitPackOffered { trigger } + the FirstMinutes funnel steps 10 Offered / 11 Bought.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)

local RecruitPackService = {}

local MC: any = MonetizationConfig
local O: any = MC.RecruitPackOffer
local deps: { [string]: any } = {}

type Session = { Trigger: string?, Tries: number, NextAt: number, Awaiting: boolean, LastAccrue: number, Slot: any? }
local sessions: { [number]: Session } = {}

RecruitPackService._clock = os.clock -- tests replace these
RecruitPackService._delay = function(s: number, fn: (...any) -> (), ...: any)
	task.delay(s, fn, ...)
end

local function sessionOf(player: Player): Session
	local s = sessions[player.UserId]
	if s == nil then
		s = { Trigger = nil, Tries = 0, NextAt = 0, Awaiting = false, LastAccrue = RecruitPackService._clock() }
		sessions[player.UserId] = s
	end
	return s :: Session
end

local function productId(): number
	local def = MC.DevProducts.RecruitPack
	return if typeof(def) == "table" then tonumber(def.Id) or 0 else 0
end

local function hasPack(player: Player, profile: any): boolean
	if typeof(profile.Entitlements) == "table" and profile.Entitlements.RecruitPack == true then
		return true
	end
	return player:GetAttribute("WE_Ent_RecruitPack") == true
end

--[[ The pure rule (tests call it). s = { Live, ProductId, Offered, Owned, Tries, Trigger?, PlaySeconds, Onboarding,
	SinceHurt, Seated, Awaiting } -> (offer, why). `why` is the trigger on an offer ("capture" | "playtime"). ]]
function RecruitPackService.Decide(s: any): (boolean, string)
	if s.Live ~= true then
		return false, "not_live"
	elseif (tonumber(s.ProductId) or 0) == 0 then
		return false, "id0" -- the owner has not OK'd the price yet: never prompts
	elseif s.Offered == true or s.Owned == true then
		return false, "done"
	elseif s.Awaiting == true then
		return false, "awaiting"
	elseif (tonumber(s.Tries) or 0) >= O.MaxTriesPerSession then
		return false, "tries"
	end
	local why: string? = nil
	if s.Trigger == "capture" then
		why = "capture"
	elseif (tonumber(s.PlaySeconds) or 0) >= O.OfferAfterPlaySeconds then
		why = "playtime"
	end
	if why == nil then
		return false, "too_early"
	elseif s.Onboarding == true then
		return false, "hold"
	elseif (tonumber(s.SinceHurt) or math.huge) < O.CombatQuietSeconds then
		return false, "combat"
	elseif s.Seated == true then
		return false, "seated"
	end
	return true, why :: string
end

-- TerritoryService: a capture (the first one is the trigger)
function RecruitPackService.OnCapture(player: Player)
	if not MC.RecruitPackLiveFor(player.UserId) then
		return
	end
	local s = sessionOf(player)
	if s.Trigger == nil then
		s.Trigger = "capture"
	end
end

local function sinceHurt(player: Player): number
	local RP = deps.RatePromptService
	if RP and RP.SinceHurt then
		local ok, v = pcall(RP.SinceHurt, player)
		if ok and typeof(v) == "number" then
			return v
		end
	end
	return math.huge
end

local function seated(player: Player): boolean
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	return hum ~= nil and hum.SeatPart ~= nil
end

local function guidedFunnel(player: Player, profile: any, name: string)
	local GS = deps.GuidedService
	if GS and GS.Funnel then
		pcall(GS.Funnel, player, profile, name)
	end
end

-- one player's check (the shared tick calls it; tests call it with a fake clock)
function RecruitPackService.Step(player: Player): (boolean, string)
	local s = sessionOf(player)
	local now = RecruitPackService._clock()
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil then
		return false, "no_profile"
	end
	-- total play: Stats.PlayTimeSeconds (it was never counted before; analytics read it as minutesPlayed)
	local dt = math.clamp(now - s.LastAccrue, 0, 60)
	s.LastAccrue = now
	if typeof(profile.Stats) == "table" then
		profile.Stats.PlayTimeSeconds = math.floor((tonumber(profile.Stats.PlayTimeSeconds) or 0) + dt + 0.5)
	end
	if now < s.NextAt then
		return false, "wait"
	end
	local RS = deps.RetentionService
	local offer, why = RecruitPackService.Decide({
		Live = MC.RecruitPackLiveFor(player.UserId),
		ProductId = productId(),
		Offered = profile.RecruitPackOffered == true,
		Owned = hasPack(player, profile),
		Tries = s.Tries,
		Trigger = s.Trigger,
		PlaySeconds = if typeof(profile.Stats) == "table" then profile.Stats.PlayTimeSeconds else 0,
		Onboarding = RS ~= nil and RS.IsOnboarding ~= nil and RS.IsOnboarding(player) == true,
		SinceHurt = sinceHurt(player),
		Seated = seated(player),
		Awaiting = s.Awaiting,
	})
	if not offer then
		return false, why
	end
	local MS = deps.MonetizationService
	local slot = if MS and MS.ClaimSoftOfferSlotRefundable then MS.ClaimSoftOfferSlotRefundable(player)
		elseif MS and MS.ClaimSoftOfferSlot and MS.ClaimSoftOfferSlot(player) then {}
		else nil
	if slot == nil then
		s.NextAt = now + O.RetrySeconds -- the existing budget is busy: try again later this session
		return false, "slot"
	end
	s.Slot = slot
	s.Tries += 1
	s.Awaiting = true
	local perMin = if MS.PassivePerMin then MS.PassivePerMin(player, profile) else 0
	local price = MC.DevProducts.RecruitPack.RobuxPrice
	local okLP, LP = pcall(function(): any
		return require(Shared.Util.LivePrices)
	end)
	if okLP and LP and LP.Price then
		local okP, p = pcall(LP.Price, "DevProduct", "RecruitPack")
		if okP and typeof(p) == "number" and p > 0 then
			price = p
		end
	end
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "RecruitPackOffer", {
			ProductKey = "RecruitPack",
			ProductId = productId(),
			Cash = MC.RecruitPackCash(perMin), -- the real number for him right now (the receipt recomputes it)
			RobuxPrice = price,
			Trigger = why,
		})
	end
	local A = deps.AnalyticsService
	if A and A.Log then
		pcall(A.Log, "RECRUIT_PACK_OFFERED", player.UserId, { trigger = why })
	end
	-- no answer at all (the client never drew it): free it for a retry
	local myTry = s.Tries
	RecruitPackService._delay(O.ClientWaitMaxSeconds + O.AutoHideSeconds + 10, function()
		if sessions[player.UserId] == s and s.Awaiting and s.Tries == myTry then
			s.Awaiting = false
			s.NextAt = RecruitPackService._clock() + O.RetrySeconds
		end
	end)
	return true, why
end

-- the client's report (already through RemoteGate + the rate limit): "shown" = mark it (saved, never again);
-- "dropped" = he never saw it: retry RetrySeconds later
function RecruitPackService.Result(player: Player, result: any): boolean
	local s = sessions[player.UserId]
	if s == nil or not s.Awaiting or (result ~= "shown" and result ~= "dropped") then
		return false
	end
	s.Awaiting = false
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	if result == "shown" then
		profile.RecruitPackOffered = true
		deps.DataService.MarkDirty(player)
		guidedFunnel(player, profile, "Offered")
	else
		-- he never saw it: give the soft-offer slot back (the Starter Pack's v153 rule) and retry
		local MS = deps.MonetizationService
		if MS and MS.RefundSoftOfferSlot and s.Slot then
			pcall(MS.RefundSoftOfferSlot, player, s.Slot)
		end
		s.Slot = nil
		s.NextAt = RecruitPackService._clock() + O.RetrySeconds
	end
	return true
end

-- the rate card (JOB 41 part D) waits while this card is out
function RecruitPackService.CardOut(player: Player): boolean
	local s = sessions[player.UserId]
	return s ~= nil and s.Awaiting
end

function RecruitPackService._Session(player: Player): Session
	return sessionOf(player)
end

function RecruitPackService.Init(d: { [string]: any })
	deps = d
	if O == nil or O.Enabled ~= true then
		print("[WAR EMPIRE] RecruitPackService: off (RecruitPackOffer.Enabled = false)")
		return
	end
	local MS = deps.MonetizationService
	if MS and MS.OnGranted then
		MS.OnGranted(function(player: Player, key: string, _event: any)
			if key == "RecruitPack" then
				local profile = deps.DataService and deps.DataService.GetProfile(player)
				if profile then
					guidedFunnel(player, profile, "Bought")
				end
				local BS = deps.BaseSignService
				if BS and BS.Refresh then
					pcall(BS.Refresh)
				end
			end
		end)
	end
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.RequestRecruitPackResult)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent).OnServerEvent:Connect(function(player: Player, result: any)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestRecruitPackResult", result) then
				return
			end
			if deps.RateLimitService and not deps.RateLimitService.Allow(player, "recruit_pack", 2 / 60, 3) then
				return
			end
			RecruitPackService.Result(player, result)
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(O.TickSeconds)
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Parent then
					pcall(RecruitPackService.Step, p)
				end
			end
		end
	end)
	print(string.format("[WAR EMPIRE] RecruitPackService Init (OwnerFirst=%s)", tostring(O.OwnerFirst)))
end

return RecruitPackService
