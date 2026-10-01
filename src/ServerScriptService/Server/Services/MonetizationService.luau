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
	player owns: Speed Pass x1.5, Speed Boost x2 (v133; v126 was x1.4 / x1.6); never multiplied together), re-applied on respawn, on load and
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
local ShopOverhaulConfig = require(Shared.Configs.ShopOverhaulConfig) -- claude-bud JOB 36 (owner-first)
local DevConfig = require(Shared.Configs.DevConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local OfferLedger = require(script.Parent.Parent.Modules.OfferLedger) -- Code Bot v153: shown-confirmed soft offers
local LivePrices = require(Shared.Util.LivePrices) -- Code Bot v156: the real Roblox price / name on every offer

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
	PerMinBucket: string?, -- claude-bud JOB 42: the buyer's income bucket on a time pack (analytics)
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
-- Code Bot v153: soft offers sent but not yet confirmed shown by the client (MonetizationConfig.FirstOffer)
local offerLedger = OfferLedger.new({
	AckTimeoutSeconds = tonumber(((MonetizationConfig :: any).FirstOffer or {}).AckTimeoutSeconds) or 100,
	RequeueSeconds = tonumber(((MonetizationConfig :: any).FirstOffer or {}).RequeueSeconds) or 45,
	MaxSendsPerSession = tonumber(((MonetizationConfig :: any).FirstOffer or {}).MaxSendsPerSession) or 4,
})
local firstOfferToken: { [number]: number } = {} -- userId -> the pending ScheduleFirstOffer run (one at a time)
local firstOfferSeq = 0
-- F8: the death speed offer was sent this session (userId -> true; cleared on PlayerRemoving)
local deathSpeedSent: { [number]: boolean } = {}
-- F8: sanity cap on a WalkSpeedMult config value (a typo must never launch players across the map)
-- claude-bud JOB 40: the sanity cap lives in config now (MonetizationConfig.MaxWalkSpeedMult 2.5 = 40: the x2.5 Speed
-- Boost fits; today's x1.5 / x2 are unchanged under it). v133 was a local 2.0; v126 1.75.
local MAX_WALK_SPEED_MULT = tonumber((MonetizationConfig :: any).MaxWalkSpeedMult) or 2.0

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

-- Code Bot v153: MonetizationConfig.FirstOffer (nil when off)
local function firstOfferCfg(): any?
	local f = (MonetizationConfig :: any).FirstOffer
	if typeof(f) == "table" and f.Enabled == true then
		return f
	end
	return nil
end

--[[ Code Bot v153: seconds until ClaimSoftOfferSlot could succeed for this player (0 = now), or nil when it never
	will this session (the session cap is spent). Never yields; claims nothing. ]]
function MonetizationService.SoftOfferSlotWait(player: Player): number?
	if not player then
		return nil
	end
	local cfg = MonetizationConfig :: any
	local now = os.clock()
	local uid = player.UserId
	local maxPerSession = tonumber(cfg.SoftOfferSessionMax)
	if maxPerSession and (softOffersClaimed[uid] or 0) >= maxPerSession then
		return nil
	end
	local wait = 0
	local first = firstOfferCfg()
	if first then
		local started = sessionStartAt[uid]
		local quiet = tonumber(first.AtPlaySeconds) or 120
		wait = if started == nil then quiet else math.max(0, quiet - (now - started))
	end
	local cd = tonumber(cfg.SoftOfferSessionCooldownSeconds) or 60
	local last = lastSoftOfferAt[uid]
	if last ~= nil then
		wait = math.max(wait, cd - (now - last))
	end
	return math.max(0, wait)
end

function MonetizationService.ClaimSoftOfferSlot(player: Player): boolean
	if not player then
		return false
	end
	local cfg = MonetizationConfig :: any
	local now = os.clock()
	local first = firstOfferCfg()
	if first then
		-- Code Bot v153: the quiet window is the first FirstOffer.AtPlaySeconds (120 s) of the session, whatever the
		-- tutorial state (it was: none until the tutorial was done, or 900 s for players who never finish it)
		local started = sessionStartAt[player.UserId]
		if started == nil or now - started < (tonumber(first.AtPlaySeconds) or 120) then
			return false
		end
	-- v71 money (M1): no pop-ups during the tutorial (the Starter Pack offer comes right after it). A player who
	-- never finishes it becomes offerable after SoftOfferQuietMaxSeconds of play this session.
	elseif cfg.SoftOfferQuietUntilTutorialComplete == true and DataService then
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

--[[ Code Bot v153: give back a slot whose offer the client never showed (OfferLedger drop). slot = { Prev, At } from
	the claim: the cooldown clock goes back to Prev unless another offer claimed a slot since. ]]
local function refundSoftOfferSlot(player: Player, slot: any)
	if typeof(slot) ~= "table" then
		return
	end
	local uid = player.UserId
	softOffersClaimed[uid] = math.max(0, (softOffersClaimed[uid] or 0) - 1)
	if lastSoftOfferAt[uid] == slot.At then
		lastSoftOfferAt[uid] = slot.Prev
	end
end

-- claude-bud JOB 41 part B: the same claim with a refund ticket, for an offer the client may report as never shown
function MonetizationService.ClaimSoftOfferSlotRefundable(player: Player): { Prev: number?, At: number? }?
	local prev = lastSoftOfferAt[player.UserId]
	if not MonetizationService.ClaimSoftOfferSlot(player) then
		return nil
	end
	return { Prev = prev, At = lastSoftOfferAt[player.UserId] }
end

function MonetizationService.RefundSoftOfferSlot(player: Player, slot: any)
	refundSoftOfferSlot(player, slot)
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

-- claude-bud JOB 36: the passes a bundle pass counts as owning (MonetizationConfig Implies, e.g. the War Chest), only
-- while the shop overhaul is live for this player; {} otherwise
local function impliedPasses(player: Player, passKey: string): { string }
	local def: any = (MonetizationConfig.GamePasses :: any)[passKey]
	if typeof(def) ~= "table" or typeof(def.Implies) ~= "table" or not ShopOverhaulConfig.LiveFor(player.UserId) then
		return {}
	end
	return def.Implies
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
			for _, implied in ipairs(impliedPasses(player, passKey)) do -- claude-bud JOB 36: War Chest parts
				if cache[implied] ~= true then
					table.insert(flipped, implied)
				end
				cache[implied] = true
				setEntitlementAttr(player, implied)
			end
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
local function walkSpeedMultOf(def: any, userId: number?): number
	-- claude-bud JOB 40: the SKU's V2 multiplier while SpeedV2 is live for the player (else WalkSpeedMult)
	local m = if typeof(def) == "table" then (if userId ~= nil then (MonetizationConfig :: any).SpeedMultOf(def, userId) else tonumber(def.WalkSpeedMult)) else nil
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
	SKUs they own (GamePasses.ImpulseSpeed x1.5, DevProducts.SpeedBoost x2; v133), never the product of them: owning
	both gives x2. 1 when none is owned. A pass whose Id is 0 is never owned outside Studio mocks. Never yields. ]]
