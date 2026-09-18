--!strict
--[[ Weapon ownership / equip / purchase validation helpers. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedRoot = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(SharedRoot.Configs.WeaponConfig)
local Types = require(SharedRoot.Types)

type PlayerProfile = Types.PlayerProfile

local CombatWeaponLogic = {}

function CombatWeaponLogic.EnsureStarter(profile: PlayerProfile)
	local starter = WeaponConfig.DefaultWeapon
	if typeof(profile.Weapons) ~= "table" then
		profile.Weapons = {}
	end
	if not profile.Weapons[starter] then
		profile.Weapons[starter] = true
	end
	if not profile.EquippedWeapon or not profile.Weapons[profile.EquippedWeapon] then
		profile.EquippedWeapon = starter
	end
end

function CombatWeaponLogic.Owns(profile: PlayerProfile, weaponId: string): boolean
	return profile.Weapons ~= nil and profile.Weapons[weaponId] == true
end

function CombatWeaponLogic.WeaponDef(id: string): any?
	return WeaponConfig.Weapons[id]
end

function CombatWeaponLogic.ClampWeaponId(weaponId: any): string?
	if typeof(weaponId) ~= "string" then
		return nil
	end
	if #weaponId > 64 then
		return nil
	end
	if WeaponConfig.Weapons[weaponId] == nil then
		return nil
	end
	return weaponId
end

return CombatWeaponLogic
