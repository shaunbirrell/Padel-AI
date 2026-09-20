--!strict
--[[ Phase 7 — Shop UI. Prompts Marketplace; grants only via server ProcessReceipt / GamePass ownership. ]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
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
local pendingCashMegaHighlight = false
local shopListFrame: ScrollingFrame? = nil
local screenGui: ScreenGui? = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function highlightCashMegaRow()
	local list = shopListFrame
	if not list then
		return
	end
	local row = list:FindFirstChild("ShopRow_CashMega")
	if not row or not row:IsA("GuiObject") then
		return
	end
	row.BackgroundColor3 = Color3.fromRGB(90, 70, 30)
	local stroke = row:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = row
	end
	stroke.Color = Constants.Colors.Gold
	stroke.Thickness = 2.5
	-- Scroll to top (CashMega is first)
	if list:IsA("ScrollingFrame") then
		list.CanvasPosition = Vector2.new(0, 0)
	end
	task.delay(4, function()
		if row.Parent then
			row.BackgroundColor3 = Constants.Colors.Background
			if stroke and stroke.Parent then
				stroke.Thickness = 0
			end
		end
	end)
end

local function setOpen(open: boolean)
	menuOpen = open
	if screenGui then
		local panel = screenGui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = open
		end
	end
	-- v35: optional CashMega highlight when shop opens from death continuity
	if open and pendingCashMegaHighlight then
		pendingCashMegaHighlight = false
		task.defer(highlightCashMegaRow)
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

	-- v30: PvP death → mobile-friendly toast (DoubleCash GP + SpeedBoost DP). Debounced; no auto-spam Marketplace.
	do
		local lastDeathToastAt = 0
		local DEATH_TOAST_DEBOUNCE = 10
		local deathToast: Frame? = nil

		local function resolveOfferPrompt(key: string): (string?, string?, number?, string?)
			-- Prefer live GamePass, then live DevProduct (DoubleCash is GP; SpeedBoost is DP)
			local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses[key]
			if gp and typeof(gp.Id) == "number" and gp.Id ~= 0 then
				return "GamePass", key, gp.Id, gp.DisplayName or key
			end
			local dp = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts[key]
			if dp and typeof(dp.Id) == "number" and dp.Id ~= 0 and dp.HideFromShop ~= true then
				return "DevProduct", key, dp.Id, dp.DisplayName or key
			end
			-- SpeedBoost / other: allow DevProduct even if HideFromShop when explicitly offered
			if dp and typeof(dp.Id) == "number" and dp.Id ~= 0 then
				return "DevProduct", key, dp.Id, dp.DisplayName or key
			end
			return nil, nil, nil, nil
		end

		local function destroyDeathToast()
			if deathToast then
				deathToast:Destroy()
				deathToast = nil
			end
		end

		local function showDeathOfferToast(offerKeys: { string })
			local now = os.clock()
			if now - lastDeathToastAt < DEATH_TOAST_DEBOUNCE then
				return
			end
			lastDeathToastAt = now
			destroyDeathToast()

			local live: { { Kind: string, Key: string, Id: number, Name: string } } = {}
			for _, key in ipairs(offerKeys) do
				local kind, k, id, name = resolveOfferPrompt(key)
				if kind and k and id and name then
					table.insert(live, { Kind = kind, Key = k, Id = id, Name = name })
				end
			end
			if #live == 0 then
				return
			end

			local host = screenGui
			if not host then
				local pg = player:FindFirstChild("PlayerGui")
				local existing = pg and pg:FindFirstChild("WarEmpireShop")
				if existing and existing:IsA("ScreenGui") then
					host = existing
					screenGui = existing
				else
					return
				end
			end
			local toast = Instance.new("Frame")
			toast.Name = "DeathShopToast"
			toast.AnchorPoint = Vector2.new(0.5, 0)
			toast.Position = UDim2.new(0.5, 0, 0, if isTouch then 72 else 56)
			toast.Size = if isTouch then UDim2.new(0.94, 0, 0, 132) else UDim2.fromOffset(360, 120)
			toast.BackgroundColor3 = Constants.Colors.Panel
			toast.BorderSizePixel = 0
			toast.ZIndex = 80
			corner(toast, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Constants.Colors.Gold
			stroke.Thickness = 1.5
			stroke.Parent = toast
			toast.Parent = host
			deathToast = toast
			pendingCashMegaHighlight = true -- v35: CashMega highlight if shop opens

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(12, 8)
			title.Size = UDim2.new(1, -56, 0, 22)
			title.Font = Enum.Font.GothamBold
			title.TextSize = if isTouch then 16 else 15
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Constants.Colors.Gold
			title.Text = "Boost after death?"
			title.ZIndex = 81
			title.Parent = toast

			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1
			sub.Position = UDim2.fromOffset(12, 30)
			sub.Size = UDim2.new(1, -24, 0, 18)
			sub.Font = Enum.Font.Gotham
			sub.TextSize = 11
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextColor3 = Constants.Colors.Muted
			sub.Text = "Tap a Robux offer — grants via ProcessReceipt / GamePass only"
			sub.ZIndex = 81
			sub.Parent = toast

			local dismiss = Instance.new("TextButton")
			dismiss.AnchorPoint = Vector2.new(1, 0)
			dismiss.Position = UDim2.new(1, -8, 0, 6)
			dismiss.Size = UDim2.fromOffset(36, 36)
			dismiss.BackgroundColor3 = Constants.Colors.Background
			dismiss.Font = Enum.Font.GothamBold
			dismiss.Text = "X"
			dismiss.TextColor3 = Constants.Colors.Text
			dismiss.BorderSizePixel = 0
			dismiss.ZIndex = 82
			corner(dismiss, 6)
			dismiss.Parent = toast
			UIUtil.EnsureMinTouch(dismiss, 44)
			dismiss.Activated:Connect(destroyDeathToast)

			local rowY = 56
			local btnH = if isTouch then 48 else 40
			-- Equal-split buttons via scale (no fixed btnW)
			for i, offer in ipairs(live) do
				local btn = Instance.new("TextButton")
				btn.Name = "DeathOffer_" .. offer.Key
				btn.Position = UDim2.new((i - 1) / #live, 8, 0, rowY)
				btn.Size = UDim2.new(1 / #live, -12, 0, btnH)
				btn.BackgroundColor3 = Constants.Colors.Gunmetal
				btn.Font = Enum.Font.GothamBold
				btn.TextSize = if isTouch then 13 else 12
				btn.TextColor3 = Constants.Colors.Gold
				btn.Text = offer.Name
				btn.TextWrapped = true
				btn.BorderSizePixel = 0
				btn.ZIndex = 82
				corner(btn, 8)
				local bs = Instance.new("UIStroke")
				bs.Color = Constants.Colors.Gold
				bs.Thickness = 1.25
				bs.Parent = btn
				btn.Parent = toast
				UIUtil.EnsureMinTouch(btn, if isTouch then 48 else 44)
				local kind, key = offer.Kind, offer.Key
				btn.Activated:Connect(function()
					destroyDeathToast()
					if kind == "GamePass" then
						promptGamePass(key)
					else
						promptDevProduct(key)
				end
				end)
			end

			-- v35: optional open shop → CashMega highlight continuity
			do
				local shopBtn = Instance.new("TextButton")
				shopBtn.Name = "DeathOffer_OpenShop"
				shopBtn.Position = UDim2.fromOffset(12, rowY + btnH + 6)
				shopBtn.Size = UDim2.new(1, -24, 0, if isTouch then 36 else 28)
				shopBtn.BackgroundColor3 = Constants.Colors.Background
				shopBtn.Font = Enum.Font.GothamBold
				shopBtn.TextSize = 12
				shopBtn.TextColor3 = Constants.Colors.Gold
				shopBtn.Text = "Open Shop · Cash Mega"
				shopBtn.BorderSizePixel = 0
				shopBtn.ZIndex = 82
				corner(shopBtn, 6)
				shopBtn.Parent = toast
				-- Grow toast a bit for the extra row
				toast.Size = if isTouch then UDim2.new(0.94, 0, 0, 168) else UDim2.fromOffset(360, 156)
				UIUtil.EnsureMinTouch(shopBtn, 44)
				shopBtn.Activated:Connect(function()
					destroyDeathToast()
					pendingCashMegaHighlight = true
					setOpen(true)
				end)
			end

			task.delay(12, function()
				if deathToast == toast then
					destroyDeathToast()
				end
			end)
		end

		local remote = Remotes.GetEvent(Constants.RemoteNames.DeathShopOffer)
		if remote then
			remote.OnClientEvent:Connect(function(payload: any)
				local offers = if typeof(payload) == "table" then (payload :: any).Offers else nil
				if typeof(offers) ~= "table" then
					offers = (MonetizationConfig :: any).DeathShopOffers or { "DoubleCash", "SpeedBoost" }
				end
				-- Wait for screenGui (Init continues below); defer one frame if needed
				task.defer(function()
					if not screenGui then
						task.wait(0.15)
					end
					showDeathOfferToast(offers :: { string })
				end)
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
	note.Text = "Prices in Robux. Live products charge on confirm. Passes persist after Rebirth."
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
	shopListFrame = list

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local order = 0
	local function addRow(label: string, sub: string, onClick: () -> (), btnText: string?, rowKey: string?)
		order += 1
		local row = Instance.new("Frame")
		row.Name = if rowKey then ("ShopRow_" .. rowKey) else ("ShopRow_" .. tostring(order))
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

	local function addDevRow(key: string, def: any, heroLabel: string?)
		if def.HideFromShop == true then
			return
		end
		-- Id=0 stubs (AutoCollect/DoubleCash/VIPBoost/GoldenPumpjack) stay out of Shop — GamePasses / pads cover them
		if (tonumber(def.Id) or 0) == 0 then
			return
		end
		local robux = tonumber(def.RobuxPrice) or 0
		local stub = false -- kept for "coming soon" path if ever re-enabled
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
		local title = def.DisplayName
		if heroLabel then
			title = heroLabel .. " · " .. title
			sub = "BEST OFFER — " .. sub
		end
		local btnLabel = if robux > 0 then (tostring(robux) .. " R$") else "BUY"
		addRow(title, sub, function()
			promptDevProduct(key)
		end, btnLabel, key)
	end

	-- Hero CashMega first, then remaining cash packs, then other DevProducts
	local cashOrder = { "CashMega", "CashLarge", "CashMedium", "CashSmall" }
	local listed: { [string]: boolean } = {}
	do
		local mega = MonetizationConfig.DevProducts.CashMega
		if mega then
			addDevRow("CashMega", mega, "★ BEST OFFER")
			listed.CashMega = true
		end
	end
	for _, key in ipairs(cashOrder) do
		if not listed[key] then
			local def = MonetizationConfig.DevProducts[key]
			if def then
				addDevRow(key, def, nil)
				listed[key] = true
			end
		end
	end
	for key, def in pairs(MonetizationConfig.DevProducts) do
		if not listed[key] then
			addDevRow(key, def, nil)
		end
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



	-- v31: VIP / AutoCollect / other GamePass pads → OWNED (hide R$ prompt look)
	do
		local ownedCache: { [string]: boolean } = {}
		local function queryOwnsGamePass(key: string): boolean
			if ownedCache[key] ~= nil then
				return ownedCache[key] == true
			end
			local def = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses[key]
			local id = def and tonumber(def.Id) or 0
			if id == 0 then
				ownedCache[key] = false
				return false
			end
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			ownedCache[key] = ok and owns == true
			return ownedCache[key] == true
		end

		local function applyOwnedVisual(part: BasePart, owned: boolean)
			local bb = part:FindFirstChild("WE_PremiumBillboard")
			if not bb then
				bb = part:FindFirstChildWhichIsA("BillboardGui")
			end
			if bb and bb:IsA("BillboardGui") then
				local label = bb:FindFirstChildWhichIsA("TextLabel", true)
				if owned then
					if label and label:IsA("TextLabel") then
						label.Text = "OWNED"
						label.TextColor3 = Color3.fromRGB(180, 255, 160)
					end
					part.LocalTransparencyModifier = 0.45
					part:SetAttribute("WE_LocalOwned", true)
				else
					part.LocalTransparencyModifier = 0
					part:SetAttribute("WE_LocalOwned", false)
				end
			elseif owned then
				part.LocalTransparencyModifier = 0.45
				part:SetAttribute("WE_LocalOwned", true)
			end
		end

		local function refreshPremiumOwned()
			local tag = (Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"
			for _, inst in ipairs(CollectionService:GetTagged(tag)) do
				if inst:IsA("BasePart") then
					local kind = inst:GetAttribute("OfferKind")
					local key = inst:GetAttribute("OfferKey")
					if kind == "GamePass" and typeof(key) == "string" then
						applyOwnedVisual(inst, queryOwnsGamePass(key))
					end
				end
			end
		end

		task.spawn(function()
			task.wait(1.5)
			refreshPremiumOwned()
		end)
		task.spawn(function()
			while true do
				task.wait(20)
				-- Re-query occasionally (purchase mid-session)
				table.clear(ownedCache)
				refreshPremiumOwned()
			end
		end)
		CollectionService:GetInstanceAddedSignal((Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"):Connect(function(inst)
			if inst:IsA("BasePart") then
				task.defer(refreshPremiumOwned)
			end
		end)
	end


	-- v32: one-shot StarterBundle soft offer (server fires once per profile)
	do
		local starterToast: Frame? = nil
		local lastStarterToastAt = 0.0
		local STARTER_TOAST_DEBOUNCE = 30

		local function destroyStarterToast()
			if starterToast then
				starterToast:Destroy()
				starterToast = nil
			end
		end

		local function showStarterBundleToast(payload: any)
			local now = os.clock()
			if now - lastStarterToastAt < STARTER_TOAST_DEBOUNCE then
				return
			end
			lastStarterToastAt = now
			destroyStarterToast()

			local productId = if typeof(payload) == "table" then tonumber((payload :: any).ProductId) else nil
			local displayName = if typeof(payload) == "table" then tostring((payload :: any).DisplayName or "Starter Bundle") else "Starter Bundle"
			local robux = if typeof(payload) == "table" then tonumber((payload :: any).RobuxPrice) else nil
			if not productId or productId == 0 then
				local def = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts.StarterBundle
				if def and typeof(def.Id) == "number" and def.Id ~= 0 then
					productId = def.Id
					displayName = def.DisplayName or displayName
					robux = def.RobuxPrice or robux
				else
					return
				end
			end

			local host = screenGui
			if not host then
				local pg = player:FindFirstChild("PlayerGui")
				local existing = pg and pg:FindFirstChild("WarEmpireShop")
				if existing and existing:IsA("ScreenGui") then
					host = existing
					screenGui = existing
				else
					return
				end
			end

			local toast = Instance.new("Frame")
			toast.Name = "StarterBundleToast"
			toast.AnchorPoint = Vector2.new(0.5, 0)
			toast.Position = UDim2.new(0.5, 0, 0, if isTouch then 72 else 56)
			toast.Size = if isTouch then UDim2.new(0.94, 0, 0, 118) else UDim2.fromOffset(360, 108)
			toast.BackgroundColor3 = Constants.Colors.Panel
			toast.BorderSizePixel = 0
			toast.ZIndex = 80
			corner(toast, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(80, 200, 120)
			stroke.Thickness = 1.6
			stroke.Parent = toast
			toast.Parent = host
			starterToast = toast

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(12, 8)
			title.Size = UDim2.new(1, -56, 0, 22)
			title.Font = Enum.Font.GothamBold
			title.TextSize = if isTouch then 16 else 15
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Color3.fromRGB(120, 255, 160)
			title.Text = "Jumpstart your base?"
			title.ZIndex = 81
			title.Parent = toast

			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1
			sub.Position = UDim2.fromOffset(12, 30)
			sub.Size = UDim2.new(1, -24, 0, 18)
			sub.Font = Enum.Font.Gotham
			sub.TextSize = 11
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextColor3 = Constants.Colors.Muted
			sub.Text = displayName .. (if robux then string.format(" · %d R$", robux) else "")
			sub.ZIndex = 81
			sub.Parent = toast

			local dismiss = Instance.new("TextButton")
			dismiss.AnchorPoint = Vector2.new(1, 0)
			dismiss.Position = UDim2.new(1, -8, 0, 6)
			dismiss.Size = UDim2.fromOffset(36, 36)
			dismiss.BackgroundColor3 = Constants.Colors.Background
			dismiss.Font = Enum.Font.GothamBold
			dismiss.Text = "X"
			dismiss.TextColor3 = Constants.Colors.Text
			dismiss.BorderSizePixel = 0
			dismiss.ZIndex = 82
			corner(dismiss, 6)
			dismiss.Parent = toast
			UIUtil.EnsureMinTouch(dismiss, 44)
			dismiss.Activated:Connect(destroyStarterToast)

			local buy = Instance.new("TextButton")
			buy.Position = UDim2.fromOffset(12, 58)
			buy.Size = UDim2.new(1, -24, 0, if isTouch then 48 else 40)
			buy.BackgroundColor3 = Color3.fromRGB(40, 140, 70)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = if isTouch then 15 else 14
			buy.TextColor3 = Color3.fromRGB(240, 255, 245)
			buy.Text = "Get Starter Bundle"
			buy.BorderSizePixel = 0
			buy.ZIndex = 82
			corner(buy, 8)
			buy.Parent = toast
			UIUtil.EnsureMinTouch(buy, if isTouch then 48 else 44)
			buy.Activated:Connect(function()
				destroyStarterToast()
				-- PromptProductPurchase only — grants via ProcessReceipt
				promptDevProduct("StarterBundle")
			end)

			task.delay(14, function()
				if starterToast == toast then
					destroyStarterToast()
				end
			end)
		end

		local remote = Remotes.GetEvent(Constants.RemoteNames.StarterBundleOffer)
		if remote then
			remote.OnClientEvent:Connect(function(payload: any)
				task.defer(function()
					if not screenGui then
						task.wait(0.2)
					end
					showStarterBundleToast(payload)
				end)
			end)
		end
	end

	-- v33: one-shot AutoCollect soft offer after first manual ATM collect
	do
		local acToast: Frame? = nil
		local lastAcToastAt = 0.0
		local AC_TOAST_DEBOUNCE = 30

		local function destroyAcToast()
			if acToast then
				acToast:Destroy()
				acToast = nil
			end
		end

		local function showAutoCollectToast(payload: any)
			local now = os.clock()
			if now - lastAcToastAt < AC_TOAST_DEBOUNCE then
				return
			end
			lastAcToastAt = now
			destroyAcToast()

			local displayName = "Auto Collect"
			local robux = nil
			if typeof(payload) == "table" then
				displayName = tostring((payload :: any).DisplayName or displayName)
				robux = tonumber((payload :: any).RobuxPrice)
			end
			local def = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses.AutoCollect
			if not def or typeof(def.Id) ~= "number" or def.Id == 0 then
				return
			end

			local host = screenGui
			if not host then
				return
			end

			local toast = Instance.new("Frame")
			toast.Name = "AutoCollectToast"
			toast.AnchorPoint = Vector2.new(0.5, 0)
			toast.Position = UDim2.new(0.5, 0, 0, if isTouch then 72 else 56)
			toast.Size = if isTouch then UDim2.new(0.94, 0, 0, 118) else UDim2.fromOffset(360, 108)
			toast.BackgroundColor3 = Constants.Colors.Panel
			toast.BorderSizePixel = 0
			toast.ZIndex = 80
			corner(toast, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(220, 80, 80)
			stroke.Thickness = 1.6
			stroke.Parent = toast
			toast.Parent = host
			acToast = toast

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(12, 8)
			title.Size = UDim2.new(1, -56, 0, 22)
			title.Font = Enum.Font.GothamBold
			title.TextSize = if isTouch then 16 else 15
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Color3.fromRGB(255, 160, 140)
			title.Text = "Skip the walk to the ATM?"
			title.ZIndex = 81
			title.Parent = toast

			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1
			sub.Position = UDim2.fromOffset(12, 30)
			sub.Size = UDim2.new(1, -24, 0, 18)
			sub.Font = Enum.Font.Gotham
			sub.TextSize = 11
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextColor3 = Constants.Colors.Muted
			sub.Text = displayName .. (if robux then string.format(" · %d R$", robux) else "")
			sub.ZIndex = 81
			sub.Parent = toast

			local dismiss = Instance.new("TextButton")
			dismiss.AnchorPoint = Vector2.new(1, 0)
			dismiss.Position = UDim2.new(1, -8, 0, 6)
			dismiss.Size = UDim2.fromOffset(36, 36)
			dismiss.BackgroundColor3 = Constants.Colors.Background
			dismiss.Font = Enum.Font.GothamBold
			dismiss.Text = "X"
			dismiss.TextColor3 = Constants.Colors.Text
			dismiss.BorderSizePixel = 0
			dismiss.ZIndex = 82
			corner(dismiss, 6)
			dismiss.Parent = toast
			UIUtil.EnsureMinTouch(dismiss, 44)
			dismiss.Activated:Connect(destroyAcToast)

			local buy = Instance.new("TextButton")
			buy.Position = UDim2.fromOffset(12, 58)
			buy.Size = UDim2.new(1, -24, 0, if isTouch then 48 else 40)
			buy.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = if isTouch then 15 else 14
			buy.TextColor3 = Color3.fromRGB(255, 240, 240)
			buy.Text = "Get Auto Collect"
			buy.BorderSizePixel = 0
			buy.ZIndex = 82
			corner(buy, 8)
			buy.Parent = toast
			UIUtil.EnsureMinTouch(buy, if isTouch then 48 else 44)
			buy.Activated:Connect(function()
				destroyAcToast()
				promptGamePass("AutoCollect")
			end)

			task.delay(12, function()
				if acToast == toast then
					destroyAcToast()
				end
			end)
		end

		local remote = Remotes.GetEvent(Constants.RemoteNames.AutoCollectOffer)
		if remote then
			remote.OnClientEvent:Connect(function(payload: any)
				task.defer(function()
					if not screenGui then
						task.wait(0.2)
					end
					showAutoCollectToast(payload)
				end)
			end)
		end
	end

	-- v34: one-shot DoubleCash soft offer toast (existing GamePass Id only)
	do
		local dcToast: Frame? = nil
		local lastDcToastAt = 0.0
		local DC_TOAST_DEBOUNCE = 8.0

		local function destroyDcToast()
			if dcToast then
				dcToast:Destroy()
				dcToast = nil
			end
		end

		local function showDoubleCashToast(payload: any)
			local now = os.clock()
			if now - lastDcToastAt < DC_TOAST_DEBOUNCE then
				return
			end
			lastDcToastAt = now
			destroyDcToast()
			local displayName = "2x Cash"
			local robux = nil
			if typeof(payload) == "table" then
				displayName = tostring((payload :: any).DisplayName or displayName)
				robux = tonumber((payload :: any).RobuxPrice)
			end
			local def = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses.DoubleCash
			if not def or typeof(def.Id) ~= "number" or def.Id == 0 then
				return
			end
			local host = screenGui
			if not host then
				return
			end
			local toast = Instance.new("Frame")
			toast.Name = "DoubleCashToast"
			toast.AnchorPoint = Vector2.new(0.5, 0)
			toast.Position = UDim2.new(0.5, 0, 0, if isTouch then 72 else 56)
			toast.Size = if isTouch then UDim2.new(0.94, 0, 0, 118) else UDim2.fromOffset(360, 108)
			toast.BackgroundColor3 = Constants.Colors.Panel
			toast.BorderSizePixel = 0
			toast.ZIndex = 80
			corner(toast, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 90, 50)
			stroke.Thickness = 1.6
			stroke.Parent = toast
			toast.Parent = host
			dcToast = toast

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(12, 8)
			title.Size = UDim2.new(1, -48, 0, 24)
			title.Font = Enum.Font.GothamBold
			title.TextSize = if isTouch then 17 else 16
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Color3.fromRGB(255, 200, 120)
			title.Text = "★ Soft offer · " .. displayName
			title.ZIndex = 81
			title.Parent = toast

			local body = Instance.new("TextLabel")
			body.BackgroundTransparency = 1
			body.Position = UDim2.fromOffset(12, 32)
			body.Size = UDim2.new(1, -24, 0, 22)
			body.Font = Enum.Font.Gotham
			body.TextSize = if isTouch then 13 else 12
			body.TextXAlignment = Enum.TextXAlignment.Left
			body.TextColor3 = Constants.Colors.Muted
			body.Text = if robux then string.format("Double all cash earnings · %d R$", robux) else "Double all cash earnings"
			body.ZIndex = 81
			body.Parent = toast

			local dismiss = Instance.new("TextButton")
			dismiss.AnchorPoint = Vector2.new(1, 0)
			dismiss.Position = UDim2.new(1, -8, 0, 6)
			dismiss.Size = UDim2.fromOffset(32, 32)
			dismiss.BackgroundTransparency = 1
			dismiss.Text = "✕"
			dismiss.Font = Enum.Font.GothamBold
			dismiss.TextSize = 18
			dismiss.TextColor3 = Constants.Colors.Muted
			dismiss.ZIndex = 82
			dismiss.Parent = toast
			UIUtil.EnsureMinTouch(dismiss, 44)
			dismiss.Activated:Connect(destroyDcToast)

			local buy = Instance.new("TextButton")
			buy.Position = UDim2.fromOffset(12, 58)
			buy.Size = UDim2.new(1, -24, 0, if isTouch then 48 else 40)
			buy.BackgroundColor3 = Color3.fromRGB(220, 70, 40)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = if isTouch then 15 else 14
			buy.TextColor3 = Color3.fromRGB(255, 240, 240)
			buy.Text = "Get 2x Cash"
			buy.BorderSizePixel = 0
			buy.ZIndex = 82
			corner(buy, 8)
			buy.Parent = toast
			UIUtil.EnsureMinTouch(buy, if isTouch then 48 else 44)
			buy.Activated:Connect(function()
				destroyDcToast()
				promptGamePass("DoubleCash")
			end)

			task.delay(12, function()
				if dcToast == toast then
					destroyDcToast()
				end
			end)
		end

		local dcRemote = Remotes.GetEvent(Constants.RemoteNames.DoubleCashOffer)
		if dcRemote then
			dcRemote.OnClientEvent:Connect(function(payload: any)
				task.defer(function()
					if not screenGui then
						task.wait(0.2)
					end
					showDoubleCashToast(payload)
				end)
			end)
		end
	end


	-- v35: one-shot VIP soft offer toast (existing GamePass Id 1985475542 only)
	do
		local vipToast: Frame? = nil
		local lastVipToastAt = 0.0
		local VIP_TOAST_DEBOUNCE = 12.0

		local function destroyVipToast()
			if vipToast then
				vipToast:Destroy()
				vipToast = nil
			end
		end

		local function showVIPToast(payload: any)
			local now = os.clock()
			if now - lastVipToastAt < VIP_TOAST_DEBOUNCE then
				return
			end
			lastVipToastAt = now
			destroyVipToast()
			local displayName = "VIP"
			local robux = nil
			if typeof(payload) == "table" then
				displayName = tostring((payload :: any).DisplayName or displayName)
				robux = tonumber((payload :: any).RobuxPrice)
			end
			local def = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses.VIP
			if not def or typeof(def.Id) ~= "number" or def.Id == 0 then
				return
			end
			local host = screenGui
			if not host then
				return
			end
			local toast = Instance.new("Frame")
			toast.Name = "VIPToast"
			toast.AnchorPoint = Vector2.new(0.5, 0)
			toast.Position = UDim2.new(0.5, 0, 0, if isTouch then 72 else 56)
			toast.Size = if isTouch then UDim2.new(0.94, 0, 0, 118) else UDim2.fromOffset(360, 108)
			toast.BackgroundColor3 = Constants.Colors.Panel
			toast.BorderSizePixel = 0
			toast.ZIndex = 80
			corner(toast, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Constants.Colors.Gold
			stroke.Thickness = 1.6
			stroke.Parent = toast
			toast.Parent = host
			vipToast = toast

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(12, 8)
			title.Size = UDim2.new(1, -48, 0, 24)
			title.Font = Enum.Font.GothamBold
			title.TextSize = if isTouch then 17 else 16
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Constants.Colors.Gold
			title.Text = "★ Soft offer · " .. displayName
			title.ZIndex = 81
			title.Parent = toast

			local body = Instance.new("TextLabel")
			body.BackgroundTransparency = 1
			body.Position = UDim2.fromOffset(12, 32)
			body.Size = UDim2.new(1, -24, 0, 22)
			body.Font = Enum.Font.Gotham
			body.TextSize = if isTouch then 13 else 12
			body.TextXAlignment = Enum.TextXAlignment.Left
			body.TextColor3 = Constants.Colors.Muted
			body.Text = if robux then string.format("+25%% cash · prestige presence · %d R$", robux) else "+25% cash · prestige presence"
			body.ZIndex = 81
			body.Parent = toast

			local dismiss = Instance.new("TextButton")
			dismiss.AnchorPoint = Vector2.new(1, 0)
			dismiss.Position = UDim2.new(1, -8, 0, 6)
			dismiss.Size = UDim2.fromOffset(32, 32)
			dismiss.BackgroundTransparency = 1
			dismiss.Text = "✕"
			dismiss.Font = Enum.Font.GothamBold
			dismiss.TextSize = 18
			dismiss.TextColor3 = Constants.Colors.Muted
			dismiss.ZIndex = 82
			dismiss.Parent = toast
			UIUtil.EnsureMinTouch(dismiss, 44)
			dismiss.Activated:Connect(destroyVipToast)

			local buy = Instance.new("TextButton")
			buy.Position = UDim2.fromOffset(12, 58)
			buy.Size = UDim2.new(1, -24, 0, if isTouch then 48 else 40)
			buy.BackgroundColor3 = Color3.fromRGB(180, 140, 40)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = if isTouch then 15 else 14
			buy.TextColor3 = Color3.fromRGB(255, 250, 230)
			buy.Text = "Get VIP"
			buy.BorderSizePixel = 0
			buy.ZIndex = 82
			corner(buy, 8)
			buy.Parent = toast
			UIUtil.EnsureMinTouch(buy, if isTouch then 48 else 44)
			buy.Activated:Connect(function()
				destroyVipToast()
				promptGamePass("VIP")
			end)

			task.delay(12, function()
				if vipToast == toast then
					destroyVipToast()
				end
			end)
		end

		local vipRemote = Remotes.GetEvent(Constants.RemoteNames.VIPOffer)
		if vipRemote then
			vipRemote.OnClientEvent:Connect(function(payload: any)
				task.defer(function()
					if not screenGui then
						task.wait(0.2)
					end
					showVIPToast(payload)
				end)
			end)
		end
	end

	-- v33: ATM raid success / cooldown HUD chip
	do
		local chip: Frame? = nil
		local hideToken = 0

		local function showAtmRaidHud(payload: any)
			if typeof(payload) ~= "table" then
				return
			end
			local host = screenGui
			if not host then
				return
			end
			if chip then
				chip:Destroy()
				chip = nil
			end
			local success = (payload :: any).Success == true
			local raided = (payload :: any).Raided == true
			local cd = math.max(0, math.floor(tonumber((payload :: any).CooldownRemaining) or 0))
			local stolen = math.floor(tonumber((payload :: any).Stolen) or 0)
			local victim = tostring((payload :: any).VictimName or "")

			local frame = Instance.new("Frame")
			frame.Name = "AtmRaidHud"
			frame.AnchorPoint = Vector2.new(0.5, 1)
			frame.Position = UDim2.new(0.5, 0, 1, if isTouch then -110 else -96)
			frame.Size = if isTouch then UDim2.new(0.9, 0, 0, 52) else UDim2.fromOffset(340, 48)
			frame.BackgroundColor3 = if success then Color3.fromRGB(30, 70, 40) elseif raided then Color3.fromRGB(80, 30, 30) else Color3.fromRGB(40, 40, 28)
			frame.BorderSizePixel = 0
			frame.ZIndex = 75
			corner(frame, 8)
			local stroke = Instance.new("UIStroke")
			stroke.Color = if success then Color3.fromRGB(120, 220, 140) elseif raided then Color3.fromRGB(255, 120, 100) else Color3.fromRGB(230, 200, 80)
			stroke.Thickness = 1.4
			stroke.Parent = frame
			frame.Parent = host
			chip = frame

			local lab = Instance.new("TextLabel")
			lab.BackgroundTransparency = 1
			lab.Size = UDim2.fromScale(1, 1)
			lab.Font = Enum.Font.GothamBold
			lab.TextSize = if isTouch then 15 else 14
			lab.TextColor3 = Color3.fromRGB(245, 245, 240)
			lab.TextStrokeTransparency = 0.35
			lab.ZIndex = 76
			if success then
				lab.Text = string.format("ATM RAID +$%d%s · cooldown 1m", stolen, if victim ~= "" then (" from " .. victim) else "")
			elseif raided then
				lab.Text = string.format("ATM RAIDED −$%d (10%%)", stolen)
			else
				lab.Text = string.format("ATM raid cooldown — %ds", cd)
			end
			lab.Parent = frame

			hideToken += 1
			local token = hideToken
			local hold = if success or raided then 5.5 else math.clamp(cd, 2, 8)
			task.delay(hold, function()
				if token == hideToken and chip == frame then
					frame:Destroy()
					if chip == frame then
						chip = nil
					end
				end
			end)
		end

		local remote = Remotes.GetEvent(Constants.RemoteNames.AtmRaidStateUpdate)
		if remote then
			remote.OnClientEvent:Connect(function(payload: any)
				task.defer(function()
					if not screenGui then
						task.wait(0.2)
					end
					showAtmRaidHud(payload)
				end)
			end)
		end
	end

	-- ATM-cluster premium pads → PromptGamePass / PromptProduct (server-validated)
	do
		local remote = Remotes.GetEvent(Constants.RemoteNames.PromptPremiumPad)
		if remote then
			remote.OnClientEvent:Connect(function(payload: any)
				if typeof(payload) ~= "table" then
					return
				end
				local kind = payload.Kind
				local key = payload.Key
				if typeof(kind) ~= "string" or typeof(key) ~= "string" then
					return
				end
				if kind == "GamePass" then
					promptGamePass(key)
				elseif kind == "DevProduct" then
					promptDevProduct(key)
				end
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
