--!strict
--[[
	Code Bot v102: social / community text shown in-game (the Codes panel).
	No URLs in-game: Roblox only allows off-platform links through its own approved social-link UI, so the Discord
	invite stays a placeholder here and is never shown. Put the real invite on the experience page's Social Links.
]]

local SocialConfig = {
	-- the line under the Redeem button in the Codes panel
	DiscordText = "Join Bud Studios Discord for free codes!",
	-- placeholder only: NOT displayed in-game (add the invite in Creator Hub → Social Links instead)
	DiscordInvite = "",
}

return SocialConfig
