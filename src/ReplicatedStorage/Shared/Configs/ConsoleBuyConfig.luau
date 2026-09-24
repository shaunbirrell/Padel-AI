--!strict
--[[
	v71 console-only structure buying. Owner: "I don't think you should be able to just buy all the items from the
	base dashboard ... you should have to actually go and click the button".

	Base structures (BaseConfig.Structures) are built / upgraded ONLY at that structure's own console (walk-in
	building) or kiosk (outdoor installation) on YOUR plot: the BUY button in the action lane or the console's
	ProximityPrompt. The Base panel is an overview; its row button is GO (shows the way, never buys).

	Server truth (Shared/Util/ConsoleLocator + BaseService.PurchaseUpgrade): the player's HumanoidRootPart, as the
	server sees it, within a CYLINDER around that structure's console part on the player's own plot:
	horizontal (XZ) distance <= PromptDistance + ServerSlack and |dy| <= MaxVerticalOffset (the MissileStrike
	"at the Command Center" check works the same way). Positions come from the real console part, so rotated plots
	(BaseLayout.PlotCFrame / FaceMapCentre) need no math here.

	This is a presence rule for honest clients and the UI, enforced on the server. It is not anti-teleport: the
	character is network-owned by its player, so an exploiter who teleports next to the console meets the rule.
]]

local ConsoleBuyConfig = {
	-- Master switch. false = the server stops checking presence (rollback only). The Base panel stays GO-only.
	Enabled = true,

	-- ProximityPrompt WE_ServerBuyPrompt (UpgradePadService; these were the literals 10 / 16 / 0.35 / 0)
	ConsolePromptDistance = 10, -- console / kiosk MaxActivationDistance (studs, HRP -> console part centre)
	PadPromptDistance = 16, -- legacy walk-over pad (only when BaseLayoutConfig.Enabled = false)
	ConsoleHoldSeconds = 0.35, -- walking past never buys
	PadHoldSeconds = 0,

	-- Server check, horizontal: |HRP - buy point centre|xz <= (ConsolePromptDistance | PadPromptDistance) + ServerSlack.
	-- The client BUY box (WorldPromptController CONSOLE_MARGIN 5) reaches 8.5 studs horizontally, so the slack covers
	-- 9.5 studs of the server's HRP trailing the client: 0.59 s at WalkSpeed 16, 0.47 s with the Speed Boost (20).
	ServerSlack = 8,
	-- Server check, vertical: |HRP.Y - buy point centre.Y|. Covers the client BUY box (-4.7 .. +9.7) and a jump at the
	-- console (+8.5); refuses the upper floor of a two-storey walk-in (+14.1 above a ground-floor console).
	MaxVerticalOffset = 10,
	RejectSeated = true, -- seated (vehicle / chair) -> refused; the client already hides BUY while seated
	-- With two consoles in range only the nearest buys (horizontal distance). Margin in studs.
	RequireNearest = true,
	NearestMargin = 0.5,
	-- Console part missing on the player's plot (map rebuild in flight): "Deny" (refuse + warn once per plot and
	-- structure) or "Allow" (skip the check). v71 world: 15 / 15 consoles on 6 / 6 plots at L0 and L5.
	NoConsolePolicy = "Deny",

	-- Base panel GO -> waypoint to the console (client Modules/ConsoleWaypoint)
	Waypoint = {
		ArriveRadius = 10, -- cleared when the HRP is this close (the BUY button takes over)
		TimeoutSeconds = 120,
		RetrySeconds = 0.5, -- rebuild / retarget attempts (respawn, console streamed in) at most this often
		BeamWidth0 = 0.22, -- HUD rule: no beam wider than 0.25 or LightEmission above 0.3 outside the tutorial
		BeamWidth1 = 0.12,
		BeamLightEmission = 0.2,
		BeamColor = Color3.fromRGB(240, 214, 110),
		MarkerLift = 3, -- studs above the console top
		-- marker BillboardGui (real px): 14-20 px text (CLAUDE.md world labels), width follows the name length
		MarkerMinWidth = 140,
		MarkerMaxWidth = 300,
		MarkerMinTextPx = 14,
		MarkerMaxTextPx = 20,
		RefreshHz = 10, -- arrival check + distance label (CLAUDE.md: UI refresh <= 10 Hz)
	},

	Text = {
		NotAtConsole = "Go to your %s console to buy it", -- %s = BaseConfig DisplayName
		PanelSubtitle = "Buy at each building's console. GO shows the way.",
		Go = "GO",
		Max = "MAX",
		Needs = "Needs %s Lv %d", -- locked row: first unmet requirement
		Build = "Build %s", -- %s = cost
		Upgrade = "Lv %d -> %d  %s",
		WaypointSet = "Follow the line to the %s console",
		NoConsole = "Can't find that console yet. Try again in a moment.",
	},
}

return ConsoleBuyConfig
