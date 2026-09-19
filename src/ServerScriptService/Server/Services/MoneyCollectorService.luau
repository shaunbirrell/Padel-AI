--!strict
--[[
	Money Collector — passive income accrues to PendingCash until the player
	touches their plot's WE_MoneyCollector (or owns AutoCollect entitlement).
	Server-authoritative only.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)

local MoneyCollectorService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local MonetizationService: any = nil
local TutorialService: any = nil

local TAG = Constants.Tags.MoneyCollector
local OVERLAP_MARGIN = 3.5
local SPATIAL_INTERVAL = 0.25
local AUTO_COLLECT_INTERVAL = 2.0

local lastOverlap: { [string]: boolean } = {}
local billboardCache: { [BasePart]: BillboardGui } = {}

local function hasAutoCollect(player: Player): boolean
	if MonetizationService and MonetizationService.PlayerOwnsEntitlement then
		if MonetizationService.PlayerOwnsEntitlement(player, "AutoCollect") then
			return true
		end
	end
	if MonetizationService and MonetizationService.PlayerOwnsGamePass then
		if MonetizationService.PlayerOwnsGamePass(player, "AutoCollect") then
			return true
		end
	end
	local profile = DataService.GetProfile(player)
	if profile and typeof(profile.Entitlements) == "table" and profile.Entitlements.AutoCollect == true then
		return true
	end
	return false
end

local function ensureBillboard(part: BasePart): BillboardGui
	local existing = billboardCache[part]
	if existing and existing.Parent then
		return existing
	end
	local old = part:FindFirstChild("WE_CollectorBillboard")
	if old and old:IsA("BillboardGui") then
		billboardCache[part] = old
		return old
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_CollectorBillboard"
	bb.Size = UDim2.fromOffset(200, 64)
	bb.StudsOffset = Vector3.new(0, 6.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Parent = part

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	backdrop.BackgroundTransparency = 0.08
	backdrop.BorderSizePixel = 0
	backdrop.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = backdrop
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 200, 120)
	stroke.Thickness = 2
	stroke.Parent = backdrop

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -8, 0.45, 0)
	title.Position = UDim2.fromOffset(4, 2)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(235, 238, 242)
	title.Text = "MONEY COLLECTOR"
	title.Parent = backdrop

	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.Size = UDim2.new(1, -8, 0.5, 0)
	amount.Position = UDim2.fromOffset(4, 28)
	amount.BackgroundTransparency = 1
	amount.Font = Enum.Font.GothamBold
	amount.TextScaled = true
	amount.TextColor3 = Color3.fromRGB(80, 220, 120)
	amount.Text = "$0"
	amount.Parent = backdrop

	billboardCache[part] = bb
	return bb
end

local function refreshBillboard(part: BasePart, pending: number)
	local bb = ensureBillboard(part)
	local amount = bb:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		amount.Text = string.format("$%s pending", tostring(math.floor(pending)))
		if pending > 0 then
			amount.TextColor3 = Color3.fromRGB(90, 240, 130)
		else
			amount.TextColor3 = Color3.fromRGB(160, 170, 180)
		end
	end
end

local function pointInPart(hrpPos: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(hrpPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X + OVERLAP_MARGIN
		and math.abs(localPos.Z) <= half.Z + OVERLAP_MARGIN
		and localPos.Y >= -half.Y - 4
		and localPos.Y <= half.Y + 10
end

function MoneyCollectorService.Collect(player: Player): (boolean, number)
	if not EconomyService or not EconomyService.CollectPendingCash then
		return false, 0
	end
	local granted = EconomyService.CollectPendingCash(player)
	if granted > 0 then
		if NotificationService then
			NotificationService.Notify(player, string.format("Collected $%d", granted), "Success", 3)
		end
		if TutorialService and TutorialService.Notify then
			TutorialService.Notify(player, "PassiveIncome")
		end
		return true, granted
	end
	return false, 0
end

function MoneyCollectorService.RefreshAllBillboards()
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") and inst.Parent then
			local plotId = inst:GetAttribute("PlotId")
			local pending = 0
			if typeof(plotId) == "number" then
				for _, player in ipairs(Players:GetPlayers()) do
					local profile = DataService.GetProfile(player)
					if profile and profile.BasePlotId == plotId then
						pending = tonumber(profile.PendingCash) or 0
						break
					end
				end
			end
			refreshBillboard(inst, pending)
		end
	end
end

function MoneyCollectorService.RefreshForPlayer(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile or profile.BasePlotId == nil then
		return
	end
	local pending = tonumber(profile.PendingCash) or 0
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == profile.BasePlotId then
			refreshBillboard(inst, pending)
		end
	end
end

function MoneyCollectorService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	MonetizationService = deps.MonetizationService
	TutorialService = deps.TutorialService

	-- Touch + spatial collect
	local function tryCollectFromPart(player: Player, part: BasePart)
		local profile = DataService.GetProfile(player)
		if not profile then
			return
		end
		local plotId = part:GetAttribute("PlotId")
		if typeof(plotId) == "number" and profile.BasePlotId ~= nil and plotId ~= profile.BasePlotId then
			return
		end
		local pending = tonumber(profile.PendingCash) or 0
		if pending <= 0 then
			return
		end
		MoneyCollectorService.Collect(player)
		MoneyCollectorService.RefreshForPlayer(player)
	end

	local attached: { [BasePart]: boolean } = {}
	local function attach(part: BasePart)
		if attached[part] then
			return
		end
		attached[part] = true
		part.CanTouch = true
		part.CanCollide = true
		ensureBillboard(part)
		part.Touched:Connect(function(hit)
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
			local key = tostring(player.UserId) .. "|" .. part:GetFullName()
			if lastOverlap[key] then
				return
			end
			lastOverlap[key] = true
			tryCollectFromPart(player, part)
		end)
		part.TouchEnded:Connect(function(hit)
			if not hit:IsA("BasePart") then
				return
			end
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				lastOverlap[tostring(player.UserId) .. "|" .. part:GetFullName()] = false
			end
		end)
	end

	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") then
			attach(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			attach(inst)
		end
	end)

	local acc = 0
	local autoAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		autoAcc += dt
		if acc >= SPATIAL_INTERVAL then
			acc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local profile = DataService.GetProfile(player)
					if profile and (tonumber(profile.PendingCash) or 0) > 0 then
						for part in pairs(attached) do
							if part.Parent and pointInPart(hrp.Position, part) then
								tryCollectFromPart(player, part)
							end
						end
					end
				end
			end
			MoneyCollectorService.RefreshAllBillboards()
		end
		if autoAcc >= AUTO_COLLECT_INTERVAL then
			autoAcc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				if hasAutoCollect(player) then
					local profile = DataService.GetProfile(player)
					if profile and (tonumber(profile.PendingCash) or 0) > 0 then
						MoneyCollectorService.Collect(player)
						MoneyCollectorService.RefreshForPlayer(player)
					end
				end
			end
		end
	end)

	print("[WAR EMPIRE] MoneyCollectorService ready (PendingCash → touch WE_MoneyCollector)")
end

return MoneyCollectorService
