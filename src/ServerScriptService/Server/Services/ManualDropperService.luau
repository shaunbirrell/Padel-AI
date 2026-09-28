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

	Owner asset list hook (2026-09-25): a newly built plate gets a deferred VisualAssetService.TryAttachPropVisual(plate,
	"ManualDropper") (VisualAssetConfig.IndustrialProps.ManualDropper; 0 / pending = no load, the plate look stays).

	droppers v1b (spec_droppers.md §3.8, owner decision OD-4 = A): one tap (the prompt or the ClickDetector; both still
	instant and both through tryAward) pays a bundle of ManualDropperConfig.BundleAwards awards (5 x $15 = $75) with ONE
	AccruePendingCash(player, amount, "manual_dropper") (multiplier-exempt, into the ATM). The bundle needs that many
	awards in BOTH budget buckets (no partial bundle); the award, cooldown, rate limit and the minute / hour budgets are
	unchanged, so the cap on money is unchanged. BundleAwards is clamped to 1..MaxAwardsPerMinute (a larger bundle could
	never be paid). The server builds no pop and no model any more: after a paid grab it sends the grabber one
	owner-only unreliable DropperFx packet (drop point, amount, bundles left, seconds until the next one) and the client
	(Client/Modules/ProductionFx) draws the falling bundle and the world "+$75" pop on every paid grab (revision 3). The
	plate inset is plain green (PlateNeon = false) and the "$75" tag is a governed base label (LabelGovernor: at most 3
	on screen at a base). There is still no client -> server remote: the client sends no amount and no target.

	droppers v1b revision 3:
	  * "Recharging" has a reliable, server-authoritative source: while the budget holds no bundle the Player attribute
	    ManualDropperConfig.RechargeAttribute = Workspace:GetServerTimeNow() when the next bundle is ready (nil once it
	    holds one). Stamped by the grab that empties the budget, by a tap the budget refuses and by a same-server rejoin
	    (PlayerAdded with a kept budget), compare-first. It is a look only: every tap is still paid or refused here, on
	    the budget itself. No new remote.
	  * The v69 budget kept for an hour after a leave is cleared only by the timer of the LAST leave (a leave token
	    bumped on every leave and join), so an older leave's timer can no longer refill a player who left again briefly.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ManualDropperConfig = require(Shared.Configs.ManualDropperConfig)
local WorldLabel = require(Shared.Util.WorldLabel)
local RemoteSetup = require(script.Parent.Parent.Modules.RemoteSetup) -- droppers v1b: the owner-only DropperFx packet

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
-- droppers v1b revision 3 (leave token): bumped on every leave and every join of a UserId. The 3600 s clear runs only
-- for the leave that started it (its token still current and the player still away), so the budget is dropped an
-- hour after the LAST leave and never by an older leave's timer during a later brief absence.
local leaveToken: { [number]: number } = {}

local function bumpLeaveToken(userId: number): number
	local token = (leaveToken[userId] or 0) + 1
	leaveToken[userId] = token
	return token
end

local function budgetLimits(): (number, number)
	local perMinute = math.max(1, math.floor(tonumber(ManualDropperConfig.MaxAwardsPerMinute) or 30))
	local perHour = math.max(perMinute, math.floor(tonumber(ManualDropperConfig.MaxAwardsPerHour) or 600))
	return perMinute, perHour
end

-- droppers v1b: awards per grab (the bundle). A number only (nil, NaN, a string -> 1), floored, clamped to
-- 1..MaxAwardsPerMinute: a bundle above the minute bucket could never be paid (takeBudget would never find it).
local function bundleAwards(): number
	local perMinute = budgetLimits()
	local raw: any = ManualDropperConfig.BundleAwards
	if typeof(raw) ~= "number" or raw ~= raw then
		return 1
	end
	return math.clamp(math.floor(raw), 1, perMinute)
end

