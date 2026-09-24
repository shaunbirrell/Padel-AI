--!strict
--[[
	Phase 4/7 — Garage UI (G). Spawn / buy / despawn requests only.
	Category + rarity + Owned filters for large roster (~99). ScrollingFrame AutomaticCanvasSize.
	Empty states via UIUtil.EmptyState. MobileScale via UIUtil.PrepareScreen.
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
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local VehicleConfig = require(Shared.Configs.VehicleConfig)

local AudioController = require(script.Parent.Parent.Modules.AudioController)
local VehicleDriveClient = require(script.Parent.Parent.Modules.VehicleDriveClient)

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

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled

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

local function addStroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(55, 65, 55)
	s.Thickness = thickness or 1
	s.Parent = parent
	return s
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
	local textSize = if isTouch then 14 else 13
	local wrapped = false
	if kind == "Despawn" then
		bg, fg = Constants.Colors.Danger, Constants.Colors.Text
	elseif kind == "Spawn" then
		bg, fg = Constants.Colors.Accent, Constants.Colors.Text
	elseif kind == "Cooldown" then
		bg, fg = Constants.Colors.Gunmetal, Constants.Colors.Muted
	elseif kind == "Locked" then
		bg, fg = Constants.Colors.Gunmetal, Constants.Colors.Muted
		textSize = 12
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

local function rowTip(def: VehicleDef): string
	local cat = def.Category or "Ground"
	if cat == "Air" then
		if string.sub(def.KitFamily or "", 1, 4) == "Heli" then
			return "Deploys on your Helipad · SPACE/▲ climb"
		end
		return "Deploys on your runway · hold W"
	elseif cat == "Naval" then
		return "Deploys at your dock / the coast · WASD"
	end
	return "Sit · WASD drive"
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
		UIUtil.EmptyState(list, "Garage empty — no vehicles configured yet.", 0)
		return
	end

	if #ids == 0 then
		local msg = if filterOwnedOnly
			then "No owned rides yet — buy Vehicle Depot / unlock Military Jeep, or turn off OWNED."
			else "No vehicles match these filters — tap All / clear rarity."
		UIUtil.EmptyState(list, msg, 0)
		return
	end

	-- Friendly empty banner when nothing owned yet (full catalog still listed below)
	if ownedN == 0 and not filterOwnedOnly then
		UIUtil.EmptyState(
			list,
			"Garage empty — buy Vehicle Depot / unlock Military Jeep (gold BUY → SPAWN). Starter Jeep syncs after join.",
			0
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
			UIUtil.EmptyState(list, "None of your rides match these filters — tap OWNED or All to find them.", 0)
		end
	end

	local rowH = if isTouch then 92 else 78
	local btnW = if isTouch then 118 else 100
	local btnH = if isTouch then 52 else 44

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
			title.Size = UDim2.new(1, -(btnW + 28), 0, 18)
			title.Font = Enum.Font.GothamBold
			title.TextSize = if isTouch then 15 else 14
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
			local chipY = 24
			local function makeChip(label: string, color: Color3, x: number): number
				local chip = Instance.new("Frame")
				chip.Size = UDim2.fromOffset(58, 16)
				chip.Position = UDim2.fromOffset(x, chipY)
				chip.BackgroundColor3 = color
				chip.BorderSizePixel = 0
				chip.Parent = row
				addCorner(chip, 4)
				local lab = Instance.new("TextLabel")
				lab.BackgroundTransparency = 1
				lab.Size = UDim2.fromScale(1, 1)
				lab.Font = Enum.Font.GothamBold
				lab.TextSize = 9
				lab.TextColor3 = Color3.fromRGB(12, 14, 16)
				lab.Text = label
				lab.Parent = chip
				return x + 62
			end
			local nextX = makeChip(string.upper(string.sub(cat, 1, 3)), catCol, 14)
			nextX = makeChip(
				string.upper(string.sub(def.Rarity or "Common", 1, 4)),
				rarityColors[def.Rarity] or Constants.Colors.Muted,
				nextX
			)
			-- v32: ArmedJeep lists with explicit DisplayName + ARMED chip (same WheeledLight drive as MilitaryJeep)
			if id == "ArmedJeep" then
				title.Text = def.DisplayName or "Armed Jeep"
				makeChip("ARMED", Color3.fromRGB(180, 70, 55), nextX)
			end

			local meta = Instance.new("TextLabel")
			meta.BackgroundTransparency = 1
			meta.Position = UDim2.fromOffset(14, if isTouch then 46 else 42)
			meta.Size = UDim2.new(1, -(btnW + 28), 0, if isTouch then 36 else 26)
			meta.Font = Enum.Font.Gotham
			meta.TextSize = if isTouch then 12 else 11
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
			btn.TextSize = if isTouch then 14 else 13
			btn.TextColor3 = Constants.Colors.Text
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = true
			-- stays Active so a tap on a locked / cooling row can explain itself (WE_Disabled marks "no action")
			btn.Active = true
			btn.Parent = row
			addCorner(btn, 8)
			UIUtil.EnsureMinTouch(btn, if isTouch then 48 else 44)
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
		screenGui.Enabled = true -- keep ScreenGui alive so GARAGE CTA stays clickable
		local panel: GuiObject? = panelFrame
		if panel then
			panel.Visible = value
		end
	end
	if value then
		rebuild()
		print("[WAR EMPIRE] Garage opened — owned=", ownedCount(), "active=", tostring(activeId))
	end
end

local function buildGui()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireGarage"
	screen.Enabled = true
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	screen.DisplayOrder = 60 -- above HUD dock (55); panels must not open behind HUD
	screenGui = screen

	local panel = Instance.new("Frame")
	panel.Name = "GaragePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	-- Phone-friendly: use scale with max offset so it fits portrait
	if isTouch then
		panel.Size = UDim2.new(0.94, 0, 0.82, 0)
	else
		panel.Size = UDim2.fromOffset(540, 560)
	end
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	panelFrame = panel
	-- panelFrame is canonical garage root for open/close
	addCorner(panel, 10)
	local gst = Instance.new("UIStroke")
	gst.Color = Constants.Colors.Gold
	gst.Thickness = 1.5
	gst.Transparency = 0.35
	gst.Parent = panel
	local sizeCon = Instance.new("UISizeConstraint")
	sizeCon.MaxSize = Vector2.new(560, 640)
	sizeCon.MinSize = Vector2.new(280, 360)
	sizeCon.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -100, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = if isTouch then 20 else 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "GARAGE"
	title.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -12, 0, 12)
	closeBtn.Size = UDim2.fromOffset(if isTouch then 48 else 44, if isTouch then 48 else 44)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Constants.Colors.Text
	closeBtn.BackgroundColor3 = Constants.Colors.Background
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel
	addCorner(closeBtn, 6)
	UIUtil.EnsureMinTouch(closeBtn, 44)
	bindTap(closeBtn, function()
		setOpen(false)
	end)

	local cd = Instance.new("TextLabel")
	cd.Name = "CooldownLine"
	cd.BackgroundTransparency = 1
	cd.Position = UDim2.fromOffset(16, 44)
	cd.Size = UDim2.new(1, -32, 0, 16)
	cd.Font = Enum.Font.Gotham
	cd.TextSize = 12
	cd.TextXAlignment = Enum.TextXAlignment.Left
	cd.TextColor3 = Constants.Colors.Muted
	cd.Text = "Spawn ready"
	cd.Parent = panel
	cooldownLabel = cd

	local status = Instance.new("TextLabel")
	status.Name = "StatusLine"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(16, 60)
	status.Size = UDim2.new(1, -32, 0, 14)
	status.Font = Enum.Font.Gotham
	status.TextSize = 11
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Constants.Colors.Muted
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Text = ""
	status.Parent = panel
	statusLabel = status

	local chipH = if isTouch then 36 else 28
	local filters = Instance.new("Frame")
	filters.Name = "Filters"
	filters.Position = UDim2.fromOffset(12, 78)
	filters.Size = UDim2.new(1, -24, 0, chipH)
	filters.BackgroundTransparency = 1
	filters.Parent = panel
	local layoutF = Instance.new("UIListLayout")
	layoutF.FillDirection = Enum.FillDirection.Horizontal
	layoutF.Padding = UDim.new(0, 5)
	layoutF.Parent = filters
	local function paintCatFilters()
		for _, child in ipairs(filters:GetChildren()) do
			if child:IsA("TextButton") then
				local name = string.gsub(child.Name, "Filter_", "")
				if name == "Owned" then
					child.BackgroundColor3 = if filterOwnedOnly then Constants.Colors.Gold else Constants.Colors.Background
					child.TextColor3 = if filterOwnedOnly then Color3.fromRGB(20, 22, 18) else Constants.Colors.Text
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
	for _, cat in ipairs({ "All", "Ground", "Air", "Naval" }) do
		local fb = Instance.new("TextButton")
		fb.Name = "Filter_" .. cat
		fb.Size = UDim2.fromOffset(if isTouch then 72 else 70, chipH - 2)
		fb.Font = Enum.Font.GothamBold
		fb.TextSize = if isTouch then 12 else 11
		fb.Text = cat:upper()
		fb.TextColor3 = Constants.Colors.Text
		fb.BorderSizePixel = 0
		fb.AutoButtonColor = true
		addCorner(fb, 6)
		fb.Parent = filters
		UIUtil.EnsureMinTouch(fb, if isTouch then 36 else 28)
		bindTap(fb, function()
			filterCategory = cat
			paintCatFilters()
			rebuild()
		end)
	end
	-- OWNED toggle chip
	local ownedChip = Instance.new("TextButton")
	ownedChip.Name = "Filter_Owned"
	ownedChip.Size = UDim2.fromOffset(if isTouch then 78 else 72, chipH - 2)
	ownedChip.Font = Enum.Font.GothamBold
	ownedChip.TextSize = if isTouch then 12 else 11
	ownedChip.Text = "OWNED"
	ownedChip.TextColor3 = Constants.Colors.Text
	ownedChip.BorderSizePixel = 0
	ownedChip.AutoButtonColor = true
	ownedChip.BackgroundColor3 = Constants.Colors.Background
	addCorner(ownedChip, 6)
	ownedChip.Parent = filters
	UIUtil.EnsureMinTouch(ownedChip, if isTouch then 36 else 28)
	bindTap(ownedChip, function()
		filterOwnedOnly = not filterOwnedOnly
		paintCatFilters()
		rebuild()
	end)
	paintCatFilters()

	local rarFilters = Instance.new("Frame")
	rarFilters.Name = "RarityFilters"
	rarFilters.Position = UDim2.fromOffset(12, 78 + chipH + 6)
	rarFilters.Size = UDim2.new(1, -24, 0, if isTouch then 32 else 26)
	rarFilters.BackgroundTransparency = 1
	rarFilters.Parent = panel
	local layoutR = Instance.new("UIListLayout")
	layoutR.FillDirection = Enum.FillDirection.Horizontal
	layoutR.Padding = UDim.new(0, 4)
	layoutR.Parent = rarFilters
	local rarList = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
	if typeof(VehicleConfig.Rarities) == "table" then
		rarList = { "All" }
		for _, r in ipairs(VehicleConfig.Rarities) do
			table.insert(rarList, r)
		end
	end
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
	for _, rar in ipairs(rarList) do
		local rb = Instance.new("TextButton")
		rb.Name = "Rarity_" .. rar
		rb.Size =
			UDim2.fromOffset(if rar == "Legendary" then 78 else (if isTouch then 64 else 60), if isTouch then 30 else 24)
		rb.Font = Enum.Font.GothamBold
		rb.TextSize = if isTouch then 11 else 10
		rb.Text = if rar == "All" then "ALL ★" else string.upper(string.sub(rar, 1, 3))
		rb.TextColor3 = Constants.Colors.Text
		rb.BorderSizePixel = 0
		rb.AutoButtonColor = true
		addCorner(rb, 5)
		rb.Parent = rarFilters
		UIUtil.EnsureMinTouch(rb, if isTouch then 30 else 24)
		bindTap(rb, function()
			filterRarity = rar
			paintRarity()
			rebuild()
		end)
	end
	paintRarity()

	local listTop = 78 + chipH + 6 + (if isTouch then 36 else 30) + 8
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(12, listTop)
	scroll.Size = UDim2.new(1, -24, 1, -(listTop + 36))
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
	hint.Position = UDim2.new(0, 16, 1, -10)
	hint.Size = UDim2.new(1, -32, 0, 18)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = if isTouch then 11 else 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Constants.Colors.Muted
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.Text = if isTouch
		then "BUY → SPAWN · air + sea deploy at your base · ▲▼ fly · Jump exits"
		else "G · SPAWN deploys at your base · Heli SPACE/CTRL · Plane hold W · F exits aircraft"
	hint.Parent = panel

	local garageBtn = Instance.new("TextButton")
	garageBtn.Name = "GarageToggle"
	garageBtn.AnchorPoint = Vector2.new(0, 1)
	-- Bottom-left, above currency pill / clear of right dock
	garageBtn.Position = UDim2.new(0, 16, 1, -88)
	garageBtn.Size = UDim2.fromOffset(if isTouch then 120 else 110, if isTouch then 48 else 44)
	garageBtn.BackgroundColor3 = Constants.Colors.Gunmetal
	garageBtn.Text = "GARAGE"
	garageBtn.Font = Enum.Font.GothamBold
	garageBtn.TextSize = 14
	garageBtn.TextColor3 = Constants.Colors.Gold
	garageBtn.BorderSizePixel = 0
	garageBtn.Active = true
	garageBtn.ZIndex = 25
	garageBtn.Visible = not isTouch -- touch uses HUD dock GARAGE tile
	garageBtn.Parent = screen
	addCorner(garageBtn, 8)
	addStroke(garageBtn, Constants.Colors.Gold, 1.5)
	UIUtil.EnsureMinTouch(garageBtn, 44)
	garageBtn.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		print("[WAR EMPIRE] Garage CTA toggled →", not isOpen)
		setOpen(not isOpen)
	end)
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
		ownedMap = owned
	end
	local act = payload.ActiveVehicleId
	activeId = if typeof(act) == "string" then act else nil
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

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
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