function MonetizationService.SpeedMultFor(player: Player): number
	local best = 1
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return best
	end
	for passKey, def in pairs(MonetizationConfig.GamePasses :: any) do
		local m = walkSpeedMultOf(def, player.UserId)
		-- claude-bud: the Speed Pass counts only while MonetizationConfig.Rollout is live for this player
		if m > best and MonetizationConfig.SkuLiveFor(player.UserId, passKey) and ownsCached(player, passKey) then
			best = m
		end
	end
	for productKey, def in pairs(MonetizationConfig.DevProducts :: any) do
		local m = walkSpeedMultOf(def, player.UserId)
		if m > best and ownsSkuCached(player, productKey) then
			best = m
		end
	end
	return best
end

-- SpeedBoost / Speed Pass: permanent move speed on the current character (F8: SpeedMultFor, the max of the owned SKUs)
--[[ v126 (owner: "the Speed Boost barely makes me faster"): the paid multiplier is applied AFTER any other writer.
	Today MonetizationService is the only server writer of a player's WalkSpeed (no armour / gun / combat slowdown).
	The guard below keeps it that way for the future: when anything else writes this Humanoid's WalkSpeed (value X,
	not the value this service wrote last) the paid speed becomes min(X x mult, cap) (0 stays 0, a slow stays a
	slow but still mult x faster than an unpaid player under the same slow). Leaving a seat (vehicle exit) re-applies.
	One guard per Humanoid (a respawn gets a fresh Humanoid and a fresh guard). ]]
local speedGuarded: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local speedWritten: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
local speedBase: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any

local function writePaidSpeed(player: Player, hum: Humanoid, base: number, who: string)
	local mult = MonetizationService.SpeedMultFor(player)
	if mult <= 1 then
		return -- nothing owned: WalkSpeed stays what the game set
	end
	local GameConfig = require(Shared.Configs.GameConfig)
	local default = tonumber(GameConfig.DefaultWalkSpeed) or 16
	local want = math.min(math.max(0, base) * mult, default * MAX_WALK_SPEED_MULT)
	speedBase[hum] = base
	speedWritten[hum] = want
	if math.abs(hum.WalkSpeed - want) < 0.01 then
		return
	end
	-- v123 /movedebug: the tagged setter (the only server write to a player's WalkSpeed)
	require(script.Parent.Parent.Modules.MoveDebug).SetWalkSpeed(hum, want, who)
end

local function applySpeedBoostToCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if MonetizationService.SpeedMultFor(player) <= 1 then
		return -- nothing owned: WalkSpeed stays the game default
	end
	local GameConfig = require(Shared.Configs.GameConfig)
	local default = tonumber(GameConfig.DefaultWalkSpeed) or 16
	writePaidSpeed(player, hum, speedBase[hum] or default, "MonetizationService.SpeedBoost")
	if speedGuarded[hum] then
		return
	end
	speedGuarded[hum] = true
	-- another writer changed WalkSpeed: apply the paid multiplier on top of ITS value
	hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		local wrote = speedWritten[hum]
		if wrote ~= nil and math.abs(hum.WalkSpeed - wrote) < 0.01 then
			return -- our own write
		end
		if player.Parent and player.Character == character then
			writePaidSpeed(player, hum, hum.WalkSpeed, "MonetizationService.SpeedBoost(after other writer)")
		end
	end)
	-- vehicle / chair exit: re-apply (defensive; a seat does not change WalkSpeed today)
	hum.Seated:Connect(function(active: boolean)
		if not active and player.Parent and player.Character == character then
			writePaidSpeed(player, hum, speedBase[hum] or default, "MonetizationService.SpeedBoost(seat exit)")
		end
	end)
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
		if ShopOverhaulConfig.LiveFor(player.UserId) then
			bonus = tonumber(ShopOverhaulConfig.Vip.CashBonusMult) or bonus -- claude-bud JOB 36: premium VIP +50 %
		end
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

