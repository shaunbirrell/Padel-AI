--!strict
--[[
	claude-bud JOB 30 (2026-09-30): the world map's server feed (MapConfig; client MapController).

	RequestMapLive (RemoteFunction, no arguments) -> the live marker snapshot while the map is open (the client asks at
	most MapConfig.RefreshSeconds apart; RemoteGate + RateLimitService cap it):
	  {
	    Bases = { { P = plotId, N = "<Name>'s Empire" | nil, X, Z, Mine } },
	    Outposts = { { Id, O = OwnerType, Mine } },
	    Drops = { { X, Z, A = airdrop? } },
	    Jobs = { { S = short label, X, Z } },
	    Bank = { X, Z },
	    TravelIn = seconds until fast travel is ready (0 = ready, -1 = not live for him),
	  }
	  Plot owners are server-only; the names use BaseSignService.TitleFor, the same string as the base sign.
	  The shared part is rebuilt at most every RefreshSeconds (one CollectionService read of ~20 zones and <= 3
	  drops), whatever the number of players; only the Mine flags are per player.
	RequestFastTravel (RemoteFunction, target: "Base" | a TerritoryConfig Id) -> { Ok, Reason? }.
	  Allowed only to his own base or an outpost he or his clan holds; never into a contested one, never while hurt in
	  the server's damage lock (VehicleService: any health drop in the last DamageLockSeconds; RecentlyHurtBy is PvP only, so the lock is
	  used), never from a seat, once per CooldownSeconds. The base goes through BaseService.TeleportToPlot; an outpost
	  through StreamPrefetch.Place at its edge. Nothing the client sends is trusted beyond the target id.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MapConfig = require(Shared.Configs.MapConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BankRaidConfig = require(Shared.Configs.BankRaidConfig)
local MissionConfig = require(Shared.Configs.MissionConfig)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local StreamPrefetch = require(script.Parent.Parent.Modules.StreamPrefetch)

local MapService = {}

local deps: { [string]: any } = {}
local lastTravelAt: { [number]: number } = {}

local JOB_KEYS = { "Checkpoint", "Camp", "Uplink", "Cargo" } -- MissionConfig.Go kinds shown (Job / Hostiles repeat them)
local MAX_JOBS = 30

local function live(userId: number): boolean
	return RetentionConfig.Live(MapConfig, userId)
end

local function travelLive(userId: number): boolean
	return live(userId) and RetentionConfig.Live(MapConfig.FastTravel, userId)
end

-- ── the shared snapshot (rebuilt at most every RefreshSeconds) ────────────────────────────────────────────────────
type Shared = { At: number, Bases: { any }, Outposts: { any }, Drops: { any }, Jobs: { any } }
local snap: Shared? = nil

local function zoneInfo(): { [string]: { O: string, U: number, C: string? } }
	local out: { [string]: { O: string, U: number, C: string? } } = {}
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.Territory)) do
		local id = inst:GetAttribute("TerritoryId")
		if typeof(id) == "string" then
			out[id] = {
				O = tostring(inst:GetAttribute("OwnerType") or "Neutral"),
				U = tonumber(inst:GetAttribute("OwnerUserId")) or 0,
			}
		end
	end
	return out
end

local function rebuild(): Shared
	local now = os.clock()
	local s = snap
	if s and now - s.At < math.max(0.25, MapConfig.RefreshSeconds) then
		return s
	end
	local bs = deps.BaseService
	local sign = deps.BaseSignService
	local bases = {}
	for plotId = 1, BaseConfig.MaxPlots do
		local ok, pos = pcall(PlotFrame.PlotPosition, plotId)
		if ok and typeof(pos) == "Vector3" then
			local owner = if bs and bs.GetOwnerUserId then bs.GetOwnerUserId(plotId) else nil
			local title = if owner and sign and sign.TitleFor then sign.TitleFor(plotId) else nil
			table.insert(bases, { P = plotId, N = title, X = math.floor(pos.X), Z = math.floor(pos.Z), U = owner or 0 })
		end
	end
	local zones = zoneInfo()
	local outposts = {}
	for _, def in pairs(TerritoryConfig.Territories) do -- keyed by Id
		if def.IsStarter ~= true then
			local z = zones[def.Id]
			table.insert(outposts, { Id = def.Id, O = if z then z.O else "Neutral", U = if z then z.U else 0 })
		end
	end
	local drops = {}
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.SupplyDrop)) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) and #drops < 6 then
			local p = inst.Position
			table.insert(drops, { X = math.floor(p.X), Z = math.floor(p.Z), A = inst:GetAttribute("WE_Airdrop") == true })
		end
	end
	local jobs = {}
	local ops = deps.OpsService
	if ops and ops.GoTargets then
		for _, key in ipairs(JOB_KEYS) do
			local def = MissionConfig.Go[key]
			local ok, list = pcall(ops.GoTargets, key)
			if def and ok and typeof(list) == "table" then
				for _, t in ipairs(list) do
					if #jobs >= MAX_JOBS then
						break
					end
					if typeof(t) == "table" and tonumber(t.X) and tonumber(t.Z) then
						table.insert(jobs, { S = def.Short, X = math.floor(t.X), Z = math.floor(t.Z) })
					end
				end
			end
		end
	end
	local fresh: Shared = { At = now, Bases = bases, Outposts = outposts, Drops = drops, Jobs = jobs }
	snap = fresh
	return fresh
end

