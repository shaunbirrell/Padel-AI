--!strict
--[[
	claude-bud JOB 33 (2026-09-30): the rebirth zones, their effects, and the visible rank (RebirthZonesConfig,
	RebirthConfig; geometry in Modules/RebirthZoneBuilder). Server-authoritative; everything behind
	RebirthConfig.LiveFor(player, "Zones" / "Trims" / "Perks").

	BUILD (per plot, for its owner): on plot-ready, after a rebirth (Refresh) and after an upgrade (that zone only):
	  * each zone's annex is checked once per plot (decor cleared; anything else blocks that annex);
	  * then locked (fence + "Unlocks at Rebirth N"), or its yard + console at its level.
	  Consoles carry a "WE_ZonePrompt" (BUILD / UPGRADE <cost>); the silo also has a "WE_SiloPrompt" (NUKE ->
	  NukeService.OpenPanel). Only the plot's owner can use them (checked here).
	UPGRADE: owner, live, zone reached, level < MaxLevel, rate-limited, then EconomyService.SpendCash(player, cost,
	  "rebirthzone_<Id>") (no purchase XP), then profile.RebirthZones[Id] += 1 (saved, kept through rebirths). Never
	  Robux.
	EFFECTS (read by the services that own each number):
	  * FlatIncomePerTick(profile, player) -> BaseService.passiveMultAndFlat;
	  * ArmyBonus(profile) -> SoldierService.maxSoldiers (the +2 soldiers per rebirth perk + Elite Barracks) and the
	    player attribute WE_RebirthArmyBonus (the client's cap mirror);
	  * MissileReloadCut(player) -> MissileStrikeService;
	  * RaidShieldBonus(profile) -> MoneyCollectorService (after an ATM raid);
	  * the Drone Hangar empties the owner's ATM every AutoCollectSeconds (EconomyService.CollectPendingCash) from a
	    2 s loop;
	  * the silo -> NukeService.
	RANK: two trim-coloured banners at the gate (RebirthConfig.TrimFor) and a small title above the head (TitleFor,
	  BillboardGui, MaxDistance 40) for Prestige >= 1.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared.Configs.RebirthConfig)
local RebirthZonesConfig = require(Shared.Configs.RebirthZonesConfig)
local WorldSitesConfig = require(Shared.Configs.WorldSitesConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local RebirthZoneService = {}

local deps: { [string]: any } = {}
local Builder: any = nil
local Dressing: any = nil -- claude-bud JOB 46: Modules/RebirthZoneDressing (the apron gateway, themed props, activity kiosk)
local ZC: any = RebirthZonesConfig
local apronOk: { [number]: { [string]: boolean } } = {} -- plotId -> zoneId -> the front apron is free (checked once)
local sweepAt: { [number]: number } = {} -- userId -> clock of the last drone sweep
local kioskOf: { [number]: { [string]: BasePart } } = {} -- claude-bud JOB A: userId -> zoneId -> his activity kiosk
local Z = RebirthZonesConfig

local plotOf: { [number]: number } = {} -- userId -> the plot his zones are built on
local slotOk: { [number]: { [string]: boolean } } = {} -- plotId -> zoneId -> annex usable (checked once per plot)
local profileOwner: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- profile -> userId
local lastCollect: { [number]: number } = {}

local function rotY(d: number): CFrame
	return CFrame.Angles(0, math.rad(d), 0)
end

local function zonesLive(uid: number): boolean
	return RebirthConfig.LiveFor(uid, "Zones")
end

local function prestigeOf(profile: any): number
	return math.max(0, math.floor(tonumber(profile and profile.Prestige) or 0))
end

local function levelOf(profile: any, zoneId: string): number
	local t = profile and profile.RebirthZones
	local lv = if typeof(t) == "table" then tonumber(t[zoneId]) or 0 else 0
	return math.clamp(math.floor(lv), 0, Z.MaxLevel)
end

local function reached(profile: any, zoneId: string): boolean
	return RebirthConfig.IsZoneOpen(prestigeOf(profile), nil, zoneId)
end

-- the level that counts for effects: reached, live, built
local function activeLevel(profile: any, uid: number?, zoneId: string): number
	if uid == nil or not zonesLive(uid) or not reached(profile, zoneId) then
		return 0
	end
	return levelOf(profile, zoneId)
end

local function pick(list: { number }?, level: number): number
	if list == nil or level < 1 then
		return 0
	end
	return tonumber(list[math.min(level, #list)]) or 0
end

-- ── effects ───────────────────────────────────────────────────────────────────────────────────────────────────────
function RebirthZoneService.FlatIncomePerTick(profile: any, player: Player?): number
	local uid = if player then player.UserId else profileOwner[profile]
	local sum = 0
	for zoneId, def in pairs(Z.Zones) do
		sum += pick(def.IncomePerTick, activeLevel(profile, uid, zoneId))
	end
	return sum
end

function RebirthZoneService.ArmyBonus(profile: any): number
	local uid = profileOwner[profile]
	if uid == nil then
		return 0
	end
	local b = 0
	if RebirthConfig.LiveFor(uid, "Perks") then
		b += RebirthConfig.PrestigeSoldierBonus(prestigeOf(profile))
	end
	b += pick(Z.Zones.EastYard.Soldiers, activeLevel(profile, uid, "EastYard"))
	return b
end

function RebirthZoneService.MissileReloadCut(player: Player): number
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	return if profile then pick(Z.Zones.WestStrip.MissileReloadCut, activeLevel(profile, player.UserId, "WestStrip")) else 0
end

function RebirthZoneService.RaidShieldBonus(profile: any): number
	return pick(Z.Zones.WestFlank.RaidShieldBonus, activeLevel(profile, profileOwner[profile], "WestFlank"))
end

function RebirthZoneService.SiloLevel(player: Player): number
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	return if profile then activeLevel(profile, player.UserId, "StrategicYard") else 0
end

local function publishArmy(player: Player, profile: any)
	pcall(function()
		player:SetAttribute("WE_RebirthArmyBonus", RebirthZoneService.ArmyBonus(profile))
	end)
end

-- ── placement ─────────────────────────────────────────────────────────────────────────────────────────────────────
local function zonesFolder(): Folder
	local f = Workspace:FindFirstChild(Z.FolderName)
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = Z.FolderName
		nf.Parent = Workspace
		f = nf
	end
	return f :: Folder
end

local function plotFolder(plotId: number): Folder
	local root = zonesFolder()
	local f = root:FindFirstChild("Plot" .. plotId)
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "Plot" .. plotId
		nf.Parent = root
		f = nf
	end
	return f :: Folder
end

local function annexFrame(plotId: number, zoneId: string): (CFrame?, any)
	local a = Z.Annex[zoneId]
	local ok, pos = pcall(PlotFrame.PlotPosition :: any, plotId)
	if a == nil or not ok or typeof(pos) ~= "Vector3" then
		return nil, nil
	end
	return PlotFrame.PlotCFrame(pos) * CFrame.new(a.X, 0, a.Z) * rotY(a.Yaw), a
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.RespectCanCollide = false

-- pure: a world (x, z) on the dry land the world uses
function RebirthZoneService.OnLand(x: number, z: number): boolean
	local L = WorldSitesConfig.Land
	return x >= L.X0 - 100 and x <= L.X1 + 100 and z >= L.Z0 - 100 and z <= L.Z1 + 100
end

local function clusterOf(p: Instance): Model?
	local m = p:FindFirstAncestorWhichIsA("Model")
	while m do
		if m:GetAttribute("WE_Cluster") ~= nil then
			return m
		end
		m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

local function checkSlot(plotId: number, zoneId: string): boolean
	local cache = slotOk[plotId]
	if cache == nil then
		cache = {}
		slotOk[plotId] = cache
	end
	if cache[zoneId] ~= nil then
		return cache[zoneId]
	end
	local frame, a = annexFrame(plotId, zoneId)
	if frame == nil or a == nil then
		cache[zoneId] = false
		return false
	end
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			local c = (frame * CFrame.new(dx * a.W * 0.5, 0, dz * a.D * 0.5)).Position
			if not RebirthZoneService.OnLand(c.X, c.Z) then
				cache[zoneId] = false
				print(string.format("[RebirthZones] plot %d %s: off the land", plotId, zoneId))
				return false
			end
		end
	end
	overlap.FilterDescendantsInstances = { zonesFolder() }
	local hits = Workspace:GetPartBoundsInBox(frame * CFrame.new(0, 20, 0), Vector3.new(a.W + 4, 40, a.D + 4), overlap)
	local clear: { [Model]: boolean } = {}
	for _, p in ipairs(hits) do
		if p.Size.X >= 300 and p.Size.Z >= 300 then
			continue -- the desert floor
		end
		local m = p:FindFirstAncestorWhichIsA("Model")
		if m and m:FindFirstChildOfClass("Humanoid") then
			continue -- a character / NPC standing there
		end
		local cl = clusterOf(p)
		local src = if cl then string.match(tostring(cl:GetAttribute("WE_Cluster")), "^([^:]+)") else nil
		if cl and src and Z.ClearableSources[src] == true then
			clear[cl] = true
		else
			cache[zoneId] = false
			print(string.format("[RebirthZones] plot %d %s: blocked by %s", plotId, zoneId, p:GetFullName()))
			return false
		end
	end
	local n = 0
	for cl in pairs(clear) do
		cl:Destroy()
		n += 1
	end
	if n > 0 then
		print(string.format("[RebirthZones] plot %d %s: cleared %d decor clusters", plotId, zoneId, n))
	end
	cache[zoneId] = true
	return true
end

-- ── build ─────────────────────────────────────────────────────────────────────────────────────────────────────────
local function trimOf(player: Player, profile: any): Color3
	local t = RebirthConfig.TrimFor(prestigeOf(profile), false)
	if RebirthConfig.LiveFor(player.UserId, "Trims") and t and typeof(t.Trim) == "Color3" then
		return t.Trim
	end
	return Color3.fromRGB(120, 116, 104)
end

local function costOf(zoneId: string, level: number): number
	local def = Z.Zones[zoneId]
	return if def then math.floor(tonumber(def.Cost[math.min(level + 1, #def.Cost)]) or 0) else 0
end

local function addPrompts(player: Player, plotId: number, zoneId: string, console: BasePart, level: number)
	local def = Z.Zones[zoneId]
	local p = Instance.new("ProximityPrompt")
	p.Name = "WE_ZonePrompt"
	p:SetAttribute("PlotId", plotId)
	p:SetAttribute("ZoneId", zoneId)
	p.HoldDuration = 0.3
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	if level >= Z.MaxLevel then
		p.ActionText = "MAX LEVEL"
		p.ObjectText = def.Name
		p.Enabled = false
	else
		p.ActionText = if level == 0 then "BUILD" else string.format("UPGRADE L%d", level + 1)
		p.ObjectText = string.format("%s  $%s", def.Name, tostring(costOf(zoneId, level)))
	end
	p:SetAttribute("Level", level) -- claude-bud JOB 46: the client preview card reads the level from here
	p.Parent = console
	local uid = player.UserId
	p.Triggered:Connect(function(who: Player)
		if who.UserId == uid then
			RebirthZoneService.Upgrade(who, zoneId)
		end
	end)
	if zoneId == "StrategicYard" and level >= 1 then
		local n = Instance.new("ProximityPrompt")
		n.Name = "WE_SiloPrompt"
		n.ActionText = "NUKE"
		n.ObjectText = "Silo control"
		n.KeyboardKeyCode = Enum.KeyCode.F
		n.GamepadKeyCode = Enum.KeyCode.ButtonY
		n.HoldDuration = 0.3
		n.MaxActivationDistance = 12
		n.RequiresLineOfSight = false
		n.UIOffset = Vector2.new(0, 70)
		n.Parent = console
		n.Triggered:Connect(function(who: Player)
			local ns = deps.NukeService
			if who.UserId == uid and ns and ns.OpenPanel then
				ns.OpenPanel(who)
			end
		end)
	end
end

-- claude-bud JOB 46: the annex's front apron (where the dressing goes) is checked once like the annex itself: decor is
-- cleared, anything else (a road, a building) means no apron dressing on that plot (logged)
local function checkApron(plotId: number, zoneId: string): boolean
	local cache = apronOk[plotId]
	if cache == nil then
		cache = {}
		apronOk[plotId] = cache
	end
	if cache[zoneId] ~= nil then
		return cache[zoneId]
	end
	local frame, a = annexFrame(plotId, zoneId)
	if frame == nil or a == nil then
		cache[zoneId] = false
		return false
	end
	overlap.FilterDescendantsInstances = { zonesFolder() }
	local box = frame * CFrame.new(0, 12, a.D * 0.5 + 10)
	local hits = Workspace:GetPartBoundsInBox(box, Vector3.new(a.W, 24, 16), overlap)
	local clear: { [Model]: boolean } = {}
	for _, p in ipairs(hits) do
		if p.Size.X >= 300 and p.Size.Z >= 300 then
			continue -- the desert floor
		end
		local m = p:FindFirstAncestorWhichIsA("Model")
		if m and m:FindFirstChildOfClass("Humanoid") then
			continue
		end
		local cl = clusterOf(p)
		local src = if cl then string.match(tostring(cl:GetAttribute("WE_Cluster")), "^([^:]+)") else nil
		if cl and src and Z.ClearableSources[src] == true then
			clear[cl] = true
		else
			cache[zoneId] = false
			print(string.format("[RebirthZones] plot %d %s: apron blocked by %s (no apron dressing)", plotId, zoneId, p:GetFullName()))
			return false
		end
	end
	for cl in pairs(clear) do
		cl:Destroy()
	end
	cache[zoneId] = true
	return true
end

local function tickSeconds(): number
	local okE, EC = pcall(function(): any
		return require(Shared.Configs.EconomyConfig)
	end)
	return if okE and EC then tonumber(EC.PassiveIncome.TickSeconds) or 5 else 5
end

local function notify(player: Player, text: string, kind: string)
	if deps.NotificationService then
		pcall(deps.NotificationService.Notify, player, text, kind, 4)
	end
end

local function clock(sec: number): string
	local s = math.max(0, math.ceil(sec))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

--[[ claude-bud JOB 46: the area's activity (RebirthZonesConfig.Info.Activity), server-side, owner only:
	ship = Shipment.Minutes of this zone's own flat income once every Shipment.CooldownMinutes (profile.ZoneShipAt,
	saved); sweep = the drones empty the ATM now; drill / strike = open the Elite Training / missile panel (FeaturePush
	"ZoneOpen"); nuke = NukeService.OpenPanel. Returns (ok, why). ]]
-- claude-bud JOB A: the position of HIS built kiosk for an activity ("drill" = the Recruitment Office's second
-- interaction point), or nil. Another player's kiosk is never returned (keyed by his UserId).
function RebirthZoneService.KioskPoint(player: Player, activity: string): Vector3?
	local mine = kioskOf[player.UserId]
	if mine == nil then
		return nil
	end
	for zoneId, panel in pairs(mine) do
		local info = ZC.Info[zoneId]
		if info and info.Activity == activity and panel.Parent then
			return panel.Position
		end
	end
	return nil
end

function RebirthZoneService.Activity(player: Player, zoneId: string, nowUnix: number?): (boolean, string)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	local info = ZC.Info[zoneId]
	if profile == nil or info == nil or not zonesLive(player.UserId) then
		return false, "off"
	end
	local lv = activeLevel(profile, player.UserId, zoneId)
	if lv < 1 then
		return false, "not_built"
	end
	local kind = info.Activity
	if kind == "ship" then
		local now = nowUnix or os.time()
		local t = if typeof(profile.ZoneShipAt) == "table" then profile.ZoneShipAt else {}
		profile.ZoneShipAt = t
		local last = tonumber(t[zoneId]) -- nil = never shipped: ready now
		local wait = if last then last + ZC.Shipment.CooldownMinutes * 60 - now else 0
		if wait > 0 then
			notify(player, string.format("Next %s in %s", string.lower(info.ActionText), clock(wait)), "Info")
			return false, "cooldown"
		end
		local cash = ZC.ShipmentCash(zoneId, lv, tickSeconds())
		if cash <= 0 then
			return false, "no_income"
		end
		t[zoneId] = now
		deps.DataService.MarkDirty(player)
		local es = deps.EconomyService
		if es and es.AddCash then
			es.AddCash(player, cash, "rebirthzone_ship")
		end
		notify(player, string.format("%s: +$%d", info.ActionText, cash), "Success")
		return true, "shipped"
	elseif kind == "sweep" then
		local now = os.clock()
		if now - (sweepAt[player.UserId] or -math.huge) < ZC.Sweep.CooldownSeconds then
			notify(player, "Drones are refuelling: sweep in " .. clock(ZC.Sweep.CooldownSeconds - (now - sweepAt[player.UserId])), "Info")
			return false, "cooldown"
		end
		local es = deps.EconomyService
		if es == nil or es.GetPendingCash == nil or (tonumber(es.GetPendingCash(player)) or 0) <= 0 then
			notify(player, "Your ATM is empty", "Info")
			return false, "empty"
		end
		sweepAt[player.UserId] = now
		pcall(es.CollectPendingCash, player)
		notify(player, "Drone sweep: your ATM is emptied", "Success")
		return true, "swept"
	elseif kind == "drill" or kind == "strike" then
		local rs = deps.RemoteSetup
		local ev = rs and rs.Get(require(Shared.Constants).RemoteNames.FeaturePush)
		if ev and ev:IsA("RemoteEvent") then
			local kp = kioskOf[player.UserId] and kioskOf[player.UserId][zoneId] -- claude-bud JOB A: the client's anchor point
			;(ev :: RemoteEvent):FireClient(player, "ZoneOpen", { Panel = if kind == "drill" then "Recruits" else "Missile", Zone = zoneId,
				Point = if kp and kp.Parent then kp.Position else nil })
		end
		return true, "opened"
	elseif kind == "nuke" then
		local ns = deps.NukeService
		if ns and ns.OpenPanel then
			ns.OpenPanel(player)
		end
		return true, "opened"
	end
	return false, "unknown"
end

local function addActivityPrompt(player: Player, zoneId: string, panel: BasePart)
	kioskOf[player.UserId] = kioskOf[player.UserId] or {}
	kioskOf[player.UserId][zoneId] = panel -- claude-bud JOB A: his kiosk (the Recruitment Office's second interaction point)
	local info = ZC.Info[zoneId]
	local z = Z.Zones[zoneId]
	local p = Instance.new("ProximityPrompt")
	p.Name = "WE_ZoneActivity"
	p:SetAttribute("ZoneId", zoneId)
	p.ActionText = info.ActionText
	p.ObjectText = z.Name
	p.HoldDuration = 0.2
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = panel
	local uid = player.UserId
	p.Triggered:Connect(function(who: Player)
		if who.UserId == uid then
			RebirthZoneService.Activity(who, zoneId)
		end
	end)
end

local function buildZone(player: Player, profile: any, plotId: number, zoneId: string)
	local pf = plotFolder(plotId)
	local old = pf:FindFirstChild("Zone_" .. zoneId)
	if old then
		old:Destroy()
	end
	local oldDress = pf:FindFirstChild("Dress_" .. zoneId) -- claude-bud JOB 46
	if oldDress then
		oldDress:Destroy()
	end
	if not checkSlot(plotId, zoneId) then
		return
	end
	local frame, a = annexFrame(plotId, zoneId)
	if frame == nil or a == nil or Builder == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Zone_" .. zoneId
	folder.Parent = pf
	if not reached(profile, zoneId) then
		local z = RebirthConfig.Zones[zoneId]
		Builder.Locked(zoneId, z and z.Tier or 1, frame, a.W, a.D, folder)
		return
	end
	local lv = levelOf(profile, zoneId)
	local console = Builder.Build(zoneId, lv, frame, a.W, a.D, trimOf(player, profile), folder)
	if console then
		addPrompts(player, plotId, zoneId, console, lv)
	end
	-- claude-bud JOB 46: a BUILT zone gets its dressing (gateway, themed props) and its activity kiosk on the apron
	if lv >= 1 and Dressing and checkApron(plotId, zoneId) then
		local dress = Instance.new("Folder")
		dress.Name = "Dress_" .. zoneId
		dress.Parent = pf
		local okD, panel = pcall(Dressing.Build, zoneId, lv, frame, a.D, trimOf(player, profile), dress)
		if okD and panel then
			addActivityPrompt(player, zoneId, panel)
		elseif not okD then
			warn("[RebirthZones] dressing failed:", zoneId, panel)
		end
	end
end

local function buildRank(player: Player, profile: any, plotId: number)
	local pf = plotFolder(plotId)
	local old = pf:FindFirstChild("Rank")
	if old then
		old:Destroy()
	end
	if not RebirthConfig.LiveFor(player.UserId, "Trims") or prestigeOf(profile) < 1 then
		return
	end
	local ok, pos = pcall(PlotFrame.PlotPosition :: any, plotId)
	if not ok or typeof(pos) ~= "Vector3" then
		return
	end
	local trim = RebirthConfig.TrimFor(prestigeOf(profile), false)
	local f = Instance.new("Folder")
	f.Name = "Rank"
	f.Parent = pf
	local base = PlotFrame.PlotCFrame(pos)
	local R = Z.Rank
	for _, s in ipairs({ -1, 1 }) do
		local cf = base * CFrame.new(s * R.BannerX, 0, R.BannerZ)
		local pole = Instance.new("Part")
		pole.Name = "RankPole"
		pole.Anchored = true
		pole.CanCollide = true
		pole.Size = Vector3.new(0.6, 14, 0.6)
		pole.CFrame = cf * CFrame.new(0, 7.5, 0)
		pole.Color = Color3.fromRGB(70, 70, 70)
		pole.Material = Enum.Material.Metal
		pole.Parent = f
		local banner = Instance.new("Part")
		banner.Name = "RankBanner"
		banner.Anchored = true
		banner.CanCollide = false
		banner.CanQuery = false
		banner.Size = Vector3.new(3.6, 7, 0.15)
		banner.CFrame = cf * CFrame.new(s * 2.1, 10, 0)
		banner.Color = trim.Trim
		banner.Material = Enum.Material.Fabric
		banner.Parent = f
	end
end

local function titleTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head == nil then
		return
	end
	local old = head:FindFirstChild("WE_RankTitle")
	if old then
		old:Destroy()
	end
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or not RebirthConfig.LiveFor(player.UserId, "Trims") then
		return
	end
	local title = RebirthConfig.TitleFor(prestigeOf(profile))
	if title == nil then
		return
	end
	local trim = RebirthConfig.TrimFor(prestigeOf(profile), false)
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_RankTitle"
	bb.Size = UDim2.fromOffset(170, 24)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = Z.Rank.TitleMaxDistance
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextSize = Z.Rank.TitlePx
	t.TextColor3 = trim.Accent
	t.TextStrokeTransparency = 0.3
	t.Text = string.upper(title)
	t.Parent = bb
	bb.Parent = head
end

--[[ (Re)build everything for this player's plot: the zones, the rank banners, the title, the army bonus. ]]
function RebirthZoneService.Refresh(player: Player)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	local bs = deps.BaseService
	local plotId = if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(player) else nil
	if profile == nil then
		return
	end
	profileOwner[profile] = player.UserId
	publishArmy(player, profile)
	pcall(titleTag, player)
	if plotId == nil then
		return
	end
	local prev = plotOf[player.UserId]
	if prev and prev ~= plotId then
		local pf = zonesFolder():FindFirstChild("Plot" .. prev)
		if pf then
			pf:Destroy()
		end
	end
	plotOf[player.UserId] = plotId
	if zonesLive(player.UserId) then
		for _, zoneId in ipairs(RebirthConfig.ZoneOrder) do
			local ok, err = pcall(buildZone :: any, player, profile, plotId, zoneId)
			if not ok then
				warn("[RebirthZones] build failed:", zoneId, err)
			end
		end
	end
	pcall(buildRank, player, profile, plotId)
end

function RebirthZoneService.Upgrade(player: Player, zoneId: string): (boolean, string?)
	local uid = player.UserId
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	local bs = deps.BaseService
	local plotId = if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(player) else nil
	if profile == nil or plotId == nil or not zonesLive(uid) or Z.Zones[zoneId] == nil then
		return false, "Off"
	end
	if deps.RateLimitService and not deps.RateLimitService.Allow(player, "rebirth_zone", 1, 2) then
		return false, "Rate"
	end
	if not reached(profile, zoneId) then
		return false, "Locked"
	end
	local lv = levelOf(profile, zoneId)
	if lv >= Z.MaxLevel then
		return false, "Max"
	end
	local cost = costOf(zoneId, lv)
	local okSpend = deps.EconomyService.SpendCash(player, cost, "rebirthzone_" .. zoneId)
	if not okSpend then
		if deps.NotificationService then
			pcall(deps.NotificationService.Notify, player, "Not enough Cash", "Warn", 3)
		end
		return false, "Cash"
	end
	if typeof(profile.RebirthZones) ~= "table" then
		profile.RebirthZones = {}
	end
	profile.RebirthZones[zoneId] = lv + 1
	deps.DataService.MarkDirty(player)
	local def = Z.Zones[zoneId]
	if deps.NotificationService then
		pcall(deps.NotificationService.Notify, player, string.format("%s level %d: %s", def.Name, lv + 1, def.Short), "Success", 5)
	end
	if deps.AnalyticsService then
		pcall(deps.AnalyticsService.Log, "REBIRTH_ZONE_BUILT", uid, { zone = zoneId, level = lv + 1 })
	end
	pcall(buildZone, player, profile, plotId, zoneId)
	publishArmy(player, profile)
	if deps.BaseService and deps.BaseService.PushState then
		pcall(deps.BaseService.PushState, player) -- the income per tick changed
	end
	return true, nil
end

-- the Drone Hangar: the owner's ATM emptied every AutoCollectSeconds
local function droneTick()
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = deps.DataService and deps.DataService.GetProfile(player)
		local lv = if profile then activeLevel(profile, player.UserId, "DroneBay") else 0
		if lv >= 1 then
			local every = pick(Z.Zones.DroneBay.AutoCollectSeconds, lv)
			if now - (lastCollect[player.UserId] or 0) >= every then
				lastCollect[player.UserId] = now
				local es = deps.EconomyService
				if es and es.GetPendingCash and es.CollectPendingCash and (tonumber(es.GetPendingCash(player)) or 0) > 0 then
					pcall(es.CollectPendingCash, player)
				end
			end
		end
	end
end

function RebirthZoneService.Init(d: { [string]: any })
	deps = d
	local okB, B = pcall(function(): any
		return require(script.Parent.Parent.Modules.RebirthZoneBuilder)
	end)
	Builder = if okB then B else nil
	if not okB then
		warn("[RebirthZones] builder failed to load:", B)
	end
	local okDr, Dr = pcall(function(): any
		return require(script.Parent.Parent.Modules.RebirthZoneDressing)
	end)
	Dressing = if okDr then Dr else nil -- claude-bud JOB 46
	d.DataService.OnProfileLoaded(function(player: Player, profile: any)
		profileOwner[profile] = player.UserId
		publishArmy(player, profile)
	end)
	if d.BaseService and d.BaseService.OnPlotReady then
		d.BaseService.OnPlotReady(function(player: Player, _plotId: number)
			task.defer(RebirthZoneService.Refresh, player)
		end)
	end
	local function hookChar(p: Player)
		p.CharacterAdded:Connect(function()
			task.delay(1, function()
				pcall(titleTag, p)
			end)
		end)
	end
	Players.PlayerAdded:Connect(hookChar)
	for _, p in ipairs(Players:GetPlayers()) do
		hookChar(p)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		local plotId = plotOf[p.UserId]
		plotOf[p.UserId] = nil
		lastCollect[p.UserId] = nil
		sweepAt[p.UserId] = nil
		kioskOf[p.UserId] = nil -- claude-bud JOB A
		if plotId then
			local pf = zonesFolder():FindFirstChild("Plot" .. plotId)
			if pf then
				pf:Destroy()
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			pcall(droneTick)
		end
	end)
	print("[WAR EMPIRE] RebirthZoneService Init: zones=" .. #RebirthConfig.ZoneOrder)
end

return RebirthZoneService
