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
local BaseService: any = nil
local SoldierService: any = nil

-- Session receipt cache; also mirrored to profile.ProcessedReceipts
local processed: { [string]: boolean } = {}
--[[ v71 money (J2): receipts being processed right now (PurchaseId -> true). ProcessReceipt yields (Battle Pass
	readiness, the profile load, pre-grant ownership lookups, the save). A second delivery of the same receipt in
	that window never runs alongside the first (with a yield between hasProcessed and markProcessed it would grant
	twice): it answers NotProcessedYet, and Roblox retries it after the first run has marked and saved it. ]]
local receiptsInFlight: { [string]: boolean } = {}
-- userId -> passKey -> owned
local gamePassCache: { [number]: { [string]: boolean } } = {}
-- v38: session soft-offer spam gate (one toast max per SoftOfferSessionCooldownSeconds)
local lastSoftOfferAt: { [number]: number } = {}
-- v70: follow-up ownership checks after UserOwnsGamePassAsync failed (userId -> retries used)
local passRefreshRetries: { [number]: number } = {}
local PASS_REFRESH_MAX_RETRIES = 4
local PASS_REFRESH_RETRY_SECONDS = 15
-- v70: a Battle Pass Premium receipt can arrive before BattlePassService.Init (it runs after MapSetup)
local BATTLE_PASS_READY_WAIT_SECONDS = 30

--[[ v70: display-only replication of one-time entitlements / owned passes (ShopController shows OWNED when
	WE_Ent_<key> is true). Never read back by the server; grants stay ProcessReceipt / ownership checks. ]]
local function setEntitlementAttr(player: Player, key: any)
	if typeof(key) ~= "string" or #key == 0 or #key > 90 or string.match(key, "^[%w_]+$") == nil then
		return
	end
	pcall(function()
		player:SetAttribute("WE_Ent_" .. key, true)
	end)
end

function MonetizationService.ClaimSoftOfferSlot(player: Player): boolean
	if not player then
		return false
	end
	local cd = tonumber((MonetizationConfig :: any).SoftOfferSessionCooldownSeconds) or 60
	local now = os.clock()
	local last = lastSoftOfferAt[player.UserId] or 0
	if now - last < cd then
		return false
	end
	lastSoftOfferAt[player.UserId] = now
	return true
end


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

--[[ v70: marks the profile only. The session cache `processed` is set once the grant is SAVED (ProcessReceipt):
	after a failed save plus a reload, that cache used to acknowledge the re-delivered receipt with no grant. ]]
local function markProcessed(profile: any, receiptId: string)
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

function MonetizationService.RefreshGamePassCache(player: Player): { [string]: boolean }
	local userId = player.UserId
	local checked: { [string]: boolean } = {}
	local anyFailed = false
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
				anyFailed = true
			end
		elseif mockOwns(passKey) then
			owned = true
		end
		checked[passKey] = owned
	end
	-- v70: merge into the live cache instead of replacing it. Keys mirrored from Entitlements or a purchase
	-- this session stay true, and a failed / lagging check never turns an owned pass off for the session.
	local cache = gamePassCache[userId]
	if not cache then
		cache = {}
		if player.Parent then -- left during the checks: PlayerRemoving already dropped the cache
			gamePassCache[userId] = cache
		end
	end
	for passKey, owned in pairs(checked) do
		if owned then
			cache[passKey] = true
			setEntitlementAttr(player, passKey)
		elseif cache[passKey] == nil then
			cache[passKey] = false
		end
	end
	-- v70: a failed check is not "not owned" — ask again a few times instead of caching false all session
	if anyFailed and player.Parent then
		local used = passRefreshRetries[userId] or 0
		if used < PASS_REFRESH_MAX_RETRIES then
			passRefreshRetries[userId] = used + 1
			task.delay(PASS_REFRESH_RETRY_SECONDS * (used + 1), function()
				if player.Parent then
					MonetizationService.RefreshGamePassCache(player)
				end
			end)
		end
	elseif not anyFailed then
		passRefreshRetries[userId] = nil
	end
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
	setEntitlementAttr(player, key) -- v70: Shop shows OWNED (display only)
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
		local cur = tonumber(profile.BaseUpgrades.Barracks) or 0
		if cur < 1 then
			profile.BaseUpgrades.Barracks = 1
			-- v70: same follow-ups as a cash Barracks purchase, or the player sees nothing until rejoin
			task.defer(function()
				if not player.Parent then
					return
				end
				local base = BaseService
				if base then
					if base.PushState then
						pcall(base.PushState, player)
					end
					if base.UpdateVisuals then
						pcall(base.UpdateVisuals, player, "Barracks", 1)
					end
					if base.GetUpgradeChangedEvent then
						pcall(function()
							local live = DataService.GetProfile(player)
							base.GetUpgradeChangedEvent():Fire(player.UserId, live and live.BasePlotId, "Barracks", 1)
						end)
					end
				end
				if SoldierService and SoldierService.Push then
					pcall(SoldierService.Push, player) -- army cap label
				end
			end)
		end
	end
	-- ExtraSoldierSlot: +1 army cap — refresh the Army panel now
	if key == "ExtraSoldierSlot" then
		task.defer(function()
			if player.Parent and SoldierService and SoldierService.Push then
				pcall(SoldierService.Push, player)
			end
		end)
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

