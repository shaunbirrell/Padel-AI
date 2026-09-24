--!strict
--[[ Phase 7 — Shop UI. Prompts Marketplace; grants only via server ProcessReceipt / GamePass ownership.
	v69: two tabs — SUPPLY (Robux DevProducts / GamePasses) and WEAPONS (in-game Cash, WeaponConfig). WEAPONS
	rows fire RequestPurchaseWeapon / RequestEquipWeapon with the weapon id only; CombatService prices,
	level-checks, rate-limits and grants. The Armory terminal (WE_OpenPanel "Shop", weapons prompt) opens the
	WEAPONS tab. One-time DevProducts (MonetizationConfig OneTime) show OWNED once owned and are never
	re-prompted. ]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local NotificationController = require(script.Parent.NotificationController)

local ShopController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local menuOpen = false
local pendingCashMegaHighlight = false
local shopListFrame: ScrollingFrame? = nil
local screenGui: ScreenGui? = nil

-- v69: tabs
local panelTitle: TextLabel? = nil
local tabLists: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local activeTab = "Supply"
local TAB_TITLES: { [string]: string } = { Supply = "Supply Depot", Weapons = "Armory" }

-- v69: what the rows show as owned / locked. Display only — the server validates every BUY, EQUIP and receipt.
local knownLevel: number? = nil -- WE_Level attribute / XPUpdate / PlayerState, whichever arrived last
local knownBarracksLevel: number? = nil -- InstantBarracks is pointless once Barracks is L1+
local knownPremium: boolean? = nil -- BattlePassStateUpdate.Premium
local fallbackWeapons: { [string]: boolean }? = nil -- PlayerState.Weapons until WE_Weapons replicates
local fallbackEquipped: string? = nil
local sessionOwnedProducts: { [string]: boolean } = {} -- one-time products bought this session
local sessionOwnedPasses: { [string]: boolean } = {}
local refreshQueued = false
local refreshShopRows: () -> () = function() end -- set in Init
local lastSnapshotAt = -math.huge

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function toast(message: string, kind: string?)
	pcall(NotificationController.Show, message, kind or "Info", 3)
end

local function formatCash(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		refreshShopRows()
	end)
end

--[[ v69: row button looks. Disabled buttons carry WE_Disabled and their Activated handler returns early,
	so a LOCKED / OWNED / EQUIPPED button never looks tappable and never does anything. ]]
local function setRowButton(btn: TextButton, text: string, mode: string)
	local disabled = mode == "owned" or mode == "locked" or mode == "busy"
	btn.Text = text
	btn:SetAttribute("WE_Disabled", disabled)
	btn.AutoButtonColor = not disabled
	if mode == "owned" then
		btn.BackgroundColor3 = Color3.fromRGB(34, 64, 40)
		btn.TextColor3 = Color3.fromRGB(180, 255, 160)
	elseif mode == "locked" or mode == "busy" then
		btn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
		btn.TextColor3 = Constants.Colors.Muted
	elseif mode == "equip" then
		btn.BackgroundColor3 = Color3.fromRGB(40, 110, 60)
		btn.TextColor3 = Color3.fromRGB(240, 255, 245)
	elseif mode == "dim" then
		btn.BackgroundColor3 = Constants.Colors.Gunmetal
		btn.TextColor3 = Constants.Colors.Muted
	else -- "buy"
		btn.BackgroundColor3 = Constants.Colors.Gunmetal
		btn.TextColor3 = Color3.fromRGB(255, 248, 230)
	end
	local stroke = btn:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if mode == "buy"
			then Constants.Colors.Gold
			elseif mode == "equip" then Color3.fromRGB(120, 220, 140)
			else Color3.fromRGB(80, 88, 96)
		stroke.Thickness = if disabled then 1 else 1.25
	end
end

--[[ v69: a OneTime DevProduct (boolean grant) is owned when the server says so (player attribute
	WE_Ent_<entitlement>), when it was bought this session, or when its effect is already there (Battle Pass
	Premium on; Barracks already L1+ for InstantBarracks). ]]
local function isOneTimeOwned(productKey: string): boolean
	local def = (MonetizationConfig.DevProducts :: any)[productKey]
	if typeof(def) ~= "table" or def.OneTime ~= true then
		return false
	end
	if sessionOwnedProducts[productKey] == true then
		return true
	end
	local entKey = if typeof(def.GrantEntitlement) == "string" and def.GrantEntitlement ~= ""
		then def.GrantEntitlement
		else productKey
	if player:GetAttribute("WE_Ent_" .. entKey) == true then
		return true
	end
	if def.GrantsBattlePassPremium == true and knownPremium == true then
		return true
	end
	if def.GrantEntitlement == "InstantBarracks" and (knownBarracksLevel or 0) >= 1 then
		return true
	end
	return false
end

local function ownedWeapons(): { [string]: boolean }
	local raw: any = player:GetAttribute("WE_Weapons")
	if typeof(raw) ~= "string" and fallbackWeapons then
		local ids: { string } = {}
		for id in pairs(fallbackWeapons) do
			table.insert(ids, id)
		end
		raw = table.concat(ids, ",")
	end
	return WeaponConfig.ParseOwned(raw)
end

local function equippedWeapon(): string?
	local attr = player:GetAttribute("WE_EquippedWeapon")
	if typeof(attr) == "string" then
		return attr
	end
	return fallbackEquipped
end

local function currentCash(): number?
	local attr = tonumber(player:GetAttribute("WE_Cash"))
	if attr then
		return attr
	end
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Cash")
	if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
		return (v :: any).Value
	end
	return nil
end

local function applyPlayerState(state: any)
	if typeof(state) ~= "table" then
		return
	end
	if typeof(state.Level) == "number" then
		knownLevel = state.Level
	end
	if typeof(state.Weapons) == "table" then
		local set: { [string]: boolean } = {}
		for id, owned in pairs(state.Weapons) do
			if typeof(id) == "string" and owned == true then
				set[id] = true
			end
		end
		fallbackWeapons = set
	end
	if typeof(state.EquippedWeapon) == "string" then
		fallbackEquipped = state.EquippedWeapon
	end
	local base = state.Base
	if typeof(base) == "table" and typeof(base.Upgrades) == "table" and typeof(base.Upgrades.Barracks) == "number" then
		knownBarracksLevel = base.Upgrades.Barracks
	end
	queueRefresh()
end

-- One GetPlayerState read per shop open (≥5 s apart) so owned / level / Barracks are fresh. Never blocks.
local function requestStateSnapshot()
	local now = os.clock()
	if now - lastSnapshotAt < 5 then
		return
	end
	lastSnapshotAt = now
	task.spawn(function()
		local fn = Remotes.TryGetFunction(Constants.RemoteNames.GetPlayerState)
		if not fn then
			return
		end
		local ok, state = pcall(function()
			return fn:InvokeServer()
		end)
		if ok then
			applyPlayerState(state)
		end
	end)
end

local function selectTab(name: string)
	if not tabLists[name] then
		return
	end
	activeTab = name
	for tabName, tabList in pairs(tabLists) do
		tabList.Visible = tabName == name
	end
	for tabName, btn in pairs(tabButtons) do
		local on = tabName == name
		btn.BackgroundColor3 = if on then Constants.Colors.Gold else Constants.Colors.Gunmetal
		btn.TextColor3 = if on then Constants.Colors.TextDark else Constants.Colors.Muted
	end
	if panelTitle then
		panelTitle.Text = TAB_TITLES[name] or "Supply Depot"
	end
	queueRefresh()
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
		selectTab("Supply")
		task.defer(highlightCashMegaRow)
	end
	if open then
		requestStateSnapshot()
		queueRefresh()
	end
end

local function promptDevProduct(productKey: string)
	local def = MonetizationConfig.DevProducts[productKey]
	if not def then
		return
	end
	-- v69: a one-time product the player already owns is never prompted again (it would charge for nothing)
	if isOneTimeOwned(productKey) then
		toast("You already own " .. tostring(def.DisplayName or productKey), "Info")
		queueRefresh()
		return
	end
	-- Ask server to log + validate; client still prompts Marketplace (v69: intent log never delays the prompt)
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseDevProduct, productKey)
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
	-- v69: HideFromShop passes (ExtraPlotCosmetic — theme not implemented) are never offered
	if (def :: any).HideFromShop == true then
		return
	end
	-- Log intent on server; NEVER treat client confirmation as a grant
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseGamePass, passKey)
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
			-- v69: never offer a one-time product the player already owns (e.g. Speed Boost)
			if isOneTimeOwned(key) then
				return nil, nil, nil, nil
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
	panel.Size = if isTouch then UDim2.new(0.92, 0, 0.72, 0) else UDim2.fromOffset(400, 400)
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
	panelTitle = title

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

	-- v69: SUPPLY / WEAPONS tabs under the title (the close button keeps the top-right corner)
	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.Position = UDim2.fromOffset(12, 44)
	tabBar.Size = UDim2.new(1, -84, 0, 44)
	tabBar.Parent = panel
	local function makeTab(name: string, text: string, index: number)
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. name
		b.Position = UDim2.new((index - 1) * 0.5, if index == 1 then 0 else 4, 0, 0)
		b.Size = UDim2.new(0.5, -4, 1, 0) -- 44 px tall: full touch target without EnsureMinTouch
		b.BackgroundColor3 = Constants.Colors.Gunmetal
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.TextColor3 = Constants.Colors.Muted
		b.Text = text
		b.BorderSizePixel = 0
		corner(b, 6)
		b.Parent = tabBar
		b.Activated:Connect(function()
			selectTab(name)
		end)
		tabButtons[name] = b
	end
	makeTab("Supply", "SUPPLY · R$", 1)
	makeTab("Weapons", "WEAPONS · CASH", 2)

	local function makeList(name: string, noteText: string): ScrollingFrame
		local l = Instance.new("ScrollingFrame")
		l.Name = "List_" .. name
		l.Position = UDim2.fromOffset(12, 96)
		l.Size = UDim2.new(1, -24, 1, -108)
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.ScrollBarThickness = 4
		l.CanvasSize = UDim2.fromOffset(0, 0)
		l.AutomaticCanvasSize = Enum.AutomaticSize.Y
		l.Visible = name == activeTab
		l.Parent = panel
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 6)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = l
		local n = Instance.new("TextLabel")
		n.Name = "Note"
		n.BackgroundTransparency = 1
		n.Size = UDim2.new(1, -8, 0, 30)
		n.Font = Enum.Font.Gotham
		n.TextSize = 11
		n.TextWrapped = true
		n.TextXAlignment = Enum.TextXAlignment.Left
		n.TextColor3 = Constants.Colors.Muted
		n.Text = noteText
		n.LayoutOrder = 0
		n.Parent = l
		tabLists[name] = l
		return l
	end
	local list = makeList("Supply", "Prices in Robux. Live products charge on confirm. Passes persist after Rebirth.")
	shopListFrame = list
	local weaponList = makeList(
		"Weapons",
		"Weapons cost in-game Cash. EQUIP owned weapons here, or cycle them with Q / E (◀ ▶ on mobile)."
	)
	selectTab(activeTab)

	local function buildRow(parentList: ScrollingFrame, layoutOrder: number, rowName: string, label: string, sub: string, btnText: string): (Frame, TextLabel, TextButton)
		local row = Instance.new("Frame")
		row.Name = "ShopRow_" .. rowName
		row.Size = UDim2.new(1, -8, 0, 56)
		row.BackgroundColor3 = Constants.Colors.Background
		row.BorderSizePixel = 0
		row.LayoutOrder = layoutOrder
		row.Parent = parentList
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
		s.TextTruncate = Enum.TextTruncate.AtEnd
		s.Text = sub
		s.Parent = row

		local btn = Instance.new("TextButton")
		btn.Name = "Action"
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, -8, 0.5, 0)
		btn.Size = UDim2.fromOffset(if isTouch then 110 else 96, 48)
		btn.BackgroundColor3 = Constants.Colors.Gunmetal
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 11
		btn.TextColor3 = Color3.fromRGB(255, 248, 230)
		btn.Text = btnText
		btn.BorderSizePixel = 0
		corner(btn, 6)
		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Constants.Colors.Gold
		btnStroke.Thickness = 1.25
		btnStroke.Parent = btn
		btn.Parent = row
		UIUtil.EnsureMinTouch(btn, 44)
		return row, s, btn
	end

	local order = 0
	-- SUPPLY row. onClick nil = display-only row: its button is disabled (never a dead gold BUY).
	local function addRow(label: string, sub: string, onClick: (() -> ())?, btnText: string?, rowKey: string?): TextButton
		order += 1
		local _, _, btn = buildRow(list, order, rowKey or tostring(order), label, sub, btnText or "BUY")
		btn.Activated:Connect(function()
			if onClick == nil or btn:GetAttribute("WE_Disabled") == true then
				return
			end
			onClick()
		end)
		if onClick == nil then
			setRowButton(btn, btnText or "LOCKED", "locked")
		end
		return btn
	end

	-- v69: rows whose button flips to OWNED (one-time DevProducts, GamePasses)
	local oneTimeRows: { [string]: { Btn: TextButton, Label: string } } = {}
	local passRows: { [string]: { Btn: TextButton, Label: string } } = {}

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
		local btn = addRow(title, sub, function()
			promptDevProduct(key)
		end, btnLabel, key)
		if def.OneTime == true then
			oneTimeRows[key] = { Btn = btn, Label = btnLabel }
		end
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
		-- v69: HideFromShop passes are not sold (ExtraPlotCosmetic "Elite Base Theme": nothing applies it yet)
		if (def :: any).HideFromShop == true then
			continue
		end
		local stub = (tonumber(def.Id) or 0) == 0
		local robux = tonumber(def.RobuxPrice) or 0
		local sub = (def.Description or "") .. (if stub then " · coming soon (no charge)" else "")
		local btnLabel = if robux > 0 then (tostring(robux) .. " R$") else "PASS"
		local btn = addRow("Pass: " .. def.DisplayName, sub, function()
			promptGamePass(key)
		end, btnLabel, "Pass_" .. key)
		passRows[key] = { Btn = btn, Label = btnLabel }
	end

	-- Policy-pending loot crates (display only — no purchase/grant path). v69: disabled LOCKED button.
	do
		local ok, LootBoxConfig = pcall(function()
			return require(Shared.Configs.LootBoxConfig)
		end)
		if ok and LootBoxConfig and LootBoxConfig.PolicyPending then
			addRow("Supply Crate (locked)", "Random loot is policy-pending — not for sale", nil, "LOCKED", "SupplyCrate")
		end
	end

	-- v69: WEAPONS tab — one row per WeaponConfig weapon in the shared order (UnlockLevel, price, id)
	local weaponRows: { { Id: string, Row: Frame, Sub: TextLabel, Btn: TextButton, Action: string? } } = {}
	local weaponBusy: { [string]: { Until: number, Text: string } } = {}
	local WEAPON_BUSY_SECONDS = 2.5

	local function weaponStats(def: any): string
		local pellets = tonumber(def.Pellets)
		local dmg = if pellets and pellets > 1 then (tostring(def.Damage) .. "×" .. tostring(pellets)) else tostring(def.Damage)
		return string.format("%s · DMG %s · %s/s · %sm", tostring(def.Rarity), dmg, tostring(def.FireRate), tostring(def.Range))
	end

	local function refreshWeaponRows()
		local owned = ownedWeapons()
		local equipped = equippedWeapon()
		local level = knownLevel
		local cash = currentCash()
		local now = os.clock()
		for _, r in ipairs(weaponRows) do
			local def = WeaponConfig.Weapons[r.Id]
			local cost = math.floor(tonumber(def.CostCash) or 0)
			local isOwned = owned[r.Id] == true
			local levelOk = level == nil or level >= def.UnlockLevel
			local stats = weaponStats(def)
			local busy = weaponBusy[r.Id]
			-- Weapons with no Cash price are only listed once owned (starter / granted)
			r.Row.Visible = isOwned or cost > 0
			r.Action = nil
			if r.Id == equipped then
				setRowButton(r.Btn, "EQUIPPED", "owned")
				r.Sub.Text = "Equipped · " .. stats
			elseif busy and now < busy.Until then
				setRowButton(r.Btn, busy.Text, "busy")
			elseif isOwned and levelOk then
				setRowButton(r.Btn, "EQUIP", "equip")
				r.Sub.Text = "Owned · " .. stats
				r.Action = "equip"
			elseif isOwned then
				setRowButton(r.Btn, "LV " .. def.UnlockLevel, "locked")
				r.Sub.Text = string.format("Owned · equip at Lv %d", def.UnlockLevel)
			elseif cost <= 0 then
				setRowButton(r.Btn, "N/A", "locked")
				r.Sub.Text = "Not sold in the Shop"
			elseif not levelOk then
				setRowButton(r.Btn, "LV " .. def.UnlockLevel, "locked")
				r.Sub.Text = string.format("Unlocks at Lv %d · $%s Cash", def.UnlockLevel, formatCash(cost))
			else
				local short = cash ~= nil and cash < cost
				-- Still tappable when short: the server answers with a "Not enough Cash" toast
				setRowButton(r.Btn, "BUY $" .. formatCash(cost), if short then "dim" else "buy")
				r.Sub.Text = if short and cash
					then string.format("Need $%s more Cash", formatCash(cost - cash))
					else string.format("Lv %d · %s", def.UnlockLevel, stats)
				r.Action = "buy"
			end
		end
	end

	do
		local wOrder = 0
		for _, id in ipairs(WeaponConfig.SortedIds()) do
			local def = WeaponConfig.Weapons[id]
			wOrder += 1
			local row, subLabel, btn = buildRow(weaponList, wOrder, "Weapon_" .. id, def.DisplayName, weaponStats(def), "…")
			local entry = { Id = id, Row = row, Sub = subLabel, Btn = btn, Action = nil :: string? }
			table.insert(weaponRows, entry)
			btn.Activated:Connect(function()
				local action = entry.Action
				if btn:GetAttribute("WE_Disabled") == true or action == nil then
					return
				end
				-- One request per tap: the row shows BUYING… / EQUIPPING… until the server's attribute push
				-- (or WEAPON_BUSY_SECONDS) — refusals arrive as a server toast.
				weaponBusy[id] = { Until = os.clock() + WEAPON_BUSY_SECONDS, Text = if action == "buy" then "BUYING…" else "EQUIPPING…" }
				refreshWeaponRows()
				task.delay(WEAPON_BUSY_SECONDS + 0.05, queueRefresh)
				local remoteName = if action == "buy"
					then Constants.RemoteNames.RequestPurchaseWeapon
					else Constants.RemoteNames.RequestEquipWeapon
				if not Remotes.FireServer(remoteName, id) then
					weaponBusy[id] = nil
					queueRefresh()
					toast("Shop is still connecting — try again in a moment", "Warn")
				end
			end)
		end
	end

	local function refreshOwnedRows()
		for key, r in pairs(oneTimeRows) do
			if isOneTimeOwned(key) then
				setRowButton(r.Btn, "OWNED", "owned")
			else
				setRowButton(r.Btn, r.Label, "buy")
			end
		end
		for key, r in pairs(passRows) do
			if sessionOwnedPasses[key] == true then
				setRowButton(r.Btn, "OWNED", "owned")
			end
		end
	end

	refreshShopRows = function()
		refreshWeaponRows()
		refreshOwnedRows()
	end

	-- v69: live inputs for the rows (attributes replicate without any remote)
	do
		local lvl = player:GetAttribute("WE_Level")
		if typeof(lvl) == "number" then
			knownLevel = lvl
		end
		player.AttributeChanged:Connect(function(attr: string)
			if attr == "WE_Weapons" or attr == "WE_EquippedWeapon" then
				table.clear(weaponBusy) -- server answered: drop BUYING… / EQUIPPING…
				queueRefresh()
			elseif attr == "WE_Level" then
				local v = player:GetAttribute("WE_Level")
				if typeof(v) == "number" then
					knownLevel = v
				end
				queueRefresh()
			elseif attr == "WE_Cash" or string.sub(attr, 1, 7) == "WE_Ent_" then
				queueRefresh()
			end
		end)
		Remotes.BindEvent(Constants.RemoteNames.XPUpdate, function(payload: any)
			if typeof(payload) == "table" and typeof(payload.Level) == "number" then
				knownLevel = payload.Level
				queueRefresh()
			end
		end)
		Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, applyPlayerState)
		Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(payload: any)
			if typeof(payload) == "table" and typeof(payload.Upgrades) == "table" and typeof(payload.Upgrades.Barracks) == "number" then
				knownBarracksLevel = payload.Upgrades.Barracks
				queueRefresh()
			end
		end)
		Remotes.BindEvent(Constants.RemoteNames.BattlePassStateUpdate, function(payload: any)
			if typeof(payload) == "table" and typeof(payload.Premium) == "boolean" then
				knownPremium = payload.Premium
				queueRefresh()
			end
		end)
		-- Same-session purchases show OWNED at once (the grant itself is ProcessReceipt / pass ownership only)
		pcall(function()
			MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, isPurchased: boolean)
				if userId ~= player.UserId or not isPurchased then
					return
				end
				for key, def in pairs(MonetizationConfig.DevProducts :: any) do
					if def.Id == productId and def.OneTime == true then
						sessionOwnedProducts[key] = true
					end
				end
				queueRefresh()
			end)
		end)
		pcall(function()
			MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, passId: number, wasPurchased: boolean)
				if who ~= player or not wasPurchased then
					return
				end
				for key, def in pairs(MonetizationConfig.GamePasses :: any) do
					if def.Id == passId then
						sessionOwnedPasses[key] = true
					end
				end
				queueRefresh()
			end)
		end)
		-- Armory terminal (WE_OpenPanel "Shop" with a weapons prompt, or WE_ShopTab) lands on WEAPONS.
		-- UIController opens the panel; this only picks the tab (deferred, so it wins whatever the handler order).
		ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
			if who ~= player or prompt:GetAttribute("WE_OpenPanel") ~= "Shop" then
				return
			end
			local tab = prompt:GetAttribute("WE_ShopTab")
			if typeof(tab) ~= "string" then
				local text = string.lower(prompt.ActionText .. " " .. prompt.ObjectText)
				tab = if string.find(text, "weapon", 1, true) then "Weapons" else "Supply"
			end
			task.defer(selectTab, tab :: string)
		end)
		queueRefresh()
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
			-- v69: Shop pass rows show OWNED too (session purchases stay OWNED even if the check lags)
			for key, r in pairs(passRows) do
				if sessionOwnedPasses[key] == true or queryOwnsGamePass(key) then
					setRowButton(r.Btn, "OWNED", "owned")
				else
					setRowButton(r.Btn, r.Label, "buy")
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

	-- v36: one-shot SpeedBoost soft offer toast (existing DevProduct Id 3713839342 only)
	do
		local sbToast: Frame? = nil
		local lastSbToastAt = 0.0
		local SB_TOAST_DEBOUNCE = 12.0

		local function destroySbToast()
			if sbToast then
				sbToast:Destroy()
				sbToast = nil
			end
		end

		local function showSpeedBoostToast(payload: any)
			local now = os.clock()
			if now - lastSbToastAt < SB_TOAST_DEBOUNCE then
				return
			end
			lastSbToastAt = now
			destroySbToast()
			local displayName = "Speed Boost"
			local robux = nil
			if typeof(payload) == "table" then
				displayName = tostring((payload :: any).DisplayName or displayName)
				robux = tonumber((payload :: any).RobuxPrice)
			end
			local def = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts.SpeedBoost
			if not def or typeof(def.Id) ~= "number" or def.Id == 0 then
				return
			end
			local host = screenGui
			if not host then
				return
			end
			local toast = Instance.new("Frame")
			toast.Name = "SpeedBoostToast"
			toast.AnchorPoint = Vector2.new(0.5, 0)
			toast.Position = UDim2.new(0.5, 0, 0, if isTouch then 72 else 56)
			toast.Size = if isTouch then UDim2.new(0.94, 0, 0, 118) else UDim2.fromOffset(360, 108)
			toast.BackgroundColor3 = Constants.Colors.Panel
			toast.BorderSizePixel = 0
			toast.ZIndex = 80
			corner(toast, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(90, 200, 255)
			stroke.Thickness = 1.6
			stroke.Parent = toast
			toast.Parent = host
			sbToast = toast

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(12, 8)
			title.Size = UDim2.new(1, -48, 0, 24)
			title.Font = Enum.Font.GothamBold
			title.TextSize = if isTouch then 17 else 16
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Color3.fromRGB(140, 220, 255)
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
			body.Text = if robux then string.format("Permanent move-speed · %d R$", robux) else "Permanent move-speed boost"
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
			dismiss.Activated:Connect(destroySbToast)

			local buy = Instance.new("TextButton")
			buy.Position = UDim2.fromOffset(12, 58)
			buy.Size = UDim2.new(1, -24, 0, if isTouch then 48 else 40)
			buy.BackgroundColor3 = Color3.fromRGB(40, 120, 160)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = if isTouch then 15 else 14
			buy.TextColor3 = Color3.fromRGB(255, 250, 230)
			buy.Text = "Get Speed Boost"
			buy.BorderSizePixel = 0
			buy.ZIndex = 82
			corner(buy, 8)
			buy.Parent = toast
			UIUtil.EnsureMinTouch(buy, if isTouch then 48 else 44)
			buy.Activated:Connect(function()
				destroySbToast()
				promptDevProduct("SpeedBoost")
			end)

			task.delay(12, function()
				if sbToast == toast then
					destroySbToast()
				end
			end)
		end

		local sbRemote = Remotes.GetEvent(Constants.RemoteNames.SpeedBoostOffer)
		if sbRemote then
			sbRemote.OnClientEvent:Connect(function(payload: any)
				task.defer(function()
					if not screenGui then
						task.wait(0.2)
					end
					showSpeedBoostToast(payload)
				end)
			end)
		end
	end

	-- v37: one-shot CashMega soft offer toast (existing DevProduct Id 3713838952 only)
	do
		local megaToast: Frame? = nil
		local lastMegaToastAt = 0.0
		local MEGA_TOAST_DEBOUNCE = 14.0

		local function destroyMegaToast()
			if megaToast then
				megaToast:Destroy()
				megaToast = nil
			end
		end

		local function showCashMegaToast(payload: any)
			local now = os.clock()
			if now - lastMegaToastAt < MEGA_TOAST_DEBOUNCE then
				return
			end
			lastMegaToastAt = now
			destroyMegaToast()
			local displayName = "Cash Pack Mega"
			local robux = nil
			if typeof(payload) == "table" then
				displayName = tostring((payload :: any).DisplayName or displayName)
				robux = tonumber((payload :: any).RobuxPrice)
			end
			local def = MonetizationConfig.DevProducts and MonetizationConfig.DevProducts.CashMega
			if not def or typeof(def.Id) ~= "number" or def.Id == 0 then
				return
			end
			local host = screenGui
			if not host then
				return
			end
			local toast = Instance.new("Frame")
			toast.Name = "CashMegaToast"
			toast.AnchorPoint = Vector2.new(0.5, 0)
			toast.Position = UDim2.new(0.5, 0, 0, if isTouch then 72 else 56)
			toast.Size = if isTouch then UDim2.new(0.94, 0, 0, 118) else UDim2.fromOffset(360, 108)
			toast.BackgroundColor3 = Color3.fromRGB(28, 42, 28)
			toast.BorderSizePixel = 0
			toast.ZIndex = 80
			corner(toast, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(130, 255, 170)
			stroke.Thickness = 1.8
			stroke.Parent = toast
			toast.Parent = host
			megaToast = toast

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(12, 8)
			title.Size = UDim2.new(1, -48, 0, 24)
			title.Font = Enum.Font.GothamBold
			title.TextSize = if isTouch then 16 else 15
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Color3.fromRGB(255, 250, 230)
			title.Text = "★ BEST OFFER — " .. displayName
			title.ZIndex = 81
			title.Parent = toast

			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1
			sub.Position = UDim2.fromOffset(12, 32)
			sub.Size = UDim2.new(1, -24, 0, 20)
			sub.Font = Enum.Font.Gotham
			sub.TextSize = 12
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextColor3 = Color3.fromRGB(180, 220, 190)
			sub.Text = if robux then string.format("Jumpstart · %d R$ · tap below", robux) else "Jumpstart cash pack · tap below"
			sub.ZIndex = 81
			sub.Parent = toast

			local dismiss = Instance.new("TextButton")
			dismiss.Position = UDim2.new(1, -36, 0, 6)
			dismiss.Size = UDim2.fromOffset(28, 28)
			dismiss.BackgroundColor3 = Color3.fromRGB(50, 55, 50)
			dismiss.Font = Enum.Font.GothamBold
			dismiss.TextSize = 16
			dismiss.TextColor3 = Color3.fromRGB(220, 220, 220)
			dismiss.Text = "×"
			dismiss.BorderSizePixel = 0
			dismiss.ZIndex = 82
			corner(dismiss, 6)
			dismiss.Parent = toast
			UIUtil.EnsureMinTouch(dismiss, 44)
			dismiss.Activated:Connect(destroyMegaToast)

			local buy = Instance.new("TextButton")
			buy.Position = UDim2.fromOffset(12, 58)
			buy.Size = UDim2.new(1, -24, 0, if isTouch then 48 else 40)
			buy.BackgroundColor3 = Color3.fromRGB(40, 140, 70)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = if isTouch then 15 else 14
			buy.TextColor3 = Color3.fromRGB(255, 250, 230)
			buy.Text = "Get Cash Mega"
			buy.BorderSizePixel = 0
			buy.ZIndex = 82
			corner(buy, 8)
			buy.Parent = toast
			UIUtil.EnsureMinTouch(buy, if isTouch then 48 else 44)
			buy.Activated:Connect(function()
				destroyMegaToast()
				pendingCashMegaHighlight = true
				promptDevProduct("CashMega")
			end)

			task.delay(12, function()
				if megaToast == toast then
					destroyMegaToast()
				end
			end)
		end

		local megaRemote = Remotes.GetEvent(Constants.RemoteNames.CashMegaOffer)
		if megaRemote then
			megaRemote.OnClientEvent:Connect(function(payload: any)
				task.defer(function()
					if not screenGui then
						task.wait(0.2)
					end
					showCashMegaToast(payload)
				end)
			end)
		end
	end

	-- v33 → v69: ATM raid chip (bottom centre). v69 payloads carry Phase (spec §4.4): Holding / Alarm show a
	-- live progress bar and hide themselves shortly after the last push; Interrupted / Blocked / Defended /
	-- Success / Robbed show the server's payload.Text for a few seconds. No Phase = legacy v33 rendering.
	do
		local chip: Frame? = nil
		local hideToken = 0

		local function dropChip()
			if chip then
				chip:Destroy()
				chip = nil
			end
		end

		local function hideLater(frame: Frame, seconds: number)
			hideToken += 1
			local token = hideToken
			task.delay(seconds, function()
				if token == hideToken and chip == frame then
					frame:Destroy()
					if chip == frame then
						chip = nil
					end
				end
			end)
		end

		-- legacy (no Phase): exactly the v33 chip
		local function showLegacyAtmRaidHud(payload: any, host: ScreenGui)
			dropChip()
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
				local thief = tostring((payload :: any).ThiefName or "")
				if thief ~= "" then
					lab.Text = string.format("ATM RAIDED −10%% by %s (−$%d)", thief, stolen)
				else
					lab.Text = string.format("ATM RAIDED −10%% (−$%d)", stolen)
				end
			else
				lab.Text = string.format("ATM raid cooldown — %ds", cd)
			end
			lab.Parent = frame

			hideLater(frame, if success or raided then 5.5 else math.clamp(cd, 2, 8))
		end

		type PhaseStyle = { Bg: Color3, Stroke: Color3, Hold: number, Bar: boolean }
		local AMBER: PhaseStyle = { Bg = Color3.fromRGB(74, 56, 16), Stroke = Color3.fromRGB(240, 190, 70), Hold = 2.5, Bar = false }
		local PHASE_STYLE: { [string]: PhaseStyle } = {
			Holding = { Bg = Color3.fromRGB(24, 28, 34), Stroke = Color3.fromRGB(230, 200, 80), Hold = 1.0, Bar = true }, -- thief
			Alarm = { Bg = Color3.fromRGB(112, 24, 22), Stroke = Color3.fromRGB(255, 120, 100), Hold = 1.5, Bar = true }, -- victim
			Interrupted = AMBER,
			Blocked = AMBER,
			Defended = { Bg = Color3.fromRGB(30, 70, 40), Stroke = Color3.fromRGB(120, 220, 140), Hold = 2.5, Bar = false },
			Success = { Bg = Color3.fromRGB(30, 70, 40), Stroke = Color3.fromRGB(120, 220, 140), Hold = 5, Bar = false },
			Robbed = { Bg = Color3.fromRGB(80, 30, 30), Stroke = Color3.fromRGB(255, 120, 100), Hold = 6, Bar = false },
		}

		local function phaseText(payload: any, phase: string): string
			local text = if typeof(payload.Text) == "string" and payload.Text ~= "" then payload.Text else nil
			local progress = tonumber(payload.HoldProgress)
			local need = tonumber(payload.HoldNeed)
			if phase == "Holding" then
				return text or string.format("ROBBING %s's ATM · %.1f/%ds — don't get hit!", tostring(payload.VictimName or "their"), progress or 0, math.floor(need or 6))
			elseif phase == "Alarm" then
				local base = text or string.format("⚠ %s is robbing your ATM!", tostring(payload.ThiefName or "Someone"))
				if progress and need and not string.find(base, "%d/%d") then
					base ..= string.format(" %d/%ds", math.floor(progress), math.floor(need))
				end
				return base
			end
			return text or tostring(payload.Reason or phase)
		end

		local function showPhaseChip(payload: any, host: ScreenGui, phase: string, style: PhaseStyle)
			local frame = chip
			if not frame or frame.Parent ~= host or frame:GetAttribute("WE_Phase") == nil then
				dropChip()
				local f = Instance.new("Frame")
				f.Name = "AtmRaidHud"
				f.AnchorPoint = Vector2.new(0.5, 1)
				f.Position = UDim2.new(0.5, 0, 1, if isTouch then -110 else -96)
				f.Size = if isTouch then UDim2.new(0.9, 0, 0, 52) else UDim2.fromOffset(460, 52)
				f.BorderSizePixel = 0
				f.ZIndex = 75
				corner(f, 8)
				local stroke = Instance.new("UIStroke")
				stroke.Name = "Stroke"
				stroke.Thickness = 1.4
				stroke.Parent = f
				local lab = Instance.new("TextLabel")
				lab.Name = "Text"
				lab.BackgroundTransparency = 1
				lab.Position = UDim2.fromOffset(10, 0)
				lab.Size = UDim2.new(1, -20, 1, 0)
				lab.Font = Enum.Font.GothamBold
				lab.TextScaled = true
				lab.TextColor3 = Color3.fromRGB(245, 245, 240)
				lab.TextStrokeTransparency = 0.35
				lab.ZIndex = 76
				lab.Parent = f
				local limit = Instance.new("UITextSizeConstraint")
				limit.MinTextSize = if isTouch then 14 else 11
				limit.MaxTextSize = if isTouch then 15 else 14
				limit.Parent = lab
				local barBg = Instance.new("Frame")
				barBg.Name = "Bar"
				barBg.AnchorPoint = Vector2.new(0.5, 1)
				barBg.Position = UDim2.new(0.5, 0, 1, -6)
				barBg.Size = UDim2.new(1, -24, 0, 6)
				barBg.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
				barBg.BorderSizePixel = 0
				barBg.ZIndex = 76
				barBg.Visible = false
				barBg.Parent = f
				corner(barBg, 3)
				local fill = Instance.new("Frame")
				fill.Name = "Fill"
				fill.Size = UDim2.fromScale(0, 1)
				fill.BorderSizePixel = 0
				fill.ZIndex = 77
				fill.Parent = barBg
				corner(fill, 3)
				f.Parent = host
				chip = f
				frame = f
			end
			local f = frame :: Frame
			f:SetAttribute("WE_Phase", phase)
			f.BackgroundColor3 = style.Bg
			local stroke = f:FindFirstChild("Stroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = style.Stroke
			end
			local lab = f:FindFirstChild("Text")
			local barBg = f:FindFirstChild("Bar")
			if lab and lab:IsA("TextLabel") then
				lab.Text = phaseText(payload, phase)
				lab.Size = if style.Bar then UDim2.new(1, -20, 1, -14) else UDim2.new(1, -20, 1, 0)
			end
			if barBg and barBg:IsA("Frame") then
				barBg.Visible = style.Bar
				local fill = barBg:FindFirstChild("Fill")
				if fill and fill:IsA("Frame") then
					local need = tonumber(payload.HoldNeed) or 0
					local pct = if need > 0 then math.clamp((tonumber(payload.HoldProgress) or 0) / need, 0, 1) else 0
					fill.Size = UDim2.fromScale(pct, 1)
					fill.BackgroundColor3 = style.Stroke
				end
			end
			hideLater(f, style.Hold)
		end

		local function showAtmRaidHud(payload: any)
			if typeof(payload) ~= "table" then
				return
			end
			local host = screenGui
			if not host then
				return
			end
			local phase = (payload :: any).Phase
			local style = if typeof(phase) == "string" then PHASE_STYLE[phase] else nil
			if style then
				showPhaseChip(payload, host, phase :: string, style)
			elseif phase == nil then
				showLegacyAtmRaidHud(payload, host)
			end
		end

		Remotes.BindEvent(Constants.RemoteNames.AtmRaidStateUpdate, function(payload: any)
			task.defer(function()
				if not screenGui then
					task.wait(0.2)
				end
				showAtmRaidHud(payload)
			end)
		end)
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

--[[ v69: open on a tab ("Supply" | "Weapons"). The Armory terminal lands on Weapons via PromptTriggered. ]]
function ShopController.OpenTab(tab: string)
	selectTab(tab)
	setOpen(true)
end

function ShopController.OpenWeapons()
	ShopController.OpenTab("Weapons")
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
