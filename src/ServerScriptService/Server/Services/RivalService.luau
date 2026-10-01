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

-- the candidate rows for one viewer (every ALLOWED base, exact loot; Pick buckets it)
function RivalService.Candidates(viewer: Player): { any }
	local P = plan()
	local bs = deps.BaseService
	if P == nil or P.CheckSend == nil or bs == nil or bs.GetOwnerUserId == nil then
		return {}
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
			if okV and typeof(v) == "table" and v.Ok == true then
				local ms = deps.MoneyCollectorService
				local bal = 0
				if ms and ms.GetRaidableBalance then
					local okM, b = pcall(ms.GetRaidableBalance, victim)
					bal = if okM then tonumber(b) or 0 else 0
				end
				local loot = math.floor(bal * ArmyOrdersConfig.LootFraction(stealFraction(), v.Bully == true))
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
	return rows
end

local function push(player: Player, rows: { any })
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "RivalTargets", { Rows = rows })
	end
end

-- the shared tick: one pass over every live viewer
function RivalService.Tick()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Parent and RivalConfig.LiveFor(p.UserId) then
			-- nothing during the Guided / onboarding hold (the chain first); no soldiers = the verdict lists nothing
			local held = deps.RetentionService and deps.RetentionService.IsOnboarding and deps.RetentionService.IsOnboarding(p) == true
			local list = {}
			if not held then
				local ok, rows = pcall(function()
					return RivalConfig.Pick(RivalService.Candidates(p))
				end)
				list = if ok then rows else {}
			end
			lastRows[p.UserId] = list
			push(p, list)
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