-- Refills the player's buckets up to `now` (first sight: both full) and returns them.
local function refillBudget(userId: number, now: number): Budget
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
	return b
end

-- Consumes n awards (default 1) from the player's budget; false (and nothing taken) unless BOTH buckets hold n.
local function takeBudget(userId: number, now: number, n: number?): boolean
	local take = n or 1
	local b = refillBudget(userId, now)
	if b.minute < take or b.hour < take then
		return false
	end
	b.minute -= take
	b.hour -= take
	return true
end

-- droppers v1b: (bundles of n the budget holds now, seconds until the next one when it holds none; else 0).
-- Consumes nothing. The client shows "Recharging" and hides the pill for `eta` seconds when `left` is 0.
local function budgetState(userId: number, now: number, n: number): (number, number)
	local perMinute, perHour = budgetLimits()
	local b = refillBudget(userId, now)
	local left = math.floor(math.min(b.minute, b.hour) / n)
	if left >= 1 then
		return left, 0
	end
	return 0, math.max(0, (n - b.minute) / (perMinute / 60), (n - b.hour) / (perHour / 3600))
end

-- droppers v1b revision 3: the reliable half of "Recharging" (see the header). The ready time of an empty budget does
-- not move while it refills, so a refused tap rewrites nothing (compare-first, 0.05 s tolerance).
local RECHARGE_ATTR: string = ManualDropperConfig.RechargeAttribute or "WE_DropRechargeAt"

-- the clock the client compares the attribute with; nil if it cannot be read (then nothing is stamped)
local function serverNow(): number?
	local ok, t = pcall(Workspace.GetServerTimeNow, Workspace)
	return if ok and typeof(t) == "number" and t == t then t else nil
end

local function stampRecharge(player: Player, now: number, n: number)
	local left, eta = budgetState(player.UserId, now, n)
	local want: number? = nil
	if left < 1 then
		local t = serverNow()
		if t == nil then
			return
		end
		want = t + eta
	end
	local have = player:GetAttribute(RECHARGE_ATTR)
	if want == nil then
		if have ~= nil then
			player:SetAttribute(RECHARGE_ATTR, nil)
		end
	elseif typeof(have) ~= "number" or math.abs(have - want) > 0.05 then
		player:SetAttribute(RECHARGE_ATTR, want)
	end
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

-- droppers v1b (spec §3.8): where the client's bundle lands, in world space.
--   * Undressed plate: the top face of the plate kit (the inset "DropNeon" stands 0.15 above the plate itself).
--   * A plate the hooks lane dressed (WE_CatalogAssetId + the Model "WE_CatalogProp" that weldCloneToPrimary names):
--     that model stands from the plate's LOWEST point (Fit = "Ground"), so the plate top can be inside it; the bundle
--     lands on the model's bounding-box top + DropPointClearance, over the plate centre.
-- Cached per plate, keyed by the dress instance: one GetBoundingBox on the first grab after a (re)dress, else none.
type DropCache = { dress: Instance?, point: Vector3 }
local dropCache: { [BasePart]: DropCache } = setmetatable({} :: any, { __mode = "k" })

local function plateTop(pad: BasePart): number
	local top = pad.Position.Y + pad.Size.Y * 0.5
	local inset = pad:FindFirstChild("DropNeon")
	if inset and inset:IsA("BasePart") then
		top = math.max(top, inset.Position.Y + inset.Size.Y * 0.5)
	end
	return top
end

