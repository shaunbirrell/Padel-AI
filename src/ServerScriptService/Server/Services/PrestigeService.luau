--!strict
--[[
	Prestige reset — server-authoritative.
	Cash earnings mult applied in EconomyService via EconomyConfig.PrestigeCashMultiplierPerLevel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PrestigeConfig = require(Shared.Configs.PrestigeConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
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
local AntiExploitService: any = nil

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local remote = RemoteSetup.Get(Constants.RemoteNames.PrestigeStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		Prestige = profile.Prestige,
		CanPrestige = PrestigeService.CanPrestige(player),
		MinLevel = PrestigeConfig.MinLevelToPrestige,
		MaxPrestige = PrestigeConfig.MaxPrestige,
		CashBonusPerLevel = PrestigeConfig.CashBonusPerPrestige,
		GoldBonusOnPrestige = PrestigeConfig.GoldBonusOnPrestige,
	})
end

function PrestigeService.CanPrestige(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	return profile.Level >= PrestigeConfig.MinLevelToPrestige and profile.Prestige < PrestigeConfig.MaxPrestige
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

	local reset = PrestigeConfig.ResetOnPrestige
	profile.Prestige += 1

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
	-- Vehicles / Weapons / Gold kept per Keep* flags (no-op when true)

	DataService.MarkDirty(player)

	if PrestigeConfig.GoldBonusOnPrestige > 0 then
		EconomyService.AddGold(player, PrestigeConfig.GoldBonusOnPrestige, "prestige")
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

	if NotificationService then
		NotificationService.Notify(
			player,
			string.format("Prestiged to P%d! +%d Gold. Cash earnings +%d%%.", profile.Prestige, PrestigeConfig.GoldBonusOnPrestige, math.floor(profile.Prestige * PrestigeConfig.CashBonusPerPrestige * 100)),
			"Success",
			6
		)
	end
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(AnalyticsConfig.Events.PRESTIGE or "PRESTIGE", player.UserId, { prestige = profile.Prestige })
	end

	return true, nil
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
	AntiExploitService = deps.AntiExploitService

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestPrestige) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player)
		if not RateLimitService.Allow(player, "prestige", 1, 2) then
			if AntiExploitService and AntiExploitService.Strike then
				AntiExploitService.Strike(player, "prestige_rate")
			end
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

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		pushState(player)
	end)
end

return PrestigeService