local PASS_CONFIRM_DELAYS = { 0, 2, 5, 10, 20 } -- re-checks after a pass purchase prompt closes (~37 s)
local passConfirming: { [string]: boolean } = {} -- "userId:passKey" -> a confirm loop is running

--[[ v70: after PromptGamePassPurchaseFinished(wasPurchased) — never trusted alone. Marks the pass owned for this
	session only when UserOwnsGamePassAsync says so (bounded re-checks, one loop per player + pass). ]]
local function confirmPassPurchase(player: Player, passKey: string, passId: number, passName: string)
	local loopKey = tostring(player.UserId) .. ":" .. passKey
	if passConfirming[loopKey] then
		return
	end
	passConfirming[loopKey] = true
	task.spawn(function()
		local confirmed = false
		for _, delaySec in ipairs(PASS_CONFIRM_DELAYS) do
			if delaySec > 0 then
				task.wait(delaySec)
			end
			if not player.Parent then
				break
			end
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if ok and owns == true then
				confirmed = true
				break
			end
		end
		passConfirming[loopKey] = nil
		if not player.Parent then
			return
		end
		if not confirmed then
			if NotificationService then
				NotificationService.Notify(player, passName .. ": waiting for Roblox to confirm the pass — rejoin if it is not active soon", "Info")
			end
			return
		end
		local cache = gamePassCache[player.UserId]
		if not cache then
			cache = {}
			gamePassCache[player.UserId] = cache
		end
		local wasOwned = cache[passKey] == true
		cache[passKey] = true
		setEntitlementAttr(player, passKey)
		if not wasOwned and NotificationService then
			NotificationService.Notify(player, "Owned: " .. passName .. " (benefits active)", "Success")
		end
	end)
end

