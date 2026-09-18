--!strict
--[[ Phase 7 — Shop UI. Prompts Marketplace; grants only via server ProcessReceipt / GamePass ownership. ]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)

local ShopController = {}

local player = Players.LocalPlayer
local menuOpen = false
local screenGui: ScreenGui? = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function setOpen(open: boolean)
	menuOpen = open
	if screenGui then
		local panel = screenGui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = open
		end
	end
end

local function promptDevProduct(productKey: string)
	local def = MonetizationConfig.DevProducts[productKey]
	if not def then
		return
	end
	-- Ask server to log + validate; client still prompts Marketplace
	Remotes.GetEvent(Constants.RemoteNames.RequestPurchaseDevProduct):FireServer(productKey)
	if def.Id and def.Id ~= 0 then
		MarketplaceService:PromptProductPurchase(player, def.Id)
	else
		warn("[Shop] Product ID placeholder for", productKey, "— set MonetizationConfig DevProduct Ids")
	end
end

local function promptGamePass(passKey: string)
	local def = MonetizationConfig.GamePasses[passKey]
	if not def then
		return
	end
	-- Log intent on server; NEVER treat client confirmation as a grant
	Remotes.GetEvent(Constants.RemoteNames.RequestPurchaseGamePass):FireServer(passKey)
	if def.Id and def.Id ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, def.Id)
	else
		warn("[Shop] GamePass ID placeholder for", passKey, "— set MonetizationConfig GamePass Ids")
	end
end

function ShopController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireShop"
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	screenGui = screen

	local toggle = Instance.new("TextButton")
	toggle.Name = "ShopToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 136, 1, -16)
	toggle.Size = UDim2.fromOffset(80, 36)
	toggle.BackgroundColor3 = Constants.Colors.Panel
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = Constants.Colors.Gold
	toggle.Text = "SHOP"
	toggle.BorderSizePixel = 0
	corner(toggle, 8)
	toggle.Parent = screen
	toggle.MouseButton1Click:Connect(function()
		setOpen(not menuOpen)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(400, 360)
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
	title.Text = "Supply Depot"
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

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Position = UDim2.fromOffset(16, 40)
	note.Size = UDim2.new(1, -32, 0, 32)
	note.Font = Enum.Font.Gotham
	note.TextSize = 11
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = Constants.Colors.Muted
	note.Text = "IDs are placeholders (0). Server ProcessReceipt / GamePass ownership grants only — never client."
	note.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 80)
	list.Size = UDim2.new(1, -24, 1, -92)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local order = 0
	local function addRow(label: string, sub: string, onClick: () -> ())
		order += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 52)
		row.BackgroundColor3 = Constants.Colors.Background
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = list
		corner(row, 6)

		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(10, 6)
		t.Size = UDim2.new(1, -100, 0, 20)
		t.Font = Enum.Font.GothamBold
		t.TextSize = 14
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = Constants.Colors.Text
		t.Text = label
		t.Parent = row

		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromOffset(10, 28)
		s.Size = UDim2.new(1, -100, 0, 16)
		s.Font = Enum.Font.Gotham
		s.TextSize = 11
		s.TextXAlignment = Enum.TextXAlignment.Left
		s.TextColor3 = Constants.Colors.Muted
		s.Text = sub
		s.Parent = row

		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, -8, 0.5, 0)
		btn.Size = UDim2.fromOffset(72, 32)
		btn.BackgroundColor3 = Constants.Colors.Accent
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.TextColor3 = Constants.Colors.Text
		btn.Text = "BUY"
		btn.BorderSizePixel = 0
		corner(btn, 6)
		btn.Parent = row
		btn.MouseButton1Click:Connect(onClick)
	end

	for key, def in pairs(MonetizationConfig.DevProducts) do
		local sub = ""
		if def.GrantsBattlePassPremium then
			sub = string.format("Unlocks BP Premium track (id=%d) — grant via ProcessReceipt only", def.Id or 0)
		elseif def.Cash and def.Cash > 0 then
			sub = string.format("$%d  (id=%d)", def.Cash, def.Id or 0)
		elseif def.Gold and def.Gold > 0 then
			sub = string.format("%d Gold  (id=%d)", def.Gold, def.Id or 0)
		else
			sub = string.format("id=%d", def.Id or 0)
		end
		addRow(def.DisplayName, sub, function()
			promptDevProduct(key)
		end)
	end

	for key, def in pairs(MonetizationConfig.GamePasses) do
		addRow(
			"Pass: " .. def.DisplayName,
			(def.Description or "") .. string.format(" (id=%d)", def.Id or 0),
			function()
				promptGamePass(key)
			end
		)
	end

	

	-- Policy-pending loot crates (display only — no purchase/grant path)
	do
		local ok, LootBoxConfig = pcall(function()
			return require(Shared.Configs.LootBoxConfig)
		end)
		if ok and LootBoxConfig and LootBoxConfig.PolicyPending then
			addRow("Supply Crate (locked)", "Random loot policy-pending — not for sale", function()
				warn("[Shop] Loot boxes disabled (policy-pending)")
			end)
		end
	end

	if order == 0 then
		UIUtil.EmptyState(list, "Shop catalog empty — MonetizationConfig has no DevProducts / GamePasses.", 0)
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			setOpen(not menuOpen)
		end
	end)
end

return ShopController
