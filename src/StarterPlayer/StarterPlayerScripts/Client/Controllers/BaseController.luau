--!strict
--[[ Upgrade menu UI → RequestPurchaseUpgrade remote ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local BaseController = {}

local player = Players.LocalPlayer
local upgrades: { [string]: number } = {}
local cash = 0
local menuOpen = false
local screenGui: ScreenGui? = nil
local listFrame: ScrollingFrame? = nil
local toggleBtn: TextButton? = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function refreshList()
	if not listFrame then
		return
	end
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local layout = listFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 6)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = listFrame
	end

	for order, structureId in ipairs(BaseConfig.StructureOrder) do
		local def = BaseConfig.Structures[structureId]
		if def then
			local level = upgrades[structureId] or 0
			local nextLevel = level + 1
			local cost = if nextLevel <= def.MaxLevel then def.Costs[nextLevel] else nil

			local row = Instance.new("Frame")
			row.Name = structureId
			row.Size = UDim2.new(1, -8, 0, 56)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = order
			row.Parent = listFrame
			corner(row, 6)

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(8, 4)
			title.Size = UDim2.new(1, -100, 0, 22)
			title.Font = Enum.Font.GothamBold
			title.TextSize = 14
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Constants.Colors.Text
			title.Text = string.format("%s  Lv%d/%d", def.DisplayName, level, def.MaxLevel)
			title.Parent = row

			local desc = Instance.new("TextLabel")
			desc.BackgroundTransparency = 1
			desc.Position = UDim2.fromOffset(8, 28)
			desc.Size = UDim2.new(1, -100, 0, 20)
			desc.Font = Enum.Font.Gotham
			desc.TextSize = 11
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextColor3 = Constants.Colors.Muted
			desc.Text = def.Description
			desc.TextTruncate = Enum.TextTruncate.AtEnd
			desc.Parent = row

			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.new(1, -8, 0.5, 0)
			btn.Size = UDim2.fromOffset(88, 36)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 12
			btn.TextColor3 = Constants.Colors.Text
			btn.AutoButtonColor = true
			btn.BorderSizePixel = 0
			corner(btn, 6)

			if not cost then
				btn.Text = "MAX"
				btn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
				btn.Active = false
			else
				btn.Text = "$" .. tostring(cost)
				local canAfford = cash >= cost
				btn.BackgroundColor3 = if canAfford then Constants.Colors.Accent else Color3.fromRGB(70, 50, 50)
				btn.MouseButton1Click:Connect(function()
					Remotes.GetEvent(Constants.RemoteNames.RequestPurchaseUpgrade):FireServer({
						StructureId = structureId,
					} :: Types.PurchaseUpgradeRequest)
				end)
			end
			btn.Parent = row
		end
	end

	local l = listFrame:FindFirstChildOfClass("UIListLayout")
	if l then
		listFrame.CanvasSize = UDim2.fromOffset(0, l.AbsoluteContentSize.Y + 12)
	end
end

local function setOpen(open: boolean)
	menuOpen = open
	if screenGui then
		local panel = screenGui:FindFirstChild("UpgradePanel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = open
		end
	end
	if toggleBtn then
		toggleBtn.Text = if open then "Close Base" else "Base Upgrades"
	end
	if open then
		refreshList()
	end
end

function BaseController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarEmpireBaseUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	screenGui = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = gui

	local btn = Instance.new("TextButton")
	btn.Name = "ToggleUpgrades"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -24)
	btn.Size = UDim2.fromOffset(160, 40)
	btn.BackgroundColor3 = Constants.Colors.Panel
	btn.TextColor3 = Constants.Colors.Text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.Text = "Base Upgrades"
	btn.BorderSizePixel = 0
	corner(btn, 8)
	btn.Parent = gui
	toggleBtn = btn
	btn.MouseButton1Click:Connect(function()
		setOpen(not menuOpen)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "UpgradePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.48)
	panel.Size = UDim2.fromOffset(420, 420)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 10)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -28, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextColor3 = Constants.Colors.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "BASE UPGRADES"
	title.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(10, 48)
	scroll.Size = UDim2.new(1, -20, 1, -58)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = panel
	listFrame = scroll

	Remotes.GetEvent(Constants.RemoteNames.BaseStateUpdate).OnClientEvent:Connect(function(base: Types.BaseStatePayload)
		upgrades = base.Upgrades or upgrades
		if menuOpen then
			refreshList()
		end
	end)

	Remotes.GetEvent(Constants.RemoteNames.EconomyUpdate).OnClientEvent:Connect(function(payload: Types.EconomyUpdatePayload)
		cash = payload.Cash
		if menuOpen then
			refreshList()
		end
	end)

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: Types.PlayerStatePayload)
		cash = state.Cash
		if state.Base then
			upgrades = state.Base.Upgrades
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			setOpen(not menuOpen)
		end
	end)
end

return BaseController