function MonetizationService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	NotificationService = deps.NotificationService
	RemoteSetup = deps.RemoteSetup
	BattlePassService = deps.BattlePassService
	BaseService = deps.BaseService
	SoldierService = deps.SoldierService

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

	-- Re-check ownership when a GamePass prompt reports a purchase (the signal itself is untrusted for grants)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		local passKey: string? = nil
		local passName = "Game Pass"
		if typeof(passId) == "number" and passId ~= 0 then
			for key, def in pairs(MonetizationConfig.GamePasses) do
				if def.Id ~= 0 and def.Id == passId then
					passKey = key
					passName = tostring(def.DisplayName or key)
					break
				end
			end
		end
		-- v70: wasPurchased is only the prompt's GUI state and exploit clients have been able to fire this event
		-- (Roblox: use receipts for purchases). A pass counts as owned only once UserOwnsGamePassAsync confirms
		-- it; that check can lag right after an in-game purchase, so it is repeated a few times.
		if wasPurchased == true and passKey ~= nil then
			confirmPassPurchase(player, passKey, passId, passName)
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		task.spawn(function()
			MonetizationService.RefreshGamePassCache(player)
			if not player.Parent then
				return
			end
			-- Rehydrate session cache from persisted Entitlements
			if typeof(profile) == "table" and typeof(profile.Entitlements) == "table" then
				local cache = gamePassCache[player.UserId] or {}
				for k, v in pairs(profile.Entitlements) do
					if v == true then
						cache[k] = true
						setEntitlementAttr(player, k) -- v70: Shop shows OWNED (display only)
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
							if not MonetizationService.ClaimSoftOfferSlot(player) then
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
							-- (no companion Info line: the client offer toast carries the offer — HUD v70 spec §4.2)
						end)
					end
				end
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		gamePassCache[player.UserId] = nil
		lastSoftOfferAt[player.UserId] = nil
		passRefreshRetries[player.UserId] = nil
	end)

	-- Re-apply SpeedBoost WalkSpeed on respawn + v36 soft offer on first walk-speed moment
	local function hookSpeed(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				task.wait(0.3)
				if MonetizationService.PlayerOwnsEntitlement(player, "SpeedBoost") then
					applySpeedBoostToCharacter(player)
				else
					-- First character walk moment (session): soft toast if not yet offered
					task.delay(4.0, function()
						if player.Parent and MonetizationService.TrySoftOfferSpeedBoost then
							MonetizationService.TrySoftOfferSpeedBoost(player, "walk_speed")
						end
					end)
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

local function battlePassReady(): boolean
	local bp = BattlePassService
	return bp ~= nil and typeof(bp.IsReady) == "function" and bp.IsReady() == true
end

local function processReceipt(receiptInfo: any, receiptId: string): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- v70: Battle Pass Premium needs BattlePassService, which Bootstrap initialises after the map build. A
	-- receipt delivered earlier waits for it; if it is still not up, Roblox re-delivers the receipt later.
	do
		local _, earlyProduct = findDevProduct(receiptInfo.ProductId)
		if earlyProduct and earlyProduct.GrantsBattlePassPremium == true and not battlePassReady() then
			local deadline = os.clock() + BATTLE_PASS_READY_WAIT_SECONDS
			while not battlePassReady() and os.clock() < deadline and player.Parent do
				task.wait(0.25)
			end
			if not battlePassReady() or not player.Parent then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
	end

	-- v70: 25 s — the load can first wait up to 12 s for the previous server's session lock (SessionLock)
	local profile = DataService.WaitForProfile(player, 25)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- v67: only grant onto a profile that was read from the DataStore and will be saved. A session-only
	-- profile (store read failed) would lose the grant; Roblox re-delivers NotProcessedYet receipts.
	if DataService.IsLoaded and not DataService.IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if hasProcessed(profile, receiptId) then
		-- v70: granted into this profile earlier, but that save may have failed — the ack still waits for a save
		if not processed[receiptId] then
			if not DataService.SaveProfile(player, false) then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			processed[receiptId] = true
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey, product = findDevProduct(receiptInfo.ProductId)
	if not product then
		-- v71 money (J2): an unknown Id is never acknowledged. Acking it ("drain the queue") took the Robux and
		-- granted nothing when a receipt for a newly pasted Id reached a server still on the old version. Roblox
		-- keeps retrying; once every server runs the version with the Id (Migrate to Latest Update) it is granted.
		-- Nothing is marked or saved here.
		warn(
			"[MonetizationService] Unknown product Id — receipt NOT acknowledged (Roblox retries it):",
			receiptInfo.ProductId,
			receiptId
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	--[[ v71 money (J2): everything above may yield (Battle Pass readiness, the profile load). Any ownership lookup
		a grant needs (UserOwnsGamePassAsync via PlayerOwnsGamePass / PlayerOwnsEntitlement) belongs HERE, before
		the first grant mutation. From the first mutation below to markProcessed nothing may yield: the grants
		(SetPremium, AddCash / AddGold with the multiplier-exempt "devproduct" reason, GrantEntitlement) only
		mutate the in-memory profile and defer their follow-ups. ]]

	-- Battle Pass Premium: server-only via ProcessReceipt (never client confirmation). First, so a failure
	-- returns before any other grant is applied.
	if product.GrantsBattlePassPremium == true then
		if not battlePassReady() or BattlePassService.SetPremium(player, true) ~= true then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	if product.Cash and product.Cash > 0 then
		EconomyService.AddCash(player, product.Cash, "devproduct")
	end
	if product.Gold and product.Gold > 0 then
		EconomyService.AddGold(player, product.Gold, "devproduct")
	end
	-- DevProduct entitlement flags (AutoCollect / DoubleCash / VIP / etc.)
	if typeof(product.GrantEntitlement) == "string" and product.GrantEntitlement ~= "" then
		MonetizationService.GrantEntitlement(player, product.GrantEntitlement)
	end

	markProcessed(profile, receiptId)
	DataService.MarkDirty(player)
	-- v67: persist the grant before acknowledging it. If the save fails, Roblox retries the receipt;
	-- ProcessedReceipts (still in memory this session) stops a double grant on the retry.
	if not DataService.SaveProfile(player, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	processed[receiptId] = true

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

--[[ Roblox MarketplaceService.ProcessReceipt callback (wired in Init). v71 money (J2): one run per PurchaseId at a
	time; an error inside is answered NotProcessedYet (Roblox retries) and always releases the in-flight lock. ]]
function MonetizationService.ProcessReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local receiptId = tostring(if typeof(receiptInfo) == "table" then receiptInfo.PurchaseId else nil)
	if receiptsInFlight[receiptId] then
		warn("[MonetizationService] Receipt already being processed — NotProcessedYet (Roblox retries):", receiptId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	receiptsInFlight[receiptId] = true
	local ok, decision = pcall(processReceipt, receiptInfo, receiptId)
	receiptsInFlight[receiptId] = nil
	if not ok then
		warn("[MonetizationService] ProcessReceipt error — NotProcessedYet (Roblox retries):", receiptId, decision)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
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
	if not MonetizationService.ClaimSoftOfferSlot(player) then
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
		-- (no companion Info line: the client offer toast carries the offer — HUD v70 spec §4.2)
	end)
end



--[[ v36: one-shot SpeedBoost soft toast after first jeep sit / walk-speed moment (existing DevProduct Id). ]]
function MonetizationService.TrySoftOfferSpeedBoost(player: Player, reason: string?)
	if not player or not player.Parent then
		return
	end
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return
	end
	if profile.SpeedBoostOffered == true then
		return
	end
	local dp = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts.SpeedBoost
	if not dp or typeof(dp.Id) ~= "number" or dp.Id == 0 then
		return
	end
	if MonetizationService.PlayerOwnsEntitlement(player, "SpeedBoost") then
		return
	end
	local offerCfg = (MonetizationConfig :: any).SpeedBoostOffer
	if not offerCfg then
		return
	end
	if not MonetizationService.ClaimSoftOfferSlot(player) then
		return
	end
	profile.SpeedBoostOffered = true
	DataService.MarkDirty(player)
	local delaySec = tonumber(offerCfg.DelaySeconds) or 1.5
	task.delay(delaySec, function()
		if not player.Parent then
			return
		end
		if MonetizationService.PlayerOwnsEntitlement(player, "SpeedBoost") then
			return
		end
		if RemoteSetup then
			local remote = RemoteSetup.Get(Constants.RemoteNames.SpeedBoostOffer)
			if remote and remote:IsA("RemoteEvent") then
				(remote :: RemoteEvent):FireClient(player, {
					ProductKey = "SpeedBoost",
					ProductId = dp.Id,
					DisplayName = dp.DisplayName or "Speed Boost",
					RobuxPrice = dp.RobuxPrice,
					Reason = reason or "vehicle_sit",
				})
			end
		end
		-- (no companion Info line: the client offer toast carries the offer — HUD v70 spec §4.2)
	end)
end


--[[ v37: one-shot CashMega soft toast after high pending collect OR death path (existing DevProduct Id only). ]]
function MonetizationService.TrySoftOfferCashMega(player: Player, reason: string?, grantedOrPending: number?)
	if not player or not player.Parent then
		return
	end
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return
	end
	if profile.CashMegaOffered == true then
		return
	end
	local dp = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts.CashMega
	if not dp or typeof(dp.Id) ~= "number" or dp.Id == 0 then
		return
	end
	local offerCfg = (MonetizationConfig :: any).CashMegaOffer
	if not offerCfg then
		return
	end
	local minNeed = tonumber(offerCfg.MinPendingCollect) or 15000
	local amt = tonumber(grantedOrPending) or 0
	-- Death path bypasses amount threshold; collect path requires high amount
	if reason ~= "death" and amt < minNeed then
		return
	end
	if not MonetizationService.ClaimSoftOfferSlot(player) then
		return
	end
	profile.CashMegaOffered = true
	DataService.MarkDirty(player)
	local delaySec = tonumber(offerCfg.DelaySeconds) or 1.8
	task.delay(delaySec, function()
		if not player.Parent then
			return
		end
		if RemoteSetup then
			local remote = RemoteSetup.Get(Constants.RemoteNames.CashMegaOffer)
			if remote and remote:IsA("RemoteEvent") then
				(remote :: RemoteEvent):FireClient(player, {
					ProductKey = "CashMega",
					ProductId = dp.Id,
					DisplayName = dp.DisplayName or "Cash Pack Mega",
					RobuxPrice = dp.RobuxPrice,
					Reason = reason or "pending_collect",
				})
			end
		end
		-- (no companion Info line: the client offer toast carries the offer — HUD v70 spec §4.2)
	end)
end


return MonetizationService
