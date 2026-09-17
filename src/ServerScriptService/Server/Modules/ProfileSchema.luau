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
		Gold = EconomyConfig.StartingGold,
		Level = 1,
		XP = 0,
		Prestige = 0,
		Soldiers = SoldierConfig.StartingSoldiers,
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

	if typeof((profile :: any).ProcessedReceipts) ~= "table" then
		(profile :: any).ProcessedReceipts = {}
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
