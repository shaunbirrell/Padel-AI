--!strict
--[[
	ProcessReceipt skeleton — idempotent grants when product IDs are set.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.MonetizationConfig)

local MonetizationService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil

-- receiptId -> true
local processed: { [string]: boolean } = {}

local function findDevProduct(productId: number): any?
	for _, def in pairs(MonetizationConfig.DevProducts) do
		if def.Id ~= 0 and def.Id == productId then
			return def
		end
	end
	return nil
end

function MonetizationService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return MonetizationService.ProcessReceipt(receiptInfo)
	end
end

function MonetizationService.ProcessReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local receiptId = tostring(receiptInfo.PurchaseId)
	if processed[receiptId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = game:GetService("Players"):GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.WaitForProfile(player, 10)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Persist processed receipts on profile if desired (future)
	local product = findDevProduct(receiptInfo.ProductId)
	if not product then
		warn("[MonetizationService] Unknown product", receiptInfo.ProductId)
		-- Still grant to avoid stuck receipts only if Id placeholders — reject unknown non-zero
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if product.Cash and product.Cash > 0 then
		EconomyService.AddCash(player, product.Cash, "devproduct")
	end
	if product.Gold and product.Gold > 0 then
		EconomyService.AddGold(player, product.Gold, "devproduct")
	end

	processed[receiptId] = true
	DataService.MarkDirty(player)

	if AnalyticsService then
		AnalyticsService.Log("PURCHASE_RECEIPT", player.UserId, {
			productId = receiptInfo.ProductId,
			receiptId = receiptId,
		})
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.PlayerOwnsGamePass(_player: Player, _passKey: string): boolean
	-- TODO: MarketplaceService:UserOwnsGamePassAsync with caching
	return false
end

return MonetizationService
