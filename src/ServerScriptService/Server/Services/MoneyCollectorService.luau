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
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local ServerModules = script.Parent.Parent.Modules
local RemoteSetup = require(ServerModules.RemoteSetup)

local MoneyCollectorService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local MonetizationService: any = nil
local TutorialService: any = nil
local RateLimitService: any = nil

local TAG = Constants.Tags.MoneyCollector
local OVERLAP_MARGIN = 3.5
local SPATIAL_INTERVAL = 0.25
local AUTO_COLLECT_INTERVAL = 2.0

local lastOverlap: { [string]: boolean } = {}
local billboardCache: { [BasePart]: BillboardGui } = {}
-- thiefUserId → victimUserId → cooldownUntil (os.clock)
local atmRaidCooldownUntil: { [number]: { [number]: number } } = {}

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

local function hasDoubleCash(player: Player): boolean
	if MonetizationService and MonetizationService.PlayerOwnsEntitlement then
		if MonetizationService.PlayerOwnsEntitlement(player, "DoubleCash") then
			return true
		end
	end
	if MonetizationService and MonetizationService.PlayerOwnsGamePass then
		if MonetizationService.PlayerOwnsGamePass(player, "DoubleCash") then
			return true
		end
	end
	local profile = DataService.GetProfile(player)
	if profile and typeof(profile.Entitlements) == "table" and profile.Entitlements.DoubleCash == true then
		return true
	end
	return false
end

