--!strict
--[[
	SERVER-AUTHORITATIVE walk-over upgrade purchase.

	Primary buy path: Touched on WE_UpgradeSlot plinths + 0.25s spatial HRP check.
	Validates PlotId == profile.BasePlotId, debounces per player+structure (~1s),
	then BaseService.PurchaseUpgrade + same Success/Warn toasts as the remote.
	Client WorldPromptController FireServer remains a secondary path (B-menu / backup).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)

local UpgradePadService = {}

local DataService: any = nil
local BaseService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil

local TAG = Constants.Tags.UpgradeSlot
local DEBOUNCE_SEC = 1.0
local OVERLAP_MARGIN = 2.4
local SPATIAL_INTERVAL = 0.25

-- userId|structureId -> last attempt clock
local lastAttempt: { [string]: number } = {}
-- part -> connected
local attached: { [BasePart]: boolean } = {}
local partConns: { [BasePart]: { RBXScriptConnection } } = {}
-- padKey -> currently overlapping (for enter-edge)
local lastOverlap: { [string]: boolean } = {}

local function attemptKey(userId: number, structureId: string): string
	return tostring(userId) .. "|" .. structureId
end

local function padKey(part: BasePart, structureId: string): string
	local pid = part:GetAttribute("PlotId")
	if typeof(pid) == "number" then
		return tostring(pid) .. "|" .. structureId
	end
	return structureId
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

local function pointInPad(hrpPos: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(hrpPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X + OVERLAP_MARGIN
		and math.abs(localPos.Z) <= half.Z + OVERLAP_MARGIN
		and localPos.Y >= -half.Y - 3
		and localPos.Y <= half.Y + 8
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

local function notifyPurchaseResult(player: Player, structureId: string, result: any)
	if not NotificationService then
		return
	end
	if result.Ok then
		local def = BaseConfig.Structures[structureId]
		local name = if def then def.DisplayName else tostring(structureId)
		NotificationService.Notify(
			player,
			string.format("%s → Lv %d", name, result.NewLevel or 0),
			"Success",
			3
		)
	else
		local err = result.Error or "Failed"
		local msg = if err == "InsufficientCash"
			then "Not enough cash"
			elseif err == "InsufficientGold"
			then "Not enough gold"
			elseif err == "MaxLevel"
			then "Already at MAX level"
			elseif err == "MissingRequirement"
			then "Missing prerequisite structure"
			elseif err == "UnknownStructure" or err == "InvalidStructure"
			then "Unknown structure"
			elseif err == "WrongPlot"
			then "Not your base — walk your plot pads to buy"
			else ("Purchase failed: " .. tostring(err))
		-- Soft-fail MaxLevel while camping: throttle
		if err == "MaxLevel" then
			NotificationService.Notify(player, msg, "Info", 2)
		else
			NotificationService.Notify(player, msg, "Warn", 3.5)
		end
	end
end

local function tryServerPurchase(player: Player, part: BasePart, structureId: string, fromStanding: boolean?)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end

	local pid = part:GetAttribute("PlotId")
	if typeof(pid) == "number" and profile.BasePlotId ~= nil and pid ~= profile.BasePlotId then
		local key = attemptKey(player.UserId, structureId)
		local now = os.clock()
		local last = lastAttempt[key] or 0
		if now - last >= DEBOUNCE_SEC then
			lastAttempt[key] = now
			if NotificationService then
				NotificationService.Notify(player, "Not your base — walk your plot pads to buy", "Warn", 2.5)
			end
		end
		return
	end

	local key = attemptKey(player.UserId, structureId)
	local now = os.clock()
	local last = lastAttempt[key] or 0
	if now - last < DEBOUNCE_SEC then
		return
	end

	-- Early MaxLevel / missing def — no rate-limit burn while camping
	local def = BaseConfig.Structures[structureId]
	local current = profile.BaseUpgrades[structureId] or 0
	if def and current >= def.MaxLevel then
		lastAttempt[key] = now
		if not fromStanding then
			notifyPurchaseResult(player, structureId, { Ok = false, Error = "MaxLevel" })
		end
		return
	end

	lastAttempt[key] = now

	-- Soft rate limit shared with remote path (avoid spam)
	if RateLimitService and not RateLimitService.Allow(player, "purchase_upgrade", 6, 8) then
		if NotificationService and not fromStanding then
			NotificationService.Notify(player, "Buying too fast — wait a moment", "Warn", 2.5)
		end
		return
	end

	local result = BaseService.PurchaseUpgrade(player, structureId)
	notifyPurchaseResult(player, structureId, result)
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
	local structureId = part:GetAttribute("StructureId")
	if typeof(structureId) ~= "string" then
		return
	end
	local key = padKey(part, structureId) .. "|" .. tostring(player.UserId)
	if lastOverlap[key] then
		return -- enter-edge only; standing handled by spatial loop
	end
	lastOverlap[key] = true
	tryServerPurchase(player, part, structureId, false)
end

local function attachSlot(part: BasePart)
	if attached[part] then
		return
	end
	if not part:IsA("BasePart") then
		return
	end
	local structureId = part:GetAttribute("StructureId")
	if typeof(structureId) ~= "string" then
		return
	end

	attached[part] = true
	part.CanTouch = true

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
		local sid = part:GetAttribute("StructureId")
		if typeof(sid) ~= "string" then
			return
		end
		local key = padKey(part, sid) .. "|" .. tostring(player.UserId)
		task.defer(function()
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and pointInPad(hrp.Position, part) then
				return
			end
			lastOverlap[key] = false
		end)
	end))

	trackConn(part, part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			detach(part)
		end
	end))
end

local function bindExistingAndFuture()
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") then
			attachSlot(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			attachSlot(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			detach(inst)
		end
	end)
end

local function startSpatialLoop()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < SPATIAL_INTERVAL then
			return
		end
		acc = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				if isSeated(character) then
					-- Clear overlap so stepping out can buy
					local uid = tostring(player.UserId)
					local suffix = "|" .. uid
					for key in pairs(lastOverlap) do
						if string.sub(key, -#suffix) == suffix then
							lastOverlap[key] = false
						end
					end
				else
					local hrp = character:FindFirstChild("HumanoidRootPart")
					if hrp and hrp:IsA("BasePart") then
						local pos = hrp.Position
						for part in pairs(attached) do
							if part.Parent then
								local structureId = part:GetAttribute("StructureId")
								if typeof(structureId) == "string" then
									local key = padKey(part, structureId) .. "|" .. tostring(player.UserId)
									local inside = pointInPad(pos, part)
									if inside then
										if not lastOverlap[key] then
											lastOverlap[key] = true
											tryServerPurchase(player, part, structureId, false)
										else
											tryServerPurchase(player, part, structureId, true)
										end
									elseif lastOverlap[key] then
										lastOverlap[key] = false
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end

function UpgradePadService.Init(deps: { [string]: any })
	DataService = deps.DataService
	BaseService = deps.BaseService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService

	bindExistingAndFuture()
	startSpatialLoop()

	-- Late map / retag: re-scan shortly after init
	task.defer(function()
		task.wait(1)
		for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
			if inst:IsA("BasePart") then
				attachSlot(inst)
			end
		end
	end)

	print("[WAR EMPIRE] UpgradePadService ready (server walk-over buy)")
end

return UpgradePadService
