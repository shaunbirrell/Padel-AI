--!strict
--[[
	Phase 4/7 — Garage UI (G). Spawn / buy / despawn requests only.
	Category + rarity filters for large roster (~50+). ScrollingFrame AutomaticCanvasSize.
	Empty states via UIUtil.EmptyState. MobileScale via UIUtil.PrepareScreen.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local Types = require(Shared.Types)
local VehicleConfig = require(Shared.Configs.VehicleConfig)

local AudioController = require(script.Parent.Parent.Modules.AudioController)

local VehicleController = {}

local player = Players.LocalPlayer

local screenGui: ScreenGui? = nil
local listFrame: ScrollingFrame? = nil
local cooldownLabel: TextLabel? = nil
local isOpen = false

local ownedMap: { [string]: boolean } = {}
local activeId: string? = nil
local cooldownLeft = 0
local filterCategory: string = "All" -- All | Ground | Air | Naval
local filterRarity: string = "All" -- All | Common | Uncommon | Rare | Epic | Legendary
local rarityColors: { [string]: Color3 } = {
	Common = Color3.fromRGB(160, 165, 170),
	Uncommon = Color3.fromRGB(90, 180, 110),
	Rare = Color3.fromRGB(80, 140, 220),
	Epic = Color3.fromRGB(170, 90, 220),
	Legendary = Color3.fromRGB(230, 170, 60),
}

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

local function sortedIds(): { string }
	local ids = {}
	for id, def in pairs(VehicleConfig.Vehicles) do
		local cat = if def then (def.Category or "Ground") else "Ground"
		local rar = if def then (def.Rarity or "Common") else "Common"
		local catOk = filterCategory == "All" or cat == filterCategory
		local rarOk = filterRarity == "All" or rar == filterRarity
		if catOk and rarOk then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
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
	for _ in pairs(ownedMap) do
		n += 1
	end
	return n
end

local function refresh()
	if not listFrame then
		return
	end
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name == "EmptyState") then
			child:Destroy()
		end
	end
	if not listFrame:FindFirstChildOfClass("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = listFrame
	end

	local ids = sortedIds()
	if #ids == 0 then
		UIUtil.EmptyState(listFrame, "Garage empty — no vehicles configured yet.", 0)
		if cooldownLabel then
			cooldownLabel.Text = if cooldownLeft > 0
				then string.format("Spawn cooldown: %.0fs", cooldownLeft)
				else "Spawn ready"
		end
		return
	end

	-- Friendly empty banner when nothing owned / nothing to spawn yet
	if ownedCount() == 0 then
		UIUtil.EmptyState(
			listFrame,
			"No owned vehicles yet — BUY a ride below, then SPAWN. Starter Jeep appears after join sync.",
			0
		)
	end

	for i, id in ipairs(ids) do
		local def = VehicleConfig.Vehicles[id]
		if def then
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 78)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.Parent = listFrame
			addCorner(row, 6)

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
			title.Size = UDim2.new(1, -124, 0, 18)
			title.Font = Enum.Font.GothamBold
			title.TextSize = 14
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Constants.Colors.Text
			title.Text = def.DisplayName
			title.Parent = row

			-- Category + rarity color chips (visual kits v2)
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
			makeChip(string.upper(string.sub(def.Rarity or "Common", 1, 4)), rarityColors[def.Rarity] or Constants.Colors.Muted, nextX)

			local meta = Instance.new("TextLabel")
			meta.BackgroundTransparency = 1
			meta.Position = UDim2.fromOffset(14, 42)
			meta.Size = UDim2.new(1, -124, 0, 26)
			meta.Font = Enum.Font.Gotham
			meta.TextSize = 11
			meta.TextXAlignment = Enum.TextXAlignment.Left
			meta.TextYAlignment = Enum.TextYAlignment.Top
			meta.TextColor3 = Constants.Colors.Muted
			meta.TextWrapped = true
			local req = ""
			if def.RequiresStructure then
				req = string.format(
					" | %s L%d",
					def.RequiresStructure.StructureId,
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
				"Lv %d · $%s · Spd %d%s",
				def.UnlockLevel,
				tostring(def.CostCash),
				def.Speed,
				req
			)
			meta.Parent = row

			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.new(1, -10, 0.5, 0)
			btn.Size = UDim2.fromOffset(100, 44)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 13
			btn.TextColor3 = Constants.Colors.Text
			btn.BorderSizePixel = 0
			btn.Parent = row
			addCorner(btn, 6)

			if activeId == id then
				btn.Text = "DESPAWN"
				btn.BackgroundColor3 = Constants.Colors.Danger
				btn.MouseButton1Click:Connect(function()
					AudioController.PlayClick()
					Remotes.GetEvent(Constants.RemoteNames.RequestDespawnVehicle):FireServer()
				end)
			elseif ownedMap[id] then
				btn.Text = if cooldownLeft > 0 then string.format("%.0fs", cooldownLeft) else "SPAWN"
				btn.BackgroundColor3 = Constants.Colors.Accent
				btn.MouseButton1Click:Connect(function()
					AudioController.PlayClick()
					Remotes.GetEvent(Constants.RemoteNames.RequestSpawnVehicle):FireServer(id)
				end)
			else
				local price = def.CostCash or 0
				btn.Text = if price <= 0 then "CLAIM" else ("BUY $" .. tostring(price))
				btn.BackgroundColor3 = Constants.Colors.Gold
				btn.TextColor3 = Color3.fromRGB(20, 22, 18)
				btn.MouseButton1Click:Connect(function()
					AudioController.PlayClick()
					Remotes.GetEvent(Constants.RemoteNames.RequestPurchaseVehicle):FireServer(id)
				end)
			end
		end
	end

	if cooldownLabel then
		cooldownLabel.Text = if cooldownLeft > 0
			then string.format("Spawn cooldown: %.0fs", cooldownLeft)
			else "Spawn ready"
	end
end

local function setOpen(value: boolean)
	isOpen = value
	if screenGui then
		screenGui.Enabled = true -- keep ScreenGui alive so GARAGE CTA stays clickable
		local panel = screenGui:FindFirstChild("GaragePanel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = value
		end
	end
	if value then
		refresh()
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
	panel.Size = UDim2.fromOffset(540, 560)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	addCorner(panel, 10)
	local gst = Instance.new("UIStroke")
	gst.Color = Constants.Colors.Gold
	gst.Thickness = 1.5
	gst.Transparency = 0.35
	gst.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -100, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "GARAGE"
	title.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -12, 0, 12)
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Constants.Colors.Text
	closeBtn.BackgroundColor3 = Constants.Colors.Background
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel
	addCorner(closeBtn, 6)
	closeBtn.MouseButton1Click:Connect(function()
		AudioController.PlayClick()
		setOpen(false)
	end)

	local cd = Instance.new("TextLabel")
	cd.BackgroundTransparency = 1
	cd.Position = UDim2.fromOffset(16, 44)
	cd.Size = UDim2.new(1, -32, 0, 18)
	cd.Font = Enum.Font.Gotham
	cd.TextSize = 12
	cd.TextXAlignment = Enum.TextXAlignment.Left
	cd.TextColor3 = Constants.Colors.Muted
	cd.Text = "Spawn ready"
	cd.Parent = panel
	cooldownLabel = cd

	local filters = Instance.new("Frame")
	filters.Name = "Filters"
	filters.Position = UDim2.fromOffset(12, 66)
	filters.Size = UDim2.new(1, -24, 0, 30)
	filters.BackgroundTransparency = 1
	filters.Parent = panel
	local layoutF = Instance.new("UIListLayout")
	layoutF.FillDirection = Enum.FillDirection.Horizontal
	layoutF.Padding = UDim.new(0, 5)
	layoutF.Parent = filters
	for _, cat in ipairs({ "All", "Ground", "Air", "Naval" }) do
		local fb = Instance.new("TextButton")
		fb.Name = "Filter_" .. cat
		fb.Size = UDim2.fromOffset(78, 28)
		fb.Font = Enum.Font.GothamBold
		fb.TextSize = 11
		fb.Text = cat:upper()
		fb.TextColor3 = Constants.Colors.Text
		fb.BorderSizePixel = 0
		fb.BackgroundColor3 = if filterCategory == cat then Constants.Colors.Accent else Constants.Colors.Background
		addCorner(fb, 6)
		fb.Parent = filters
		fb.MouseButton1Click:Connect(function()
			AudioController.PlayClick()
			filterCategory = cat
			for _, child in ipairs(filters:GetChildren()) do
				if child:IsA("TextButton") then
					local name = string.gsub(child.Name, "Filter_", "")
					child.BackgroundColor3 = if name == filterCategory then Constants.Colors.Accent else Constants.Colors.Background
				end
			end
			refresh()
		end)
	end

	local rarFilters = Instance.new("Frame")
	rarFilters.Name = "RarityFilters"
	rarFilters.Position = UDim2.fromOffset(12, 98)
	rarFilters.Size = UDim2.new(1, -24, 0, 26)
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
	for _, rar in ipairs(rarList) do
		local rb = Instance.new("TextButton")
		rb.Name = "Rarity_" .. rar
		rb.Size = UDim2.fromOffset(if rar == "Legendary" then 78 else 68, 24)
		rb.Font = Enum.Font.GothamBold
		rb.TextSize = 10
		rb.Text = if rar == "All" then "ALL ★" else string.upper(string.sub(rar, 1, 3))
		rb.TextColor3 = Constants.Colors.Text
		rb.BorderSizePixel = 0
		rb.BackgroundColor3 = if filterRarity == rar then (rarityColors[rar] or Constants.Colors.Accent) else Constants.Colors.Background
		addCorner(rb, 5)
		rb.Parent = rarFilters
		rb.MouseButton1Click:Connect(function()
			AudioController.PlayClick()
			filterRarity = rar
			for _, child in ipairs(rarFilters:GetChildren()) do
				if child:IsA("TextButton") then
					local name = string.gsub(child.Name, "Rarity_", "")
					child.BackgroundColor3 = if name == filterRarity
						then (rarityColors[name] or Constants.Colors.Accent)
						else Constants.Colors.Background
				end
			end
			refresh()
		end)
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(12, 130)
	scroll.Size = UDim2.new(1, -24, 1, -170)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.Always
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = panel
	listFrame = scroll

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 16, 1, -12)
	hint.Size = UDim2.new(1, -32, 0, 18)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Constants.Colors.Muted
	hint.Text = "G · Cat + Rarity filters · scroll · E on pad · DriverSeat"
	hint.Parent = panel

	local garageBtn = Instance.new("TextButton")
	garageBtn.Name = "GarageToggle"
	garageBtn.AnchorPoint = Vector2.new(0, 1)
	-- Bottom-left, above currency pill / clear of right dock
	garageBtn.Position = UDim2.new(0, 16, 1, -88)
	garageBtn.Size = UDim2.fromOffset(110, 44)
	garageBtn.BackgroundColor3 = Constants.Colors.Gunmetal
	garageBtn.Text = "GARAGE"
	garageBtn.Font = Enum.Font.GothamBold
	garageBtn.TextSize = 14
	garageBtn.TextColor3 = Constants.Colors.Gold
	garageBtn.BorderSizePixel = 0
	garageBtn.Active = true
	garageBtn.ZIndex = 25
	garageBtn.Parent = screen
	addCorner(garageBtn, 8)
	addStroke(garageBtn, Constants.Colors.Gold, 1.5)
	garageBtn.Activated:Connect(function()
		AudioController.PlayClick()
		print("[WAR EMPIRE] Garage CTA toggled →", not isOpen)
		setOpen(not isOpen)
	end)
end

function VehicleController.Open()
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

function VehicleController.Init()
	buildGui()

	Remotes.GetEvent(Constants.RemoteNames.VehicleStateUpdate).OnClientEvent:Connect(
		function(payload: Types.VehicleStatePayload)
			ownedMap = payload.Owned or {}
			activeId = payload.ActiveVehicleId
			cooldownLeft = payload.CooldownRemaining or 0
			if isOpen then
				refresh()
			end
		end
	)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			setOpen(not isOpen)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			if cooldownLeft > 0 then
				local prev = cooldownLeft
				cooldownLeft = math.max(0, cooldownLeft - 0.5)
				if isOpen and listFrame then
					-- Soft update: avoid full list rebuild every tick on large roster
					if cooldownLabel then
						cooldownLabel.Text = if cooldownLeft > 0
							then string.format("Spawn cooldown: %.0fs", cooldownLeft)
							else "Spawn ready"
					end
					if cooldownLeft == 0 or math.floor(prev) ~= math.floor(cooldownLeft) then
						-- Rebuild when crossing whole seconds or hitting ready (button labels)
						refresh()
					end
				end
			end
		end
	end)
end

return VehicleController
