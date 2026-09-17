--!strict
--[[
	Phase 5 — Territory control.
	Server-authoritative stand-in-zone capture; bonuses for Economy / XP / Vehicles / Combat.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

type TerritoryDef = TerritoryConfig.TerritoryDef

type TerritoryRuntime = {
	Id: string,
	Def: TerritoryDef,
	OwnerType: string,
	OwnerUserId: number, -- 0 neutral, -1 NPC, else player
	ClanId: string?,
	Progress: number, -- seconds accumulated toward capture
	CapturingUserId: number, -- 0 if none
	ProtectedUntil: number, -- unix
	Contested: boolean,
	Marker: BasePart?,
}

local TerritoryService = {}

local DataService: any = nil
local EconomyService: any = nil
local XPService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local NotificationService: any = nil
local MissionService: any = nil
local TutorialService: any = nil
local RemoteSetup: any = nil
local BaseService: any = nil

local territories: { [string]: TerritoryRuntime } = {}
local firstOutpostLogged: { [number]: boolean } = {}
local lastPushAt = 0

local function ownerTypes()
	return TerritoryConfig.OwnerTypes
end

local function nowUnix(): number
	return os.time()
end

local function findMarker(territoryId: string): BasePart?
	-- Prefer dedicated capture zones
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.CaptureZone)) do
		if inst:IsA("BasePart") and inst:GetAttribute("TerritoryId") == territoryId then
			return inst
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.Territory)) do
		if inst:IsA("BasePart") and (inst:GetAttribute("TerritoryId") == territoryId or inst.Name == territoryId) then
			return inst
		end
	end
	return nil
end

local function ensureRuntime()
	for id, def in pairs(TerritoryConfig.Territories) do
		if not territories[id] then
			territories[id] = {
				Id = id,
				Def = def,
				OwnerType = ownerTypes().Neutral,
				OwnerUserId = TerritoryConfig.NeutralOwnerId,
				ClanId = nil,
				Progress = 0,
				CapturingUserId = 0,
				ProtectedUntil = 0,
				Contested = false,
				Marker = findMarker(id),
			}
		elseif not territories[id].Marker or not territories[id].Marker.Parent then
			territories[id].Marker = findMarker(id)
		end
	end
end

local function countPersonalTerritories(userId: number): number
	local n = 0
	for _, rt in pairs(territories) do
		if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == userId then
			n += 1
		end
	end
	return n
end

local function syncProfileOwnership(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	if typeof(profile.Territories) ~= "table" then
		profile.Territories = {}
	end
	-- Clear then re-apply owned
	for id in pairs(profile.Territories) do
		profile.Territories[id] = nil
	end
	for id, rt in pairs(territories) do
		if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == player.UserId then
			profile.Territories[id] = true
		end
	end
	DataService.MarkDirty(player)
end

local function updateMarkerVisual(rt: TerritoryRuntime)
	local marker = rt.Marker
	if not marker then
		return
	end
	local ot = ownerTypes()
	if rt.Contested or rt.OwnerType == ot.Contested then
		marker.Color = Color3.fromRGB(220, 120, 40)
	elseif rt.OwnerType == ot.Player then
		marker.Color = Color3.fromRGB(70, 160, 90)
	elseif rt.OwnerType == ot.NPC then
		marker.Color = Color3.fromRGB(160, 60, 60)
	elseif rt.OwnerType == ot.Clan then
		marker.Color = Color3.fromRGB(90, 110, 200)
	else
		marker.Color = rt.Def.Color
	end
	marker:SetAttribute("OwnerType", rt.OwnerType)
	marker:SetAttribute("OwnerUserId", rt.OwnerUserId)
	marker:SetAttribute("CaptureProgress", rt.Progress / math.max(1, rt.Def.CaptureTimeSeconds))
end

local function buildPayloadForPlayer(player: Player?): Types.TerritoryStatePayload
	local list: { Types.TerritoryEntryPayload } = {}
	local localCapture = {
		TerritoryId = nil :: string?,
		Progress = 0,
		Capturing = false,
	}

	for _, rt in pairs(territories) do
		table.insert(list, {
			Id = rt.Id,
			DisplayName = rt.Def.DisplayName,
			OwnerType = if rt.Contested then ownerTypes().Contested else rt.OwnerType,
			OwnerUserId = rt.OwnerUserId,
			ClanId = rt.ClanId,
			Progress = math.clamp(rt.Progress / math.max(1, rt.Def.CaptureTimeSeconds), 0, 1),
			CapturingUserId = rt.CapturingUserId,
			ProtectedUntil = rt.ProtectedUntil,
			BonusType = rt.Def.BonusType,
			BonusValue = rt.Def.BonusValue,
			Contested = rt.Contested,
		})
		if player and rt.CapturingUserId == player.UserId and rt.Progress > 0 then
			localCapture.TerritoryId = rt.Id
			localCapture.Progress = math.clamp(rt.Progress / math.max(1, rt.Def.CaptureTimeSeconds), 0, 1)
			localCapture.Capturing = true
		end
	end

	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)

	return {
		Territories = list,
		LocalCapture = localCapture,
	}
