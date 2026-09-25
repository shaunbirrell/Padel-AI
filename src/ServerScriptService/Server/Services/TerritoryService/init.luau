--!strict
--[[
	Phase 5 — Territory control.
	Server-authoritative stand-in-zone capture; bonuses for Economy / XP / Vehicles / Combat.

	v71 (HUD v70 spec §5, roadmap W1 F): the capture marker and ring only take the owner colour (no forced Neon,
	no transparency / size writes — World v2 owns their look); the flag is painted (SmoothPlastic) and sits at
	basePos.Y + flagLift − 1 (oil-rig decks too); the zone label is one stud-scaled WorldLabel with the zone name
	in the owner colour (capture % and "contested" live on the HUD capture bar); the WE_FlagBillboard diamond is
	28 px and draws through walls only while contested (WorldLabel.SetRole). No "Capturing X..." toast.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local WorldLabel = require(Shared.Util.WorldLabel)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local TerritoryRadar = require(script.TerritoryRadar)
local TerritoryOwnership = require(script.TerritoryOwnership)
local TerritoryCapture = require(script.TerritoryCapture)

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
	-- v38: up to two contester UserIds for dual nation-color pulse
	ContesterA: number?,
	ContesterB: number?,
	Marker: BasePart?,
}

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local TerritoryService = {}

local ClanWarService: any = nil

local DataService: any = nil
local _EconomyService: any = nil
local _XPService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local NotificationService: any = nil
local MissionService: any = nil
local TutorialService: any = nil
local RemoteSetup: any = nil
local BaseService: any = nil
local NationColorService: any = nil

local territories: { [string]: TerritoryRuntime } = {}
local firstOutpostLogged: { [number]: boolean } = {}
local lastPushAt = 0
local pushDirty = true

local function ownerTypes()
	return TerritoryConfig.OwnerTypes
end

local function nowUnix(): number
	return os.time()
end

local function findMarker(territoryId: string): BasePart?
	return TerritoryRadar.FindMarker(territoryId)
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

-- Zone label: the zone name only, in the owner colour (spec §5). MapSetup's old "Label" card (name + [NEUTRAL] ·
-- Stand to capture, 220 studs) is replaced by this one stud-scaled WorldLabel above the flag pole.
local ZONE_LABEL_HEIGHT = 16 -- studs above the marker centre (the pole is 14 tall)

local function ensureZoneLabel(rt: TerritoryRuntime, marker: BasePart): BillboardGui
	local existing = marker:FindFirstChild("WE_ZoneLabel")
	if existing and existing:IsA("BillboardGui") then
		return existing
	end
	local legacy = marker:FindFirstChild("Label")
	if legacy and legacy:IsA("BillboardGui") then
		legacy:Destroy()
	end
	return WorldLabel.Create(marker, rt.Def.DisplayName, {
		Name = "WE_ZoneLabel",
		Studs = Vector2.new(8, 1.6),
		Offset = Vector3.new(0, ZONE_LABEL_HEIGHT, 0),
		MaxDistance = 40,
	})
end

