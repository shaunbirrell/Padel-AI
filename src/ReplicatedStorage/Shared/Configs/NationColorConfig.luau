--!strict
--[[
	Nation color roster — assigned on join / first spawn.
	Used to tint captured territory flags for that player.
]]

export type NationColorDef = {
	Id: string,
	DisplayName: string,
	Color: Color3,
}

local NationColorConfig = {
	Colors = {
		{ Id = "Crimson", DisplayName = "Crimson Legion", Color = Color3.fromRGB(200, 45, 55) },
		{ Id = "Azure", DisplayName = "Azure Fleet", Color = Color3.fromRGB(45, 110, 220) },
		{ Id = "Emerald", DisplayName = "Emerald Guard", Color = Color3.fromRGB(40, 170, 90) },
		{ Id = "Amber", DisplayName = "Amber Corps", Color = Color3.fromRGB(220, 160, 40) },
		{ Id = "Violet", DisplayName = "Violet Spear", Color = Color3.fromRGB(140, 70, 200) },
		{ Id = "Ivory", DisplayName = "Ivory Shield", Color = Color3.fromRGB(230, 225, 210) },
		{ Id = "Obsidian", DisplayName = "Obsidian Wing", Color = Color3.fromRGB(55, 55, 65) },
		{ Id = "Cyan", DisplayName = "Cyan Patrol", Color = Color3.fromRGB(40, 190, 200) },
	} :: { NationColorDef },
}

return NationColorConfig