end

function TerritoryService.PushAll()
	ensureRuntime()
	local remote = RemoteSetup.Get(Constants.RemoteNames.TerritoryStateUpdate) :: RemoteEvent
	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, buildPayloadForPlayer(player))
	end
	lastPushAt = os.clock()
end

function TerritoryService.PushPlayer(player: Player)
	ensureRuntime()
	local remote = RemoteSetup.Get(Constants.RemoteNames.TerritoryStateUpdate) :: RemoteEvent
	remote:FireClient(player, buildPayloadForPlayer(player))
end

function TerritoryService.GetController(territoryId: string): number?
	local rt = territories[territoryId]
	if not rt then
		return nil
	end
	if rt.OwnerType == ownerTypes().Neutral or rt.OwnerType == ownerTypes().Contested then
		return nil
	end
	return rt.OwnerUserId
end

function TerritoryService.GetRuntime(territoryId: string): TerritoryRuntime?
	return territories[territoryId]
end

--[[ Aggregate bonus values for territories controlled by this player (or their clan). ]]
function TerritoryService.GetBonusesForPlayer(player: Player): { [string]: number }
	local bonuses: { [string]: number } = {}
	local profile = DataService and DataService.GetProfile(player)
	local clanId = if profile then profile.ClanId else nil

	for _, rt in pairs(territories) do
		local owns = false
		if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == player.UserId then
			owns = true
		elseif rt.OwnerType == ownerTypes().Clan and clanId and rt.ClanId == clanId then
			owns = true
		end
		if owns then
			-- Flat and multiplicative bonuses both accumulate additively into the map;
			-- consumers interpret FlatPassiveCash/MinimapReveal as flat, *Mult as fractions.
			local key = rt.Def.BonusType
			local value = rt.Def.BonusValue
			bonuses[key] = (bonuses[key] or 0) + value
		end
	end
	return bonuses
end

function TerritoryService.GetPassiveCashBonus(player: Player): (number, number)
	-- returns (multiplierAdd, flatAdd) e.g. 0.10, 50
	local b = TerritoryService.GetBonusesForPlayer(player)
	return b.PassiveCashMult or 0, b.FlatPassiveCash or 0
end

function TerritoryService.GetXPMult(player: Player): number
	local b = TerritoryService.GetBonusesForPlayer(player)
	return 1 + (b.XPMult or 0)
end

function TerritoryService.GetDamageMult(player: Player): number
	local b = TerritoryService.GetBonusesForPlayer(player)
	return 1 + (b.DamageMult or 0)
end

function TerritoryService.GetVehicleCooldownMult(player: Player): number
	local b = TerritoryService.GetBonusesForPlayer(player)
	-- BonusValue for WestDepot is -0.20 → cooldown * 0.80
	return 1 + (b.VehicleCooldownMult or 0)
end

function TerritoryService.GetMissionCashMult(player: Player): number
	local b = TerritoryService.GetBonusesForPlayer(player)
	return 1 + (b.MissionCashMult or 0)
end

local function releaseOwnership(rt: TerritoryRuntime, reason: string)
	local prevUserId = rt.OwnerUserId
	local prevType = rt.OwnerType
	rt.OwnerType = ownerTypes().Neutral
	rt.OwnerUserId = TerritoryConfig.NeutralOwnerId
	rt.ClanId = nil
	rt.ProtectedUntil = 0

	if prevType == ownerTypes().Player and prevUserId > 0 then
		local prevPlayer = Players:GetPlayerByUserId(prevUserId)
		if prevPlayer then
			syncProfileOwnership(prevPlayer)
			if NotificationService then
				NotificationService.Notify(prevPlayer, "Lost control of " .. rt.Def.DisplayName, "Warn")
			end
			if AnalyticsService then
				AnalyticsService.Log(AnalyticsConfig.Events.TERRITORY_LOST, prevUserId, {
					territory = rt.Id,
					reason = reason,
				})
			end
			if BaseService then
				BaseService.PushState(prevPlayer)
			end
		end
	end
