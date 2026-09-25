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
	  * AtmRaidHud is the TopStack "Progress" pill (was a full-width chip over the jump button).
	Owner's 11 features, lane S (spec_f11 F1 / F2 / F8 / F9):
	  * OWNED comes only from the server (player attribute WE_Ent_<key>, MonetizationService) or a purchase made
	    this session; the client never asks Roblox about pass ownership itself. The ATM pads (and the golden pump
	    pad) read OWNED for game passes AND Developer Products, including a slot's OwnedIfAny keys (the Speed pad:
	    Speed Pass or Speed Boost) and entitlements another product granted (Auto Collect from the Starter Pack).
	  * Nothing prompts while an Id is 0: Id 0 passes get no Shop row, and promptGamePass / promptDevProduct stop
	    at Id 0 before any remote or Roblox prompt. An owned pass shows "Already owned" instead of a prompt.
	  * Every prompt forwards its source (shop, hud_plus, pad, offer, starter_offer, death_card; analytics only).
	  * Cash Pack Mega is a permanent hero row (gold stroke, taller, bigger title). VIP stays a Shop row.
	  * The one PvP death offer is the Speed Pass (MonetizationConfig.DeathSpeedOffer), never shown to a player
	    who owns any of its SkipIfOwnsAny keys. ]]

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
-- F2: where the Shop was opened from (the purchase source its rows send): "hud_plus" from the cash "+", else "shop"
local openSource = "shop"

-- v69: tabs
local panelTitle: TextLabel? = nil
local tabLists: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local activeTab = "Supply"
local TAB_TITLES: { [string]: string } = { Supply = "Supply Depot", Weapons = "Armory" }

-- F2: the permanent Cash Pack Mega hero row (gold stroke, 22 v taller, bigger gold title, gold BUY face)
local HERO_ROW_BG = Color3.fromRGB(46, 38, 18)
local HERO_ROW_STROKE = 2
local HERO_ROW_EXTRA_H = 22

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
local refreshPremiumPads: () -> () = function() end -- set in Init (F1: OWNED look of the world pads)
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

--[[ v70: a GamePass is known owned (display / offer gating only): bought this session, or replicated by the server
	(WE_Ent_<passKey>, MonetizationService: its join check, a confirmed purchase, or a saved entitlement).
	F1: no client-side ownership polling any more; the server attribute is the one source. Never yields. ]]
local function passOwnedKnown(passKey: string): boolean
	if sessionOwnedPasses[passKey] == true then
		return true
	end
	return player:GetAttribute("WE_Ent_" .. passKey) == true
end

--[[ F1: one key is owned (display only): a game pass or entitlement the server reports (WE_Ent_<key>), a one-time
	Developer Product (isOneTimeOwned), or the entitlement a Developer Product of that name grants. ]]
local function ownsKey(key: string): boolean
	if passOwnedKnown(key) or isOneTimeOwned(key) then
		return true
	end
	local dp = (MonetizationConfig.DevProducts :: any)[key]
	local ent = if typeof(dp) == "table" then dp.GrantEntitlement else nil
	return typeof(ent) == "string" and ent ~= "" and player:GetAttribute("WE_Ent_" .. ent) == true
end

local MAX_OWNED_KEYS = 8 -- same cap as PremiumPadService: a pad's OwnedIfAny attribute is read up to this many keys

local function isKeyName(v: any): boolean
	return typeof(v) == "string" and #v > 0 and #v <= 64 and string.match(v, "^[%w_]+$") ~= nil
end

--[[ F1: the extra keys whose ownership makes an offer read OWNED (the same rule as PremiumPadService.alreadyOwns):
	the pad's OwnedIfAny attribute (comma string, written by the server when it builds the pad) plus the OwnedIfAny of
	every MonetizationConfig.PremiumPads slot that sells this Kind + Key (MonetizationConfig.PadOwnedKeys). ]]
