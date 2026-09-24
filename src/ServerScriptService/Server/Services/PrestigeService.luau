--!strict
--[[
	Prestige / Rebirth — server-authoritative.
	Each prestige: permanent +10% cash earnings (EconomyConfig.PrestigeCashMultiplierPerLevel).
	RebirthUnlocks from PrestigeConfig applied into profile.RebirthUnlocks (+ optional vehicle/weapon grants).
	Alias: DoRebirth == DoPrestige.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PrestigeConfig = require(Shared.Configs.PrestigeConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local PrestigeService = {}

local DataService: any = nil
local EconomyService: any = nil
local XPService: any = nil
local BaseService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local VehicleService: any = nil

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
		if newPrestige >= u.AtPrestige and not profile.RebirthUnlocks[u.Flag] then
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

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local bonus = cashBonusPer()
	local nextMultPct = math.floor((profile.Prestige + 1) * bonus * 100)
	local curMultPct = math.floor(profile.Prestige * bonus * 100)
	local remote = RemoteSetup.Get(Constants.RemoteNames.PrestigeStateUpdate) :: RemoteEvent
	local basePct = baseCompletionPercent(profile)
	remote:FireClient(player, {
		Prestige = profile.Prestige,
		CanPrestige = PrestigeService.CanPrestige(player),
		MinLevel = PrestigeConfig.MinLevelToPrestige,
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
		UnlockTrack = unlockListFor(profile.Prestige),
	})
end

function PrestigeService.CanPrestige(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	if profile.Level < PrestigeConfig.MinLevelToPrestige or profile.Prestige >= PrestigeConfig.MaxPrestige then
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

function PrestigeService.DoPrestige(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if profile.Prestige >= PrestigeConfig.MaxPrestige then
		return false, "MaxPrestige"
	end
	if profile.Level < PrestigeConfig.MinLevelToPrestige then
		return false, "LevelTooLow"
	end
	local fee = tonumber(PrestigeConfig.CashFee) or 0
	if fee > 0 and (tonumber(profile.Cash) or 0) < fee then
		return false, "NeedCashFee"
	end

	local reset = PrestigeConfig.ResetOnPrestige
	profile.Prestige += 1

	if fee > 0 then
		profile.Cash = math.max(0, (tonumber(profile.Cash) or 0) - fee)
	end
	if reset.Cash then
		profile.Cash = PrestigeConfig.StartingCashAfterPrestige
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

	local newly = applyUnlocks(player, profile, profile.Prestige)

	DataService.MarkDirty(player)

	if PrestigeConfig.GoldBonusOnPrestige > 0 then
		EconomyService.AddGold(player, PrestigeConfig.GoldBonusOnPrestige, "prestige")
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
		if BaseService.RefreshAllVisuals then
			BaseService.RefreshAllVisuals(player)
		end
	end

	pushState(player)

	local bonusPct = math.floor(profile.Prestige * cashBonusPer() * 100)
	local unlockNote = if #newly > 0 then (" Unlocked: " .. table.concat(newly, ", ") .. ".") else ""
	if NotificationService then
		NotificationService.Notify(
			player,
			string.format(
				"Rebirth P%d! +%d Gold. Cash earnings +%d%%%s",
				profile.Prestige,
				PrestigeConfig.GoldBonusOnPrestige,
				bonusPct,
				unlockNote
			),
			"Success",
			7
		)
	end
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(AnalyticsConfig.Events.PRESTIGE or "PRESTIGE", player.UserId, {
			prestige = profile.Prestige,
			unlocks = newly,
		})
	end

	return true, nil
end


-- v71 (HUD v70 spec §4.2): the near-rebirth nudge shows ONCE per session for each level in the window (L38, L39);
-- the Rebirth badge does the rest. Was: every 90 s, and it named a keyboard key that phones do not have.
local nearNudged: { [number]: { [number]: boolean } } = {}

-- v38: soft rebirth CTA when Level is within NearPrestigeLevels of Min
function PrestigeService.MaybeNearPrestigeToast(player: Player)
	if not NotificationService then
		return
	end
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return
	end
	local minLv = PrestigeConfig.MinLevelToPrestige or 40
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
function PrestigeService.DoRebirth(player: Player): (boolean, string?)
	return PrestigeService.DoPrestige(player)
end

function PrestigeService.Push(player: Player)
	pushState(player)
end

function PrestigeService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	BaseService = deps.BaseService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService
	VehicleService = deps.VehicleService

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestPrestige) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player)
		-- v69: extra taps are dropped silently (the allowed tap already answered) — never a strike
		if not RateLimitService.Allow(player, "prestige", 1, 2) then
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		local ok, err = PrestigeService.DoPrestige(player)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Cannot prestige: " .. tostring(err), "Warn")
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		nearNudged[player.UserId] = nil
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
