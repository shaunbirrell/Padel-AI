--!strict
--[[
	Phase 7 — Monetization MVP
	- ProcessReceipt: idempotent DevProduct grants from MonetizationConfig only
	- GamePass ownership cached on join (MarketplaceService:UserOwnsGamePassAsync)
	- VIP / 2x Cash / 2x XP multipliers for EconomyService / XPService
	- NEVER grant currency from client purchase confirmation alone
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local DevConfig = require(Shared.Configs.DevConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local MonetizationService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local NotificationService: any = nil
local RemoteSetup: any = nil
local BattlePassService: any = nil

-- Session receipt cache; also mirrored to profile.ProcessedReceipts
local processed: { [string]: boolean } = {}
-- userId -> passKey -> owned
local gamePassCache: { [number]: { [string]: boolean } } = {}

local function findDevProduct(productId: number): (string?, any?)
	if typeof(productId) ~= "number" or productId == 0 then
		return nil, nil
	end
	for key, def in pairs(MonetizationConfig.DevProducts) do
		if def.Id ~= 0 and def.Id == productId then
			return key, def
		end
	end
	return nil, nil
end

local function findDevProductByKey(key: string): any?
	return MonetizationConfig.DevProducts[key]
end

local function findGamePassByKey(key: string): any?
	return MonetizationConfig.GamePasses[key]
end

local function hasProcessed(profile: any, receiptId: string): boolean
	if processed[receiptId] then
		return true
	end
	if typeof(profile) == "table" and typeof(profile.ProcessedReceipts) == "table" then
		return profile.ProcessedReceipts[receiptId] == true
	end
	return false
end

local function markProcessed(profile: any, receiptId: string)
	processed[receiptId] = true
	if typeof(profile) == "table" then
		if typeof(profile.ProcessedReceipts) ~= "table" then
			profile.ProcessedReceipts = {}
		end
		profile.ProcessedReceipts[receiptId] = true
	end
end

local function mockOwns(passKey: string): boolean
	if not RunService:IsStudio() then
		return false
	end
	local mock = DevConfig.MockOwnedGamePasses
	return typeof(mock) == "table" and mock[passKey] == true
end

function MonetizationService.RefreshGamePassCache(player: Player)
	local userId = player.UserId
	local cache: { [string]: boolean } = {}
	for passKey, def in pairs(MonetizationConfig.GamePasses) do
		local owned = false
		if typeof(def.Id) == "number" and def.Id ~= 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(userId, def.Id)
			end)
			if ok and result == true then
				owned = true
			elseif not ok then
				warn("[MonetizationService] UserOwnsGamePassAsync failed", passKey, result)
			end
		elseif mockOwns(passKey) then
			owned = true
		end
		cache[passKey] = owned
	end
	gamePassCache[userId] = cache
	return cache
end

function MonetizationService.PlayerOwnsGamePass(player: Player, passKey: string): boolean
	local cache = gamePassCache[player.UserId]
	if not cache then
		cache = MonetizationService.RefreshGamePassCache(player)
	end
	return cache[passKey] == true
end

function MonetizationService.SetMockGamePassOwned(player: Player, passKey: string, owned: boolean)
	if not RunService:IsStudio() then
		return
	end
	if not findGamePassByKey(passKey) then
		return
	end
	local cache = gamePassCache[player.UserId]
	if not cache then
		cache = {}
		gamePassCache[player.UserId] = cache
	end
	cache[passKey] = owned
end

--[[ Cash multiplier from VIP (additive bonus) + DoubleCash (multiplicative). ]]
function MonetizationService.GetCashMultiplier(player: Player): number
	local mult = 1
	local vip = MonetizationConfig.GamePasses.VIP
	if vip and MonetizationService.PlayerOwnsGamePass(player, "VIP") then
		local bonus = tonumber(vip.CashBonusMult) or 0
		mult += bonus
	end
	local doubleCash = MonetizationConfig.GamePasses.DoubleCash
	if doubleCash and MonetizationService.PlayerOwnsGamePass(player, "DoubleCash") then
		local m = tonumber(doubleCash.CashMult) or 2
		mult *= m
	end
	return math.max(0, mult)
end

function MonetizationService.GetXPMultiplier(player: Player): number
	local doubleXP = MonetizationConfig.GamePasses.DoubleXP
	if doubleXP and MonetizationService.PlayerOwnsGamePass(player, "DoubleXP") then
		return math.max(1, tonumber(doubleXP.XPMult) or 2)
	end
	return 1
end

function MonetizationService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	NotificationService = deps.NotificationService
	RemoteSetup = deps.RemoteSetup
	BattlePassService = deps.BattlePassService

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return MonetizationService.ProcessReceipt(receiptInfo)
	end

	-- Client may fire to log intent; grants still ONLY happen in ProcessReceipt
	local shopRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseDevProduct) :: RemoteEvent
	shopRemote.OnServerEvent:Connect(function(player: Player, productKey: any)
		if not RateLimitService.Allow(player, "shop_prompt", 2, 3) then
			return
		end
		if typeof(productKey) ~= "string" then
			return
		end
		local def = findDevProductByKey(productKey)
		if not def then
			return
		end
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.SHOP_PROMPT, player.UserId, {
				kind = "DevProduct",
				key = productKey,
				productId = def.Id,
			})
		end
		if def.Id == 0 and NotificationService then
			NotificationService.Notify(player, "Shop item not configured (placeholder ID).", "Warn")
		end
		-- Do NOT grant here. Client prompts Marketplace; ProcessReceipt grants.
	end)

	local passRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseGamePass) :: RemoteEvent
	passRemote.OnServerEvent:Connect(function(player: Player, passKey: any)
		if not RateLimitService.Allow(player, "shop_pass_prompt", 2, 3) then
			return
		end
		if typeof(passKey) ~= "string" then
			return
		end
		local def = findGamePassByKey(passKey)
		if not def then
			return
		end
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.SHOP_PROMPT, player.UserId, {
				kind = "GamePass",
				key = passKey,
				productId = def.Id,
			})
		end
		if def.Id == 0 and NotificationService then
			NotificationService.Notify(player, "GamePass not configured (placeholder ID).", "Warn")
		end
		-- Do NOT grant benefits from this remote — ownership cache only.
	end)

	-- Refresh ownership when Roblox reports a GamePass purchase finished (client signal is untrusted for grants)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		-- Always refresh cache; never grant Cash/Gold/XP from wasPurchased alone
		MonetizationService.RefreshGamePassCache(player)
		if wasPurchased and NotificationService then
			local name = "Game Pass"
			for key, def in pairs(MonetizationConfig.GamePasses) do
				if def.Id ~= 0 and def.Id == passId then
					name = def.DisplayName or key
					break
				end
			end
			NotificationService.Notify(player, "Owned: " .. name .. " (benefits active)", "Success")
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		task.spawn(function()
			MonetizationService.RefreshGamePassCache(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		gamePassCache[player.UserId] = nil
	end)
end

function MonetizationService.ProcessReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local receiptId = tostring(receiptInfo.PurchaseId)

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.WaitForProfile(player, 10)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if hasProcessed(profile, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey, product = findDevProduct(receiptInfo.ProductId)
	if not product then
		-- Unknown / placeholder Id: do not invent grants. Mark processed so Roblox queue drains.
		warn("[MonetizationService] Unknown or unconfigured product", receiptInfo.ProductId)
		markProcessed(profile, receiptId)
		DataService.MarkDirty(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if product.Cash and product.Cash > 0 then
		EconomyService.AddCash(player, product.Cash, "devproduct")
	end
	if product.Gold and product.Gold > 0 then
		EconomyService.AddGold(player, product.Gold, "devproduct")
	end
	-- Battle Pass Premium: server-only via ProcessReceipt (never client confirmation)
	if product.GrantsBattlePassPremium == true and BattlePassService and BattlePassService.SetPremium then
		BattlePassService.SetPremium(player, true)
	end

	markProcessed(profile, receiptId)
	DataService.MarkDirty(player)

	if NotificationService then
		NotificationService.Notify(player, "Purchase granted: " .. (product.DisplayName or productKey or "item"), "Reward")
	end

	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.PURCHASE_RECEIPT, player.UserId, {
			productId = receiptInfo.ProductId,
			productKey = productKey,
			receiptId = receiptId,
		})
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return MonetizationService
