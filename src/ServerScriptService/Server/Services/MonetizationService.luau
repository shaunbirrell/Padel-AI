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

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

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


local function ensureEntitlements(profile: any)
	if typeof(profile.Entitlements) ~= "table" then
		profile.Entitlements = {}
	end
	return profile.Entitlements
end

local SPEED_BOOST_MULT = 1.25

local function applySpeedBoostToCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local GameConfig = require(Shared.Configs.GameConfig)
	local base = tonumber(GameConfig.DefaultWalkSpeed) or 16
	hum.WalkSpeed = base * SPEED_BOOST_MULT
end

function MonetizationService.GrantEntitlement(player: Player, key: string)
	local profile = DataService.GetProfile(player)
	if not profile or typeof(key) ~= "string" or key == "" then
		return
	end
	local ents = ensureEntitlements(profile)
	ents[key] = true
	-- Mirror common keys into GamePass session cache so multipliers apply immediately
	if key == "VIP" or key == "DoubleCash" or key == "DoubleXP" or key == "AutoCollect" then
		local cache = gamePassCache[player.UserId]
		if not cache then
			cache = {}
			gamePassCache[player.UserId] = cache
		end
		cache[key] = true
	end
	-- InstantBarracks: bump Barracks to at least 1
	if key == "InstantBarracks" and typeof(profile.BaseUpgrades) == "table" then
		local cur = profile.BaseUpgrades.Barracks or 0
		if cur < 1 then
			profile.BaseUpgrades.Barracks = 1
		end
	end
	-- GoldenPumpjack: re-dress plot oil pumps when product Id is live + granted
	if key == "GoldenPumpjack" and typeof(profile.BasePlotId) == "number" then
		task.defer(function()
			local ok, pumpSvc = pcall(function()
				return require(script.Parent.PlotOilPumpService)
			end)
			if ok and pumpSvc and pumpSvc.SyncPlot then
				pumpSvc.SyncPlot(profile.BasePlotId)
			end
		end)
	end
	-- SpeedBoost: permanent move-speed on current character
	if key == "SpeedBoost" then
		applySpeedBoostToCharacter(player)
	end
	DataService.MarkDirty(player)
end

function MonetizationService.PlayerOwnsEntitlement(player: Player, key: string): boolean
	if MonetizationService.PlayerOwnsGamePass(player, key) then
		return true
	end
	local profile = DataService.GetProfile(player)
	if profile and typeof(profile.Entitlements) == "table" and profile.Entitlements[key] == true then
		return true
	end
	return false
end

