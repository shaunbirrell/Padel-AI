--!strict
--[[
	v69 Command Center missile strikes (owner: "From command centre you should be able to direct missiles at
	players/bases when you have the upgrade to take down their defenses").

	Unlock ("the upgrade"): Command Center L3 + Missile Defense L1 (RaidConfig.Strike.Unlock).
	Launch: Missiles panel from the Missile Command terminal inside your own Command Center — the server checks the
	attacker's character is at their CC. $5,000, 10 min reload (profile.Raid.StrikeCooldownUntil, os.time).
	Flight: attacker's Missile Defense battery → target's main gate, 5–9 s (drawn by every client from one
	MissileStrikeFx packet). The target's Missile Defense may shoot it down (outcome rolled at launch).
	Hit: target's guards / AutoGuns / gate barrier go down for 120–180 s (profile.Raid.DefensesDownUntil →
	GateDefenseService.SetDefensesDown). Missiles never damage players.

	Remotes: RequestMissileStrike (client → server: { Action = "State" } | { Action = "Launch", TargetUserId }),
	MissileStrikeStateUpdate (server → client: MissileState), MissileStrikeFx (server → all clients: MissileFx).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local RaidConfig = require(Shared.Configs.RaidConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)
local GateDefenseConfig = require(Shared.Configs.GateDefenseConfig)
local ServerModules = script.Parent.Parent.Modules
local RemoteSetup = require(ServerModules.RemoteSetup)
local RemoteGuard = require(ServerModules.RemoteGuard)

local MissileStrikeService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local BaseService: any = nil
local GateDefenseService: any = nil
local AnalyticsService: any = nil

export type StrikeResult = {
	Kind: string, -- "Launched" | "Hit" | "Intercepted" | "Refunded" | "Refused"
	TargetName: string?,
	Reason: string?,
	Text: string,
	DownSeconds: number?,
	ImpactIn: number?,
}

type Strike = {
	Id: number,
	AttackerUserId: number,
	AttackerName: string,
	VictimUserId: number,
	VictimName: string,
	PlotId: number,
	LaunchUnix: number,
	LaunchClock: number,
	FlightSeconds: number,
	Outcome: string, -- "Hit" | "Intercepted"
	AttackerCC: number,
	Cost: number,
}

local strikes: { [number]: Strike } = {}
local inFlight: { [number]: Strike } = {} -- attackerUserId → strike
local incoming: { [number]: Strike } = {} -- victimUserId → strike
local nextStrikeId = 0

local rng = Random.new()
local function defaultRandom(): number
	return rng:NextNumber()
end
local randomFn: () -> number = defaultRandom

-- Plot-local offsets (plots are not rotated: plot-local = world offset from the pad centre)
local function siteOffset(structureId: string, fallbackX: number, fallbackZ: number): Vector3
	local structures = (BaseLayoutConfig :: any).Structures
	local entry = structures and structures[structureId]
	local site = entry and entry.Site
	if site and typeof(site.X) == "number" and typeof(site.Z) == "number" then
		return Vector3.new(site.X, 0, site.Z)
	end
	return Vector3.new(fallbackX, 0, fallbackZ)
end
local CC_OFFSET = siteOffset("CommandCenter", 0, -38)
-- Missile Defense site + the launcher's local (0, -3), ~8 studs above the pad
local BATTERY_OFFSET = siteOffset("MissileDefense", 132, -40) + Vector3.new(0, 8.5, -3)
local LAUNCH_MAX_DY = 30

-- ── helpers ────────────────────────────────────────────────────────────────

local function profileOf(player: Player): any
	if not DataService then
		return nil
	end
	return DataService.GetProfile(player)
end

local function isLoaded(player: Player): boolean
	if not DataService then
		return false
	end
	if DataService.IsLoaded then
		return DataService.IsLoaded(player) == true
	end
	return DataService.GetProfile(player) ~= nil
end

local function markDirty(player: Player)
	if DataService and DataService.MarkDirty then
		DataService.MarkDirty(player)
	end
end

local function levelOf(profile: any, structureId: string): number
	local ups = profile and profile.BaseUpgrades
	if typeof(ups) ~= "table" then
		return 0
	end
	return math.max(0, math.floor(tonumber(ups[structureId]) or 0))
end

local function raidNum(profile: any, key: string): number
	local raid = profile and profile.Raid
	if typeof(raid) ~= "table" then
		return 0
	end
	return tonumber(raid[key]) or 0
end

local function raidOf(profile: any): { [string]: any }
	local raid = profile.Raid
	if typeof(raid) ~= "table" then
		raid = { ShieldUntil = 0, StrikeCooldownUntil = 0, DefensesDownUntil = 0 }
		profile.Raid = raid
	end
	return raid
end

local function setAttr(player: Player, name: string, value: number)
	pcall(function()
		player:SetAttribute(name, if value > 0 then value else nil)
	end)
end

local function formatCash(n: number): string
	local s = string.format("%d", math.floor(math.abs(n)))
	local out = (string.reverse(s):gsub("(%d%d%d)", "%1,"))
	out = string.reverse(out)
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if n < 0 then "-" else "") .. out
end

local function round1(x: number): number
	return math.floor(x * 10 + 0.5) / 10
end

local function ownedPlotOf(player: Player): number?
	if BaseService and BaseService.GetOwnedPlotId then
		local pid = BaseService.GetOwnedPlotId(player)
		if typeof(pid) == "number" then
			return pid
		end
	end
	return nil
end

local function plotPos(plotId: number): Vector3?
	local p = BaseConfig.PlotPositions[plotId]
	if typeof(p) == "Vector3" then
		return p
	end
	return nil
end

local function batteryPos(plotId: number): Vector3?
	local p = plotPos(plotId)
	return if p then p + BATTERY_OFFSET else nil
end

local function gatePos(plotId: number): Vector3?
	if GateDefenseService and GateDefenseService.GetGateCFrame then
		local cf = GateDefenseService.GetGateCFrame(plotId)
		if typeof(cf) == "CFrame" then
			return cf.Position
		end
	end
	local p = plotPos(plotId)
	if not p then
		return nil
	end
	return p + Vector3.new(0, 3.5, BaseConfig.PlotSize.Z * 0.5 - 1.5)
end

local function isUnlocked(profile: any): boolean
	local U = RaidConfig.Strike.Unlock
	return levelOf(profile, "CommandCenter") >= (U.CommandCenter or 3) and levelOf(profile, "MissileDefense") >= (U.MissileDefense or 1)
end

local function isAlly(ownerUserId: number, player: Player): boolean
	if player.UserId == ownerUserId then
		return true
	end
	if GateDefenseService and GateDefenseService.IsAlly then
		return GateDefenseService.IsAlly(ownerUserId, player) == true
	end
	return false
end

-- Same new-player rule as raids
local function newPlayerSecondsLeft(profile: any): number
	local R = RaidConfig.Raid
	if RunService:IsStudio() and not R.ProtectNewPlayersInStudio then
		return 0
	end
	local first = tonumber(profile.FirstJoinUnix) or 0
	if first <= 0 then
		return 0
	end
	return math.max(0, first + R.NewPlayerProtectionSeconds - os.time())
end

-- Server's own view of the character: within LaunchMaxDistanceFromCC (horizontal) of the player's own CC site
local function atCommandCenter(player: Player, plotId: number?): boolean
	if plotId == nil then
		return false
	end
	local p = plotPos(plotId)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not p or not (hrp and hrp:IsA("BasePart")) then
		return false
	end
	local d = hrp.Position - (p + CC_OFFSET)
	return Vector3.new(d.X, 0, d.Z).Magnitude <= RaidConfig.Strike.LaunchMaxDistanceFromCC and math.abs(d.Y) <= LAUNCH_MAX_DY
end

local function reasonText(reason: string, secs: number?): string
	local tpl = RaidConfig.Text.StrikeReasons[reason]
	if not tpl then
		return reason
	end
	if string.find(tpl, "%s", 1, true) then
		if reason == "InsufficientCash" then
			return string.format(tpl, formatCash(RaidConfig.Strike.Cost))
		end
		return string.format(tpl, RaidConfig.FormatTime(secs or 0))
	end
	return tpl
end

local function structureName(structureId: string): string
	local def = (BaseConfig.Structures :: any)[structureId]
	return if def and typeof(def.DisplayName) == "string" then def.DisplayName else structureId
end

-- ── rules (spec §2.3; launch-only checks are in launch) ─────────────────────

function MissileStrikeService.CanStrike(attacker: Player, victim: Player): (boolean, string?, number?)
	local S = RaidConfig.Strike
	if not S.Enabled then
		return false, "Disabled"
	end
	local aProfile = profileOf(attacker)
	if not aProfile or not isLoaded(attacker) then
		return false, "Loading"
	end
	if ownedPlotOf(attacker) == nil then
		return false, "NoBase"
	end
	if not isUnlocked(aProfile) then
		return false, "Locked"
	end
	-- (InFlight before Cooldown: a launch always starts the reload, so the other order could never say "in the air")
	if inFlight[attacker.UserId] ~= nil then
		return false, "InFlight"
	end
	local nowUnix = os.time()
	local cd = raidNum(aProfile, "StrikeCooldownUntil")
	if nowUnix < cd then
		return false, "Cooldown", cd - nowUnix
	end
	if victim == attacker or victim.UserId == attacker.UserId then
		return false, "Self"
	end
	local vPlot = if victim.Parent ~= nil then ownedPlotOf(victim) else nil
	if vPlot == nil or Players:GetPlayerByUserId(victim.UserId) == nil then
		return false, "TargetOffline"
	end
	local vProfile = profileOf(victim)
	if not vProfile or not isLoaded(victim) then
		return false, "TargetLoading"
	end
	if isAlly(victim.UserId, attacker) then
		return false, "Ally"
	end
	local newLeft = newPlayerSecondsLeft(vProfile)
	if newLeft > 0 then
		return false, "NewPlayer", newLeft
	end
	local shield = raidNum(vProfile, "ShieldUntil")
	if nowUnix < shield then
		return false, "Shielded", shield - nowUnix
	end
	local downUntil = raidNum(vProfile, "DefensesDownUntil")
	if nowUnix < downUntil then
		return false, "AlreadyDown", downUntil - nowUnix
	end
	if downUntil > 0 and nowUnix < downUntil + S.PostDownImmunitySeconds then
		return false, "Recovering", downUntil + S.PostDownImmunitySeconds - nowUnix
	end
	if incoming[victim.UserId] ~= nil then
		return false, "Incoming"
	end
	if not (GateDefenseService and GateDefenseService.HasDefenses and GateDefenseService.HasDefenses(vPlot) == true) then
		return false, "NoDefenses"
	end
	return true, nil, nil
end

-- ── state for the panel ────────────────────────────────────────────────────

local function buildTarget(attacker: Player, aPlot: number?, aMD: number, victim: Player, vPlot: number, nowUnix: number): { [string]: any }
	local S = RaidConfig.Strike
	local vProfile = profileOf(victim)
	local walls = levelOf(vProfile, "DefensiveWalls")
	local vMD = levelOf(vProfile, "MissileDefense")
	local from: Vector3? = if aPlot ~= nil then batteryPos(aPlot) else nil
	if from == nil then
		local hrp = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			from = hrp.Position
		end
	end
	local to = gatePos(vPlot)
	local distance = if from and to then (to - from).Magnitude else 0
	local ok, reason, secs = MissileStrikeService.CanStrike(attacker, victim)
	local shield = raidNum(vProfile, "ShieldUntil")
	local down = raidNum(vProfile, "DefensesDownUntil")
	local reboot = if down > 0 and nowUnix >= down then math.max(0, down + S.PostDownImmunitySeconds - nowUnix) else 0
	return {
		UserId = victim.UserId,
		Name = victim.DisplayName,
		BaseName = victim.DisplayName .. "'s Base",
		PlotId = vPlot,
		Distance = math.floor(distance),
		FlightSeconds = round1(RaidConfig.FlightSeconds(distance)),
		WallsLevel = walls,
		HasAutoGuns = walls >= (GateDefenseConfig.AutoGunMinWallsLevel or 4),
		MissileDefenseLevel = vMD,
		-- rounded (0.55 − 0.20 is 0.35000000000000003 as a float)
		InterceptChance = math.floor(RaidConfig.InterceptChance(vMD, aMD) * 100 + 0.5) / 100,
		ShieldRemaining = math.max(0, shield - nowUnix),
		DefensesDownRemaining = math.max(0, down - nowUnix),
		RebootRemaining = reboot,
		Incoming = incoming[victim.UserId] ~= nil,
		CanStrike = ok,
		Reason = reason,
		ReasonText = if reason then reasonText(reason, secs) else nil,
	}
end

function MissileStrikeService.BuildState(player: Player, result: StrikeResult?): { [string]: any }
	local S = RaidConfig.Strike
	local nowUnix = os.time()
	local profile = profileOf(player)
	local cc = levelOf(profile, "CommandCenter")
	local md = levelOf(profile, "MissileDefense")
	local unlocked = profile ~= nil and isUnlocked(profile)
	local aPlot = ownedPlotOf(player)
	local cd = raidNum(profile, "StrikeCooldownUntil")
	local cash = 0
	if EconomyService and EconomyService.GetCash and profile then
		cash = math.floor(tonumber(EconomyService.GetCash(player)) or 0)
	end
	local fly = inFlight[player.UserId]
	local targets: { { [string]: any } } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.UserId ~= player.UserId then
			local vPlot = ownedPlotOf(other)
			if vPlot ~= nil then
				table.insert(targets, buildTarget(player, aPlot, md, other, vPlot, nowUnix))
			end
		end
	end
	table.sort(targets, function(a, b)
		return (a.Distance :: number) < (b.Distance :: number)
	end)
	return {
		ServerTime = nowUnix,
		Unlocked = unlocked,
		LockedText = if unlocked
			then nil
			else string.format(RaidConfig.Text.StrikeLocked, S.Unlock.CommandCenter, S.Unlock.MissileDefense),
		Requirements = {
			{ StructureId = "CommandCenter", DisplayName = structureName("CommandCenter"), Need = S.Unlock.CommandCenter, Have = cc },
			{ StructureId = "MissileDefense", DisplayName = structureName("MissileDefense"), Need = S.Unlock.MissileDefense, Have = md },
		},
		Cost = S.Cost,
		Cash = cash,
		CooldownRemaining = math.max(0, cd - nowUnix),
		CooldownTotal = S.CooldownSeconds,
		AtCommandCenter = atCommandCenter(player, aPlot),
		InFlight = if fly
			then {
				TargetUserId = fly.VictimUserId,
				TargetName = fly.VictimName,
				ImpactIn = round1(math.max(0, fly.LaunchClock + fly.FlightSeconds - os.clock())),
			}
			else nil,
		Targets = targets,
		Result = result,
	}
end

local function pushState(player: Player, result: StrikeResult?)
	if player.Parent == nil then
		return
	end
	local remote = RemoteSetup.Get(Constants.RemoteNames.MissileStrikeStateUpdate)
	if remote and remote:IsA("RemoteEvent") then
		(remote :: RemoteEvent):FireClient(player, MissileStrikeService.BuildState(player, result))
	end
end

-- ── resolution (spec §2.7) — synchronous ───────────────────────────────────

local function resolve(strikeId: number)
	local strike = strikes[strikeId]
	if not strike then
		return
	end
	strikes[strikeId] = nil
	if inFlight[strike.AttackerUserId] == strike then
		inFlight[strike.AttackerUserId] = nil
	end
	if incoming[strike.VictimUserId] == strike then
		incoming[strike.VictimUserId] = nil
	end
	local S = RaidConfig.Strike
	local T = RaidConfig.Text
	local attacker = Players:GetPlayerByUserId(strike.AttackerUserId)
	local aProfile = if attacker then profileOf(attacker) else nil
	local victim = Players:GetPlayerByUserId(strike.VictimUserId)
	local vProfile = if victim then profileOf(victim) else nil
	local ownerNow = if BaseService and BaseService.GetOwnerUserId then BaseService.GetOwnerUserId(strike.PlotId) else nil

	-- target gone (left / plot changed hands / save not loaded): refund 1:1 and reload now
	if not victim or not vProfile or not isLoaded(victim) or ownerNow ~= strike.VictimUserId then
		if attacker and aProfile and S.RefundIfTargetLeaves then
			if EconomyService and EconomyService.AddCash then
				EconomyService.AddCash(attacker, strike.Cost, "purchase_refund")
			end
			local aRaid = raidOf(aProfile)
			aRaid.StrikeCooldownUntil = os.time()
			markDirty(attacker)
			setAttr(attacker, "WE_StrikeCooldownUntil", aRaid.StrikeCooldownUntil)
			pushState(attacker, {
				Kind = "Refunded",
				TargetName = strike.VictimName,
				Text = string.format(T.StrikeRefunded, strike.VictimName),
			})
		end
		return
	end

	if strike.Outcome == "Intercepted" then
		if attacker and aProfile then
			local aRaid = raidOf(aProfile)
			aRaid.StrikeCooldownUntil = strike.LaunchUnix + S.InterceptedCooldownSeconds
			markDirty(attacker)
			setAttr(attacker, "WE_StrikeCooldownUntil", aRaid.StrikeCooldownUntil)
			pushState(attacker, {
				Kind = "Intercepted",
				TargetName = strike.VictimName,
				Text = string.format(T.StrikeIntercepted, strike.VictimName),
			})
		end
		if NotificationService then
			NotificationService.Notify(victim, string.format(T.StrikeVictimIntercepted, strike.AttackerName), "Success")
		end
		return
	end

	-- Hit: the target's defenses go down (applies even if they got shielded mid-flight — the shield blocks raids)
	local down = RaidConfig.DownSeconds(strike.AttackerCC)
	local untilUnix = os.time() + down
	local vRaid = raidOf(vProfile)
	vRaid.DefensesDownUntil = untilUnix
	markDirty(victim)
	setAttr(victim, "WE_DefensesDownUntil", untilUnix)
	if GateDefenseService and GateDefenseService.SetDefensesDown then
		local ok, err = pcall(GateDefenseService.SetDefensesDown, strike.PlotId, untilUnix)
		if not ok then
			warn("[MissileStrike] SetDefensesDown failed", strike.PlotId, err)
		end
	end
	local downText = RaidConfig.FormatTime(down)
	if NotificationService then
		NotificationService.Notify(victim, string.format(T.StrikeVictimHit, downText), "Warn", 6)
	end
	if attacker then
		local hitText = string.format(T.StrikeHit, strike.VictimName, downText)
		if NotificationService then
			NotificationService.Notify(attacker, hitText, "Reward", 6)
		end
		pushState(attacker, {
			Kind = "Hit",
			TargetName = strike.VictimName,
			Text = hitText,
			DownSeconds = down,
		})
	end
end

-- ── launch (spec §2.4–2.6) ─────────────────────────────────────────────────

local function launch(attacker: Player, targetUserId: number): (boolean, string?, number?, Strike?)
	local S = RaidConfig.Strike
	local victim = Players:GetPlayerByUserId(targetUserId)
	if not victim then
		return false, "TargetOffline", nil, nil
	end
	local ok, reason, secs = MissileStrikeService.CanStrike(attacker, victim)
	if not ok then
		return false, reason, secs, nil
	end
	local aPlot = ownedPlotOf(attacker)
	local vPlot = ownedPlotOf(victim)
	if aPlot == nil or vPlot == nil then
		return false, "TargetOffline", nil, nil
	end
	if not atCommandCenter(attacker, aPlot) then
		return false, "NotAtCommandCenter", nil, nil
	end
	if not (EconomyService and EconomyService.GetCash and EconomyService.SpendCash) then
		return false, "Disabled", nil, nil
	end
	if (tonumber(EconomyService.GetCash(attacker)) or 0) < S.Cost then
		return false, "InsufficientCash", nil, nil
	end
	local from = batteryPos(aPlot)
	local to = gatePos(vPlot)
	if not from or not to then
		return false, "TargetOffline", nil, nil
	end
	local aProfile = profileOf(attacker)
	local vProfile = profileOf(victim)
	local distance = (to - from).Magnitude
	local flight = RaidConfig.FlightSeconds(distance)
	local arc = RaidConfig.ArcHeight(distance)
	local aCC = levelOf(aProfile, "CommandCenter")
	local aMD = levelOf(aProfile, "MissileDefense")
	local vMD = levelOf(vProfile, "MissileDefense")
	local chance = RaidConfig.InterceptChance(vMD, aMD)
	local intercepted = randomFn() < chance
	local interceptT = if intercepted then S.InterceptAtMin + randomFn() * (S.InterceptAtMax - S.InterceptAtMin) else nil
	local launchTime = Workspace:GetServerTimeNow()

	-- pay last, then register in the same synchronous block
	local spent = EconomyService.SpendCash(attacker, S.Cost, "missile_strike")
	if not spent then
		return false, "InsufficientCash", nil, nil
	end
	nextStrikeId += 1
	local nowUnix = os.time()
	local strike: Strike = {
		Id = nextStrikeId,
		AttackerUserId = attacker.UserId,
		AttackerName = attacker.DisplayName,
		VictimUserId = victim.UserId,
		VictimName = victim.DisplayName,
		PlotId = vPlot,
		LaunchUnix = nowUnix,
		LaunchClock = os.clock(),
		FlightSeconds = flight,
		Outcome = if intercepted then "Intercepted" else "Hit",
		AttackerCC = aCC,
		Cost = S.Cost,
	}
	strikes[strike.Id] = strike
	inFlight[attacker.UserId] = strike
	incoming[victim.UserId] = strike
	local aRaid = raidOf(aProfile)
	aRaid.StrikeCooldownUntil = nowUnix + S.CooldownSeconds
	markDirty(attacker)
	setAttr(attacker, "WE_StrikeCooldownUntil", aRaid.StrikeCooldownUntil)

	local fx: { [string]: any } = {
		StrikeId = strike.Id,
		AttackerUserId = attacker.UserId,
		AttackerName = attacker.DisplayName,
		VictimUserId = victim.UserId,
		VictimName = victim.DisplayName,
		PlotId = vPlot,
		From = from,
		To = to,
		ArcHeight = arc,
		LaunchTime = launchTime,
		FlightSeconds = flight,
		Outcome = strike.Outcome,
	}
	if intercepted then
		fx.InterceptT = interceptT
		fx.InterceptFrom = batteryPos(vPlot)
	else
		fx.DownSeconds = RaidConfig.DownSeconds(aCC)
	end
	local fxRemote = RemoteSetup.Get(Constants.RemoteNames.MissileStrikeFx)
	if fxRemote and fxRemote:IsA("RemoteEvent") then
		(fxRemote :: RemoteEvent):FireAllClients(fx)
	end
	task.delay(flight, resolve, strike.Id)
	if AnalyticsService and AnalyticsService.Log then
		local props = { VictimUserId = victim.UserId, Outcome = strike.Outcome, Chance = chance, Distance = math.floor(distance) }
		task.spawn(function()
			pcall(AnalyticsService.Log, "MISSILE_STRIKE", attacker.UserId, props)
		end)
	end
	return true, nil, nil, strike
end

function MissileStrikeService.Launch(attacker: Player, targetUserId: number): (boolean, string?)
	local ok, reason = launch(attacker, targetUserId)
	return ok, reason
end

-- ── remote ─────────────────────────────────────────────────────────────────

function MissileStrikeService.HandleRequest(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local action = payload.Action
	if action ~= "State" and action ~= "Launch" then
		return
	end
	local S = RaidConfig.Strike
	if RateLimitService and not RateLimitService.Allow(player, "missile_req", S.RequestRate, S.RequestBurst) then
		return
	end
	if action == "State" then
		pushState(player, nil)
		return
	end
	local targetUserId = RemoteGuard.ClampInt(payload.TargetUserId, 1, 2 ^ 53)
	if targetUserId == nil then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local targetName = if target then target.DisplayName else nil
	if RateLimitService and not RateLimitService.Allow(player, "missile_launch", S.LaunchRate, S.LaunchBurst) then
		pushState(player, { Kind = "Refused", TargetName = targetName, Reason = "Busy", Text = reasonText("Busy", nil) })
		return
	end
	local ok, reason, secs, strike = launch(player, targetUserId)
	if ok and strike then
		pushState(player, {
			Kind = "Launched",
			TargetName = strike.VictimName,
			Text = string.format(RaidConfig.Text.StrikeLaunched, strike.VictimName, math.ceil(strike.FlightSeconds)),
			ImpactIn = round1(strike.FlightSeconds),
		})
	else
		local code = reason or "Disabled"
		pushState(player, { Kind = "Refused", TargetName = targetName, Reason = code, Text = reasonText(code, secs) })
	end
end

-- Tests: deterministic interception rolls (nil restores the module RNG)
function MissileStrikeService.SetRandomForTests(fn: (() -> number)?)
	randomFn = fn or defaultRandom
end

function MissileStrikeService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	BaseService = deps.BaseService
	GateDefenseService = deps.GateDefenseService
	AnalyticsService = deps.AnalyticsService

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestMissileStrike)
	if remote and remote:IsA("RemoteEvent") then
		(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, payload: any)
			xpcall(MissileStrikeService.HandleRequest, function(err)
				warn("[MissileStrike] request failed", player.UserId, err)
			end, player, payload)
		end)
	end
	-- make sure the reply / FX remotes exist before any client binds them
	RemoteSetup.Get(Constants.RemoteNames.MissileStrikeStateUpdate)
	RemoteSetup.Get(Constants.RemoteNames.MissileStrikeFx)

	-- Mirror persisted timers for HUDs once the real save is in (strikes themselves never stop on leave: they
	-- resolve against whoever is still there, refunding when the target is gone)
	if DataService and DataService.OnProfileLoaded then
		DataService.OnProfileLoaded(function(player: Player, profile: any)
			setAttr(player, "WE_StrikeCooldownUntil", raidNum(profile, "StrikeCooldownUntil"))
			setAttr(player, "WE_DefensesDownUntil", raidNum(profile, "DefensesDownUntil"))
		end)
	end

	print("[WAR EMPIRE] MissileStrikeService ready (CC L3 + Missile Defense L1 · $5k · 10 min reload)")
end

return MissileStrikeService
