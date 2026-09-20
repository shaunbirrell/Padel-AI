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
	-- v38: brief order state over nearest soldier
	OrderBillboardSeconds = 2.8,
	OrderLabels = {
		Follow = "FOLLOWING",
		Attack = "ATTACKING",
		Hold = "HOLDING",
		Retreat = "RETREATING",
	},

	Walkie = {
		PositionTouch = UDim2.new(0, 12, 1, -268), -- clear of dock / ATM chips
		PositionDesktop = UDim2.new(0, 16, 1, -110),
		Size = UDim2.fromOffset(200, 168),
		SizeTouch = UDim2.fromOffset(268, 236),
		MinTouchPx = 56,
	},
}

return OrdersConfig
