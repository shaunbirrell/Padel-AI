--!strict
--[[
	HudConfig — v70 "clean screen" HUD (competitor-style left rail, bottom-left cash pill, top-centre text
	toasts, bottom-centre weapon hotbar). Config-first: every HUD element reads its placement, size, colour and
	visibility rule from this file. Nothing in a controller may hard-code a HUD offset again.
	Spec: the v70 "clean screen" design hand-off (spec + mock_*.png). Runtime API: Client/Modules/HudLayout.luau
	(scale, insets, flags, top stack, panel registry, badges, cash float, reserved rects) and HudIcons.luau.

	OWNER DECISIONS (v70): Settings = TopStrip gear (not a rail tile); no Base tile on the rail; you spawn
	HOLSTERED (Hotbar.DrawnOnSpawn = false, auto-draw on damage); Army popover key Y; Robux offer pop-ups at most
	Offer.MaxPerSession per session and Offer.MinGapSeconds apart.

	UNITS
	  v     virtual px. Every HUD ScreenGui gets ONE UIScale named "MobileScale" from HudLayout.ApplyScreen():
	        S = clamp(min(viewport.X, viewport.Y) / Scale.BasePx, Scale.Min, Scale.Max)
	          844x390 phone → 0.70   956x440 phone → 0.70   1280x720 → 0.90   1920x1080 → 1.15
	        and ScreenInsets = CoreUISafeInsets (below the Roblox topbar, inside the landscape notch).
	        So 1 v = S real px everywhere, and offsets from different ScreenGuis finally line up.
	  real  device px. Only the TopStrip (it lives in the Roblox topbar row, whose buttons are a fixed 44 px) and
	        BillboardGui world labels (BillboardGui offsets are never UIScaled) use real px.

	ANCHORS
	  "Left/Right/Top/Bottom" = distance in v from that edge of the safe content rect. The content rect on an
	  844x390 phone is x 47..797, y 58..390 (real); on 1280x720 it is x 0..1280, y 58..720.

	NOTHING IN HERE TOUCHES A PURCHASE PATH. Buy buttons keep btn.Activated → the same remotes.
]]

local HudConfig = {}

-- Toast.Reroute entry (see HudConfig.Toast.Reroute)
export type RerouteRule = {
	Match: string,
	Float: boolean?,
	Show: string?,
	Strip: string?,
	Type: string?,
	MinGapSeconds: number?,
	AlertSeconds: number?,
}

HudConfig.Version = 70

---------------------------------------------------------------------------------------------------------------
-- Scale, fonts, palette, z-order
---------------------------------------------------------------------------------------------------------------