end

local function awardCapture(player: Player, rt: TerritoryRuntime)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end

	-- Enforce max personal territories (balancing stub)
	local owned = countPersonalTerritories(player.UserId)
	-- If already owning this one (re-secure), skip max check
	local alreadyOwns = rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == player.UserId
	if not alreadyOwns and owned >= TerritoryConfig.MaxPersonalTerritories then
		-- Drop oldest unprotected personal territory
		local oldest: TerritoryRuntime? = nil
		local oldestTime = math.huge
		for _, other in pairs(territories) do
			if other.Id ~= rt.Id and other.OwnerType == ownerTypes().Player and other.OwnerUserId == player.UserId then
				if other.ProtectedUntil < oldestTime then
					oldestTime = other.ProtectedUntil
					oldest = other
				end
			end
		end
		if oldest then
			releaseOwnership(oldest, "max_personal")
			updateMarkerVisual(oldest)
		end
	end

	-- Previous owner loses it
	if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId ~= player.UserId and rt.OwnerUserId > 0 then
		releaseOwnership(rt, "captured")
	end

	rt.OwnerType = ownerTypes().Player
	rt.OwnerUserId = player.UserId
	rt.ClanId = profile.ClanId
	rt.Progress = 0
	rt.CapturingUserId = 0
	rt.Contested = false
	rt.ProtectedUntil = nowUnix() + TerritoryConfig.ProtectionPeriodSeconds

	profile.Stats.TerritoriesCaptured += 1
	syncProfileOwnership(player)

	if NotificationService then
		NotificationService.Notify(player, "Captured " .. rt.Def.DisplayName .. "!", "Reward")
	end

	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.TERRITORY_CAPTURED, player.UserId, {
			territory = rt.Id,
			total = profile.Stats.TerritoriesCaptured,
		})
		if profile.Stats.TerritoriesCaptured == 1 and not firstOutpostLogged[player.UserId] then
			firstOutpostLogged[player.UserId] = true
			AnalyticsService.Log(AnalyticsConfig.Events.FIRST_OUTPOST, player.UserId, { territory = rt.Id })
		end
	end

	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(player, "CaptureTerritory", 1)
	end
	if TutorialService and TutorialService.Notify then
		TutorialService.Notify(player, "CaptureTerritory", rt.Id)
	end

	if BaseService then
		BaseService.PushState(player)
	end

	updateMarkerVisual(rt)
end

local function playersInZone(rt: TerritoryRuntime): { Player }
	local found: { Player } = {}
	local marker = rt.Marker
	local center = if marker then marker.Position else rt.Def.Position
	local radius = rt.Def.Radius
	if marker then
		-- Use larger of config radius and half diagonal of part
		local half = marker.Size.Magnitude * 0.5
		radius = math.max(radius, half)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
			if flat.Magnitude <= radius then
				table.insert(found, player)
			end
		end
	end
	return found
end

