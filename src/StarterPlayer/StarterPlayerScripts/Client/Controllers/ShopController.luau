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
local isTouch = UserInputService.TouchEnabled
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

	-- P1: on PvP death, server fires DeathShopOffer → open shop (prompt only if product Id ~= 0)
	do
		local remote = Remotes.GetEvent(Constants.RemoteNames.DeathShopOffer)
		if remote then
			remote.OnClientEvent:Connect(function(payload: any)
				ShopController.Open()
				local offers = if typeof(payload) == "table" then (payload :: any).Offers else nil
				if typeof(offers) ~= "table" then
					offers = (MonetizationConfig :: any).DeathShopOffers or { "DoubleCash", "SpeedBoost" }
				end
				for _, key in ipairs(offers :: { string }) do
					local def = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts[key]
					if def and typeof(def.Id) == "number" and def.Id ~= 0 then
						pcall(function()
							MarketplaceService:PromptProductPurchase(player, def.Id)
						end)
						break
					end
				end
			end)
		end
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireShop"
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	screen.DisplayOrder = 60 -- above HUD dock (55); panels must not open behind HUD
	screenGui = screen

	local toggle = Instance.new("TextButton")
	toggle.Name = "ShopToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 136, 1, -16)
	toggle.Size = UDim2.fromOffset(88, 44)
	toggle.BackgroundColor3 = Constants.Colors.Gunmetal
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = Constants.Colors.Gold
	toggle.Text = "SHOP"
	toggle.BorderSizePixel = 0
	toggle.Visible = false -- docked in HUD MobileActionBar
	corner(toggle, 8)
	local toggleStroke = Instance.new("UIStroke")
	toggleStroke.Color = Constants.Colors.Gold
	toggleStroke.Thickness = 1.5
	toggleStroke.Parent = toggle
	toggle.Parent = screen
	UIUtil.EnsureMinTouch(toggle, 44)
	toggle.Activated:Connect(function()
		setOpen(not menuOpen)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.92, 0, 0.72, 0) else UDim2.fromOffset(400, 360)
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
	close.Size = UDim2.fromOffset(48, 48)
	close.BackgroundColor3 = Constants.Colors.Background
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Constants.Colors.Text
	close.BorderSizePixel = 0
	corner(close, 6)
	close.Parent = panel
	UIUtil.EnsureMinTouch(close, 48)
	close.Activated:Connect(function()
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
	note.Text = "Prices shown in Robux. Id=0 items log intent only (no charge) until Creator Dashboard IDs are set."
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
	local function addRow(label: string, sub: string, onClick: () -> (), btnText: string?)
		order += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 56)
		row.BackgroundColor3 = Constants.Colors.Background
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = list
		corner(row, 6)

		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(10, 6)
		t.Size = UDim2.new(1, -110, 0, 20)
		t.Font = Enum.Font.GothamBold
		t.TextSize = 14
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = Constants.Colors.Text
		t.Text = label
		t.Parent = row

		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromOffset(10, 28)
		s.Size = UDim2.new(1, -110, 0, 16)
		s.Font = Enum.Font.Gotham
		s.TextSize = 11
		s.TextXAlignment = Enum.TextXAlignment.Left
		s.TextColor3 = Constants.Colors.Muted
		s.Text = sub
		s.Parent = row

		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, -8, 0.5, 0)
		btn.Size = UDim2.fromOffset(if isTouch then 110 else 96, 48)
		btn.BackgroundColor3 = Constants.Colors.Gunmetal
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 11
		btn.TextColor3 = Color3.fromRGB(255, 248, 230)
		btn.Text = btnText or "BUY"
		btn.BorderSizePixel = 0
		corner(btn, 6)
		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Constants.Colors.Gold
		btnStroke.Thickness = 1.25
		btnStroke.Parent = btn
		btn.Parent = row
		UIUtil.EnsureMinTouch(btn, 44)
		btn.Activated:Connect(onClick)
	end

	for key, def in pairs(MonetizationConfig.DevProducts) do
		local robux = tonumber(def.RobuxPrice) or 0
		local stub = (tonumber(def.Id) or 0) == 0
		local sub = def.Description or ""
		if def.GrantsBattlePassPremium then
			sub = "Unlocks Battle Pass Premium (ProcessReceipt only)"
		elseif def.GrantEntitlement then
			sub = (def.Description or ("Grants " .. tostring(def.GrantEntitlement))) 
		elseif def.Cash and def.Cash > 0 then
			sub = string.format("+$%d Cash", def.Cash)
		elseif def.Gold and def.Gold > 0 then
			sub = string.format("+%d Gold", def.Gold)
		end
		if stub then
			sub = sub .. " · coming soon (no charge)"
		end
		local btnLabel = if robux > 0 then (tostring(robux) .. " R$") else "BUY"
		addRow(def.DisplayName, sub, function()
			promptDevProduct(key)
		end, btnLabel)
	end

	for key, def in pairs(MonetizationConfig.GamePasses) do
		local stub = (tonumber(def.Id) or 0) == 0
		local robux = tonumber(def.RobuxPrice) or 0
		local sub = (def.Description or "") .. (if stub then " · coming soon (no charge)" else "")
		local btnLabel = if robux > 0 then (tostring(robux) .. " R$") else "PASS"
		addRow("Pass: " .. def.DisplayName, sub, function()
			promptGamePass(key)
		end, btnLabel)
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





function ShopController.Toggle()
	setOpen(not menuOpen)
end

function ShopController.Open()
	setOpen(true)
end

function ShopController.Close()
	setOpen(false)
end

function ShopController.IsOpen(): boolean
	return menuOpen
end

return ShopController
