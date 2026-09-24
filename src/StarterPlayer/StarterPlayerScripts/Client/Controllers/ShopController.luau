--!strict
--[[ Phase 7 — Shop UI. Prompts Marketplace; grants only via server ProcessReceipt / GamePass ownership.
	v69: two tabs — SUPPLY (Robux DevProducts / GamePasses) and WEAPONS (in-game Cash, WeaponConfig). WEAPONS
	rows fire RequestPurchaseWeapon / RequestEquipWeapon with the weapon id only; CombatService prices,
	level-checks, rate-limits and grants. The Armory terminal (WE_OpenPanel "Shop", weapons prompt) opens the
	WEAPONS tab. One-time DevProducts (MonetizationConfig OneTime) show OWNED once owned and are never
	re-prompted.
	v70 "clean screen" (spec §3.3 / §3.4 / §3.8 / §4.3):
	  * A registered Modal panel (HudLayout id "Shop") with the black dim; one HUD scale + safe area; every
	    tappable ≥ 44 real px on touch. Gold (> 0) shows in the header (it left the cash pill).
	  * OpenCashPacks(): the cash pill's + opens the SUPPLY tab with the Cash Pack Mega row highlighted.
	  * The seven upsell cards (StarterBundleToast, AutoCollectToast, DoubleCashToast, VIPToast, SpeedBoostToast,
	    CashMegaToast, DeathShopToast) are thin wrappers around NotificationController.ShowOffer — ONE throttled
	    offer toast in the top-centre stack. OnGet = the same promptDevProduct / promptGamePass as before.
	  * AtmRaidHud is the TopStack "Progress" pill (was a full-width chip over the jump button). ]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local NotificationController = require(script.Parent.NotificationController)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local HudIcons = require(script.Parent.Parent.Modules.HudIcons)
local PanelShell = require(script.Parent.Parent.Modules.PanelShell)

local ShopController = {}

local PANEL_ID = "Shop"

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local menuOpen = false
local pendingCashMegaHighlight = false
local shopListFrame: ScrollingFrame? = nil
local screenGui: ScreenGui? = nil
local shell: PanelShell.Shell? = nil
local goldChip: Frame? = nil
local goldText: TextLabel? = nil
-- UserOwnsGamePassAsync results (refreshed every 20 s by the premium-pad block); read without yielding
local ownedCache: { [string]: boolean } = {}

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

--[[ v70: a GamePass is known owned (display / offer gating only): bought this session, replicated by the server
	(WE_Ent_<passKey>, MonetizationService), or a cached UserOwnsGamePassAsync hit. Never yields. ]]
local function passOwnedKnown(passKey: string): boolean
	if sessionOwnedPasses[passKey] == true then
		return true
	end
	if player:GetAttribute("WE_Ent_" .. passKey) == true then
		return true
	end
	return ownedCache[passKey] == true
end

--[[ v70 (spec §4.3): every upsell goes through ONE offer toast (throttled / deferred by NotificationController). ]]
type OfferDef = { Key: string, Title: string, Sub: string?, Cta: string, OnGet: () -> () }
local function showOffer(def: OfferDef): boolean
	local fn = (NotificationController :: any).ShowOffer
	if typeof(fn) ~= "function" then
		return false
	end
	local ok, shown = pcall(fn, def)
	return ok and shown == true
end

local function ctaFor(robux: number?): string
	return if robux and robux > 0 then string.format("GET R$ %d", robux) else "GET"
end

local function refreshGold()
	local chip, lab = goldChip, goldText
	if not (chip and lab) then
		return
	end
	local g = math.floor(tonumber(player:GetAttribute("WE_Gold")) or 0)
	chip.Visible = g > 0
	lab.Text = formatCash(g) .. " GOLD"
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
	local found = row:FindFirstChildOfClass("UIStroke")
	local stroke: UIStroke = found or Instance.new("UIStroke")
	stroke.Parent = row
	stroke.Color = Constants.Colors.Gold
	stroke.Thickness = 2.5
	-- Scroll to top (CashMega is first)
	if list:IsA("ScrollingFrame") then
		list.CanvasPosition = Vector2.new(0, 0)
	end
	task.delay(4, function()
		if row.Parent then
			row.BackgroundColor3 = Constants.Colors.Background
			if stroke.Parent then
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
	local sh = shell
	if sh then
		sh.Sync(open)
	end
	if open then
		refreshGold()
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

	-- v30 → v70: PvP death → ONE offer toast (DoubleCash GP / SpeedBoost DP …), no longer a card with a button
	-- per product. DEATH_TOAST_DEBOUNCE stays the client floor; HudConfig.Offer.DeathOfferMinGapSeconds (the
	-- "^Death" offer key) is the real cap. v35 continuity kept: the next Shop open highlights ShopRow_CashMega.
	do
		local lastDeathToastAt = -math.huge
		local DEATH_TOAST_DEBOUNCE = 10

		local function resolveOfferPrompt(key: string): (string?, string?, number?, string?)
			-- Prefer live GamePass, then live DevProduct (DoubleCash is GP; SpeedBoost is DP)
			local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses[key]
			if gp and typeof(gp.Id) == "number" and gp.Id ~= 0 then
				if passOwnedKnown(key) then
					return nil, nil, nil, nil
				end
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

		-- the first live, not-owned offer of the server's list becomes the death offer toast
		local function DeathShopToast(offerKeys: { string }): boolean
			local now = os.clock()
			if now - lastDeathToastAt < DEATH_TOAST_DEBOUNCE then
				return false
			end
			for _, key in ipairs(offerKeys) do
				local kind, k, _, name = resolveOfferPrompt(key)
				if kind and k and name then
					lastDeathToastAt = now
					local def: any = if kind == "GamePass"
						then (MonetizationConfig.GamePasses :: any)[k]
						else (MonetizationConfig.DevProducts :: any)[k]
					local robux = if typeof(def) == "table" then tonumber(def.RobuxPrice) else nil
					local desc = if typeof(def) == "table" and typeof(def.Description) == "string" then def.Description else nil
					pendingCashMegaHighlight = true -- v35: CashMega highlight if the shop opens next
					local offerKind, offerKey = kind, k
					return showOffer({
						Key = "DeathShopToast",
						Title = "Back stronger: " .. name,
						Sub = desc or "Boost after death",
						Cta = ctaFor(robux),
						OnGet = function()
							if offerKind == "GamePass" then
								promptGamePass(offerKey)
							else
								promptDevProduct(offerKey)
							end
						end,
					})
				end
			end
			return false
		end

		-- DeathShopOffer never blocks Init (BindEvent connects when the remote appears)
		Remotes.BindEvent(Constants.RemoteNames.DeathShopOffer, function(payload: any)
			local offers = if typeof(payload) == "table" then (payload :: any).Offers else nil
			if typeof(offers) ~= "table" then
				offers = (MonetizationConfig :: any).DeathShopOffers or { "DoubleCash", "SpeedBoost" }
			end
			DeathShopToast(offers :: { string })
		end)
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireShop"
	screen.DisplayOrder = 60 -- above HUD dock (55); panels must not open behind HUD
	-- v70: one HUD scale + the safe area (HudLayout.ApplyScreen via PanelShell); DisplayOrder stays Panels = 60
	PanelShell.Screen(screen, HudConfig.DisplayOrder.Panels)
	screen.Parent = player:WaitForChild("PlayerGui")
	screenGui = screen

	local TAP = PanelShell.TouchMinV()
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.94, 0, 1, -16) else UDim2.fromOffset(480, 520)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = screen
	corner(panel, 12)
	do
		local cap = Instance.new("UISizeConstraint")
		cap.MaxSize = if isTouch then Vector2.new(900, 620) else Vector2.new(480, 520)
		cap.Parent = panel
	end

	local title = PanelShell.Title(panel, "Supply Depot")
	panelTitle = title

	-- v70: Gold left the cash pill; it shows here, only while the player has any (WE_Gold / EconomyUpdate)
	do
		local goldSize = PanelShell.Text(18)
		local chip = Instance.new("Frame")
		chip.Name = "Gold"
		chip.AnchorPoint = Vector2.new(1, 0.5)
		chip.Position = UDim2.new(1, -(TAP + 12), 0, title.Position.Y.Offset + title.Size.Y.Offset / 2)
		chip.Size = UDim2.fromOffset(170, goldSize + 12)
		chip.BackgroundTransparency = 1
		chip.Visible = false
		chip.Parent = panel
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Right
		lay.VerticalAlignment = Enum.VerticalAlignment.Center
		lay.Padding = UDim.new(0, 6)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = chip
		HudIcons.Make("Dot", chip, {
			Size = UDim2.fromOffset(goldSize - 2, goldSize - 2),
			LayoutOrder = 1,
			Color = HudConfig.Colors.Gold,
			Fill = Constants.Colors.Panel,
		})
		local lab = Instance.new("TextLabel")
		lab.Name = "Amount"
		lab.LayoutOrder = 2
		lab.BackgroundTransparency = 1
		lab.Size = UDim2.fromOffset(0, goldSize + 6)
		lab.AutomaticSize = Enum.AutomaticSize.X -- the dot hugs the number
		lab.Font = HudConfig.Fonts.Display
		lab.TextSize = goldSize
		lab.TextColor3 = HudConfig.Colors.Gold
		lab.TextXAlignment = Enum.TextXAlignment.Right
		lab.Text = "0 GOLD"
		lab.Parent = chip
		UIUtil.TextOutline(lab, 1.5)
		goldChip = chip
		goldText = lab
	end

	PanelShell.CloseButton(panel, function()
		setOpen(false)
	end)

	-- v69: SUPPLY / WEAPONS tabs under the title (the close button keeps the top-right corner)
	local tabTop = TAP + 8
	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.Position = UDim2.fromOffset(12, tabTop)
	tabBar.Size = UDim2.new(1, -24, 0, TAP)
	tabBar.Parent = panel
	local function makeTab(name: string, text: string, index: number)
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. name
		b.Position = UDim2.new((index - 1) * 0.5, if index == 1 then 0 else 4, 0, 0)
		b.Size = UDim2.new(0.5, -4, 1, 0) -- TAP tall: a full touch target without EnsureMinTouch
		b.BackgroundColor3 = Constants.Colors.Gunmetal
		b.Font = Enum.Font.GothamBold
		b.TextSize = PanelShell.Text(13)
		b.TextColor3 = Constants.Colors.Muted
		b.Text = text
		b.BorderSizePixel = 0
		b.Active = true
		corner(b, 8)
		b.Parent = tabBar
		b.Activated:Connect(function()
			selectTab(name)
		end)
		tabButtons[name] = b
	end
	makeTab("Supply", "SUPPLY · R$", 1)
	makeTab("Weapons", "WEAPONS · CASH", 2)

	local listTop = tabTop + TAP + 8
	local noteSize = PanelShell.Text(11)
	local function makeList(name: string, noteText: string): ScrollingFrame
		local l = Instance.new("ScrollingFrame")
		l.Name = "List_" .. name
		l.Position = UDim2.fromOffset(12, listTop)
		l.Size = UDim2.new(1, -24, 1, -(listTop + 12))
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.ScrollBarThickness = if isTouch then 6 else 4
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
		n.Size = UDim2.new(1, -8, 0, noteSize * 2 + 6)
		n.Font = Enum.Font.GothamMedium
		n.TextSize = noteSize
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
		"Weapons cost in-game Cash. EQUIP owned weapons here; draw them from the hotbar (tap a slot or press 1-4)."
	)
	selectTab(activeTab)

	local rowBtnH = if isTouch then TAP else 48
	local rowBtnW = if isTouch then 140 else 100
	local rowTitleSize = PanelShell.Text(14)
	local rowSubSize = PanelShell.Text(11)
	local function buildRow(parentList: ScrollingFrame, layoutOrder: number, rowName: string, label: string, sub: string, btnText: string): (Frame, TextLabel, TextButton)
		local row = Instance.new("Frame")
		row.Name = "ShopRow_" .. rowName
		row.Size = UDim2.new(1, -8, 0, math.max(rowBtnH + 10, rowTitleSize + rowSubSize + 22))
		row.BackgroundColor3 = Constants.Colors.Background
		row.BorderSizePixel = 0
		row.LayoutOrder = layoutOrder
		row.Parent = parentList
		corner(row, 8)

		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(12, 7)
		t.Size = UDim2.new(1, -(rowBtnW + 30), 0, rowTitleSize + 4)
		t.Font = Enum.Font.GothamBold
		t.TextSize = rowTitleSize
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.TextColor3 = Constants.Colors.Text
		t.Text = label
		t.Parent = row

		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromOffset(12, 7 + rowTitleSize + 6)
		s.Size = UDim2.new(1, -(rowBtnW + 30), 0, rowSubSize + 4)
		s.Font = Enum.Font.GothamMedium
		s.TextSize = rowSubSize
		s.TextXAlignment = Enum.TextXAlignment.Left
		s.TextColor3 = Constants.Colors.Muted
		s.TextTruncate = Enum.TextTruncate.AtEnd
		s.Text = sub
		s.Parent = row

		local btn = Instance.new("TextButton")
		btn.Name = "Action"
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, -8, 0.5, 0)
		btn.Size = UDim2.fromOffset(rowBtnW, rowBtnH)
		btn.BackgroundColor3 = Constants.Colors.Gunmetal
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = PanelShell.Text(12)
		btn.TextColor3 = Color3.fromRGB(255, 248, 230)
		btn.Text = btnText
		btn.BorderSizePixel = 0
		btn.Active = true
		corner(btn, 8)
		local btnStroke = Instance.new("UIStroke")
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		btnStroke.Color = Constants.Colors.Gold
		btnStroke.Thickness = 1.25
		btnStroke.Parent = btn
		btn.Parent = row
		UIUtil.EnsureMinTouch(btn, rowBtnH)
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
			sub = "+$" .. formatCash(def.Cash) .. " Cash"
		elseif def.Gold and def.Gold > 0 then
			sub = "+" .. formatCash(def.Gold) .. " Gold"
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
			if passOwnedKnown(key) then
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
			-- v69: Shop pass rows show OWNED too (session purchases / WE_Ent_<pass> stay OWNED even if the check lags)
			for key, r in pairs(passRows) do
				if passOwnedKnown(key) or queryOwnsGamePass(key) then
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


	-- v32 → v70: one-shot StarterBundle soft offer (server fires once per profile) → ONE offer toast
	do
		local lastStarterToastAt = -math.huge
		local STARTER_TOAST_DEBOUNCE = 30

		local function StarterBundleToast(payload: any): boolean
			local now = os.clock()
			if now - lastStarterToastAt < STARTER_TOAST_DEBOUNCE then
				return false
			end
			local def = (MonetizationConfig.DevProducts :: any).StarterBundle
			if typeof(def) ~= "table" or (tonumber(def.Id) or 0) == 0 or isOneTimeOwned("StarterBundle") then
				return false
			end
			lastStarterToastAt = now
			local p: any = if typeof(payload) == "table" then payload else {}
			local displayName = tostring(p.DisplayName or def.DisplayName or "Starter Bundle")
			local robux = tonumber(p.RobuxPrice) or tonumber(def.RobuxPrice)
			return showOffer({
				Key = "StarterBundleToast",
				Title = "Jumpstart your base",
				Sub = displayName,
				Cta = ctaFor(robux),
				OnGet = function()
					-- PromptProductPurchase only — grants via ProcessReceipt
					promptDevProduct("StarterBundle")
				end,
			})
		end

		Remotes.BindEvent(Constants.RemoteNames.StarterBundleOffer, StarterBundleToast)
	end

	-- v33 → v70: one-shot AutoCollect soft offer after the first manual ATM collect
	do
		local lastAcToastAt = -math.huge
		local AC_TOAST_DEBOUNCE = 30

		local function AutoCollectToast(payload: any): boolean
			local now = os.clock()
			if now - lastAcToastAt < AC_TOAST_DEBOUNCE then
				return false
			end
			local def = (MonetizationConfig.GamePasses :: any).AutoCollect
			if typeof(def) ~= "table" or typeof(def.Id) ~= "number" or def.Id == 0 or passOwnedKnown("AutoCollect") then
				return false
			end
			lastAcToastAt = now
			local p: any = if typeof(payload) == "table" then payload else {}
			return showOffer({
				Key = "AutoCollectToast",
				Title = "Skip the walk to the ATM",
				Sub = tostring(p.DisplayName or def.DisplayName or "Auto Collect") .. " · collects for you",
				Cta = ctaFor(tonumber(p.RobuxPrice) or tonumber(def.RobuxPrice)),
				OnGet = function()
					promptGamePass("AutoCollect")
				end,
			})
		end

		Remotes.BindEvent(Constants.RemoteNames.AutoCollectOffer, AutoCollectToast)
	end

	-- v34 → v70: one-shot DoubleCash soft offer (existing GamePass Id only)
	do
		local lastDcToastAt = -math.huge
		local DC_TOAST_DEBOUNCE = 8.0

		local function DoubleCashToast(payload: any): boolean
			local now = os.clock()
			if now - lastDcToastAt < DC_TOAST_DEBOUNCE then
				return false
			end
			local def = (MonetizationConfig.GamePasses :: any).DoubleCash
			if typeof(def) ~= "table" or typeof(def.Id) ~= "number" or def.Id == 0 or passOwnedKnown("DoubleCash") then
				return false
			end
			lastDcToastAt = now
			local p: any = if typeof(payload) == "table" then payload else {}
			return showOffer({
				Key = "DoubleCashToast",
				Title = "Double all cash",
				Sub = tostring(p.DisplayName or def.DisplayName or "2x Cash") .. " · every payout, forever",
				Cta = ctaFor(tonumber(p.RobuxPrice) or tonumber(def.RobuxPrice)),
				OnGet = function()
					promptGamePass("DoubleCash")
				end,
			})
		end

		Remotes.BindEvent(Constants.RemoteNames.DoubleCashOffer, DoubleCashToast)
	end

	-- v35 → v70: one-shot VIP soft offer (existing GamePass Id only)
	do
		local lastVipToastAt = -math.huge
		local VIP_TOAST_DEBOUNCE = 12.0

		local function VIPToast(payload: any): boolean
			local now = os.clock()
			if now - lastVipToastAt < VIP_TOAST_DEBOUNCE then
				return false
			end
			local def = (MonetizationConfig.GamePasses :: any).VIP
			if typeof(def) ~= "table" or typeof(def.Id) ~= "number" or def.Id == 0 or passOwnedKnown("VIP") then
				return false
			end
			lastVipToastAt = now
			local p: any = if typeof(payload) == "table" then payload else {}
			return showOffer({
				Key = "VIPToast",
				Title = "Go " .. tostring(p.DisplayName or def.DisplayName or "VIP"),
				Sub = "+25% cash · prestige presence",
				Cta = ctaFor(tonumber(p.RobuxPrice) or tonumber(def.RobuxPrice)),
				OnGet = function()
					promptGamePass("VIP")
				end,
			})
		end

		Remotes.BindEvent(Constants.RemoteNames.VIPOffer, VIPToast)
	end

	-- v36 → v70: one-shot SpeedBoost soft offer (existing DevProduct Id only; never for an owner)
	do
		local lastSbToastAt = -math.huge
		local SB_TOAST_DEBOUNCE = 12.0

		local function SpeedBoostToast(payload: any): boolean
			local now = os.clock()
			if now - lastSbToastAt < SB_TOAST_DEBOUNCE then
				return false
			end
			local def = (MonetizationConfig.DevProducts :: any).SpeedBoost
			if typeof(def) ~= "table" or typeof(def.Id) ~= "number" or def.Id == 0 or isOneTimeOwned("SpeedBoost") then
				return false
			end
			lastSbToastAt = now
			local p: any = if typeof(payload) == "table" then payload else {}
			return showOffer({
				Key = "SpeedBoostToast",
				Title = tostring(p.DisplayName or def.DisplayName or "Speed Boost"),
				Sub = if typeof(def.Description) == "string" and def.Description ~= "" then def.Description else "Run faster across the map",
				Cta = ctaFor(tonumber(p.RobuxPrice) or tonumber(def.RobuxPrice)),
				OnGet = function()
					promptDevProduct("SpeedBoost")
				end,
			})
		end

		Remotes.BindEvent(Constants.RemoteNames.SpeedBoostOffer, SpeedBoostToast)
	end

	-- v37 → v70: one-shot CashMega soft offer (existing DevProduct Id only) — "BEST OFFER"
	do
		local lastMegaToastAt = -math.huge
		local MEGA_TOAST_DEBOUNCE = 14.0

		local function CashMegaToast(payload: any): boolean
			local now = os.clock()
			if now - lastMegaToastAt < MEGA_TOAST_DEBOUNCE then
				return false
			end
			local def = (MonetizationConfig.DevProducts :: any).CashMega
			if typeof(def) ~= "table" or typeof(def.Id) ~= "number" or def.Id == 0 then
				return false
			end
			lastMegaToastAt = now
			local p: any = if typeof(payload) == "table" then payload else {}
			local cashAmount = tonumber(def.Cash) or 0
			return showOffer({
				Key = "CashMegaToast",
				Title = "★ BEST OFFER",
				Sub = tostring(p.DisplayName or def.DisplayName or "Cash Pack Mega")
					.. (if cashAmount > 0 then " · +$" .. formatCash(cashAmount) else ""),
				Cta = ctaFor(tonumber(p.RobuxPrice) or tonumber(def.RobuxPrice)),
				OnGet = function()
					pendingCashMegaHighlight = true
					promptDevProduct("CashMega")
				end,
			})
		end

		Remotes.BindEvent(Constants.RemoteNames.CashMegaOffer, CashMegaToast)
	end

	-- v33 → v70: ATM raid hold / cooldown / result → the TopStack "Progress" pill (spec §3.4; it was a full-width
	-- chip over the jump button). ONE persistent pill (Frame "AtmRaidHud", its own gui "WarEmpireAtmRaid" at the
	-- bank-raid z) that HudLayout.RegisterTopStack places under the topbar and collapses while hidden. v69
	-- payloads carry Phase: Holding / Alarm show a live bar and hide shortly after the last push; Interrupted /
	-- Blocked / Defended / Success / Robbed show the server's payload.Text for a few seconds. No Phase = legacy v33.
	do
		local P = HudConfig.TopStack.Progress
		local pill: Frame? = nil
		local hideToken = 0

		type PhaseStyle = { Stroke: Color3, Text: Color3, Hold: number, Bar: boolean }
		local AMBER: PhaseStyle = { Stroke = P.ContestedColor, Text = Color3.fromRGB(255, 226, 170), Hold = 2.5, Bar = false }
		local GREEN: PhaseStyle = { Stroke = Color3.fromRGB(120, 220, 140), Text = Color3.fromRGB(200, 255, 210), Hold = 2.5, Bar = false }
		local PHASE_STYLE: { [string]: PhaseStyle } = {
			Holding = { Stroke = Color3.fromRGB(230, 200, 80), Text = Color3.fromRGB(255, 255, 255), Hold = 1.0, Bar = true }, -- thief
			Alarm = { Stroke = Color3.fromRGB(255, 96, 84), Text = Color3.fromRGB(255, 205, 200), Hold = 1.5, Bar = true }, -- victim
			Interrupted = AMBER,
			Blocked = AMBER,
			Defended = GREEN,
			Success = { Stroke = GREEN.Stroke, Text = GREEN.Text, Hold = 5, Bar = false },
			Robbed = { Stroke = Color3.fromRGB(255, 96, 84), Text = Color3.fromRGB(255, 205, 200), Hold = 6, Bar = false },
		}

		local function ensurePill(): Frame?
			local existing = pill
			if existing and existing.Parent then
				return existing
			end
			local pg = player:FindFirstChildOfClass("PlayerGui")
			if not pg then
				return nil
			end
			local gui = Instance.new("ScreenGui")
			gui.Name = "WarEmpireAtmRaid"
			HudLayout.ApplyScreen(gui, { DisplayOrder = HudConfig.DisplayOrder.WarEmpireBankRaid, Insets = "Core" })
			gui.Parent = pg

			local f = Instance.new("Frame")
			f.Name = "AtmRaidHud"
			f.AnchorPoint = Vector2.new(0.5, 0)
			f.Position = UDim2.new(0.5, 0, 0, HudConfig.TopStack.Top)
			f.Size = UDim2.fromOffset(P.Size.X, P.Size.Y)
			f.BackgroundColor3 = HudConfig.Colors.PillBg
			f.BackgroundTransparency = 0.12
			f.BorderSizePixel = 0
			f.Visible = false
			f.Active = false
			corner(f, 12)
			local stroke = Instance.new("UIStroke")
			stroke.Name = "Stroke"
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Thickness = 2
			stroke.Parent = f

			local lab = Instance.new("TextLabel")
			lab.Name = "Text"
			lab.BackgroundTransparency = 1
			lab.Font = HudConfig.Fonts.Body
			lab.TextSize = P.TextSize
			lab.TextXAlignment = Enum.TextXAlignment.Left
			lab.TextTruncate = Enum.TextTruncate.AtEnd
			lab.TextColor3 = HudConfig.Colors.White
			lab.Parent = f
			UIUtil.TextOutline(lab, 1.2)

			local pct = Instance.new("TextLabel")
			pct.Name = "Pct"
			pct.BackgroundTransparency = 1
			pct.AnchorPoint = Vector2.new(1, 0)
			pct.Position = UDim2.new(1, -12, 0, 3)
			pct.Size = UDim2.fromOffset(56, P.TextSize + 6)
			pct.Font = HudConfig.Fonts.Display
			pct.TextSize = P.TextSize + 2
			pct.TextXAlignment = Enum.TextXAlignment.Right
			pct.TextColor3 = HudConfig.Colors.White
			pct.Text = ""
			pct.Parent = f
			UIUtil.TextOutline(pct, 1.2)

			local barBg = Instance.new("Frame")
			barBg.Name = "Bar"
			barBg.AnchorPoint = Vector2.new(0.5, 1)
			barBg.Position = UDim2.new(0.5, 0, 1, -7)
			barBg.Size = UDim2.new(1, -24, 0, P.BarH)
			barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			barBg.BackgroundTransparency = 0.45
			barBg.BorderSizePixel = 0
			barBg.Visible = false
			barBg.Parent = f
			corner(barBg, P.BarH // 2)
			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.Size = UDim2.fromScale(0, 1)
			fill.BorderSizePixel = 0
			fill.Parent = barBg
			corner(fill, P.BarH // 2)

			f.Parent = gui
			HudLayout.RegisterTopStack("AtmRaid", f, HudConfig.TopStack.Order.Progress, { Space = "Hud" })
			pill = f
			return f
		end

		local function hideLater(frame: Frame, seconds: number)
			hideToken += 1
			local token = hideToken
			task.delay(seconds, function()
				if token == hideToken and pill == frame then
					frame.Visible = false
				end
			end)
		end

		-- paint the pill: text, optional bar fraction, colours; auto width (Progress.Size.X … the stack's max)
		local function showPill(text: string, style: PhaseStyle, fraction: number?)
			local f = ensurePill()
			if not f then
				return
			end
			local lab = f:FindFirstChild("Text")
			local pct = f:FindFirstChild("Pct")
			local barBg = f:FindFirstChild("Bar")
			local stroke = f:FindFirstChild("Stroke")
			local withBar = style.Bar and fraction ~= nil
			local pctW = if withBar then 60 else 0
			local textW = P.Size.X
			pcall(function()
				textW = TextService:GetTextSize(text, P.TextSize, HudConfig.Fonts.Body, Vector2.new(4000, 100)).X
			end)
			local maxW = math.max(P.Size.X, HudLayout.TopStackMaxWidthV())
			local w = math.clamp(math.ceil(textW * 1.06) + 24 + pctW, P.Size.X, maxW)
			f.Size = UDim2.fromOffset(w, P.Size.Y)
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = style.Stroke
			end
			if lab and lab:IsA("TextLabel") then
				lab.Text = text
				lab.TextColor3 = style.Text
				if withBar then
					lab.Position = UDim2.fromOffset(12, 4)
					lab.Size = UDim2.new(1, -(24 + pctW), 0, P.TextSize + 6)
				else
					lab.Position = UDim2.fromOffset(12, 0)
					lab.Size = UDim2.new(1, -24, 1, 0)
				end
			end
			if pct and pct:IsA("TextLabel") then
				pct.Visible = withBar
				pct.Text = if withBar and fraction then string.format("%d%%", math.floor(fraction * 100 + 0.5)) else ""
			end
			if barBg and barBg:IsA("Frame") then
				barBg.Visible = withBar
				local fill = barBg:FindFirstChild("Fill")
				if fill and fill:IsA("Frame") then
					fill.Size = UDim2.fromScale(math.clamp(fraction or 0, 0, 1), 1)
					fill.BackgroundColor3 = style.Stroke
				end
			end
			f.Visible = true
			hideLater(f, style.Hold)
		end

		-- legacy (no Phase): the v33 texts
		local function showLegacyAtmRaidHud(payload: any)
			local success = (payload :: any).Success == true
			local raided = (payload :: any).Raided == true
			local cd = math.max(0, math.floor(tonumber((payload :: any).CooldownRemaining) or 0))
			local stolen = math.floor(tonumber((payload :: any).Stolen) or 0)
			local victim = tostring((payload :: any).VictimName or "")
			local text: string
			if success then
				text = string.format("ATM RAID +$%s%s · cooldown 1m", formatCash(stolen), if victim ~= "" then (" from " .. victim) else "")
			elseif raided then
				local thief = tostring((payload :: any).ThiefName or "")
				if thief ~= "" then
					text = string.format("ATM RAIDED −10%% by %s (−$%s)", thief, formatCash(stolen))
				else
					text = string.format("ATM RAIDED −10%% (−$%s)", formatCash(stolen))
				end
			else
				text = string.format("ATM raid cooldown — %ds", cd)
			end
			local base = if success then GREEN elseif raided then PHASE_STYLE.Robbed else AMBER
			local hold = if success or raided then 5.5 else math.clamp(cd, 2, 8)
			showPill(text, { Stroke = base.Stroke, Text = base.Text, Hold = hold, Bar = false }, nil)
		end

		local function phaseText(payload: any, phase: string): string
			local text = if typeof(payload.Text) == "string" and payload.Text ~= "" then payload.Text else nil
			local progress = tonumber(payload.HoldProgress)
			local need = tonumber(payload.HoldNeed)
			if phase == "Holding" then
				return text or string.format("ROBBING %s's ATM — don't get hit!", tostring(payload.VictimName or "their"))
			elseif phase == "Alarm" then
				local base = text or string.format("%s is robbing your ATM!", tostring(payload.ThiefName or "Someone"))
				if progress and need and not string.find(base, "%d/%d") then
					base ..= string.format(" %d/%ds", math.floor(progress), math.floor(need))
				end
				return base
			end
			return text or tostring(payload.Reason or phase)
		end

		local function showAtmRaidHud(payload: any)
			if typeof(payload) ~= "table" then
				return
			end
			local phase = (payload :: any).Phase
			local style = if typeof(phase) == "string" then PHASE_STYLE[phase] else nil
			if style then
				local need = tonumber(payload.HoldNeed) or 0
				local fraction = if need > 0 then math.clamp((tonumber(payload.HoldProgress) or 0) / need, 0, 1) else nil
				showPill(phaseText(payload, phase :: string), style, fraction)
			elseif phase == nil then
				showLegacyAtmRaidHud(payload)
			end
		end

		Remotes.BindEvent(Constants.RemoteNames.AtmRaidStateUpdate, showAtmRaidHud)
	end

	-- ATM-cluster premium pads → PromptGamePass / PromptProduct (server-validated)
	Remotes.BindEvent(Constants.RemoteNames.PromptPremiumPad, function(payload: any)
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

	if order == 0 then
		UIUtil.EmptyState(list, "Shop catalog empty — MonetizationConfig has no DevProducts / GamePasses.", 0)
	end

	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = screen,
		Panel = panel,
		IsOpen = function(): boolean
			return menuOpen
		end,
		Close = function()
			setOpen(false)
		end,
	})

	-- Gold in the header (WE_Gold replicates from the server; EconomyUpdate as a backup)
	player:GetAttributeChangedSignal("WE_Gold"):Connect(refreshGold)
	Remotes.BindEvent(Constants.RemoteNames.EconomyUpdate, function(payload: any)
		if typeof(payload) == "table" and typeof(payload.Gold) == "number" and player:GetAttribute("WE_Gold") == nil then
			local chip, lab = goldChip, goldText
			if chip and lab then
				chip.Visible = payload.Gold > 0
				lab.Text = formatCash(payload.Gold) .. " GOLD"
			end
		end
	end)
	refreshGold()

	local shopKey: Enum.KeyCode = HudConfig.Keys.Shop or Enum.KeyCode.P
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == shopKey then
			setOpen(not menuOpen)
		end
	end)
end





function ShopController.Toggle()
	-- the tap that just closed the Shop through its dim lands on the Shop tile too: stay closed
	local sh = shell
	if not menuOpen and sh and sh.TapThrough() then
		return
	end
	setOpen(not menuOpen)
end

--[[ v70: the cash pill's + (HUDController.BindShopOpener → UIController): SUPPLY tab, Cash Pack Mega highlighted.
	Visual only — no toast, no purchase prompt. ]]
function ShopController.OpenCashPacks()
	pendingCashMegaHighlight = true
	setOpen(true)
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
