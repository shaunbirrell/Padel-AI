--!strict
--[[ Army panel — recruit/dismiss soldiers (key A / ARMY button). Server-authoritative. ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local ArmyController = {}

local player = Players.LocalPlayer
local open = false
local screenGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local armyState: any = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function refreshLabels()
	if not statusLabel then
		return
	end
	if typeof(armyState) ~= "table" then
		statusLabel.Text = "Loading army..."
		return
	end
	statusLabel.Text = string.format(
		"Soldiers: %d / %d\nBarracks Lv %d\nRecruit: $%d each (batch %d)",
		tonumber(armyState.Soldiers) or 0,
		tonumber(armyState.MaxSoldiers) or 0,
		tonumber(armyState.BarracksLevel) or 0,
		tonumber(armyState.RecruitCostCash) or 500,
		tonumber(armyState.RecruitBatchSize) or 1
	)
end

local function setOpen(isOpen: boolean)
	open = isOpen
	if screenGui then
		local panel = screenGui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = isOpen
		end
	end
end

function ArmyController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireArmy"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.IgnoreGuiInset = true
	screen.Parent = player:WaitForChild("PlayerGui")
	screenGui = screen

	local scale = Instance.new("UIScale")
	scale.Name = "MobileScale"
	scale.Parent = screen
	local function updateScale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local size = cam.ViewportSize
		scale.Scale = math.clamp(math.min(size.X, size.Y) / 900, 0.65, 1.1)
	end
	updateScale()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		updateScale()
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
	end)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	local inset = GuiService:GetGuiInset()
	local toggle = Instance.new("TextButton")
	toggle.Name = "ArmyToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 16, 1, -16 - inset.Y)
	toggle.Size = UDim2.fromOffset(88, 36)
	toggle.BackgroundColor3 = Constants.Colors.Panel
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 13
	toggle.TextColor3 = Constants.Colors.Text
	toggle.Text = "ARMY"
	toggle.BorderSizePixel = 0
	corner(toggle, 8)
	toggle.Parent = screen
	toggle.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(360, 280)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	corner(panel, 10)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "Army"
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(32, 28)
	close.BackgroundColor3 = Constants.Colors.Background
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Constants.Colors.Text
	close.BorderSizePixel = 0
	corner(close, 6)
	close.Parent = panel
	close.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(16, 48)
	statusLabel.Size = UDim2.new(1, -32, 0, 80)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 14
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.TextColor3 = Constants.Colors.Muted
	statusLabel.Text = "..."
	statusLabel.Parent = panel

	local function makeBtn(label: string, x: number, y: number, cb: () -> ())
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, y)
		b.Size = UDim2.fromOffset(150, 36)
		b.BackgroundColor3 = Constants.Colors.Accent
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.TextColor3 = Constants.Colors.Text
		b.Text = label
		b.BorderSizePixel = 0
		corner(b, 6)
		b.Parent = panel
		b.MouseButton1Click:Connect(cb)
	end

	makeBtn("RECRUIT x1", 16, 140, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestRecruitSoldiers):FireServer(1)
	end)
	makeBtn("RECRUIT x5", 180, 140, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestRecruitSoldiers):FireServer(5)
	end)
	makeBtn("DISMISS x1", 16, 188, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestDismissSoldiers):FireServer(1)
	end)
	makeBtn("DISMISS x5", 180, 188, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestDismissSoldiers):FireServer(5)
	end)

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Position = UDim2.fromOffset(16, 236)
	note.Size = UDim2.new(1, -32, 0, 32)
	note.Font = Enum.Font.Gotham
	note.TextSize = 11
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = Constants.Colors.Muted
	note.Text = "Server validates cash + barracks cap. Key A toggles."
	note.Parent = panel

	Remotes.GetEvent(Constants.RemoteNames.SoldierStateUpdate).OnClientEvent:Connect(function(payload)
		armyState = payload
		refreshLabels()
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.A then
			setOpen(not open)
		end
	end)
end

return ArmyController
