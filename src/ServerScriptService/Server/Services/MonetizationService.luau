--!strict
--[[
	ProcessReceipt — idempotent grants when product IDs are set.
	Phase 7 skeleton: receipt persistence on profile + shop prompt remote.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local MonetizationService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local NotificationService: any = nil
local RemoteSetup: any = nil

-- Session cache; also mirrored to profile.ProcessedReceipts when present
local processed: { [string]: boolean } = {}

local function findDevProduct(productId: number): any?
	for _, def in pairs(MonetizationConfig.DevProducts) do
		if def.Id ~= 0 and def.Id == productId then
			return def
		end
	end
	return nil
end

local function findDevProductByKey(key: string): any?
	return MonetizationConfig.DevProducts[key]
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

function MonetizationService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	NotificationService = deps.NotificationService
	RemoteSetup = deps.RemoteSetup

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return MonetizationService.ProcessReceipt(receiptInfo)
	end

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
				key = productKey,
				productId = def.Id,
			})
		end
		if def.Id == 0 and NotificationService then
			NotificationService.Notify(player, "Shop item not configured (placeholder ID).", "Warn")
		end
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

	local product = findDevProduct(receiptInfo.ProductId)
	if not product then
		warn("[MonetizationService] Unknown product", receiptInfo.ProductId)
		-- Placeholder / unknown: grant to unblock queueed receipts only when Id was never configured
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

	markProcessed(profile, receiptId)
	DataService.MarkDirty(player)

	if NotificationService then
		NotificationService.Notify(player, "Purchase granted: " .. (product.DisplayName or "item"), "Reward")
	end

	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.PURCHASE_RECEIPT, player.UserId, {
			productId = receiptInfo.ProductId,
			receiptId = receiptId,
		})
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.PlayerOwnsGamePass(_player: Player, _passKey: string): boolean
	-- TODO: MarketplaceService:UserOwnsGamePassAsync with caching when Ids != 0
	return false
end

return MonetizationService