--[[ claude-bud JOB 36: the player's passive income in $ per minute, cash multipliers included (the base's passive tick
	x EconomyService.GetCashMult "passive" / TickSeconds x 60). May yield once (a cold pass cache), like any ownership
	lookup; 0 when unknown. Cash packs, the VIP crate and the Shop's live amounts use it. ]]
-- claude-bud JOB 42: excludeTimed = leave out the TIMED multipliers (profile.CashBoost and the Double Cash event): the
-- time packs' income ("4 hours of your cash" must not double while a code / Recruit Pack boost runs). Same function.
function MonetizationService.PassivePerMin(player: Player, profile: any, excludeTimed: boolean?): number
	if BaseService == nil or EconomyService == nil or profile == nil then
		return 0
	end
	local okT, perTick = pcall(BaseService.ComputePassiveIncomePerTick, profile, player)
	local okM, mult = pcall(EconomyService.GetCashMult, player, "passive")
	local tick = math.max(1, tonumber((require(Shared.Configs.EconomyConfig) :: any).PassiveIncome.TickSeconds) or 5)
	local t = if okT then tonumber(perTick) or 0 else 0
	local m = if okM then tonumber(mult) or 1 else 1
	if excludeTimed == true then
		local okB, boost = pcall(function()
			return EconomyService.CashBoostMult and EconomyService.CashBoostMult(profile) or 1
		end)
		local okE, ev = pcall(function()
			local ES: any = require(script.Parent.EngagementService)
			return ES.CashMult and ES.CashMult(player) or 1
		end)
		local b = if okB then tonumber(boost) or 1 else 1
		local e = if okE then tonumber(ev) or 1 else 1
		m = m / math.max(1, b) / math.max(1, e)
	end
	local v = t * m / tick * 60
	return if v == v and v > 0 and v < 1e12 then v else 0
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
			-- claude-bud BOARDS: the real price (Roblox's PriceInRobux for this pass), the config price only as a fallback;
			-- counted once, here, after UserOwnsGamePassAsync confirmed the purchase
			local okP, info = pcall(function()
				return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
			end)
			if okP and typeof(info) == "table" and tonumber((info :: any).PriceInRobux) then
				price = nonNegInt((info :: any).PriceInRobux)
			end
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
					productKey = passKey, -- Code Bot v153: Custom "PassBought" (value = price, field = productKey)
					price = price,
					source = source,
				})
			end
			if first and profile then
				logFirstPurchase(player, profile, passKey)
			end
			firePassOwned(player, passKey, "purchase")
			for _, implied in ipairs(impliedPasses(player, passKey)) do -- claude-bud JOB 36: War Chest parts
				if cache[implied] ~= true then
					cache[implied] = true
					setEntitlementAttr(player, implied)
					firePassOwned(player, implied, "purchase")
				end
			end
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
	-- claude-bud JOB 41 part B: while the Recruit Pack offer is live for him it takes this pop-up slot (one starter
	-- offer per profile); the StarterBundle row stays in the Shop
	if (MonetizationConfig :: any).RecruitPackLiveFor(player.UserId) then
		return nil
	end
	local bundle = starterBundleLive()
	local profile = DataService.GetProfile(player)
	local first = firstOfferCfg()
	-- Code Bot v153: with FirstOffer on the tutorial state no longer matters (the 120 s quiet window times it)
	if not bundle or not profile or profile.StarterBundleOffered == true or (first == nil and profile.TutorialComplete ~= true) then
		return nil
	end
	if first and offerLedger:IsPending(player.UserId, "StarterBundle") then
		return true -- already out, waiting for the client's answer
	end
	if first and offerLedger:Exhausted(player.UserId, "StarterBundle") then
		return nil -- every send this session was dropped: next session (the flag is still unset)
	end
	if MonetizationService.PlayerOwnsEntitlement(player, "StarterBundle") then
		return nil
	end
	-- the lookup may have yielded
	if not player.Parent or DataService.GetProfile(player) ~= profile or profile.StarterBundleOffered == true then
		return nil
	end
	-- claude-bud JOB 5d: a real limited window (Placement.StarterLimitedHours after the first join)
	local limitedEnds: number? = nil
	local place: any = (MonetizationConfig :: any).Placement
	if MonetizationConfig.PlacementLiveFor(player.UserId) and typeof(place) == "table" and tonumber(place.StarterLimitedHours) then
		local first = tonumber((profile :: any).FirstJoinUnix) or os.time()
		limitedEnds = first + math.floor(place.StarterLimitedHours * 3600)
		if os.time() >= (limitedEnds :: number) then
			return nil -- the limited window is over: never offered again
		end
	end
	local prevSlotAt = lastSoftOfferAt[player.UserId]
	if not MonetizationService.ClaimSoftOfferSlot(player) then
		return false
	end
	local ackId: number? = nil
	if first then
		-- Code Bot v153 (root cause of "the Starter Pack is lost for good"): NOT marked offered here any more. The
		-- client often held this card (driving the 4x4 right after the tutorial) and dropped it 60 s later, while
		-- the saved flag already said "offered". The flag is set when the client answers "shown" (onOfferResult);
		-- a drop / refusal / no answer re-queues it.
		ackId = offerLedger:Sent(player.UserId, "StarterBundle", os.clock(), { Prev = prevSlotAt, At = lastSoftOfferAt[player.UserId] })
		local myAck = ackId
		task.delay(tonumber(first.AckTimeoutSeconds) or 100, function()
			MonetizationService._OfferResult(player, "StarterBundle", "timeout", myAck)
		end)
	else
		profile.StarterBundleOffered = true
		DataService.MarkDirty(player)
	end
	if RemoteSetup then
		local remote = RemoteSetup.Get(Constants.RemoteNames.StarterBundleOffer)
		if remote and remote:IsA("RemoteEvent") then
			(remote :: RemoteEvent):FireClient(player, {
				ProductKey = "StarterBundle",
				ProductId = bundle.Id,
				DisplayName = LivePrices.Name("DevProduct", "StarterBundle"), -- Code Bot v156: the Roblox product name
				RobuxPrice = LivePrices.Price("DevProduct", "StarterBundle"), -- Code Bot v156: the real price (was config 149)
				Reason = if typeof(reason) == "string" then reason else "session",
				EndsUnix = limitedEnds, -- claude-bud JOB 5d: the toast shows the time left (nil = no limit)
				AckId = ackId, -- Code Bot v153: echo back on OfferResult ("shown" / "dropped" / "refused")
				First = ackId ~= nil, -- Code Bot v153: the first offer: not held for the tutorial card
			})
		end
	end
	-- (no companion Info line: the client offer toast carries the offer — HUD v70 spec §4.2)
	return true
