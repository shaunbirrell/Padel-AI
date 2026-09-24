--!strict
--[[
	v70 "clean screen" combat HUD + input (spec §3.6). The client sends fire / reload / equip REQUESTS only:
	damage, ammo, magazine size (research), reload time (research) and ownership are the server's
	(CombatService pushes CombatStateUpdate / CombatHitFeedback). Numbers live in HudConfig
	(Hotbar, Health, Ammo, TouchCombat, Reticle, HitFeedback, Keys); layout helpers in Modules/HudLayout.

	HOLSTER STATE
	  You spawn HOLSTERED (HudConfig.Hotbar.DrawnOnSpawn). Tap a hotbar slot / press 1-4 to draw that weapon
	  (RequestEquipWeapon when it is not the equipped one); tap / press the drawn slot again to holster.
	  Taking damage (CombatHitFeedback "Damaged", or the humanoid's health dropping) auto-draws the last weapon
	  (Hotbar.AutoDrawOnDamage). Published HudLayout flags: Drawn, Reloading, Hurt, RecentCombat.

	WHAT SHOWS WHEN (HudLayout.BindVisibility with the HudConfig rules)
	  Hotbar (bottom-centre)          always — hidden while Driving / Dead / Modal / seated
	  Health bar (above the hotbar)   Hurt (HP < max, fades 3 s after full) or RecentCombat (6 s)
	  Ammo readout, touch FIRE / R    Drawn — hidden while Driving / Modal / Dead / seated
	  WE_Reticle                      Drawn and not Reloading. Its own ScreenGui (IgnoreGuiInset, no safe-area
	                                  insets), so it sits on the TRUE viewport centre = the aimRay point.
	  DamageEdge (in WE_Reticle)      red screen-edge flash when you are hit (no full-screen strobe); a softer
	                                  steady edge at <= Health.LowHpVignette of max HP.

	BOTTOM-RIGHT RESERVE / VEHICLES
	  FIRE, RELOAD and the touch ammo readout live inside HudLayout.Reserve("CombatTouch"). VehicleDriveClient's
	  ▲▼ column shares that space (centred over the jump button, top edge H − 212 px on phones — it no longer sits
	  below a FIRE button at H − 250), so every combat control is HIDDEN while seated: the Driving flag
	  (Humanoid.SeatPart is a VehicleSeat), any SeatPart, or the player attribute WE_DriveMode that
	  VehicleDriveClient sets while it drives. The two sets of controls are never on screen together.

	INPUT (HudConfig.Keys) — ignored while Driving / Modal / Dead / seated / the Roblox menu is open
	  LMB, touch FIRE, gamepad R2   fire ONLY while drawn (Keys.FireNeedsDrawn: a click on a ClickDetector —
	                                the tutorial dropper — never shoots while holstered). Hold = 20 Hz; the
	                                server clamps to the (research-boosted) FireRate, so the client never does.
	  1-4                           draw / holster that hotbar slot — squad orders instead while the Army popover
	                                is open (flag OrdersOpen; OrdersController handles those keys)
	  Q, gamepad L1 / R1            previous / next owned weapon (draws it)
	  mouse wheel                   cycles weapons while drawn (Roblox camera zoom while holstered)
	  R, gamepad Y, touch R         reload
	  gamepad DPadUp                draw / holster
	  E                             ProximityPrompts only — it no longer cycles weapons
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local Types = require(Shared.Types)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local ResearchConfig = require(Shared.Configs.ResearchConfig)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local HudIcons = require(script.Parent.Parent.Modules.HudIcons)

local CombatController = {}

local player = Players.LocalPlayer

local HB = HudConfig.Hotbar
local HP = HudConfig.Health
local AM = HudConfig.Ammo
local TC = HudConfig.TouchCombat
local RT = HudConfig.Reticle
local HF = HudConfig.HitFeedback
local KEYS = HudConfig.Keys
local GP = HudConfig.Keys.Gamepad
local COLORS = HudConfig.Colors
local FONT_DISPLAY = HudConfig.Fonts.Display
local FONT_BODY = HudConfig.Fonts.Body
local WHITE = Color3.fromRGB(255, 255, 255)

-- Optional HudConfig.HitFeedback fields (read with defaults so HudConfig can take them over later)
local HF_ANY: any = HF
local EDGE_V: number = tonumber(HF_ANY.DamageEdgeWidth) or 40 -- v, thickness of each red screen-edge strip
local EDGE_LOW_HP_TRANSPARENCY: number = tonumber(HF_ANY.LowHpEdgeTransparency) or 0.74 -- steady <= 25 % HP edge

-- Roblox's engine touch jump button (TouchJump): 70 px at (1, -95, 1, -90) of the safe area when
-- min(viewport) <= 500, otherwise 120 px at (1, -170, 1, -210). HudConfig.TouchCombat / Ammo.BottomTouch are the
-- small-button (phone) layout — every phone lands on S = 0.70, where 86 / 143 v = 60 / 100 px: FIRE centred
-- over the jump button, 10 px above it. Large-button tablets derive the same placement from the big button.
local SMALL_JUMP_MAX_AXIS = 500
local LARGE_JUMP_CENTRE_FROM_RIGHT = 110 -- px: 170 − 120 / 2
local LARGE_JUMP_TOP_FROM_BOTTOM = 210 -- px
local FIRE_ABOVE_JUMP = 10 -- px

local EQUIP_PENDING_SECONDS = 0.8
local WHEEL_MIN_GAP = 0.12
local AUTO_RELOAD_MIN_GAP = 1
local ACTION_WHEEL = "WE_WeaponWheel"
local GAMEPAD_TYPES: { [Enum.UserInputType]: boolean } = {}
for i = 1, 8 do
	local ok, item = pcall(function(): any
		return (Enum.UserInputType :: any)["Gamepad" .. i]
	end)
	if ok and item ~= nil then
		GAMEPAD_TYPES[item] = true
	end
end

type Slot = {
	Cell: Frame,
	Button: TextButton,
	Stroke: UIStroke,
	Scale: UIScale,
	Name: TextLabel,
}

-- gui objects
local hotbar: Frame? = nil
local healthPanel: Frame? = nil
local healthFill: Frame? = nil
local ammoPanel: Frame? = nil
local ammoName: TextLabel? = nil
local ammoCount: TextLabel? = nil
local ammoMag: TextLabel? = nil
local ammoBarFill: Frame? = nil
local fireBtn: TextButton? = nil
local reloadBtn: TextButton? = nil
local reticle: Frame? = nil
local hitMarker: Frame? = nil
local damageEdge: Frame? = nil
local edgeStrips: { Frame } = {}
local bound: { GuiObject } = {}
local slots: { Slot } = {}

-- server state (CombatStateUpdate)
local currentWeaponId: string? = nil
local ammo = 0
local magazineSize = 0
local reloading = false
local alive = true
local health = 100
local maxHealth = 100
local healthKnown = false -- a CombatStateUpdate arrived for this life (health drops before that are no damage)

-- client state
local initialized = false
local isTouch = false
local drawn = HB.DrawnOnSpawn == true
local firing = false -- mouse / gamepad hold
local fireTouches: { [InputObject]: boolean } = {} -- touch FIRE holds, one entry per finger
local knownLevel: number? = nil
local lastEquipRequestId: string? = nil
local lastEquipRequestAt = -math.huge
local slotIds: { string } = {}
local hotbarKey = "?"
local reloadMult = 1 -- research WeaponReload (display only: the reload bar's duration)
local reloadTween: Tween? = nil
local lastAutoReloadAt = -math.huge
local lastWheelAt = -math.huge
local lastEdgeFlashAt = -math.huge
local edgeToken = 0
local markerToken = 0
local lastCombatAt = -math.huge
local combatWatching = false
local fullSince: number? = nil
local hurtWatching = false
local wheelBound = false
local humanoid: Humanoid? = nil
local lastHumHealth: number? = nil
local humConns: { RBXScriptConnection } = {}

-- forward declarations
local requestFire: () -> ()
local requestReload: () -> ()
local setDrawn: (on: boolean) -> ()
local refreshHotbar: () -> ()
local refreshAmmo: () -> ()
local updateWheelBinding: () -> ()

local function clock(): number
	return os.clock()
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

local function round(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = parent
end

---------------------------------------------------------------------------------------------------------------
-- context: seated / blocked
---------------------------------------------------------------------------------------------------------------

-- Seated in anything (driver or passenger) or driving through VehicleDriveClient (WE_DriveMode).
local function seatedNow(): boolean
	if HudLayout.GetFlag("Driving") then
		return true
	end
	local mode = player:GetAttribute("WE_DriveMode")
	if typeof(mode) == "string" and mode ~= "" then
		return true
	end
	local hum = humanoid
	return hum ~= nil and hum.Parent ~= nil and hum.SeatPart ~= nil
end

local function combatBlocked(): boolean
	if not alive or GuiService.MenuIsOpen or seatedNow() then
		return true
	end
	for _, f in ipairs(KEYS.CombatInputBlockedWhen) do
		if HudLayout.GetFlag(f) then
			return true
		end
	end
	return false
end

local function stopFiring()
	firing = false
	table.clear(fireTouches)
end

local function refreshBound()
	for _, obj in ipairs(bound) do
		HudLayout.RefreshVisibility(obj)
	end
end

local function publishDrawn()
	HudLayout.SetFlag("Drawn", drawn and alive and not HudLayout.GetFlag("Dead"))
end

---------------------------------------------------------------------------------------------------------------
-- flags: RecentCombat (fired / hit / hurt within Health.RecentCombatSeconds), Hurt (HP < max, + fade after full)
---------------------------------------------------------------------------------------------------------------

local function markCombat()
	lastCombatAt = clock()
	HudLayout.SetFlag("RecentCombat", true)
	if combatWatching then
		return
	end
	combatWatching = true
	task.spawn(function()
		while true do
			local left = lastCombatAt + HP.RecentCombatSeconds - clock()
			if left <= 0 then
				break
			end
			task.wait(left + 0.05)
		end
		combatWatching = false
		HudLayout.SetFlag("RecentCombat", false)
	end)
end

local function refreshHurt()
	if alive and maxHealth > 0 and health < maxHealth - 0.5 then
		fullSince = nil
		HudLayout.SetFlag("Hurt", true)
		return
	end
	if not alive then
		fullSince = nil
		HudLayout.SetFlag("Hurt", false)
		return
	end
	if not HudLayout.GetFlag("Hurt") then
		return
	end
	if fullSince == nil then
		fullSince = clock()
	end
	if hurtWatching then
		return
	end
	hurtWatching = true
	task.spawn(function()
		while true do
			local since = fullSince
			if since == nil then
				break -- hurt again (or dead): the flag is already right
			end
			local left = since + HP.HideAfterFullSeconds - clock()
			if left <= 0 then
				HudLayout.SetFlag("Hurt", false)
				break
			end
			task.wait(left + 0.05)
		end
		hurtWatching = false
	end)
end

---------------------------------------------------------------------------------------------------------------
-- damage edge (replaces the full-screen strobe) + hit marker
---------------------------------------------------------------------------------------------------------------

local function steadyEdge(): number
	if alive and maxHealth > 0 and health > 0 and health / maxHealth <= HP.LowHpVignette then
		return EDGE_LOW_HP_TRANSPARENCY
	end
	return 1
end

local function setEdge(transparency: number)
	local e = damageEdge
	if not e then
		return
	end
	for _, s in ipairs(edgeStrips) do
		s.BackgroundTransparency = transparency
	end
	e.Visible = transparency < 0.99
end

local function flashEdge()
	local t = clock()
	if t - lastEdgeFlashAt < HF.DamageEdgeMinGap then
		return
	end
	lastEdgeFlashAt = t
	edgeToken += 1
	local token = edgeToken
	setEdge(HF.DamageEdgeTransparency)
	task.delay(HF.DamageEdgeSeconds, function()
		if edgeToken == token then
			setEdge(steadyEdge())
		end
	end)
end

local function showHitMarker(kind: string)
	local m = hitMarker
	if not m then
		return
	end
	local color = if kind == "Kill" then Color3.fromRGB(255, 90, 70) else Color3.fromRGB(255, 230, 80)
	for _, child in ipairs(m:GetChildren()) do
		if child:IsA("Frame") then
			child.BackgroundColor3 = color
		end
	end
	m.Visible = true
	markerToken += 1
	local token = markerToken
	task.delay(HF.HitMarkerSeconds, function()
		if markerToken == token and hitMarker then
			hitMarker.Visible = false
		end
	end)
end

local function onDamaged()
	if not alive then
		return
	end
	markCombat()
	flashEdge()
	-- ambush: draw the last weapon (not from a seat — combat is hidden there and Q/1-4 belong to the vehicle)
	if HB.AutoDrawOnDamage and not drawn and not seatedNow() and not HudLayout.GetFlag("Dead") then
		setDrawn(true)
	end
end

---------------------------------------------------------------------------------------------------------------
-- health
---------------------------------------------------------------------------------------------------------------

local function applyHealth(h: number, mx: number)
	if h ~= h or mx ~= mx then
		return
	end
	health = math.max(0, h)
	maxHealth = math.max(0, mx)
	local fill = healthFill
	if fill and maxHealth > 0 then
		local ratio = math.clamp(health / maxHealth, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = if ratio <= 0.25 then HP.Low elseif ratio <= 0.5 then HP.Mid else HP.Fill
	end
	if clock() - lastEdgeFlashAt >= HF.DamageEdgeSeconds then
		setEdge(steadyEdge())
	end
	refreshHurt()
end

---------------------------------------------------------------------------------------------------------------
-- weapons: owned list, hotbar slots, equip / cycle / draw
---------------------------------------------------------------------------------------------------------------

local function shortName(id: string): string
	local def = WeaponConfig.Weapons[id]
	if not def then
		return string.upper(id)
	end
	local sn = def.ShortName
	if sn ~= nil and sn ~= "" then
		return sn
	end
	return string.upper(def.DisplayName)
end

--[[ Owned weapons the server would equip (WE_Weapons attribute, at/above UnlockLevel when the level is known),
	in the Shop › WEAPONS order (WeaponConfig.SortedIds). The server's equipped weapon is always included. ]]
local function ownedCandidates(): { string }
	local owned = WeaponConfig.ParseOwned(player:GetAttribute("WE_Weapons"))
	local level = knownLevel
	local ids: { string } = {}
	for _, id in ipairs(WeaponConfig.SortedIds()) do
		local def = WeaponConfig.Weapons[id]
		if owned[id] and (level == nil or level >= def.UnlockLevel) then
			table.insert(ids, id)
		end
	end
	local cur = currentWeaponId
	if cur and WeaponConfig.Weapons[cur] and not table.find(ids, cur) then
		table.insert(ids, cur)
	end
	return ids
end

-- the weapon just requested (state push not back yet) or the server's equipped one
local function activeWeaponId(): string?
	local pending = lastEquipRequestId
	if pending and clock() - lastEquipRequestAt < EQUIP_PENDING_SECONDS then
		return pending
	end
	return currentWeaponId
end

--[[ Up to Hotbar.MaxSlots owned weapons; with more owned, the last slot shows the active weapon when it would
	not make the cut (Q / wheel / L1 / R1 still reach every owned weapon). ]]
local function hotbarIds(): { string }
	local ids = ownedCandidates()
	local max = HB.MaxSlots
	if #ids <= max then
		return ids
	end
	local out = table.move(ids, 1, max, 1, {})
	local cur = activeWeaponId()
	if cur and not table.find(out, cur) and table.find(ids, cur) then
		out[max] = cur
	end
	return out
end

local function equip(id: string)
	lastEquipRequestId = id
	local at = clock()
	lastEquipRequestAt = at
	-- bounded (≤ 3 s) remote lookup, off the input thread
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEquipWeapon, id)
	-- when the pending window ends, the hotbar highlights whatever the server actually equipped (a refused
	-- equip — level / ownership — falls back to the real weapon)
	task.delay(EQUIP_PENDING_SECONDS + 0.05, function()
		if lastEquipRequestAt == at then
			refreshHotbar()
			refreshAmmo()
		end
	end)
end

local function selectSlot(i: number)
	local id = slotIds[i]
	if not id then
		return
	end
	local active = activeWeaponId()
	if drawn and id == active then
		if HB.TapSelectedHolsters then
			setDrawn(false)
		end
		return
	end
	if id ~= active then
		equip(id)
	end
	setDrawn(true)
end

local function cycleWeapon(delta: number)
	local ids = ownedCandidates()
	if #ids == 0 then
		return
	end
	local from = activeWeaponId()
	local idx = if from then table.find(ids, from) else nil
	local target: string
	if idx == nil then
		target = if delta >= 0 then ids[1] else ids[#ids]
	else
		local step = if delta >= 0 then 1 else -1
		target = ids[((idx - 1 + step) % #ids) + 1]
	end
	if target ~= from then
		equip(target)
	end
	if drawn then
		refreshHotbar()
	else
		setDrawn(true)
	end
end

setDrawn = function(on: boolean)
	if drawn ~= on then
		drawn = on
		if not on then
			stopFiring()
		end
	end
	publishDrawn()
	refreshHotbar()
	refreshAmmo()
	updateWheelBinding()
end

---------------------------------------------------------------------------------------------------------------
-- hotbar
---------------------------------------------------------------------------------------------------------------

local function slotSize(): number
	return if isTouch then HB.Slot else HB.SlotDesktop
end

-- v from the content bottom to the health bar's bottom edge: Hotbar.Bottom + slot + Health.GapAboveHotbar,
-- raised when needed so the DRAWN slot (UIScale SelectedScale about its bottom edge + its outer stroke) keeps
-- a 2 v gap below the bar (touch 85 v, desktop 70 v; the action lane still starts at ActionLaneBottomV()).
local function healthBottomV(): number
	local s = slotSize()
	local selectedTop = s * HB.SelectedScale + HB.SelectedStrokePx
	return HB.Bottom + math.max(s + HP.GapAboveHotbar, selectedTop + 2)
end

local function styleSlot(sl: Slot, selected: boolean)
	sl.Button.BackgroundTransparency = if selected then HB.SelectedBgTransparency else HB.BgTransparency
	sl.Stroke.Thickness = if selected then HB.SelectedStrokePx else 1.5
	sl.Stroke.Transparency = if selected then 0 else HB.StrokeTransparency
	sl.Scale.Scale = if selected then HB.SelectedScale else 1
end

local function makeSlot(parent: Frame, i: number): Slot
	local s = slotSize()
	local nameSize = if isTouch then HB.NameSize else HB.NameSizeDesktop

	local cell = Instance.new("Frame")
	cell.Name = "Slot" .. i
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Size = UDim2.fromOffset(s, s)
	cell.LayoutOrder = i
	cell.Active = false

	-- the button fills the cell; its UIScale (selected 1.08) grows it about the bottom-centre anchor
	local btn = Instance.new("TextButton")
	btn.Name = "SlotButton"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.fromScale(0.5, 1)
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = HB.Bg
	btn.BackgroundTransparency = HB.BgTransparency
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Active = true
	btn.Parent = cell
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, HB.Corner)
	c.Parent = btn
	local st = stroke(btn, HB.Stroke, 1.5, HB.StrokeTransparency)
	local sc = Instance.new("UIScale")
	sc.Name = "SlotScale"
	sc.Parent = btn

	local num = Instance.new("TextLabel")
	num.Name = "Number"
	num.BackgroundTransparency = 1
	num.Position = UDim2.fromOffset(5, 2)
	num.Size = UDim2.fromOffset(20, HB.NumberSize + 2)
	num.Font = FONT_BODY
	num.TextSize = HB.NumberSize
	num.TextColor3 = WHITE
	num.TextTransparency = 0.3
	num.TextXAlignment = Enum.TextXAlignment.Left
	num.TextYAlignment = Enum.TextYAlignment.Top
	num.Text = tostring(i)
	num.Active = false
	num.Parent = btn
	UIUtil.TextOutline(num, 1, nil, 0.3)

	-- a little wider than the slot (into the gap) so "SHOTGUN" keeps its full size on phones
	local name = Instance.new("TextLabel")
	name.Name = "WeaponName"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 1)
	name.Position = UDim2.new(0.5, 0, 1, -4)
	name.Size = UDim2.new(1, HB.Gap + 4, 0, nameSize + 4)
	name.Font = FONT_BODY
	name.TextScaled = true
	name.TextColor3 = WHITE
	name.Text = ""
	name.Active = false
	name.Parent = btn
	local tc = Instance.new("UITextSizeConstraint")
	tc.MaxTextSize = nameSize
	tc.Parent = name
	UIUtil.TextOutline(name, 1)

	btn.Activated:Connect(function()
		if not combatBlocked() then
			selectSlot(i)
		end
	end)
	HudLayout.AssertTouchTarget(btn, "Hotbar slot " .. i)
	cell.Parent = parent
	return { Cell = cell, Button = btn, Stroke = st, Scale = sc, Name = name }
end

refreshHotbar = function()
	local bar = hotbar
	if not bar then
		return
	end
	local ids = hotbarIds()
	local key = table.concat(ids, ",")
	if key ~= hotbarKey then
		hotbarKey = key
		slotIds = ids
		for _, sl in ipairs(slots) do
			sl.Cell:Destroy()
		end
		table.clear(slots)
		for i, id in ipairs(ids) do
			local sl = makeSlot(bar, i)
			sl.Name.Text = shortName(id)
			slots[i] = sl
		end
		local s = slotSize()
		local n = #ids
		local w = if n > 0 then n * s + (n - 1) * HB.Gap else 0
		bar.Size = UDim2.fromOffset(w, s)
		local hp = healthPanel
		if hp then
			hp.Size = UDim2.fromOffset(math.max(w, HP.MinWidth), HP.Height)
		end
		HudLayout.RefreshVisibility(bar)
	end
	local sel = if drawn then activeWeaponId() else nil
	for i, sl in ipairs(slots) do
		styleSlot(sl, sel ~= nil and slotIds[i] == sel)
	end
end

---------------------------------------------------------------------------------------------------------------
-- ammo readout
---------------------------------------------------------------------------------------------------------------

local function reloadSeconds(): number
	local id = currentWeaponId
	local def = if id then WeaponConfig.Weapons[id] else nil
	local base = if def then def.ReloadTime else 2
	return math.max(0.1, base / math.max(1, reloadMult))
end

local function stopReloadTween()
	local tw = reloadTween
	if tw then
		reloadTween = nil
		tw:Cancel()
	end
end

-- reloading: the gold bar fills over the (research-scaled) reload time; the server's push ends it
local function startReloadBar()
	local fill = ammoBarFill
	if not fill then
		return
	end
	stopReloadTween()
	fill.BackgroundColor3 = AM.ReloadColor
	fill.Size = UDim2.fromScale(0, 1)
	local tw = TweenService:Create(fill, TweenInfo.new(reloadSeconds(), Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
	reloadTween = tw
	tw:Play()
end

refreshAmmo = function()
	local name, count, mag, fill = ammoName, ammoCount, ammoMag, ammoBarFill
	if not (name and count and mag and fill) then
		return
	end
	local id = currentWeaponId
	local def = if id then WeaponConfig.Weapons[id] else nil
	local wname = if def then string.upper(def.DisplayName) elseif id then string.upper(id) else ""
	local n = math.max(0, math.floor(ammo))
	local m = math.max(0, math.floor(magazineSize))
	count.Text = tostring(n)
	mag.Text = "/" .. tostring(m)
	local frac = if m > 0 then math.clamp(n / m, 0, 1) else 0
	local low = m > 1 and n <= math.max(1, math.floor(m * AM.LowFraction))
	if reloading then
		name.Text = "RELOADING"
		count.TextColor3 = AM.CountColor
		fill.BackgroundColor3 = AM.ReloadColor
		if not reloadTween then
			fill.Size = UDim2.fromScale(1, 1)
		end
		return
	end
	stopReloadTween()
	if n <= 0 then
		name.Text = if isTouch then "TAP ↻" else "RELOAD [R]"
		count.TextColor3 = AM.EmptyColor
		fill.BackgroundColor3 = AM.EmptyColor
	elseif low then
		name.Text = wname
		count.TextColor3 = AM.LowColor
		fill.BackgroundColor3 = AM.LowColor
	else
		name.Text = wname
		count.TextColor3 = AM.CountColor
		fill.BackgroundColor3 = WHITE
	end
	fill.Size = UDim2.fromScale(frac, 1)
end

---------------------------------------------------------------------------------------------------------------
-- server state
---------------------------------------------------------------------------------------------------------------

local function applyState(raw: any)
	if typeof(raw) ~= "table" then
		return
	end
	local payload: Types.CombatStatePayload = raw
	local wasReloading = reloading
	local prevWeapon = currentWeaponId
	local prevHealth = health
	alive = payload.Alive ~= false
	ammo = tonumber(payload.Ammo) or 0
	magazineSize = tonumber(payload.MagazineSize) or 0
	reloading = payload.Reloading == true and alive
	local wid = payload.WeaponId
	currentWeaponId = if typeof(wid) == "string" then wid else nil
	if lastEquipRequestId ~= nil and lastEquipRequestId == currentWeaponId then
		lastEquipRequestId = nil
	end
	HudLayout.SetFlag("Reloading", reloading)
	local h = tonumber(payload.Health)
	local mx = tonumber(payload.MaxHealth)
	if h and mx then
		applyHealth(h, mx)
		if alive and healthKnown and h < prevHealth - 0.5 then
			onDamaged()
		end
		healthKnown = alive
	end
	if not alive then
		stopFiring()
	end
	if reloading and (not wasReloading or prevWeapon ~= currentWeaponId) then
		startReloadBar()
	end
	publishDrawn()
	refreshHotbar()
	refreshAmmo()
	local ap = ammoPanel
	if ap then
		HudLayout.RefreshVisibility(ap)
	end
	updateWheelBinding()
end

local function onHitFeedback(raw: any)
	if typeof(raw) ~= "table" then
		return
	end
	local kind = raw.Kind
	if kind == "Hit" or kind == "Kill" then
		markCombat()
		showHitMarker(kind)
	elseif kind == "Damaged" then
		onDamaged()
	elseif kind == "Death" then
		stopFiring()
		flashEdge()
	end
end

---------------------------------------------------------------------------------------------------------------
-- requests (never damage amounts)
---------------------------------------------------------------------------------------------------------------

local function aimRay(): (Vector3, Vector3)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local fallbackOrigin = if root then root.Position + Vector3.new(0, 1.5, 0) else Vector3.new(0, 5, 0)

	local cam = Workspace.CurrentCamera
	if cam then
		-- the viewport centre = WE_Reticle's centre (that gui ignores the topbar + safe-area insets)
		local vp = cam.ViewportSize
		local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
		return ray.Origin, ray.Direction.Unit
	end
	return fallbackOrigin, Vector3.new(0, 0, -1)
end

local function canFireNow(): boolean
	if combatBlocked() then
		return false
	end
	if KEYS.FireNeedsDrawn and not drawn then
		return false -- holstered: the click belongs to the world (droppers, consoles, ClickDetectors)
	end
	return true
end

requestFire = function()
	if not canFireNow() or reloading then
		return
	end
	if ammo <= 0 then
		-- empty trigger pull → one reload request (the readout already says RELOAD)
		local t = clock()
		if t - lastAutoReloadAt >= AUTO_RELOAD_MIN_GAP then
			lastAutoReloadAt = t
			requestReload()
		end
		return
	end

	local origin, direction = aimRay()
	local payload: Types.FireRequestPayload = {
		Direction = direction,
		Origin = origin,
		TargetUserId = nil,
		TargetNpcId = nil,
		HitPosition = nil,
	}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	if character then
		params.FilterDescendantsInstances = { character }
	end
	local result = Workspace:Raycast(origin, direction * 500, params)
	if result then
		payload.HitPosition = result.Position
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model then
			local other = Players:GetPlayerFromCharacter(model)
			if other then
				payload.TargetUserId = other.UserId
			else
				local npcId = model:GetAttribute("NPCId")
				if typeof(npcId) == "string" then
					payload.TargetNpcId = npcId
				end
			end
		end
	end

	-- non-blocking lookup: a missing remote drops the shot instead of stalling the 20 Hz loop
	local remote = Remotes.TryGetEvent(Constants.RemoteNames.RequestFire)
	if remote then
		remote:FireServer(payload)
		markCombat()
	end
end

requestReload = function()
	if combatBlocked() then
		return
	end
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestReload)
end

---------------------------------------------------------------------------------------------------------------
-- mouse wheel (bound only while drawn, so a holstered wheel still zooms the camera)
---------------------------------------------------------------------------------------------------------------

local function onWheel(_name: string, _state: Enum.UserInputState, io: InputObject): Enum.ContextActionResult
	local z = io.Position.Z
	if z == 0 or not drawn or combatBlocked() then
		return Enum.ContextActionResult.Pass
	end
	local t = clock()
	if t - lastWheelAt >= WHEEL_MIN_GAP then
		lastWheelAt = t
		cycleWeapon(if z < 0 then 1 else -1)
	end
	return Enum.ContextActionResult.Sink
end

updateWheelBinding = function()
	local want = KEYS.WeaponWheel == true and UserInputService.MouseEnabled and drawn and not combatBlocked()
	if want == wheelBound then
		return
	end
	wheelBound = want
	if want then
		ContextActionService:BindActionAtPriority(
			ACTION_WHEEL,
			onWheel,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.UserInputType.MouseWheel
		)
	else
		ContextActionService:UnbindAction(ACTION_WHEEL)
	end
end

---------------------------------------------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------------------------------------------

type TouchGeo = { FireRight: number, FireBottom: number, ReloadRight: number, ReloadBottom: number, AmmoBottom: number }

-- v offsets from the content rect's bottom-right (see the jump-button note at the top)
local function touchGeometry(): TouchGeo
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
	local geo: TouchGeo = {
		FireRight = TC.Fire.Right,
		FireBottom = TC.Fire.Bottom,
		ReloadRight = TC.Reload.Right,
		ReloadBottom = TC.Reload.Bottom,
		AmmoBottom = AM.BottomTouch,
	}
	if math.min(vp.X, vp.Y) <= SMALL_JUMP_MAX_AXIS then
		return geo
	end
	local s = HudLayout.Scale()
	local half = TC.Fire.Size * TC.Fire.Anchor.X
	local reloadGap = TC.Reload.Right - TC.Fire.Right - half -- v between FIRE's left edge and RELOAD
	local ammoGap = AM.BottomTouch - TC.Fire.Bottom - TC.Fire.Size -- v between FIRE's top and the readout
	geo.FireRight = LARGE_JUMP_CENTRE_FROM_RIGHT / s
	geo.FireBottom = (LARGE_JUMP_TOP_FROM_BOTTOM + FIRE_ABOVE_JUMP) / s
	geo.ReloadRight = geo.FireRight + half + reloadGap
	geo.ReloadBottom = geo.FireBottom + (TC.Reload.Bottom - TC.Fire.Bottom)
	geo.AmmoBottom = geo.FireBottom + TC.Fire.Size + ammoGap
	return geo
end

local function placeCombatControls()
	local ap = ammoPanel
	if not isTouch then
		if ap then
			ap.Position = UDim2.new(1, -AM.Right, 1, -AM.Bottom)
		end
		return
	end
	local g = touchGeometry()
	if ap then
		ap.Position = UDim2.new(1, -AM.RightTouch, 1, -g.AmmoBottom)
	end
	local f = fireBtn
	if f then
		f.Position = UDim2.new(1, -g.FireRight, 1, -g.FireBottom)
	end
	local r = reloadBtn
	if r then
		r.Position = UDim2.new(1, -g.ReloadRight, 1, -g.ReloadBottom)
	end
end

local function textLabel(parent: Instance, name: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = ""
	l.Active = false
	l.Parent = parent
	return l
end

local function buildAmmo(parent: Instance)
	local size = if isTouch then AM.SizeTouch else AM.Size
	local countSize = if isTouch then AM.CountSizeTouch else AM.CountSize
	local magSize = if isTouch then AM.MagSizeTouch else AM.MagSize
	local barW = if isTouch then math.floor(AM.SizeTouch.X * 0.75) else AM.BarSize.X
	local barH = AM.BarSize.Y

	local ap = Instance.new("Frame")
	ap.Name = "AmmoPanel"
	ap.AnchorPoint = AM.Anchor
	ap.Size = UDim2.fromOffset(size.X, size.Y)
	ap.BackgroundTransparency = 1
	ap.BorderSizePixel = 0
	ap.Active = false
	ap.Parent = parent
	ammoPanel = ap

	local name = textLabel(ap, "WeaponName", FONT_BODY, AM.NameSize, WHITE)
	name.AnchorPoint = Vector2.new(1, 0)
	name.Position = UDim2.fromScale(1, 0)
	name.Size = UDim2.new(1, 0, 0, AM.NameSize + 2)
	name.TextXAlignment = Enum.TextXAlignment.Right
	name.TextTransparency = 0.1
	UIUtil.TextOutline(name, 1)
	ammoName = name

	local row = Instance.new("Frame")
	row.Name = "CountRow"
	row.AnchorPoint = Vector2.new(1, 1)
	row.Position = UDim2.new(1, 0, 1, -(barH + (if isTouch then 4 else 6)))
	row.Size = UDim2.new(1, 0, 0, countSize)
	row.BackgroundTransparency = 1
	row.Active = false
	row.Parent = ap
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = row

	local count = textLabel(row, "Count", FONT_DISPLAY, countSize, AM.CountColor)
	count.AutomaticSize = Enum.AutomaticSize.X
	count.Size = UDim2.fromOffset(0, countSize)
	count.TextYAlignment = Enum.TextYAlignment.Bottom
	count.LayoutOrder = 1
	UIUtil.TextOutline(count, if isTouch then 1.6 else 2)
	ammoCount = count

	local mag = textLabel(row, "Magazine", FONT_DISPLAY, magSize, AM.MagColor)
	mag.AutomaticSize = Enum.AutomaticSize.X
	mag.Size = UDim2.fromOffset(0, magSize)
	mag.TextYAlignment = Enum.TextYAlignment.Bottom
	mag.LayoutOrder = 2
	UIUtil.TextOutline(mag, 1.3)
	ammoMag = mag

	local bar = Instance.new("Frame")
	bar.Name = "MagBar"
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.fromScale(1, 1)
	bar.Size = UDim2.fromOffset(barW, barH)
	bar.BackgroundColor3 = WHITE
	bar.BackgroundTransparency = 0.78
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	bar.Active = false
	bar.Parent = ap
	round(bar)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(1, 0)
	fill.Position = UDim2.fromScale(1, 0)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.Parent = bar
	round(fill)
	ammoBarFill = fill
end

local function buildTouchButtons(parent: Instance)
	local fire = Instance.new("TextButton")
	fire.Name = "FireButton"
	fire.AnchorPoint = TC.Fire.Anchor
	fire.Size = UDim2.fromOffset(TC.Fire.Size, TC.Fire.Size)
	fire.BackgroundColor3 = TC.FireColor
	fire.BackgroundTransparency = 0.05
	fire.BorderSizePixel = 0
	fire.Text = ""
	fire.AutoButtonColor = true
	fire.Active = true
	fire.ZIndex = 2
	fire.Parent = parent
	round(fire)
	stroke(fire, Color3.fromRGB(0, 0, 0), 3, 0.55)
	HudIcons.Make("Crosshair", fire, {
		Name = "Icon",
		Size = UDim2.fromScale(0.6, 0.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Color = WHITE,
		Fill = TC.FireColor,
	})
	-- hold-to-fire: one entry per finger; released on the button's InputEnded or anywhere (TouchEnded)
	fire.InputBegan:Connect(function(io: InputObject)
		local ut = io.UserInputType
		if ut == Enum.UserInputType.Touch or ut == Enum.UserInputType.MouseButton1 then
			if canFireNow() then
				fireTouches[io] = true
				requestFire()
			end
		end
	end)
	fire.InputEnded:Connect(function(io: InputObject)
		fireTouches[io] = nil
	end)
	fireBtn = fire
	HudLayout.AssertTouchTarget(fire, "FIRE")

	local rel = Instance.new("TextButton")
	rel.Name = "ReloadButton"
	rel.AnchorPoint = TC.Reload.Anchor
	rel.Size = UDim2.fromOffset(TC.Reload.Size, TC.Reload.Size)
	rel.BackgroundColor3 = TC.ReloadColor
	rel.BackgroundTransparency = 0.12
	rel.BorderSizePixel = 0
	rel.Text = ""
	rel.AutoButtonColor = true
	rel.Active = true
	rel.ZIndex = 2
	rel.Parent = parent
	round(rel)
	stroke(rel, Color3.fromRGB(0, 0, 0), 2.5, 0.55)
	HudIcons.Make("Cycle", rel, {
		Name = "Icon",
		Size = UDim2.fromScale(0.56, 0.56),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Color = WHITE,
		Fill = TC.ReloadColor,
	})
	rel.Activated:Connect(function()
		requestReload()
	end)
	reloadBtn = rel
	HudLayout.AssertTouchTarget(rel, "RELOAD")
end

local function buildReticleGui(pg: Instance)
	local rg = Instance.new("ScreenGui")
	rg.Name = "WE_Reticle"
	HudLayout.ApplyScreen(rg, { Insets = "None" }) -- full screen: (0.5, 0.5) is the viewport centre = aimRay

	-- screen-edge damage flash / low-HP edge, drawn under every other HUD gui (DisplayOrder 24)
	local edge = Instance.new("Frame")
	edge.Name = "DamageEdge"
	edge.BackgroundTransparency = 1
	edge.Size = UDim2.fromScale(1, 1)
	edge.Visible = false
	edge.Active = false
	edge.Parent = rg
	damageEdge = edge
	type EdgeSpec = { Name: string, Size: UDim2, Pos: UDim2, Rot: number }
	local specs: { EdgeSpec } = {
		{ Name = "Top", Size = UDim2.new(1, 0, 0, EDGE_V), Pos = UDim2.fromScale(0, 0), Rot = 90 },
		{ Name = "Bottom", Size = UDim2.new(1, 0, 0, EDGE_V), Pos = UDim2.new(0, 0, 1, -EDGE_V), Rot = 270 },
		{ Name = "Left", Size = UDim2.new(0, EDGE_V, 1, 0), Pos = UDim2.fromScale(0, 0), Rot = 0 },
		{ Name = "Right", Size = UDim2.new(0, EDGE_V, 1, 0), Pos = UDim2.new(1, -EDGE_V, 0, 0), Rot = 180 },
	}
	for _, spec in ipairs(specs) do
		local s = Instance.new("Frame")
		s.Name = spec.Name
		s.Size = spec.Size
		s.Position = spec.Pos
		s.BackgroundColor3 = HP.Low
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.Active = false
		s.Parent = edge
		local g = Instance.new("UIGradient") -- solid at the screen edge, clear towards the middle
		g.Rotation = spec.Rot
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = s
		table.insert(edgeStrips, s)
	end

	local ret = Instance.new("Frame")
	ret.Name = "Reticle"
	ret.AnchorPoint = Vector2.new(0.5, 0.5)
	ret.Position = UDim2.fromScale(0.5, 0.5)
	ret.Size = UDim2.fromOffset(RT.Size, RT.Size)
	ret.BackgroundTransparency = 1
	ret.Active = false
	ret.ZIndex = 5
	ret.Parent = rg
	reticle = ret
	local off = RT.Gap + RT.Arm / 2
	for _, a in ipairs({
		{ 0, -off, RT.Thickness, RT.Arm },
		{ 0, off, RT.Thickness, RT.Arm },
		{ -off, 0, RT.Arm, RT.Thickness },
		{ off, 0, RT.Arm, RT.Thickness },
	}) do
		local arm = Instance.new("Frame")
		arm.Name = "Arm"
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.Position = UDim2.new(0.5, a[1], 0.5, a[2])
		arm.Size = UDim2.fromOffset(a[3], a[4])
		arm.BackgroundColor3 = RT.Color
		arm.BackgroundTransparency = 0.05
		arm.BorderSizePixel = 0
		arm.Active = false
		arm.ZIndex = 6
		arm.Parent = ret
		stroke(arm, Color3.fromRGB(0, 0, 0), 1, 0.55)
	end
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(4, 4)
	dot.BackgroundColor3 = RT.DotColor
	dot.BorderSizePixel = 0
	dot.Active = false
	dot.ZIndex = 7
	dot.Parent = ret
	round(dot)

	-- hit marker (X) on the same centre, HitFeedback.HitMarkerSeconds per hit you land
	local marker = Instance.new("Frame")
	marker.Name = "HitMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(28, 28)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.Active = false
	marker.ZIndex = 8
	marker.Parent = rg
	hitMarker = marker
	for _, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(22, 3)
		bar.BackgroundColor3 = Color3.fromRGB(255, 230, 80)
		bar.BorderSizePixel = 0
		bar.Rotation = rot
		bar.Active = false
		bar.ZIndex = 9
		bar.Parent = marker
	end

	rg.Parent = pg
end

local function buildHud(pg: Instance)
	isTouch = HudLayout.IsTouch()

	local sg = Instance.new("ScreenGui")
	sg.Name = "WarEmpireCombatHUD"
	HudLayout.ApplyScreen(sg) -- DisplayOrder 25 (HudConfig.DisplayOrder), CoreUISafeInsets, MobileScale

	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -HB.Bottom)
	bar.Size = UDim2.fromOffset(0, slotSize())
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Active = false
	bar.Parent = sg
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, HB.Gap)
	list.Parent = bar
	hotbar = bar

	local hp = Instance.new("Frame")
	hp.Name = "HealthPanel"
	hp.AnchorPoint = Vector2.new(0.5, 1)
	hp.Position = UDim2.new(0.5, 0, 1, -healthBottomV())
	hp.Size = UDim2.fromOffset(HP.MinWidth, HP.Height)
	hp.BackgroundColor3 = HP.Bg
	hp.BackgroundTransparency = HP.BgTransparency
	hp.BorderSizePixel = 0
	hp.ClipsDescendants = true
	hp.Active = false
	hp.Parent = sg
	round(hp)
	stroke(hp, COLORS.Ink, 1, 0.2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HP.Fill
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.Parent = hp
	round(fill)
	healthPanel = hp
	healthFill = fill

	buildAmmo(sg)
	if isTouch then
		buildTouchButtons(sg)
	end
	placeCombatControls()

	sg.Parent = pg
	buildReticleGui(pg)

	HudLayout.SetRect("Hotbar", bar)
	HudLayout.SetRect("Health", hp)
	HudLayout.SetRect("Ammo", ammoPanel :: Frame)

	-- visibility: the HudConfig rules + "not seated" (VehicleDriveClient's ▲▼ own the reserve while seated)
	local function notSeated(): boolean
		return not seatedNow()
	end
	HudLayout.BindVisibility(bar, HB, function(): boolean
		return #slotIds > 0 and not seatedNow()
	end)
	HudLayout.BindVisibility(hp, HP, notSeated)
	HudLayout.BindVisibility(ammoPanel :: Frame, AM, function(): boolean
		return currentWeaponId ~= nil and not seatedNow()
	end)
	bound = { bar, hp, ammoPanel :: Frame }
	local f, r = fireBtn, reloadBtn
	if f and r then
		HudLayout.BindVisibility(f, TC, notSeated)
		HudLayout.BindVisibility(r, TC, notSeated)
		table.insert(bound, f)
		table.insert(bound, r)
	end
	local ret = reticle
	if ret then
		HudLayout.BindVisibility(ret, RT, notSeated)
		table.insert(bound, ret)
	end
end

---------------------------------------------------------------------------------------------------------------
-- character / seat / flags
---------------------------------------------------------------------------------------------------------------

local function onSeatContext()
	if seatedNow() then
		stopFiring()
	end
	refreshBound()
	updateWheelBinding()
end

local function bindHumanoid(hum: Humanoid)
	for _, c in ipairs(humConns) do
		c:Disconnect()
	end
	table.clear(humConns)
	humanoid = hum
	lastHumHealth = tonumber(hum.Health)
	table.insert(
		humConns,
		hum.HealthChanged:Connect(function(h: number)
			local prev = lastHumHealth
			lastHumHealth = h
			local mx = tonumber(hum.MaxHealth) or maxHealth
			applyHealth(h, mx)
			if prev ~= nil and h > 0 and h < prev - 0.5 then
				onDamaged()
			end
		end)
	)
	table.insert(humConns, hum:GetPropertyChangedSignal("SeatPart"):Connect(onSeatContext))
	onSeatContext()
end

local function onCharacter(char: Model)
	-- every life starts holstered (HudConfig.Hotbar.DrawnOnSpawn)
	drawn = HB.DrawnOnSpawn == true
	stopFiring()
	fullSince = nil
	healthKnown = false
	setDrawn(drawn)
	local h = char:FindFirstChildOfClass("Humanoid")
	if h then
		bindHumanoid(h)
		return
	end
	task.spawn(function()
		local found = char:WaitForChild("Humanoid", 10)
		if found and found:IsA("Humanoid") and player.Character == char then
			bindHumanoid(found)
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------------------------------------------

function CombatController.IsDrawn(): boolean
	return drawn
end

function CombatController.Holster()
	setDrawn(false)
end

function CombatController.Draw()
	setDrawn(true)
end

function CombatController.Init()
	if initialized then
		return
	end
	-- PlayerGui exists before LocalScripts run; the bounded wait only covers a very slow client
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not pg then
		warn("[CombatController] no PlayerGui after 10 s — combat HUD not built")
		return
	end
	initialized = true
	HudLayout.Init()
	buildHud(pg)
	publishDrawn()
	refreshHotbar()
	refreshAmmo()

	-- level for the hotbar's UnlockLevel filter (server attribute + XPUpdate, whichever is newer)
	local function readLevelAttribute()
		local v = player:GetAttribute("WE_Level")
		if typeof(v) == "number" then
			knownLevel = v
			refreshHotbar()
		end
	end
	readLevelAttribute()
	player:GetAttributeChangedSignal("WE_Level"):Connect(readLevelAttribute)
	player:GetAttributeChangedSignal("WE_Weapons"):Connect(refreshHotbar)
	player:GetAttributeChangedSignal("WE_DriveMode"):Connect(onSeatContext)
	Remotes.BindEvent(Constants.RemoteNames.XPUpdate, function(payload: any)
		if typeof(payload) == "table" and typeof(payload.Level) == "number" then
			knownLevel = payload.Level
			refreshHotbar()
		end
	end)
	-- research WeaponReload → reload bar duration (display only; magazine size arrives in CombatStateUpdate)
	Remotes.BindEvent(Constants.RemoteNames.ResearchStateUpdate, function(payload: any)
		if typeof(payload) == "table" then
			local m = ResearchConfig.MultFor(payload.Levels, "WeaponReload")
			if typeof(m) == "number" and m == m and m >= 1 then
				reloadMult = m
			end
		end
	end)
	Remotes.BindEvent(Constants.RemoteNames.CombatStateUpdate, applyState)
	Remotes.BindEvent(Constants.RemoteNames.CombatHitFeedback, onHitFeedback)

	HudLayout.FlagChanged:Connect(function(name: string, on: boolean)
		if name == "Driving" or name == "Modal" or name == "Dead" then
			if on then
				stopFiring()
			end
			if name == "Dead" then
				publishDrawn()
			end
			if name == "Driving" then
				refreshBound()
			end
			updateWheelBinding()
		end
	end)
	HudLayout.LayoutChanged:Connect(placeCombatControls)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local ut = input.UserInputType
		local kc = input.KeyCode
		if ut == Enum.UserInputType.MouseButton1 or kc == GP.Fire then
			if canFireNow() then
				firing = true
				requestFire()
			end
			return
		end
		if ut ~= Enum.UserInputType.Keyboard and not GAMEPAD_TYPES[ut] then
			return
		end
		if combatBlocked() then
			return -- seated: Q / R / 1-4 belong to the vehicle; panels / death / menu: nothing
		end
		local slot = table.find(KEYS.Weapons, kc)
		if slot then
			if HudLayout.GetFlag("OrdersOpen") then
				return -- Army popover open: 1-4 are squad orders (OrdersController)
			end
			selectSlot(slot)
		elseif kc == KEYS.Reload or kc == GP.Reload then
			if not drawn then
				setDrawn(true)
			end
			requestReload()
		elseif kc == KEYS.WeaponPrev or kc == GP.Prev then
			cycleWeapon(-1)
		elseif kc == GP.Next then
			cycleWeapon(1)
		elseif kc == GP.DrawHolster then
			setDrawn(not drawn)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == GP.Fire then
			firing = false
		end
		fireTouches[input] = nil
	end)
	UserInputService.TouchEnded:Connect(function(input: InputObject)
		fireTouches[input] = nil
	end)

	-- hold-to-fire loop (HudConfig.TouchCombat.HoldToFireHz); the server clamps every shot to the FireRate
	task.spawn(function()
		local period = 1 / math.max(1, TC.HoldToFireHz)
		while true do
			task.wait(period)
			if firing or next(fireTouches) ~= nil then
				if canFireNow() then
					requestFire()
				else
					stopFiring()
				end
			end
		end
	end)
end

return CombatController
