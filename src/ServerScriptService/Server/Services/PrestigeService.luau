--!strict
--[[
	Prestige / Rebirth — server-authoritative.
	Each prestige: permanent +10% cash earnings (EconomyConfig.PrestigeCashMultiplierPerLevel).
	RebirthUnlocks from PrestigeConfig applied into profile.RebirthUnlocks (+ optional vehicle/weapon grants).
	Alias: DoRebirth == DoPrestige.

	Owner's 11 features (lane P, spec_f11 F7 + F11):
	  Two rebirth paths, same gate (Level >= MinLevelToPrestige, Prestige < MaxPrestige):
	    free ("Cash")   ResetOnPrestige: cash, level, XP and every base upgrade reset
	    keep-base       ResetOnPrestigeKeepBase: the same but BaseUpgrades are KEPT. Spends one token from
	                    profile.KeepBaseRebirths. Tokens come ONLY from the 50 R$ RebirthKeepBase DevProduct: the
	                    receipt adds the token and saves it before PurchaseGranted (MonetizationService CounterGrants).
	                    The rebirth itself never runs inside the receipt: the OnGranted listener below (after the
	                    save) uses the token at once when this session prompted the product (purchase intent) and
	                    the player can rebirth; otherwise the token is banked for later. Tokens never expire.
	  PrestigeConfig.ResetFor(path) is the ONE reset table per path, and PrestigeConfig.RebirthSummary(path, ctx)
	  builds the confirm modal's KEEP / RESET / GAIN lines from the same table (pushed in PrestigeStateUpdate.Summary).
	  RequestPrestige(path): the keep-base path only when path == "KeepBase"; anything else is the free path. A
	  keep-base request with no token is refused and never falls through to the free path.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local PrestigeConfig = require(Shared.Configs.PrestigeConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local RebirthConfig = require(Shared.Configs.RebirthConfig) -- claude-bud JOB 33

-- claude-bud JOB 33: the level this player needs for his next rebirth (RebirthConfig.LiveFor "Pacing")
local function minLevelFor(player: Player, profile: any): number
	return PrestigeConfig.MinLevelFor(tonumber(profile and profile.Prestige) or 0, RebirthConfig.LiveFor(player.UserId, "Pacing"))
end

-- claude-bud JOB 33: this life's play time (profile.LifePlaySeconds + the running session), for the rebirth funnel
local sessionFrom: { [number]: number } = {}
local function lifeSeconds(player: Player, profile: any): number
	local from = sessionFrom[player.UserId]
	return (tonumber(profile.LifePlaySeconds) or 0) + (if from then os.clock() - from else 0)
end
local function bankPlay(player: Player, profile: any)
	local from = sessionFrom[player.UserId]
	if from then
		profile.LifePlaySeconds = math.floor((tonumber(profile.LifePlaySeconds) or 0) + (os.clock() - from))
		sessionFrom[player.UserId] = os.clock()
	end
end

local PrestigeService = {}

-- F7: DoPrestige options. KeepBase = true spends one keep-base token (profile.KeepBaseRebirths).
export type PrestigeOpts = { KeepBase: boolean? }

local DataService: any = nil
local EconomyService: any = nil
local XPService: any = nil
local BaseService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local VehicleService: any = nil
local MonetizationService: any = nil

local MAX_TOKENS = 1e15 -- same ceiling as ProfileSchema / MonetizationService counters
-- F11: coalesce state pushes caused by base buys / level-ups (the modal's "(N built)" line and the READY state)
local PUSH_COALESCE_SECONDS = 1.5

-- Whole number >= 0; junk (nil, strings, NaN, inf, negatives) becomes 0.
local function nonNegInt(value: any): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.clamp(math.floor(n), 0, MAX_TOKENS)
end

local function cashBonusPer(): number
	return PrestigeConfig.CashBonusPerPrestige
		or EconomyConfig.PrestigeCashMultiplierPerLevel
		or 0.10
end


local function baseCompletionPercent(profile: any): number
	local owned = 0
	local maxN = 0
	local upgrades = profile.BaseUpgrades
	if typeof(upgrades) ~= "table" then
		upgrades = {}
	end
	for id, _def in pairs(BaseConfig.Structures) do
		maxN += 1
		if (tonumber(upgrades[id]) or 0) > 0 then
			owned += 1
		end
	end
	if maxN <= 0 then
		return 0
	end
	return math.floor((owned / maxN) * 100)
end

-- F11: structure levels bought (the modal's "Base buildings (N built)" line; businesses count while merged)
local function builtCount(profile: any): number
	local upgrades = profile.BaseUpgrades
	if typeof(upgrades) ~= "table" then
		return 0
	end
	local n = 0
	for id in pairs(BaseConfig.Structures) do
		n += nonNegInt(upgrades[id])
	end
	return n
end

-- F11: war businesses are live (they reset with the base on the free path). A config error counts as off.
local function businessesOn(): boolean
	local ok, cfg = pcall(function(): any
		return require(Shared.Configs.BusinessConfig)
	end)
	return ok and typeof(cfg) == "table" and cfg.Enabled == true
end

-- F7: the keep-base product entry (MonetizationConfig.DevProducts[PrestigeConfig.KeepBase.ProductKey])
local function keepBaseProduct(): any
	local key = PrestigeConfig.KeepBase.ProductKey
	local def = (MonetizationConfig.DevProducts :: any)[key]
	return if typeof(def) == "table" then def else nil
end

-- F7: the keep-base path can be SOLD (the Rebirth modal prompts it) only while its Id is pasted and it is Enabled.
-- A saved token is always usable (it was paid for), whatever these say.
local function keepBaseLive(player: Player): boolean
	local def = keepBaseProduct()
	local id = if def then tonumber(def.Id) else nil
	-- claude-bud: MonetizationConfig.Rollout ("owner" first) gates the SALE only; a saved token is always usable
	return PrestigeConfig.KeepBase.Enabled == true
		and id ~= nil
		and id ~= 0
		and MonetizationConfig.SkuLiveFor(player.UserId, PrestigeConfig.KeepBase.ProductKey)
end

local function keepBasePrice(): number
	local def = keepBaseProduct()
	return nonNegInt(if def then def.RobuxPrice else 0)
end

-- display-only mirror of the token count (the same attribute the receipt's CounterGrants writes)
local function publishTokens(player: Player, profile: any)
	local spec = (MonetizationConfig :: any).CounterGrants
	local grant = if typeof(spec) == "table" then spec.GrantKeepBaseRebirths else nil
	local attr = if typeof(grant) == "table" and typeof(grant.Attribute) == "string" then grant.Attribute else "WE_KeepBaseRebirths"
	pcall(function()
		player:SetAttribute(attr, nonNegInt(profile.KeepBaseRebirths))
	end)
end

local function feeSummaryFor(profile: any): string
	local pct = baseCompletionPercent(profile)
	if PrestigeConfig.BuildFeeSummary then
		return PrestigeConfig.BuildFeeSummary({ BaseCompletionPercent = pct })
	end
	local fee = tonumber(PrestigeConfig.CashFee) or 0
	local feePart = if fee > 0 then string.format("Fee $%s", tostring(fee)) else "Fee: none"
	return string.format(
		"%s · Cash → $%s after · +%d Gold · Base %d%%",
		feePart,
		tostring(PrestigeConfig.StartingCashAfterPrestige or 0),
		tonumber(PrestigeConfig.GoldBonusOnPrestige) or 0,
		pct
	)
end


local function unlockListFor(prestige: number): { any }
	local list = {}
	for _, u in ipairs(PrestigeConfig.RebirthUnlocks or {}) do
		table.insert(list, {
			AtPrestige = u.AtPrestige,
			Flag = u.Flag,
			DisplayName = u.DisplayName,
			Kind = u.Kind,
			Id = u.Id,
			Unlocked = prestige >= u.AtPrestige,
		})
	end
	return list
end

local function applyUnlocks(player: Player, profile: any, newPrestige: number)
	if typeof(profile.RebirthUnlocks) ~= "table" then
		profile.RebirthUnlocks = {}
	end
	local newly: { string } = {}
	for _, u in ipairs(PrestigeConfig.RebirthUnlocks or {}) do
		local gateOk = (u :: any).Gate == nil or RebirthConfig.LiveFor(player.UserId, (u :: any).Gate) -- claude-bud JOB 33
		if gateOk and newPrestige >= u.AtPrestige and not profile.RebirthUnlocks[u.Flag] then
			profile.RebirthUnlocks[u.Flag] = true
			table.insert(newly, u.DisplayName or u.Flag)
			if u.GrantOwned and typeof(u.Id) == "string" then
				if u.Kind == "Vehicle" then
					profile.Vehicles[u.Id] = true
					if VehicleService and VehicleService.GrantVehicle then
						-- GrantVehicle marks dirty + push; safe even if already owned
						VehicleService.GrantVehicle(player, u.Id)
					end
				elseif u.Kind == "Weapon" then
					profile.Weapons[u.Id] = true
				end
			end
		end
	end
	return newly
end

-- per-player: the CanPrestige value last pushed (a level-up that flips it pushes at once), and a queued push
local lastPushedCan: { [number]: boolean } = {}
local pushQueued: { [number]: boolean } = {}

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local bonus = cashBonusPer()
	local prestige = nonNegInt(profile.Prestige)
	local level = math.max(1, nonNegInt(profile.Level))
	local xp = nonNegInt(profile.XP)
	local nextMultPct = math.floor((prestige + 1) * bonus * 100)
	local curMultPct = math.floor(prestige * bonus * 100)
	local remote = RemoteSetup.Get(Constants.RemoteNames.PrestigeStateUpdate) :: RemoteEvent
	local basePct = baseCompletionPercent(profile)
	local canPrestige = PrestigeService.CanPrestige(player)
	-- F11: the confirm modal's columns, built by the same function (and reset tables) DoPrestige uses
	local ctx: PrestigeConfig.RebirthSummaryCtx = {
		Built = builtCount(profile),
		Prestige = prestige,
		NextUnlock = PrestigeConfig.NextUnlockName(prestige),
		BusinessesOn = businessesOn(),
	}
	-- claude-bud JOB 33 (RebirthConfig.LiveFor "Screen"): what the next rebirth gives, in the GAIN column, and the next 3
	local screenLive = RebirthConfig.LiveFor(player.UserId, "Screen")
	local zoneAt: { [number]: string } = {}
	for _, zid in ipairs(RebirthConfig.ZoneOrder) do
		local z = RebirthConfig.Zones[zid]
		if z and RebirthConfig.LiveFor(player.UserId, "Zones") then
			zoneAt[z.Tier] = z.DisplayName
		end
	end
	if screenLive then
		local x: any = ctx
		x.Zone = zoneAt[prestige + 1]
		if RebirthConfig.LiveFor(player.UserId, "Perks") then
			x.Soldiers = RebirthConfig.PrestigeSoldierBonus(prestige + 1) - RebirthConfig.PrestigeSoldierBonus(prestige)
			x.StartCash = RebirthConfig.StartingCash(prestige + 1, false)
			x.Gold = RebirthConfig.GoldBonus(prestige + 1, false)
		end
	end
	local payload: Types.PrestigeStatePayload = {
		Prestige = prestige,
		CanPrestige = canPrestige,
		MinLevel = minLevelFor(player, profile), -- claude-bud JOB 33 pacing
		MaxPrestige = PrestigeConfig.MaxPrestige,
		CashBonusPerLevel = bonus,
		CashMultPercent = curMultPct,
		NextCashMultPercent = nextMultPct,
		GoldBonusOnPrestige = PrestigeConfig.GoldBonusOnPrestige,
		CashFee = tonumber(PrestigeConfig.CashFee) or 0,
		StartingCashAfter = PrestigeConfig.StartingCashAfterPrestige,
		BaseCompletionPercent = basePct,
		FeeSummary = feeSummaryFor(profile),
		RebirthUnlocks = profile.RebirthUnlocks or {},
		UnlockTrack = unlockListFor(prestige),
		-- F7 / F11 (display only; RequestPrestige and the receipt re-check everything)
		KeepBaseTokens = nonNegInt(profile.KeepBaseRebirths),
		KeepBaseLive = keepBaseLive(player),
		KeepBasePrice = keepBasePrice(),
		ProgressPct = PrestigeConfig.ProgressPct(level, xp),
		Level = level,
		XP = xp,
		Summary = {
			Cash = PrestigeConfig.RebirthSummary("Cash", ctx),
			KeepBase = PrestigeConfig.RebirthSummary("KeepBase", ctx),
		},
	};
	(payload :: any).Next3 = if screenLive then PrestigeConfig.NextRebirths(prestige, 3, zoneAt) else nil -- claude-bud JOB 33
	lastPushedCan[player.UserId] = canPrestige
	remote:FireClient(player, payload)
end

-- one push per player per PUSH_COALESCE_SECONDS for background changes (base buys, level-ups)
local function schedulePush(player: Player)
	local uid = player.UserId
	if pushQueued[uid] then
		return
	end
	pushQueued[uid] = true
	task.delay(PUSH_COALESCE_SECONDS, function()
		pushQueued[uid] = nil
		if player.Parent and DataService and DataService.GetProfile(player) then
			pushState(player)
		end
	end)
end

function PrestigeService.CanPrestige(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	if profile.Level < minLevelFor(player, profile) or profile.Prestige >= PrestigeConfig.MaxPrestige then
		return false
	end
	local fee = tonumber(PrestigeConfig.CashFee) or 0
	if fee > 0 and (tonumber(profile.Cash) or 0) < fee then
		return false
	end
	return true
end

function PrestigeService.HasUnlock(player: Player, flag: string): boolean
	local profile = DataService.GetProfile(player)
	if not profile or typeof(profile.RebirthUnlocks) ~= "table" then
		return false
	end
	return profile.RebirthUnlocks[flag] == true
end

-- F7: saved keep-base tokens (0 when the profile is not loaded)
function PrestigeService.KeepBaseTokens(player: Player): number
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return 0
	end
	return nonNegInt(profile.KeepBaseRebirths)
end

--[[ opts.KeepBase = true: the 50 R$ keep-base path (spends one token; refused with "NoKeepBaseToken" when there is
	none, never the free path instead). Everything from the checks to the last reset field runs without yielding,
	so two requests in the same frame (the OnGranted auto-use and a tap) give ONE rebirth: the second sees Level 1. ]]
function PrestigeService.DoPrestige(player: Player, opts: PrestigeOpts?): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local keepBase = typeof(opts) == "table" and opts.KeepBase == true
	if profile.Prestige >= PrestigeConfig.MaxPrestige then
		return false, "MaxPrestige"
	end
	if profile.Level < minLevelFor(player, profile) then
		return false, "LevelTooLow"
	end
	local levelAt = tonumber(profile.Level) or 0 -- claude-bud JOB 33: for the rebirth funnel
	if keepBase and nonNegInt(profile.KeepBaseRebirths) <= 0 then
		return false, "NoKeepBaseToken"
	end
	local fee = tonumber(PrestigeConfig.CashFee) or 0
	if fee > 0 and (tonumber(profile.Cash) or 0) < fee then
		return false, "NeedCashFee"
	end

	-- ── one no-yield block: token, prestige and the path's reset table ──
	local reset = PrestigeConfig.ResetFor(if keepBase then "KeepBase" else "Cash")
	if keepBase then
		profile.KeepBaseRebirths = nonNegInt(profile.KeepBaseRebirths) - 1
	end
	profile.Prestige += 1

	if fee > 0 then
		profile.Cash = math.max(0, (tonumber(profile.Cash) or 0) - fee)
	end
	if reset.Cash then
		-- claude-bud JOB 33 perks: the starting cash steps ($25k at R1 .. $250k at R20) replace the flat 10,000
		profile.Cash = if RebirthConfig.LiveFor(player.UserId, "Perks") then RebirthConfig.StartingCash(profile.Prestige, false) else PrestigeConfig.StartingCashAfterPrestige
	end
	if reset.Level then
		profile.Level = 1
	end
	if reset.XP then
		profile.XP = 0
	end
	if reset.BaseUpgrades then
		for id in pairs(BaseConfig.Structures) do
			profile.BaseUpgrades[id] = 0
		end
	end
	-- Vehicles / Weapons / Gold / RebirthUnlocks kept per Keep* flags.
	-- Income buffs survive rebirth: OutpostIncomeStacks + Territories are NOT reset
	-- (competitor-style permanent outpost income). PrestigeConfig unlocks unchanged.
	-- PendingCash (the ATM) is kept on both paths (owner decision, ASSUMPTIONS).
	-- ── end of the no-yield block ──

	local newly = applyUnlocks(player, profile, profile.Prestige)

	DataService.MarkDirty(player)
	if keepBase then
		publishTokens(player, profile)
	end

	-- claude-bud JOB 33 perks: gold 50 + 10 per rebirth (max 250) instead of the flat 50
	local goldGain = if RebirthConfig.LiveFor(player.UserId, "Perks") then RebirthConfig.GoldBonus(profile.Prestige, false) else PrestigeConfig.GoldBonusOnPrestige
	if goldGain > 0 then
		EconomyService.AddGold(player, goldGain, "prestige")
	end
	-- claude-bud JOB 33: the rebirth funnel (level + this life's minutes), then a fresh life
	if AnalyticsService and AnalyticsService.Log then
		pcall(AnalyticsService.Log, "REBIRTH_CONFIRMED", player.UserId, { level = levelAt, minutes = math.floor(lifeSeconds(player, profile) / 60), prestige = profile.Prestige })
	end
	profile.LifePlaySeconds = 0
	sessionFrom[player.UserId] = os.clock()
	profile.RebirthReadyLogged = nil
	-- claude-bud JOB 33: the zones / rank / army bonus for the new rebirth (a zone that just opened appears)
	do
		local okRZ, RZ = pcall(function(): any
			return require(script.Parent.RebirthZoneService)
		end)
		if okRZ and RZ and RZ.Refresh then
			task.defer(RZ.Refresh, player)
		end
	end

	-- Reaffirm outpost stacks from owned Territories (never wipe stacks on prestige)
	if EconomyService.SyncOutpostIncomeStacks then
		pcall(EconomyService.SyncOutpostIncomeStacks, player)
	end

	if EconomyService.Push then
		EconomyService.Push(player)
	end
	if XPService and XPService.Push then
		XPService.Push(player)
	end
	if BaseService and BaseService.PushState then
		BaseService.PushState(player)
		-- F7: the keep-base path changes no structure level, so the base is not rebuilt (0 instance changes)
		if reset.BaseUpgrades and BaseService.RefreshAllVisuals then
			BaseService.RefreshAllVisuals(player)
		end
	end

	pushState(player)

	local bonusPct = math.floor(profile.Prestige * cashBonusPer() * 100)
	local unlockNote = if #newly > 0 then (" Unlocked: " .. table.concat(newly, ", ") .. ".") else ""
	if NotificationService then
		local msg = if keepBase
			then string.format("Rebirth P%d!  Base kept  +%d Gold%s", profile.Prestige, goldGain, unlockNote)
			else string.format(
				"Rebirth P%d! +%d Gold. Cash earnings +%d%%%s",
				profile.Prestige,
				goldGain,
				bonusPct,
				unlockNote
			)
		NotificationService.Notify(player, msg, "Success", 7)
	end
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(AnalyticsConfig.Events.PRESTIGE or "PRESTIGE", player.UserId, {
			prestige = profile.Prestige,
			unlocks = newly,
			path = if keepBase then "keep_base" else "free",
		})
	end
	-- claude-bud JOB 11: the rebirth celebration on his client (JuiceConfig, owner-only first)
	do
		local okJ, JuiceConfig = pcall(function(): any
			return require(Shared.Configs.JuiceConfig)
		end)
		local ev = RemoteSetup and RemoteSetup.Get(Constants.RemoteNames.FeaturePush)
		if okJ and JuiceConfig and JuiceConfig.LiveFor(player.UserId) and ev and ev:IsA("RemoteEvent") then
			(ev :: RemoteEvent):FireClient(player, "Rebirth", {
				Prestige = profile.Prestige,
				Sub = if keepBase then "Base kept" else string.format("Cash earnings +%d%%", bonusPct),
			})
		end
	end
	-- claude-bud JOB 34: rebirth achievements + the "REBIRTHED for the Nth time!" line (AchievementConfig.Live)
	do
		local okA, AS = pcall(function(): any
			return require(script.Parent.AchievementService)
		end)
		if okA and AS and AS.OnRebirth then
			pcall(AS.OnRebirth, player)
		end
	end
	-- claude-bud JOB 5d: a purchase prompt after a rebirth (MonetizationConfig.Placement, owner-only first)
	if MonetizationService and MonetizationService.OfferMoment then
		task.delay(6, function()
			pcall(MonetizationService.OfferMoment, player, "rebirth")
		end)
	end

	return true, nil
end

-- F11: player-facing refusal copy (short, no key names; the modal also disables its buttons for these)
local REFUSAL_TEXT: { [string]: string } = {
	LevelTooLow = string.format("Reach Lv %d to rebirth", PrestigeConfig.MinLevelToPrestige),
	MaxPrestige = "Max rebirth reached",
	NeedCashFee = "Not enough cash to rebirth",
	NoKeepBaseToken = "No Keep-Base Rebirth saved",
	NoProfile = "Still loading, try again",
}

function PrestigeService.RefusalText(err: string?): string
	return REFUSAL_TEXT[tostring(err)] or "Rebirth not ready"
end

--[[ F7: after a RebirthKeepBase grant is SAVED (MonetizationService.OnGranted; never inside the receipt).
	Auto-use when KeepBase.AutoUseOnGrant, this session prompted the product (event.Source ~= "none": the purchase
	intent is at most MonetizationConfig.IntentAttributionSeconds old) and the player can rebirth now. Otherwise the
	token stays banked (saved; used from the Rebirth modal later). A receipt that lands before this listener exists
	(before PrestigeService.Init) is simply banked. ]]
local function onGranted(player: Player, productKey: string, event: any)
	local kb = PrestigeConfig.KeepBase
	if productKey ~= kb.ProductKey or typeof(event) ~= "table" then
		return
	end
	local counters = event.Counters
	local added = if typeof(counters) == "table" then nonNegInt(counters.KeepBaseRebirths) else 0
	if added <= 0 or not player.Parent then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	if kb.AutoUseOnGrant == true and event.Source ~= "none" and PrestigeService.CanPrestige(player) then
		local ok = PrestigeService.DoPrestige(player, { KeepBase = true })
		if ok then
			return
		end
	end
	pushState(player)
	-- a tap in the same frame (USE SAVED) may already have spent it: then there is nothing banked to announce
	if nonNegInt(profile.KeepBaseRebirths) <= 0 then
		return
	end
	if NotificationService then
		local level = tonumber(profile.Level) or 1
		local msg = if nonNegInt(profile.Prestige) >= PrestigeConfig.MaxPrestige
			then "Keep-Base Rebirth saved"
			elseif level < PrestigeConfig.MinLevelToPrestige then string.format("Keep-Base Rebirth saved  use it at Lv %d", PrestigeConfig.MinLevelToPrestige)
			else "Keep-Base Rebirth saved  use it in Rebirth"
		NotificationService.Notify(player, msg, "Success", 6)
	end
end

-- v71 (HUD v70 spec §4.2): the near-rebirth nudge shows ONCE per session for each level in the window (L38, L39);
-- the Rebirth badge does the rest. Was: every 90 s, and it named a keyboard key that phones do not have.
local nearNudged: { [number]: { [number]: boolean } } = {}

-- v38: soft rebirth CTA when Level is within NearPrestigeLevels of Min
-- XPService calls this on every level-up. F11: it also pushes the rebirth state when READY flips (the modal's
-- REBIRTH button), coalesced; the % bar itself follows XPUpdate on the client.
function PrestigeService.MaybeNearPrestigeToast(player: Player)
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return
	end
	if RemoteSetup then
		local can = PrestigeService.CanPrestige(player)
		local last = lastPushedCan[player.UserId]
		if last ~= nil and last ~= can then
			schedulePush(player)
		end
		-- claude-bud JOB 33: the rebirth funnel's first step, once per life
		if can and profile.RebirthReadyLogged ~= true and AnalyticsService and AnalyticsService.Log then
			profile.RebirthReadyLogged = true
			DataService.MarkDirty(player)
			pcall(AnalyticsService.Log, "REBIRTH_AVAILABLE", player.UserId, { level = tonumber(profile.Level) or 0, minutes = math.floor(lifeSeconds(player, profile) / 60) })
		end
	end
	if not NotificationService then
		return
	end
	local minLv = minLevelFor(player, profile) -- claude-bud JOB 33 pacing
	local near = PrestigeConfig.NearPrestigeLevels or 2
	local level = tonumber(profile.Level) or 1
	local prestige = tonumber(profile.Prestige) or 0
	local maxP = PrestigeConfig.MaxPrestige or 50
	if prestige >= maxP then
		return
	end
	if level >= minLv then
		return -- CanPrestige join toast covers READY
	end
	if level < (minLv - near) then
		return
	end
	local seen = nearNudged[player.UserId]
	if not seen then
		seen = {}
		nearNudged[player.UserId] = seen
	end
	if seen[level] then
		return
	end
	seen[level] = true
	local remain = minLv - level
	local msg = string.format(
		"Rebirth almost ready (Lv %d/%d) — %d level%s left · Keep all Robux Items",
		level,
		minLv,
		remain,
		if remain == 1 then "" else "s"
	)
	NotificationService.Notify(player, msg, "Info", 5.5)
end

-- Alias for MT-inspired "rebirth" wording
function PrestigeService.DoRebirth(player: Player, opts: PrestigeOpts?): (boolean, string?)
	return PrestigeService.DoPrestige(player, opts)
end

function PrestigeService.Push(player: Player)
	pushState(player)
end

--[[ Admin allowlist only (AdminService "givekeepbase"; never a remote of its own): adds n (1-5) keep-base tokens to
	the caller so the owner can test the keep-base path on his phone before the product Id is pasted. ]]
function PrestigeService.AdminGiveKeepBase(player: Player, n: number): (boolean, string?)
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local add = math.clamp(math.floor(tonumber(n) or 1), 1, 5)
	profile.KeepBaseRebirths = math.min(nonNegInt(profile.KeepBaseRebirths) + add, MAX_TOKENS)
	DataService.MarkDirty(player)
	publishTokens(player, profile)
	pushState(player)
	return true, nil
end

function PrestigeService.Init(deps: { [string]: any })
	-- claude-bud JOB 33: this life's play time (banked into profile.LifePlaySeconds every minute and on leave)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
				local pr = deps.DataService and deps.DataService.GetProfile(p)
				if pr and sessionFrom[p.UserId] then
					bankPlay(p, pr)
					deps.DataService.MarkDirty(p)
				end
			end
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(p: Player)
		local pr = deps.DataService and deps.DataService.GetProfile(p)
		if pr then
			bankPlay(p, pr)
		end
		sessionFrom[p.UserId] = nil
	end)
	deps.DataService.OnProfileLoaded(function(p: Player, _pr: any)
		sessionFrom[p.UserId] = os.clock()
	end)
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	BaseService = deps.BaseService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService
	VehicleService = deps.VehicleService
	MonetizationService = deps.MonetizationService

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestPrestige) :: RemoteEvent
	-- F7: optional 1st arg `path`. Only the exact string "KeepBase" picks the keep-base path (server-checked token).
	remote.OnServerEvent:Connect(function(player: Player, rawPath: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestPrestige", rawPath) then -- claude-bud JOB 15: rate ceiling + argument schema
			return
		end
		-- v69: extra taps are dropped silently (the allowed tap already answered) — never a strike
		if not RateLimitService.Allow(player, "prestige", 1, 2) then
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		local path = if rawPath == "KeepBase" then "KeepBase" else "Cash"
		local ok, err = PrestigeService.DoPrestige(player, { KeepBase = path == "KeepBase" })
		if not ok then
			if NotificationService then
				NotificationService.Notify(player, PrestigeService.RefusalText(err), "Warn")
			end
			-- the modal waits for a state push to leave REBIRTHING...
			pushState(player)
		end
	end)

	-- F7: use a keep-base token right after its receipt is saved (see onGranted)
	local mon = MonetizationService
	if mon and typeof(mon.OnGranted) == "function" then
		local okListen, listenErr = pcall(mon.OnGranted, onGranted)
		if not okListen then
			warn("[PrestigeService] OnGranted listener not registered:", listenErr)
		end
	end

	-- F11: keep the modal's "Base buildings (N built)" line true while the player buys (coalesced push)
	if BaseService and BaseService.GetUpgradeChangedEvent then
		local okEv, ev = pcall(BaseService.GetUpgradeChangedEvent)
		if okEv and ev and ev.Event then
			ev.Event:Connect(function(userId: any)
				local p = Players:GetPlayerByUserId(tonumber(userId) or 0)
				if p and lastPushedCan[p.UserId] ~= nil then
					schedulePush(p)
				end
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		nearNudged[player.UserId] = nil
		lastPushedCan[player.UserId] = nil
		pushQueued[player.UserId] = nil
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		if typeof(profile.RebirthUnlocks) ~= "table" then
			profile.RebirthUnlocks = {}
			DataService.MarkDirty(player)
		end
		-- Re-apply unlock flags for current prestige (idempotent) in case config grew
		applyUnlocks(player, profile, profile.Prestige or 0)
		pushState(player)
		-- UX: remind eligible commanders (MinLevelToPrestige = 40) that Rebirth is ready
		if PrestigeService.CanPrestige(player) and NotificationService then
			local msg = string.format(
				"REBIRTH READY (Lv %d) — %s · Rebirth for +10%% cash forever",
				tonumber(profile.Level) or PrestigeConfig.MinLevelToPrestige,
				feeSummaryFor(profile)
			)
			if NotificationService.NotifyThrottled then
				NotificationService.NotifyThrottled(player, msg, "Success", 6, 120, "prestige_ready_join")
			else
				NotificationService.Notify(player, msg, "Success", 6)
			end
		else
			PrestigeService.MaybeNearPrestigeToast(player)
		end
	end)
end

return PrestigeService