end

--[[ Code Bot v153: the client's answer about a confirmed-shown offer (OfferResult remote), or "timeout" from the
	send's own AckTimeoutSeconds timer. "shown" = mark it (StarterBundleOffered, saved) + OFFER_SHOWN; "dropped" /
	"refused" / "timeout" = refund the soft-offer slot and re-queue RequeueSeconds later (up to MaxSendsPerSession
	sends; then it waits for the next session, still unmarked). Only keys the ledger has a pending send for count. ]]
function MonetizationService._OfferResult(player: Player, key: string, result: string, ackId: number?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local action, slot = offerLedger:Result(player.UserId, key, result, ackId, os.clock())
	if action == "ignore" then
		return
	end
	if action == "mark" then
		local profile = DataService and DataService.GetProfile(player)
		if profile and key == "StarterBundle" then
			profile.StarterBundleOffered = true
			DataService.MarkDirty(player)
		end
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.OFFER_SHOWN, player.UserId, { productKey = key, key = key })
		end
		return
	end
	-- dropped / refused / timeout: the player never saw it
	if player.Parent then
		refundSoftOfferSlot(player, slot)
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.OFFER_RESULT, player.UserId, { productKey = key, key = key, result = result, requeued = action == "requeue" })
	end
	if action == "requeue" and player.Parent and key == "StarterBundle" then
		local first = firstOfferCfg()
		-- the new run starts after the wait (the answer can land while the sending run is still unwinding)
		task.delay(if first then tonumber(first.RequeueSeconds) or 45 else 45, function()
			if player.Parent then
				MonetizationService.ScheduleFirstOffer(player, "requeue", 0)
			end
		end)
	end
end

-- Code Bot v153: sitting in any seat (driving or riding)
local function seatedNow(player: Player): boolean
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	return hum ~= nil and hum.SeatPart ~= nil
end

-- Code Bot v153: FirstOffer.FallbackKeys: the best cheap offer when the Starter Pack is not wanted (once per profile;
-- the existing one-shot TrySoftOffer* gates decide). Returns true when one was sent.
local function tryFallbackOffer(player: Player, first: any): boolean
	local keys = if typeof(first.FallbackKeys) == "table" then first.FallbackKeys else {}
	for _, key in ipairs(keys) do
		if typeof(key) == "string" and MonetizationConfig.SkuLiveFor(player.UserId, key) and not ownsSkuCached(player, key) then
			if key == "SpeedBoost" then
				local profile = DataService and DataService.GetProfile(player)
				if profile and profile.SpeedBoostOffered ~= true then
					MonetizationService.TrySoftOfferSpeedBoost(player, "first_offer")
					return profile.SpeedBoostOffered == true
				end
			end
		end
	end
	return false
end

--[[ Code Bot v153: THE first-offer schedule (MonetizationConfig.FirstOffer). TutorialService calls it at load for
	every player (delay AtPlaySeconds) and when the tutorial ends; OfferResult re-queues through it. One run per
	player at a time (a second call while one waits is ignored). Each attempt: wait while seated (SeatedWaitSeconds
	in total), then TrySoftOfferStarterBundle: true = out (the ledger takes over), false = slot busy / quiet window
	(wait exactly until it frees, MaxSlotWaits times), nil = not wanted (reason "first_offer": the fallback, once). ]]
