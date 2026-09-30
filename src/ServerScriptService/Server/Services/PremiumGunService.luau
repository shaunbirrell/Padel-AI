--!strict
--[[
	claude-bud JOB 35 (2026-09-30): the PREMIUM GUNS ARMORY (PremiumGunsConfig). Server-authoritative.
	  * GRANTS: owning PG_<gun> or PG_ArmoryPass sets profile.Weapons[id] = true. MonetizationService fires
	    OnPassOwned on join (every owned pass with a real Id, UserOwnsGamePassAsync) and after a confirmed purchase, so
	    one listener covers both. While live and the passes are Id 0, the playtest owner (and every Studio test player)
	    gets the six guns (OwnerTestGrant) so they can be tested.
	  * ARMORY: in every live player's base, 7 glass cases in one row west of the Supply Depot (6 guns + the Armory Pass),
	    one ARMORY sign (PurchaseStands.Sign) with the row's only light (Shadows off). Each case: a plinth, a gold trim, a
	    glass box (0.6), a gold cap; a ProximityPrompt on the plinth; one base label (WorldLabel BaseLabel = the
	    LabelGovernor shows the 3 nearest). The client (ArmoryClient) spins the gun template inside each nearby case.
	  * PROMPT: owned -> "Equip" (CombatService.EquipWeapon); a pass with Id 0 -> SOON, the prompt is disabled (never
	    prompted); else "Buy - R$ X" (price from MonetizationConfig only) -> MarketplaceService:PromptGamePassPurchase.
	    The purchase is confirmed by MonetizationService (PromptGamePassPurchaseFinished + UserOwnsGamePassAsync) and
	    only then granted here. Once owned, the glass fades (OwnedGlassTransparency).
	Kill switch: PremiumGunsConfig.Live (owner-first). Off = no armory, no grants.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PremiumGunsConfig = require(Shared.Configs.PremiumGunsConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)
local PlotFrame = require(Shared.Util.PlotFrame)
local WorldLabel = require(Shared.Util.WorldLabel)
local PurchaseStands = require(script.Parent.Parent.Modules.PurchaseStands)

local PremiumGunService = {}

local deps: { [string]: any } = {}
local A = PremiumGunsConfig.Armory
local ROBUX = utf8.char(0xE002) -- the Robux glyph (same as PurchaseStands)
local plotOf: { [number]: number } = {} -- uid -> plot id with a built armory

local function live(uid: number): boolean
	return PremiumGunsConfig.LiveFor(uid)
end

local function passDef(key: string): any
	return (MonetizationConfig.GamePasses :: any)[key]
end

local function passPrice(key: string): number
	local d = passDef(key)
	return if typeof(d) == "table" then math.floor(tonumber(d.RobuxPrice) or 0) else 0
end

local function passId(key: string): number
	local d = passDef(key)
	return if typeof(d) == "table" then math.floor(tonumber(d.Id) or 0) else 0
end

-- the prompt line for a price (the PurchaseStands "Buy - R$ X" format)
function PremiumGunService.BuyText(price: number): string
	return "Buy - " .. ROBUX .. " " .. tostring(price)
end

local function ownsGun(profile: any, weaponId: string): boolean
	return typeof(profile) == "table" and typeof(profile.Weapons) == "table" and profile.Weapons[weaponId] == true
end

--[[ The state one case shows for a profile (pure; tests call it): "Owned" | "Soon" | "Buy", the board sub line and
	the prompt text. entry = a PremiumGunsConfig.Guns row, or nil for the Armory Pass case. ]]
function PremiumGunService.CaseState(profile: any, entry: any): (string, string, string)
	if entry ~= nil then
		if ownsGun(profile, entry.WeaponId) then
			return "Owned", "OWNED", "Equip"
		end
		if passId(entry.PassKey) == 0 then
			return "Soon", "SOON", ""
		end
		local price = passPrice(entry.PassKey)
		return "Buy", ROBUX .. " " .. tostring(price), PremiumGunService.BuyText(price)
	end
	local all = true
	for _, g in ipairs(PremiumGunsConfig.Guns) do
		if not ownsGun(profile, g.WeaponId) then
			all = false
		end
	end
	if all then
		return "Owned", "ALL OWNED", ""
	end
	if passId(PremiumGunsConfig.BundleKey) == 0 then
		return "Soon", "SOON", ""
	end
	local price = passPrice(PremiumGunsConfig.BundleKey)
	return "Buy", ROBUX .. " " .. tostring(price), PremiumGunService.BuyText(price)
end

-- grant these weapons (idempotent). Returns how many were new.
function PremiumGunService.Grant(player: Player, weaponIds: { string }, why: string): number
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or typeof(profile.Weapons) ~= "table" then
		return 0
	end
	local newly: { string } = {}
	for _, id in ipairs(weaponIds) do
		local def: any = WeaponConfig.Weapons[id]
		if def and def.Premium == true and profile.Weapons[id] ~= true then
			profile.Weapons[id] = true
			table.insert(newly, def.DisplayName)
		end
	end
	if #newly == 0 then
		return 0
	end
	deps.DataService.MarkDirty(player)
	local cs = deps.CombatService
	if cs and cs.SyncWeapons then
		pcall(cs.SyncWeapons, player)
	end
	local ns = deps.NotificationService
	if ns and ns.Notify and why ~= "test" then
		pcall(ns.Notify, player, "Armory: " .. table.concat(newly, ", ") .. " unlocked!", "Reward", 5)
	end
	if deps.AnalyticsService then
		pcall(deps.AnalyticsService.Log, "PREMIUM_GUN_GRANTED", player.UserId, { guns = #newly, why = why })
	end
	PremiumGunService.Refresh(player)
	return #newly
end

local function armoryRoot(): Folder
	local f = Workspace:FindFirstChild(A.FolderName)
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = A.FolderName
		nf.Parent = Workspace
		f = nf
	end
	return f :: Folder
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = collide
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- plot-local case positions (tests read them): i = 1..7
function PremiumGunService.CaseOffset(i: number): Vector3
	return Vector3.new(A.X0 + (i - 1) * A.Step, 0, A.Z)
end

local function paint(case: Model, profile: any)
	local entry: any = nil
	local gun = case:GetAttribute("WE_ArmoryGun")
	for _, g in ipairs(PremiumGunsConfig.Guns) do
		if g.WeaponId == gun then
			entry = g
		end
	end
	local stateName, sub, action = PremiumGunService.CaseState(profile, entry)
	case:SetAttribute("WE_ArmoryState", stateName)
	local glass = case:FindFirstChild("Glass")
	if glass and glass:IsA("BasePart") then
		glass.Transparency = if stateName == "Owned" then A.OwnedGlassTransparency else A.GlassTransparency
	end
	local plinth = case:FindFirstChild("Plinth")
	local pp = plinth and plinth:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.ActionText = action
		pp.Enabled = action ~= ""
	end
	local bb = glass and glass:FindFirstChildOfClass("BillboardGui")
	if bb then
		local name = case:GetAttribute("WE_ArmoryName")
		pcall(WorldLabel.SetText, bb, tostring(name), sub, if stateName == "Owned" then Color3.fromRGB(120, 230, 120) else A.Trim)
	end
end

local function onTriggered(case: Model, player: Player)
	local rl = deps.RateLimitService
	if rl and not rl.Allow(player, "armory", 1, 2) then
		return
	end
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local gun = case:GetAttribute("WE_ArmoryGun")
	local key: string = PremiumGunsConfig.BundleKey
	if typeof(gun) == "string" then
		if ownsGun(profile, gun) then
			local cs = deps.CombatService
			if cs and cs.EquipWeapon then
				local ok = cs.EquipWeapon(player, gun)
				local ns = deps.NotificationService
				if ok and ns then
					pcall(ns.Notify, player, "Equipped " .. tostring(case:GetAttribute("WE_ArmoryName")), "Success", 3)
				end
			end
			return
		end
		key = PremiumGunsConfig.PassFor(gun) or key
	end
	local id = passId(key)
	if id == 0 then
		return -- SOON: the prompt is disabled; never prompted
	end
	if deps.AnalyticsService then
		pcall(deps.AnalyticsService.Log, "SHOP_PROMPT", player.UserId, { kind = "GamePass", key = key, productId = id, source = "armory" })
	end
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, id)
	end)
end

--[[ Build the armory row for this plot (idempotent: an old row is replaced). owner = the plot's owner (his profile
	paints the cases). ]]
function PremiumGunService.Build(plotId: number, owner: Player)
	local ok, pos = pcall(PlotFrame.PlotPosition :: any, plotId)
	if not ok or typeof(pos) ~= "Vector3" then
		return
	end
	local root = armoryRoot()
	local old = root:FindFirstChild("Plot" .. plotId)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. plotId
	local F = PlotFrame.PlotCFrame(pos)
	local steel = Color3.fromRGB(58, 60, 64)
	local entries: { any } = table.clone(PremiumGunsConfig.Guns) :: { any }
	table.insert(entries, false) -- the 7th case: the Armory Pass
	for i, entry in ipairs(entries) do
		local o = PremiumGunService.CaseOffset(i)
		local base = F * CFrame.new(o.X, 0.3, o.Z) * CFrame.Angles(0, math.pi, 0)
		local case = Instance.new("Model")
		case.Name = "ArmoryCase" .. i
		local gunDef: any = if entry then WeaponConfig.Weapons[entry.WeaponId] else nil
		local name = if gunDef then gunDef.DisplayName else "Armory Pass"
		case:SetAttribute("WE_ArmoryName", name)
		if entry then
			case:SetAttribute("WE_ArmoryGun", entry.WeaponId)
		else
			case:SetAttribute("WE_ArmoryPass", true)
		end
		local P = A.Plinth
		local G = A.Glass
		local plinth = part("Plinth", P, base * CFrame.new(0, P.Y / 2, 0), steel, Enum.Material.Metal, case, true)
		part("Trim", Vector3.new(P.X + 0.3, 0.25, P.Z + 0.3), base * CFrame.new(0, P.Y, 0), A.Trim, Enum.Material.Metal, case, false)
		local glass = part("Glass", G, base * CFrame.new(0, P.Y + G.Y / 2, 0), Color3.fromRGB(200, 225, 240), Enum.Material.Glass, case, true)
		glass.Transparency = A.GlassTransparency
		part("Cap", Vector3.new(G.X + 0.3, 0.3, G.Z + 0.3), base * CFrame.new(0, P.Y + G.Y + 0.15, 0), A.Trim, Enum.Material.Metal, case, false)
		local pp = Instance.new("ProximityPrompt")
		pp.ObjectText = name
		pp.ActionText = ""
		pp.HoldDuration = 0
		pp.MaxActivationDistance = A.PromptDistance
		pp.RequiresLineOfSight = false
		pp.Parent = plinth
		pp.Triggered:Connect(function(p: Player)
			onTriggered(case, p)
		end)
		do
			pcall(WorldLabel.Create, glass, name, {
				Name = "WE_ArmoryLabel",
				Sub = "",
				MaxDistance = A.LabelMaxDistance,
				BaseLabel = true, -- the LabelGovernor shows the 3 nearest base labels
				Parent = glass :: Instance,
			})
		end
		case.Parent = folder
	end
	-- one sign behind the row (the row's only light, Shadows off)
	local mid = A.X0 + (#entries - 1) * A.Step / 2
	do
		pcall(PurchaseStands.Sign, folder, F * CFrame.new(mid, 0.3, A.SignZ) * CFrame.Angles(0, math.pi, 0), A.Sign)
	end
	local lampHolder = folder:FindFirstChild("SupplyDepotSign")
	if lampHolder then
		lampHolder.Name = "ArmorySign"
		local board = lampHolder:FindFirstChild("SignBoard")
		if board then
			local light = Instance.new("PointLight")
			light.Range = A.LightRange
			light.Brightness = A.LightBrightness
			light.Shadows = false
			light.Color = Color3.fromRGB(255, 230, 180)
			light.Parent = board
		end
	end
	folder:SetAttribute("OwnerUserId", owner.UserId)
	folder.Parent = root
	plotOf[owner.UserId] = plotId
	PremiumGunService.Refresh(owner)
end

-- repaint this player's armory from his profile (after a grant / on build)
function PremiumGunService.Refresh(player: Player)
	local plotId = plotOf[player.UserId]
	if plotId == nil then
		return
	end
	local folder = armoryRoot():FindFirstChild("Plot" .. plotId)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if folder == nil or profile == nil then
		return
	end
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("Model") and (c:GetAttribute("WE_ArmoryGun") ~= nil or c:GetAttribute("WE_ArmoryPass") == true) then
			paint(c, profile)
		end
	end
end

local function testGrant(player: Player)
	if PremiumGunsConfig.OwnerTestGrant ~= true or not live(player.UserId) then
		return
	end
	if AdminConfig.IsPlaytestOwner(player.UserId) or RunService:IsStudio() then
		local all: { string } = {}
		for _, g in ipairs(PremiumGunsConfig.Guns) do
			table.insert(all, g.WeaponId)
		end
		PremiumGunService.Grant(player, all, "test")
	end
end

function PremiumGunService.Init(d: { [string]: any })
	deps = d
	local ms = d.MonetizationService
	if ms and ms.OnPassOwned then
		ms.OnPassOwned(function(player: Player, passKey: string, reason: string)
			if typeof(passKey) ~= "string" or not live(player.UserId) then
				return
			end
			local ids = PremiumGunsConfig.UnlockedBy({ [passKey] = true })
			if #ids > 0 then
				PremiumGunService.Grant(player, ids, tostring(reason))
			end
		end)
	end
	if d.DataService and d.DataService.OnProfileLoaded then
		d.DataService.OnProfileLoaded(function(player: Player)
			testGrant(player)
		end)
	end
	if d.BaseService and d.BaseService.OnPlotReady then
		d.BaseService.OnPlotReady(function(player: Player, plotId: number)
			if live(player.UserId) then
				task.defer(function()
					local ok, err = pcall(PremiumGunService.Build :: any, plotId, player)
					if not ok then
						warn("[PremiumGunService] armory build failed: " .. tostring(err))
					end
				end)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local plotId = plotOf[player.UserId]
		plotOf[player.UserId] = nil
		if plotId then
			local f = armoryRoot():FindFirstChild("Plot" .. plotId)
			if f then
				f:Destroy()
			end
		end
	end)
	print("[WAR EMPIRE] PremiumGunService Init: guns=" .. #PremiumGunsConfig.Guns)
end

return PremiumGunService
