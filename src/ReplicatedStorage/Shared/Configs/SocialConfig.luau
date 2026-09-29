--!strict
--[[
	Code Bot v102: social / community text shown in-game (the Codes panel).
	v104 (Code Bot, owner 2026-09-29): the real Bud Studios Discord invite. In-game it is PLAIN TEXT only
	(DiscordInviteText in a TextLabel: never a button, never a TextBox, never clickable), and only for a player whose
	PolicyService AllowedExternalLinkReferences lists "Discord" (Roblox's rule for naming off-platform socials);
	everyone else sees just DiscordText. Also add the invite in Creator Hub -> Social Links (the clickable one).
]]

local SocialConfig = {
	-- the line under the Redeem button in the Codes panel
	DiscordText = "Join Bud Studios Discord for free codes!",
	-- v104: the Bud Studios server (config / Creator Hub Social Links); never shown in-game as a link
	DiscordInvite = "https://discord.gg/tkjA2DFBmZ",
	-- v104: what the Codes panel shows (plain text, no scheme), policy-gated
	DiscordInviteText = "Discord: discord.gg/tkjA2DFBmZ",
}

return SocialConfig
