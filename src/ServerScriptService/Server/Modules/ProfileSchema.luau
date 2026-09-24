--!strict
--[[
	Default player profile + migrations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local SoldierConfig = require(Shared.Configs.SoldierConfig)
local VehicleConfig = require(Shared.Configs.VehicleConfig)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local SeasonConfig = require(Shared.Configs.SeasonConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local Types = require(Shared:WaitForChild("Types"))

type PlayerProfile = Types.PlayerProfile

local ProfileSchema = {}

local function emptyUpgrades(): { [string]: number }
	local upgrades: { [string]: number } = {}
	for id in pairs(BaseConfig.Structures) do
		upgrades[id] = 0
	end
	return upgrades
end

local function emptyDailyMissions(): Types.DailyMissionProgress
	return {
		DayKey = 0,
		Progress = {},
		Claimed = {},
		ActiveTimed = {},
	}
end

function ProfileSchema.CreateDefault(): PlayerProfile
	local now = os.time()
	return {
		DataVersion = Constants.CURRENT_DATA_VERSION,
		Cash = EconomyConfig.StartingCash,
		PendingCash = 0,
		Gold = EconomyConfig.StartingGold,
		Level = 1,
		XP = 0,
		Prestige = 0,
		RebirthUnlocks = {},
		Soldiers = SoldierConfig.StartingSoldiers,
		NationColorId = nil,
		RedeemedCodes = {},
		LastSpinnerClaimUnix = 0,
		Vehicles = {
			[VehicleConfig.StarterVehicle] = true,
		},
		Weapons = {
			[WeaponConfig.DefaultWeapon] = true,
		},
		EquippedWeapon = WeaponConfig.DefaultWeapon,
		Territories = {},
		BaseUpgrades = emptyUpgrades(),
		BasePlotId = nil,
		TutorialStep = 0,
		TutorialComplete = false,
		DailyLogin = {
			LastClaimDay = 0,
			Streak = 0,
			LastClaimUnix = 0,
		},
		DailyMissions = emptyDailyMissions(),
		Settings = {
			MusicVolume = 0.7,
			SFXVolume = 0.8,
			ShowDamageNumbers = true,
			AutoSprint = true,
		},
		Stats = {
			TotalCashEarned = 0,
			TotalGoldEarned = 0,
			UpgradesPurchased = 0,
			VehiclesSpawned = 0,
			MissionsCompleted = 0,
			TerritoriesCaptured = 0,
			Kills = 0,
			Deaths = 0,
			PlayTimeSeconds = 0,
		},
		Achievements = {},
		BattlePass = {
			SeasonId = SeasonConfig.CurrentSeasonId,
			XP = 0,
			Level = 0,
			Premium = false,
			ClaimedFree = {},
			ClaimedPremium = {},
		},
		ClanId = nil,
		FirstJoinUnix = now,
		LastJoinUnix = now,
		ProcessedReceipts = {},
		Entitlements = {},
		OutpostIncomeStacks = 0,
		StarterBundleOffered = false,
		AutoCollectOffered = false,
		DoubleCashOffered = false,
		VIPOffered = false,
		SpeedBoostOffered = false,
		CashMegaOffered = false,
		-- v69: Research Lab upgrades (UpgradeId → level) and raid / missile-strike timers (os.time seconds)
		Research = {},
		Raid = { ShieldUntil = 0, StrikeCooldownUntil = 0, DefensesDownUntil = 0 },
	}
end

--[[
	Migrate older profiles to CURRENT_DATA_VERSION.
	Add new migration steps as DataVersion increments.
]]
function ProfileSchema.Migrate(data: any): PlayerProfile
	if typeof(data) ~= "table" then
		return ProfileSchema.CreateDefault()
	end

	local profile = data :: PlayerProfile
	local version = tonumber(profile.DataVersion) or 0

	-- v0 / missing → fill defaults then set version
	if version < 1 then
		local defaults = ProfileSchema.CreateDefault()
		for key, value in pairs(defaults) do
			if profile[key] == nil then
				(profile :: any)[key] = value
			end
		end
		-- Ensure nested tables
		if typeof(profile.BaseUpgrades) ~= "table" then
			profile.BaseUpgrades = emptyUpgrades()
		else
			for id in pairs(BaseConfig.Structures) do
				if profile.BaseUpgrades[id] == nil then
					profile.BaseUpgrades[id] = 0
				end
			end
		end
		if typeof(profile.Vehicles) ~= "table" then
			profile.Vehicles = { [VehicleConfig.StarterVehicle] = true }
		elseif not profile.Vehicles[VehicleConfig.StarterVehicle] then
			profile.Vehicles[VehicleConfig.StarterVehicle] = true
		end
		if typeof(profile.Weapons) ~= "table" then
			profile.Weapons = { [WeaponConfig.DefaultWeapon] = true }
		elseif not profile.Weapons[WeaponConfig.DefaultWeapon] then
			profile.Weapons[WeaponConfig.DefaultWeapon] = true
		end
		profile.DataVersion = 1
		version = 1
	end

	-- v1 → v2: DailyMissions progress table
	if version < 2 then
		if typeof((profile :: any).DailyMissions) ~= "table" then
			(profile :: any).DailyMissions = emptyDailyMissions()
		else
			local dm = (profile :: any).DailyMissions
			if typeof(dm.Progress) ~= "table" then
				dm.Progress = {}
			end
			if typeof(dm.Claimed) ~= "table" then
				dm.Claimed = {}
			end
			if typeof(dm.ActiveTimed) ~= "table" then
				dm.ActiveTimed = {}
			end
			if typeof(dm.DayKey) ~= "number" then
				dm.DayKey = 0
			end
		end
		if typeof(profile.Achievements) ~= "table" then
			profile.Achievements = {}
		end
		if typeof(profile.Territories) ~= "table" then
			profile.Territories = {}
		end
		profile.DataVersion = 2
		version = 2
	end


	-- v2 → v3: ensure clan / season / battle pass / soldier / war-adjacent fields for older saves
	if version < 3 then
		if typeof(profile.Prestige) ~= "number" then
			profile.Prestige = 0
		end
		if typeof(profile.Soldiers) ~= "number" then
			profile.Soldiers = SoldierConfig.StartingSoldiers or 0
		end
		if profile.ClanId ~= nil and typeof(profile.ClanId) ~= "string" then
			profile.ClanId = nil
		end
		if typeof(profile.BattlePass) ~= "table" then
			profile.BattlePass = {
				SeasonId = SeasonConfig.CurrentSeasonId,
				XP = 0,
				Level = 0,
				Premium = false,
				ClaimedFree = {},
				ClaimedPremium = {},
			}
		else
			local bp = profile.BattlePass
			if typeof(bp.SeasonId) ~= "string" then
				bp.SeasonId = SeasonConfig.CurrentSeasonId
			end
			if typeof(bp.XP) ~= "number" then
				bp.XP = 0
			end
			if typeof(bp.Level) ~= "number" then
				bp.Level = 0
			end
			if typeof(bp.Premium) ~= "boolean" then
				bp.Premium = false
			end
			if typeof(bp.ClaimedFree) ~= "table" then
				bp.ClaimedFree = {}
			end
			if typeof(bp.ClaimedPremium) ~= "table" then
				bp.ClaimedPremium = {}
			end
		end
		if typeof(profile.Stats) == "table" then
			if typeof(profile.Stats.TerritoriesCaptured) ~= "number" then
				profile.Stats.TerritoriesCaptured = 0
			end
			if typeof(profile.Stats.Kills) ~= "number" then
				profile.Stats.Kills = 0
			end
			if typeof(profile.Stats.Deaths) ~= "number" then
				profile.Stats.Deaths = 0
			end
		end
		if typeof(profile.Territories) ~= "table" then
			profile.Territories = {}
		end
		if typeof(profile.Achievements) ~= "table" then
			profile.Achievements = {}
		end
		profile.DataVersion = 3
		version = 3
	end

	-- v3 → v4: nation color + redeemed codes (MT-inspired systems)
	if version < 4 then
		if profile.NationColorId ~= nil and typeof(profile.NationColorId) ~= "string" then
			profile.NationColorId = nil
		end
		if typeof(profile.RedeemedCodes) ~= "table" then
			profile.RedeemedCodes = {}
		end
		profile.DataVersion = 4
		version = 4
	end

	-- v4 → v5: free supply spinner cooldown stamp
	if version < 5 then
		if typeof((profile :: any).LastSpinnerClaimUnix) ~= "number" then
			(profile :: any).LastSpinnerClaimUnix = 0
		end
		profile.DataVersion = 5
		version = 5
	end


	-- v5 → v6: rebirth unlock flags (prestige track)
	if version < 6 then
		if typeof((profile :: any).RebirthUnlocks) ~= "table" then
			(profile :: any).RebirthUnlocks = {}
		end
		profile.DataVersion = 6
		version = 6
	end


	-- v6 → v7: Money Collector pending cash + entitlements flags
	if version < 7 then
		if typeof((profile :: any).PendingCash) ~= "number" then
			(profile :: any).PendingCash = 0
		end
		if typeof((profile :: any).Entitlements) ~= "table" then
			(profile :: any).Entitlements = {}
		end
		profile.DataVersion = 7
		version = 7
	end


	-- v7 → v8: permanent outpost income buff stacks
	if version < 8 then
		if typeof((profile :: any).OutpostIncomeStacks) ~= "number" then
			(profile :: any).OutpostIncomeStacks = 0
		end
		profile.DataVersion = 8
		version = 8
	end

	if typeof((profile :: any).ProcessedReceipts) ~= "table" then
		(profile :: any).ProcessedReceipts = {}
	end
	do
		local cashN = tonumber((profile :: any).Cash)
		profile.Cash = if typeof(cashN) == "number" then math.floor(cashN) else EconomyConfig.StartingCash
		local goldN = tonumber((profile :: any).Gold)
		profile.Gold = if typeof(goldN) == "number" then math.floor(goldN) else EconomyConfig.StartingGold
	end
	if typeof((profile :: any).PendingCash) ~= "number" then
		local pendN = tonumber((profile :: any).PendingCash)
		;(profile :: any).PendingCash = if typeof(pendN) == "number" then math.floor(pendN) else 0
	end
	if typeof((profile :: any).Entitlements) ~= "table" then
		(profile :: any).Entitlements = {}
	end
	if typeof((profile :: any).OutpostIncomeStacks) ~= "number" then
		(profile :: any).OutpostIncomeStacks = 0
	end
	if (profile :: any).StarterBundleOffered == nil then
		(profile :: any).StarterBundleOffered = false
	end
	if (profile :: any).AutoCollectOffered == nil then
		(profile :: any).AutoCollectOffered = false
	end
	if (profile :: any).DoubleCashOffered == nil then
		(profile :: any).DoubleCashOffered = false
	end
	if (profile :: any).VIPOffered == nil then
		(profile :: any).VIPOffered = false
	end
	if (profile :: any).SpeedBoostOffered == nil then
		(profile :: any).SpeedBoostOffered = false
	end
	if (profile :: any).CashMegaOffered == nil then
		(profile :: any).CashMegaOffered = false
	end
	-- v69: Research levels + raid / strike timers (idempotent; no DataVersion bump needed for new tables)
	if typeof((profile :: any).Research) ~= "table" then
		(profile :: any).Research = {}
	end
	do
		local raid = (profile :: any).Raid
		if typeof(raid) ~= "table" then
			raid = {}
			;(profile :: any).Raid = raid
		end
		for _, k in ipairs({ "ShieldUntil", "StrikeCooldownUntil", "DefensesDownUntil" }) do
			if typeof(raid[k]) ~= "number" then
				raid[k] = 0
			end
		end
	end

	-- v64: always ensure nested tables (corrupt DS / partial migrate must not nil-index on buy)
	if typeof(profile.BaseUpgrades) ~= "table" then
		profile.BaseUpgrades = emptyUpgrades()
	else
		for id in pairs(BaseConfig.Structures) do
			if profile.BaseUpgrades[id] == nil then
				profile.BaseUpgrades[id] = 0
			end
		end
	end
	if typeof(profile.Stats) ~= "table" then
		profile.Stats = {
			TotalCashEarned = 0,
			TotalGoldEarned = 0,
			UpgradesPurchased = 0,
			VehiclesSpawned = 0,
			MissionsCompleted = 0,
			TerritoriesCaptured = 0,
			Kills = 0,
			Deaths = 0,
			PlayTimeSeconds = 0,
		}
	else
		if typeof(profile.Stats.UpgradesPurchased) ~= "number" then
			profile.Stats.UpgradesPurchased = math.floor(tonumber(profile.Stats.UpgradesPurchased) or 0)
		end
	end

	profile.DataVersion = Constants.CURRENT_DATA_VERSION
	return profile
end

function ProfileSchema.DeepCopy(profile: PlayerProfile): PlayerProfile
	-- Simple recursive copy sufficient for our schema
	local function copy(v: any): any
		if typeof(v) ~= "table" then
			return v
		end
		local t = {}
		for k, val in pairs(v) do
			t[k] = copy(val)
		end
		return t
	end
	return copy(profile) :: PlayerProfile
end

return ProfileSchema
