--!strict
--[[
	Promo code redemption — once per code per player. Server-validated Cash/Gold grants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CodesConfig = require(Shared.Configs.CodesConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local CodesService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local AntiExploitService: any = nil

local function normalize(code: string): string
	local s = string.upper(string.gsub(code, "%s+", ""))
	return s
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	if typeof(profile.RedeemedCodes) ~= "table" then
		profile.RedeemedCodes = {}
	end
	local redeemed: { string } = {}
	for id in pairs(profile.RedeemedCodes) do
		table.insert(redeemed, id)
	end
	table.sort(redeemed)
	local remote = RemoteSetup.Get(Constants.RemoteNames.CodeStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		Redeemed = redeemed,
		AvailableHints = { "WARFOUNDING", "BUILDCONQUER" },
	})
end

function CodesService.Redeem(player: Player, rawCode: any): (boolean, string?)
	if not RemoteGuard.IsIdString(rawCode, CodesConfig.MaxCodeLength or 32) then
		return false, "InvalidCode"
	end
	local code = normalize(rawCode :: string)
	local def = CodesConfig.Codes[code]
	if not def then
		return false, "UnknownCode"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if typeof(profile.RedeemedCodes) ~= "table" then
		profile.RedeemedCodes = {}
	end
	if profile.RedeemedCodes[code] then
		return false, "AlreadyRedeemed"
	end

	profile.RedeemedCodes[code] = true
	DataService.MarkDirty(player)

	local cash = tonumber(def.Cash) or 0
	local gold = tonumber(def.Gold) or 0
	if cash > 0 then
		EconomyService.AddCash(player, cash, "code")
	end
	if gold > 0 then
		EconomyService.AddGold(player, gold, "code")
	end

	if NotificationService then
		local name = def.DisplayName or code
		NotificationService.Notify(
			player,
			string.format("Code %s: +$%d · +%d Gold", name, cash, gold),
			"Reward"
		)
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.CODE_REDEEM, player.UserId, {
			code = code,
			cash = cash,
			gold = gold,
		})
	end
	pushState(player)
	return true, nil
end

function CodesService.Push(player: Player)
	pushState(player)
end

function CodesService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService
	AntiExploitService = deps.AntiExploitService

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestRedeemCode) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, code: any)
		if not RateLimitService.Allow(player, "redeem_code", 1, 3) then
			if AntiExploitService and AntiExploitService.Strike then
				AntiExploitService.Strike(player, "redeem_code_rate")
			end
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		local ok, err = CodesService.Redeem(player, code)
		if not ok and NotificationService then
			local msg = "Code failed"
			if err == "AlreadyRedeemed" then
				msg = "Code already redeemed"
			elseif err == "UnknownCode" then
				msg = "Unknown code"
			elseif err == "InvalidCode" then
				msg = "Invalid code"
			end
			NotificationService.Notify(player, msg, "Warn")
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		if typeof(profile.RedeemedCodes) ~= "table" then
			profile.RedeemedCodes = {}
			DataService.MarkDirty(player)
		end
		pushState(player)
	end)
end

return CodesService
