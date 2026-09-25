--!strict
--[[
	Early-game manual cash droppers at each plot (Money Collector + Training Yard).
	ClickDetector / ProximityPrompt → AccruePendingCash. Server cooldown + rate limit.

	v71 (HUD v70 spec §5): the "$15" tag and the "+$15" pop are Shared/Util/WorldLabel labels owned by the plot's
	owner (the client filter hides them for everyone else), stud-scaled, never AlwaysOnTop. The plate keeps its
	glow but no PointLight (light budget).

	streaming2 lane C1 (F5): while Workspace.StreamingEnabled is on, the owner's plate position is stamped on the
	Player as WE_DropperPos (the ATM-side plate, else the Training Yard one), like UpgradePadService's
	WE_ConsolePos_<sid> and BusinessService's WE_AtmPos, so the tutorial beam has an end while the plate is streamed
	out on that client. Stamped on plot ready and kept right by the 2 s owner sync (hand-outs, late claims, release,
	rebuilt plates). Streaming off: no hook, no attribute (HEAD behaviour).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ManualDropperConfig = require(Shared.Configs.ManualDropperConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

local ManualDropperService = {}

local DataService: any = nil
local EconomyService: any = nil
local RateLimitService: any = nil
local VisualAssetService: any = nil
local TutorialService: any = nil
local NotificationService: any = nil
local BaseService: any = nil

local TAG_COLLECTOR = Constants.Tags.MoneyCollector
local TAG_DROPPER = "WE_ManualDropper"

-- owner-only tag on a plate nobody owns yet: a UserId no player has (the client filter hides it for everyone)
local NOBODY = -1

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

-- "+$15" rising from the plate — only the player who grabbed it sees it (owner-only WorldLabel)
local function spawnFloatingCash(dropper: BasePart, amount: number, ownerUserId: number)
	local top = dropper.Size.Y * 0.5
	local bb = WorldLabel.Create(dropper, string.format("+$%d", amount), {
		Name = "CashPop",
		Color = Color3.fromRGB(80, 255, 120),
		TextSize = 20,
		Studs = Vector2.new(3, 1.2),
		Offset = Vector3.new(0, top + 1.2, 0),
		MaxDistance = 30,
		OwnerUserId = ownerUserId,
	})
	local label = bb:FindFirstChild("Title")
	if label and label:IsA("TextLabel") then
		-- Competitor-style $ pop: dark green glow outline (replaces the ink text stroke on this label)
		local glow = Instance.new("UIStroke")
		glow.Name = "CashPopGlow"
		glow.Color = Color3.fromRGB(8, 36, 14)
		glow.Thickness = 1.4
		glow.Parent = label
	end

	local rise = ManualDropperConfig.PopupRiseStuds or 3.2
	local dur = ManualDropperConfig.PopupDuration or 0.55
	task.spawn(function()
		local steps = 6
		for i = 1, steps do
			if not bb.Parent then
				return
			end
			local t = i / steps
			bb.StudsOffsetWorldSpace = Vector3.new(0, top + 1.2 + rise * t, 0)
			if label and label:IsA("TextLabel") then
				label.TextTransparency = t * 0.85
			end
			task.wait(dur / steps)
		end
		bb:Destroy()
	end)

	pcall(function()
		if VisualAssetService and VisualAssetService.PlayMoneyBagFX then
			VisualAssetService.PlayMoneyBagFX(dropper.Position + Vector3.new(0, 1.5, 0), dropper.Parent or dropper)
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
		spawnFloatingCash(dropper, amount, player.UserId)
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

	-- v71: no PointLight (the neon plate is the glow; light budget) and an owner-only "$15" tag
	local shown = ManualDropperConfig.AwardAmount or ManualDropperConfig.MinAward or 10
	WorldLabel.Create(pad, (ManualDropperConfig.BillboardLabel or "$") .. tostring(shown), {
		Name = "WE_DropperLabel",
		Color = Color3.fromRGB(100, 255, 140),
		Studs = ManualDropperConfig.LabelStuds,
		MaxDistance = ManualDropperConfig.LabelMaxDistance,
		OwnerUserId = NOBODY, -- syncTagOwners hands it to the plot owner (≤ 2 s)
	})

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

-- Older server builds left a PointLight and a carded price tag on the plate: strip / rebuild them once.
local function upgradeLegacyKit(pad: BasePart)
	local light = pad:FindFirstChildOfClass("PointLight")
	if light then
		light:Destroy()
	end
	local tag = pad:FindFirstChild("WE_DropperLabel")
	if tag and not tag:FindFirstChild("Title") then
		tag:Destroy()
		local shown = ManualDropperConfig.AwardAmount or ManualDropperConfig.MinAward or 10
		WorldLabel.Create(pad, (ManualDropperConfig.BillboardLabel or "$") .. tostring(shown), {
			Name = "WE_DropperLabel",
			Color = Color3.fromRGB(100, 255, 140),
			Studs = ManualDropperConfig.LabelStuds,
			MaxDistance = ManualDropperConfig.LabelMaxDistance,
			OwnerUserId = NOBODY,
		})
	end
end

-- The tag belongs to the plot owner: follow plot hand-outs (join / leave / late claim). ≤ 12 plates, 0.5 Hz.
local function syncTagOwners()
	if not (BaseService and BaseService.GetOwnerUserId) then
		return
	end
	for pad in pairs(wired) do
		if pad.Parent then
			local tag = pad:FindFirstChild("WE_DropperLabel")
			local plotId = pad:GetAttribute("PlotId")
			if tag and tag:IsA("BillboardGui") and typeof(plotId) == "number" then
				local owner = BaseService.GetOwnerUserId(plotId)
				WorldLabel.SetOwner(tag, if typeof(owner) == "number" and owner ~= 0 then owner else NOBODY)
			end
		else
			wired[pad] = nil
		end
	end
end

-- C1 F5: the tutorial's dropper position (see the header). Only while streaming is on (a place setting).
local ATTR_DROPPER_POS = "WE_DropperPos"

local function streamingOn(): boolean
	return Workspace.StreamingEnabled == true
end

-- the plate the tutorial points at on a plot: the one beside the ATM, else the Training Yard one
local function dropperPosOf(plotId: number): Vector3?
	local best: BasePart? = nil
	for pad in pairs(wired) do
		if pad.Parent and pad:GetAttribute("PlotId") == plotId and (best == nil or pad.Name == "ManualDropper_Collector") then
			best = pad
		end
	end
	return if best then best.Position else nil
end

local function stampDropperPos(player: Player, plotId: number?)
	if player.Parent == nil or not streamingOn() then
		return
	end
	local pos = if plotId ~= nil then dropperPosOf(plotId) else nil
	if player:GetAttribute(ATTR_DROPPER_POS) ~= pos then
		player:SetAttribute(ATTR_DROPPER_POS, pos)
	end
end

-- every player's stamp follows the plot they own now (nil when they have none)
local function syncDropperStamps()
	if not (streamingOn() and BaseService and BaseService.GetOwnedPlotId) then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, plotId = pcall(BaseService.GetOwnedPlotId, player)
		stampDropperPos(player, if ok and typeof(plotId) == "number" then plotId else nil)
	end
end

local function wireDropper(pad: BasePart)
	if wired[pad] then
		return
	end
	wired[pad] = true
	upgradeLegacyKit(pad)

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

-- v70: the plot's rotation (PlotPad carries the plot yaw, BaseLayout.PlotCFrame); identity when there is no pad
local function rotOf(plotFolder: Instance?): CFrame
	local plotPad = plotFolder and plotFolder:FindFirstChild("PlotPad")
	if plotPad and plotPad:IsA("BasePart") then
		return plotPad.CFrame.Rotation
	end
	return CFrame.identity
end

-- v70: plot-local XZ offset turned with the plot, added to a world base point, at ground height gy
local function offsetPos(plotFolder: Instance?, base: Vector3, offset: Vector3, gy: number): Vector3
	local w = rotOf(plotFolder):VectorToWorldSpace(Vector3.new(offset.X, 0, offset.Z))
	return Vector3.new(base.X + w.X, gy, base.Z + w.Z)
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
	local pos = offsetPos(plotFolder, collector.Position, offset, gy)
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
	local pos = offsetPos(plotFolder, anchor.Position, offset, gy)
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
	BaseService = deps.BaseService

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
		task.defer(syncTagOwners)
		-- Budget refills fully within an hour; drop it then unless the player came back.
		task.delay(3600, function()
			if not Players:GetPlayerByUserId(userId) then
				budgets[userId] = nil
			end
		end)
	end)

	-- C1 F5: the tutorial's dropper position on the owner (streaming only; see the header)
	if streamingOn() and BaseService and BaseService.OnPlotReady then
		BaseService.OnPlotReady(stampDropperPos)
	end

	task.spawn(function()
		while true do
			task.wait(2)
			syncTagOwners()
			syncDropperStamps()
		end
	end)

	print("[WAR EMPIRE] ManualDropperService ready (prompt / ClickDetector → PendingCash)")
end

return ManualDropperService
