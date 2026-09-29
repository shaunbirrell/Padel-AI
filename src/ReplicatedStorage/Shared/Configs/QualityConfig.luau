--!strict
--[[
	claude-bud JOB 8 (2026-09-29): the automatic LOW quality tier for phones (Client/Modules/QualityGovernor).
	Low turns on for a player it is live for when:
	  * the screen is small (viewport shorter side <= SmallScreenShortSide real px, i.e. a phone in landscape), or
	  * the frame rate stays under LowFpsBelow for LowFpsSeconds (and it goes back to normal only after RecoverSeconds
	    over RecoverFpsAbove, and never on a small screen).
	While low (client only; nothing replicates, the server world is unchanged):
	  * decoration clusters (WorldKits clusters: WE_Cluster, in the Folders below) are taken out of this client's world
	    beyond HideTier2BeyondStuds (Tier 2 = Full-quality extras) or HideAnyBeyondStuds (everything else), checked at
	    CheckHz with the camera focus (no per-frame work; the cluster list is built once and kept up to date);
	  * Lighting.GlobalShadows off on this client;
	  * the player attribute WE_LowQuality = true, which ProductionFx.IsLowFx() reads (cheaper effects).
	Rollout "owner" = AdminConfig.IsPlaytestOwner only, "all", anything else = off (the game as before).
]]

local QualityConfig = {
	Rollout = "owner",
	SmallScreenShortSide = 480,
	LowFpsBelow = 28,
	LowFpsSeconds = 8,
	RecoverFpsAbove = 50,
	RecoverSeconds = 30,
	HideTier2BeyondStuds = 180,
	HideAnyBeyondStuds = 420,
	CheckHz = 1,
	ShadowsOffWhenLow = true,
	-- where the decoration lives (resolved from Workspace by name; missing ones are retried every few seconds)
	Folders = { "WorldFill", "WarEmpireSetup/WorldDressing" } :: { string },
}

function QualityConfig.LiveFor(userId: any): boolean
	local mode = QualityConfig.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)
	end
	return false
end

return QualityConfig