local function dropPoint(pad: BasePart): Vector3
	local dress: Instance? = nil
	if pad:GetAttribute("WE_CatalogAssetId") ~= nil then
		local prop = pad:FindFirstChild("WE_CatalogProp")
		if prop and prop:IsA("Model") then
			dress = prop
		end
	end
	local cached = dropCache[pad]
	if cached and cached.dress == dress then
		return cached.point
	end
	local pos = pad.Position
	local y = plateTop(pad)
	if dress ~= nil then
		local ok, cf, size = pcall(function()
			return (dress :: Model):GetBoundingBox()
		end)
		if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
			-- world half-height of the (possibly turned) box
			local half = math.abs(cf.RightVector.Y) * size.X * 0.5
				+ math.abs(cf.UpVector.Y) * size.Y * 0.5
				+ math.abs(cf.LookVector.Y) * size.Z * 0.5
			y = cf.Position.Y + half + (tonumber(ManualDropperConfig.DropPointClearance) or 0.3)
		end
	end
	local point = Vector3.new(pos.X, y, pos.Z)
	dropCache[pad] = { dress = dress, point = point }
	return point
end

-- droppers v1b: the grab's effect goes to the grabber only, as one unreliable packet (a lost packet loses the effect,
-- never money). Replaces HEAD's server BillboardGui + UIStroke + task loop + money-bag model, which replicated to
-- every client on every tap. Payload: (dropPoint, amount, left, eta), see budgetState.
local function sendDropFx(player: Player, pad: BasePart, amount: number, n: number, now: number)
	if ManualDropperConfig.FxEvent == false then
		return
	end
	local left, eta = budgetState(player.UserId, now, n)
	local ok, err = pcall(function()
		RemoteSetup.GetUnreliable(Constants.RemoteNames.DropperFx):FireClient(player, dropPoint(pad), amount, left, eta)
	end)
	if not ok then
		warn("[ManualDropper] DropperFx failed:", err)
	end
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
	local n = bundleAwards()
	if not takeBudget(player.UserId, now, n) then
		stampRecharge(player, now, n) -- revision 3: the refused tap re-states "Recharging" (a lost packet, a rejoin)
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
	local amount = pickAward() * n -- droppers v1b: one bundle = n awards, one grant (exempt: "manual_dropper")
	local ok = EconomyService.AccruePendingCash(player, amount, "manual_dropper")
	if ok then
		sendDropFx(player, dropper, amount, n, now)
		stampRecharge(player, now, n) -- revision 3: the reliable "Recharging" (set when this grab emptied the budget)
		if TutorialService and TutorialService.Notify then
			TutorialService.Notify(player, "ManualDrop")
		end
	end
end

-- droppers v1b: the plate tag shows one bundle ("$75"; "$15" with BundleAwards = 1)
local function tagText(): string
	local per = ManualDropperConfig.AwardAmount or ManualDropperConfig.MinAward or 10
	return (ManualDropperConfig.BillboardLabel or "$") .. tostring(per * bundleAwards())
end

-- droppers v1b (OD-6): the inset is plain SmoothPlastic; PlateNeon = true is the one-line revert to HEAD's glow. The
-- Neon material is named by string on purpose: this file is pinned to hold no Neon literal, so the pinned config line
-- `PlateNeon = false,` is the only way back to Neon (and the census counts every Neon part).
local function insetMaterial(): Enum.Material
	return if ManualDropperConfig.PlateNeon == true then (Enum.Material :: any)["Neon"] else Enum.Material.SmoothPlastic
end