--[[ Cash multiplier from VIP (additive bonus) + DoubleCash (multiplicative). ]]
function MonetizationService.GetCashMultiplier(player: Player): number
	local mult = 1
	local vip = MonetizationConfig.GamePasses.VIP
	local hasVip = MonetizationService.PlayerOwnsEntitlement(player, "VIP")
		or MonetizationService.PlayerOwnsGamePass(player, "VIP")
	if vip and hasVip then
		local bonus = tonumber(vip.CashBonusMult) or 0
		mult += bonus
	end
	local doubleCash = MonetizationConfig.GamePasses.DoubleCash
	local hasDouble = MonetizationService.PlayerOwnsEntitlement(player, "DoubleCash")
		or MonetizationService.PlayerOwnsGamePass(player, "DoubleCash")
	if doubleCash and hasDouble then
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
		-- Intent-only: never grants currency. Still validate + require profile loaded.
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		if not RemoteGuard.IsKeyString(productKey) then
			return
		end
		local def = findDevProductByKey(productKey :: string)
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
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		if not RemoteGuard.IsKeyString(passKey) then
			return
		end
		local def = findGamePassByKey(passKey :: string)
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

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		task.spawn(function()
			MonetizationService.RefreshGamePassCache(player)
			-- Rehydrate session cache from persisted Entitlements
			if typeof(profile) == "table" and typeof(profile.Entitlements) == "table" then
				local cache = gamePassCache[player.UserId] or {}
				for k, v in pairs(profile.Entitlements) do
					if v == true then
						cache[k] = true
					end
				end
				gamePassCache[player.UserId] = cache
			end

			-- v32: one-shot StarterBundle soft offer (new profile / low cash). Marks profile so it never repeats.
			local offerCfg = (MonetizationConfig :: any).StarterBundleOffer
			local bundle = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts.StarterBundle
			if offerCfg and bundle and typeof(bundle.Id) == "number" and bundle.Id ~= 0 and typeof(profile) == "table" then
				local alreadyOffered = profile.StarterBundleOffered == true
				local ownsBundle = MonetizationService.PlayerOwnsEntitlement(player, "StarterBundle")
				if not alreadyOffered and not ownsBundle then
					local cash = tonumber(profile.Cash) or 0
					local cashBelow = tonumber(offerCfg.CashBelow) or 12000
					local firstJoin = tonumber(profile.FirstJoinUnix) or 0
					local lastJoin = tonumber(profile.LastJoinUnix) or firstJoin
					local maxAge = tonumber(offerCfg.NewProfileMaxAgeSeconds) or 600
					local isNewish = firstJoin > 0 and (lastJoin - firstJoin) <= maxAge
					local cashLow = cash <= cashBelow
					if isNewish or cashLow then
						local delaySec = tonumber(offerCfg.DelaySeconds) or 8
						task.delay(delaySec, function()
							if not player.Parent then
								return
							end
							local live = DataService.GetProfile(player)
							if not live or live.StarterBundleOffered == true then
								return
							end
							if MonetizationService.PlayerOwnsEntitlement(player, "StarterBundle") then
								return
							end
							live.StarterBundleOffered = true
							DataService.MarkDirty(player)
							if RemoteSetup then
								local remote = RemoteSetup.Get(Constants.RemoteNames.StarterBundleOffer)
								if remote and remote:IsA("RemoteEvent") then
									(remote :: RemoteEvent):FireClient(player, {
										ProductKey = "StarterBundle",
										ProductId = bundle.Id,
										DisplayName = bundle.DisplayName or "Starter Bundle",
										RobuxPrice = bundle.RobuxPrice,
									})
								end
							end
							if NotificationService then
								NotificationService.Notify(
									player,
									"Commander Starter Bundle available — tap toast to jumpstart",
									"Info",
									5
								)
							end
						end)
					end
				end
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		gamePassCache[player.UserId] = nil
	end)

	-- Re-apply SpeedBoost WalkSpeed on respawn
	local function hookSpeed(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				task.wait(0.3)
				if MonetizationService.PlayerOwnsEntitlement(player, "SpeedBoost") then
					applySpeedBoostToCharacter(player)
				end
			end)
		end)
		if player.Character then
			task.defer(function()
				if MonetizationService.PlayerOwnsEntitlement(player, "SpeedBoost") then
					applySpeedBoostToCharacter(player)
				end
			end)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		hookSpeed(p)
	end
	Players.PlayerAdded:Connect(hookSpeed)
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
	-- DevProduct entitlement flags (AutoCollect / DoubleCash / VIP / etc.)
	if typeof(product.GrantEntitlement) == "string" and product.GrantEntitlement ~= "" then
		MonetizationService.GrantEntitlement(player, product.GrantEntitlement)
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


--[[ v35: one-shot VIP soft toast at mid-game (level≥MinLevel OR structure≥MinStructureLevel). ]]
function MonetizationService.TrySoftOfferVIP(player: Player, reason: string?)
	if not player or not player.Parent then
		return
	end
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return
	end
	if profile.VIPOffered == true then
		return
	end
	local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses.VIP
	if not gp or typeof(gp.Id) ~= "number" or gp.Id == 0 then
		return
	end
	if MonetizationService.PlayerOwnsGamePass(player, "VIP") then
		return
	end
	local offerCfg = (MonetizationConfig :: any).VIPOffer
	if not offerCfg then
		return
	end
	local minLevel = tonumber(offerCfg.MinLevel) or 10
	local minStruct = tonumber(offerCfg.MinStructureLevel) or 3
	local level = tonumber(profile.Level) or 1
	local maxStruct = 0
	if typeof(profile.BaseUpgrades) == "table" then
		for _, lv in pairs(profile.BaseUpgrades) do
			local n = tonumber(lv) or 0
			if n > maxStruct then
				maxStruct = n
			end
		end
	end
	if level < minLevel and maxStruct < minStruct then
		return
	end
	profile.VIPOffered = true
	DataService.MarkDirty(player)
	local delaySec = tonumber(offerCfg.DelaySeconds) or 2.0
	task.delay(delaySec, function()
		if not player.Parent then
			return
		end
		if MonetizationService.PlayerOwnsGamePass(player, "VIP") then
			return
		end
		if RemoteSetup then
			local remote = RemoteSetup.Get(Constants.RemoteNames.VIPOffer)
			if remote and remote:IsA("RemoteEvent") then
				(remote :: RemoteEvent):FireClient(player, {
					ProductKey = "VIP",
					GamePassId = gp.Id,
					DisplayName = gp.DisplayName or "VIP",
					RobuxPrice = gp.RobuxPrice,
					Reason = reason or "midgame",
				})
			end
		end
		if NotificationService then
			NotificationService.Notify(
				player,
				"Commander status unlocked — VIP boosts cash & prestige",
				"Info",
				4.5
			)
		end
	end)
end

return MonetizationService
