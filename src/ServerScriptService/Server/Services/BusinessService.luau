--!strict
--[[
	v72 war businesses (world) + the server's "next buy" pick (BusinessConfig / TycoonGuideConfig / Shared/Util/TycoonMath).

	World (called by BaseService inside its visual pipeline, so the kiosks exist before plot-ready fires):
	  SyncPlot(plotId, upgrades, owner?)       every business on the plot at its saved level (RefreshAllVisuals)
	  SyncBusiness(plotId, id, level, owner?)  one business after a buy / rebirth / admin reset (UpdateVisuals)
	  ClearPlot(plotId)                        plot released (the next owner gets fresh L0 kiosks)
	  Plot<N>/WE_Businesses/WE_Business_<Id> (Model, tag WE_Business, attrs PlotId / BusinessId / Level / OwnerUserId /
	  WE_SiteCFrame; streaming2 S4: ModelStreamingMode Atomic, built unparented and parented once whole, so the tag
	  added-signals fire on a finished kiosk; inert while Workspace.StreamingEnabled is false)
	    Console  WE_UpgradeSlot console (PlotId, StructureId, WE_Console): UpgradePadService adds the hold prompt,
	             ConsoleLocator finds it, BaseService.PurchaseUpgrade buys at it (console-only buying, no bypass).
	             No screen gui, no Neon, no light (budget).
	    Slab + kit parts with MinLevel <= level (idempotent: missing parts built, parts above the level removed).
	  L0 (slab + 3-part console) stands on every OWNED plot from plot assignment on, so tutorial step 6 and GO find
	  the kiosk before the first buy. Unowned plots have none. Static only: nothing here moves or ticks; crates and
	  the "+$N" pops are client-only (Client/Modules/BusinessVisuals). Every world call is a no-op while
	  BusinessConfig.Enabled is false.
	  Owner asset list hook (2026-09-25): after the kit loop a deferred VisualAssetService.TryAttachBusinessVisual lets
	  the line's catalog model (VisualAssetConfig.Businesses) take over its kit parts one for one (the Kit_<Role> names
	  stay, so PartsPerBusinessL5 holds and the client belt crates still find Kit_Belt); a 0 id is a no-op.
	  Droppers v1a look tiers: Field (L1-2) / Works (L3-4) / Arsenal (L5) from BusinessConfig.LookTiers on the
	  LookTierRoles parts (applyLook): property-only, 0 new parts, written only where a value differs, never on a part
	  that carries WE_CatalogAssetId.
	  bizlook growth (BusinessConfig.Kit Grow rows): a kit part's Size / CFrame for the level (applyGrow), written only
	  when they differ, never on a dressed part; the slab widens at L2 and the head office grows at L4 / L5. A building
	  piece stretched into a grown box (WE_BizFitRole) is rebuilt as its Part-kit role and the deferred dress fits it
	  again; the colliders a piece hid (WE_BizHiddenBy) show again whenever that piece goes. Stand-in count (T3b, pieces
	  on): <= 18 instance changes per buy after the pack's first load, 29 for a 1 -> 5 jump; an idle re-sync writes nothing.

	Money: NONE here (no remote, no grant). Business income is part of BaseService.ComputePassiveIncomePerTick
	(TycoonMath.BasePassivePerTick) and is paid into the ATM on the existing 5 s passive tick.

	Next buy (TycoonGuideConfig.Enabled only): WE_NextBuy = "<Id>:<TargetLevel>" | "Soldier:0" | "" on the Player,
	re-picked on profile load, plot ready, every purchase, army change and every RepickSeconds since the player's
	last pick (TycoonMath.PickNext, sticky by Hysteresis). Written only when the value changes. Reads server state
	only: the profile (upgrades, cash, ATM, Prestige for the rebirth-zone filter), SoldierService count / cap and
	WE_IncomePerSec (EconomyService). Advice only: the server
	re-checks every buy. Also stamps WE_AtmPos (the player's OWN ATM position) on plot ready, nil on release, so
	the client's "Collect at your ATM" line never needs the ATM part streamed in.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BusinessConfig = require(Shared.Configs.BusinessConfig)
local TycoonGuideConfig = require(Shared.Configs.TycoonGuideConfig)
local TycoonMath = require(Shared.Util.TycoonMath)

local BaseLayout = require(script.Parent.Parent.Modules.BaseLayout)

local BusinessService = {}

local DataService: any = nil
local BaseService: any = nil
local SoldierService: any = nil

local TAG_SLOT = Constants.Tags.UpgradeSlot
local TAG_ATM = Constants.Tags.MoneyCollector
local ATTR_NEXT = "WE_NextBuy"
local ATTR_ATM = "WE_AtmPos"
local REPICK_CHECK_SECONDS = 1 -- the loop only compares clocks; a pick runs when RepickSeconds have passed

---------------------------------------------------------------------------------------------------------------
-- world
---------------------------------------------------------------------------------------------------------------

local function plotFolder(plotId: number): Instance?
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	return bases and bases:FindFirstChild("Plot" .. tostring(plotId))
end

local function colorFor(def: BusinessConfig.BusinessDef, key: string): Color3
	local pal = def.Palette :: any
	if pal[key] ~= nil then
		return pal[key]
	end
	return (BusinessConfig.SharedColors :: any)[key] or Color3.fromRGB(90, 90, 90)
end

local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, collide: boolean, parent: Instance, reflectance: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if reflectance ~= nil and reflectance ~= 0 then
		p.Reflectance = reflectance -- droppers v1a look tier (Arsenal Roof), set before parenting (bizlook: the window band too)
	end
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = collide
	p.CastShadow = collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[ Droppers v1a look tiers (BusinessConfig.LookTiers on LookTierRoles; spec_droppers §3.4). Property-only, 0 new
	parts: Material, Color and the Roof Reflectance. A new part is built with its tier look (newPart); an existing part
	is written only where a value differs, so an idle re-sync writes nothing and a level-down or rebirth reapplies the
	lower tier. Colours compare as whole RGB (BasePart.Color is stored 8 bits per channel) and Reflectance within 0.001
	(stored as a float), so a live part never looks "different" from the value just written. A part that carries
	WE_CatalogAssetId (a hooks dress) is never written. Cosmetic only: no money, no remote. ]]
local tierRoles: { [string]: boolean } = {}
for _, role in ipairs(BusinessConfig.LookTierRoles) do
	tierRoles[role] = true
end

local function rgb8(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

local function shaded(c: Color3, s: number): Color3
	if s == 1 then
		return c
	end
	local r, g, b = math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
	return Color3.fromRGB(
		math.clamp(math.floor(r * s + 0.5), 0, 255),
		math.clamp(math.floor(g * s + 0.5), 0, 255),
		math.clamp(math.floor(b * s + 0.5), 0, 255)
	)
end

-- the tier look of kit part `kp` of business `def` at level `lv`: Material, Color, Roof Reflectance (nil = other roles)
local function lookFor(def: BusinessConfig.BusinessDef, kp: BusinessConfig.KitPart, lv: number): (Enum.Material, Color3, number?)
	local tier = BusinessConfig.LookTierFor(lv)
	local material = tier.Material
	if kp.Role == "Housing" and tier.HousingMaterial ~= nil then
		material = tier.HousingMaterial
	end
	local color = if kp.Role == "BeltFrame" and tier.PaintFrame ~= nil
		then colorFor(def, tier.PaintFrame)
		else shaded(colorFor(def, kp.ColorKey), tier.Shade)
	local reflectance: number? = if kp.Role == "Roof" then (tier.RoofReflectance or 0) else nil
	return material, color, reflectance
end

-- bizlook: the box of kit part kp at level lv (the last Grow row with FromLevel <= lv, else the kit row's own)
local function geomFor(kp: BusinessConfig.KitPart, lv: number): (Vector3, Vector3)
	local size, offset = kp.Size, kp.Offset
	for _, g in ipairs(kp.Grow or {}) do
		if g.FromLevel <= lv then
			size, offset = g.Size, g.Offset
		end
	end
	return size, offset
end

-- bizlook: an existing kit part with Grow rows: write Size / CFrame only when they differ (a level-up grows it, a
-- level-down or rebirth shrinks it back, an idle re-sync writes nothing); a hooks-dressed part is never moved
local function applyGrow(p: BasePart, kp: BusinessConfig.KitPart, base: CFrame, lv: number)
	if kp.Grow == nil or p:GetAttribute("WE_CatalogAssetId") ~= nil then
		return
	end
	local size, offset = geomFor(kp, lv)
	if (p.Size - size).Magnitude > 0.001 then
		p.Size = size
	end
	local cf = base * CFrame.new(offset)
	if (p.Position - cf.Position).Magnitude > 0.001 then
		p.CFrame = cf
	end
end

-- bizlook: kit rows by role (the box a stretched building piece fills: VisualAssetConfig.BusinessPieces Into)
local kitByRole: { [string]: BusinessConfig.KitPart } = {}
for _, kp in ipairs(BusinessConfig.Kit) do
	kitByRole[kp.Role] = kp
end

-- bizlook: a building piece stretched into another role's box (WE_BizFitRole) whose box is not this level's any more
-- (the office grows at L4 / L5): it must be rebuilt and dressed again at the new size
local function needsRefit(p: BasePart, lv: number): boolean
	local r = p:GetAttribute("WE_BizFitRole")
	if typeof(r) ~= "string" or p:GetAttribute("WE_CatalogAssetId") == nil then
		return false
	end
	local row = kitByRole[r]
	if row == nil then
		return false
	end
	local size = geomFor(row, lv)
	local turned = Vector3.new(size.Z, size.Y, size.X)
	return (p.Size - size).Magnitude > 0.001 and (p.Size - turned).Magnitude > 0.001
end

-- bizlook: the colliders a building piece hid (WE_BizHiddenBy = the piece's role) show again when the piece goes
local function showHidden(m: Model, role: string)
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") and c:GetAttribute("WE_BizHiddenBy") == role then
			c.Transparency = 0
			c.CastShadow = c.CanCollide
			c:SetAttribute("WE_BizHiddenBy", nil)
		end
	end
end

-- an existing kit part: write only the tier values that differ; skip non-tier roles and hooks-dressed parts
local function applyLook(p: BasePart, kp: BusinessConfig.KitPart, def: BusinessConfig.BusinessDef, lv: number)
	if not tierRoles[kp.Role] then
		return
	end
	if p:GetAttribute("WE_CatalogAssetId") ~= nil then
		return -- a hooks dress (VisualAssetService) wears its own look: never recoloured
	end
	local material, color, reflectance = lookFor(def, kp, lv)
	if p.Material ~= material then
		p.Material = material
	end
	if rgb8(p.Color) ~= rgb8(color) then
		p.Color = color
	end
	if reflectance ~= nil and math.abs(p.Reflectance - reflectance) > 0.001 then
		p.Reflectance = reflectance
	end
end

local function ensureConsole(model: Model, plotId: number, id: string, plotPos: Vector3): BasePart?
	local existing = model:FindFirstChild("Console")
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local cf = BaseLayout.ConsoleCFrame(plotPos, id)
	if cf == nil then
		return nil
	end
	local size = BaseLayout.CONSOLE_SIZE
	local console = newPart("Console", size, cf, Color3.fromRGB(46, 50, 48), Enum.Material.Metal, true, model)
	console.CanQuery = true
	console:SetAttribute("PlotId", plotId)
	console:SetAttribute("StructureId", id)
	console:SetAttribute("WE_Console", true)
	console:SetAttribute("BaseSize", size)
	local site = BaseLayout.SiteCFrame(plotPos, id)
	if site then
		console:SetAttribute("WE_SiteCFrame", site)
	end
	-- terminal look, same shapes as MapSetup.dressConsole, minus the screen gui and the neon (budget)
	local screen = newPart(
		"ConsoleScreen",
		Vector3.new(2.3, 1.3, 0.16),
		cf * CFrame.new(0, size.Y * 0.5 + 0.45, -0.25) * CFrame.Angles(math.rad(20), 0, 0),
		Color3.fromRGB(14, 22, 16),
		Enum.Material.SmoothPlastic,
		false,
		console
	)
	screen:SetAttribute("WE_Decor", true)
	local button = newPart(
		"ConsoleButton",
		Vector3.new(0.5, 0.2, 0.5),
		cf * CFrame.new(0.8, size.Y * 0.5 + 0.1, -0.35),
		Color3.fromRGB(90, 255, 120),
		if BusinessConfig.ConsoleNeon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		false,
		console
	)
	button:SetAttribute("WE_Decor", true)
	-- tag last: UpgradePadService's added-signal attaches the hold prompt to a fully attributed console
	CollectionService:AddTag(console, TAG_SLOT)
	return console
end

-- Build / trim one business to `level`. Idempotent; safe before Init (reads configs + BaseLayout only).
function BusinessService.SyncBusiness(plotId: number, id: string, level: number, ownerUserId: number?)
	if not BusinessConfig.Enabled then
		return
	end
	local def = BusinessConfig.Get(id)
	local plotPos = BaseConfig.PlotPositions[plotId]
	local folderParent = plotFolder(plotId)
	if def == nil or typeof(plotPos) ~= "Vector3" or folderParent == nil then
		return
	end
	local lv = math.clamp(math.floor(tonumber(level) or 0), 0, #def.Costs)
	local folder: Instance? = folderParent:FindFirstChild(BusinessConfig.FolderName)
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = BusinessConfig.FolderName
		f.Parent = folderParent
		folder = f
	end
	local name = BusinessConfig.ModelPrefix .. id
	local model = (folder :: Instance):FindFirstChild(name)
	local siteCF = BaseLayout.SiteCFrame(plotPos :: Vector3, id)
	if siteCF == nil then
		return
	end
	-- streaming2 S4 (F11): a new kiosk is Atomic and is built unparented, then parented once it is whole (below), so its
	-- console, kit parts, attributes and tags are all initial descendants: a client gets the whole kiosk or none of it.
	-- A later level-up adds parts to the parented model (they stream in normally, inside the same 22-stud kiosk).
	-- Inert while Workspace.StreamingEnabled is false: the finished tree is the same.
	local newModel: Model? = nil
	if model == nil then
		local m = Instance.new("Model")
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		m.Name = name
		m:SetAttribute("PlotId", plotId)
		m:SetAttribute("BusinessId", id)
		m:SetAttribute("WE_SiteCFrame", siteCF)
		model = m
		newModel = m
	end
	local m = model :: Model
	ensureConsole(m, plotId, id, plotPos :: Vector3)
	-- pad top: the site frame sits at pad-centre height (BaseLayout), the pad is 1 stud thick
	local base = (siteCF :: CFrame) * CFrame.new(0, 0.5, 0)
	local sigs = BusinessConfig.Signatures :: any
	for _, kp in ipairs(BusinessConfig.Kit) do
		local partName = "Kit_" .. kp.Role
		local have = m:FindFirstChild(partName)
		if have and have:IsA("BasePart") and kp.MinLevel <= lv and needsRefit(have, lv) then
			-- bizlook: its box grew / shrank: the fallback part is rebuilt now, the deferred dress fits the piece again
			showHidden(m, kp.Role)
			have:Destroy()
			have = nil
		end
		if kp.MinLevel <= lv then
			if have == nil then
				local size, offset = geomFor(kp, lv) -- bizlook: built at its level's box (0 extra writes)
				local shape = kp.Shape
				local rot: Vector3? = nil
				local sigMaterial: Enum.Material? = nil
				if kp.Role == "Signature" then
					local sig = sigs[def.Signature]
					if sig then
						size, offset, shape = sig.Size, sig.Offset, sig.Shape
						rot = sig.Rot -- bizlook: a turned product sign (the Ammo casing stands up)
						sigMaterial = sig.Material
					end
				end
				local color, material, reflectance = colorFor(def, kp.ColorKey), sigMaterial or kp.Material, kp.Reflectance
				if tierRoles[kp.Role] then
					material, color, reflectance = lookFor(def, kp, lv) -- droppers v1a: built in its tier look (0 extra writes)
				end
				local cf = base * CFrame.new(offset)
				if rot ~= nil then
					cf *= CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
				end
				local p = newPart(partName, size, cf, color, material, kp.Collide == true, m, reflectance)
				if shape then
					p.Shape = shape
				end
				p:SetAttribute("WE_BizRole", kp.Role)
			elseif have:IsA("BasePart") then
				applyLook(have, kp, def, lv) -- droppers v1a: tier change / level-down; writes only what differs
				applyGrow(have, kp, base, lv) -- bizlook: the level's box; writes only what differs
			end
		elseif have then
			showHidden(m, kp.Role) -- bizlook: a collider this role's piece hid shows again (if it stays)
			have:Destroy() -- rebirth reset / admin resetbase / level down
		end
	end
	-- owner asset list hook: the line's catalog dress (VisualAssetConfig.Businesses). Deferred: a first load may yield, and
	-- the kiosk is whole and parented by then; a re-sync that finds it in place does nothing. VisualAssetService is
	-- required here, pcall'd (as BaseService does), so a dress-module error can never stop the business world.
	task.defer(function()
		local okVas, vas = pcall(require, script.Parent.VisualAssetService)
		if okVas and vas and vas.TryAttachBusinessVisual then
			pcall(vas.TryAttachBusinessVisual, m, id, lv)
		end
	end)
	if m:GetAttribute("Level") ~= lv then
		m:SetAttribute("Level", lv)
	end
	if ownerUserId ~= nil and m:GetAttribute("OwnerUserId") ~= ownerUserId then
		m:SetAttribute("OwnerUserId", ownerUserId) -- client visuals run crates on the owner's lines only
	end
	if not CollectionService:HasTag(m, BusinessConfig.Tag) then
		CollectionService:AddTag(m, BusinessConfig.Tag)
	end
	if newModel ~= nil then
		newModel.Parent = folder -- streaming2 S4: parented last, whole (see above)
	end
end

function BusinessService.SyncPlot(plotId: number, upgrades: { [string]: any }?, ownerUserId: number?)
	if not BusinessConfig.Enabled then
		return
	end
	for _, id in ipairs(BusinessConfig.Order) do
		BusinessService.SyncBusiness(plotId, id, TycoonMath.Level(upgrades, id), ownerUserId)
	end
end

function BusinessService.ClearPlot(plotId: number)
	if not BusinessConfig.Enabled then
		return
	end
	local parent = plotFolder(plotId)
	local folder = parent and parent:FindFirstChild(BusinessConfig.FolderName)
	if folder then
		folder:Destroy()
	end
end

---------------------------------------------------------------------------------------------------------------
-- ATM position (guide: "Collect at your ATM" line; streaming-safe, the client never needs the ATM part)
---------------------------------------------------------------------------------------------------------------

local function atmPartOf(plotId: number): BasePart?
	for _, inst in ipairs(CollectionService:GetTagged(TAG_ATM)) do
		if inst:IsA("BasePart") and tonumber(inst:GetAttribute("PlotId") :: any) == plotId then
			return inst
		end
	end
	return nil
end

function BusinessService.StampAtmPos(player: Player, plotId: number?)
	if not TycoonGuideConfig.Enabled or player.Parent == nil then
		return
	end
	local part = if plotId ~= nil then atmPartOf(plotId) else nil
	local pos: Vector3? = if part then part.Position else nil
	if player:GetAttribute(ATTR_ATM) ~= pos then
		player:SetAttribute(ATTR_ATM, pos)
	end
end

-- BaseService.ReleasePlot: the plot's lines go, and the player's ATM line has no target any more
function BusinessService.OnPlotReleased(player: Player, plotId: number)
	BusinessService.ClearPlot(plotId)
	if TycoonGuideConfig.Enabled and player:GetAttribute(ATTR_ATM) ~= nil then
		player:SetAttribute(ATTR_ATM, nil)
	end
end

---------------------------------------------------------------------------------------------------------------
-- next buy
---------------------------------------------------------------------------------------------------------------

local lastRepick: { [Player]: number } = {}

local function soldierInfo(player: Player): (number?, number?)
	if not TycoonGuideConfig.IncludeSoldiers or SoldierService == nil or SoldierService.GetCap == nil then
		return nil, nil
	end
	local okC, count = pcall(SoldierService.GetCount, player)
	local okM, cap = pcall(SoldierService.GetCap, player)
	if okC and okM and typeof(count) == "number" and typeof(cap) == "number" then
		return count, cap
	end
	return nil, nil
end

-- The encoded pick for `player` right now ("" when the guide is off or there is no profile / nothing left).
function BusinessService.ComputeNextBuy(player: Player): string
	local profile = if DataService then DataService.GetProfile(player) else nil
	if not profile or not TycoonGuideConfig.Enabled then
		return ""
	end
	local soldiers, cap = soldierInfo(player)
	local cur = player:GetAttribute(ATTR_NEXT)
	local pick = TycoonMath.PickNext({
		Upgrades = if typeof(profile.BaseUpgrades) == "table" then profile.BaseUpgrades else {},
		Cash = tonumber(profile.Cash) or 0,
		Pending = tonumber(profile.PendingCash) or 0,
		IncomePerSec = tonumber(player:GetAttribute("WE_IncomePerSec")) or 0,
		Soldiers = soldiers,
		SoldierCap = cap,
		Current = if typeof(cur) == "string" and cur ~= "" then cur else nil,
		-- rebirth zones: a pad in a zone this player's Prestige has not opened is never the pick (PickCheapest filter)
		Prestige = tonumber(profile.Prestige) or 0,
	})
	return TycoonMath.Encode(pick)
end

-- Re-pick and stamp WE_NextBuy (only when the value changes). No-op while the guide is off.
function BusinessService.RefreshNextBuy(player: Player)
	if not TycoonGuideConfig.Enabled or player.Parent == nil then
		return
	end
	lastRepick[player] = os.clock()
	local ok, value = pcall(BusinessService.ComputeNextBuy, player)
	if not ok then
		warn("[BusinessService] ComputeNextBuy failed:", value)
		return
	end
	if player:GetAttribute(ATTR_NEXT) ~= value then
		player:SetAttribute(ATTR_NEXT, value)
	end
end

function BusinessService.Init(deps: { [string]: any })
	DataService = deps.DataService
	BaseService = deps.BaseService
	SoldierService = deps.SoldierService

	-- Both flags off: no hooks, no loop, no attributes (the game is exactly as before v72)
	if not TycoonGuideConfig.Enabled then
		return
	end

	if BaseService and BaseService.GetUpgradeChangedEvent then
		BaseService.GetUpgradeChangedEvent().Event:Connect(function(userId: number)
			local p = Players:GetPlayerByUserId(userId)
			if p then
				task.defer(BusinessService.RefreshNextBuy, p)
			end
		end)
	end
	if BaseService and BaseService.OnPlotReady then
		BaseService.OnPlotReady(function(p: Player, plotId: number)
			BusinessService.StampAtmPos(p, plotId)
			BusinessService.RefreshNextBuy(p)
		end)
	end
	if SoldierService and SoldierService.OnArmyChanged then
		SoldierService.OnArmyChanged(function(p: Player)
			BusinessService.RefreshNextBuy(p)
		end)
	end
	if DataService and DataService.OnProfileLoaded then
		DataService.OnProfileLoaded(function(p: Player)
			task.defer(BusinessService.RefreshNextBuy, p)
		end)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		lastRepick[p] = nil
	end)
	-- RepickSeconds since each player's last pick (money came in, the ATM filled up, a soldier share changed)
	task.spawn(function()
		while true do
			task.wait(REPICK_CHECK_SECONDS)
			local now = os.clock()
			for _, p in ipairs(Players:GetPlayers()) do
				if now - (lastRepick[p] or 0) >= TycoonGuideConfig.RepickSeconds then
					BusinessService.RefreshNextBuy(p)
				end
			end
		end
	end)
end

return BusinessService