local function sameClan(player: Player, userId: number): boolean
	local clans = deps.ClanService
	if userId == 0 or clans == nil or clans.GetClanId == nil then
		return false
	end
	local other = Players:GetPlayerByUserId(userId)
	if other == nil then
		return false
	end
	local okA, a = pcall(clans.GetClanId, player)
	local okB, b = pcall(clans.GetClanId, other)
	return okA and okB and a ~= nil and a == b
end

local function travelLeft(player: Player): number
	if not travelLive(player.UserId) then
		return -1
	end
	local at = lastTravelAt[player.UserId]
	if at == nil then
		return 0
	end
	return math.max(0, math.ceil(MapConfig.FastTravel.CooldownSeconds - (os.clock() - at)))
end

function MapService.Live(player: Player): { [string]: any }?
	if not live(player.UserId) then
		return nil
	end
	local s = rebuild()
	local uid = player.UserId
	local bases, outposts = {}, {}
	for _, b in ipairs(s.Bases) do
		table.insert(bases, { P = b.P, N = b.N, X = b.X, Z = b.Z, Mine = b.U == uid })
	end
	for _, o in ipairs(s.Outposts) do
		local mine = (o.O == "Player" and o.U == uid) or (o.O == "Clan" and sameClan(player, o.U))
		table.insert(outposts, { Id = o.Id, O = o.O, Mine = mine })
	end
	return {
		Bases = bases,
		Outposts = outposts,
		Drops = s.Drops,
		Jobs = s.Jobs,
		Bank = { X = math.floor(BankRaidConfig.Position.X), Z = math.floor(BankRaidConfig.Position.Z) },
		TravelIn = travelLeft(player),
	}
end

-- ── fast travel ───────────────────────────────────────────────────────────────────────────────────────────────────
local function inCombat(player: Player): boolean
	local vs = deps.VehicleService
	if vs and vs._DamageLockLeft then
		local ok, left = pcall(vs._DamageLockLeft, player.UserId)
		if ok and typeof(left) == "number" and left > 0 then
			return true
		end
	end
	return false
end

function MapService.FastTravel(player: Player, target: any): (boolean, string?)
	if not travelLive(player.UserId) or typeof(target) ~= "string" then
		return false, "Off"
	end
	if travelLeft(player) > 0 then
		return false, "Cooldown"
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char == nil or hum == nil or hum.Health <= 0 then
		return false, "NoCharacter"
	end
	if hum.SeatPart ~= nil then
		return false, "Seated"
	end
	if inCombat(player) then
		return false, "InCombat"
	end
	if target == "Base" then
		local bs = deps.BaseService
		if bs == nil or bs.GetOwnedPlotId == nil or bs.GetOwnedPlotId(player) == nil then
			return false, "NoBase"
		end
		lastTravelAt[player.UserId] = os.clock()
		local ok = pcall(bs.TeleportToPlot, player)
		return ok, if ok then nil else "Failed"
	end
	local def: any = TerritoryConfig.Territories[target] -- keyed by Id
	if def == nil or def.IsStarter == true then
		return false, "Unknown"
	end
	local z = zoneInfo()[def.Id]
	local held = z ~= nil and ((z.O == "Player" and z.U == player.UserId) or (z.O == "Clan" and sameClan(player, z.U)))
	if not held then
		return false, if z and z.O == "Contested" then "Contested" else "Locked"
	end
	-- land at the zone's edge, facing its centre, on the ground below
	local centre: Vector3 = def.Position
	local r = math.max(8, (tonumber(def.Radius) or 40) * 0.6)
	local at = centre + Vector3.new(0, 0, r)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(at + Vector3.new(0, 300, 0), Vector3.new(0, -700, 0), params)
	local ground = if hit then hit.Position.Y else centre.Y
	local cf = CFrame.lookAt(Vector3.new(at.X, ground + 4, at.Z), Vector3.new(centre.X, ground + 4, centre.Z))
	lastTravelAt[player.UserId] = os.clock()
	StreamPrefetch.Place(char, cf)
	return true, nil
end

function MapService.Init(d: { [string]: any })
	deps = d
	local RemoteSetup = d.RemoteSetup
	local liveFn = RemoteSetup.Get(Constants.RemoteNames.RequestMapLive) :: RemoteFunction
	liveFn.OnServerInvoke = function(player: Player): any
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestMapLive") then
			return nil
		end
		if d.RateLimitService and not d.RateLimitService.Allow(player, "map_live", 4, 6) then
			return nil
		end
		return MapService.Live(player)
	end
	local travelFn = RemoteSetup.Get(Constants.RemoteNames.RequestFastTravel) :: RemoteFunction
	travelFn.OnServerInvoke = function(player: Player, target: any): any
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestFastTravel", target) then
			return { Ok = false, Reason = "Rate" }
		end
		if d.RateLimitService and not d.RateLimitService.Allow(player, "fast_travel", 1, 2) then
			return { Ok = false, Reason = "Rate" }
		end
		local ok, reason = MapService.FastTravel(player, target)
		if ok and d.AnalyticsService then
			pcall(d.AnalyticsService.Log, "FAST_TRAVEL", player.UserId, { target = target })
		end
		return { Ok = ok, Reason = reason }
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		lastTravelAt[p.UserId] = nil
	end)
	print(string.format("[WAR EMPIRE] MapService Init: map=%s fastTravel=%s", tostring(MapConfig.Enabled), tostring(MapConfig.FastTravel.Enabled)))
end

return MapService