local function ownedIfAnyKeys(kind: string, key: string, part: Instance?): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(k: any)
		if #out < MAX_OWNED_KEYS and isKeyName(k) and not seen[k] then
			seen[k] = true
			table.insert(out, k)
		end
	end
	local attr = if part then part:GetAttribute("OwnedIfAny") else nil
	if typeof(attr) == "string" and #attr <= 512 then
		for _, k in ipairs(string.split(attr, ",")) do
			add(string.match(k, "^%s*(.-)%s*$"))
		end
	end
	local pads = (MonetizationConfig :: any).PremiumPads
	local slots = if typeof(pads) == "table" then pads.Slots else nil
	if typeof(slots) == "table" then
		for _, slot in ipairs(slots) do
			local offers = if typeof(slot) == "table" then slot.Offers else nil
			if typeof(offers) ~= "table" then
				continue
			end
			for _, offer in ipairs(offers) do
				if typeof(offer) == "table" and offer.Kind == kind and offer.Key == key then
					for _, k in ipairs(MonetizationConfig.PadOwnedKeys(slot)) do
						add(k)
					end
					break
				end
			end
		end
	end
	return out
end

--[[ F1: an offer (a pad, a pass row, a pass prompt) is owned: its own key, or any of its OwnedIfAny keys. The Speed
	Pass therefore reads OWNED for a Speed Boost owner (the higher multiplier wins, so the pass would add nothing).
	Developer Product Shop rows keep their own rule (isOneTimeOwned), so a Speed Pass owner can still buy Speed Boost. ]]
local function offerOwned(kind: string, key: string, part: Instance?): boolean
	if ownsKey(key) then
		return true
	end
	for _, k in ipairs(ownedIfAnyKeys(kind, key, part)) do
		if ownsKey(k) then
			return true
		end
	end
	return false
end

-- F8: owns any of these keys (DeathSpeedOffer.SkipIfOwnsAny)
local function ownsAnyKey(keys: any): boolean
	if typeof(keys) ~= "table" then
		return false
	end
	for _, k in ipairs(keys) do
		if isKeyName(k) and ownsKey(k) then
			return true
		end
	end
	return false
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
			-- F2: the hero row goes back to its permanent gold look, any other row to plain
			local hero = row:GetAttribute("WE_HeroRow") == true
			row.BackgroundColor3 = if hero then HERO_ROW_BG else Constants.Colors.Background
			if stroke.Parent then
				stroke.Thickness = if hero then HERO_ROW_STROKE else 0
			end
		end
	end)
end

-- source: the purchase source of this open (F2: "hud_plus" from the cash "+"); a fresh open without one is "shop"
local function setOpen(open: boolean, source: string?)
	if open then
		openSource = source or (if menuOpen then openSource else "shop")
	end
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

-- v71 money (M1): the optional 2nd arg of RequestPurchase* (analytics only; the server whitelists it, else "other")
local function cleanSource(source: string?): string
	return if typeof(source) == "string" and source ~= "" then source else "shop"
end

local function promptDevProduct(productKey: string, source: string?)
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
	-- Nothing prompts while the Id is 0 (the owner has not created the product yet): no intent, no Roblox sheet
	if (tonumber(def.Id) or 0) == 0 then
		toast("Coming soon", "Info")
		return
	end
	-- Ask server to log + validate; client still prompts Marketplace (v69: intent log never delays the prompt)
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseDevProduct, productKey, cleanSource(source))
	MarketplaceService:PromptProductPurchase(player, def.Id)
end

local function promptGamePass(passKey: string, source: string?)
	local def = MonetizationConfig.GamePasses[passKey]
	if not def then
		return
	end
	-- v69: HideFromShop passes (ExtraPlotCosmetic — theme not implemented) are never offered
	if (def :: any).HideFromShop == true then
		return
	end
	-- F1: an owned pass (or one whose OwnedIfAny key is owned: the Speed Pass for a Speed Boost owner) never prompts
	if offerOwned("GamePass", passKey) then
		toast("Already owned", "Info")
		queueRefresh()
		return
	end
	-- Nothing prompts while the Id is 0
	if (tonumber(def.Id) or 0) == 0 then
		toast("Coming soon", "Info")
		return
	end
	-- Log intent on server; NEVER treat client confirmation as a grant
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseGamePass, passKey, cleanSource(source))
	MarketplaceService:PromptGamePassPurchase(player, def.Id)
end

