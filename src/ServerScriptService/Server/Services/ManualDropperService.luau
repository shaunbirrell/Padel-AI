--!strict
--[[
	Early-game manual cash droppers at each plot (Money Collector + Training Yard).
	ClickDetector / ProximityPrompt → AccruePendingCash. Server cooldown + rate limit.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ManualDropperConfig = require(Shared.Configs.ManualDropperConfig)

local ManualDropperService = {}

local DataService: any = nil
local EconomyService: any = nil
local RateLimitService: any = nil
local VisualAssetService: any = nil
local TutorialService: any = nil
local NotificationService: any = nil

local TAG_COLLECTOR = Constants.Tags.MoneyCollector
local TAG_DROPPER = "WE_ManualDropper"

local lastAwardAt: { [string]: number } = {}
local wired: { [BasePart]: boolean } = {}

-- v69: per-player award budget (minute + hour refilling buckets). Kept for an hour after leaving so a
-- same-server rejoin does not reset it.
type Budget = { minute: number, hour: number, at: number }
local budgets: { [number]: Budget } = {}

local function budgetLimits(): (number, number)
	local perMinute = math.max(1, math.floor(tonumber(ManualDropperConfig.MaxAwardsPerMinute) or 30))
	local perHour = math.max(perMinute, math.floor(tonumber(ManualDropperConfig.MaxAwardsPerHour) or 600))
	return perMinute, perHour
end

-- Consumes one award from the player's budget; false when either bucket is empty.
local function takeBudget(userId: number, now: number): boolean
	local perMinute, perHour = budgetLimits()
	local b = budgets[userId]
	if not b then
		b = { minute = perMinute, hour = perHour, at = now }
		budgets[userId] = b
	end
	local dt = math.max(0, now - b.at)
	b.at = now
	b.minute = math.min(perMinute, b.minute + dt * perMinute / 60)
	b.hour = math.min(perHour, b.hour + dt * perHour / 3600)
	if b.minute < 1 or b.hour < 1 then
		return false
	end
	b.minute -= 1
	b.hour -= 1
	return true
end

local function pickAward(): number
	local fixed = ManualDropperConfig.AwardAmount
	if typeof(fixed) == "number" and fixed > 0 then
		return math.floor(fixed)
	end
	local lo = math.floor(ManualDropperConfig.MinAward or 10)
	local hi = math.floor(ManualDropperConfig.MaxAward or 25)
	if hi < lo then
		hi = lo
	end
	return math.random(lo, hi)
end

local function cooldownKey(player: Player, dropper: BasePart): string
	return tostring(player.UserId) .. "|" .. dropper:GetFullName()
end

local function ownsPlot(player: Player, plotId: any): boolean
	if typeof(plotId) ~= "number" then
		return false
	end
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return false
	end
	return profile.BasePlotId == plotId
end

local function spawnFloatingCash(parent: Instance, amount: number, at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "WE_DropCashPop"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(at + Vector3.new(0, 2.2, 0))
	anchor.Parent = parent

	local bb = Instance.new("BillboardGui")
	bb.Name = "CashPop"
	bb.Size = UDim2.fromOffset(132, 44)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(80, 255, 120)
	label.TextStrokeTransparency = 0.25
	label.TextStrokeColor3 = Color3.fromRGB(8, 36, 14)
	label.Text = string.format("+$%d", amount)
	label.Parent = bb
	-- Competitor-style floating green $ pop (glow stroke)
	local glow = Instance.new("UIStroke")
	glow.Name = "CashPopGlow"
	glow.Color = Color3.fromRGB(40, 200, 80)
	glow.Thickness = 1.4
	glow.Transparency = 0.35
	glow.Parent = label

	local rise = ManualDropperConfig.PopupRiseStuds or 3.2
	local dur = ManualDropperConfig.PopupDuration or 0.55
	task.spawn(function()
		local steps = 10
		for i = 1, steps do
			if not anchor.Parent then
				return
			end
			local t = i / steps
			anchor.CFrame = CFrame.new(at + Vector3.new(0, 2.2 + rise * t, 0))
			label.TextTransparency = t * 0.85
			label.TextStrokeTransparency = 0.35 + t * 0.55
			task.wait(dur / steps)
		end
		anchor:Destroy()
	end)

	pcall(function()
		if VisualAssetService and VisualAssetService.PlayMoneyBagFX then
			VisualAssetService.PlayMoneyBagFX(at + Vector3.new(0, 1.5, 0), parent)
		end
	end)
end

local function tryAward(player: Player, dropper: BasePart)
	if not ManualDropperConfig.Enabled then
		return
	end
	if not player or not player.Parent then
		return
	end
	local plotId = dropper:GetAttribute("PlotId")
	if not ownsPlot(player, plotId) then
		return
	end

	local key = cooldownKey(player, dropper)
	local now = os.clock()
	local cd = ManualDropperConfig.CooldownSeconds or 0.35
	local last = lastAwardAt[key]
	if last and (now - last) < cd then
		return
	end

	if RateLimitService and RateLimitService.Allow then
		local rate = ManualDropperConfig.RateLimitRate or 4
		local burst = ManualDropperConfig.RateLimitBurst or 3
		if not RateLimitService.Allow(player, "manual_dropper", rate, burst) then
			return
		end
	end

	if not EconomyService or not EconomyService.AccruePendingCash then
		return
	end
	lastAwardAt[key] = now
	if not takeBudget(player.UserId, now) then
		if NotificationService and NotificationService.NotifyThrottled then
			NotificationService.NotifyThrottled(
				player,
				ManualDropperConfig.BudgetEmptyToast or "Cash drop is recharging",
				"Info",
				3,
				ManualDropperConfig.BudgetEmptyToastCooldown or 20,
				"manual_dropper_budget"
			)
		end
		return
	end
	local amount = pickAward()
	local ok = EconomyService.AccruePendingCash(player, amount, "manual_dropper")
	if ok then
		spawnFloatingCash(dropper.Parent or dropper, amount, dropper.Position)
		if TutorialService and TutorialService.Notify then
			TutorialService.Notify(player, "ManualDrop")
		end
	end
end

local function buildDropperKit(parent: Instance, name: string, worldPos: Vector3, plotId: number): BasePart
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		existing:SetAttribute("PlotId", plotId)
		return existing
	end

	local size = ManualDropperConfig.PartSize or Vector3.new(2.4, 1.2, 2.4)
	local pad = Instance.new("Part")
	pad.Name = name
	pad.Size = size
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanTouch = false
	pad.Material = Enum.Material.SmoothPlastic
	pad.Color = ManualDropperConfig.PartColor or Color3.fromRGB(40, 140, 70)
	pad.CFrame = CFrame.new(worldPos + Vector3.new(0, size.Y * 0.5 + 0.15, 0))
	pad:SetAttribute("PlotId", plotId)
	pad:SetAttribute("WE_ManualDropper", true)
	pad.Parent = parent
	CollectionService:AddTag(pad, TAG_DROPPER)

	local neon = Instance.new("Part")
	neon.Name = "DropNeon"
	neon.Size = Vector3.new(size.X * 0.7, 0.2, size.Z * 0.7)
	neon.Anchored = true
	neon.CanCollide = false
	neon.Material = Enum.Material.Neon
	neon.Color = ManualDropperConfig.NeonAccentColor or Color3.fromRGB(90, 255, 120)
	neon.CFrame = pad.CFrame * CFrame.new(0, size.Y * 0.5 + 0.05, 0)
	neon.Parent = pad

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(100, 255, 130)
	light.Brightness = 0.7
	light.Range = 10
	light.Parent = pad

	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_DropperLabel"
	bb.Size = UDim2.fromOffset(140, 32)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 55
	bb.Parent = pad
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(12, 28, 16)
	label.BackgroundTransparency = 0.25
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(100, 255, 140)
	local shown = ManualDropperConfig.AwardAmount or ManualDropperConfig.MinAward or 10
	label.Text = (ManualDropperConfig.BillboardLabel or "CLICK · $") .. tostring(shown)
	label.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local click = Instance.new("ClickDetector")
	click.Name = "DropClick"
	click.MaxActivationDistance = ManualDropperConfig.PromptMaxDistance or 12
	click.Parent = pad

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DropPrompt"
	prompt.ActionText = ManualDropperConfig.PromptActionText or "Grab Cash"
	prompt.ObjectText = ManualDropperConfig.PromptObjectText or "Cash Drop"
	prompt.HoldDuration = ManualDropperConfig.PromptHoldDuration or 0
	prompt.MaxActivationDistance = ManualDropperConfig.PromptMaxDistance or 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	return pad
end

local function wireDropper(pad: BasePart)
	if wired[pad] then
		return
	end
	wired[pad] = true

	local click = pad:FindFirstChild("DropClick")
	if click and click:IsA("ClickDetector") then
		click.MouseClick:Connect(function(player: Player)
			tryAward(player, pad)
		end)
	end
	local prompt = pad:FindFirstChild("DropPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player: Player)
			tryAward(player, pad)
		end)
	end
end

local function groundYForPlot(plotFolder: Instance, fallbackY: number): number
	local plotPad = plotFolder:FindFirstChild("PlotPad")
	if plotPad and plotPad:IsA("BasePart") then
		return plotPad.Position.Y + plotPad.Size.Y * 0.5
	end
	return fallbackY
end

local function ensureDropperNearCollector(collector: BasePart)
	local plotId = collector:GetAttribute("PlotId")
	if typeof(plotId) ~= "number" then
		return
	end
	local parent = collector.Parent or collector
	local offset = ManualDropperConfig.CollectorOffset or Vector3.new(-5.5, 0, 4)
	local gy = collector.Position.Y - collector.Size.Y * 0.5
	local plotFolder = parent.Parent
	if plotFolder then
		gy = groundYForPlot(plotFolder, gy)
	end
	local pos = Vector3.new(collector.Position.X + offset.X, gy, collector.Position.Z + offset.Z)
	local pad = buildDropperKit(parent, "ManualDropper_Collector", pos, plotId)
	wireDropper(pad)
end

local function ensureDropperNearYard(plotFolder: Instance, plotId: number)
	local yard = plotFolder:FindFirstChild("TrainingYard")
	if not yard then
		return
	end
	local anchor = yard:FindFirstChild("YardEarnAnchor")
		or yard:FindFirstChild("YardAnchor")
		or yard:FindFirstChildWhichIsA("BasePart", true)
	if not anchor or not anchor:IsA("BasePart") then
		return
	end
	local offset = ManualDropperConfig.YardOffset or Vector3.new(6, 0, -4)
	local gy = groundYForPlot(plotFolder, anchor.Position.Y - 6)
	local pos = Vector3.new(anchor.Position.X + offset.X, gy, anchor.Position.Z + offset.Z)
	local pad = buildDropperKit(yard, "ManualDropper_Yard", pos, plotId)
	wireDropper(pad)
end

local function scanPlots()
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	if not setup then
		return
	end
	local bases = setup:FindFirstChild("Bases")
	if not bases then
		return
	end
	for _, plotFolder in ipairs(bases:GetChildren()) do
		if plotFolder:IsA("Folder") or plotFolder:IsA("Model") then
			local plotIdAttr = plotFolder:GetAttribute("PlotId")
			local plotId: number? = if typeof(plotIdAttr) == "number" then plotIdAttr else tonumber(string.match(plotFolder.Name, "%d+"))
			if typeof(plotId) == "number" then
				ensureDropperNearYard(plotFolder, plotId)
			end
		end
	end
end

function ManualDropperService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	RateLimitService = deps.RateLimitService
	VisualAssetService = deps.VisualAssetService
	TutorialService = deps.TutorialService
	NotificationService = deps.NotificationService

	if not ManualDropperConfig.Enabled then
		print("[WAR EMPIRE] ManualDropperService disabled by config")
		return
	end

	for _, inst in ipairs(CollectionService:GetTagged(TAG_COLLECTOR)) do
		if inst:IsA("BasePart") then
			ensureDropperNearCollector(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG_COLLECTOR):Connect(function(inst)
		if inst:IsA("BasePart") then
			task.defer(function()
				ensureDropperNearCollector(inst)
			end)
		end
	end)

	for _, inst in ipairs(CollectionService:GetTagged(TAG_DROPPER)) do
		if inst:IsA("BasePart") then
			wireDropper(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG_DROPPER):Connect(function(inst)
		if inst:IsA("BasePart") then
			wireDropper(inst)
		end
	end)

	scanPlots()
	task.spawn(function()
		for _ = 1, 15 do
			task.wait(1)
			scanPlots()
			for _, inst in ipairs(CollectionService:GetTagged(TAG_COLLECTOR)) do
				if inst:IsA("BasePart") then
					ensureDropperNearCollector(inst)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		local prefix = tostring(userId) .. "|"
		for key in pairs(lastAwardAt) do
			if string.sub(key, 1, #prefix) == prefix then
				lastAwardAt[key] = nil
			end
		end
		-- Budget refills fully within an hour; drop it then unless the player came back.
		task.delay(3600, function()
			if not Players:GetPlayerByUserId(userId) then
				budgets[userId] = nil
			end
		end)
	end)

	print("[WAR EMPIRE] ManualDropperService ready (click/prompt → PendingCash)")
end

return ManualDropperService