function MonetizationService.ScheduleFirstOffer(player: Player, reason: string, delaySec: number?)
	local first = firstOfferCfg()
	if not first or typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	-- claude-bud JOB 41 part B: the Recruit Pack replaces the first offer (and its fallback) for players it is live for
	if (MonetizationConfig :: any).RecruitPackLiveFor(player.UserId) then
		return
	end
	local uid = player.UserId
	if firstOfferToken[uid] ~= nil then
		return
	end
	firstOfferSeq += 1
	local my = firstOfferSeq
	firstOfferToken[uid] = my
	local seatedLeft = math.max(0, tonumber(first.SeatedWaitSeconds) or 30)
	local seatedStep = math.max(0.25, tonumber(first.SeatedCheckSeconds) or 1)
	local maxWaits = math.max(0, tonumber(first.MaxSlotWaits) or 6)
	local function attempt(n: number)
		if firstOfferToken[uid] ~= my then
			return
		end
		if not player.Parent then
			firstOfferToken[uid] = nil
			return
		end
		if seatedLeft > 0 and seatedNow(player) then
			seatedLeft -= seatedStep
			task.delay(seatedStep, attempt, n)
			return
		end
		local ok, res = pcall(MonetizationService.TrySoftOfferStarterBundle, player, reason)
		if firstOfferToken[uid] ~= my then
			return
		end
		if not ok then
			warn("[MonetizationService] first offer failed:", res)
			firstOfferToken[uid] = nil
			return
		end
		if res == true then
			firstOfferToken[uid] = nil
			return
		end
		if res == nil then
			firstOfferToken[uid] = nil
			if reason == "first_offer" then
				pcall(tryFallbackOffer, player, first)
			end
			return
		end
		-- false: the quiet window or another offer's cooldown: wait exactly until the slot frees
		local wait = MonetizationService.SoftOfferSlotWait(player)
		if wait == nil or n > maxWaits then
			firstOfferToken[uid] = nil
			return
		end
		task.delay(math.max(1, wait + 0.5), attempt, n + 1)
	end
	task.delay(math.max(0, tonumber(delaySec) or 0), attempt, 1)
end

-- test hook (tools/sim/run_first_offer_test.py reads the ledger through the pure module; this exposes the live one)
function MonetizationService._Ledger(): any
	return offerLedger
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

