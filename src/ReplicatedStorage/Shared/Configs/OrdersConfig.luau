--!strict
--[[
	Squad Orders (walkie) — Follow / Attack / Hold / Retreat.
	Field units project SoldierService army counts (not a second recruit economy).
]]

local OrdersConfig = {
	Enabled = true,

	MinSoldiersToShow = 1,
	MaxFieldUnits = 5,
	UnitsPerSoldier = 1,

	OrderRatePerSec = 2,
	OrderBurst = 4,

	DefaultOrder = "Follow",

	Orders = {
		Follow = true,
		Attack = true,
		Hold = true,
		Retreat = true,
	},

	ThinkInterval = 0.4,
	FollowDistance = 10, -- old grid only (FollowSlots empty): face the player beyond this
	FollowStopDistance = 6, -- old grid only: stop within this of the player
	FormationSpacing = 3.5, -- old grid (3 wide, rows 6 / 9.5 / 13 studs straight behind the player)
	-- Base identity lane C (owner: the squad blocked the camera). Follow slots in player-local studs: +X is the
	-- player's right, +Z is BEHIND the player. Two wings beside the player, clear of the third-person camera's
	-- line to the player (the old grid put 2 of 5 units right between the camera and you). Slot 6+ (Squad
	-- Expansion research) repeats the list FollowRankStepZ further back per rank. Empty list = the old grid.
	FollowSlots = {
		{ X = -5.5, Z = 1.5 },
		{ X = 5.5, Z = 1.5 },
		{ X = -10, Z = 3.5 },
		{ X = 10, Z = 3.5 },
		{ X = -14.5, Z = 5.5 },
	},
	FollowRankStepZ = 3.5,
	FollowArriveStuds = 2, -- within this of its slot a unit stands still and faces where the player faces
	FollowMirrorHysteresis = 3, -- after a turn the wings swap sides when that saves this many studs per unit
	-- FollowPath: a unit that cannot walk straight to its slot stands against the wall beside the player when the slot
	-- is inside or behind that wall (walking along a building), squeezes in when a wall end is in its way, else walks
	-- the player's own trail (a 6-stud door, a narrow lane, a floor above) and fans back out once its slot is
	-- walkable. Server raycasts per unit per think (2.5 Hz): 0 in its slot, 2 on the way, 5 against a wall, 5-11 on
	-- the trail, a full trail scan only on losing its place (at most every RescanSeconds when nothing is walkable).
	-- Enabled = false = straight MoveTo, as before.
	FollowPath = {
		Enabled = true,
		CrumbSpacing = 3, -- studs the player moves before a new trail point
		MaxCrumbs = 12,
		ResetJump = 40, -- a jump this far (respawn, recall, vehicle) starts a new trail
		ReachStuds = 2.5, -- a unit this close to its trail point takes the next one
		StopGap = 4, -- trail points closer than this to the player are skipped (a cut-off unit stops behind you)
		RescanSeconds = 2,
		RayDrop = 1, -- rays run this far below the root centres (knee-to-waist): kerbs and pads never block
		RayHalfWidth = 0.9, -- one ray along each edge of the unit's 2-stud body
		WallGap = 1.5, -- a unit against a wall stands this far off it
		MinSide = 3, -- ...and only when that leaves this much room from the player's centre line (else the trail)
		SqueezeStuds = 2, -- a wall end in the way of an open slot: aim this much nearer the player instead
	},
	AttackAggroRange = 120,
	AttackRange = 55,
	AttackDamage = 8,
	AttackFireRate = 1.8,
	HoldLeashStuds = 14,
	UnitHealth = 90,
	UnitWalkSpeed = 14,
	UnitColor = Color3.fromRGB(70, 90, 55),

	VisualKind = "Infantry",
	DisplayName = "Squad",
	ShowUnitLabels = false, -- v68: floating "SQUAD" tag over every field unit (owner: clutter)
	-- v38: brief order state over nearest soldier
	OrderBillboardSeconds = 2.8,
	OrderLabels = {
		Follow = "FOLLOWING",
		Attack = "ATTACKING",
		Hold = "HOLDING",
		Retreat = "RETREATING",
	},

	-- v70 Army popover (spec §3.8): never auto-shown. The rail's Army tile / Y toggles it; it sits right of the
	-- tile (AnchorPoint 0,0.5 at tile right + GapFromTile, tile centre, clamped to the safe area). Sizes are in v
	-- under the one HUD UIScale (HudLayout.ApplyScreen: 0.70 on phones), so 64 v = 44.8 real px.
	Walkie = {
		Size = UDim2.fromOffset(216, 180), -- desktop: title + 2×2 cells of 100×44 v + MANAGE row 40 v
		SizeTouch = UDim2.fromOffset(216, 244), -- 2×2 cells of 96×64 v + title + MANAGE row
		MinTouchPx = 64, -- v; 56 v × 0.70 = 39 px was under the 44 px touch minimum
		PanelMaxWidth = 240, -- popover 216 v + padding (UISizeConstraint)
		PanelMaxHeight = 260,
		GapFromTile = 10, -- v between the Army tile's right edge and the popover
		EdgeMargin = 8, -- v kept free between the popover (incl. its corner ✕) and the safe-area edges
		Pad = 6,
		TitleHeight = 28,
		TitleSize = 22, -- "ARMY 5/20" (Display font)
		CellGap = 4,
		CellHeightDesktop = 44,
		ManageHeightDesktop = 40,
		CellTextSize = 18,
		CaptionSize = 16, -- desktop "ORDERS 1-4 · T" hint, hotkey digits
		CloseFace = 30, -- v ✕ disc centred on the popover's top-right corner (hit = MinTouchPx on touch)
		Bg = Color3.fromRGB(22, 24, 28),
		BgTransparency = 0.08,
		Accent = Color3.fromRGB(72, 220, 96), -- the Army rail tile's accent: popover + cell strokes
		CellBg = Color3.fromRGB(32, 36, 42),
		ActiveBg = Color3.fromRGB(40, 132, 60), -- the order the squad follows now
		ManageBg = Color3.fromRGB(16, 58, 28),
		HotkeyToastSeconds = 1.6, -- T with the popover closed → local Info toast "Squad: FOLLOW"
	},
}

return OrdersConfig
