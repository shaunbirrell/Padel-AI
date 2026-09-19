--!strict
--[[
	Phase 4 — Garage UI (G). Spawn / buy / despawn requests only.
	Empty states via UIUtil.EmptyState when catalog/owned list is empty.
	MobileScale via UIUtil.PrepareScreen (same as Army/Shop).
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

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(55, 65, 55)
	s.Thickness = 1
	s.Parent = parent
end

local function sortedIds(): { string }
	local ids = {}
	for id in pairs(VehicleConfig.Vehicles) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local da = VehicleConfig.Vehicles[a]
		local db = VehicleConfig.Vehicles[b]
		return (da and da.UnlockLevel or 0) < (db and db.UnlockLevel or 0)
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
			row.Size = UDim2.new(1, -8, 0, 72)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.Parent = listFrame
			addCorner(row, 6)

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(10, 6)
			title.Size = UDim2.new(1, -120, 0, 20)
			title.Font = Enum.Font.GothamBold
			title.TextSize = 14
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Constants.Colors.Text
			title.Text = def.DisplayName
			title.Parent = row

			local meta = Instance.new("TextLabel")
			meta.BackgroundTransparency = 1
			meta.Position = UDim2.fromOffset(10, 28)
			meta.Size = UDim2.new(1, -120, 0, 36)
			meta.Font = Enum.Font.Gotham
			meta.TextSize = 12
			meta.TextXAlignment = Enum.TextXAlignment.Left
			meta.TextYAlignment = Enum.TextYAlignment.Top
			meta.TextColor3 = Constants.Colors.Muted
			meta.TextWrapped = true
			local req = ""
			if def.RequiresStructure then
				req = string.format(
					" | Needs %s L%d",
					def.RequiresStructure.StructureId,
					def.RequiresStructure.Level
				)
			end
			meta.Text = string.format(
				"%s · Lv %d · $%s · Spd %d%s",
				def.Rarity,
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
		screenGui.Enabled = value
	end
	if value then
		refresh()
	end
end

local function buildGui()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireGarage"
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	screenGui = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(460, 420)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
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

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(12, 70)
	scroll.Size = UDim2.new(1, -24, 1, -110)
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
	hint.Text = "G / GARAGE · E on pad · Sit DriverSeat to drive"
	hint.Parent = panel

	local garageBtn = Instance.new("TextButton")
	garageBtn.AnchorPoint = Vector2.new(0, 1)
	garageBtn.Position = UDim2.new(0, 16, 1, -20)
	garageBtn.Size = UDim2.fromOffset(110, 44)
	garageBtn.BackgroundColor3 = Constants.Colors.Accent
	garageBtn.Text = "GARAGE"
	garageBtn.Font = Enum.Font.GothamBold
	garageBtn.TextSize = 14
	garageBtn.TextColor3 = Constants.Colors.Text
	garageBtn.BorderSizePixel = 0
	garageBtn.Parent = screen
	addCorner(garageBtn, 8)
	addStroke(garageBtn)
	garageBtn.MouseButton1Click:Connect(function()
		AudioController.PlayClick()
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
				cooldownLeft = math.max(0, cooldownLeft - 0.5)
				if isOpen then
					refresh()
				end
			end
		end
	end)
end

return VehicleController
