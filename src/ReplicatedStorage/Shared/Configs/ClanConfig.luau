--!strict
--[[ Clan scaffolding — session-authoritative roster; ClanId persisted on profile. ]]

local ClanConfig = {
	MaxNameLength = 24,
	MinNameLength = 3,
	MaxTagLength = 5,
	MinTagLength = 2,
	MaxMembers = 20,
	CreateCooldownSeconds = 30,
	-- Territory ownership: capturing while in a clan stamps runtime.ClanId = profile.ClanId
}

return ClanConfig
