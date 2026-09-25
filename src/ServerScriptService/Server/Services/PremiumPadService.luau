--!strict
--[[
	ATM-cluster premium pads (AutoCollect / DoubleCash / SpeedBoost / GoldenPumpjack).
	Server validates own-plot + debounce, then FireClient PromptPremiumPad.
	Client prompts Marketplace; grants only via ProcessReceipt / GamePass ownership.
	F1 / F9 (owner's 11 features, lane M): the ATM pads come from MonetizationConfig.PremiumPads.Slots (the first live
	offer of a slot is the one its pad sells) and the golden pump pad sits by the pumps; every pad is a WE_PremiumPad
	part with OfferKind / OfferKey / PlotId (and OwnedIfAny) attributes. OWNED = the offer, or any key of the slot's
	OwnedIfAny (pad attribute and config), is owned as a game pass or an entitlement, which includes Developer
	Products and entitlements granted by another product (Auto Collect from the Starter Pack). An owned pad never
	prompts; a pad whose offer Id is 0 never prompts either.
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
local MAX_OWNED_KEYS = 8 -- F1: a pad's OwnedIfAny attribute is read up to this many keys
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

local function isKeyName(v: any): boolean
	return typeof(v) == "string" and #v > 0 and #v <= 64 and string.match(v, "^[%w_]+$") ~= nil
end

--[[ F1: the extra keys whose ownership makes this pad OWNED: the pad's OwnedIfAny attribute (comma string, written
	by the server when it builds the pad) plus the OwnedIfAny of every PremiumPads slot that offers this Kind + Key
	(so a pad built before the attribute existed, e.g. the Speed Boost pad, still honours the Speed Pass). ]]
local function ownedIfAnyKeys(part: BasePart?, kind: string, key: string): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(k: any)
		if #out < MAX_OWNED_KEYS and isKeyName(k) and not seen[k] then
			seen[k] = true
			table.insert(out, k)
		end
	end
	local attr = if part then part:GetAttribute("OwnedIfAny") else nil
	if typeof(attr) == "string" and #attr <= 512 then
		for _, k in ipairs(string.split(attr, ",")) do
			add(string.match(k, "^%s*(.-)%s*$"))
		end
	end
	local pads = (MonetizationConfig :: any).PremiumPads
	local slots = if typeof(pads) == "table" then pads.Slots else nil
	if typeof(slots) == "table" then
		for _, slot in ipairs(slots) do
			local offers = if typeof(slot) == "table" then slot.Offers else nil
			if typeof(offers) ~= "table" then
				continue
			end
			for _, offer in ipairs(offers) do
				if typeof(offer) == "table" and offer.Kind == kind and offer.Key == key then
					for _, k in ipairs(MonetizationConfig.PadOwnedKeys(slot)) do
						add(k)
					end
					break
				end
			end
		end
	end
	return out
end

-- one key: a game pass, an entitlement of that name, or the entitlement a Developer Product of that name grants
local function ownsKey(player: Player, key: string): boolean
	if MonetizationService.PlayerOwnsGamePass and MonetizationService.PlayerOwnsGamePass(player, key) then
		return true
	end
	if MonetizationService.PlayerOwnsEntitlement and MonetizationService.PlayerOwnsEntitlement(player, key) then
		return true
	end
	local dp = (MonetizationConfig.DevProducts :: any)[key]
	local ent = if typeof(dp) == "table" then dp.GrantEntitlement else nil
	if typeof(ent) == "string" and ent ~= key and MonetizationService.PlayerOwnsEntitlement then
		return MonetizationService.PlayerOwnsEntitlement(player, ent) == true
	end
	return false
end

local function alreadyOwns(player: Player, kind: string, key: string, part: BasePart?): boolean
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
		local def = (MonetizationConfig.DevProducts :: any)[key]
		local ent = if typeof(def) == "table" then def.GrantEntitlement else nil
		if typeof(ent) == "string" and MonetizationService.PlayerOwnsEntitlement then
			if MonetizationService.PlayerOwnsEntitlement(player, ent) == true then
				return true
			end
		end
	end
	-- F1: OwnedIfAny (Speed pad: owning the Speed Pass OR Speed Boost = OWNED, whichever the pad sells)
	for _, k in ipairs(ownedIfAnyKeys(part, kind, key)) do
		if ownsKey(player, k) then
			return true
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

	-- v68: assign a plot if missing, but never fall back to someone else's plot 1
	if profile.BasePlotId == nil and BaseService and BaseService.AssignPlot then
		BaseService.AssignPlot(player)
		profile = DataService.GetProfile(player) or profile
	end

	-- v70: another plot's pads (or an unowned plot's, or any plot's while you have none) do nothing — no
	-- prompt, no teleport. Teleporting here threw raiders off the ATM approach and anyone crossing a cluster.
	local pid = part:GetAttribute("PlotId")
	if typeof(pid) == "number" and pid ~= profile.BasePlotId then
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

	if alreadyOwns(player, kind, offerKey, part) then
		if NotificationService and not fromStanding then
			if NotificationService.NotifyThrottled then
				NotificationService.NotifyThrottled(player, "OWNED", "Info", 2, 4, "prem_owned_" .. offerKey)
			else
				NotificationService.Notify(player, "OWNED", "Info", 2)
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
			local msg = (displayName or offerKey) .. " — coming soon"
			if NotificationService.NotifyThrottled then
				NotificationService.NotifyThrottled(player, msg, "Info", 2.5, 4, "prem_stub_" .. offerKey)
			else
				NotificationService.Notify(player, msg, "Info", 2.5)
			end
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
