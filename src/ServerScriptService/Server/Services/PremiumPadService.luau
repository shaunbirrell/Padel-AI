--!strict
--[[
	ATM-cluster premium pads (AutoCollect / DoubleCash / SpeedBoost / GoldenPumpjack).
	Server validates own-plot + debounce, then FireClient PromptPremiumPad.
	Client prompts Marketplace; grants only via ProcessReceipt / GamePass ownership.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)

local PremiumPadService = {}

local DataService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local MonetizationService: any = nil
local BaseService: any = nil

local TAG = (Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"
local DEBOUNCE_SEC = 2.5
local OVERLAP_MARGIN = 3.5
local SPATIAL_INTERVAL = 0.25

local lastAttempt: { [string]: number } = {}
local lastOverlap: { [string]: boolean } = {}
local attached: { [BasePart]: boolean } = {}
local partConns: { [BasePart]: { RBXScriptConnection } } = {}
local promptRemote: RemoteEvent? = nil

local function attemptKey(userId: number, offerKey: string): string
	return tostring(userId) .. "|prem|" .. offerKey
end

local function trackConn(part: BasePart, conn: RBXScriptConnection)
	local list = partConns[part]
	if not list then
		list = {}
		partConns[part] = list
	end
	table.insert(list, conn)
end

local function detach(part: BasePart)
	local list = partConns[part]
	if list then
		for _, c in ipairs(list) do
			c:Disconnect()
		end
		partConns[part] = nil
	end
	attached[part] = nil
end

local function hardenPad(part: BasePart)
	part.CanTouch = true
	part.CanCollide = true
	part.CanQuery = true
end

local function pointInPad(hrpPos: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(hrpPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X + OVERLAP_MARGIN
		and math.abs(localPos.Z) <= half.Z + OVERLAP_MARGIN
		and localPos.Y >= -half.Y - 4
		and localPos.Y <= half.Y + 12
end

local function isSeated(character: Model): boolean
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	local seat = hum.SeatPart
	if seat == nil then
		return false
	end
	return seat:IsA("VehicleSeat") or seat:IsA("Seat")
end

local function alreadyOwns(player: Player, kind: string, key: string): boolean
	if not MonetizationService then
		return false
	end
	if kind == "GamePass" then
		if MonetizationService.PlayerOwnsGamePass and MonetizationService.PlayerOwnsGamePass(player, key) then
			return true
		end
		if MonetizationService.PlayerOwnsEntitlement and MonetizationService.PlayerOwnsEntitlement(player, key) then
			return true
		end
	elseif kind == "DevProduct" then
		local def = MonetizationConfig.DevProducts[key]
		local ent = def and def.GrantEntitlement
		if typeof(ent) == "string" and MonetizationService.PlayerOwnsEntitlement then
			return MonetizationService.PlayerOwnsEntitlement(player, ent) == true
		end
	end
	return false
end

local function resolveOffer(kind: string, key: string): (number?, string?)
	if kind == "GamePass" then
		local def = MonetizationConfig.GamePasses[key]
		if def and typeof(def.Id) == "number" then
			return def.Id, def.DisplayName or key
		end
	elseif kind == "DevProduct" then
		local def = MonetizationConfig.DevProducts[key]
		if def and typeof(def.Id) == "number" then
			return def.Id, def.DisplayName or key
		end
	end
	return nil, nil
end

local function tryPrompt(player: Player, part: BasePart, fromStanding: boolean?)
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return
	end

	if RunService:IsStudio() and profile.BasePlotId == nil then
		if BaseService and BaseService.AssignPlot then
			BaseService.AssignPlot(player)
			profile = DataService.GetProfile(player) or profile
		end
		if profile.BasePlotId == nil then
			profile.BasePlotId = 1
		end
	end

	local pid = part:GetAttribute("PlotId")
	if typeof(pid) == "number" and profile.BasePlotId ~= nil and pid ~= profile.BasePlotId then
		local key = attemptKey(player.UserId, "wrongplot")
		local now = os.clock()
		if now - (lastAttempt[key] or 0) >= DEBOUNCE_SEC then
			lastAttempt[key] = now
			if BaseService and BaseService.TeleportToPlot then
				BaseService.TeleportToPlot(player)
			end
			if NotificationService then
				if NotificationService.NotifyThrottled then
					NotificationService.NotifyThrottled(player, "Not your base — teleported to YOUR plot", "Warn", 2.5, 1.5, "prem_wrongplot")
				else
					NotificationService.Notify(player, "Not your base — teleported to YOUR plot", "Warn", 2.5)
				end
			end
		end
		return
	end

	local kind = part:GetAttribute("OfferKind")
	local offerKey = part:GetAttribute("OfferKey")
	if typeof(kind) ~= "string" or typeof(offerKey) ~= "string" then
		return
	end

	local akey = attemptKey(player.UserId, offerKey)
	local now = os.clock()
	if now - (lastAttempt[akey] or 0) < DEBOUNCE_SEC then
		return
	end
	lastAttempt[akey] = now

	if RateLimitService and not RateLimitService.Allow(player, "premium_pad", 3, 6) then
		return
	end

	if alreadyOwns(player, kind, offerKey) then
		if NotificationService and not fromStanding then
			if NotificationService.NotifyThrottled then
				NotificationService.NotifyThrottled(player, "Already owned", "Info", 2, 4, "prem_owned_" .. offerKey)
			else
				NotificationService.Notify(player, "Already owned", "Info", 2)
			end
		end
		return
	end

	local productId, displayName = resolveOffer(kind, offerKey)
	if productId == nil then
		return
	end
	if productId == 0 then
		if NotificationService then
			NotificationService.NotifyThrottled
				and NotificationService.NotifyThrottled(player, (displayName or offerKey) .. " — coming soon", "Info", 2.5, 4, "prem_stub_" .. offerKey)
				or NotificationService.Notify(player, (displayName or offerKey) .. " — coming soon", "Info", 2.5)
		end
		return
	end

	if promptRemote then
		promptRemote:FireClient(player, {
			Kind = kind,
			Key = offerKey,
			ProductId = productId,
			DisplayName = displayName,
		})
	end
end

local function onPadTouched(part: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	if isSeated(character) then
		return
	end
	local offerKey = part:GetAttribute("OfferKey")
	if typeof(offerKey) ~= "string" then
		return
	end
	local okey = tostring(part:GetAttribute("PlotId") or 0) .. "|" .. offerKey .. "|" .. tostring(player.UserId)
	if lastOverlap[okey] then
		return
	end
	lastOverlap[okey] = true
	tryPrompt(player, part, false)
end

local function attachPad(part: BasePart)
	if attached[part] then
		hardenPad(part)
		return
	end
	if not part:IsA("BasePart") then
		return
	end
	if typeof(part:GetAttribute("OfferKey")) ~= "string" then
		return
	end
	attached[part] = true
	hardenPad(part)

	trackConn(part, part.Touched:Connect(function(hit)
		if hit:IsA("BasePart") then
			onPadTouched(part, hit)
		end
	end))

	trackConn(part, part.TouchEnded:Connect(function(hit)
		if not hit:IsA("BasePart") then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local offerKey = part:GetAttribute("OfferKey")
		if typeof(offerKey) ~= "string" then
			return
		end
		local okey = tostring(part:GetAttribute("PlotId") or 0) .. "|" .. offerKey .. "|" .. tostring(player.UserId)
		task.defer(function()
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and pointInPad(hrp.Position, part) then
				return
			end
			lastOverlap[okey] = false
		end)
	end))

	trackConn(part, part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			detach(part)
		end
	end))
end

function PremiumPadService.Init(deps: { [string]: any })
	DataService = deps.DataService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	MonetizationService = deps.MonetizationService
	BaseService = deps.BaseService

	promptRemote = RemoteSetup.Get(Constants.RemoteNames.PromptPremiumPad) :: RemoteEvent

	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") then
			attachPad(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			attachPad(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			detach(inst)
		end
	end)

	-- Spatial standing check (debounce like UpgradePadService)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < SPATIAL_INTERVAL then
			return
		end
		accum = 0
		for part, _ in pairs(attached) do
			if not part.Parent then
				continue
			end
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if not character or isSeated(character) then
					continue
				end
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if not hrp or not hrp:IsA("BasePart") then
					continue
				end
				local offerKey = part:GetAttribute("OfferKey")
				if typeof(offerKey) ~= "string" then
					continue
				end
				local okey = tostring(part:GetAttribute("PlotId") or 0) .. "|" .. offerKey .. "|" .. tostring(player.UserId)
				local inside = pointInPad(hrp.Position, part)
				if inside and not lastOverlap[okey] then
					lastOverlap[okey] = true
					tryPrompt(player, part, true)
				elseif not inside then
					lastOverlap[okey] = false
				end
			end
		end
	end)

	print("[WAR EMPIRE] PremiumPadService ready (ATM-cluster Robux pads)")
end

return PremiumPadService
