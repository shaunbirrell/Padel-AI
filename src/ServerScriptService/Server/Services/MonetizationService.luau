--!strict
--[[
	Phase 7 — Monetization MVP
	- ProcessReceipt: idempotent DevProduct grants from MonetizationConfig only
	- GamePass ownership cached on join (MarketplaceService:UserOwnsGamePassAsync)
	- VIP / 2x Cash / 2x XP multipliers for EconomyService / XPService
	- NEVER grant currency from client purchase confirmation alone
	v71 money (M1): receipt core — GrantEntitlements lists, whitelisted counter grants (MonetizationConfig.CounterGrants,
	e.g. GrantNukes -> profile.Nukes), StarterFallbackCash decided before any grant, profile.Monetization accounting
	(CurrencySpent), post-save OnGranted(fn) listeners, OnPassOwned(fn) listeners (confirmPassPurchase and
	RefreshGamePassCache), pass checks in parallel (J21), Roblox AnalyticsService economy events (deferred, pcall),
	a whitelisted `source` on RequestPurchase*. Offers: none before the tutorial is complete, the Starter Pack gate
	TrySoftOfferStarterBundle (TutorialService schedules it), no Speed Boost / death Cash Mega pop-ups, D8 budget.
	Owner's 11 features, lane M (spec_f11 F7 / F8): SpeedMultFor (the highest WalkSpeedMult among the speed SKUs the
	player owns: Speed Pass x1.15, Speed Boost x1.25; never multiplied together), re-applied on respawn, on load and
	when a speed pass flips to owned; TryDeathSpeedOffer (the one death offer, MonetizationConfig.DeathSpeedOffer).
	The Keep-Base Rebirth receipt needs no branch of its own: CounterGrants.GrantKeepBaseRebirths banks the token,
	it is saved before PurchaseGranted, and PrestigeService runs the rebirth from OnGranted (never in the receipt).
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

-- v71 money (M1) ────────────────────────────────────────────────────────────────────────────────────────────────
local MAX_COUNTER = 1e15 -- same ceiling as ProfileSchema's sanitiser
type GrantEvent = {
	ProductKey: string,
	ProductId: number,
	ReceiptId: string,
	DisplayName: string,
	Cash: number,
	Gold: number,
	Entitlements: { string },
	Counters: { [string]: number }, -- profile field -> amount added (e.g. Nukes = 3)
	CurrencySpent: number,
	Source: string,
	FirstPurchase: boolean,
	At: number, -- os.clock() of the grant (prunes stale pending events)
}
type GrantListener = (player: Player, productKey: string, event: GrantEvent) -> ()
type PassOwnedListener = (player: Player, passKey: string, reason: string) -> ()
local grantListeners: { GrantListener } = {}
local passOwnedListeners: { PassOwnedListener } = {}
-- receiptId -> grant applied in memory whose save failed; its post-save work runs when a retry saves it
local pendingGrantEvents: { [string]: GrantEvent } = {}
local PENDING_GRANT_TTL_SECONDS = 3600
-- userId -> "DP:<key>" / "GP:<key>" -> last purchase intent (analytics source attribution only)
local purchaseIntents: { [number]: { [string]: { Source: string, At: number } } } = {}
-- userId -> the first pass-cache fill of this session is done (OnPassOwned reason "join" vs "refresh")
local passCacheFilled: { [number]: boolean } = {}
-- D8 session soft-offer budget, and the session start used by the tutorial quiet window
local softOffersClaimed: { [number]: number } = {}
local sessionStartAt: { [number]: number } = {}
-- F8: the death speed offer was sent this session (userId -> true; cleared on PlayerRemoving)
local deathSpeedSent: { [number]: boolean } = {}
-- F8: sanity cap on a WalkSpeedMult config value (a typo must never launch players across the map)
local MAX_WALK_SPEED_MULT = 2

-- Whole number >= 0; junk (nil, strings, NaN, inf, negatives) becomes 0.
local function nonNegInt(value: any): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.clamp(math.floor(n), 0, MAX_COUNTER)
end

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
	local cfg = MonetizationConfig :: any
	local now = os.clock()
	-- v71 money (M1): no pop-ups during the tutorial (the Starter Pack offer comes right after it). A player who
	-- never finishes it becomes offerable after SoftOfferQuietMaxSeconds of play this session.
	if cfg.SoftOfferQuietUntilTutorialComplete == true and DataService then
		local profile = DataService.GetProfile(player)
		if profile and profile.TutorialComplete ~= true then
			local started = sessionStartAt[player.UserId]
			local quietMax = tonumber(cfg.SoftOfferQuietMaxSeconds) or 900
			if started == nil or now - started < quietMax then
				return false
			end
		end
	end
	-- v71 money (M1, D8): at most SoftOfferSessionMax per session (the HUD refuses a 4th anyway)
	local maxPerSession = tonumber(cfg.SoftOfferSessionMax)
	if maxPerSession and (softOffersClaimed[player.UserId] or 0) >= maxPerSession then
		return false
	end
	local cd = tonumber(cfg.SoftOfferSessionCooldownSeconds) or 60
	local last = lastSoftOfferAt[player.UserId]
	if last ~= nil and now - last < cd then
		return false
	end
	lastSoftOfferAt[player.UserId] = now
	softOffersClaimed[player.UserId] = (softOffersClaimed[player.UserId] or 0) + 1
	return true
end

--[[ v71 money (M1): listener registries. Each returns a function that removes the listener. Listeners run
	deferred, each in its own pcall, so a failing listener never touches a receipt or another listener.
	OnGranted(fn(player, productKey, event)): after a DevProduct grant is SAVED (the receipt is then acknowledged).
	  Never for a grant whose save failed (it runs later, when a retry saves it). event: GrantEvent above.
	OnPassOwned(fn(player, passKey, reason)): a game pass flips to owned in the session cache. reason = "join" (the
	  first ownership check of the session), "refresh" (a later check, e.g. after a failed one) or "purchase"
	  (confirmPassPurchase after PromptGamePassPurchaseFinished, confirmed by UserOwnsGamePassAsync). ]]
local function addListener<T>(list: { T }, fn: T): () -> ()
	table.insert(list, fn)
	return function()
		local i = table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end

function MonetizationService.OnGranted(fn: GrantListener): () -> ()
	assert(typeof(fn) == "function", "OnGranted expects a function")
	return addListener(grantListeners, fn)
end

function MonetizationService.OnPassOwned(fn: PassOwnedListener): () -> ()
	assert(typeof(fn) == "function", "OnPassOwned expects a function")
	return addListener(passOwnedListeners, fn)
end

local function runListener(label: string, fn: any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[MonetizationService] " .. label .. " listener error:", err)
	end
end

local function firePassOwned(player: Player, passKey: string, reason: string)
	for _, fn in ipairs(table.clone(passOwnedListeners)) do
		task.defer(runListener, "OnPassOwned", fn, player, passKey, reason)
	end
end

-- v71 money (M1): `source` of a purchase intent (RequestPurchase* 2nd arg), checked against the whitelist
local function cleanSource(raw: any): string
	if typeof(raw) == "string" and #raw > 0 and #raw <= 32 then
		local sources = (MonetizationConfig :: any).PurchaseSources
		if typeof(sources) == "table" and sources[raw] == true then
			return raw
		end
	end
	return "other"
end

local function rememberIntent(player: Player, intentKey: string, source: string)
	local t = purchaseIntents[player.UserId]
	if not t then
		t = {}
		purchaseIntents[player.UserId] = t
	end
	t[intentKey] = { Source = source, At = os.clock() }
end

-- "none" when no intent for this key was logged within IntentAttributionSeconds (e.g. a Roblox retry)
local function intentSource(userId: number, intentKey: string): string
	local t = purchaseIntents[userId]
	local e = t and t[intentKey]
	local window = tonumber((MonetizationConfig :: any).IntentAttributionSeconds) or 180
	if e and os.clock() - e.At <= window then
		return e.Source
	end
	return "none"
end

--[[ v71 money (M1): Roblox's built-in AnalyticsService economy event (bound as RbxAnalytics: the in-house
	AnalyticsService dep has the same name). Deferred and pcall'd: it can never block or fail a grant. ]]
local function logEconomySource(player: Player, currency: string, amount: number, endingBalance: number, sku: string)
	if amount <= 0 then
		return
	end
	task.defer(function()
		pcall(function()
			local RbxAnalytics: any = game:GetService("AnalyticsService")
			local E: any = Enum
			RbxAnalytics:LogEconomyEvent(
				player,
				E.AnalyticsEconomyFlowType.Source,
				currency,
				amount,
				endingBalance,
				E.AnalyticsEconomyTransactionType.IAP.Name,
				sku
			)
		end)
	end)
end

-- Purchase accounting (analytics / segmentation only; never shown to players). Returns true on the first purchase.
local function recordPurchase(profile: any, robux: number): boolean
	local m = profile.Monetization
	if typeof(m) ~= "table" then
		m = {}
		profile.Monetization = m
	end
	local nowUnix = os.time()
	local first = nonNegInt(m.FirstPurchaseUnix) == 0
	m.Purchases = math.min(nonNegInt(m.Purchases) + 1, MAX_COUNTER)
	m.RobuxSpent = math.min(nonNegInt(m.RobuxSpent) + nonNegInt(robux), MAX_COUNTER)
	if first then
		m.FirstPurchaseUnix = nowUnix
	end
	m.LastPurchaseUnix = nowUnix
	return first
end

local function logFirstPurchase(player: Player, profile: any, key: string)
	if not AnalyticsService then
		return
	end
	local stats = if typeof(profile) == "table" and typeof(profile.Stats) == "table" then profile.Stats else {}
	AnalyticsService.Log(AnalyticsConfig.Events.FIRST_PURCHASE, player.UserId, {
		key = key,
		minutesPlayed = math.floor(nonNegInt(stats.PlayTimeSeconds) / 60),
		tutorialComplete = typeof(profile) == "table" and profile.TutorialComplete == true,
	})
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
	-- v71 money (J21): every pass with a live Id is checked at the same time (one thread each); the caller waits
	-- for the last one. 12 serial checks added about 2 s to each join.
	local pending = 0
	local waiter: thread? = nil
	for passKey, def in pairs(MonetizationConfig.GamePasses) do
		checked[passKey] = false
		if typeof(def.Id) == "number" and def.Id ~= 0 then
			local passId: number = def.Id
			pending += 1
			task.spawn(function()
				local ok, result = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
				end)
				if ok and result == true then
					checked[passKey] = true
				elseif not ok then
					warn("[MonetizationService] UserOwnsGamePassAsync failed", passKey, result)
					anyFailed = true
				end
				pending -= 1
				local co = waiter
				if pending == 0 and co ~= nil then
					waiter = nil
					task.spawn(co)
				end
			end)
		elseif mockOwns(passKey) then
			checked[passKey] = true
		end
	end
	while pending > 0 do
		waiter = coroutine.running()
		coroutine.yield()
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
	local flipped: { string } = {}
	for passKey, owned in pairs(checked) do
		if owned then
			if cache[passKey] ~= true then
				table.insert(flipped, passKey) -- v71 money (M1): OnPassOwned
			end
			cache[passKey] = true
			setEntitlementAttr(player, passKey)
		elseif cache[passKey] == nil then
			cache[passKey] = false
		end
	end
	if player.Parent then
		local reason = if passCacheFilled[userId] then "refresh" else "join"
		passCacheFilled[userId] = true
		for _, passKey in ipairs(flipped) do
			firePassOwned(player, passKey, reason)
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

--[[ F8: ownership from what this session already knows: the pass cache (filled on join; mirrors entitlements and
	confirmed purchases) or the saved entitlement. Never yields and never calls Roblox, so it is safe inside a
	receipt's no-yield window and in a death listener. ]]
local function ownsCached(player: Player, key: string): boolean
	local cache = gamePassCache[player.UserId]
	if cache ~= nil and cache[key] == true then
		return true
	end
	local profile = DataService and DataService.GetProfile(player)
	return typeof(profile) == "table" and typeof(profile.Entitlements) == "table" and profile.Entitlements[key] == true
end

-- F8: a SKU key (game pass or Developer Product) is owned: its own key, or the entitlement its product grants
local function ownsSkuCached(player: Player, key: string): boolean
	if ownsCached(player, key) then
		return true
	end
	local dp = (MonetizationConfig.DevProducts :: any)[key]
	local ent = if typeof(dp) == "table" then dp.GrantEntitlement else nil
	return typeof(ent) == "string" and ent ~= key and ownsCached(player, ent)
end

-- F8: WalkSpeedMult of one config entry (1 when missing or junk; capped at MAX_WALK_SPEED_MULT)
local function walkSpeedMultOf(def: any): number
	local m = if typeof(def) == "table" then tonumber(def.WalkSpeedMult) else nil
	if m == nil or m ~= m or m <= 1 then
		return 1
	end
	return math.min(m, MAX_WALK_SPEED_MULT)
end

-- F8: the key (game pass, Developer Product or granted entitlement) belongs to a speed SKU
local function isSpeedKey(key: string): boolean
	if walkSpeedMultOf((MonetizationConfig.GamePasses :: any)[key]) > 1 then
		return true
	end
	for dpKey, def in pairs(MonetizationConfig.DevProducts :: any) do
		if walkSpeedMultOf(def) > 1 and (dpKey == key or def.GrantEntitlement == key) then
			return true
		end
	end
	return false
end

--[[ F8 (owner's 11 features): the walk-speed multiplier for this player = the HIGHEST WalkSpeedMult among the speed
	SKUs they own (GamePasses.ImpulseSpeed x1.15, DevProducts.SpeedBoost x1.25), never the product of them: owning
	both gives x1.25. 1 when none is owned. A pass whose Id is 0 is never owned outside Studio mocks. Never yields. ]]
function MonetizationService.SpeedMultFor(player: Player): number
	local best = 1
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return best
	end
	for passKey, def in pairs(MonetizationConfig.GamePasses :: any) do
		local m = walkSpeedMultOf(def)
		if m > best and ownsCached(player, passKey) then
			best = m
		end
	end
	for productKey, def in pairs(MonetizationConfig.DevProducts :: any) do
		local m = walkSpeedMultOf(def)
		if m > best and ownsSkuCached(player, productKey) then
			best = m
		end
	end
	return best
end

-- SpeedBoost / Speed Pass: permanent move speed on the current character (F8: SpeedMultFor, the max of the owned SKUs)
local function applySpeedBoostToCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local mult = MonetizationService.SpeedMultFor(player)
	if mult <= 1 then
		return -- nothing owned: WalkSpeed stays the game default
	end
	local GameConfig = require(Shared.Configs.GameConfig)
	local base = tonumber(GameConfig.DefaultWalkSpeed) or 16
	hum.WalkSpeed = base * mult
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
	-- F8: a mocked Speed Pass applies at once (Studio only; the live path is OnPassOwned below)
	if owned and isSpeedKey(passKey) then
		applySpeedBoostToCharacter(player)
	end
end


local function ensureEntitlements(profile: any)
	if typeof(profile.Entitlements) ~= "table" then
		profile.Entitlements = {}
	end
	return profile.Entitlements
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
	-- SpeedBoost (F8: any speed SKU): permanent move-speed on current character; no yield (receipt-safe)
	if isSpeedKey(key) then
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
		if not wasOwned then
			-- v71 money (M1): owned-flip listeners, PASS_OWNED, and approximate accounting (config price: a pass
			-- purchase has no receipt, so the exact Robux amount is unknown)
			local def = MonetizationConfig.GamePasses[passKey]
			local price = nonNegInt(def and def.RobuxPrice)
			local source = intentSource(player.UserId, "GP:" .. passKey)
			local profile = DataService and DataService.GetProfile(player)
			local first = false
			if profile then
				first = recordPurchase(profile, price)
				DataService.MarkDirty(player)
			end
			if AnalyticsService then
				AnalyticsService.Log(AnalyticsConfig.Events.PASS_OWNED, player.UserId, {
					key = passKey,
					price = price,
					source = source,
				})
			end
			if first and profile then
				logFirstPurchase(player, profile, passKey)
			end
			firePassOwned(player, passKey, "purchase")
		end
	end)
end

-- v71 money (M1): the Starter Pack offer ───────────────────────────────────────────────────────────────────────
local function starterBundleLive(): any?
	local bundle = MonetizationConfig.DevProducts.StarterBundle
	if bundle and typeof(bundle.Id) == "number" and bundle.Id ~= 0 then
		return bundle
	end
	return nil
end

--[[ v71 money (M1): the Starter Pack offer gate. TutorialService schedules it (StarterBundleOffer.AfterTutorialSeconds
	after the tutorial completes, finished or skipped, or DelaySeconds after load when it is already done); this
	sends it, once per profile (StarterBundleOffered). Returns true when the offer was sent, false when the session
	soft-offer slot is busy (the caller may retry later), nil when it is not wanted (Id 0, no profile, tutorial not
	complete, already offered or owned). May yield once (the ownership lookup on a cold pass cache). ]]
function MonetizationService.TrySoftOfferStarterBundle(player: Player, reason: string?): boolean?
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent or not DataService then
		return nil
	end
	local bundle = starterBundleLive()
	local profile = DataService.GetProfile(player)
	if not bundle or not profile or profile.StarterBundleOffered == true or profile.TutorialComplete ~= true then
		return nil
	end
	if MonetizationService.PlayerOwnsEntitlement(player, "StarterBundle") then
		return nil
	end
	-- the lookup may have yielded
	if not player.Parent or DataService.GetProfile(player) ~= profile or profile.StarterBundleOffered == true then
		return nil
	end
	if not MonetizationService.ClaimSoftOfferSlot(player) then
		return false
	end
	profile.StarterBundleOffered = true
	DataService.MarkDirty(player)
	if RemoteSetup then
		local remote = RemoteSetup.Get(Constants.RemoteNames.StarterBundleOffer)
		if remote and remote:IsA("RemoteEvent") then
			(remote :: RemoteEvent):FireClient(player, {
				ProductKey = "StarterBundle",
				ProductId = bundle.Id,
				DisplayName = bundle.DisplayName or "Starter Pack",
				RobuxPrice = bundle.RobuxPrice,
				Reason = if typeof(reason) == "string" then reason else "session",
			})
		end
	end
	-- (no companion Info line: the client offer toast carries the offer — HUD v70 spec §4.2)
	return true
end

--[[ v71 money (M1, D2): players who bought the old 249 R$ Starter Bundle get Auto Collect once. Only onto a
	persistent profile (a session-only one would lose both the grant and the flag). Runs after the pass cache
	is filled, so the ownership check does not yield. ]]
local function applyStarterGoodwill(player: Player, profile: any)
	local cfg = (MonetizationConfig :: any).StarterGoodwill
	if typeof(cfg) ~= "table" or cfg.Enabled ~= true then
		return
	end
	local flag, need, grant = cfg.Flag, cfg.IfEntitlement, cfg.GrantEntitlement
	if typeof(flag) ~= "string" or typeof(need) ~= "string" or typeof(grant) ~= "string" then
		return
	end
	if typeof(profile) ~= "table" or typeof(profile.Entitlements) ~= "table" then
		return
	end
	local ents = profile.Entitlements
	if ents[need] ~= true or ents[flag] == true then
		return
	end
	if DataService.IsLoaded and not DataService.IsLoaded(player) then
		return
	end
	if DataService.GetProfile(player) ~= profile then
		return
	end
	local alreadyOwned = MonetizationService.PlayerOwnsEntitlement(player, grant)
	ents[flag] = true
	if not alreadyOwned then
		MonetizationService.GrantEntitlement(player, grant) -- marks the profile dirty
		if NotificationService then
			NotificationService.Notify(player, "Thank you, Commander! Your Starter Pack now includes Auto Collect.", "Reward")
		end
	end
	DataService.MarkDirty(player)
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
	-- v71 money (M1): optional 2nd arg `source` (where the prompt came from), whitelisted; analytics only
	shopRemote.OnServerEvent:Connect(function(player: Player, productKey: any, rawSource: any)
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
		local source = cleanSource(rawSource)
		rememberIntent(player, "DP:" .. (productKey :: string), source)
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.SHOP_PROMPT, player.UserId, {
				kind = "DevProduct",
				key = productKey,
				productId = def.Id,
				source = source,
			})
		end
		if def.Id == 0 and NotificationService then
			NotificationService.Notify(player, "Shop item not configured (placeholder ID).", "Warn")
		end
		-- Do NOT grant here. Client prompts Marketplace; ProcessReceipt grants.
	end)

	local passRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseGamePass) :: RemoteEvent
	passRemote.OnServerEvent:Connect(function(player: Player, passKey: any, rawSource: any)
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
		local source = cleanSource(rawSource)
		rememberIntent(player, "GP:" .. (passKey :: string), source)
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.SHOP_PROMPT, player.UserId, {
				kind = "GamePass",
				key = passKey,
				productId = def.Id,
				source = source,
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
		sessionStartAt[player.UserId] = os.clock() -- v71 money (M1): tutorial quiet window
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
			-- F8: the character can spawn before the pass cache and the profile are ready; apply the speed now
			applySpeedBoostToCharacter(player)

			-- v71 money (M1): display-only counter attributes (e.g. WE_Nukes); never read back by the server
			local counterSpecs = (MonetizationConfig :: any).CounterGrants
			if typeof(counterSpecs) == "table" and typeof(profile) == "table" then
				for _, spec in pairs(counterSpecs) do
					if typeof(spec) == "table" and typeof(spec.Field) == "string" and typeof(spec.Attribute) == "string" then
						pcall(function()
							player:SetAttribute(spec.Attribute, nonNegInt(profile[spec.Field]))
						end)
					end
				end
			end

			-- v71 money (M1, D2): Auto Collect for old Starter Bundle buyers (once)
			applyStarterGoodwill(player, profile)

			-- v32 one-shot StarterBundle offer at load: v71 money (M1) moved it off the join. TutorialService now
			-- schedules it after the tutorial (or at load when the tutorial is already done) and sends it through
			-- MonetizationService.TrySoftOfferStarterBundle (StarterBundleOffered gate).
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		gamePassCache[player.UserId] = nil
		lastSoftOfferAt[player.UserId] = nil
		passRefreshRetries[player.UserId] = nil
		-- v71 money (M1)
		passCacheFilled[player.UserId] = nil
		softOffersClaimed[player.UserId] = nil
		sessionStartAt[player.UserId] = nil
		purchaseIntents[player.UserId] = nil
		deathSpeedSent[player.UserId] = nil -- F8: the next session may get one death offer again
	end)

	-- F8: a speed pass that flips to owned (the join check, a retried check or a confirmed purchase) applies at once
	MonetizationService.OnPassOwned(function(player: Player, passKey: string)
		if player.Parent and isSpeedKey(passKey) then
			applySpeedBoostToCharacter(player)
		end
	end)

	-- Re-apply SpeedBoost WalkSpeed on respawn. v71 money (M1): the v36 spawn ("walk_speed") Speed Boost pop-up is
	-- gone (it raced the Starter offer; SpeedBoostOffer.IgnoreReasons). F8: SpeedMultFor (Speed Pass or Speed Boost,
	-- the higher one); it reads the session cache only, so a respawn never waits on a Roblox ownership call.
	local function hookSpeed(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				task.wait(0.3)
				if player.Parent then
					applySpeedBoostToCharacter(player)
				end
			end)
		end)
		if player.Character then
			task.defer(function()
				applySpeedBoostToCharacter(player)
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

-- v71 money (M1): GrantEntitlement + GrantEntitlements, each key once, in order
local function entitlementList(product: any): { string }
	local list: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(k: any)
		if typeof(k) == "string" and k ~= "" and not seen[k] then
			seen[k] = true
			table.insert(list, k)
		end
	end
	add(product.GrantEntitlement)
	if typeof(product.GrantEntitlements) == "table" then
		for _, k in ipairs(product.GrantEntitlements) do
			add(k)
		end
	end
	return list
end

type CounterGrant = { Field: string, Spec: any, N: number }

-- v71 money (M1): only product fields whitelisted in MonetizationConfig.CounterGrants add to a profile number
local function counterGrantList(product: any): { CounterGrant }
	local out: { CounterGrant } = {}
	local specs = (MonetizationConfig :: any).CounterGrants
	if typeof(specs) ~= "table" then
		return out
	end
	for grantField, spec in pairs(specs) do
		if typeof(grantField) == "string" and typeof(spec) == "table" and typeof(spec.Field) == "string" then
			local n = nonNegInt(product[grantField])
			local cap = tonumber(spec.MaxPerReceipt)
			if cap then
				n = math.min(n, nonNegInt(cap))
			end
			if n > 0 then
				table.insert(out, { Field = spec.Field, Spec = spec, N = n })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Field < b.Field
	end)
	return out
end

-- Mutates the in-memory profile only (no yield); the attribute is display-only
local function applyCounterGrant(player: Player, profile: any, c: CounterGrant)
	profile[c.Field] = math.min(nonNegInt(profile[c.Field]) + c.N, MAX_COUNTER)
	local stats = c.Spec.Stats
	if typeof(stats) == "table" and typeof(stats.Table) == "string" and typeof(stats.Key) == "string" then
		local t = profile[stats.Table]
		if typeof(t) ~= "table" then
			t = {}
			profile[stats.Table] = t
		end
		t[stats.Key] = math.min(nonNegInt(t[stats.Key]) + c.N, MAX_COUNTER)
	end
	if typeof(c.Spec.Attribute) == "string" then
		pcall(function()
			player:SetAttribute(c.Spec.Attribute, profile[c.Field])
		end)
	end
end

local function rememberPendingGrant(receiptId: string, event: GrantEvent)
	local now = os.clock()
	for id, e in pairs(pendingGrantEvents) do
		if now - e.At > PENDING_GRANT_TTL_SECONDS then
			pendingGrantEvents[id] = nil
		end
	end
	pendingGrantEvents[receiptId] = event
end

--[[ v71 money (M1): everything that must only happen once a grant is SAVED: the toast, PURCHASE_RECEIPT (with
	CurrencySpent + source), FIRST_PURCHASE, the Roblox economy events and the OnGranted listeners. Nothing here can
	change the receipt decision (listeners and economy events are deferred + pcall'd). ]]
local function afterGrantSaved(player: Player, profile: any, event: GrantEvent)
	if NotificationService then
		NotificationService.Notify(player, "Purchase granted: " .. event.DisplayName, "Reward")
	end
	if AnalyticsService then
		local firstJoin = if typeof(profile) == "table" then nonNegInt(profile.FirstJoinUnix) else 0
		AnalyticsService.Log(AnalyticsConfig.Events.PURCHASE_RECEIPT, player.UserId, {
			productId = event.ProductId,
			productKey = event.ProductKey,
			receiptId = event.ReceiptId,
			currencySpent = event.CurrencySpent,
			source = event.Source,
			firstPurchase = event.FirstPurchase,
			daysSinceFirstJoin = if firstJoin > 0 then math.max(0, math.floor((os.time() - firstJoin) / 86400)) else nil,
			level = if typeof(profile) == "table" then profile.Level else nil,
			prestige = if typeof(profile) == "table" then profile.Prestige else nil,
		})
	end
	if event.FirstPurchase then
		logFirstPurchase(player, profile, event.ProductKey)
	end
	if typeof(profile) == "table" then
		logEconomySource(player, "Cash", event.Cash, nonNegInt(profile.Cash), event.ProductKey)
		logEconomySource(player, "Gold", event.Gold, nonNegInt(profile.Gold), event.ProductKey)
		local specs = (MonetizationConfig :: any).CounterGrants
		for field, n in pairs(event.Counters) do
			local currency: string? = nil
			if typeof(specs) == "table" then
				for _, spec in pairs(specs) do
					if typeof(spec) == "table" and spec.Field == field and typeof(spec.Currency) == "string" then
						currency = spec.Currency
					end
				end
			end
			if currency then
				logEconomySource(player, currency, n, nonNegInt(profile[field]), event.ProductKey)
			end
		end
	end
	-- listeners share one event: read-only, so one listener cannot change what the next one sees
	for _, t: any in ipairs({ event.Counters :: any, event.Entitlements :: any, event :: any }) do
		if not table.isfrozen(t) then
			table.freeze(t)
		end
	end
	for _, fn in ipairs(table.clone(grantListeners)) do
		task.defer(runListener, "OnGranted", fn, player, event.ProductKey, event)
	end
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
			-- v71 money (M1): a grant applied earlier this session whose save failed is saved only now
			local pending = pendingGrantEvents[receiptId]
			if pending then
				pendingGrantEvents[receiptId] = nil
				afterGrantSaved(player, profile, pending)
			end
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
	-- v71 money (M1): the whole grant is computed here, before any mutation. StarterFallbackCash: a buyer who
	-- already owns Auto Collect gets that much more Cash (the Auto Collect grant would add nothing).
	local cashGrant = nonNegInt(product.Cash)
	local fallbackCash = nonNegInt(product.StarterFallbackCash)
	if fallbackCash > 0 then
		if MonetizationService.PlayerOwnsEntitlement(player, "AutoCollect") then
			cashGrant += fallbackCash
		end
		-- that lookup can yield (first pass-cache fill): the player and the profile must still be the live ones
		if not player.Parent or DataService.GetProfile(player) ~= profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	local goldGrant = nonNegInt(product.Gold)
	local entitlements = entitlementList(product)
	local counters = counterGrantList(product)
	local event: GrantEvent = {
		ProductKey = productKey :: string,
		ProductId = receiptInfo.ProductId,
		ReceiptId = receiptId,
		DisplayName = tostring(product.DisplayName or productKey or "item"),
		Cash = cashGrant,
		Gold = goldGrant,
		Entitlements = entitlements,
		Counters = {},
		CurrencySpent = nonNegInt(receiptInfo.CurrencySpent),
		Source = intentSource(player.UserId, "DP:" .. (productKey :: string)),
		FirstPurchase = false,
		At = os.clock(),
	}

	-- Battle Pass Premium: server-only via ProcessReceipt (never client confirmation). First, so a failure
	-- returns before any other grant is applied.
	if product.GrantsBattlePassPremium == true then
		if not battlePassReady() or BattlePassService.SetPremium(player, true) ~= true then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	if cashGrant > 0 then
		EconomyService.AddCash(player, cashGrant, "devproduct")
	end
	if goldGrant > 0 then
		EconomyService.AddGold(player, goldGrant, "devproduct")
	end
	-- DevProduct entitlement flags (AutoCollect / DoubleCash / VIP / StarterBundle + AutoCollect / etc.)
	for _, ent in ipairs(entitlements) do
		MonetizationService.GrantEntitlement(player, ent)
	end
	-- v71 money (M1): whitelisted counters (GrantNukes -> profile.Nukes + NukeStats.Bought)
	for _, c in ipairs(counters) do
		applyCounterGrant(player, profile, c)
		event.Counters[c.Field] = (event.Counters[c.Field] or 0) + c.N
	end
	-- v71 money (M1): accounting (exact Robux from the receipt); saved together with the grant
	event.FirstPurchase = recordPurchase(profile, event.CurrencySpent)

	markProcessed(profile, receiptId)
	DataService.MarkDirty(player)
	-- v67: persist the grant before acknowledging it. If the save fails, Roblox retries the receipt;
	-- ProcessedReceipts (still in memory this session) stops a double grant on the retry.
	if not DataService.SaveProfile(player, false) then
		rememberPendingGrant(receiptId, event) -- v71 money (M1): its post-save work runs when a retry saves it
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	processed[receiptId] = true
	pendingGrantEvents[receiptId] = nil

	afterGrantSaved(player, profile, event)

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
	-- v71 money (M1): the spawn / first-vehicle-sit triggers are ignored (they raced the Starter offer)
	do
		local cfg = (MonetizationConfig :: any).SpeedBoostOffer
		local ignore = cfg and cfg.IgnoreReasons
		if typeof(ignore) == "table" and ignore[reason or "vehicle_sit"] == true then
			return
		end
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
	-- v71 money (M1): no Cash Mega pop-up on a PvP death (CashMegaOffer.IgnoreReasons)
	do
		local cfg = (MonetizationConfig :: any).CashMegaOffer
		local ignore = cfg and cfg.IgnoreReasons
		if typeof(ignore) == "table" and ignore[reason or "pending_collect"] == true then
			return
		end
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

--[[ F8 (owner's 11 features): the ONE offer allowed after a death (MonetizationConfig.DeathSpeedOffer; DeathShopOffers
	stays empty, so there is still no 2x Cash / Cash Mega death offer). CombatService calls it in a pcall after a PvP
	death that was not a blast. Sends DeathShopOffer { Offers = { PassKey } } only when ALL of these hold:
	  - the pass Id is not 0 (nothing is offered or prompted while it is 0);
	  - the tutorial is complete (RequireTutorialComplete);
	  - it is the first send this session (OncePerSession; deathSpeedSent, cleared on PlayerRemoving);
	  - ownership is KNOWN (the join check has run and no failed check is waiting for a retry) and the victim owns
	    none of SkipIfOwnsAny (Speed Pass or Speed Boost);
	  - a D8 soft-offer slot is free (ClaimSoftOfferSlot, claimed last so a refused offer never spends one).
	Never yields. Returns true when the offer was sent. The client still refuses it for an owner (WE_Ent_*). ]]
function MonetizationService.TryDeathSpeedOffer(victim: Player): boolean
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") or not victim.Parent or not DataService then
		return false
	end
	local cfg = (MonetizationConfig :: any).DeathSpeedOffer
	if typeof(cfg) ~= "table" or typeof(cfg.PassKey) ~= "string" then
		return false
	end
	local passKey: string = cfg.PassKey
	local pass = (MonetizationConfig.GamePasses :: any)[passKey]
	if typeof(pass) ~= "table" or typeof(pass.Id) ~= "number" or pass.Id == 0 then
		return false
	end
	local userId = victim.UserId
	if cfg.OncePerSession ~= false and deathSpeedSent[userId] == true then
		return false
	end
	local profile = DataService.GetProfile(victim)
	if not profile then
		return false
	end
	if cfg.RequireTutorialComplete ~= false and profile.TutorialComplete ~= true then
		return false
	end
	-- unknown ownership is never "not owned": no offer until the join check has run without a pending retry
	if passCacheFilled[userId] ~= true or passRefreshRetries[userId] ~= nil then
		return false
	end
	if ownsSkuCached(victim, passKey) then
		return false
	end
	if typeof(cfg.SkipIfOwnsAny) == "table" then
		for _, key in ipairs(cfg.SkipIfOwnsAny) do
			if typeof(key) == "string" and ownsSkuCached(victim, key) then
				return false
			end
		end
	end
	if not MonetizationService.ClaimSoftOfferSlot(victim) then
		return false
	end
	deathSpeedSent[userId] = true
	if RemoteSetup then
		local remote = RemoteSetup.Get(Constants.RemoteNames.DeathShopOffer)
		if remote and remote:IsA("RemoteEvent") then
			(remote :: RemoteEvent):FireClient(victim, { Offers = { passKey } })
		end
	end
	return true
end


return MonetizationService
