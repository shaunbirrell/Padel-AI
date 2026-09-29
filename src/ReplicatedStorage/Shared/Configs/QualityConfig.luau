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
	Rollout = "all", -- v101
	SmallScreenShortSide = 480,
	LowFpsBelow = 28,
	LowFpsSeconds = 8,
	RecoverFpsAbove = 50,
	RecoverSeconds = 30,
	HideTier2BeyondStuds = 180,
	HideAnyBeyondStuds = 420,
	CheckHz = 1,
	ShadowsOffWhenLow = true,
	-- claude-bud JOB 24 §8 (owner: "town buildings vanish / pop when driving fast"): the cause was this governor, not
	-- instance streaming (StreamingEnabled is OFF). On a phone it is always LOW, and it took whole clusters out beyond
	-- 180 / 420 studs, checked once a second from the camera: at 60-100+ studs/s a building popped in late / vanished.
	--   * NeverHideKinds: WE_Cluster kinds (the part after "source:") that are buildings / landmarks: never hidden;
	--   * LookAheadSeconds: the distance is measured from where the camera will be this far ahead (its velocity);
	--   * FastHz: the check rate while the camera moves faster than FastStuds per second; ShowSlackStuds: hysteresis.
	NeverHideKinds = { "block", "tower", "landmark", "square", "town", "fort", "checkpoint", "motorpool", "mast", "ruins", "camp", "hold", "Booth" },
	LookAheadSeconds = 1.5,
	FastStuds = 30,
	FastHz = 3,
	ShowSlackStuds = 40,
	-- where the decoration lives (resolved from Workspace by name; missing ones are retried every few seconds)
	Folders = { "WorldFill", "WarEmpireSetup/WorldDressing" } :: { string },
}

function QualityConfig.LiveFor(userId: any): boolean
	if (require(script.Parent.MonetizationConfig) :: any).Launched("QualityTier") then
		return true -- claude-bud JOB 12: MonetizationConfig.LaunchAll
	end
	local mode = QualityConfig.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)
	end
	return false
end

return QualityConfig