function ShopController.Init()

	-- v30 → v70: PvP death → ONE offer toast (DoubleCash GP / SpeedBoost DP …), no longer a card with a button
	-- per product. DEATH_TOAST_DEBOUNCE stays the client floor; HudConfig.Offer.DeathOfferMinGapSeconds (the
	-- "^Death" offer key) is the real cap. v35 continuity kept: the next Shop open highlights ShopRow_CashMega.
	do
		local lastDeathToastAt = -math.huge
		local DEATH_TOAST_DEBOUNCE = 10

		-- F8: MonetizationConfig.DeathSpeedOffer (the one death offer: the Speed Pass)
		local speedOffer: any = (MonetizationConfig :: any).DeathSpeedOffer
		local speedPassKey: string? = if typeof(speedOffer) == "table" and typeof(speedOffer.PassKey) == "string"
			then speedOffer.PassKey
			else nil

		local function resolveOfferPrompt(key: string): (string?, string?, number?, string?)
			-- F8: never offer the Speed Pass to a player who owns any SkipIfOwnsAny key (Speed Pass or Speed Boost)
			if key == speedPassKey and ownsAnyKey(speedOffer.SkipIfOwnsAny) then
				return nil, nil, nil, nil
			end
			-- Prefer live GamePass, then live DevProduct (DoubleCash is GP; SpeedBoost is DP)
			local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses[key]
			if gp and typeof(gp.Id) == "number" and gp.Id ~= 0 then
				if offerOwned("GamePass", key) then
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
					local title = "Back stronger: " .. name
					local sub = desc or "Boost after death"
					if k == speedPassKey then
						-- F8 copy: "Run faster" / "Speed Pass  +15% forever" / "GET R$ 5" (from the config values).
						-- No Cash Pack Mega highlight after this offer (M1: no 799 R$ push after a death).
						local mult = if typeof(def) == "table" then tonumber(def.WalkSpeedMult) else nil
						title = "Run faster"
						sub = if mult and mult > 1
							then string.format("%s  +%d%% forever", name, math.floor((mult - 1) * 100 + 0.5))
							else name
					else
						pendingCashMegaHighlight = true -- v35: CashMega highlight if the shop opens next
					end
					local offerKind, offerKey = kind, k
					return showOffer({
						Key = "DeathShopToast",
						Title = title,
						Sub = sub,
						Cta = ctaFor(robux),
						OnGet = function()
							if offerKind == "GamePass" then
								promptGamePass(offerKey, "death_card")
							else
								promptDevProduct(offerKey, "death_card")
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
		"Weapons cost in-game Cash. EQUIP owned weapons here; draw them from the hotbar (tap a slot" .. (if HudLayout.PrefersKeys() then " or press 1-4)." else ").")
	)
	selectTab(activeTab)

	local rowBtnH = if isTouch then TAP else 48
	local rowBtnW = if isTouch then 140 else 100
	local rowTitleSize = PanelShell.Text(14)
	local rowSubSize = PanelShell.Text(11)
	-- F2: the hero title. PanelShell.Text(16) clamps to the same 20 v as every row title on touch, so the hero uses
	-- 24 v (16.8 real px on phones) to stand out on the device most players use.
	local heroTitleSize = PanelShell.Text(24)
	local function buildRow(parentList: ScrollingFrame, layoutOrder: number, rowName: string, label: string, sub: string, btnText: string, hero: boolean?): (Frame, TextLabel, TextButton)
		local isHero = hero == true
		local titleSize = if isHero then heroTitleSize else rowTitleSize
		local rowH = math.max(rowBtnH + 10, rowTitleSize + rowSubSize + 22) + (if isHero then HERO_ROW_EXTRA_H else 0)
		-- the hero centres its two lines in the taller row; every other row keeps the v69 7 v top
		local titleY = if isHero then math.floor((rowH - (titleSize + 4 + 6 + rowSubSize + 4)) / 2) else 7
		local row = Instance.new("Frame")
		row.Name = "ShopRow_" .. rowName
		row.Size = UDim2.new(1, -8, 0, rowH)
		row.BackgroundColor3 = if isHero then HERO_ROW_BG else Constants.Colors.Background
		row.BorderSizePixel = 0
		row.LayoutOrder = layoutOrder
		row.Parent = parentList
		corner(row, 8)
		if isHero then
			row:SetAttribute("WE_HeroRow", true)
			local heroStroke = Instance.new("UIStroke")
			heroStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			heroStroke.Color = Constants.Colors.Gold
			heroStroke.Thickness = HERO_ROW_STROKE
			heroStroke.Parent = row
		end

		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(12, titleY)
		t.Size = UDim2.new(1, -(rowBtnW + 30), 0, titleSize + 4)
		t.Font = if isHero then HudConfig.Fonts.Display else Enum.Font.GothamBold
		t.TextSize = titleSize
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.TextColor3 = if isHero then Constants.Colors.GoldBright else Constants.Colors.Text
		t.Text = label
		if isHero then
			-- the hero title shrinks to fit a narrow panel (desktop 480 v), never below a plain row title
			t.TextScaled = true
			local fit = Instance.new("UITextSizeConstraint")
			fit.MinTextSize = rowTitleSize
			fit.MaxTextSize = titleSize
			fit.Parent = t
		end
		t.Parent = row

		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromOffset(12, titleY + titleSize + 6)
		s.Size = UDim2.new(1, -(rowBtnW + 30), 0, rowSubSize + 4)
		s.Font = Enum.Font.GothamMedium
		s.TextSize = rowSubSize
		s.TextXAlignment = Enum.TextXAlignment.Left
		s.TextColor3 = if isHero then Constants.Colors.Text else Constants.Colors.Muted
		s.TextTruncate = Enum.TextTruncate.AtEnd
		s.Text = sub
		s.Parent = row

		local btn = Instance.new("TextButton")
		btn.Name = "Action"
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, -8, 0.5, 0)
		btn.Size = UDim2.fromOffset(rowBtnW, rowBtnH)
		-- F2: the hero's BUY face is gold with dark text (the plain rows keep the gunmetal face)
		btn.BackgroundColor3 = if isHero then Constants.Colors.Gold else Constants.Colors.Gunmetal
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = PanelShell.Text(12)
		btn.TextColor3 = if isHero then Constants.Colors.TextDark else Color3.fromRGB(255, 248, 230)
		btn.Text = btnText
		btn.BorderSizePixel = 0
		btn.Active = true
		corner(btn, 8)
		local btnStroke = Instance.new("UIStroke")
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		btnStroke.Color = if isHero then Constants.Colors.GoldBright else Constants.Colors.Gold
		btnStroke.Thickness = 1.25
		btnStroke.Parent = btn
		btn.Parent = row
		UIUtil.EnsureMinTouch(btn, rowBtnH)
		return row, s, btn
	end

	local order = 0
	-- SUPPLY row. onClick nil = display-only row: its button is disabled (never a dead gold BUY).
	local function addRow(label: string, sub: string, onClick: (() -> ())?, btnText: string?, rowKey: string?, hero: boolean?): TextButton
		order += 1
		local _, _, btn = buildRow(list, order, rowKey or tostring(order), label, sub, btnText or "BUY", hero)
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
			-- F2: the title carries "BEST OFFER"; the sub is just what you get (no second "BEST OFFER —")
			title = heroLabel .. " · " .. title
		end
		local btnLabel = if robux > 0 then (tostring(robux) .. " R$") else "BUY"
		local btn = addRow(title, sub, function()
			promptDevProduct(key, openSource)
		end, btnLabel, key, heroLabel ~= nil)
		if def.OneTime == true then
			oneTimeRows[key] = { Btn = btn, Label = btnLabel }
		end
	end

	-- F9: a stable row order (Robux price, then key) instead of the table's hash order, so a newly pasted Id (Golden
	-- Pumpjacks, the Speed Pass) always lands in the same place on every server
	local function sortedKeys(section: any): { string }
		local keys: { string } = {}
		for key in pairs(section) do
			if typeof(key) == "string" then
				table.insert(keys, key)
			end
		end
		table.sort(keys, function(a: string, b: string): boolean
			local pa = tonumber(section[a].RobuxPrice) or 0
			local pb = tonumber(section[b].RobuxPrice) or 0
			if pa ~= pb then
				return pa < pb
			end
			return a < b
		end)
		return keys
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
	for _, key in ipairs(sortedKeys(MonetizationConfig.DevProducts)) do
		if not listed[key] then
			addDevRow(key, (MonetizationConfig.DevProducts :: any)[key], nil)
		end
	end

	for _, key in ipairs(sortedKeys(MonetizationConfig.GamePasses)) do
		local def: any = (MonetizationConfig.GamePasses :: any)[key]
		-- v69: HideFromShop passes are not sold (ExtraPlotCosmetic "Elite Base Theme": nothing applies it yet)
		if def.HideFromShop == true then
			continue
		end
		-- F8: an Id 0 pass (the Speed Pass until the owner creates it) gets no row at all: it appears, with no
		-- other edit, once its Id is pasted. Nothing is ever prompted for an Id 0 pass.
		if (tonumber(def.Id) or 0) == 0 then
			continue
		end
		local robux = tonumber(def.RobuxPrice) or 0
		local btnLabel = if robux > 0 then (tostring(robux) .. " R$") else "PASS"
		local name = tostring(def.DisplayName or key)
		-- "Pass: VIP", but "Speed Pass" (not "Pass: Speed Pass")
		local passTitle = if string.find(string.lower(name), "pass", 1, true) then name else "Pass: " .. name
		local btn = addRow(passTitle, tostring(def.Description or ""), function()
			promptGamePass(key, openSource)
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
		-- F1: pass rows follow the server's WE_Ent_<key> (and the pad slot's OwnedIfAny) both ways
		for key, r in pairs(passRows) do
			if offerOwned("GamePass", key) then
				setRowButton(r.Btn, "OWNED", "owned")
			else
				setRowButton(r.Btn, r.Label, "buy")
			end
		end
	end

	refreshShopRows = function()
		-- phones: no row work while the Shop is closed (WE_Cash changes on every payout); setOpen(true) refreshes
		if not menuOpen then
			return
		end
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
			elseif attr == "WE_Cash" then
				queueRefresh()
			elseif string.sub(attr, 1, 7) == "WE_Ent_" then
				-- F1: the server reports a pass / entitlement: Shop rows AND the world pads flip to OWNED
				queueRefresh()
				refreshPremiumPads()
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
				refreshPremiumPads()
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
				refreshPremiumPads()
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



	--[[ v31 → F1: the ATM pads (and the golden pump pad) → OWNED look (dimmed, "OWNED" tag, WE_LocalOwned) for game
		passes AND Developer Products, including a slot's OwnedIfAny keys and entitlements another product granted
		(Auto Collect from the Starter Pack). Ownership comes only from the server's WE_Ent_<key> attributes (and this
		session's purchases): refreshed when a WE_Ent_* attribute changes, when a purchase finishes and when a pad
		streams in. No polling loop, no per-frame work, and no client ownership web call. Display only: the server
		(PremiumPadService.alreadyOwns) decides whether a pad prompts. ]]
	do
		local PAD_TAG = (Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"

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
					-- v71: the server tag is a two-line WorldLabel ("Auto Collect" / "R$"): no price line under OWNED
					local sub = bb:FindFirstChild("Sub")
					if sub and sub:IsA("TextLabel") and sub ~= label then
						sub.Visible = false
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

		local function applyPad(inst: Instance)
			if not inst:IsA("BasePart") then
				return
			end
			local kind = inst:GetAttribute("OfferKind")
			local key = inst:GetAttribute("OfferKey")
			if (kind == "GamePass" or kind == "DevProduct") and isKeyName(key) then
				applyOwnedVisual(inst, offerOwned(kind :: string, key :: string, inst))
			end
		end

		-- one pass over the tagged pads (a CollectionService list, never a workspace scan), coalesced per frame
		local padRefreshQueued = false
		refreshPremiumPads = function()
			if padRefreshQueued then
				return
			end
			padRefreshQueued = true
			task.defer(function()
				padRefreshQueued = false
				for _, inst in ipairs(CollectionService:GetTagged(PAD_TAG)) do
					applyPad(inst)
				end
			end)
		end

		refreshPremiumPads()
		-- a pad that streams in (StreamingEnabled) or is rebuilt gets its look once its attributes are there
		CollectionService:GetInstanceAddedSignal(PAD_TAG):Connect(function(inst)
			if inst:IsA("BasePart") then
				task.defer(applyPad, inst)
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
					promptDevProduct("StarterBundle", "starter_offer")
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
					promptGamePass("AutoCollect", "offer")
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
					promptGamePass("DoubleCash", "offer")
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
					promptGamePass("VIP", "offer")
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
					promptDevProduct("SpeedBoost", "offer")
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
					promptDevProduct("CashMega", "offer")
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
		if kind ~= "GamePass" and kind ~= "DevProduct" then
			return
		end
		-- F1: an owned pad never prompts (the server checks first; this covers a WE_Ent_* that landed in between)
		if offerOwned(kind, key) then
			toast("Already owned", "Info")
			refreshPremiumPads()
			return
		end
		if kind == "GamePass" then
			promptGamePass(key, "pad")
		else
			promptDevProduct(key, "pad")
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
	setOpen(true, "hud_plus") -- F2: the rows bought from here report source "hud_plus"
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
