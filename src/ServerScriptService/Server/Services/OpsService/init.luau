--!strict
--[[
	OpsService — Jobs at every place (players see "Jobs"; the code says Ops). W3 step 2 Phase B, lane O.
	Spec scratchpad w3s2/spec_w3s2.md §4-§5, activities design §2-§3, contract w3s2/buildB/KB/contract.md §4.
	Config: Shared/Configs/OpsConfig (ships OFF). SERVER ONLY; the server decides every state, payout and cooldown.

	Modules (children): OpsSites (liveness, prompts, labels, doors), OpsKinds (the stage machine), OpsGarrison (NPC
	ledger + lane N's CombatService API), OpsZones (presence, under fire, teleport lockout), OpsCargo (bags),
	OpsDirector (which big sites are open), OpsRewards (pay, cooldowns, the saved Ops block).

	Off switches (Init returns at once, one log line, nothing created): OpsConfig.Enabled; OpsConfig.Validate() not
	empty; OpsConfig.Rewards.RequireCashExempt while MonetizationConfig.CashMultExemptReasons.ops ~= true (a job is
	never paid through a pass multiplier); RateLimitService missing. Per site: OpsSites.Resolve (switches, POI,
	coexistence with BankRaidService / the field NPCs, lane N, anchors, the streaming host rule).

	The client never sends a job request: there is NO Ops client -> server remote and no remote handler in this service. Every
	action is a server ProximityPrompt.Triggered, re-checked in this order: the rate limit
	(RateLimitService.Allow(player, "ops_prompt", ...)), the profile is loaded, alive, the root within
	MaxActivationDistance + Zones.PromptSlack of the anchor (server positions), on foot unless the site allows
	vehicles, the stage is valid, not on cooldown, not teleport-locked.

	Server -> client (contract §3): OpsState (RemoteEvent: a Full snapshot on profile load and every
	Remote.SnapshotSeconds, deltas coalesced to one per Remote.DeltaMinGap), OpsProgress (RemoteEvent, Remote.ProgressHz
	only while the player is inside an Active job's zone; one final {Site} hides the pill) and OpsPing
	(UnreliableRemoteEvent, every Remote.PingSeconds per carrier, non-allies only, never for a novice carrier).
	Timers are seconds remaining. About 2 + 4 + 0.1 Hz per player at most (<= 20 Hz).

	Performance: anchors are read once (ActivityAnchors.List) and re-read only on a 30 s health check; one 4 Hz tick
	for all sites (Heartbeat accumulator), wake / sleep and top-ups at 1 Hz, the director every 30 s. No per-frame
	scans, no descendant walks in any loop, no wait on the tree without a timeout.

	PUBLIC API (other lanes rely on these):
	  OpsService.Init(deps)
	  OpsService.IsLive(siteId) -> boolean
	  OpsService.GetSites() -> { { Id, State } }          (a copy; never per frame)
	  OpsService.IsCarrier(player) -> boolean
	  OpsService.OnJobDone(fn(player, siteId, kind, pay)) -> disconnect
	  OpsService.GoTargets(goKey) -> { {X, Y, Z} }?       (MissionService hooks, lane M1)
	  OpsService.ObjectiveLive(objectiveType) -> boolean?
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local OpsConfig = require(Shared.Configs.OpsConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local OpsSites = require(script.OpsSites)
local OpsKinds = require(script.OpsKinds)
local OpsGarrison = require(script.OpsGarrison)
local OpsZones = require(script.OpsZones)
local OpsCargo = require(script.OpsCargo)
local OpsDirector = require(script.OpsDirector)
local OpsRewards = require(script.OpsRewards)

local Z = OpsConfig.Zones
local N = OpsConfig.Npc
local REMOTE = OpsConfig.Remote
local TOAST = OpsConfig.Text.Toast
local D = OpsConfig.Director

local OpsService = {}

local DataService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local NotificationService: any = nil
local MissionService: any = nil
local CombatService: any = nil
local BaseService: any = nil
local NationColorService: any = nil

local running = false
local sites: { any } = {} -- runtime records, OpsConfig.Sites order
local byId: { [string]: any } = {}
local offReason: { [string]: string } = {}
local loaded: { [number]: boolean } = {} -- profile loaded: payloads flow
local pending: { [number]: { [string]: boolean } } = {}
local pendingAny: { [number]: boolean } = {}
local needFull: { [number]: boolean } = {}
local lastSent: { [number]: number } = {}
local nextFull: { [number]: number } = {}
local progSite: { [number]: string } = {}
local lastRobbedLine = -math.huge
local accum = 0
local wakeAccum = 0
local directorAccum = 0
local healthAccum = 0

-- analytics event names (AnalyticsConfig.Events; the literal name when a key is missing)
local Events: { [string]: string } = {}
for _, k in ipairs({ "OPS_OPEN", "OPS_START", "OPS_DONE", "OPS_FAIL", "BAG_GRAB", "BAG_DROP", "BAG_PICKUP", "BAG_DELIVER" }) do
	Events[k] = (AnalyticsConfig.Events :: any)[k] or k
end

-- ── helpers shared with the child modules (ctx) ─────────────────────────────────────────────────────────────────
local playerList: { Player } = {} -- Players:GetPlayers() once per tick (no per-site allocation)
local ctx: any = {
	PlayerList = playerList,
	Sites = OpsSites,
	Kinds = OpsKinds,
	Garrison = OpsGarrison,
	Zones = OpsZones,
	Cargo = OpsCargo,
	Director = OpsDirector,
	Rewards = OpsRewards,
	Events = Events,
}

local function profileOf(player: Player): any
	if DataService == nil then
		return nil
	end
	local ok, p = pcall(DataService.GetProfile, player)
	return if ok then p else nil
end
ctx.Profile = profileOf

function ctx.PlotOf(player: Player): number?
	if BaseService and typeof(BaseService.GetOwnedPlotId) == "function" then
		local ok, id = pcall(BaseService.GetOwnedPlotId, player)
		if ok and typeof(id) == "number" then
			return id
		end
	end
	local attr = player:GetAttribute("WE_PlotId")
	return if typeof(attr) == "number" and attr > 0 then attr else nil
end

function ctx.Notify(player: Player, msg: string, kind: string?)
	if NotificationService and NotificationService.Notify then
		pcall(NotificationService.Notify, player, msg, kind or "Info")
	end
end

function ctx.NotifyThrottled(player: Player, msg: string, kind: string?, gap: number, key: string)
	if NotificationService and typeof(NotificationService.NotifyThrottled) == "function" then
		pcall(NotificationService.NotifyThrottled, player, msg, kind or "Info", nil, gap, key)
	end
end

-- a job action ends the F6 novice shield (a shielded raider would carry an unstealable bag)
function ctx.EndNovice(player: Player)
	if CombatService and typeof(CombatService.EndNoviceShield) == "function" then
		pcall(CombatService.EndNoviceShield, player, "ops")
	end
end

-- the taker's cosmetic colour (NationColorService, the captured-ring rule); never a flag or a name
function ctx.ColorOf(player: Player): Color3?
	if NationColorService and typeof(NationColorService.GetColor) == "function" then
		local ok, c = pcall(NationColorService.GetColor, player.UserId)
		if ok and typeof(c) == "Color3" then
			return c
		end
	end
	return nil
end

function ctx.Blast(attacker: Player?, centre: Vector3, radius: number, damage: number)
	if CombatService and typeof(CombatService.ApplyRadiusDamage) == "function" then
		local ok, err = pcall(CombatService.ApplyRadiusDamage, attacker, centre, radius, damage, {
			WeaponId = "OpsCharge",
			RequireLos = false,
			Quiet = true,
		})
		if not ok then
			warn("[Ops] blast failed: " .. tostring(err))
		end
	end
end

local function markSite(rt: any)
	for uid in pairs(loaded) do
		local set = pending[uid]
		if set == nil then
			set = {}
			pending[uid] = set
		end
		set[rt.Id] = true
	end
end
ctx.MarkSite = markSite

function ctx.MarkPlayerSite(player: Player, siteId: string)
	local uid = player.UserId
	if not loaded[uid] then
		return
	end
	local set = pending[uid]
	if set == nil then
		set = {}
		pending[uid] = set
	end
	set[siteId] = true
end

function ctx.MarkAllBags()
	for uid in pairs(loaded) do
		pendingAny[uid] = true
	end
end

function ctx.SetState(rt: any, state: string, secs: number?)
	rt.State = state
	rt.StateUntil = if secs ~= nil then os.clock() + secs else nil
	OpsSites.Label(rt)
	OpsSites.Banner(rt)
	markSite(rt)
end

-- "Empire Bank raid started" to everyone else (once per 10 min each; never while being shot at)
function ctx.RaidStarted(rt: any, starter: Player?)
	local nowC = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		if (starter == nil or not OpsZones.Allies(starter, p)) and not OpsZones.HitWithin(p, nowC, D.SkipToastIfHitSeconds) then
			ctx.NotifyThrottled(p, TOAST.RaidStarted, "Info", D.OpenToastGapSeconds, "ops_raid")
		end
	end
end

local function remoteEvent(name: string): RemoteEvent?
	if RemoteSetup == nil then
		return nil
	end
	local ok, r = pcall(RemoteSetup.Get, name)
	if ok and typeof(r) == "Instance" and r:IsA("RemoteEvent") then
		return r
	end
	return nil
end

local function pingRemote(): any
	if RemoteSetup == nil or typeof(RemoteSetup.GetUnreliable) ~= "function" then
		return nil
	end
	local ok, r = pcall(RemoteSetup.GetUnreliable, Constants.RemoteNames.OpsPing)
	return if ok then r else nil
end

-- a carrier's position to every non-ally (the carrier is not a novice: OpsCargo checked)
function ctx.Ping(carrier: Player, bag: any)
	local s = OpsZones.Get(carrier)
	if s.Pos == nil then
		return
	end
	local payload: OpsConfig.OpsPingPayload = { U = carrier.UserId, X = math.floor(s.Pos.X + 0.5), Z = math.floor(s.Pos.Z + 0.5) }
	local remote = pingRemote()
	local def = OpsConfig.Get(bag.Site)
	local firstMove = def ~= nil and def.Kind == "Vault" and not bag.PingedMove
	bag.PingedMove = true
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= carrier and not OpsZones.Allies(carrier, p) then
			if remote then
				pcall(function()
					remote:FireClient(p, payload)
				end)
			end
			if firstMove then
				ctx.NotifyThrottled(p, TOAST.BagMoving, "Info", 60, "ops_bagmove")
			end
		end
	end
end

-- a bag reached its carrier's own plot: pay (the picker gets Cargo.PickerMult), toast, the bank's server line
function ctx.Deliver(player: Player, bag: any)
	local def = OpsConfig.Get(bag.Site)
	if def == nil then
		return
	end
	local value = OpsCargo.ValueFor(bag, player)
	if OpsRewards.Grant(player, def, value, bag.XP, true) then
		ctx.Notify(player, string.format(TOAST.Paid, def.Title, OpsRewards.FormatCash(value)), "Reward")
		OpsRewards.Log(Events.BAG_DELIVER, player.UserId, { site = def.Id, value = value, picked = player.UserId ~= bag.Grabber })
		ctx.MarkPlayerSite(player, def.Id)
		if def.Kind == "Vault" and os.clock() - lastRobbedLine >= D.RobbedLineGapSeconds then
			lastRobbedLine = os.clock()
			local line = string.format(TOAST.Robbed, player.DisplayName)
			for _, p in ipairs(Players:GetPlayers()) do
				ctx.Notify(p, line, "Info")
			end
		end
	end
end

-- ── the prompt re-checks (the ONLY way a player acts) ───────────────────────────────────────────────────────────
local function actor(player: Player, at: Vector3, dist: number, seatedOk: boolean): boolean
	local char = player.Character
	local rootInst = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if rootInst == nil or not rootInst:IsA("BasePart") or hum == nil or hum.Health <= 0 then
		return false
	end
	local root = rootInst :: BasePart
	if (root.Position - at).Magnitude > dist + Z.PromptSlack then
		return false
	end
	if not seatedOk and hum.SeatPart ~= nil then
		return false
	end
	return true
end

function ctx.OnSitePrompt(rt: any, key: string, role: string, stage: OpsConfig.StageDef, player: Player)
	if not RateLimitService.Allow(player, "ops_prompt", Z.RateLimitRate, Z.RateLimitBurst) then
		return
	end
	local profile = profileOf(player)
	if profile == nil then
		return
	end
	local def: OpsConfig.SiteDef = rt.Def
	local a = rt.Anchors[role]
	if a == nil or not actor(player, a.Position, stage.Dist or 10, def.AllowSeated == true) then
		return
	end
	if not rt.Live or rt.Prompts[key] == nil or not OpsKinds.PromptValid(rt, stage) then
		return
	end
	local left = OpsRewards.CdLeft(profile, def.Id, os.time())
	if left > 0 then
		ctx.NotifyThrottled(player, string.format(TOAST.JobCooldown, OpsKinds.FmtClock(left)), "Info", 3, "ops_cd")
		return
	end
	if OpsZones.Locked(player, os.clock()) then
		return
	end
	OpsKinds.OnPrompt(rt, stage, role, player)
end

function ctx.OnBagPrompt(bag: any, player: Player)
	if not RateLimitService.Allow(player, "ops_prompt", Z.RateLimitRate, Z.RateLimitBurst) then
		return
	end
	if profileOf(player) == nil or bag.Part == nil then
		return
	end
	if not actor(player, bag.Part.Position, OpsConfig.Cargo.PickupDist, false) then
		return
	end
	if OpsCargo.Carrying(player) ~= nil then
		ctx.Notify(player, TOAST.HandsFull, "Info")
		return
	end
	if OpsZones.Locked(player, os.clock()) then
		return
	end
	if OpsCargo.PickUp(bag, player) then
		ctx.EndNovice(player)
	end
end

-- ── sites: resolve, build, tear down ────────────────────────────────────────────────────────────────────────────
local function logOff(id: string, reason: string)
	if offReason[id] ~= reason then
		offReason[id] = reason
		print(string.format("[Ops] %s off: %s", id, reason))
	end
end

local function newRecord(def: OpsConfig.SiteDef, order: number): any
	return {
		Id = def.Id,
		Def = def,
		Order = order,
		Live = false,
		State = "Off",
		StateUntil = nil,
		Anchors = {},
		Points = {},
		Target = nil,
		Need = 0,
		Alloc = 0,
		AllocEvent = 0,
		Npcs = {},
		NpcCount = 0,
		RowNpc = {},
		Pending = 0,
		Spawned = 0,
		Killed = 0,
		Gen = 0,
		Prompts = {},
		Parts = {},
		Blocked = {},
		Planted = {},
		PlantCount = 0,
		Provoke = {},
		StageIdx = 1,
		StageAt = 0,
		Progress = 0,
		EmptyFor = 0,
		BagsTaken = 0,
		SleepSince = nil,
		LastEntered = os.clock(),
	}
end

-- the zone points: Target + every stage anchor + config deck posts (rigs): presence is "near any of them"
local function zonePoints(rt: any): { Vector3 }
	local def: OpsConfig.SiteDef = rt.Def
	local pts: { Vector3 } = {}
	local seen: { [any]: boolean } = {}
	local function add(a: any)
		if a ~= nil and not seen[a] then
			seen[a] = true
			table.insert(pts, a.Position)
		end
	end
	add(rt.Anchors[def.Target])
	for _, st in ipairs(def.Stages) do
		if st.At then
			add(rt.Anchors[st.At])
		end
		for _, r in ipairs(st.AtAny or {}) do
			add(rt.Anchors[r])
		end
	end
	for _, row in ipairs(def.Garrison) do
		if row.At ~= nil then
			table.insert(pts, Vector3.new(row.At.X, row.At.Y, row.At.Z))
		end
	end
	return pts
end

local function goLive(rt: any, byRole: { [string]: any }, persist: { Model })
	local def: OpsConfig.SiteDef = rt.Def
	OpsSites.Persist(persist)
	rt.Anchors = byRole
	rt.Live = true
	rt.RotateRole = if def.Rotate then def.Rotate[1] else nil
	if rt.RotateRole ~= nil and byRole[rt.RotateRole] == nil then
		for _, r in ipairs(def.Rotate or {}) do
			if byRole[r] ~= nil then
				rt.RotateRole = r
				break
			end
		end
	end
	rt.Target = byRole[rt.RotateRole or def.Target] or byRole[def.Target]
	rt.Points = zonePoints(rt)
	rt.Need = OpsGarrison.Need(rt)
	rt.Door = OpsSites.FindDoor(rt)
	rt.DoorClose = rt.Door ~= nil
	rt.Banner = if def.Kind == "Vault" then OpsSites.FindBanner(rt) else nil
	offReason[rt.Id] = nil
	print(string.format("[Ops] %s live (%s, %d NPC slots)", rt.Id, def.Kind, rt.Need))
	if OpsDirector.Rotating(rt) then
		rt.State = "Closed"
		rt.ClosedAt = nil
		OpsSites.Label(rt)
		OpsSites.Banner(rt)
	else
		ctx.SetState(rt, if rt.Need > 0 then "Dormant" else "Open")
		OpsKinds.Reset(rt)
	end
end

local function goOff(rt: any, reason: string)
	if rt.Live then
		if rt.State == "Active" then
			OpsKinds.End(rt, false, nil)
		end
		OpsGarrison.Sleep(rt)
		OpsSites.DropPrompts(rt)
		OpsSites.DropLabel(rt)
		OpsSites.Smoke(rt, false)
		OpsSites.Sparks(rt, false)
		OpsSites.HeldSign(rt, nil)
		rt.Live = false
		rt.State = "Off"
		markSite(rt)
	end
	logOff(rt.Id, reason)
end

local function anchorsById(): { [string]: any }
	local map: { [string]: any } = {}
	local ok, AA = pcall(function(): any
		local modules = script.Parent and script.Parent.Parent and script.Parent.Parent:FindFirstChild("Modules")
		local m = modules and modules:FindFirstChild("ActivityAnchors")
		return if m and m:IsA("ModuleScript") then require(m) :: any else nil
	end)
	if not ok or AA == nil then
		return map
	end
	local okL, list = pcall(AA.List)
	if okL and typeof(list) == "table" then
		for _, a in ipairs(list) do
			map[a.Id] = a
		end
	end
	return map
end

local function resolveAll(onlyWaiting: boolean)
	local anchors = anchorsById()
	local changed = false
	for _, rt in ipairs(sites) do
		if not rt.Live then
			local waiting = offReason[rt.Id] == nil or string.find(offReason[rt.Id], "anchor", 1, true) ~= nil
			if not onlyWaiting or waiting then
				local byRole, extra = OpsSites.Resolve(rt.Def, anchors)
				if byRole ~= nil then
					goLive(rt, byRole, extra)
					changed = true
				else
					logOff(rt.Id, tostring(extra))
				end
			end
		end
	end
	if changed then
		for uid in pairs(loaded) do
			needFull[uid] = true
		end
		OpsDirector.Tick(sites, os.clock(), true)
	end
end

-- 30 s health check: a live site whose anchor lost its host goes off and waits for a re-resolve
local function healthCheck()
	local lost = false
	for _, rt in ipairs(sites) do
		if rt.Live then
			for role, a in pairs(rt.Anchors) do
				if a.Attachment.Parent == nil then
					goOff(rt, "anchor " .. role .. " lost")
					lost = true
					break
				end
			end
		end
	end
	local anyWaiting = lost
	for _, rt in ipairs(sites) do
		local r = offReason[rt.Id]
		if not rt.Live and r ~= nil and string.find(r, "anchor", 1, true) ~= nil then
			anyWaiting = true
		end
	end
	if anyWaiting then
		resolveAll(true)
	end
end

-- ── payloads ────────────────────────────────────────────────────────────────────────────────────────────────────
local function r0(n: number): number
	return math.floor(n + 0.5)
end

local function snap(rt: any, profile: any, full: boolean, nowC: number, nowU: number): OpsConfig.OpsSiteSnap
	local def: OpsConfig.SiteDef = rt.Def
	local s: OpsConfig.OpsSiteSnap = { Id = rt.Id, State = rt.State }
	if not rt.Live then
		s.State = "Off"
		return s
	end
	if full or def.Rotate ~= nil then
		local p: Vector3 = rt.Target.Position
		s.X, s.Y, s.Z = r0(p.X), r0(p.Y * 10) / 10, r0(p.Z)
	end
	if rt.State == "Active" and rt.LockUntil then
		s.Left = math.max(0, math.ceil(rt.LockUntil - nowC))
	elseif (rt.State == "Cooling" or rt.State == "Held") and rt.StateUntil then
		s.Left = math.max(0, math.ceil(rt.StateUntil - nowC))
	end
	if profile ~= nil then
		local cash = OpsRewards.Quote(profile, def, nowU)
		s.Pay = cash
		local cd = OpsRewards.CdLeft(profile, def.Id, nowU)
		if cd > 0 then
			s.MyCd = cd
		end
	end
	if rt.Need > 0 and (rt.State == "Open" or rt.State == "Active") then
		s.Guards = rt.NpcCount
	end
	if rt.State == "Held" then
		s.HeldBy = rt.HeldBy
	end
	return s
end

local function send(player: Player, full: boolean)
	local uid = player.UserId
	local remote = remoteEvent(Constants.RemoteNames.OpsState)
	if remote == nil then
		return
	end
	local profile = profileOf(player)
	local nowC, nowU = os.clock(), os.time()
	local list: { OpsConfig.OpsSiteSnap } = {}
	if full then
		for _, rt in ipairs(sites) do
			if rt.Live then
				table.insert(list, snap(rt, profile, true, nowC, nowU))
			end
		end
	else
		for id in pairs(pending[uid] or {}) do
			local rt = byId[id]
			if rt then
				table.insert(list, snap(rt, profile, false, nowC, nowU))
			end
		end
		table.sort(list, function(a, b)
			return a.Id < b.Id
		end)
	end
	local bags = OpsCargo.BagSnaps(nowC)
	local payload: OpsConfig.OpsStatePayload = {
		V = OpsConfig.PayloadVersion,
		Full = full,
		Sites = list,
		Home = if full then OpsCargo.HomePoint(player) else nil,
		Carrying = OpsCargo.CarrySnap(player, nowC),
		Bags = if #bags > 0 then bags else nil,
	}
	pending[uid] = nil
	pendingAny[uid] = nil
	lastSent[uid] = nowC
	if full then
		needFull[uid] = nil
		nextFull[uid] = nowC + REMOTE.SnapshotSeconds
	end
	pcall(function()
		remote:FireClient(player, payload)
	end)
end

local function flushState(nowC: number)
	for _, p in ipairs(playerList) do
		local uid = p.UserId
		if loaded[uid] then
			local gapOk = nowC - (lastSent[uid] or -math.huge) >= REMOTE.DeltaMinGap
			if needFull[uid] or nowC >= (nextFull[uid] or 0) then
				if gapOk or needFull[uid] then
					send(p, true)
				end
			elseif gapOk and (pendingAny[uid] or (pending[uid] ~= nil and next(pending[uid]) ~= nil)) then
				send(p, false)
			end
		end
	end
end

local function sendProgress(nowC: number)
	local remote = remoteEvent(Constants.RemoteNames.OpsProgress)
	if remote == nil then
		return
	end
	for _, p in ipairs(playerList) do
		local uid = p.UserId
		local s = OpsZones.Get(p)
		local payload: OpsConfig.OpsProgressPayload? = nil
		if loaded[uid] and s.Alive and s.Pos then
			for _, rt in ipairs(sites) do
				if rt.Live and rt.State == "Active" then
					local def: OpsConfig.SiteDef = rt.Def
					if OpsZones.NearAny(s.Pos, rt.Points, def.PresentR or Z.PresentR, def.AllowSeated) then
						payload = OpsKinds.Progress(rt, p, nowC)
						if payload then
							break
						end
					end
				end
			end
		end
		if payload then
			progSite[uid] = payload.Site
			pcall(function()
				remote:FireClient(p, payload)
			end)
		elseif progSite[uid] ~= nil then
			local done: OpsConfig.OpsProgressPayload = { Site = progSite[uid] }
			progSite[uid] = nil
			pcall(function()
				remote:FireClient(p, done)
			end)
		end
	end
end

-- ── the ticks ───────────────────────────────────────────────────────────────────────────────────────────────────
local function nearestPlayers(rt: any): (number, number)
	local onFoot, any = math.huge, math.huge
	for _, p in ipairs(playerList) do
		local s = OpsZones.Get(p)
		if s.Alive and s.Pos then
			local d = OpsZones.Nearest(s.Pos, rt.Points)
			if d < any then
				any = d
			end
			if not s.Seated and d < onFoot then
				onFoot = d
			end
		end
	end
	return onFoot, any
end

local function clearOf(radius: number): (Vector3) -> boolean
	return function(pos: Vector3): boolean
		for _, p in ipairs(playerList) do
			local s = OpsZones.Get(p)
			if s.Pos and OpsZones.Within(s.Pos, pos, radius, true) then
				return false
			end
		end
		return true
	end
end

local function standingCount(rt: any): number
	local n = 0
	for _, row in ipairs((rt.Def :: OpsConfig.SiteDef).Garrison) do
		if (row.When == nil or row.When == "Open") and OpsGarrison.RowCFrame(rt, row) ~= nil then
			n += 1
		end
	end
	return n
end

local function wake(rt: any)
	if not OpsGarrison.Reserve(rt) then
		if rt.State ~= "Quiet" then
			OpsSites.DropPrompts(rt)
			ctx.SetState(rt, "Quiet")
		end
		return
	end
	local before = rt.Spawned
	local want = math.min(N.MinGarrison, standingCount(rt))
	local gen = rt.Gen
	OpsGarrison.SpawnRows(rt, nil, nil, function()
		if rt.Gen == gen and want > 0 and rt.Spawned - before < want then
			-- CombatService refused (its cap): never a clearable empty site
			OpsGarrison.Sleep(rt)
			OpsSites.DropPrompts(rt)
			ctx.SetState(rt, "Quiet")
		end
		markSite(rt)
	end)
	if rt.State == "Dormant" or rt.State == "Quiet" then
		ctx.SetState(rt, "Open")
		OpsKinds.Idle(rt)
	end
end

local function wakeTick(nowC: number)
	local wakeCfg = N.Wake
	for _, rt in ipairs(sites) do
		if rt.Live and rt.State ~= "Closed" then
			local def: OpsConfig.SiteDef = rt.Def
			local onFoot, any = nearestPlayers(rt)
			if any <= (def.PresentR or Z.PresentR) then
				rt.LastEntered = nowC
			end
			if rt.Need > 0 then
				local w = wakeCfg[def.Wake] or wakeCfg.Default
				local near = onFoot <= w.OnFoot or any <= w.Any
				if rt.Alloc == 0 and rt.Pending == 0 then
					if near and (rt.State == "Dormant" or rt.State == "Quiet" or rt.State == "Open") then
						wake(rt)
					elseif not near and rt.State == "Quiet" then
						ctx.SetState(rt, "Dormant")
					end
				else
					if any > N.SleepRadius then
						rt.SleepSince = rt.SleepSince or nowC
						if nowC - rt.SleepSince >= N.SleepGraceSeconds then
							rt.SleepSince = nil
							if rt.State == "Active" then
								OpsKinds.End(rt, false, nil)
							end
							OpsGarrison.Sleep(rt)
							if rt.State == "Open" or rt.State == "Quiet" then
								OpsSites.DropPrompts(rt)
								ctx.SetState(rt, "Dormant")
							end
						end
					else
						rt.SleepSince = nil
						if rt.State == "Open" and rt.Pending == 0 and rt.Alloc > 0 then
							local before = rt.NpcCount
							OpsGarrison.SpawnRows(rt, nil, clearOf(N.TopUpClearRadius), function()
								if rt.NpcCount ~= before then
									markSite(rt)
								end
							end)
						end
					end
				end
			elseif rt.State == "Dormant" or rt.State == "Quiet" then
				ctx.SetState(rt, "Open")
				OpsKinds.Idle(rt)
			end
		end
	end
	-- the one-time bank tip (Seen bit BankVisit) within Director.FirstVisitRadius
	local bank = byId["Town.Bank"]
	if bank and bank.Live then
		local bit = OpsConfig.Profile.SeenBits.BankVisit
		for _, p in ipairs(playerList) do
			local s = OpsZones.Get(p)
			local profile = if loaded[p.UserId] then profileOf(p) else nil
			if profile and s.Pos and not OpsZones.HitWithin(p, nowC, D.SkipToastIfHitSeconds)
				and OpsZones.NearAny(s.Pos, bank.Points, D.FirstVisitRadius, true)
				and not OpsRewards.HasSeen(profile, bit)
			then
				OpsRewards.MarkSeen(p, profile, bit)
				ctx.Notify(p, TOAST.BankFirst, "Info")
			end
		end
	end
end

local function timers(nowC: number)
	for _, rt in ipairs(sites) do
		if rt.Live then
			local def: OpsConfig.SiteDef = rt.Def
			if rt.State == "Cooling" and rt.StateUntil and nowC >= rt.StateUntil then
				ctx.SetState(rt, if rt.Alloc > 0 or rt.Need == 0 then "Open" else "Dormant")
				OpsKinds.Reset(rt)
			elseif rt.State == "Held" and rt.StateUntil and nowC >= rt.StateUntil then
				local _, any = nearestPlayers(rt)
				if any > (def.RegarrisonClear or 100) then
					rt.HeldBy = nil
					rt.HeldColor = nil
					OpsSites.HeldSign(rt, nil)
					ctx.SetState(rt, if rt.Need == 0 then "Open" else "Dormant")
					OpsKinds.Reset(rt)
				end
			end
			if rt.DoorClose and rt.State ~= "Active" then
				local _, any = nearestPlayers(rt)
				if any > (def.PresentR or Z.PresentR) then
					rt.DoorClose = false
					OpsSites.SetDoor(rt, false)
				end
			end
		end
	end
end

local function onTeleport(player: Player, prevPos: Vector3?)
	local uid = player.UserId
	for _, rt in ipairs(sites) do
		if rt.Parts[uid] ~= nil then
			rt.Parts[uid] = nil
		end
	end
	-- a bag never travels by teleport or a new character: it drops where the carrier stood
	if prevPos ~= nil and OpsCargo.Carrying(player) ~= nil then
		OpsCargo.DropFor(player, prevPos)
	end
end

--[[ One OpsService tick (Heartbeat accumulator at Zones.TickSeconds). Exposed for the headless drivers. ]]
function OpsService._Step(dt: number)
	if not running then
		return
	end
	local nowC = os.clock()
	playerList = Players:GetPlayers()
	ctx.PlayerList = playerList
	for _, p in ipairs(playerList) do
		OpsZones.SamplePlayer(p, nowC, dt)
	end
	for _, rt in ipairs(sites) do
		if rt.Live then
			local ok, err = pcall(OpsKinds.Tick :: any, rt, dt, nowC)
			if not ok then
				warn("[Ops] tick " .. rt.Id .. ": " .. tostring(err))
			end
		end
	end
	OpsCargo.Tick(nowC)
	timers(nowC)
	wakeAccum += dt
	if wakeAccum >= 1 then
		wakeAccum = 0
		wakeTick(nowC)
	end
	directorAccum += dt
	if directorAccum >= D.TickSeconds then
		directorAccum = 0
		OpsDirector.Tick(sites, nowC, false)
	end
	healthAccum += dt
	if healthAccum >= 30 then
		healthAccum = 0
		healthCheck()
	end
	sendProgress(nowC)
	flushState(nowC)
end

-- ── players ─────────────────────────────────────────────────────────────────────────────────────────────────────
local function onProfileLoaded(player: Player, profile: any)
	if not running or player.Parent == nil then
		return
	end
	local nowU = os.time()
	OpsRewards.Block(profile, nowU)
	OpsRewards.AdoptBankCooldown(profile, nowU)
	loaded[player.UserId] = true
	needFull[player.UserId] = true
	-- "Jobs are on the map · see Missions": once (Seen bit Intro), after the tutorial, while a job is live
	local anyLive = false
	for _, rt in ipairs(sites) do
		if rt.Live then
			anyLive = true
			break
		end
	end
	local bit = OpsConfig.Profile.SeenBits.Intro
	if anyLive and profile.TutorialComplete == true and not OpsRewards.HasSeen(profile, bit) then
		OpsRewards.MarkSeen(player, profile, bit)
		task.delay(8, function()
			if player.Parent then
				ctx.Notify(player, TOAST.Intro, "Info")
			end
		end)
	end
end

local function onRemoving(player: Player)
	local uid = player.UserId
	OpsCargo.OnLeave(player)
	onTeleport(player)
	OpsZones.Forget(player)
	loaded[uid] = nil
	pending[uid] = nil
	pendingAny[uid] = nil
	needFull[uid] = nil
	lastSent[uid] = nil
	nextFull[uid] = nil
	progSite[uid] = nil
end

-- ── public API ──────────────────────────────────────────────────────────────────────────────────────────────────
function OpsService.IsLive(siteId: string): boolean
	local rt = byId[siteId]
	return rt ~= nil and rt.Live == true
end

function OpsService.GetSites(): { { Id: string, State: string } }
	local out: { { Id: string, State: string } } = {}
	for _, rt in ipairs(sites) do
		table.insert(out, { Id = rt.Id, State = if rt.Live then rt.State else "Off" })
	end
	return out
end

function OpsService.IsCarrier(player: Player): boolean
	return OpsCargo.Carrying(player) ~= nil
end

function OpsService.OnJobDone(fn: (player: Player, siteId: string, kind: string, pay: number) -> ()): () -> ()
	return OpsRewards.OnJobDone(fn)
end

local GO_KINDS: { [string]: { [string]: boolean } } = {
	Checkpoint = { Checkpoint = true },
	Camp = { Camp = true },
	Uplink = { Uplink = true },
	Hostiles = { Checkpoint = true, Camp = true },
	Cargo = { VaultLite = true, Cargo = true }, -- lane M1: the Haul Cargo daily op (Delivery)
}

--[[ MissionService hook (lane M1): every Open site for a Go key (the client picks the nearest). nil = not an Ops
	key, or the bank is not an Ops site yet (MissionService keeps its own resolver). ]]
function OpsService.GoTargets(goKey: string): { { X: number, Y: number, Z: number } }?
	if not running then
		return nil
	end
	local function point(rt: any): { X: number, Y: number, Z: number }
		local p: Vector3 = rt.Target.Position
		return { X = r0(p.X), Y = r0(p.Y), Z = r0(p.Z) }
	end
	if goKey == "Bank" then
		local bank = byId["Town.Bank"]
		if bank == nil or not bank.Live then
			return nil
		end
		return { point(bank) }
	end
	local kinds = GO_KINDS[goKey]
	if kinds == nil and goKey ~= "Job" then
		return nil
	end
	local out: { { X: number, Y: number, Z: number } } = {}
	for _, rt in ipairs(sites) do
		local def: OpsConfig.SiteDef = rt.Def
		if rt.Live and (rt.State == "Open" or rt.State == "Dormant") and (kinds == nil or kinds[def.Kind]) then
			table.insert(out, point(rt))
		end
	end
	return out
end

--[[ MissionService hook: is an Ops objective type live (some live site reports it)? nil = not an Ops type, or the
	Heist while the bank is not an Ops site (BankRaidService reports it until the cutover). ]]
function OpsService.ObjectiveLive(objectiveType: string): boolean?
	if not running or table.find(OpsConfig.TrackTypes, objectiveType) == nil then
		return nil
	end
	if objectiveType == "Heist" then
		local bank = byId["Town.Bank"]
		return if bank and bank.Live then true else nil
	end
	for _, rt in ipairs(sites) do
		if rt.Live then
			local kind = OpsConfig.Kinds[(rt.Def :: OpsConfig.SiteDef).Kind]
			if kind and table.find(kind.Track, objectiveType) ~= nil then
				return true
			end
		end
	end
	return false
end

-- headless drivers only: the shared state
function OpsService._Ctx(): any
	ctx.SitesList = sites
	ctx.ById = byId
	ctx.OffReason = offReason
	ctx.Running = running
	return ctx
end

-- ── Init ────────────────────────────────────────────────────────────────────────────────────────────────────────
local function cashExempt(): boolean
	local ok, cfg = pcall(function(): any
		return require(Shared.Configs.MonetizationConfig) :: any
	end)
	if not ok or typeof(cfg) ~= "table" then
		return false
	end
	local ex = cfg.CashMultExemptReasons
	return typeof(ex) == "table" and ex[OpsConfig.Rewards.CashReason] == true
end

function OpsService.Init(deps: { [string]: any })
	if running then
		return
	end
	if OpsConfig.Enabled ~= true then
		print("[Ops] OpsService off (OpsConfig.Enabled = false)")
		return
	end
	local problems = OpsConfig.Validate()
	if #problems > 0 then
		warn("[Ops] OpsService off: OpsConfig.Validate: " .. table.concat(problems, "; "))
		return
	end
	if OpsConfig.Rewards.RequireCashExempt and not cashExempt() then
		warn('[Ops] OpsService off: MonetizationConfig.CashMultExemptReasons has no "ops" (job pay must never be pass-multiplied)')
		return
	end
	if deps.RateLimitService == nil or typeof(deps.RateLimitService.Allow) ~= "function" then
		warn("[Ops] OpsService off: RateLimitService missing (every prompt is rate-limited)")
		return
	end
	if Z.RateLimitKey ~= "ops_prompt" then
		warn("[Ops] Zones.RateLimitKey is " .. tostring(Z.RateLimitKey) .. "; OpsService uses ops_prompt")
	end
	DataService = deps.DataService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	NotificationService = deps.NotificationService
	MissionService = deps.MissionService
	CombatService = deps.CombatService
	BaseService = deps.BaseService
	NationColorService = deps.NationColorService
	running = true

	OpsRewards.Init(deps)
	OpsZones.Init(deps, onTeleport)
	OpsGarrison.Init(deps, function(rt: any, _info: any)
		markSite(rt)
	end)
	OpsCargo.Init(ctx)
	OpsSites.Init(ctx)
	OpsKinds.Init(ctx)
	OpsDirector.Init(ctx)

	sites = {}
	byId = {}
	for i, def in ipairs(OpsConfig.Sites) do
		local rt = newRecord(def, i)
		table.insert(sites, rt)
		byId[def.Id] = rt
	end

	if CombatService and typeof(CombatService.OnPlayerDeath) == "function" then
		pcall(CombatService.OnPlayerDeath, function(victim: Player, _killer: Player?, _info: any)
			OpsCargo.OnDeath(victim)
		end)
	end
	if DataService and typeof(DataService.OnProfileLoaded) == "function" then
		DataService.OnProfileLoaded(onProfileLoaded)
	end
	Players.PlayerRemoving:Connect(onRemoving)
	if MissionService and typeof(MissionService.SetOpsHooks) == "function" then
		local ok, err = pcall(MissionService.SetOpsHooks, { GoTargets = OpsService.GoTargets, ObjectiveLive = OpsService.ObjectiveLive })
		if not ok then
			warn("[Ops] MissionService.SetOpsHooks failed: " .. tostring(err))
		end
	end

	-- the world dressing (and its anchors) is built a few frames after MapSetup: resolve shortly after, then the
	-- 30 s health check re-resolves sites still waiting for anchors
	task.delay(3, function()
		resolveAll(false)
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum < Z.TickSeconds then
			return
		end
		local step = accum
		accum = 0
		local ok, err = pcall(OpsService._Step :: any, step)
		if not ok then
			warn("[Ops] step failed: " .. tostring(err))
		end
	end)
	print("[Ops] OpsService running (" .. #sites .. " sites configured)")
end

-- headless drivers: resolve now (instead of the 3 s delay)
function OpsService._Resolve()
	resolveAll(false)
end

return OpsService