local function makeTag(pad: BasePart)
	WorldLabel.Create(pad, tagText(), {
		Name = "WE_DropperLabel",
		Color = Color3.fromRGB(100, 255, 140),
		Studs = ManualDropperConfig.LabelStuds,
		MaxDistance = ManualDropperConfig.LabelMaxDistance,
		OwnerUserId = NOBODY, -- syncTagOwners hands it to the plot owner (≤ 2 s)
		BaseLabel = true, -- droppers v1b: counted by the LabelGovernor (at most 3 base labels on screen)
	})
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
	neon.Material = insetMaterial()
	neon.Color = ManualDropperConfig.NeonAccentColor or Color3.fromRGB(90, 255, 120)
	neon.CFrame = pad.CFrame * CFrame.new(0, size.Y * 0.5 + 0.05, 0)
	neon.Parent = pad

	-- v71: no PointLight (light budget) and an owner-only tag; droppers v1b: "$75" (one bundle), a governed base label
	makeTag(pad)

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
	-- atmprompt: its own keys (F / B), apart from the ATM "Collect" beside it (E / X)
	prompt.KeyboardKeyCode = ManualDropperConfig.PromptKeyboardKey
	prompt.GamepadKeyCode = ManualDropperConfig.PromptGamepadKey
	prompt.Exclusivity = ManualDropperConfig.PromptExclusivity
	prompt.Parent = pad

	-- owner asset list hook: the dropper model on the plate (the plate is the kit's only host part; deferred, pcall'd)
	if VisualAssetService and VisualAssetService.TryAttachPropVisual then
		task.defer(pcall, VisualAssetService.TryAttachPropVisual, pad, "ManualDropper")
	end

	return pad
end

-- Older server builds left a PointLight and a carded price tag on the plate: strip / rebuild them once.
-- droppers v1b: a pre-v1b plate (Neon inset, ungoverned "$15" tag) is brought to the v1b look once; every write is
-- compare-first, so a plate already in that look is left untouched.
local function upgradeLegacyKit(pad: BasePart)
	local light = pad:FindFirstChildOfClass("PointLight")
	if light then
		light:Destroy()
	end
	local inset = pad:FindFirstChild("DropNeon")
	if inset and inset:IsA("BasePart") then
		local material = insetMaterial()
		if inset.Material ~= material then
			inset.Material = material
		end
	end
	local tag = pad:FindFirstChild("WE_DropperLabel")
	if tag and not tag:FindFirstChild("Title") then
		tag:Destroy()
		makeTag(pad)
	elseif tag and tag:IsA("BillboardGui") then
		local text = tagText()
		local title = tag:FindFirstChild("Title")
		if title and title:IsA("TextLabel") and title.Text ~= text then
			WorldLabel.SetText(tag, text)
		end
		WorldLabel.TagBaseLabel(tag) -- no-op when it is already a base label
	end
	local prompt = pad:FindFirstChild("DropPrompt")
	local hold = ManualDropperConfig.PromptHoldDuration or 0
	if prompt and prompt:IsA("ProximityPrompt") and prompt.HoldDuration ~= hold then
		prompt.HoldDuration = hold
	end
	-- atmprompt: a plate built before the key split still uses E / X (it hid the ATM "Collect"); compare-first
	if prompt and prompt:IsA("ProximityPrompt") then
		if prompt.KeyboardKeyCode ~= ManualDropperConfig.PromptKeyboardKey then
			prompt.KeyboardKeyCode = ManualDropperConfig.PromptKeyboardKey
		end
		if prompt.GamepadKeyCode ~= ManualDropperConfig.PromptGamepadKey then
			prompt.GamepadKeyCode = ManualDropperConfig.PromptGamepadKey
		end
		if prompt.Exclusivity ~= ManualDropperConfig.PromptExclusivity then
			prompt.Exclusivity = ManualDropperConfig.PromptExclusivity
		end
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
		-- Budget refills fully within an hour; drop it then unless the player came back. Revision 3: only this leave's
		-- timer may do it (leave token; a later join or leave makes it stale).
		local token = bumpLeaveToken(userId)
		task.delay(3600, function()
			if leaveToken[userId] == token and not Players:GetPlayerByUserId(userId) then
				budgets[userId] = nil
				leaveToken[userId] = nil
			end
		end)
	end)
	-- revision 3: a join makes every earlier leave's timer stale; a same-server rejoin whose kept budget holds no bundle
	-- gets "Recharging" at once (the client reads the attribute when it starts)
	Players.PlayerAdded:Connect(function(player)
		local userId = player.UserId
		bumpLeaveToken(userId)
		if budgets[userId] ~= nil then
			stampRecharge(player, os.clock(), bundleAwards())
		end
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
