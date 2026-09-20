--!strict
--[[
	Phase 5 — Territory control.
	Server-authoritative stand-in-zone capture; bonuses for Economy / XP / Vehicles / Combat.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
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

local function ownerStateLabel(rt: TerritoryRuntime): string
	local ot = ownerTypes()
	if rt.Contested or rt.OwnerType == ot.Contested then
		return "CONTESTED"
	elseif rt.OwnerType == ot.Player then
		local plr = Players:GetPlayerByUserId(rt.OwnerUserId)
		return if plr then ("OWNED · " .. plr.DisplayName) else "OWNED"
	elseif rt.OwnerType == ot.NPC then
		return "HOSTILE NPC"
	elseif rt.OwnerType == ot.Clan then
		return "CLAN"
	end
	return "NEUTRAL · Stand to capture"
end

local function updateMarkerVisual(rt: TerritoryRuntime)
	local marker = rt.Marker
	if not marker then
		return
	end
	local ot = ownerTypes()
	local contested = rt.Contested or rt.OwnerType == ot.Contested
	local color: Color3
	local markerTransparency = 0.45
	local flagTransparency = 0.15
	local flagMaterial = Enum.Material.Neon
	local ringTransparency = 0.65
	local flagLift = 12 -- studs above ground for flag center

	if contested then
		color = Color3.fromRGB(255, 140, 35)
		markerTransparency = 0.28
		flagTransparency = 0.05
		ringTransparency = 0.35
		flagLift = 13.5
	elseif rt.OwnerType == ot.Player then
		local nation = if NationColorService and NationColorService.GetColor then NationColorService.GetColor(rt.OwnerUserId) else nil
		color = nation or Color3.fromRGB(55, 210, 95)
		markerTransparency = 0.35
		flagTransparency = 0.0
		ringTransparency = 0.45
		flagLift = 14.5
	elseif rt.OwnerType == ot.NPC then
		color = Color3.fromRGB(210, 45, 45)
		markerTransparency = 0.32
		flagTransparency = 0.05
		ringTransparency = 0.4
		flagLift = 13.2
	elseif rt.OwnerType == ot.Clan then
		color = Color3.fromRGB(70, 120, 240)
		markerTransparency = 0.35
		flagTransparency = 0.0
		ringTransparency = 0.45
		flagLift = 14.0
	else
		color = rt.Def.Color
		flagMaterial = Enum.Material.SmoothPlastic
		flagTransparency = 0.35
		flagLift = 11.0
	end

	marker.Color = color
	marker.Transparency = markerTransparency
	marker.Material = Enum.Material.Neon
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
		flag.Material = flagMaterial
		flag.Transparency = flagTransparency
		-- Raise owned flags; lower neutral so ownership reads at a glance
		local basePos = marker.Position
		flag.Size = if contested then Vector3.new(6.2, 3.6, 0.3) elseif rt.OwnerType == ot.Neutral then Vector3.new(4.2, 2.4, 0.22) else Vector3.new(5.5, 3.2, 0.28)
		flag.Position = Vector3.new(basePos.X + flag.Size.X * 0.5 + 0.2, flagLift, basePos.Z)
		-- Ownership flash light (brief)
		local lightInst = flag:FindFirstChild("WE_OwnerLight")
		local light: PointLight
		if lightInst and lightInst:IsA("PointLight") then
			light = lightInst
		else
			if lightInst then
				lightInst:Destroy()
			end
			light = Instance.new("PointLight")
			light.Name = "WE_OwnerLight"
			light.Range = 28
			light.Parent = flag
		end
		light.Color = color
		light.Brightness = if contested then 3.2 elseif rt.OwnerType == ot.Neutral then 0.4 else 2.4
		light.Enabled = true

		-- Keep stripe locked to flag (nation color visibility polish)
		local stripe = parent:FindFirstChild(tid .. "_FlagStripe")
		if stripe and stripe:IsA("BasePart") then
			stripe.Size = Vector3.new(flag.Size.X, math.max(0.35, flag.Size.Y * 0.14), flag.Size.Z + 0.06)
			stripe.Position = flag.Position
			stripe.Color = Color3.fromRGB(245, 245, 245)
			stripe.Transparency = if rt.OwnerType == ot.Neutral then 0.45 else 0.08
		end

		-- Floating nation-color flag marker (AlwaysOnTop billboard) for long-range read
		local flagBbInst = flag:FindFirstChild("WE_FlagBillboard")
		local flagBb: BillboardGui
		if flagBbInst and flagBbInst:IsA("BillboardGui") then
			flagBb = flagBbInst
		else
			if flagBbInst then
				flagBbInst:Destroy()
			end
			local created = Instance.new("BillboardGui")
			created.Name = "WE_FlagBillboard"
			created.Size = UDim2.fromOffset(52, 52)
			created.StudsOffset = Vector3.new(0, 2.2, 0)
			created.AlwaysOnTop = true
			created.MaxDistance = 160
			created.Parent = flag
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
			flagBb = created
		end
		flagBb.Enabled = rt.OwnerType ~= ot.Neutral or contested
		flagBb.MaxDistance = if contested then 180 else 150
		local diamond = flagBb:FindFirstChild("NationDiamond")
		if diamond and diamond:IsA("Frame") then
			diamond.BackgroundColor3 = color
			local ds = diamond:FindFirstChild("DiamondStroke")
			if ds and ds:IsA("UIStroke") then
				ds.Color = if contested then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(255, 255, 255)
			end
		end
	end

	local ring = parent:FindFirstChild(tid .. "_Ring")
	if ring and ring:IsA("BasePart") then
		ring.Color = color
		ring.Transparency = ringTransparency
		ring.Material = if contested then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local d = (rt.Def.Radius or 30) * 2
		ring.Size = if contested then Vector3.new(d + 14, 0.55, d + 14) else Vector3.new(d + 8, 0.4, d + 8)
	end

	local pole = parent:FindFirstChild(tid .. "_FlagPole")
	if pole and pole:IsA("BasePart") then
		pole.Color = if contested then Color3.fromRGB(180, 90, 30) elseif rt.OwnerType == ot.Neutral then Color3.fromRGB(55, 55, 55) else Color3.fromRGB(40, 45, 40)
	end

	-- Billboard state line (CONTESTED reads loud — progress + enemy presence)
	local labelGui = marker:FindFirstChild("Label")
	if labelGui and labelGui:IsA("BillboardGui") then
		local backdrop = labelGui:FindFirstChild("Backdrop")
		local textLabel = backdrop and backdrop:FindFirstChild("Text")
		local pct = math.floor((rt.Progress / math.max(1, rt.Def.CaptureTimeSeconds)) * 100)
		if contested then
			-- Enlarge billboard while contested so it reads at range
			labelGui.Size = UDim2.fromOffset(220, 64)
			labelGui.StudsOffset = Vector3.new(0, 10, 0)
			labelGui.MaxDistance = 120
			if backdrop and backdrop:IsA("Frame") then
				backdrop.BackgroundColor3 = Color3.fromRGB(55, 28, 8)
				backdrop.BackgroundTransparency = 0.08
			end
			-- Ensure a second "CONTESTED" badge line
			local badge = backdrop and backdrop:FindFirstChild("ContestedBadge")
			if backdrop and (not badge or not badge:IsA("TextLabel")) then
				if badge then
					badge:Destroy()
				end
				local b = Instance.new("TextLabel")
				b.Name = "ContestedBadge"
				b.BackgroundTransparency = 1
				b.Position = UDim2.fromScale(0, 0)
				b.Size = UDim2.new(1, 0, 0.42, 0)
				b.Font = Enum.Font.GothamBold
				b.TextScaled = true
				b.TextColor3 = Color3.fromRGB(255, 170, 60)
				b.TextStrokeTransparency = 0.4
				b.Text = "⚠ CONTESTED"
				b.Parent = backdrop
				badge = b
				if textLabel and textLabel:IsA("TextLabel") then
					textLabel.Position = UDim2.fromScale(0, 0.42)
					textLabel.Size = UDim2.new(1, 0, 0.58, 0)
				end
			elseif badge and badge:IsA("TextLabel") then
				badge.Visible = true
				badge.Text = "⚠ CONTESTED"
			end
			if textLabel and textLabel:IsA("TextLabel") then
				local enemyNote = "enemy present"
				textLabel.Text = string.format("%s · %d%% · %s", rt.Def.DisplayName, pct, enemyNote)
				textLabel.TextColor3 = Color3.fromRGB(255, 210, 140)
			end
		else
			-- v34: brief progress/owner chip when capture in progress; otherwise owner state
			local capturing = (rt.Progress or 0) > 0.02 and (rt.CapturingUserId or 0) > 0
			labelGui.Size = if capturing then UDim2.fromOffset(200, 56) else UDim2.fromOffset(180, 40)
			labelGui.StudsOffset = Vector3.new(0, 8, 0)
			labelGui.MaxDistance = if capturing then 90 else 70
			if backdrop and backdrop:IsA("Frame") then
				backdrop.BackgroundColor3 = if capturing then Color3.fromRGB(28, 40, 22) else Color3.fromRGB(12, 14, 16)
				backdrop.BackgroundTransparency = 0.18
			end
			local badge = backdrop and backdrop:FindFirstChild("ContestedBadge")
			if badge and badge:IsA("GuiObject") then
				badge.Visible = false
			end
			-- Owner / progress chip
			local chip = backdrop and backdrop:FindFirstChild("OwnerChip")
			if backdrop and (not chip or not chip:IsA("TextLabel")) then
				if chip then chip:Destroy() end
				local c = Instance.new("TextLabel")
				c.Name = "OwnerChip"
				c.BackgroundTransparency = 1
				c.Position = UDim2.fromScale(0, 0)
				c.Size = UDim2.new(1, 0, 0.4, 0)
				c.Font = Enum.Font.GothamBold
				c.TextScaled = true
				c.TextStrokeTransparency = 0.45
				c.Parent = backdrop
				chip = c
			end
			if chip and chip:IsA("TextLabel") then
				if capturing then
					chip.Visible = true
					chip.Text = string.format("CAPTURING · %d%%", pct)
					chip.TextColor3 = Color3.fromRGB(200, 230, 120)
					if textLabel and textLabel:IsA("TextLabel") then
						textLabel.Position = UDim2.fromScale(0, 0.4)
						textLabel.Size = UDim2.new(1, 0, 0.6, 0)
					end
				else
					chip.Visible = true
					chip.Text = ownerStateLabel(rt)
					chip.TextColor3 = if rt.OwnerType == ot.Player then Color3.fromRGB(140, 230, 160) elseif rt.OwnerType == ot.NPC then Color3.fromRGB(255, 150, 140) else Color3.fromRGB(180, 180, 180)
					if textLabel and textLabel:IsA("TextLabel") then
						textLabel.Position = UDim2.fromScale(0, 0.4)
						textLabel.Size = UDim2.new(1, 0, 0.6, 0)
					end
				end
			end
			if textLabel and textLabel:IsA("TextLabel") then
				if capturing then
					textLabel.Text = string.format("%s · was %s", rt.Def.DisplayName, ownerStateLabel(rt))
				else
					textLabel.Text = rt.Def.DisplayName
				end
				textLabel.TextColor3 = if rt.OwnerType == ot.Player then Color3.fromRGB(160, 255, 180) elseif rt.OwnerType == ot.NPC then Color3.fromRGB(255, 160, 150) else Color3.new(1, 1, 1)
			end
		end
		local stroke = backdrop and backdrop:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
			stroke.Thickness = if contested then 2 else 1
		end
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
				msg = string.format("%s secured — +%d%% Income (yours)", zoneName, incomePct)
			end
			NotificationService.Notify(player, msg, "Reward", 5)
		else
			local bonusHint = rt.Def.Description or ""
			if #bonusHint > 60 then
				bonusHint = string.sub(bonusHint, 1, 57) .. "..."
			end
			NotificationService.Notify(
				player,
				string.format("Captured %s! %s", zoneName, bonusHint),
				"Reward"
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
	if NotificationService then
		NotificationService.Notify(player, "Capturing " .. rt.Def.DisplayName .. "...", "Info")
	end
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