local function updateMarkerVisual(rt: TerritoryRuntime)
	local marker = rt.Marker
	if not marker then
		return
	end
	local ot = ownerTypes()
	local contested = rt.Contested or rt.OwnerType == ot.Contested
	local color: Color3
	local flagTransparency = 0.15
	local flagLift = 12 -- studs above the marker for the flag centre (+ basePos.Y − 1 below)

	if contested then
		-- v38: pulse between both nation colors when two contesting players known
		local ca = rt.ContesterA or 0
		local cb = rt.ContesterB or 0
		local colA = if ca > 0 and NationColorService and NationColorService.GetColor then NationColorService.GetColor(ca) else nil
		local colB = if cb > 0 and NationColorService and NationColorService.GetColor then NationColorService.GetColor(cb) else nil
		if colA and colB then
			local pulse = (math.sin(os.clock() * 4) + 1) * 0.5
			color = colA:Lerp(colB, pulse)
		elseif colA then
			local pulse = (math.sin(os.clock() * 5) + 1) * 0.5
			color = colA:Lerp(Color3.fromRGB(255, 140, 35), pulse)
		else
			color = Color3.fromRGB(255, 140, 35)
		end
		flagTransparency = 0.05
		flagLift = 13.5
	elseif rt.OwnerType == ot.Player then
		local nation = if NationColorService and NationColorService.GetColor then NationColorService.GetColor(rt.OwnerUserId) else nil
		color = nation or Color3.fromRGB(55, 210, 95)
		flagTransparency = 0.0
		flagLift = 14.5
	elseif rt.OwnerType == ot.NPC then
		color = Color3.fromRGB(210, 45, 45)
		flagTransparency = 0.05
		flagLift = 13.2
	elseif rt.OwnerType == ot.Clan then
		color = Color3.fromRGB(70, 120, 240)
		flagTransparency = 0.0
		flagLift = 14.0
	else
		color = rt.Def.Color
		flagTransparency = 0.35
		flagLift = 11.0
	end

	-- v71: colour only (no forced Neon / transparency: World v2 decides how the marker looks)
	if marker.Color ~= color then
		marker.Color = color
	end
	marker:SetAttribute("OwnerType", if contested then ot.Contested else rt.OwnerType)
	marker:SetAttribute("OwnerUserId", rt.OwnerUserId)
	marker:SetAttribute("CaptureProgress", rt.Progress / math.max(1, rt.Def.CaptureTimeSeconds))

	local tid = marker:GetAttribute("TerritoryId")
	if typeof(tid) ~= "string" then
		return
	end
	local parent = marker.Parent
	if not parent then
		return
	end

	local flag = parent:FindFirstChild(tid .. "_Flag")
	if flag and flag:IsA("BasePart") then
		flag.Color = color
		flag.Material = Enum.Material.SmoothPlastic -- v71: painted, not neon (not a light source)
		flag.Transparency = flagTransparency
		-- Raise owned flags; lower neutral so ownership reads at a glance. Height from the marker, so a flag on
		-- an oil-rig deck (marker high above the sea) stays on its pole instead of dropping to y ≈ 12.
		local basePos = marker.Position
		flag.Size = if contested then Vector3.new(6.2, 3.6, 0.3) elseif rt.OwnerType == ot.Neutral then Vector3.new(4.2, 2.4, 0.22) else Vector3.new(5.5, 3.2, 0.28)
		flag.Position = Vector3.new(basePos.X + flag.Size.X * 0.5 + 0.2, basePos.Y + flagLift - 1, basePos.Z)
		-- W3 step 2 (spec w3s2 §1.11, lane P): no owner light on the flag any more. It broke the world light policy
		-- (Brightness 2.4-3.2 and Range 28 > 0.8 / 18, one per zone); the painted flag, stripe and diamond show the owner.
		-- A leftover one (a place saved with an older build's flag) is removed.
		local oldLight = flag:FindFirstChild("WE_OwnerLight")
		if oldLight then
			oldLight:Destroy()
		end

		-- Keep stripe locked to flag (nation color visibility polish)
		local stripe = parent:FindFirstChild(tid .. "_FlagStripe")
		if stripe and stripe:IsA("BasePart") then
			stripe.Size = Vector3.new(flag.Size.X, math.max(0.35, flag.Size.Y * 0.14), flag.Size.Z + 0.06)
			stripe.Position = flag.Position
			stripe.Color = Color3.fromRGB(245, 245, 245)
			stripe.Transparency = if rt.OwnerType == ot.Neutral then 0.45 else 0.08
		end

		-- Nation-colour diamond over the flag: 28 px, MaxDistance <= 40, through walls ONLY while contested
		-- (WorldLabel.SetRole "contested"; WorldLabelPolicy honours the role). Range is set once, never per refresh.
		local flagBbInst = flag:FindFirstChild("WE_FlagBillboard")
		local flagBb: BillboardGui
		if flagBbInst and flagBbInst:IsA("BillboardGui") and flagBbInst:GetAttribute("WE_V71") == true then
			flagBb = flagBbInst
		else
			if flagBbInst then
				flagBbInst:Destroy()
			end
			local created = Instance.new("BillboardGui")
			created.Name = "WE_FlagBillboard"
			created.Size = UDim2.fromOffset(28, 28)
			created.StudsOffset = Vector3.new(0, 2.2, 0)
			created.AlwaysOnTop = false
			created.LightInfluence = 0
			created.MaxDistance = 40
			created:SetAttribute("WE_V71", true)
			local diamond = Instance.new("Frame")
			diamond.Name = "NationDiamond"
			diamond.AnchorPoint = Vector2.new(0.5, 0.5)
			diamond.Position = UDim2.fromScale(0.5, 0.5)
			diamond.Size = UDim2.fromScale(0.62, 0.62)
			diamond.Rotation = 45
			diamond.BorderSizePixel = 0
			diamond.Parent = created
			local ds = Instance.new("UIStroke")
			ds.Name = "DiamondStroke"
			ds.Thickness = 2
			ds.Color = Color3.fromRGB(255, 255, 255)
			ds.Parent = diamond
			created.Parent = flag
			flagBb = created
		end
		local showFlag = rt.OwnerType ~= ot.Neutral or contested
		if flagBb.Enabled ~= showFlag then
			flagBb.Enabled = showFlag
		end
		WorldLabel.SetRole(flagBb, if contested then "contested" else nil)
		local diamond = flagBb:FindFirstChild("NationDiamond")
		if diamond and diamond:IsA("Frame") then
			diamond.BackgroundColor3 = color
			local ds = diamond:FindFirstChild("DiamondStroke")
			if ds and ds:IsA("UIStroke") then
				ds.Color = if contested then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(255, 255, 255)
			end
		end
	end

	-- v71: the ring writes colour only (roadmap W1 F; no Neon while contested, no size / transparency churn)
	local ring = parent:FindFirstChild(tid .. "_Ring")
	if ring and ring:IsA("BasePart") and ring.Color ~= color then
		ring.Color = color
	end

	local pole = parent:FindFirstChild(tid .. "_FlagPole")
	if pole and pole:IsA("BasePart") then
		pole.Color = if contested then Color3.fromRGB(180, 90, 30) elseif rt.OwnerType == ot.Neutral then Color3.fromRGB(55, 55, 55) else Color3.fromRGB(40, 45, 40)
	end

	-- Zone label: name only, owner colour (neutral = white); % / contested are on the HUD capture bar
	local zoneLabel = ensureZoneLabel(rt, marker)
	local title = zoneLabel:FindFirstChild("Title")
	local nameColor = if contested then Color3.fromRGB(255, 176, 48) elseif rt.OwnerType == ot.Neutral then Color3.new(1, 1, 1) else color
	if title and title:IsA("TextLabel") and title.TextColor3 ~= nameColor then
		title.TextColor3 = nameColor
	end
end

local function buildPayloadForPlayer(player: Player?): Types.TerritoryStatePayload
	local list: { Types.TerritoryEntryPayload } = {}
	local localCapture = {
		TerritoryId = nil :: string?,
		Progress = 0,
		Capturing = false,
		Contested = false,
		Protected = false,
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
			localCapture.Contested = rt.Contested == true
			localCapture.Protected = rt.ProtectedUntil > nowUnix()
				and rt.OwnerUserId ~= TerritoryConfig.NeutralOwnerId
				and rt.OwnerUserId ~= player.UserId
			-- v38: dual nation colors for contested pulse HUD
			if rt.Contested then
				local function packColor(uid: number?): { number }?
					if not uid or uid <= 0 then
						return nil
					end
					local c = if NationColorService and NationColorService.GetColor then NationColorService.GetColor(uid) else nil
					if not c then
						return nil
					end
					return { c.R, c.G, c.B }
				end
				;(localCapture :: any).ContesterColorA = packColor(rt.ContesterA)
				;(localCapture :: any).ContesterColorB = packColor(rt.ContesterB)
			end
		end
	end

	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)

	local radar = false
	local radarRadius = TerritoryConfig.RadarRevealRadius or 220
	if player then
		radar = TerritoryService.HasRadarReveal(player)
	end

	return {
		Territories = list,
		LocalCapture = localCapture,
		RadarReveal = radar,
		RadarRadius = radarRadius,
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
		local owns = (rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == player.UserId)
			or (rt.OwnerType == ownerTypes().Clan and clanId ~= nil and rt.ClanId == clanId)
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

--[[ True when player (or their clan) controls a MinimapReveal territory (Radar Hill). ]]
function TerritoryService.HasRadarReveal(player: Player): boolean
	return TerritoryOwnership.HasRadar(player)
end

function TerritoryService.GetRadarRevealRadius(): number
	return TerritoryConfig.RadarRevealRadius or 220
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
			-- Contested: recount OutpostIncomeStacks from remaining owned zones
			if _EconomyService and _EconomyService.SyncOutpostIncomeStacks then
				_EconomyService.SyncOutpostIncomeStacks(prevPlayer)
			end
			if NotificationService then
				local zoneName = if rt.Def and rt.Def.DisplayName then rt.Def.DisplayName else "Outpost"
				local lostToast = string.format("Outpost lost: %s stolen — Income buff dropped", zoneName)
				pcall(function()
					local buff = require(Shared.Configs.EconomyConfig).OutpostIncomeBuff
					if buff and typeof(buff.ToastStolenFromYou) == "string" then
						lostToast = string.format(buff.ToastStolenFromYou, zoneName)
					elseif buff and typeof(buff.ToastLost) == "string" then
						lostToast = buff.ToastLost
					end
				end)
				NotificationService.Notify(prevPlayer, lostToast, "Warn", 4.5)
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

	-- Enforce max personal territories
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

	-- Previous owner loses it (v33: mark steal for toast clarity)
	local stoleFromPlayer = false
	if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId ~= player.UserId and rt.OwnerUserId > 0 then
		stoleFromPlayer = true
		releaseOwnership(rt, "captured")
	end

	rt.OwnerType = ownerTypes().Player
	rt.OwnerUserId = player.UserId
	rt.ClanId = profile.ClanId
	if ClanWarService and ClanWarService.OnTerritoryCaptured then
		ClanWarService.OnTerritoryCaptured(player)
	end
	rt.Progress = 0
	rt.CapturingUserId = 0
	rt.Contested = false
	rt.ContesterA = nil
	rt.ContesterB = nil
	rt.ProtectedUntil = nowUnix() + TerritoryConfig.ProtectionPeriodSeconds

	profile.Stats.TerritoriesCaptured += 1
	syncProfileOwnership(player)

	-- Contested income buff: recount stacks from owned zones (stealable by re-capture)
	local incomeToastShown = false
	local incomePct = 0
	if _EconomyService and _EconomyService.SyncOutpostIncomeStacks then
		local oldStacks, newStacks, pct = _EconomyService.SyncOutpostIncomeStacks(player)
		if newStacks > oldStacks and pct > 0 then
			incomePct = pct
			incomeToastShown = true
		end
	elseif _EconomyService and _EconomyService.GrantOutpostIncomeStack then
		local granted, _stacks, pct = _EconomyService.GrantOutpostIncomeStack(player)
		if granted and pct > 0 then
			incomePct = pct
			incomeToastShown = true
		end
	end

	if NotificationService then
		local zoneName = rt.Def.DisplayName
		local wasSteal = stoleFromPlayer
		if incomeToastShown then
			-- v33: explicit who gets the +income
			local stealTpl = nil
			pcall(function()
				local buff = require(Shared.Configs.EconomyConfig).OutpostIncomeBuff
				if buff then
					stealTpl = buff.ToastStealGain
				end
			end)
			local msg
			if wasSteal and typeof(stealTpl) == "string" then
				msg = string.format(stealTpl, zoneName, incomePct)
			else
				msg = string.format("★ SECURED %s — +%d%% Income (yours)", zoneName, incomePct)
			end
			NotificationService.Notify(player, msg, "Reward", 5)
		else
			local bonusHint = rt.Def.Description or ""
			if #bonusHint > 60 then
				bonusHint = string.sub(bonusHint, 1, 57) .. "..."
			end
			NotificationService.Notify(
				player,
				string.format("★ SECURED %s! %s", zoneName, bonusHint),
				"Reward",
				5
			)
		end
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
	return TerritoryCapture.PlayersInZone(rt)
end

local function tickTerritory(rt: TerritoryRuntime, dt: number)
	local inside = playersInZone(rt)
	local ot = ownerTypes()

	if #inside == 0 then
		rt.Contested = false
		rt.ContesterA = nil
		rt.ContesterB = nil
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
		-- v38: remember first two contesting players for dual-color pulse
		do
			local ids: { number } = {}
			for uid in pairs(unique) do
				table.insert(ids, uid)
			end
			table.sort(ids)
			rt.ContesterA = ids[1]
			rt.ContesterB = ids[2]
		end
		rt.OwnerType = if rt.OwnerUserId == TerritoryConfig.NeutralOwnerId then ot.Contested else rt.OwnerType
		-- Contested: ContestedProgressMult scales capture; 0 freezes and applies ContestedDecayMult decay
		local mult = TerritoryConfig.ContestedProgressMult
		if mult <= 0 then
			local decayMult = TerritoryConfig.ContestedDecayMult or 0.5
			rt.Progress = math.max(0, rt.Progress - TerritoryConfig.ProgressDecayPerSecond * decayMult * dt)
		else
			-- Rare path: allow slow contested progress for both (not used at default 0)
			rt.Progress += dt * mult
		end
		updateMarkerVisual(rt)
		return
	end

	rt.Contested = false
	rt.ContesterA = nil
	rt.ContesterB = nil
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
	if not RemoteGuard.IsIdString(territoryId, 48) then
		return false, "InvalidTerritory"
	end
	if not RemoteGuard.RequireProfile(DataService, player) then
		return false, "NoProfile"
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
	-- (no "Capturing X..." toast per request: the HUD capture bar shows it — spec §4.2)
	TerritoryService.PushPlayer(player)
	return true, nil
end

--[[ Seed a few territories as NPC-held for contested feel (Studio / empty servers). ]]
local function seedNpcOwners()
	local npcHeld = { "EastArmory", "RadarHill", "CoastalOilAlpha", "CoastalOilBravo" }
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
	ClanWarService = deps.ClanWarService
	DataService = deps.DataService
	_EconomyService = deps.EconomyService
	_XPService = deps.XPService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	NotificationService = deps.NotificationService
	MissionService = deps.MissionService
	TutorialService = deps.TutorialService
	RemoteSetup = deps.RemoteSetup
	BaseService = deps.BaseService
	NationColorService = deps.NationColorService

	TerritoryOwnership.Bind({
		territories = territories,
		ownerTypes = ownerTypes,
		DataService = DataService,
	})

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
		if _EconomyService and _EconomyService.SyncOutpostIncomeStacks then
			_EconomyService.SyncOutpostIncomeStacks(player)
		end
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
			local anyProgress = false
			for _, rt in pairs(territories) do
				local before = rt.Progress
				local beforeCap = rt.CapturingUserId
				tickTerritory(rt, dt)
				if rt.Progress ~= before or rt.CapturingUserId ~= beforeCap or rt.Contested then
					anyProgress = true
				end
			end
			-- Throttle full pushes; skip when idle and recently pushed
			local now = os.clock()
			if anyProgress or pushDirty or (now - lastPushAt >= 2.0) then
				if now - lastPushAt >= (if anyProgress then 0.5 else 2.0) then
					TerritoryService.PushAll()
					pushDirty = false
				end
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
