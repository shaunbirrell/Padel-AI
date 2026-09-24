--!strict
--[[
	Phase 4/7 — Garage UI (G). Spawn / buy / despawn requests only.
	Category + rarity + Owned filters for large roster (~99). ScrollingFrame AutomaticCanvasSize.
	Empty states via UIUtil.EmptyState.
	Mobile: ≥48px filter chips, ≥52px row actions, Activated (not MouseButton1 only),
	responsive panel, clear empty / filter-empty / no-owned banners.

	v70 (garage audit G4):
	  * Rows show why a vehicle is locked ("LOCKED\nLv 10", "Depot L2", "Prestige 5", "Rebirth") instead of an
	    active gold BUY; tapping a locked / unaffordable row explains it and sends nothing.
	  * No periodic rebuild: the cooldown ticker only repaints buttons in place. Rows are rebuilt only on open,
	    on a filter change, or when owned ids / the active vehicle / the unlock gates change (debounced 0.25 s).
	  * Remotes only via Remotes.BindEvent / Remotes.FireServer (never a blocking GetEvent).
	  * Sort: active, owned, buyable, can't afford, locked. Open(tab) presets the category (terminal WE_OpenTab).
	  * Touch: the panel closes once the requested vehicle is deployed.
	  * Init also starts VehicleDriveClient (the client half of drivable vehicles).

	v70 "clean screen" HUD (spec §3.7 / §3.8):
	  * No desktop GARAGE toggle: the rail's Garage tile, G (HudConfig.Keys.Garage), the vehicle-pad prompt and
	    the Vehicle Depot terminal open it. A registered Modal panel (HudLayout id "Garage") with the black dim.
	  * One HUD scale + safe area (PanelShell / HudLayout.ApplyScreen). Touch: one row of 64 v filter chips (the
	    rarity chip cycles), 64 v row buttons, ≥ 16 v text.
	  * Rail badge "!" (NewVehicle) while a vehicle bought this session has not been spawned; cleared on open.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local VehicleConfig = require(Shared.Configs.VehicleConfig)

local HudConfig = require(Shared.Configs.HudConfig)

local AudioController = require(script.Parent.Parent.Modules.AudioController)
local VehicleDriveClient = require(script.Parent.Parent.Modules.VehicleDriveClient)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local PanelShell = require(script.Parent.Parent.Modules.PanelShell)

type VehicleDef = VehicleConfig.VehicleDef

export type Gates = {
	Level: number,
	Prestige: number,
	Structures: { [string]: number },
	Rebirth: { [string]: boolean },
}

export type RowCtx = {
	Owned: any, -- { [id]: true } map (or a boolean for this row)
	ActiveId: string?,
	Cooldown: number,
	Gates: Gates?,
	Cash: number?,
}

export type RowState = {
	Kind: string, -- Despawn | Cooldown | Spawn | Locked | CantAfford | Buy | Claim
	Text: string,
	Enabled: boolean,
	Reason: string?, -- Locked: short reason
	Need: number?, -- CantAfford: cash missing
}

local VehicleController = {}

local PANEL_ID = "Garage"

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local shell: PanelShell.Shell? = nil

-- v70 rail badge (HudConfig.Rail.BadgeSources.Garage = "NewVehicle"): "!" while a vehicle bought / granted this
-- session has not been spawned yet; opening the Garage clears it. The join sync (incl. a late starter 4x4 merge)
-- never counts as new.
local NEW_VEHICLE_GRACE_SECONDS = 10
local newVehicleIds: { [string]: boolean } = {}
local ownedSyncedAt: number? = nil

local screenGui: ScreenGui? = nil
local listFrame: ScrollingFrame? = nil
local cooldownLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local panelFrame: Frame? = nil
local isOpen = false
local paintFilters: (() -> ())? = nil

local ownedMap: { [string]: boolean } = {}
local activeId: string? = nil
local cooldownLeft = 0
local gates: Gates = { Level = 1, Prestige = 0, Structures = {}, Rebirth = {} }
local filterCategory: string = "All" -- All | Ground | Air | Naval
local filterRarity: string = "All" -- All | Common | Uncommon | Rare | Epic | Legendary
local filterOwnedOnly = false
local rarityColors: { [string]: Color3 } = {
	Common = Color3.fromRGB(160, 165, 170),
	Uncommon = Color3.fromRGB(90, 180, 110),
	Rare = Color3.fromRGB(80, 140, 220),
	Epic = Color3.fromRGB(170, 90, 220),
	Legendary = Color3.fromRGB(230, 170, 60),
}

-- rows currently on screen: every row's action button, and the owned (spawn / cooldown) subset
local rowButtons: { [string]: TextButton } = {}
local spawnButtons: { [string]: TextButton } = {}
local buyingUntil: { [string]: number } = {}
local lastBuiltSig = ""
local rebuildPending = false
local repaintPending = false
local lastSpawnRequestedId: string? = nil

local STRUCTURE_SHORT: { [string]: string } =
	{ VehicleDepot = "Depot", Helipad = "Helipad", Airfield = "Airfield", Dock = "Dock" }
local STRUCTURE_LONG: { [string]: string } =
	{ VehicleDepot = "Vehicle Depot", Helipad = "Helipad", Airfield = "Airfield", Dock = "Dock" }
local KIND_RANK: { [string]: number } =
	{ Despawn = 0, Cooldown = 1, Spawn = 1, Claim = 2, Buy = 2, CantAfford = 3, Locked = 4 }

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- UIUtil.EmptyState at the panel text floor (≥ 11 real px)
local function emptyState(parent: Instance, message: string)
	local lab = UIUtil.EmptyState(parent, message, 0)
	lab.TextSize = PanelShell.Text(13)
	lab.Size = UDim2.new(1, -8, 0, PanelShell.Text(13) * 3 + 8)
	lab.Font = Enum.Font.GothamMedium
end

local function commas(n: number): string
	local s = tostring(math.floor(math.max(0, n) + 0.5))
	local out = s
	while true do
		local k
		out, k = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Pure row logic (tested headless)
-- ─────────────────────────────────────────────────────────────────────────────

--[[ Short lock reason for a not-owned vehicle, or nil when it can be bought. Order: level, structure,
	prestige, rebirth flag (same order as VehicleService.Purchase). ]]
function VehicleController._LockReason(def: VehicleDef, g: Gates?): string?
	if g == nil then
		return nil
	end
	if (g.Level or 1) < def.UnlockLevel then
		return "Lv " .. tostring(def.UnlockLevel)
	end
	local req = def.RequiresStructure
	if req then
		local have = (g.Structures and g.Structures[req.StructureId]) or 0
		if have < req.Level then
			return (STRUCTURE_SHORT[req.StructureId] or req.StructureId) .. " L" .. tostring(req.Level)
		end
	end
	local needP = def.RequiresPrestige
	if typeof(needP) == "number" and needP > 0 and (g.Prestige or 0) < needP then
		return "Prestige " .. tostring(needP)
	end
	local flag = def.RequiresRebirthFlag
	if typeof(flag) == "string" and flag ~= "" and not (g.Rebirth and g.Rebirth[flag] == true) then
		return "Rebirth"
	end
	return nil
end

--[[ Long form for the status line: "<Name> needs <reason> (you have …)". ]]
function VehicleController._LockDetail(def: VehicleDef, g: Gates): string?
	local name = def.DisplayName or def.Id
	if (g.Level or 1) < def.UnlockLevel then
		return string.format("%s needs Level %d (you have Lv %d)", name, def.UnlockLevel, g.Level or 1)
	end
	local req = def.RequiresStructure
	if req then
		local have = (g.Structures and g.Structures[req.StructureId]) or 0
		if have < req.Level then
			return string.format(
				"%s needs %s L%d (you have L%d)",
				name,
				STRUCTURE_LONG[req.StructureId] or req.StructureId,
				req.Level,
				have
			)
		end
	end
	local needP = def.RequiresPrestige
	if typeof(needP) == "number" and needP > 0 and (g.Prestige or 0) < needP then
		return string.format("%s needs Prestige %d (you have %d)", name, needP, g.Prestige or 0)
	end
	local flag = def.RequiresRebirthFlag
	if typeof(flag) == "string" and flag ~= "" and not (g.Rebirth and g.Rebirth[flag] == true) then
		return string.format("%s needs the %s rebirth unlock (you have not unlocked it yet)", name, flag)
	end
	return nil
end

function VehicleController._RowState(id: string, def: VehicleDef, ctx: RowCtx): RowState
	if ctx.ActiveId == id then
		return { Kind = "Despawn", Text = "DESPAWN", Enabled = true }
	end
	local owned = if typeof(ctx.Owned) == "table" then ctx.Owned[id] == true else ctx.Owned == true
	if owned then
		local cd = ctx.Cooldown or 0
		if cd > 0 then
			return { Kind = "Cooldown", Text = string.format("%ds", math.max(1, math.floor(cd + 0.5))), Enabled = false }
		end
		return { Kind = "Spawn", Text = "SPAWN", Enabled = true }
	end
	local reason = VehicleController._LockReason(def, ctx.Gates)
	if reason then
		return { Kind = "Locked", Text = "LOCKED\n" .. reason, Enabled = false, Reason = reason }
	end
	local price = def.CostCash or 0
	if price <= 0 then
		return { Kind = "Claim", Text = "CLAIM", Enabled = true }
	end
	local text = "BUY $" .. commas(price)
	local cash = ctx.Cash
	if cash ~= nil and cash < price then
		return { Kind = "CantAfford", Text = text, Enabled = false, Need = price - cash }
	end
	return { Kind = "Buy", Text = text, Enabled = true }
end

--[[ Each source overwrites only the fields it carries. Structures / Rebirth are full maps. ]]
function VehicleController._MergeGates(g: Gates, patch: any): Gates
	if typeof(patch) ~= "table" then
		return g
	end
	local lvl = tonumber(patch.Level)
	if lvl then
		g.Level = lvl
	end
	local pres = tonumber(patch.Prestige)
	if pres then
		g.Prestige = pres
	end
	if typeof(patch.Structures) == "table" then
		local s: { [string]: number } = {}
		for k, v in pairs(patch.Structures) do
			local n = tonumber(v)
			if typeof(k) == "string" and n then
				s[k] = n
			end
		end
		g.Structures = s
	end
	if typeof(patch.Rebirth) == "table" then
		local r: { [string]: boolean } = {}
		for k, v in pairs(patch.Rebirth) do
			if typeof(k) == "string" and v == true then
				r[k] = true
			end
		end
		g.Rebirth = r
	end
	return g
end

local function ownedSig(map: { [string]: boolean }): string
	local ids = {}
	for id, v in pairs(map) do
		if v == true then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

local function gatesSig(g: Gates): string
	local s: { [string]: number } = g.Structures or {}
	local flags = {}
	for k, v in pairs(g.Rebirth or {}) do
		if v == true then
			table.insert(flags, k)
		end
	end
	table.sort(flags)
	return string.format(
		"%d|%d|%d,%d,%d,%d|%s",
		g.Level or 0,
		g.Prestige or 0,
		s.VehicleDepot or 0,
		s.Helipad or 0,
		s.Airfield or 0,
		s.Dock or 0,
		table.concat(flags, ",")
	)
end

local function dataSig(): string
	return ownedSig(ownedMap) .. "#" .. tostring(activeId) .. "#" .. gatesSig(gates)
end

local function currentCtx(): RowCtx
	return {
		Owned = ownedMap,
		ActiveId = activeId,
		Cooldown = cooldownLeft,
		Gates = gates,
		Cash = tonumber(player:GetAttribute("WE_Cash")),
	}
end

local function sortedIds(): { string }
	local ctx = currentCtx()
	local ids = {}
	local rank: { [string]: number } = {}
	for id, def in pairs(VehicleConfig.Vehicles) do
		local cat = if def then (def.Category or "Ground") else "Ground"
		local rar = if def then (def.Rarity or "Common") else "Common"
		local catOk = filterCategory == "All" or cat == filterCategory
		local rarOk = filterRarity == "All" or rar == filterRarity
		local ownedOk = not filterOwnedOnly or ownedMap[id] == true
		if catOk and rarOk and ownedOk then
			table.insert(ids, id)
			rank[id] = KIND_RANK[VehicleController._RowState(id, def, ctx).Kind] or 5
		end
	end
	table.sort(ids, function(a, b)
		local ra, rb = rank[a], rank[b]
		if ra ~= rb then
			return ra < rb
		end
		local da = VehicleConfig.Vehicles[a]
		local db = VehicleConfig.Vehicles[b]
		local la = da and da.UnlockLevel or 0
		local lb = db and db.UnlockLevel or 0
		if la == lb then
			return a < b
		end
		return la < lb
	end)
	return ids
end

local function ownedCount(): number
	local n = 0
	for _, v in pairs(ownedMap) do
		if v == true then
			n += 1
		end
	end
	return n
end

local function catalogCount(): number
	local n = 0
	for _ in pairs(VehicleConfig.Vehicles) do
		n += 1
	end
	return n
end

local lastSpawnRequestAt = -math.huge
local SPAWN_CLIENT_DEBOUNCE = 0.85
local BUYING_SECONDS = 1.5

local function setStatus(text: string)
	if statusLabel then
		statusLabel.Text = text
	end
end

local function updateCooldownLabel()
	if cooldownLabel then
		cooldownLabel.Text = if cooldownLeft > 0
			then string.format("Spawn cooldown: %ds", math.max(1, math.floor(cooldownLeft + 0.5)))
			else "Spawn ready"
	end
end

local function bindTap(btn: GuiButton, fn: () -> ())
	btn.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		fn()
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Painting (in place — never creates instances)
-- ─────────────────────────────────────────────────────────────────────────────
local DARK_TEXT = Color3.fromRGB(20, 22, 18)

local function paintButton(btn: TextButton, id: string, st: RowState)
	local kind = st.Kind
	local text = st.Text
	local enabled = st.Enabled
	local bg, fg = Constants.Colors.Gold, DARK_TEXT
	local textSize = PanelShell.Text(if isTouch then 14 else 13)
	local wrapped = false
	if kind == "Despawn" then
		bg, fg = Constants.Colors.Danger, Constants.Colors.Text
	elseif kind == "Spawn" then
		bg, fg = Constants.Colors.Accent, Constants.Colors.Text
	elseif kind == "Cooldown" then
		bg, fg = Constants.Colors.Gunmetal, Constants.Colors.Muted
	elseif kind == "Locked" then
		bg, fg = Constants.Colors.Gunmetal, Constants.Colors.Muted
		textSize = PanelShell.Text(12)
		wrapped = true
	elseif kind == "CantAfford" then
		bg, fg = Constants.Colors.Gunmetal, Constants.Colors.Gold
	end
	if (kind == "Buy" or kind == "Claim" or kind == "CantAfford") and (buyingUntil[id] or 0) > os.clock() then
		text = "BUYING…"
		enabled = false
		bg, fg = Constants.Colors.GunmetalLight, Constants.Colors.Gold
	end
	if btn.Text ~= text then
		btn.Text = text
	end
	btn.BackgroundColor3 = bg
	btn.TextColor3 = fg
	btn.TextSize = textSize
	btn.TextWrapped = wrapped
	btn.AutoButtonColor = enabled
	btn:SetAttribute("WE_Kind", kind)
	btn:SetAttribute("WE_Disabled", not enabled)
end

local function paintRow(id: string)
	local btn = rowButtons[id]
	local def = VehicleConfig.Vehicles[id]
	if btn and def and btn.Parent then
		paintButton(btn, id, VehicleController._RowState(id, def, currentCtx()))
	end
end

local function repaintAll()
	for id in pairs(rowButtons) do
		paintRow(id)
	end
	updateCooldownLabel()
end

local function repaintOwned()
	for id in pairs(spawnButtons) do
		paintRow(id)
	end
	updateCooldownLabel()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Actions
-- ─────────────────────────────────────────────────────────────────────────────
local function fireSpawn(vehicleId: string)
	local now = os.clock()
	if now - lastSpawnRequestAt < SPAWN_CLIENT_DEBOUNCE then
		setStatus("Spawn request cooling down…")
		return
	end
	if cooldownLeft > 0 then
		setStatus(string.format("Spawn ready in %ds", math.max(1, math.floor(cooldownLeft + 0.5))))
		return
	end
	lastSpawnRequestAt = now
	lastSpawnRequestedId = vehicleId
	local def = VehicleConfig.Vehicles[vehicleId]
	setStatus("Deploying " .. (if def then def.DisplayName else vehicleId) .. "…")
	task.spawn(function()
		if not Remotes.FireServer(Constants.RemoteNames.RequestSpawnVehicle, vehicleId) then
			setStatus("Garage offline — try again in a moment")
		end
	end)
end

local function firePurchase(id: string, def: VehicleDef)
	buyingUntil[id] = os.clock() + BUYING_SECONDS
	paintRow(id)
	setStatus("Buying " .. def.DisplayName .. "…")
	task.spawn(function()
		if not Remotes.FireServer(Constants.RemoteNames.RequestPurchaseVehicle, id) then
			setStatus("Garage offline — try again in a moment")
		end
	end)
	task.delay(BUYING_SECONDS + 0.05, function()
		paintRow(id)
	end)
end

local function onRowTap(id: string)
	local def = VehicleConfig.Vehicles[id]
	if not def then
		return
	end
	local st = VehicleController._RowState(id, def, currentCtx())
	local kind = st.Kind
	if kind == "Despawn" then
		setStatus("Despawning " .. def.DisplayName .. "…")
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestDespawnVehicle)
	elseif kind == "Cooldown" then
		setStatus(string.format("Spawn ready in %ds", math.max(1, math.floor(cooldownLeft + 0.5))))
	elseif kind == "Spawn" then
		fireSpawn(id)
	elseif kind == "Locked" then
		setStatus(VehicleController._LockDetail(def, gates) or (def.DisplayName .. " is locked"))
	elseif (buyingUntil[id] or 0) > os.clock() then
		setStatus("Buying " .. def.DisplayName .. "…")
	elseif kind == "CantAfford" then
		setStatus(string.format("Need $%s more for %s", commas(st.Need or 0), def.DisplayName))
	else
		firePurchase(id, def)
	end
end

-- Copy by device (mobile merge gate #7, CLAUDE.md §1): key names only while HudLayout.PrefersKeys() (PreferredInput
-- keyboard / gamepad); touch players read what their own controls do (stick, ▲ — VehicleDriveClient's touch hints).
local function rowTip(def: VehicleDef): string
	local cat = def.Category or "Ground"
	local keys = HudLayout.PrefersKeys()
	if cat == "Air" then
		if string.sub(def.KitFamily or "", 1, 4) == "Heli" then
			return if keys then "Deploys on your Helipad · SPACE/▲ climb" else "Deploys on your Helipad · ▲ climbs"
		end
		return if keys then "Deploys on your runway · hold W" else "Deploys on your runway · stick up to go"
	elseif cat == "Naval" then
		return if keys then "Deploys at your dock / the coast · WASD" else "Deploys at your dock / the coast"
	end
	return if keys then "Sit · WASD drive" else "Sit · drive with the stick"
end

-- garage chips carry whole words ("GROUND", "COMMON" — never "GRO" / "COMM"): width follows the text
local function chipWidthFor(text: string, size: number, minW: number): number
	local ok, v = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, Enum.Font.GothamBold, Vector2.new(1000, 100))
	end)
	-- never trust a short measurement (font fallbacks draw wider): at least ~0.62 em per character, plus padding
	local est = (utf8.len(text) or #text) * size * 0.62
	local w = if ok and typeof(v) == "Vector2" and v.X > 0 then math.max(v.X, est) else est
	return math.max(minW, math.ceil(w) + 18)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Full rebuild (open, filter change, owned / active / gates change)
-- ─────────────────────────────────────────────────────────────────────────────
local function rebuild()
	local list = listFrame
	if not list then
		return
	end
	lastBuiltSig = dataSig()
	table.clear(rowButtons)
	table.clear(spawnButtons)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name == "EmptyState") then
			child:Destroy()
		end
	end
	if not list:FindFirstChildOfClass("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, if isTouch then 8 else 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list
	end

	local ids = sortedIds()
	local ownedN = ownedCount()
	local catalogN = catalogCount()

	setStatus(
		string.format(
			"%d shown · %d owned · %d in catalog%s",
			#ids,
			ownedN,
			catalogN,
			if filterOwnedOnly then " · OWNED filter" else ""
		)
	)
	updateCooldownLabel()

	if catalogN == 0 then
		emptyState(list, "Garage empty — no vehicles configured yet.")
		return
	end

	if #ids == 0 then
		local msg = if filterOwnedOnly
			then "No owned rides yet — buy Vehicle Depot / unlock Field 4x4, or turn off OWNED."
			else "No vehicles match these filters — tap All / clear rarity."
		emptyState(list, msg)
		return
	end

	-- Friendly empty banner when nothing owned yet (full catalog still listed below)
	if ownedN == 0 and not filterOwnedOnly then
		emptyState(
			list,
			"Garage empty — buy Vehicle Depot / unlock Field 4x4 (gold BUY → SPAWN). Starter 4x4 syncs after join."
		)
	elseif ownedN > 0 and filterOwnedOnly == false then
		-- soft tip only when filters hide all owned
		local ownedVisible = 0
		for _, id in ipairs(ids) do
			if ownedMap[id] then
				ownedVisible += 1
			end
		end
		if ownedVisible == 0 then
			emptyState(list, "None of your rides match these filters — tap OWNED or All to find them.")
		end
	end

	-- v70: touch rows hold a 64 v action button (44.8 real px) and ≥ 16 v text (11.2 px) at the phone scale
	local titleSize = PanelShell.Text(if isTouch then 15 else 14)
	local chipTextSize = PanelShell.Text(9)
	local chipW = if isTouch then 64 else 60
	local chipHt = chipTextSize + 6
	local metaSize = PanelShell.Text(if isTouch then 12 else 11)
	local chipTop = 4 + titleSize + 6
	local metaTop = chipTop + chipHt + 4
	local metaH = if isTouch then metaSize * 2 + 6 else 26
	local rowH = math.max(if isTouch then 92 else 78, metaTop + metaH + 6)
	local btnW = if isTouch then 132 else 100
	local btnH = if isTouch then PanelShell.TouchMinV() else 44

	for i, id in ipairs(ids) do
		local def = VehicleConfig.Vehicles[id]
		if def then
			local row = Instance.new("Frame")
			row.Name = "Row_" .. id
			row.Size = UDim2.new(1, -8, 0, rowH)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.Parent = list
			addCorner(row, 8)

			local rarBar = Instance.new("Frame")
			rarBar.Size = UDim2.new(0, 4, 1, -8)
			rarBar.Position = UDim2.fromOffset(4, 4)
			rarBar.BorderSizePixel = 0
			rarBar.BackgroundColor3 = rarityColors[def.Rarity] or Constants.Colors.Muted
			rarBar.Parent = row
			addCorner(rarBar, 2)

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(14, 4)
			title.Size = UDim2.new(1, -(btnW + 28), 0, titleSize + 4)
			title.Font = Enum.Font.GothamBold
			title.TextSize = titleSize
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Constants.Colors.Text
			title.Text = def.DisplayName
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.Parent = row

			local cat = def.Category or "Ground"
			local catCol = if cat == "Air"
				then Constants.Colors.CategoryAir
				elseif cat == "Naval" then Constants.Colors.CategoryNaval
				else Constants.Colors.CategoryGround
			local chipY = chipTop
			local function makeChip(label: string, color: Color3, x: number): number
				local w = chipWidthFor(label, chipTextSize, chipW)
				local chip = Instance.new("Frame")
				chip.Size = UDim2.fromOffset(w, chipHt)
				chip.Position = UDim2.fromOffset(x, chipY)
				chip.BackgroundColor3 = color
				chip.BorderSizePixel = 0
				chip.Parent = row
				addCorner(chip, 4)
				local lab = Instance.new("TextLabel")
				lab.BackgroundTransparency = 1
				lab.Size = UDim2.fromScale(1, 1)
				lab.Font = Enum.Font.GothamBold
				lab.TextSize = chipTextSize
				lab.TextColor3 = Color3.fromRGB(12, 14, 16)
				lab.Text = label
				lab.Parent = chip
				return x + w + 4
			end
			local nextX = makeChip(string.upper(cat), catCol, 14)
			nextX = makeChip(string.upper(def.Rarity or "Common"), rarityColors[def.Rarity] or Constants.Colors.Muted, nextX)
			-- v32: ArmedJeep lists with explicit DisplayName + ARMED chip (same WheeledLight drive as MilitaryJeep);
			-- JEEP-2: players see "Armed 4x4" (the id stays ArmedJeep)
			if id == "ArmedJeep" then
				title.Text = def.DisplayName or "Armed 4x4"
				makeChip("ARMED", Color3.fromRGB(180, 70, 55), nextX)
			end

			local meta = Instance.new("TextLabel")
			meta.BackgroundTransparency = 1
			meta.Position = UDim2.fromOffset(14, metaTop)
			meta.Size = UDim2.new(1, -(btnW + 28), 0, metaH)
			meta.Font = Enum.Font.GothamMedium
			meta.TextSize = metaSize
			meta.TextXAlignment = Enum.TextXAlignment.Left
			meta.TextYAlignment = Enum.TextYAlignment.Top
			meta.TextColor3 = Constants.Colors.Muted
			meta.TextWrapped = true
			local req = ""
			if def.RequiresStructure then
				req = string.format(
					" | %s L%d",
					STRUCTURE_SHORT[def.RequiresStructure.StructureId] or def.RequiresStructure.StructureId,
					def.RequiresStructure.Level
				)
			end
			if typeof(def.RequiresPrestige) == "number" and (def.RequiresPrestige :: number) > 0 then
				req ..= string.format(" | P%d+", def.RequiresPrestige :: number)
			end
			if typeof(def.RequiresRebirthFlag) == "string" and (def.RequiresRebirthFlag :: string) ~= "" then
				req ..= " | Rebirth"
			end
			meta.Text = string.format(
				"%s · Lv %d · $%s · Spd %d%s",
				rowTip(def),
				def.UnlockLevel,
				commas(def.CostCash or 0),
				def.Speed,
				req
			)
			meta.Parent = row

			local btn = Instance.new("TextButton")
			btn.Name = "Action"
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.new(1, -10, 0.5, 0)
			btn.Size = UDim2.fromOffset(btnW, btnH)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = PanelShell.Text(if isTouch then 14 else 13)
			btn.TextColor3 = Constants.Colors.Text
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = true
			-- stays Active so a tap on a locked / cooling row can explain itself (WE_Disabled marks "no action")
			btn.Active = true
			btn.Parent = row
			addCorner(btn, 8)
			UIUtil.EnsureMinTouch(btn, btnH)
			rowButtons[id] = btn
			if ownedMap[id] or activeId == id then
				spawnButtons[id] = btn
			end
			paintRow(id)
			bindTap(btn, function()
				onRowTap(id)
			end)
		end
	end
end

-- data changed (payloads / attributes): rebuild once, 0.25 s later, only if something that
-- changes the rows' order or kind changed; otherwise repaint in place
local function scheduleRebuild()
	if not isOpen or rebuildPending then
		return
	end
	rebuildPending = true
	task.delay(0.25, function()
		rebuildPending = false
		if isOpen and dataSig() ~= lastBuiltSig then
			rebuild()
		end
	end)
end

local function scheduleRepaint()
	if not isOpen or repaintPending then
		return
	end
	repaintPending = true
	task.delay(0.25, function()
		repaintPending = false
		if isOpen then
			repaintAll()
		end
	end)
end

local function refreshNewVehicleBadge()
	HudLayout.SetBadge("Garage", if next(newVehicleIds) ~= nil then "!" else nil)
end

-- a fresh owned map from the server: ids that were not owned before are "new" (after the join grace window)
local function noteOwned(owned: { [string]: boolean })
	local now = os.clock()
	local syncedAt = ownedSyncedAt
	if syncedAt == nil then
		ownedSyncedAt = now
		return
	end
	if now - syncedAt < NEW_VEHICLE_GRACE_SECONDS or isOpen then
		return
	end
	local changed = false
	for id in pairs(owned) do
		if not ownedMap[id] and id ~= activeId then
			newVehicleIds[id] = true
			changed = true
		end
	end
	if changed then
		refreshNewVehicleBadge()
	end
end

local function onDataChanged()
	if not isOpen then
		return
	end
	if dataSig() ~= lastBuiltSig then
		scheduleRebuild()
	else
		scheduleRepaint()
	end
end

local function setOpen(value: boolean)
	isOpen = value
	if screenGui then
		screenGui.Enabled = true
		local panel: GuiObject? = panelFrame
		if panel then
			panel.Visible = value
		end
	end
	local sh = shell
	if sh then
		sh.Sync(value)
	end
	if value then
		-- v70: opening the Garage clears the rail's "!" (HUDController also clears it on PanelChanged)
		table.clear(newVehicleIds)
		refreshNewVehicleBadge()
		rebuild()
		print("[WAR EMPIRE] Garage opened — owned=", ownedCount(), "active=", tostring(activeId))
	end
end

local function buildGui()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireGarage"
	screen.Enabled = true
	-- v70: DisplayOrder 60 (Panels) above the HUD rail (55); one HUD scale + safe area (HudLayout.ApplyScreen)
	PanelShell.Screen(screen)
	screen.Parent = player:WaitForChild("PlayerGui")
	screenGui = screen

	local TAP = PanelShell.TouchMinV()
	local panel = Instance.new("Frame")
	panel.Name = "GaragePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	-- Phone-friendly: scale with a max offset so it fits every landscape phone
	if isTouch then
		panel.Size = UDim2.new(0.94, 0, 1, -16)
	else
		panel.Size = UDim2.fromOffset(560, 580)
	end
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = screen
	panelFrame = panel
	-- panelFrame is canonical garage root for open/close
	addCorner(panel, 12)
	local gst = Instance.new("UIStroke")
	gst.Color = Constants.Colors.Gold
	gst.Thickness = 1.5
	gst.Transparency = 0.35
	gst.Parent = panel
	local sizeCon = Instance.new("UISizeConstraint")
	sizeCon.MaxSize = if isTouch then Vector2.new(880, 640) else Vector2.new(560, 640)
	sizeCon.MinSize = Vector2.new(280, 300)
	sizeCon.Parent = panel

	local title = PanelShell.Title(panel, "GARAGE")

	PanelShell.CloseButton(panel, function()
		pcall(AudioController.PlayClick)
		setOpen(false)
	end)

	local lineSize = PanelShell.Text(12)
	local lineY = title.Position.Y.Offset + title.Size.Y.Offset - 2
	local cd = Instance.new("TextLabel")
	cd.Name = "CooldownLine"
	cd.BackgroundTransparency = 1
	cd.Position = UDim2.fromOffset(16, lineY)
	cd.Size = UDim2.new(0.45, -16, 0, lineSize + 4)
	cd.Font = Enum.Font.GothamBold
	cd.TextSize = lineSize
	cd.TextXAlignment = Enum.TextXAlignment.Left
	cd.TextColor3 = Constants.Colors.Muted
	cd.Text = "Spawn ready"
	cd.Parent = panel
	cooldownLabel = cd

	local status = Instance.new("TextLabel")
	status.Name = "StatusLine"
	status.BackgroundTransparency = 1
	status.Position = if isTouch then UDim2.new(0.45, 0, 0, lineY) else UDim2.fromOffset(16, lineY + lineSize + 4)
	status.Size = if isTouch
		then UDim2.new(0.55, -(TAP + 20), 0, lineSize + 4)
		else UDim2.new(1, -(TAP + 28), 0, lineSize + 4)
	status.Font = Enum.Font.GothamMedium
	status.TextSize = lineSize
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Constants.Colors.Muted
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Text = ""
	status.Parent = panel
	statusLabel = status

	local filtersY = math.max(TAP + 8, status.Position.Y.Offset + lineSize + 10)
	-- touch: ONE row of 64 v chips (All / Ground / Air / Naval / Owned + a rarity chip that cycles);
	-- desktop keeps two compact rows
	local chipH = if isTouch then TAP else 28
	local filters = Instance.new("Frame")
	filters.Name = "Filters"
	filters.Position = UDim2.fromOffset(12, filtersY)
	filters.Size = UDim2.new(1, -24, 0, chipH)
	filters.BackgroundTransparency = 1
	filters.Parent = panel
	local layoutF = Instance.new("UIListLayout")
	layoutF.FillDirection = Enum.FillDirection.Horizontal
	layoutF.Padding = UDim.new(0, if isTouch then 6 else 5)
	layoutF.SortOrder = Enum.SortOrder.LayoutOrder
	layoutF.Parent = filters

	local rarList = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
	if typeof(VehicleConfig.Rarities) == "table" then
		rarList = { "All" }
		for _, r in ipairs(VehicleConfig.Rarities) do
			table.insert(rarList, r)
		end
	end
	local function rarityText(): string
		if filterRarity == "All" then
			return "ALL ★"
		end
		return string.upper(filterRarity)
	end

	local function paintCatFilters()
		for _, child in ipairs(filters:GetChildren()) do
			if child:IsA("TextButton") then
				local name = string.gsub(child.Name, "Filter_", "")
				if name == "Owned" then
					child.BackgroundColor3 = if filterOwnedOnly then Constants.Colors.Gold else Constants.Colors.Background
					child.TextColor3 = if filterOwnedOnly then Color3.fromRGB(20, 22, 18) else Constants.Colors.Text
				elseif name == "Rarity" then
					child.Text = rarityText()
					child.BackgroundColor3 = if filterRarity == "All"
						then Constants.Colors.Background
						else (rarityColors[filterRarity] or Constants.Colors.Accent)
					child.TextColor3 = if filterRarity == "All" then Constants.Colors.Text else Color3.fromRGB(20, 22, 18)
				else
					child.BackgroundColor3 = if name == filterCategory
						then Constants.Colors.Accent
						else Constants.Colors.Background
					child.TextColor3 = Constants.Colors.Text
				end
			end
		end
	end
	paintFilters = paintCatFilters
	local chipText = PanelShell.Text(if isTouch then 13 else 11)
	local function chip(name: string, text: string, w: number, order: number): TextButton
		local fb = Instance.new("TextButton")
		fb.Name = name
		fb.LayoutOrder = order
		fb.Size = UDim2.fromOffset(w, chipH)
		fb.Font = Enum.Font.GothamBold
		fb.TextSize = chipText
		fb.Text = text
		fb.TextColor3 = Constants.Colors.Text
		fb.BackgroundColor3 = Constants.Colors.Background
		fb.BorderSizePixel = 0
		fb.AutoButtonColor = true
		fb.Active = true
		addCorner(fb, 8)
		fb.Parent = filters
		UIUtil.EnsureMinTouch(fb, chipH)
		return fb
	end
	for i, cat in ipairs({ "All", "Ground", "Air", "Naval" }) do
		local fb = chip("Filter_" .. cat, cat:upper(), if isTouch then 100 else 70, i)
		bindTap(fb, function()
			filterCategory = cat
			paintCatFilters()
			rebuild()
		end)
	end
	-- OWNED toggle chip
	local ownedChip = chip("Filter_Owned", "OWNED", if isTouch then 100 else 72, 5)
	bindTap(ownedChip, function()
		filterOwnedOnly = not filterOwnedOnly
		paintCatFilters()
		rebuild()
	end)

	local rowsBelow = chipH + 8
	if isTouch then
		-- one chip cycles All → Common → … → Legendary (six 64 v chips would not fit next to the categories)
		local rc = chip("Filter_Rarity", rarityText(), 150, 6)
		bindTap(rc, function()
			local idx = table.find(rarList, filterRarity) or 1
			filterRarity = rarList[(idx % #rarList) + 1]
			paintCatFilters()
			rebuild()
		end)
	else
		local rarFilters = Instance.new("Frame")
		rarFilters.Name = "RarityFilters"
		rarFilters.Position = UDim2.fromOffset(12, filtersY + chipH + 6)
		rarFilters.Size = UDim2.new(1, -24, 0, 26)
		rarFilters.BackgroundTransparency = 1
		rarFilters.Parent = panel
		local layoutR = Instance.new("UIListLayout")
		layoutR.FillDirection = Enum.FillDirection.Horizontal
		layoutR.Padding = UDim.new(0, 4)
		layoutR.SortOrder = Enum.SortOrder.LayoutOrder
		layoutR.Parent = rarFilters
		local function paintRarity()
			for _, child in ipairs(rarFilters:GetChildren()) do
				if child:IsA("TextButton") then
					local name = string.gsub(child.Name, "Rarity_", "")
					child.BackgroundColor3 = if name == filterRarity
						then (rarityColors[name] or Constants.Colors.Accent)
						else Constants.Colors.Background
				end
			end
		end
		for i, rar in ipairs(rarList) do
			local rb = Instance.new("TextButton")
			rb.Name = "Rarity_" .. rar
			rb.LayoutOrder = i
			rb.Size = UDim2.fromOffset(if rar == "Legendary" then 78 else 64, 26)
			rb.Font = Enum.Font.GothamBold
			rb.TextSize = PanelShell.Text(10)
			rb.Text = if rar == "All" then "ALL ★" else string.upper(string.sub(rar, 1, 3))
			rb.TextColor3 = Constants.Colors.Text
			rb.BorderSizePixel = 0
			rb.AutoButtonColor = true
			rb.Active = true
			addCorner(rb, 5)
			rb.Parent = rarFilters
			bindTap(rb, function()
				filterRarity = rar
				paintRarity()
				rebuild()
			end)
		end
		paintRarity()
		rowsBelow += 26 + 8
	end
	paintCatFilters()

	local hintSize = PanelShell.Text(11)
	local listTop = filtersY + rowsBelow
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(12, listTop)
	scroll.Size = UDim2.new(1, -24, 1, -(listTop + hintSize + 20))
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.Always
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = if isTouch then 6 else 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = panel
	listFrame = scroll

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 16, 1, -8)
	hint.Size = UDim2.new(1, -32, 0, hintSize + 4)
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = hintSize
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Constants.Colors.Muted
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	-- copy by device: key names only for keyboard / gamepad players (HudLayout.PrefersKeys, not TouchEnabled)
	local function hintText(keys: boolean): string
		return if keys
			then "G · SPAWN deploys at your base · Heli SPACE/CTRL · Plane hold W · F exits aircraft"
			else "BUY → SPAWN · air + sea deploy at your base · ▲▼ fly · hold EXIT to leave"
	end
	hint.Text = hintText(HudLayout.PrefersKeys())
	hint.Parent = panel
	HudLayout.InputModeChanged:Connect(function(keys: boolean)
		hint.Text = hintText(keys)
		if isOpen then
			rebuild() -- the row tips name keys only for keyboard / gamepad players
		end
	end)

	-- v70: the desktop GARAGE toggle (bottom-left, over the thumbstick / cash pill) is gone — the Garage opens from
	-- the rail's Garage tile, G, the vehicle-pad prompt and the Vehicle Depot terminal.
	-- Bootstrap calls VehicleController.Init without a pcall: a registry / dim failure must never stop the garage
	local okShell, res = pcall(PanelShell.Attach, {
		Id = PANEL_ID,
		Screen = screen,
		Panel = panel,
		IsOpen = function(): boolean
			return isOpen
		end,
		Close = function()
			setOpen(false)
		end,
	})
	if okShell then
		shell = res
	else
		warn("[VehicleController] panel registry / dim failed:", res)
	end
end

--[[ tab: optional "Ground" | "Air" | "Naval" (terminal prompt attribute WE_OpenTab) presets the category. ]]
function VehicleController.Open(tab: string?)
	if tab == "Ground" or tab == "Air" or tab == "Naval" then
		filterCategory = tab
		local paint = paintFilters
		if paint then
			paint()
		end
	end
	setOpen(true)
end

function VehicleController.Close()
	setOpen(false)
end

function VehicleController.Toggle()
	-- the tap that just closed the Garage through its dim lands on the Garage tile too: stay closed
	local sh = shell
	if not isOpen and sh and sh.TapThrough() then
		return
	end
	setOpen(not isOpen)
end

function VehicleController.IsOpen(): boolean
	return isOpen
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Server data
-- ─────────────────────────────────────────────────────────────────────────────
local function readOwned(v: any): { [string]: boolean }?
	if typeof(v) ~= "table" then
		return nil
	end
	local out: { [string]: boolean } = {}
	for id, owned in pairs(v) do
		if typeof(id) == "string" and owned == true then
			out[id] = true
		end
	end
	return out
end

local function onVehicleState(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local owned = readOwned(payload.Owned)
	if owned then
		noteOwned(owned)
		ownedMap = owned
	end
	local act = payload.ActiveVehicleId
	activeId = if typeof(act) == "string" then act else nil
	-- a spawned vehicle is no longer "new"
	if activeId and newVehicleIds[activeId] then
		newVehicleIds[activeId] = nil
		refreshNewVehicleBadge()
	end
	cooldownLeft = math.max(0, tonumber(payload.CooldownRemaining) or 0)
	if payload.Gates ~= nil then
		VehicleController._MergeGates(gates, payload.Gates)
	end
	-- touch: close once the requested vehicle is out, so the player sees it
	if isTouch and isOpen and lastSpawnRequestedId ~= nil and activeId == lastSpawnRequestedId then
		lastSpawnRequestedId = nil
		setOpen(false)
		return
	end
	if isOpen then
		if dataSig() ~= lastBuiltSig then
			scheduleRebuild()
		else
			repaintAll()
		end
	end
end

local function onPlayerState(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local patch: { [string]: any } = { Level = payload.Level, Prestige = payload.Prestige }
	local base = payload.Base
	if typeof(base) == "table" and typeof(base.Upgrades) == "table" then
		patch.Structures = base.Upgrades
	end
	VehicleController._MergeGates(gates, patch)
	-- backup ownership refresh (the join merge can land after the first VehicleStateUpdate)
	local owned = readOwned(payload.Vehicles)
	if owned then
		noteOwned(owned)
		ownedMap = owned
	end
	onDataChanged()
end

local function onBaseState(payload: any)
	if typeof(payload) == "table" and typeof(payload.Upgrades) == "table" then
		VehicleController._MergeGates(gates, { Structures = payload.Upgrades })
		onDataChanged()
	end
end

local function onXP(payload: any)
	if typeof(payload) == "table" and tonumber(payload.Level) then
		VehicleController._MergeGates(gates, { Level = payload.Level })
		onDataChanged()
	end
end

local function readLevelAttribute()
	local lvl = tonumber(player:GetAttribute("WE_Level"))
	if lvl then
		VehicleController._MergeGates(gates, { Level = lvl })
		onDataChanged()
	end
end

function VehicleController.Init()
	-- the drive loop first: a garage UI failure must never stop vehicles from being drivable
	local okDrive, errDrive = pcall(function(): any
		VehicleDriveClient.Init()
		return nil
	end)
	if not okDrive then
		warn("[VehicleController] VehicleDriveClient.Init failed:", errDrive)
	end

	buildGui()

	Remotes.BindEvent(Constants.RemoteNames.VehicleStateUpdate, onVehicleState)
	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, onPlayerState)
	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, onBaseState)
	Remotes.BindEvent(Constants.RemoteNames.XPUpdate, onXP)
	player:GetAttributeChangedSignal("WE_Level"):Connect(readLevelAttribute)
	player:GetAttributeChangedSignal("WE_Cash"):Connect(scheduleRepaint)
	readLevelAttribute()

	local garageKey: Enum.KeyCode = HudConfig.Keys.Garage or Enum.KeyCode.G
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == garageKey then
			setOpen(not isOpen)
		end
	end)

	-- cooldown ticker: repaints the owned rows' buttons in place (no rebuild, no new instances)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if cooldownLeft > 0 then
				cooldownLeft = math.max(0, cooldownLeft - 0.5)
				if isOpen and listFrame then
					repaintOwned()
				end
			end
		end
	end)
end

return VehicleController