local function tickTerritory(rt: TerritoryRuntime, dt: number)
	local inside = playersInZone(rt)
	local ot = ownerTypes()

	if #inside == 0 then
		rt.Contested = false
		if rt.Progress > 0 then
			rt.Progress = math.max(0, rt.Progress - TerritoryConfig.ProgressDecayPerSecond * dt)
		end
		if rt.Progress <= 0 then
			rt.CapturingUserId = 0
		end
		updateMarkerVisual(rt)
		return
	end

	-- Contested if 2+ distinct players and not all already the owner
	local unique: { [number]: boolean } = {}
	for _, p in ipairs(inside) do
		unique[p.UserId] = true
	end
	local uniqueCount = 0
	for _ in pairs(unique) do
		uniqueCount += 1
	end

	if uniqueCount >= 2 then
		rt.Contested = true
		rt.OwnerType = if rt.OwnerUserId == TerritoryConfig.NeutralOwnerId then ot.Contested else rt.OwnerType
		-- Contested: no capture progress (stub mult)
		local mult = TerritoryConfig.ContestedProgressMult
		if mult <= 0 then
			-- slight decay while contested
			rt.Progress = math.max(0, rt.Progress - TerritoryConfig.ProgressDecayPerSecond * 0.5 * dt)
		end
		updateMarkerVisual(rt)
		return
	end

	rt.Contested = false
	local capturer = inside[1]
	-- If capturer already owns it, just refresh presence (no progress needed)
	if rt.OwnerType == ot.Player and rt.OwnerUserId == capturer.UserId then
		rt.CapturingUserId = 0
		rt.Progress = 0
		updateMarkerVisual(rt)
		return
	end

	-- Protection period hook: slower capture while protected
	local rate = 1
	if rt.ProtectedUntil > nowUnix() and rt.OwnerUserId ~= TerritoryConfig.NeutralOwnerId then
		rate = TerritoryConfig.ProtectedCaptureMult
	end

	rt.CapturingUserId = capturer.UserId
	rt.Progress += dt * rate

	if rt.Progress >= rt.Def.CaptureTimeSeconds then
		awardCapture(capturer, rt)
	else
		updateMarkerVisual(rt)
	end
end

--[[
	Optional explicit request — mainly for UI "begin capture" ping; actual progress is proximity-based.
]]
function TerritoryService.BeginCapture(player: Player, territoryId: any): (boolean, string?)
	if typeof(territoryId) ~= "string" then
		return false, "InvalidTerritory"
	end
	ensureRuntime()
	local rt = territories[territoryId]
	if not rt then
		return false, "UnknownTerritory"
	end
	local inside = playersInZone(rt)
	local present = false
	for _, p in ipairs(inside) do
		if p == player then
			present = true
			break
		end
	end
	if not present then
		if NotificationService then
			NotificationService.Notify(player, "Enter the capture zone first.", "Warn")
		end
		return false, "NotInZone"
	end
	if NotificationService then
		NotificationService.Notify(player, "Capturing " .. rt.Def.DisplayName .. "...", "Info")
	end
	TerritoryService.PushPlayer(player)
	return true, nil
end

--[[ Seed a few territories as NPC-held for contested feel (Studio / empty servers). ]]
local function seedNpcOwners()
	local npcHeld = { "EastArmory", "RadarHill" }
	for _, id in ipairs(npcHeld) do
		local rt = territories[id]
		if rt and rt.OwnerType == ownerTypes().Neutral then
			rt.OwnerType = ownerTypes().NPC
			rt.OwnerUserId = TerritoryConfig.NPCOwnerId
			rt.ProtectedUntil = nowUnix() + 30
			updateMarkerVisual(rt)
		end
	end
end

function TerritoryService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	NotificationService = deps.NotificationService
	MissionService = deps.MissionService
	TutorialService = deps.TutorialService
	RemoteSetup = deps.RemoteSetup
	BaseService = deps.BaseService

	ensureRuntime()
	seedNpcOwners()

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestCaptureTerritory) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, territoryId: any)
		if not RateLimitService.Allow(player, "capture_territory", 1, 2) then
			return
		end
		TerritoryService.BeginCapture(player, territoryId)
	end)

	-- Late marker discovery (StudioSetup may run after Bootstrap)
	task.spawn(function()
		for _ = 1, 20 do
			task.wait(1)
			ensureRuntime()
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, _profile: Types.PlayerProfile)
		syncProfileOwnership(player)
		TerritoryService.PushPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Soft-release: keep world ownership so others can contest; clear profile sync only
		firstOutpostLogged[player.UserId] = nil
	end)

	-- Capture loop
	task.spawn(function()
		local tickSec = TerritoryConfig.CaptureTickSeconds or 0.5
		while true do
			local dt = tickSec
			task.wait(dt)
			ensureRuntime()
			for _, rt in pairs(territories) do
				tickTerritory(rt, dt)
			end
			-- Throttle full pushes
			if os.clock() - lastPushAt >= 0.75 then
				TerritoryService.PushAll()
			end
		end
	end)

	if RunService:IsStudio() then
		print("[TerritoryService] Initialized", (function()
			local n = 0
			for _ in pairs(TerritoryConfig.Territories) do
				n += 1
			end
			return n
		end)(), "territories")
	end
end

return TerritoryService