local function ensureBillboard(part: BasePart): BillboardGui
	local existing = billboardCache[part]
	if existing and existing.Parent then
		return existing
	end
	local oldBb = part:FindFirstChild("WE_CollectorBillboard")
	if oldBb and oldBb:IsA("BillboardGui") then
		billboardCache[part] = oldBb
		return oldBb
	end
	-- ATM-like green digit billboard
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_CollectorBillboard"
	bb.Size = UDim2.fromOffset(220, 72)
	bb.StudsOffset = Vector3.new(0, 7.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 100
	bb.Parent = part

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(18, 22, 20)
	backdrop.BackgroundTransparency = 0.05
	backdrop.BorderSizePixel = 0
	backdrop.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = backdrop
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 200, 100)
	stroke.Thickness = 2.5
	stroke.Parent = backdrop

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -10, 0, 18)
	title.Position = UDim2.fromOffset(5, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextColor3 = Color3.fromRGB(200, 210, 200)
	title.Text = "COLLECT · ATM · Codes in Settings"
	title.Parent = backdrop

	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.Size = UDim2.new(1, -10, 0, 42)
	amount.Position = UDim2.fromOffset(5, 24)
	amount.BackgroundColor3 = Color3.fromRGB(6, 48, 22)
	amount.BackgroundTransparency = 0.2
	amount.Font = Enum.Font.Code
	amount.TextScaled = true
	amount.TextColor3 = Color3.fromRGB(70, 255, 120)
	amount.Text = "$0"
	amount.Parent = backdrop
	local ac = Instance.new("UICorner")
	ac.CornerRadius = UDim.new(0, 4)
	ac.Parent = amount

	billboardCache[part] = bb
	return bb
end

local function syncAtmScreen(part: BasePart, pending: number)
	local folder = part.Parent
	if not folder then
		return
	end
	local screen = folder:FindFirstChild("CollectorScreen")
	if not (screen and screen:IsA("BasePart")) then
		return
	end
	local sg = screen:FindFirstChild("WE_ATMScreen")
	local digits = sg and sg:FindFirstChild("Digits")
	if digits and digits:IsA("TextLabel") then
		digits.Text = string.format("$%s", tostring(math.floor(pending)))
		digits.TextColor3 = if pending > 0 then Color3.fromRGB(70, 255, 120) else Color3.fromRGB(40, 120, 70)
	end
	local light = part:FindFirstChild("ATMGlow")
	if light and light:IsA("PointLight") then
		light.Color = Color3.fromRGB(120, 255, 90)
		if pending >= 500 then
			light.Brightness = 1.4
			light.Range = 18
		elseif pending > 0 then
			light.Brightness = 0.9
			light.Range = 14
		else
			light.Brightness = 0.35
			light.Range = 10
		end
	end
end

local function refreshBillboard(part: BasePart, pending: number)
	local bb = ensureBillboard(part)
	local amount = bb:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		if pending > 0 then
			amount.Text = string.format("$%s", tostring(math.floor(pending)))
			amount.TextColor3 = Color3.fromRGB(70, 255, 120)
		else
			amount.Text = "$0"
			amount.TextColor3 = Color3.fromRGB(100, 140, 110)
		end
	end
	syncAtmScreen(part, pending)
end

local function pointInPart(hrpPos: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(hrpPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X + OVERLAP_MARGIN
		and math.abs(localPos.Z) <= half.Z + OVERLAP_MARGIN
		and localPos.Y >= -half.Y - 4
		and localPos.Y <= half.Y + 10
end

local function getAtmRaidConfig()
	local cfg = EconomyConfig.AtmRaid
	if not cfg or cfg.Enabled == false then
		return nil
	end
	return cfg
end

local function findOwnerByPlot(plotId: number): Player?
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.GetProfile(player)
		if profile and profile.BasePlotId == plotId then
			return player
		end
	end
	return nil
end

local function raidCooldownRemaining(thiefId: number, victimId: number): number
	local byVictim = atmRaidCooldownUntil[thiefId]
	if not byVictim then
		return 0
	end
	local untilT = byVictim[victimId]
	if not untilT then
		return 0
	end
	return math.max(0, untilT - os.clock())
end

local function raidOnCooldown(thiefId: number, victimId: number, _cooldownSec: number): boolean
	return raidCooldownRemaining(thiefId, victimId) > 0
end

local function pushAtmRaidState(player: Player, payload: { [string]: any })
	local remote = RemoteSetup.Get(Constants.RemoteNames.AtmRaidStateUpdate)
	if remote and remote:IsA("RemoteEvent") then
		(remote :: RemoteEvent):FireClient(player, payload)
	end
end

local function setRaidCooldown(thiefId: number, victimId: number, cooldownSec: number)
	local byVictim = atmRaidCooldownUntil[thiefId]
	if not byVictim then
		byVictim = {}
		atmRaidCooldownUntil[thiefId] = byVictim
	end
	byVictim[victimId] = os.clock() + cooldownSec
end

--[[
	Enemy touches WE_MoneyCollector belonging to another player → steal 10% PendingCash.
	Server-authoritative; distance + rate-limit + per thief→victim cooldown.
]]
function MoneyCollectorService.TryAtmRaid(thief: Player, part: BasePart): (boolean, number)
	local cfg = getAtmRaidConfig()
	if not cfg then
		return false, 0
	end
	local plotId = part:GetAttribute("PlotId")
	if typeof(plotId) ~= "number" then
		return false, 0
	end
	local thiefProfile = DataService.GetProfile(thief)
	if not thiefProfile then
		return false, 0
	end
	-- Must not be owner
	if thiefProfile.BasePlotId ~= nil and thiefProfile.BasePlotId == plotId then
		return false, 0
	end
	local victim = findOwnerByPlot(plotId)
	if not victim or victim == thief then
		return false, 0
	end
	-- Distance check
	local character = thief.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return false, 0
	end
	local maxDist = cfg.MaxDistanceStuds or 14
	if (hrp.Position - part.Position).Magnitude > maxDist + OVERLAP_MARGIN then
		return false, 0
	end
	if RateLimitService and not RateLimitService.Allow(thief, "atm_raid", 1, 2) then
		return false, 0
	end
	local cooldownSec = cfg.AtmRaidCooldownSeconds or 60
	local remain = raidCooldownRemaining(thief.UserId, victim.UserId)
	if remain > 0 then
		if NotificationService then
			local cdToast = cfg.ToastCooldown or "ATM raid cooldown — %ds left"
			NotificationService.Notify(thief, string.format(cdToast, math.ceil(remain)), "Warn", 2.5)
		end
		pushAtmRaidState(thief, {
			CooldownRemaining = math.ceil(remain),
			CooldownTotal = cooldownSec,
			Success = false,
		})
		return false, 0
	end
	local victimPending = 0
	if EconomyService and EconomyService.GetPendingCash then
		victimPending = EconomyService.GetPendingCash(victim)
	else
		local vp = DataService.GetProfile(victim)
		victimPending = if vp then math.floor(tonumber((vp :: any).PendingCash) or 0) else 0
	end
	local minSteal = cfg.MinStealCash or 1
	if victimPending < minSteal then
		return false, 0
	end
	local fraction = cfg.StealFraction or 0.10
	local stealAmount = math.floor(victimPending * fraction)
	if stealAmount < minSteal then
		return false, 0
	end
	local transferred = 0
	if EconomyService and EconomyService.TransferPendingCash then
		transferred = EconomyService.TransferPendingCash(victim, thief, stealAmount)
	end
	if transferred <= 0 then
		return false, 0
	end
	setRaidCooldown(thief.UserId, victim.UserId, cooldownSec)
	if NotificationService then
		local thiefToast = cfg.ToastThief or "ATM RAID +$%d (10%%) from %s — 1m cooldown"
		local victimToast = cfg.ToastVictim or "ATM RAIDED −$%d (10%% stolen)"
		NotificationService.Notify(thief, string.format(thiefToast, transferred, victim.DisplayName), "Reward", 5)
		NotificationService.Notify(victim, string.format(victimToast, transferred), "Warn", 5)
	end
	pushAtmRaidState(thief, {
		CooldownRemaining = cooldownSec,
		CooldownTotal = cooldownSec,
		Success = true,
		Stolen = transferred,
		VictimName = victim.DisplayName,
	})
	pushAtmRaidState(victim, {
		CooldownRemaining = 0,
		CooldownTotal = cooldownSec,
		Success = false,
		Stolen = transferred,
		Raided = true,
	})
	return true, transferred
end

function MoneyCollectorService.Collect(player: Player): (boolean, number)
	if not EconomyService or not EconomyService.CollectPendingCash then
		return false, 0
	end
	local granted = EconomyService.CollectPendingCash(player)
	if granted > 0 then
		if NotificationService then
			NotificationService.Notify(player, string.format("Collected $%d", granted), "Collect", 3)
		end
		if TutorialService and TutorialService.Notify then
			TutorialService.Notify(player, "PassiveIncome")
		end
		-- v33: one-shot soft AutoCollect GamePass offer after first manual collect
		do
			local profile = DataService.GetProfile(player)
			local offerCfg = (MonetizationConfig :: any).AutoCollectOffer
			local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses.AutoCollect
			if (
				profile
				and offerCfg
				and gp
				and typeof(gp.Id) == "number"
				and gp.Id ~= 0
				and profile.AutoCollectOffered ~= true
				and not hasAutoCollect(player)
			) then
				profile.AutoCollectOffered = true
				DataService.MarkDirty(player)
				task.delay(tonumber(offerCfg.DelaySeconds) or 1.2, function()
					if not player.Parent then
						return
					end
					if hasAutoCollect(player) then
						return
					end
					local remote = RemoteSetup.Get(Constants.RemoteNames.AutoCollectOffer)
					if remote and remote:IsA("RemoteEvent") then
						(remote :: RemoteEvent):FireClient(player, {
							ProductKey = "AutoCollect",
							GamePassId = gp.Id,
							DisplayName = gp.DisplayName or "Auto Collect",
							RobuxPrice = gp.RobuxPrice,
						})
					end
					if NotificationService then
						NotificationService.Notify(
							player,
							"Tired of walking to the ATM? Auto Collect available",
							"Info",
							4.5
						)
					end
				end)
			end
		end
		-- v34: one-shot DoubleCash soft offer after meaningful collect (existing Id only; not spammy)
		do
			local profile = DataService.GetProfile(player)
			local offerCfg = (MonetizationConfig :: any).DoubleCashOffer
			local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses.DoubleCash
			local minCash = tonumber(offerCfg and offerCfg.MinCollectCash) or 2500
			-- Prefer after AutoCollect already teased/owned so we don't stack two toasts on first collect
			local acReady = profile and (profile.AutoCollectOffered == true or hasAutoCollect(player))
			if (
				profile
				and offerCfg
				and gp
				and typeof(gp.Id) == "number"
				and gp.Id ~= 0
				and granted >= minCash
				and acReady
				and profile.DoubleCashOffered ~= true
				and not hasDoubleCash(player)
			) then
				profile.DoubleCashOffered = true
				DataService.MarkDirty(player)
				task.delay(tonumber(offerCfg.DelaySeconds) or 1.8, function()
					if not player.Parent then
						return
					end
					if hasDoubleCash(player) then
						return
					end
					local remote = RemoteSetup.Get(Constants.RemoteNames.DoubleCashOffer)
					if remote and remote:IsA("RemoteEvent") then
						(remote :: RemoteEvent):FireClient(player, {
							ProductKey = "DoubleCash",
							GamePassId = gp.Id,
							DisplayName = gp.DisplayName or "2x Cash",
							RobuxPrice = gp.RobuxPrice,
						})
					end
					if NotificationService then
						NotificationService.Notify(
							player,
							"Big collect! Double your cash with 2x Cash",
							"Info",
							4.5
						)
					end
				end)
			end
		end
		pcall(function()
			local vas = require(script.Parent.VisualAssetService)
			local profile = DataService.GetProfile(player)
			local pos: Vector3? = nil
			local parent: Instance? = nil
			if profile and profile.BasePlotId ~= nil then
				for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
					if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == profile.BasePlotId then
						pos = inst.Position + Vector3.new(0, 4, 0)
						parent = inst.Parent
						break
					end
				end
			end
			if not pos then
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					pos = hrp.Position
				end
			end
			if pos and vas and vas.PlayMoneyBagFX then
				vas.PlayMoneyBagFX(pos, parent)
			end
		end)
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
	RateLimitService = deps.RateLimitService

	-- Touch + spatial collect
	local function tryCollectFromPart(player: Player, part: BasePart)
		local profile = DataService.GetProfile(player)
		if not profile then
			return
		end
		local plotId = part:GetAttribute("PlotId")
		-- Enemy ATM: attempt raid (10% PendingCash steal)
		if typeof(plotId) == "number" and (profile.BasePlotId == nil or plotId ~= profile.BasePlotId) then
			MoneyCollectorService.TryAtmRaid(player, part)
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
		task.defer(function()
			pcall(function()
				local vas = require(script.Parent.VisualAssetService)
				if vas and vas.TryAttachCollectorVisual then
					vas.TryAttachCollectorVisual(part)
				end
			end)
		end)
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
					if profile then
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

	Players.PlayerRemoving:Connect(function(player)
		atmRaidCooldownUntil[player.UserId] = nil
		-- Also drop entries where this player was victim
		for thiefId, byVictim in pairs(atmRaidCooldownUntil) do
			byVictim[player.UserId] = nil
		end
	end)

	print("[WAR EMPIRE] MoneyCollectorService ready (PendingCash → touch WE_MoneyCollector; AtmRaid 10%)")
end

return MoneyCollectorService
