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
	FollowDistance = 10,
	FollowStopDistance = 6,
	FormationSpacing = 3.5,
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
