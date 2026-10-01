--!strict
--[[
	claude-bud JOB 41 part C (2026-10-01): RIVAL TARGETS (RivalConfig, owner-first). The server picks; the client never
	computes loot. ONE shared tick every RivalConfig.RefreshSeconds:
	  * for each viewer it is live for: every other occupied base whose JOB 38 SEND verdict is Ok right now
	    (ArmyPlan.CheckSend: ArmySendRules on the same facts; blocked bases are simply not listed), with the loot
	    estimate (MoneyCollectorService.GetRaidableBalance x ArmyOrdersConfig.LootFraction(StealFraction, bully)), the
	    victim's live army size, the verdict chip and the distance between the two bases;
	  * RivalConfig.Pick keeps the top MaxShown (loot, then distance) and turns the loot into a BUCKET;
	  * FeaturePush "RivalTargets" { Rows } to that viewer.
	RequestRivalAction("open" | "send", plotId?) is telemetry only (RivalListOpened / RivalSendTapped { verdict }); the
	SEND itself goes down the JOB 38 RequestArmySend remote, which re-checks everything. RivalRaidWon is logged when a
	SEND tapped from the list loots (ArmyPlan calls OnRaidWon).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local RivalConfig = require(Shared.Configs.RivalConfig)
local ArmyOrdersConfig = require(Shared.Configs.ArmyOrdersConfig)

local RivalService = {}

local deps: { [string]: any } = {}
local lastRows: { [number]: { any } } = {} -- viewer -> the rows last sent
local tapped: { [number]: { [number]: boolean } } = {} -- viewer -> plot ids sent at from the list

local function plan(): any?
	local ok, P = pcall(function(): any
		return require(script.Parent.Parent.Modules.ArmyPlan)
	end)
	return if ok then P else nil
end

local function plotCentre(plotId: number): Vector3?
	local ok, PF = pcall(function(): any
		return require(Shared.Util.PlotFrame)
	end)
	if not ok or PF == nil then
		return nil
	end
	local okP, pos = pcall(PF.PlotPosition, plotId)
	return if okP and typeof(pos) == "Vector3" then pos else nil
end

local function stealFraction(): number
	local ok, RC = pcall(function(): any
		return require(Shared.Configs.RaidConfig)
	end)
	return if ok and RC and RC.Raid then tonumber(RC.Raid.StealFraction) or 0.1 else 0.1
end

-- the candidate rows for one viewer (every ALLOWED base, exact loot; Pick buckets it). Code Bot v163: the 2nd return
-- counts what kept the other online bases off the list (verdict reasons + "Poor" for an allowed base under
-- MinLootToShow), so an empty list can say why (RivalService.WhyEmpty)
function RivalService.Candidates(viewer: Player): ({ any }, { [string]: number })
	local P = plan()
	local bs = deps.BaseService
	local reasons: { [string]: number } = {}
	if P == nil or P.CheckSend == nil or bs == nil or bs.GetOwnerUserId == nil then
		return {}, reasons
	end
	local myPlot = bs.GetOwnedPlotId and bs.GetOwnedPlotId(viewer) or nil
	local mine = if myPlot then plotCentre(myPlot) else nil
	local maxPlots = 10
	local okB, BC = pcall(function(): any
		return require(Shared.Configs.BaseConfig)
	end)
	if okB and BC then
		maxPlots = tonumber(BC.MaxPlots) or 10
	end
	local rows = {}
	for plotId = 1, maxPlots do
		local ownerId = bs.GetOwnerUserId(plotId)
		local victim = if typeof(ownerId) == "number" and ownerId ~= viewer.UserId then Players:GetPlayerByUserId(ownerId) else nil
		if victim then
			local okV, v = pcall(P.CheckSend, viewer, plotId)
			reasons.Others = (reasons.Others or 0) + 1
			if okV and typeof(v) == "table" and v.Ok ~= true and typeof(v.Reason) == "string" then
				reasons[v.Reason] = (reasons[v.Reason] or 0) + 1
			end
			if okV and typeof(v) == "table" and v.Ok == true then
				local ms = deps.MoneyCollectorService
				local bal = 0
				if ms and ms.GetRaidableBalance then
					local okM, b = pcall(ms.GetRaidableBalance, victim)
					bal = if okM then tonumber(b) or 0 else 0
				end
				local loot = math.floor(bal * ArmyOrdersConfig.LootFraction(stealFraction(), v.Bully == true))
				if loot < RivalConfig.MinLootToShow then
					reasons.Poor = (reasons.Poor or 0) + 1
				end
				local army = 0
				local sqs = deps.SquadOrdersService
				if sqs and sqs.UnitPower then
					local okU, u = pcall(sqs.UnitPower, victim)
					army = if okU then math.floor(tonumber(u) or 0) else 0
				end
				local there = plotCentre(plotId)
				local dist = if mine and there then Vector3.new(there.X - mine.X, 0, there.Z - mine.Z).Magnitude else 0
				table.insert(rows, {
					PlotId = plotId,
					Name = victim.DisplayName,
					Army = army,
					Verdict = RivalConfig.VerdictWord(v.Bully == true, tonumber(v.Ratio) or 1, ArmyOrdersConfig.Fairness.RiskyRatio),
					Loot = loot,
					Dist = dist,
				})
			end
		end
	end
	return rows, reasons
end

--[[ Code Bot v163: the one-line reason an EMPTY list shows under RivalConfig.EmptyText (the most common blocker
	among the other online bases; nil = the generic text alone). Pure on the reason counts. ]]
function RivalService.WhyEmpty(held: boolean, reasons: { [string]: number }?): string?
	local W = RivalConfig.WhyText
	if held then
		return W.Held
	end
	local r = reasons or {}
	if (r.Others or 0) == 0 then
		return W.Alone
	end
	if (r.NoArmy or 0) > 0 then
		return W.NoArmy -- the viewer's own state: every base says the same
	end
	if (r.Active or 0) > 0 or (r.Cooldown or 0) > 0 then
		return W.Busy
	end
	local protected = (r.Shielded or 0) + (r.NewPlayer or 0) + (r.Novice or 0) + (r.Protected or 0) + (r.Ally or 0)
	local best, bestN = nil, 0
	for key, n in pairs({ Protected = protected, Poor = r.Poor or 0, Strong = r.TooWeak or 0 }) do
		if n > bestN then
			best, bestN = key, n
		end
	end
	return if best then W[best] else nil
end

local function push(player: Player, rows: { any }, why: string?)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "RivalTargets", { Rows = rows, Why = if #rows == 0 then why else nil })
	end
end

-- the shared tick: one pass over every live viewer
function RivalService.Tick()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Parent and RivalConfig.LiveFor(p.UserId) then
			-- nothing during the Guided / onboarding hold (the chain first); no soldiers = the verdict lists nothing
			local held = deps.RetentionService and deps.RetentionService.IsOnboarding and deps.RetentionService.IsOnboarding(p) == true
			local list = {}
			local reasons = nil
			if not held then
				local ok, rows, rs = pcall(function()
					local cand, why = RivalService.Candidates(p)
					return RivalConfig.Pick(cand), why
				end)
				list = if ok then rows else {}
				reasons = if ok then rs else nil
			end
			lastRows[p.UserId] = list
			local okW, why = pcall(RivalService.WhyEmpty, held, reasons)
			push(p, list, if okW then why else nil)
		end
	end
end

local function log(player: Player, ev: string, props: { [string]: any })
	local A = deps.AnalyticsService
	if A and A.Log then
		pcall(A.Log, ev, player.UserId, props)
	end
end

function RivalService.Action(player: Player, kind: any, plotId: any)
	if not RivalConfig.LiveFor(player.UserId) then
		return
	end
	if kind == "open" then
		log(player, "RIVAL_LIST_OPENED", {})
	elseif kind == "send" then
		local id = math.floor(tonumber(plotId) or 0)
		local verdict = nil
		for _, r in ipairs(lastRows[player.UserId] or {}) do
			if r.PlotId == id then
				verdict = r.Verdict
			end
		end
		if verdict == nil then
			return -- not a listed target: the JOB 38 handler still decides the send itself
		end
		local t = tapped[player.UserId] or {}
		t[id] = true
		tapped[player.UserId] = t
		log(player, "RIVAL_SEND_TAPPED", { verdict = verdict })
	end
end

-- ArmyPlan: a SEND looted. Logged as RivalRaidWon when it was sent from the list.
function RivalService.OnRaidWon(player: Player, plotId: number, looted: number)
	local t = tapped[player.UserId]
	if t and t[plotId] then
		t[plotId] = nil
		log(player, "RIVAL_RAID_WON", { loot = looted })
	end
end

function RivalService._Rows(player: Player): { any }?
	return lastRows[player.UserId]
end

function RivalService.Init(d: { [string]: any })
	deps = d
	if RivalConfig.Enabled ~= true then
		print("[WAR EMPIRE] RivalService: off (RivalConfig.Enabled = false)")
		return
	end
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.RequestRivalAction)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent).OnServerEvent:Connect(function(player: Player, kind: any, plotId: any)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestRivalAction", kind, plotId) then
				return
			end
			if deps.RateLimitService and not deps.RateLimitService.Allow(player, "rival_action", 1, 4) then
				return
			end
			RivalService.Action(player, kind, plotId)
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRows[player.UserId] = nil
		tapped[player.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(RivalConfig.RefreshSeconds)
			pcall(RivalService.Tick)
		end
	end)
	print(string.format("[WAR EMPIRE] RivalService Init (OwnerFirst=%s)", tostring(RivalConfig.OwnerFirst)))
end

return RivalService
