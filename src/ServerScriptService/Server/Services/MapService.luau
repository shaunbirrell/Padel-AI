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
	  }
	  Plot owners are server-only; the names use BaseSignService.TitleFor, the same string as the base sign.
	  The shared part is rebuilt at most every RefreshSeconds (one CollectionService read of ~20 zones and <= 3
	  drops), whatever the number of players; only the Mine flags are per player.
	Code Bot v127: fast travel was REMOVED at the owner's request (no remote, no handler, no button). Do not re-add it.
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

local MapService = {}

local deps: { [string]: any } = {}

local JOB_KEYS = { "Checkpoint", "Camp", "Uplink", "Cargo" } -- MissionConfig.Go kinds shown (Job / Hostiles repeat them)
local MAX_JOBS = 30

local function live(userId: number): boolean
	return RetentionConfig.Live(MapConfig, userId)
end

-- ── the shared snapshot (rebuilt at most every RefreshSeconds) ────────────────────────────────────────────────────
type Shared = { At: number, Bases: { any }, Outposts: { any }, Drops: { any }, Jobs: { any }, Sites: { any } }
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
	-- claude-bud JOB 31: the named sites (their real, placed positions: Modules/WorldSites)
	local sites = {}
	local okW, WS = pcall(function(): any
		return require(script.Parent.Parent.Modules.WorldSites)
	end)
	if okW and WS and WS.List then
		for _, st in ipairs(WS.List()) do
			table.insert(sites, { Id = st.Id, N = st.Name, K = st.Kind, X = math.floor(st.X), Z = math.floor(st.Z), R = st.R })
		end
	end
	local fresh: Shared = { At = now, Bases = bases, Outposts = outposts, Drops = drops, Jobs = jobs, Sites = sites }
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

-- claude-bud JOB 38: the armies marching on this player's base (ArmyPlan; the defender always sees them)
local function incomingRows(player: Player): { any }?
	local okP, AP = pcall(function(): any
		return require(script.Parent.Parent.Modules.ArmyPlan)
	end)
	if not okP or AP == nil or AP.IncomingFor == nil then
		return nil
	end
	local ok, list = pcall(AP.IncomingFor, player.UserId)
	return if ok then list else nil
end

-- claude-bud JOB 37: the road checkpoints for this player (CheckpointGuardService; nil when not live)
local function checkpointRows(player: Player): { any }?
	local okC, CG = pcall(function(): any
		return require(script.Parent.CheckpointGuardService)
	end)
	if not okC or CG == nil or CG.MapList == nil then
		return nil
	end
	local ok, list = pcall(CG.MapList, player)
	return if ok then list else nil
end

-- claude-bud JOB 50 C: HIS built rebirth zones (RebirthZoneService.MapRows; nil when not live)
local function zoneRows(player: Player): { any }?
	local okZ, RZ = pcall(function(): any
		return require(script.Parent.RebirthZoneService)
	end)
	if not okZ or RZ == nil or RZ.MapRows == nil then
		return nil
	end
	local ok, list = pcall(RZ.MapRows, player)
	return if ok then list else nil
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
		Sites = s.Sites, -- claude-bud JOB 31
		Checkpoints = checkpointRows(player), -- claude-bud JOB 37: hostile / cleared + respawn countdown (live players only)
		Zones = zoneRows(player), -- claude-bud JOB 50 C: his rebirth zones (tap = pin)
		Incoming = incomingRows(player), -- claude-bud JOB 38: armies marching on / sieging his base (always shown to him)
		Bank = { X = math.floor(BankRaidConfig.Position.X), Z = math.floor(BankRaidConfig.Position.Z) },
	}
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
	print(string.format("[WAR EMPIRE] MapService Init: map=%s pinOnly=v127", tostring(MapConfig.Enabled)))
end

return MapService