--[[ claude-bud JOB 5b: pass perks, server side. Bigger Army (a pass live for him that he owns) is mirrored into
	profile.Entitlements.BiggerArmy (SoldierService's cap reads it; GrantEntitlement pushes the Army panel); the VIP
	perks (MonetizationConfig.VIPPerks) set the display attribute WE_VIPTag (chat tag + the lounge door on HIS client;
	the lounge payout re-checks VIP ownership here on the server). ]]
--[[ claude-bud JOB 5d: one purchase prompt at a moment ("rebirth" | "army"), owner-only first
	(MonetizationConfig.Placement). Spends the soft-offer budget; nothing already owned; a FeaturePush "Offer" to this
	player only (the client toast prompts Roblox; every grant stays ProcessReceipt / pass ownership). ]]
function MonetizationService.OfferMoment(player: Player, moment: string)
	if typeof(player) ~= "Instance" or not player.Parent then
		return
	end
	local place: any = (MonetizationConfig :: any).Placement
	if typeof(place) ~= "table" or not MonetizationConfig.PlacementLiveFor(player.UserId) then
		return
	end
	local kind, key, title, cta = nil, nil, nil, nil
	if moment == "rebirth" and place.AfterRebirth == true then
		local dc: any = MonetizationConfig.GamePasses.DoubleCash
		if dc and (tonumber(dc.Id) or 0) ~= 0 and not ownsCached(player, "DoubleCash") then
			kind, key, title, cta = "GamePass", "DoubleCash", "Rebuild faster: 2x Cash", LivePrices.Cta("GamePass", "DoubleCash")
		else
			local cl: any = MonetizationConfig.DevProducts.CashLarge
			if cl and (tonumber(cl.Id) or 0) ~= 0 then
				local boost = 200000
				if ShopOverhaulConfig.LiveFor(player.UserId) then -- claude-bud JOB 36: the live pack amount
					local prof = DataService and DataService.GetProfile(player)
					boost = ShopOverhaulConfig.CashPackAmount("CashLarge", MonetizationService.PassivePerMin(player, prof)) or boost
				end
				local s = tostring(math.floor(boost)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
				kind, key, title, cta = "DevProduct", "CashLarge", "Fresh start boost: $" .. s, LivePrices.Cta("DevProduct", "CashLarge")
			end
		end
	elseif moment == "army" and place.ArmyWiped == true and ShopOverhaulConfig.LiveFor(player.UserId) then
		-- claude-bud JOB 36: the army-wiped offer sells Bigger Army (the pass); Army Expansion left the Shop
		local ba: any = (MonetizationConfig.GamePasses :: any)[ShopOverhaulConfig.ArmyWipedPass]
		if ba and (tonumber(ba.Id) or 0) ~= 0 and not ownsCached(player, ShopOverhaulConfig.ArmyWipedPass) then
			kind, key, title, cta = "GamePass", ShopOverhaulConfig.ArmyWipedPass, "Army down! Bigger Army: +10 soldiers", LivePrices.Cta("GamePass", ShopOverhaulConfig.ArmyWipedPass)
		end
	elseif moment == "army" and place.ArmyWiped == true then
		local rf: any = (MonetizationConfig.DevProducts :: any).SoldierRefill
		local ex: any = (MonetizationConfig.DevProducts :: any).ExtraSoldierSlot
		if rf and (tonumber(rf.Id) or 0) ~= 0 and MonetizationConfig.SkuLiveFor(player.UserId, "SoldierRefill") then
			kind, key, title, cta = "DevProduct", "SoldierRefill", "Army down! Refill instantly", LivePrices.Cta("DevProduct", "SoldierRefill")
		elseif ex and (tonumber(ex.Id) or 0) ~= 0 and not ownsCached(player, "ExtraSoldierSlot") then
			kind, key, title, cta = "DevProduct", "ExtraSoldierSlot", "Bigger army: +10 soldiers", LivePrices.Cta("DevProduct", "ExtraSoldierSlot")
		end
	end
	if key == nil or not MonetizationService.ClaimSoftOfferSlot(player) then
		return
	end
	local ev = RemoteSetup and RemoteSetup.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "Offer", { Kind = kind, Key = key, Title = title, Cta = cta, Source = "offer" })
	end
end

--[[ claude-bud JOB 5e: the Roblox Premium daily bonus (Retention.PremiumDailyCash once per UTC day, saved in
	profile.PremiumBonusDay). Server-side MembershipType check; on join and when the membership changes. ]]
function MonetizationService.TryPremiumBonus(player: Player)
	local R: any = (MonetizationConfig :: any).Retention
	if not player.Parent or typeof(R) ~= "table" or not MonetizationConfig.RetentionLiveFor(player.UserId) then
		return
	end
	if player.MembershipType ~= Enum.MembershipType.Premium then
		return
	end
	local profile: any = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local today = tonumber(os.date("!%Y%m%d")) or 0
	if tonumber(profile.PremiumBonusDay) == today then
		return
	end
	profile.PremiumBonusDay = today
	EconomyService.AddCash(player, R.PremiumDailyCash, "premium_daily")
	DataService.MarkDirty(player)
	if NotificationService then
		NotificationService.Notify(player, "Premium daily bonus +$" .. tostring(R.PremiumDailyCash), "Reward")
	end
end

--[[ claude-bud JOB 5e: the one-time group reward. The server checks the group itself (IsInGroupAsync), the flag
	profile.GroupRewardClaimed and the rollout; the client only asks. ]]
local function claimGroupReward(player: Player)
	local R: any = (MonetizationConfig :: any).Retention
	if typeof(R) ~= "table" or (tonumber(R.GroupId) or 0) <= 0 or not MonetizationConfig.RetentionLiveFor(player.UserId) then
		return
	end
	local profile: any = DataService.GetProfile(player)
	if profile == nil or profile.GroupRewardClaimed == true then
		return
	end
	local okG, inGroup = pcall(function()
		return player:IsInGroupAsync(R.GroupId)
	end)
	if not (okG and inGroup == true) then
		if NotificationService then
			NotificationService.Notify(player, "Join the group first, then tap again", "Info")
		end
		return
	end
	if not player.Parent or DataService.GetProfile(player) ~= profile or profile.GroupRewardClaimed == true then
		return -- the check yielded
	end
	profile.GroupRewardClaimed = true
	EconomyService.AddCash(player, R.GroupCash, "group_reward")
	DataService.MarkDirty(player)
	if NotificationService then
		NotificationService.Notify(player, "Group reward +$" .. tostring(R.GroupCash), "Reward")
	end
end

function MonetizationService.ApplyPassPerks(player: Player)
	if not player.Parent then
		return
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local ents = (profile :: any).Entitlements
	if MonetizationConfig.SkuLiveFor(player.UserId, "BiggerArmy") and ownsCached(player, "BiggerArmy") then
		if typeof(ents) ~= "table" or ents.BiggerArmy ~= true then
			MonetizationService.GrantEntitlement(player, "BiggerArmy")
			DataService.MarkDirty(player)
		end
		if SoldierService and SoldierService.Push then
			task.defer(function()
				pcall(SoldierService.Push, player)
			end)
		end
	end
	local vip = MonetizationConfig.VIPPerksLiveFor(player.UserId) and ownsCached(player, "VIP")
	pcall(function()
		player:SetAttribute("WE_VIPTag", if vip then true else nil)
		-- claude-bud JOB 36: the premium VIP's gold chat name (ShopOverhaulConfig.Vip.GoldName, owner-first)
		local gold = vip and ShopOverhaulConfig.Vip.GoldName == true and ShopOverhaulConfig.LiveFor(player.UserId)
		player:SetAttribute("WE_VIPGold", if gold then true else nil)
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
	-- Code Bot v156: the real Robux prices / names (GetProductInfo, cached, published on ReplicatedStorage)
	LivePrices.StartServer()

	-- Client may fire to log intent; grants still ONLY happen in ProcessReceipt
	local shopRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseDevProduct) :: RemoteEvent
	-- v71 money (M1): optional 2nd arg `source` (where the prompt came from), whitelisted; analytics only
	shopRemote.OnServerEvent:Connect(function(player: Player, productKey: any, rawSource: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestPurchaseDevProduct", productKey, rawSource) then -- claude-bud JOB 15: rate ceiling + argument schema
			return
		end
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
		if not MonetizationConfig.SkuLiveFor(player.UserId, productKey :: string) then
			return -- claude-bud: rollout gate; nothing is logged or prompted for a player it is not live for
		end
		local source = cleanSource(rawSource)
		rememberIntent(player, "DP:" .. (productKey :: string), source)
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.SHOP_PROMPT, player.UserId, {
				kind = "DevProduct",
				key = productKey,
				productKey = productKey, -- Code Bot v153: AnalyticsConfig Custom ProductPrompted reads productKey
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
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestPurchaseGamePass", passKey, rawSource) then -- claude-bud JOB 15: rate ceiling + argument schema
			return
		end
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
		if not MonetizationConfig.SkuLiveFor(player.UserId, passKey :: string) then
			return -- claude-bud: rollout gate
		end
		local source = cleanSource(rawSource)
		rememberIntent(player, "GP:" .. (passKey :: string), source)
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.SHOP_PROMPT, player.UserId, {
				kind = "GamePass",
				key = passKey,
				productKey = passKey, -- Code Bot v153: AnalyticsConfig Custom ProductPrompted reads productKey
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

	-- claude-bud JOB 5e: group reward remote (rate-limited) and the Premium bonus on a membership change
	do
		local groupRemote = RemoteSetup and RemoteSetup.Get(Constants.RemoteNames.RequestGroupReward)
		if groupRemote and groupRemote:IsA("RemoteEvent") then
			(groupRemote :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
				if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestGroupReward") then -- claude-bud JOB 15: rate ceiling + argument schema
					return
				end
				if RateLimitService and not RateLimitService.Allow(player, "group_reward", 1, 2) then
					return
				end
				claimGroupReward(player)
			end)
		end
		Players.PlayerMembershipChanged:Connect(function(player: Player)
			MonetizationService.TryPremiumBonus(player)
		end)
	end
	-- claude-bud JOB 5c: a saved army refill is spent right after its receipt is saved; the plaza airstrike remote
	MonetizationService.OnGranted(function(player: Player, productKey: string)
		if productKey == "SoldierRefill" and SoldierService and SoldierService.ConsumeRefills then
			SoldierService.ConsumeRefills(player)
		end
	end)
	do
		local okA, strike = pcall(function(): any
			return require(script.Parent.Parent.Modules.PlazaAirstrike)
		end)
		if okA and strike then
			pcall(strike.Start, {
				DataService = DataService,
				NotificationService = NotificationService,
				RateLimitService = RateLimitService,
				RemoteSetup = RemoteSetup,
			})
		end
	end
	-- claude-bud JOB 5b: pass perks when a pass is bought in-game; the VIP lounge (VIPPerks.Lounge)
	MonetizationService.OnPassOwned(function(player: Player, _passKey: string)
		MonetizationService.ApplyPassPerks(player)
	end)
	task.delay(10, function()
		local okL, lounge = pcall(function(): any
			return require(script.Parent.Parent.Modules.VIPLounge)
		end)
		if okL and lounge then
			pcall(lounge.Start, {
				IsVIP = function(pl: Player): boolean
					return MonetizationConfig.VIPPerksLiveFor(pl.UserId) and ownsCached(pl, "VIP")
				end,
				AddCash = function(pl: Player, n: number, why: string)
					EconomyService.AddCash(pl, n, why)
				end,
				Notify = function(pl: Player, msg: string, kind: string)
					if NotificationService then
						NotificationService.Notify(pl, msg, kind)
					end
				end,
			})
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
			MonetizationService.ApplyPassPerks(player) -- claude-bud JOB 5b: Bigger Army mirror, VIP tag
			MonetizationService.TryPremiumBonus(player) -- claude-bud JOB 5e
			if SoldierService and SoldierService.ConsumeRefills then
				pcall(SoldierService.ConsumeRefills, player) -- claude-bud JOB 5c: a refill banked before a crash
			end

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
		offerLedger:Forget(player.UserId) -- Code Bot v153
		firstOfferToken[player.UserId] = nil
	end)

	-- Code Bot v153: the client confirms a soft offer SHOWED (or was dropped / refused unseen): OfferLedger
	do
		local resultRemote = RemoteSetup.Get(Constants.RemoteNames.OfferResult)
		if resultRemote and resultRemote:IsA("RemoteEvent") then
			(resultRemote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, key: any, result: any, ackId: any)
				if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "OfferResult", key, result, ackId) then
					return
				end
				if typeof(key) ~= "string" or typeof(result) ~= "string" or (ackId ~= nil and typeof(ackId) ~= "number") then
					return
				end
				if RateLimitService and not RateLimitService.Allow(player, "offer_result", 2, 4) then
					return
				end
				MonetizationService._OfferResult(player, key, result, ackId)
			end)
		end
	end

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
		local tp = ShopOverhaulConfig.TimePacks.Packs[event.ProductKey]
		if tp then
			-- claude-bud JOB 42: the real granted number ("+$1,234,567 (4 hours of cash)")
			local s = tostring(math.floor(event.Cash))
			local commas = (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
			NotificationService.Notify(player, string.format("+$%s (%s)", commas, tp.Label), "Reward")
		else
			NotificationService.Notify(player, "Purchase granted: " .. event.DisplayName, "Reward")
		end
	end
	if AnalyticsService then
		local firstJoin = if typeof(profile) == "table" then nonNegInt(profile.FirstJoinUnix) else 0
		AnalyticsService.Log(AnalyticsConfig.Events.PURCHASE_RECEIPT, player.UserId, {
			productId = event.ProductId,
			productKey = event.ProductKey,
			receiptId = event.ReceiptId,
			currencySpent = event.CurrencySpent,
			perMinBucket = event.PerMinBucket, -- claude-bud JOB 42 (time packs only)
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
	-- claude-bud JOB 36: a cash pack scales with the buyer's passive income (ShopOverhaulConfig.CashPacks, owner-first):
	-- max(Floor, Minutes x $/min). The lookup may yield, so it is here, before any mutation, and re-checked after.
	if ShopOverhaulConfig.CashPacks[productKey :: string] ~= nil and ShopOverhaulConfig.LiveFor(player.UserId) then
		local perMin = MonetizationService.PassivePerMin(player, profile)
		if not player.Parent or DataService.GetProfile(player) ~= profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		cashGrant = nonNegInt(ShopOverhaulConfig.CashPackAmount(productKey :: string, perMin))
	end
	-- claude-bud JOB 42: a TIME pack = max(Floor, Minutes x his income at RECEIPT time), timed boosts left out. For ANY
	-- receipt of a time-pack Id (a paid receipt always gets the real amount); the lookup may yield, so it is here,
	-- before any mutation, and re-checked after (the same rule as the JOB 36 block above)
	local timePerMin: number? = nil
	if ShopOverhaulConfig.TimePacks.Packs[productKey :: string] ~= nil then
		local perMin = MonetizationService.PassivePerMin(player, profile, ShopOverhaulConfig.TimePacks.ExcludeTimedBoosts == true)
		if not player.Parent or DataService.GetProfile(player) ~= profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		timePerMin = perMin
		cashGrant = nonNegInt(ShopOverhaulConfig.TimePackAmount(productKey :: string, perMin))
	end
	-- claude-bud JOB 41 part B: the Recruit Pack's cash = RecruitPackOffer.IncomeMinutes of his income, clamped
	-- ($25k..$150k); computed here (the lookup may yield) and re-checked, before any mutation
	if productKey == "RecruitPack" then
		local perMin = MonetizationService.PassivePerMin(player, profile)
		if not player.Parent or DataService.GetProfile(player) ~= profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		cashGrant = nonNegInt((MonetizationConfig :: any).RecruitPackCash(perMin))
	end
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
		PerMinBucket = if timePerMin then ShopOverhaulConfig.PerMinBucket(timePerMin) else nil, -- claude-bud JOB 42
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
	-- claude-bud JOB 41 part B: the Recruit Pack's 2x cash boost through the ONE boost path (CodesService.GrantCashBoost:
	-- stacks like codes, capped at CashBoostMaxMinutes; it only mutates the profile, no yield)
	if productKey == "RecruitPack" then
		local o: any = (MonetizationConfig :: any).RecruitPackOffer
		local okC, CS = pcall(function(): any
			return require(script.Parent.CodesService)
		end)
		if okC and CS and CS.GrantCashBoost then
			pcall(CS.GrantCashBoost, player, o.BoostMinutes, o.BoostMult)
		end
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
					DisplayName = LivePrices.Name("GamePass", "VIP"), -- Code Bot v156
					RobuxPrice = LivePrices.Price("GamePass", "VIP"),
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
					DisplayName = LivePrices.Name("DevProduct", "SpeedBoost"), -- Code Bot v156
					RobuxPrice = LivePrices.Price("DevProduct", "SpeedBoost"),
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
					DisplayName = LivePrices.Name("DevProduct", "CashMega"), -- Code Bot v156
					RobuxPrice = LivePrices.Price("DevProduct", "CashMega"),
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
--[[ claude-bud JOB 36: the death offer while the shop overhaul is live: the Speed Boost dev product (the Speed Pass left
	the Shop). Same rules as the pass offer: once per session, tutorial done, ownership known, no speed owned yet, the
	soft-offer budget. ]]
local function deathSpeedProductOffer(victim: Player, cfg: any, productKey: string): boolean
	local product: any = (MonetizationConfig.DevProducts :: any)[productKey]
	if typeof(product) ~= "table" or (tonumber(product.Id) or 0) == 0 then
		return false
	end
	local userId = victim.UserId
	if cfg.OncePerSession ~= false and deathSpeedSent[userId] == true then
		return false
	end
	local profile = DataService.GetProfile(victim)
	if not profile or (cfg.RequireTutorialComplete ~= false and profile.TutorialComplete ~= true) then
		return false
	end
	if passCacheFilled[userId] ~= true or passRefreshRetries[userId] ~= nil or ownsSkuCached(victim, productKey) then
		return false
	end
	for _, key in ipairs(if typeof(cfg.SkipIfOwnsAny) == "table" then cfg.SkipIfOwnsAny else {}) do
		if typeof(key) == "string" and ownsSkuCached(victim, key) then
			return false
		end
	end
	if not MonetizationService.ClaimSoftOfferSlot(victim) then
		return false
	end
	deathSpeedSent[userId] = true
	local remote = RemoteSetup and RemoteSetup.Get(Constants.RemoteNames.DeathShopOffer)
	if remote and remote:IsA("RemoteEvent") then
		(remote :: RemoteEvent):FireClient(victim, { Offers = { productKey } })
	end
	return true
end

function MonetizationService.TryDeathSpeedOffer(victim: Player): boolean
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") or not victim.Parent or not DataService then
		return false
	end
	local cfg = (MonetizationConfig :: any).DeathSpeedOffer
	if typeof(cfg) ~= "table" or typeof(cfg.PassKey) ~= "string" then
		return false
	end
	if ShopOverhaulConfig.LiveFor(victim.UserId) then
		return deathSpeedProductOffer(victim, cfg, ShopOverhaulConfig.DeathOfferProduct) -- claude-bud JOB 36
	end
	local passKey: string = cfg.PassKey
	local pass = (MonetizationConfig.GamePasses :: any)[passKey]
	if typeof(pass) ~= "table" or typeof(pass.Id) ~= "number" or pass.Id == 0 then
		return false
	end
	if not MonetizationConfig.SkuLiveFor(victim.UserId, passKey) then
		return false -- claude-bud rollout gate: no death offer for a pass that is not on sale for this player
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