HudConfig.Scale = {
	BasePx = 800,
	Min = 0.70, -- 64 v tile → 44.8 real px on every phone (Apple/Roblox 44 px touch minimum)
	Max = 1.15,
	TouchMinPx = 44, -- real px; HudLayout.AssertTouchTarget() warns in Studio when a tappable is smaller
	-- real px floor for any HUD text (check_hud's rule): at S 0.70 that is 16 v, so no v text size below 16
	MinTextPx = 11,
}

-- Roblox built-in fonts only.
HudConfig.Fonts = {
	Display = Enum.Font.FredokaOne, -- rail labels, cash number, toasts, level, ammo count, console labels
	Body = Enum.Font.GothamBold, -- small captions, prompt text, slot names
	BodyMedium = Enum.Font.GothamMedium,
}

HudConfig.Colors = {
	Ink = Color3.fromRGB(10, 12, 14), -- every outlined text uses this stroke
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(190, 196, 204),
	PillBg = Color3.fromRGB(22, 24, 28), -- cash pill, hotbar slots, prompt pills, top-strip chips
	PillBgTransparency = 0.2,
	PillStroke = Color3.fromRGB(0, 0, 0),
	PillStrokeTransparency = 0.45,
	Positive = Color3.fromRGB(110, 255, 90), -- success toast, cash gain float, affordable price
	Negative = Color3.fromRGB(255, 72, 72), -- error toast, spend float, unaffordable price
	Warn = Color3.fromRGB(255, 120, 104), -- "need more cash" red-pink (competitor "You need more Money!")
	Gold = Color3.fromRGB(255, 214, 72), -- reward / level-up toast, offer stroke
	Info = Color3.fromRGB(255, 255, 255),
	XP = Color3.fromRGB(90, 170, 255),
	PlusGreen = Color3.fromRGB(46, 204, 64),
	PlusGreenStroke = Color3.fromRGB(12, 70, 22),
	Badge = Color3.fromRGB(235, 40, 52),
	Locked = Color3.fromRGB(170, 176, 184),
}

-- One z-order for the whole client. Names are the existing ScreenGui names (BuyPathVerify looks them up).
HudConfig.DisplayOrder = {
	WE_Reticle = 24, -- NEW gui: crosshair at the true viewport centre (IgnoreGuiInset = true)
	WarEmpireCompass = 20, -- kept only as a shell; the compass chip moves to WE_TopStrip
	WarEmpireCombatHUD = 25, -- hotbar, health bar, ammo, touch FIRE/R
	WarEmpireTerritory = 28, -- capture bar (top-centre stack)
	WarEmpireBankRaid = 32, -- bank + ATM raid hold bars (top-centre stack)
	WarEmpireTutorial = 50, -- objective chip (top-centre stack)
	WarEmpireOrders = 52, -- Army popover (orders)
	WarEmpireHUD = 55, -- rail + cash pill (BuyPathStatic pins "DisplayOrder = 55")
	WE_TopStrip = 56, -- NEW gui: level chip, settings gear, shield chip, compass (Roblox topbar row)
	WarEmpireVehicleHUD = 56, -- VehicleDriveClient (v70): SPD pill + hint + ▲▼ column (inside Reserve.CombatTouch)
	WE_PromptLane = 57, -- NEW gui: custom ProximityPrompt pills (action lane)
	WarEmpireBaseUI = 58,
	Panels = 60, -- Shop / Army / Missions / Settings / Garage / Progression / Research / Missiles
	WE_PadBuyGui = 65, -- console BUY button (action lane); hidden while any panel is open
	WE_MissileAlert = 66, -- INCOMING MISSILE (top-centre stack, slot "Alert")
	WarEmpireNotifications = 70, -- toast lane + offer toast
}

HudConfig.Edge = 12 -- v; default gap from the safe content rect's edges

---------------------------------------------------------------------------------------------------------------
-- TOP STRIP — the Roblox topbar row (ScreenGui "WE_TopStrip", ScreenInsets = TopbarSafeInsets, NO UIScale).
-- Left group sits right after Roblox's buttons (GuiService.TopbarInset.Min.X); compass is right-aligned.
---------------------------------------------------------------------------------------------------------------

HudConfig.TopStrip = {
	Height = 44, -- real px — same as Roblox's topbar buttons
	YNudge = 0, -- real px; if a device shows our chips off-centre against Roblox's pills, nudge here
	Gap = 8, -- real px between chips
	EdgePad = 12, -- real px after Roblox's buttons / before the right edge
	-- Roblox's own 44 px topbar buttons sit at y 12..56 of the 58 px row (owner screenshot), i.e. 2 px above the
	-- row's bottom: our chips are bottom-aligned the same way (AnchorPoint Y 1, offset -BottomPad + YNudge).
	BottomPad = 2,
	-- Clients without GuiService.TopbarInset / ScreenInsets.TopbarSafeInsets (risk #1): the free part of the
	-- topbar row is assumed to start this many real px right of the safe-left edge (Roblox logo + unibar pill),
	-- i.e. x 255 on an 844x390 phone, 270 on the owner's 956x440, 208 on desktop. HudLayout.TopbarRect().
	FallbackLeft = 208,
	Corner = 22, -- pill
	TextStroke = 1.2, -- real px Colors.Ink outline on the chips' Display-font numbers
	Bg = Color3.fromRGB(18, 20, 24),
	BgTransparency = 0.25, -- visually matches Roblox's own topbar pills
	LeftItems = { "Level", "Settings", "Shield" }, -- order; Shield only while shielded
	Level = {
		MinWidth = 118,
		CaptionSize = 12, -- "LV"
		NumberSize = 22, -- "7"
		BarSize = Vector2.new(56, 6),
		BarBg = Color3.fromRGB(255, 255, 255),
		BarBgTransparency = 0.8,
		PulseColor = Color3.fromRGB(255, 214, 72), -- level-up: stroke flash + UIScale 1 → 1.15 → 1 (0.45 s)
		PulseSeconds = 1.2,
		TapShowsGoalSeconds = 3.5, -- tap/hover: GoalLabel tooltip under the chip (goal + rebirth summary)
		TipGap = 6, -- real px between the topbar row and the tooltip card
		TipMaxWidth = 340,
		TipGoalSize = 13, -- GothamBold, white
		TipRebirthSize = 12, -- GothamMedium, gold
		PopScale = 1.15, -- level-up chip pop (UIScale 1 → 1.15 → 1 over PopSeconds)
		PopSeconds = 0.45,
	},
	Settings = { Size = 44, IconColor = Color3.fromRGB(52, 156, 255) }, -- gear; opens SettingsController
	Shield = { -- raids: victim shield after being robbed (player attribute WE_ShieldUntil, os.time())
		Attribute = "WE_ShieldUntil",
		IconColor = Color3.fromRGB(80, 210, 255),
		IconSize = 24,
		TextSize = 18, -- "9:12"
	},
	Compass = {
		MinWidth = 112,
		ArrowSize = 22, -- chevron built from 2 Frames, Rotation = bearing relative to the camera
		ArrowBox = 24, -- faint round backing behind the arrow
		ArrowColor = Color3.fromRGB(255, 214, 72),
		LabelSize = 13, -- "BASE"
		DistanceSize = 18, -- "95m" (Display font)
		TickSeconds = 0.25,
		HideInsideOwnPlot = true, -- inside your own walls you need no arrow home
		OwnPlotMarginStuds = 12,
		RadarDot = Color3.fromRGB(190, 110, 255), -- 8 px pulsing dot at the chip's left while RadarReveal is on
		TapOpensTerritories = true, -- tap → TerritoryController dropdown under the chip (the old list)
	},
}

---------------------------------------------------------------------------------------------------------------
-- LEFT RAIL — 5 square tiles, vertically centred between the top of the content rect and the cash pill.
-- Settings is NOT a rail tile: 5 tiles at 64 v fit an 844x390 phone (332 px of content); 6 need 353 px.
-- If a screen is too short even for 5 (e.g. 800x360), the grid wraps to a 2nd column (FillDirectionMaxCells).
---------------------------------------------------------------------------------------------------------------

HudConfig.Rail = {
	Tile = 64, -- v, touch   (44.8 real on phones)
	TileDesktop = 76, -- v   (68 real at 720p, 87 at 1080p)
	Gap = 5,
	GapDesktop = 8, -- dock≤8 (BuyPathStatic pins the phrase in HUDController)
	ColumnGap = 10, -- v added to Gap between columns when a short screen wraps the rail (e.g. 800x360 → 4 + 1)
	LabelOverhang = 6, -- v the label hangs below the tile edge (included in the hit area)
	LabelOverhangDesktop = 8,
	LabelSize = 17,
	LabelSizeDesktop = 20,
	LabelStroke = 2, -- real px, Colors.Ink
	Corner = 12,
	StrokePx = 3,
	IconScale = 0.6, -- icon box = 60 % of the tile, centred in the top 78 %
	Left = 12, -- v from the safe left edge
	CenterY = 0.55, -- centre of the rail within its band (competitor sits a little below mid-screen)
	TopReserve = 12, -- v band top
	PressScale = 0.92,
	KeyHintDelay = 0.6, -- desktop: hovering a tile shows "Shop [P]" after this many seconds (keys: HudConfig.Keys)
	KeyHintSize = 16,
	NearPrestigePulse = 1.12, -- ShowNearPrestigeBanner: the Rebirth tile pulses once per level in the near band
	Tiles = {
		-- Name = the MobileActionBar child name (kept: "DockMissions" etc. are pinned by BuyPathStatic)
		{ Id = "Shop", Name = "DockShop", Label = "Shop", Icon = "Cart", Accent = Color3.fromRGB(255, 64, 88), Fill = Color3.fromRGB(70, 16, 26), Key = Enum.KeyCode.P },
		{ Id = "Rebirth", Name = "DockRebirth", Label = "Rebirth", Icon = "Cycle", Accent = Color3.fromRGB(196, 80, 255), Fill = Color3.fromRGB(50, 18, 74), Key = Enum.KeyCode.K },
		{ Id = "Army", Name = "DockArmy", Label = "Army", Icon = "Helmet", Accent = Color3.fromRGB(72, 220, 96), Fill = Color3.fromRGB(16, 58, 28), Key = Enum.KeyCode.Y },
		{ Id = "Garage", Name = "DockGarage", Label = "Garage", Icon = "Car", Accent = Color3.fromRGB(40, 212, 200), Fill = Color3.fromRGB(8, 52, 56), Key = Enum.KeyCode.G },
		{ Id = "Missions", Name = "DockMissions", Label = "Missions", Icon = "Clipboard", Accent = Color3.fromRGB(255, 150, 32), Fill = Color3.fromRGB(80, 42, 6), Key = Enum.KeyCode.M },
	},
	Badge = {
		Size = 24, -- v circle at the tile's top-right corner (AnchorPoint 0.5,0.5 at (1,-4,0,4))
		TextSize = 16, -- 11.2 real px on phones (Scale.MinTextPx)
		Bg = Color3.fromRGB(235, 40, 52),
		ReadyBg = Color3.fromRGB(255, 214, 72), -- "!" on Rebirth uses gold with dark text
		ReadyText = Color3.fromRGB(30, 22, 4),
		PulseWhenNew = true, -- UIScale 1 → 1.2 → 1 once when a badge appears
	},
	-- What drives each badge (HUDController.SetRailBadge). nil = no badge.
	BadgeSources = {
		Shop = "OfferPending", -- "!" while an offer toast was deferred/dismissed unseen (clears on Shop open)
		Rebirth = "PrestigeReady", -- "!" at level >= PrestigeConfig.MinLevelToPrestige
		Army = nil, -- the count lives in the Army popover header, not on the HUD
		Garage = "NewVehicle", -- "!" when a vehicle was bought/unlocked and not spawned yet (clears on Garage open)
		Missions = "Claimables", -- count = completed-unclaimed missions + claimable daily login + (spinner READY ? 1 : 0)
	},
	HideWhen = { "Driving", "Dead" },
}

---------------------------------------------------------------------------------------------------------------
-- CASH PILL — the only always-on number. Bottom-left, under the rail.
---------------------------------------------------------------------------------------------------------------

HudConfig.CashPill = {
	Left = 12,
	Bottom = 12,
	Height = 56, -- v touch (39 real); the + hit area is taller (PlusHit)
	HeightDesktop = 52,
	MinWidth = 200,
	MaxWidth = 380,
	Corner = 14,
	StrokePx = 2,
	PadLeft = 10,
	PadRight = 6,
	Gap = 8,
	IconSize = Vector2.new(42, 32), -- HudIcons "Cash": 3 stacked green bills
	NumberSize = 34,
	NumberSizeDesktop = 32,
	NumberColor = Color3.fromRGB(255, 255, 255),
	ShowDollarSign = false, -- the icon says "cash"; prices elsewhere keep "$"
	AbbreviateAbove = 1e9, -- 1,234,567,890 → "1.23B"
	CountUpSeconds = 0.35,
	PopScale = 1.08, -- the number pops once per change
	FlashSeconds = 0.5, -- gain/spend colour (CashFloat.GainColor / SpendColor) settles back to NumberColor
	NumberPadRight = 4,
	PlusStrokePx = 2.5,
	PlusVisual = 44, -- v green circle
	PlusHit = 64, -- v transparent hit area (≥ 44 real on phones)
	PlusOpens = "ShopCashPacks", -- ShopController.OpenCashPacks() — no toast
	HideWhen = { "Dead" },
}

-- "+$141" that rises from the pill and fades. Replaces every "Collected $N" centre toast.
HudConfig.CashFloat = {
	TextSize = 26,
	StrokePx = 1.6,
	Rise = 40, -- v
	Seconds = 0.9,
	MergeWindow = 0.6, -- gains within this window add into the same float ("+$141" → "+$810")
	GainColor = Color3.fromRGB(120, 255, 120),
	SpendColor = Color3.fromRGB(255, 96, 96),
	ShowSpend = true, -- "-$5,000" on purchases
	-- spend floats come from cash DROPS seen while a panel is open or within this many seconds of the console
	-- BUY button being on screen (other drops — e.g. a raid — get their float from the notification that explains them)
	SpendContextSeconds = 3,
	-- Floats come ONLY from Notification type "Collect" (server manual collects, kill/raid money): passive and
	-- AutoCollect income just counts the number up silently. That is the owner's "don't notify every 2 s" rule.
	Source = "CollectNotifications",
	MaxPerSecond = 2,
}

---------------------------------------------------------------------------------------------------------------
-- TOP-CENTRE STACK — one column under the topbar. Items stack in this order, each collapses when hidden:
--   Alert (INCOMING MISSILE, base under attack) → Progress (capture / bank / ATM raid hold) →
--   Objective (tutorial step) → Toasts (2 lines max) → Offer (one purchasable offer toast)
-- HudLayout.RegisterTopStack(name, guiObject, order) positions them; no gui hard-codes a Y again.
---------------------------------------------------------------------------------------------------------------

HudConfig.TopStack = {
	Top = 8, -- v below the content top (= below the topbar)
	Gap = 6,
	MaxWidthScale = 0.62, -- of content width; nothing in the stack is wider
	Order = { Alert = 10, Progress = 20, Objective = 30, Toasts = 40, Offer = 50 },
	Progress = { Size = Vector2.new(320, 44), BarH = 8, TextSize = 16, ContestedColor = Color3.fromRGB(255, 176, 48) },
	Objective = { MaxWidth = 460, Height = 64, TitleSize = 20, HintSize = 16, GoHit = 64, SkipHit = 44 },
}

HudConfig.Toast = {
	MaxVisible = 2, -- newest at the bottom; a 3rd removes the oldest
	TextSize = 26, -- v touch (18 real)
	TextSizeDesktop = 30, -- v (27 real at 720p, 34 at 1080p)
	StrokePx = 2.5,
	LineGap = 2,
	FadeIn = 0.12,
	FadeOut = 0.25,
	PopFrom = 0.7, -- UIScale pop on appear (Back ease, 0.14 s)
	CoalesceWindow = 3, -- same key again within 3 s → one line "Text ×2", timer restarts
	CoalesceKey = "StripDigits", -- "Not enough cash — need $500"/"… $700" coalesce
	SoundMinGap = 0.4,
	Types = {
		Success = { Color = Color3.fromRGB(110, 255, 90), Hold = 1.8, Sound = true },
		Error = { Color = Color3.fromRGB(255, 72, 72), Hold = 2.4, Sound = true },
		Warn = { Color = Color3.fromRGB(255, 120, 104), Hold = 2.2, Sound = true },
		Reward = { Color = Color3.fromRGB(255, 214, 72), Hold = 2.4, Sound = true },
		Info = { Color = Color3.fromRGB(255, 255, 255), Hold = 2.0, Sound = false },
		Collect = { Route = "CashFloat" }, -- never a lane line; amount = payload.Amount or first "$n" in Message
	},
	-- TODAY'S server lines, re-routed on the client (the §4.2 server fixes are deferred; they will send type
	-- "Collect" + Amount / one "BASE UNDER ATTACK" themselves later — these rules then simply stop matching).
	-- Checked in order BEFORE Drop; first match wins. Fields:
	--   Match   Lua pattern on Message
	--   Float   true → "+$N" cash float from the first "$n" in Message (commas allowed); no lane line unless Show
	--   Show    replacement lane text ("" or nil with Float = float only); "%STRIP%" = Message minus Strip
	--   Strip   pattern removed from Message when Show == "%STRIP%"
	--   Type    lane type for Show (default: the payload's own Type)
	--   MinGapSeconds  show at most once per this many seconds (per rule)
	--   AlertSeconds   also light the TopStack "Alert" slot for this long (NotificationController owns it)
	Reroute = ({
		{ Match = "^Collected %$", Float = true }, -- MoneyCollectorService manual/spatial collect (type Collect)
		{ Match = " down %(%+%$[%d,]+%)$", Float = true }, -- NPC kill "<NPC> down (+$N)" (Reward today)
		{ Match = "^Eliminated .+ %(%+%$[%d,]+%)$", Float = true, Show = "%STRIP%", Strip = " %(%+%$[%d,]+%)$", Type = "Success" }, -- PvP kill: "Eliminated X" + float
		{ Match = "^DEF HIT", Show = "BASE UNDER ATTACK!", Type = "Warn", MinGapSeconds = 60, AlertSeconds = 4 }, -- every 1.2 s today
	} :: { RerouteRule }),
	-- Client safety net for server/client noise that has no business on screen. Lua patterns on Message.
	-- (The real fix is at the source — see spec §World/Server noise — this only stops regressions.)
	Drop = {
		" opened$", -- UIController dockPress (removed)
		"^Squad: ", -- order echo; the Army popover shows the active order
		"^Capture stipend", -- recurring every 90 s; the cash counts up silently
		"^DEF HIT", -- every 1.2 s during a gate fight; Reroute turns it into one "BASE UNDER ATTACK!" per 60 s
		"^Buying .+…$", -- the BUY button already reads BUYING…
		"^Capturing .+%.%.%.$", -- TerritoryService per-trigger echo; the capture bar shows it
		"Walk to glowing pads", -- stale v67 first-join hints
		"Prices float above pads",
		"Only one weapon owned", -- the hotbar shows what you own
		-- upsell companions: the offer toast (ShowOffer) carries the offer; the extra Info line goes
		"^Tired of walking to the ATM%?",
		"^Big collect! Double your cash",
		"Starter Bundle available",
		"^Commander status unlocked",
		"Speed Boost available$",
		"BEST OFFER — Cash Mega pack ready",
		"^Boost%? .+ tap toast$",
	},
	-- One failed purchase = one line (today it is 3: WE_BuyAck + PurchaseResult + server Warn)
	DedupePurchaseFailure = true,
}

HudConfig.Offer = { -- Robux soft offers (7 ShopController cards) become ONE offer toast in the stack
	Height = 56, -- v touch
	HeightDesktop = 48,
	MaxWidth = 460,
	Stroke = Color3.fromRGB(255, 214, 72),
	Bg = Color3.fromRGB(26, 22, 8),
	BgTransparency = 0.12,
	TitleSize = 20,
	SubSize = 16,
	GetHit = 64, -- green GET button
	CloseHit = 44,
	HoldSeconds = 9,
	-- Owner decision (money plan D8): at most 3 offer pop-ups per session, at least 4 minutes apart.
	-- The server Offer Director (money workflow) may be stricter; this client throttle is the floor.
	MaxPerSession = 3, -- shown offers (dropped/deferred-then-dropped ones do not count)
	MinGapSeconds = 240, -- at most one offer every 4 minutes
	FirstAfterJoinSeconds = 90,
	DeathOfferMinGapSeconds = 600, -- the PvP death offer: at most once per 10 minutes (still counts toward MaxPerSession)
	DeferWhen = { "Drawn", "RecentCombat", "Driving", "Modal", "Tutorial" }, -- queued, dropped after 60 s
	DropAfterQueuedSeconds = 60,
	ShopBadgeWhenDropped = true,
}

---------------------------------------------------------------------------------------------------------------
-- BOTTOM-CENTRE COLUMN — hotbar at the bottom, slim health bar above it, action lane (prompts / BUY) above that
---------------------------------------------------------------------------------------------------------------

HudConfig.Hotbar = {
	MaxSlots = 4,
	Slot = 64, -- v touch (44.8 real)
	SlotDesktop = 50, -- v (45 real at 720p)
	Gap = 6,
	Bottom = 12,
	Corner = 8,
	Bg = Color3.fromRGB(20, 22, 26),
	BgTransparency = 0.45,
	Stroke = Color3.fromRGB(255, 255, 255),
	StrokeTransparency = 0.75,
	SelectedBgTransparency = 0.12,
	SelectedStrokePx = 2,
	SelectedScale = 1.08,
	NumberSize = 16, -- slot number, top-left (11.2 real px on phones)
	NameSize = 16, -- v touch, TextScaled max; WeaponConfig.ShortName (RIFLE / AR / SMG / PISTOL / SHOTGUN / SNIPER / RPG / FRAG)
	NameSizeDesktop = 13, -- 11.7 real px at 720p
	TapSelectedHolsters = true, -- tap / press the drawn weapon's slot again → holster
	DrawnOnSpawn = false, -- you spawn holstered: clicks go to the world (droppers, consoles), not the gun
	AutoDrawOnDamage = true, -- taking damage from a player/NPC draws the last weapon
	HideWhen = { "Driving", "Dead", "Modal" },
}

HudConfig.Health = {
	Height = 8, -- v
	MinWidth = 200, -- v; otherwise the hotbar's width
	GapAboveHotbar = 6,
	Fill = Color3.fromRGB(80, 220, 110),
	Mid = Color3.fromRGB(240, 170, 60), -- ≤ 50 %
	Low = Color3.fromRGB(235, 60, 60), -- ≤ 25 %
	Bg = Color3.fromRGB(0, 0, 0),
	BgTransparency = 0.45,
	ShowWhen = { "Hurt", "RecentCombat" }, -- HP < max, or hit/firing within RecentCombatSeconds
	RecentCombatSeconds = 6,
	HideAfterFullSeconds = 3,
	HideWhen = { "Driving", "Dead", "Modal" },
	LowHpVignette = 0.25, -- below 25 % a soft red screen-edge vignette replaces the full-screen red strobe
}

HudConfig.ActionLane = {
	-- bottom edge = Hotbar.Bottom + slot + Health.GapAboveHotbar + Health.Height + Gap
	Gap = 10,
	PromptHeight = 64, -- v touch (44.8 real) — the pill is the tap target
	PromptHeightDesktop = 50,
	PromptMinWidth = 150,
	PromptGap = 8, -- two prompts (E + F) side by side
	PromptTextSize = 18,
	KeyCapSize = 34, -- desktop/gamepad key cap ("E", "F", ButtonX glyph)
	HoldFill = Color3.fromRGB(110, 255, 90),
	-- BuyButton (WorldPromptController, gui WE_PadBuyGui): same lane. Desktop keeps the pinned 300x58.
	BuyButtonSize = UDim2.fromOffset(300, 58),
	BuyButtonSizeTouch = UDim2.fromOffset(300, 64),
	SuppressPromptWhenBuyButton = true, -- the console's own "Build / Upgrade" pill is hidden while BUY shows
	OwnerOnlyPromptNames = { "WE_ServerBuyPrompt", "WE_PanelPrompt", "WE_DrivePrompt" }, -- disabled locally on other plots/vehicles
	RemovePrompts = { "Open Base", "Hold to capture" }, -- ActionText of client prompts that go away
	HideWhen = { "Modal", "Dead" },
}

---------------------------------------------------------------------------------------------------------------
-- COMBAT (CombatController) — only while a weapon is DRAWN
---------------------------------------------------------------------------------------------------------------

HudConfig.Ammo = {
	-- Desktop: bottom-right corner. Touch: above the FIRE button, right-aligned.
	Anchor = Vector2.new(1, 1),
	Right = 16,
	Bottom = 14,
	Size = Vector2.new(240, 80),
	RightTouch = 12,
	BottomTouch = 243, -- FIRE top (143 + 88) + 12
	SizeTouch = Vector2.new(200, 56),
	CountSize = 44, -- "27" Display font
	CountSizeTouch = 30,
	MagSize = 24, -- "/30"
	MagSizeTouch = 18,
	NameSize = 16, -- weapon name above the count (11.2 real px on phones)
	BarSize = Vector2.new(200, 4), -- magazine / reload fraction
	CountColor = Color3.fromRGB(255, 255, 255),
	MagColor = Color3.fromRGB(200, 204, 210),
	LowFraction = 0.25,
	LowColor = Color3.fromRGB(255, 170, 60),
	EmptyColor = Color3.fromRGB(255, 72, 72),
	ReloadColor = Color3.fromRGB(255, 214, 72),
	ShowWhen = { "Drawn" },
	HideWhen = { "Driving", "Modal", "Dead" },
}

HudConfig.TouchCombat = { -- positions are from the content rect's bottom-right; Roblox's jump button is at
	-- x = W − safeRight − 95 .. +70, y = H − 90 .. +70 (real) and is never covered
	Fire = { Size = 88, Anchor = Vector2.new(0.5, 1), Right = 86, Bottom = 143 }, -- centred over the jump button
	Reload = { Size = 64, Anchor = Vector2.new(1, 1), Right = 142, Bottom = 143 }, -- left of FIRE
	FireColor = Color3.fromRGB(220, 50, 50),
	ReloadColor = Color3.fromRGB(34, 38, 44),
	HoldToFireHz = 20, -- existing loop; the server still clamps to the weapon FireRate
	ShowWhen = { "Drawn" },
	HideWhen = { "Driving", "Modal", "Dead" },
}

HudConfig.Reticle = {
	Size = 20, -- v
	Gap = 5,
	Arm = 7,
	Thickness = 2,
	Color = Color3.fromRGB(245, 248, 240),
	DotColor = Color3.fromRGB(255, 214, 72),
	CenterOnViewport = true, -- own ScreenGui with IgnoreGuiInset = true → the aimRay centre, not 22 px below it
	ShowWhen = { "Drawn" },
	HideWhen = { "Driving", "Modal", "Reloading", "Dead" },
}

HudConfig.HitFeedback = {
	HitMarkerSeconds = 0.12, -- the X at the reticle is the only feedback for hits you land
	DamageEdgeSeconds = 0.18, -- red screen-edge flash when YOU are hit (no full-screen tint)
	DamageEdgeMinGap = 0.3,
	DamageEdgeTransparency = 0.55,
	FullScreenTint = false, -- the 0.08 s full-screen strobe goes
}

---------------------------------------------------------------------------------------------------------------
-- RESERVED REGIONS — nothing but the owners listed may draw here (HudLayout.Reserve(name) returns the rect)
---------------------------------------------------------------------------------------------------------------

HudConfig.Reserve = {
	-- Bottom-right vehicle/combat controls. Owners: CombatController (FIRE / R / ammo), VehicleDriveClient
	-- (▲▼ lift/pitch, throttle, exit), Roblox jump. Measured from the content rect's bottom-right, in v;
	-- MinWidthPx/MinHeightPx (real px) are floors so the rect always holds VehicleDriveClient's ▲▼ column:
	-- Laws.ControlsLayout puts it right above the jump button, top edge at H − (90 + 10 + 52 + 8 + 52) = H − 212
	-- on phones (H − 222 without a jump button, H − 218 on tablets); its hard cap is RESERVED_FROM_BOTTOM = 250.
	-- FIRE / RELOAD share that space, which is why combat is hidden while Driving.
	CombatTouch = { Width = 290, Height = 300, MinWidthPx = 0, MinHeightPx = 222 }, -- 844x390: x ≥ 594, y ≥ 168 real
	CombatDesktop = { Width = 340, Height = 150, MinWidthPx = 0, MinHeightPx = 0 }, -- 1280x720: x ≥ 974, y ≥ 585 real
	-- Suggested touch slots (VehicleDriveClient v70 computes its own column above the jump button instead;
	-- these stay as the documented fallback; combat is hidden while seated):
	VehicleTouch = {
		Up = { Size = 64, Anchor = Vector2.new(1, 1), Right = 142, Bottom = 143 }, -- the RELOAD slot
		Down = { Size = 64, Anchor = Vector2.new(1, 1), Right = 142, Bottom = 36 }, -- left of jump, same row
	},
}

---------------------------------------------------------------------------------------------------------------
-- CONTEXT FLAGS + VISIBILITY — HudLayout publishes these; every element's HideWhen/ShowWhen reads them
---------------------------------------------------------------------------------------------------------------

HudConfig.Context = {
	-- Flag       Set by
	-- Modal      any registered panel open (HudLayout.PanelOpened / PanelClosed) — also enforces ONE open panel
	-- Driving    Humanoid.SeatPart is a VehicleSeat (HudLayout watches the humanoid) + VehicleDriveClient
	-- Drawn      CombatController holster state
	-- Reloading  CombatStateUpdate.Reloading
	-- Hurt       health < max
	-- RecentCombat  hit taken/landed or fired within Health.RecentCombatSeconds
	-- Tutorial   TutorialController step active
	-- InOwnPlot  CompassController plot test (inside own walls + margin)
	-- Dead       Humanoid dead (HudLayout: Died → true, CharacterAdded → false) / CombatState.Alive == false
	-- OrdersOpen OrdersController (Army popover open → 1-4 / T are order hotkeys)
	-- Radar      TerritoryController (RadarReveal active → purple dot on the compass chip)
	Flags = { "Modal", "Driving", "Drawn", "Reloading", "Hurt", "RecentCombat", "Tutorial", "InOwnPlot", "Dead", "OrdersOpen", "Radar" },
	ModalExclusive = true, -- opening a panel closes the others
	ModalDim = 0.45, -- BackgroundTransparency of the black dim behind the open panel (UIUtil.MakeModalDim; Active = false; tap outside closes)
}

---------------------------------------------------------------------------------------------------------------
-- INPUT — one table; SettingsController's keybind sheet is generated from it
---------------------------------------------------------------------------------------------------------------

HudConfig.Keys = {
	Shop = Enum.KeyCode.P,
	Rebirth = Enum.KeyCode.K,
	Army = Enum.KeyCode.Y, -- was A (strafe-left toggled the Army panel while walking)
	Garage = Enum.KeyCode.G,
	Missions = Enum.KeyCode.M,
	Settings = nil, -- was O (Roblox camera zoom-out). Gear button only.
	Base = Enum.KeyCode.B, -- Base menu leaves the HUD; B and the Command Center map table remain
	Weapons = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }, -- draw / holster
	WeaponPrev = Enum.KeyCode.Q, -- ignored while seated; E no longer cycles (it is the prompt key)
	WeaponWheel = true, -- mouse wheel cycles only while drawn (camera zoom otherwise)
	Reload = Enum.KeyCode.R,
	OrdersCycle = Enum.KeyCode.T,
	-- 1-4 issue squad orders ONLY while the Army popover is open (HudLayout.GetFlag("OrdersOpen"))
	Gamepad = {
		Fire = Enum.KeyCode.ButtonR2,
		Reload = Enum.KeyCode.ButtonY, -- ButtonX stays the ProximityPrompt button
		Next = Enum.KeyCode.ButtonR1,
		Prev = Enum.KeyCode.ButtonL1,
		DrawHolster = Enum.KeyCode.DPadUp,
	},
	CombatInputBlockedWhen = { "Driving", "Modal", "Dead" }, -- no firing from a seat, through a panel, or dead
	FireNeedsDrawn = true, -- LMB on a ClickDetector (tutorial dropper) never fires the gun while holstered
}

---------------------------------------------------------------------------------------------------------------
-- WORLD LABELS — client console tags (WorldPromptController) + the shared stud-scaled helper (WorldLabel)
---------------------------------------------------------------------------------------------------------------

HudConfig.WorldLabels = {
	Console = {
		Size = UDim2.fromOffset(118, 40), -- real px (pinned PRICE_BILLBOARD_SIZE); plain text, NO card
		StudsAboveConsoleTop = 2.2, -- stays under the 12-stud ceiling inside walk-in buildings
		MaxDistanceBuild = 30, -- L0 "HELIPAD / BUILD $5,000"
		MaxDistanceUpgrade = 18, -- L1-4 "HELIPAD / LV 2 → 3 · $12K"
		NameSize = 16,
		PriceSize = 15,
		NameColor = Color3.fromRGB(255, 255, 255),
		PriceAffordable = Color3.fromRGB(110, 255, 90),
		PriceShort = Color3.fromRGB(255, 96, 96),
		LockedColor = Color3.fromRGB(170, 176, 184), -- "Needs Command Center 2"
		StrokeTransparency = 0, -- Colors.Ink
		ShowOnMax = false, -- MAX lives on the console screen SurfaceGui, not in the air
		ShowIncome = false, -- income is on the console screen and in the Base panel
		OwnerOnly = true,
		AlwaysOnTop = false,
	},
	-- Shared helper Shared/Util/WorldLabel.luau: stud-scaled plain text (Size = UDim2.fromScale(w, h)),
	-- AlwaysOnTop = false, optional OwnerUserId (client hides it for everyone else).
	Default = { StudsW = 6, StudsH = 1.6, MaxDistance = 40, Font = Enum.Font.FredokaOne },
	Transient = { MaxDistance = 28 }, -- "+$10" pops: owner client only
}

return HudConfig
