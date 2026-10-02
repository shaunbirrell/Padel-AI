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
local ZoneRuns: any = nil -- claude-bud JOB 50: Modules/ZoneRuns (the runs behind the kiosk, owner-first via ZC.Rebuild)
local plaqueOf: { [number]: { [string]: TextLabel } } = {} -- claude-bud JOB 50: uid -> zoneId -> the plaque text
local ZC: any = RebirthZonesConfig
local apronOk: { [number]: { [string]: boolean } } = {} -- plotId -> zoneId -> the front apron is free (checked once)
local sweepAt: { [number]: number } = {} -- userId -> clock of the last drone sweep
local kioskOf: { [number]: { [string]: BasePart } } = {} -- claude-bud JOB A: userId -> zoneId -> his activity kiosk
local Z = RebirthZonesConfig

local plotOf: { [number]: number } = {} -- userId -> the plot his zones are built on
local slotOk: { [number]: { [string]: boolean } } = {} -- plotId -> zoneId -> annex usable (checked once per plot)
local profileOwner: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- profile -> userId
local lastCollect: { [number]: number } = {}

-- the plot's owner on this server (0 = none); Code Bot v219: the owner-first Slots gate reads it before any check
local function ownerOfPlot(plotId: number): number
	local bs = deps.BaseService
	local owner = if bs and bs.GetOwnerUserId then bs.GetOwnerUserId(plotId) else nil
	return if typeof(owner) == "number" then owner else 0
end

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

-- claude-bud JOB 69: the frame of a zone's annex at `slot` (nil = its own slot in Z.Annex). `a` = { X, Z, Yaw, W, D }.
local function annexFrameAt(plotId: number, zoneId: string, slot: any?): (CFrame?, any)
	local base = Z.Annex[zoneId]
	local ok, pos = pcall(PlotFrame.PlotPosition :: any, plotId)
	if base == nil or not ok or typeof(pos) ~= "Vector3" then
		return nil, nil
	end
	local sl = slot or base
	local a = { X = sl.X, Z = sl.Z, Yaw = sl.Yaw, W = base.W, D = base.D }
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

-- Code Bot v219: something that moves (a parked / driven vehicle, a dropped crate, a ragdoll) is not a reason to give
-- a zone no slot: the verdict is cached for the plot's life, so a jeep parked there once cost the zone for good
local function transient(p: BasePart): boolean
	if not p.Anchored then
		return true
	end
	local m = p:FindFirstAncestorWhichIsA("Model")
	return m ~= nil and (m:FindFirstChildWhichIsA("VehicleSeat", true) ~= nil or m:GetAttribute("WE_Vehicle") ~= nil)
end

local function checkSlotAt(plotId: number, zoneId: string, frame: CFrame?, a: any): boolean
	local cache = slotOk[plotId]
	if cache == nil then
		cache = {}
		slotOk[plotId] = cache
	end
	local key = if a then string.format("%s@%d,%d,%d", zoneId, a.X, a.Z, a.Yaw) else zoneId
	if cache[key] ~= nil then
		return cache[key]
	end
	if frame == nil or a == nil then
		cache[key] = false
		return false
	end
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			local c = (frame * CFrame.new(dx * a.W * 0.5, 0, dz * a.D * 0.5)).Position
			if not RebirthZoneService.OnLand(c.X, c.Z) then
				cache[key] = false
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
		if ZC.RebuildLive(ownerOfPlot(plotId), "Slots") and transient(p) then
			continue -- Code Bot v219 (owner-first with Rebuild.Slots): a vehicle / loose part is not a blocker
		end
		local cl = clusterOf(p)
		local src = if cl then string.match(tostring(cl:GetAttribute("WE_Cluster")), "^([^:]+)") else nil
		if cl and src and Z.ClearableSources[src] == true then
			clear[cl] = true
		else
			cache[key] = false
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
	cache[key] = true
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
local function checkApronAt(plotId: number, zoneId: string, frame: CFrame?, a: any): boolean
	local cache = apronOk[plotId]
	if cache == nil then
		cache = {}
		apronOk[plotId] = cache
	end
	local key = if a then string.format("%s@%d,%d,%d", zoneId, a.X, a.Z, a.Yaw) else zoneId
	if cache[key] ~= nil then
		return cache[key]
	end
	if frame == nil or a == nil then
		cache[key] = false
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
		if ZC.RebuildLive(ownerOfPlot(plotId), "Slots") and transient(p) then
			continue -- Code Bot v219
		end
		local cl = clusterOf(p)
		local src = if cl then string.match(tostring(cl:GetAttribute("WE_Cluster")), "^([^:]+)") else nil
		if cl and src and Z.ClearableSources[src] == true then
			clear[cl] = true
		else
			cache[key] = false
			print(string.format("[RebirthZones] plot %d %s: apron blocked by %s (no apron dressing)", plotId, zoneId, p:GetFullName()))
			return false
		end
	end
	for cl in pairs(clear) do
		cl:Destroy()
	end
	cache[key] = true
	return true
end

-- ── claude-bud JOB 69: every zone gets a slot (RebirthZonesConfig.ResolveSlots; owner-first by the plot owner) ────
local resolved: { [string]: { [string]: any } } = {} -- "<plotId>:<alts>" -> zoneId -> slot | false
local warnedBlocked: { [string]: boolean } = {}

local function altsFor(plotId: number): boolean
	local owner = ownerOfPlot(plotId)
	return owner ~= 0 and ZC.RebuildLive(owner, "Slots")
end

-- Code Bot v219: a plot whose last resolve left a zone without a slot is resolved again on the next Refresh (join /
-- rebirth / upgrade; no loop): only the NEGATIVE verdicts are dropped, so every zone that has a slot keeps it
local function retryBlocked(plotId: number)
	if not altsFor(plotId) then
		return
	end
	local key = plotId .. ":1"
	local res = resolved[key]
	if res == nil then
		return
	end
	local any = false
	for _, sl in pairs(res) do
		if sl == false then
			any = true
		end
	end
	if not any then
		return
	end
	resolved[key] = nil
	for _, cache in ipairs({ slotOk[plotId], apronOk[plotId] }) do
		if cache then
			for k, v in pairs(cache) do
				if v == false then
					cache[k] = nil
				end
			end
		end
	end
end

local function slotsOf(plotId: number): { [string]: any }
	local alts = altsFor(plotId)
	local key = plotId .. ":" .. (if alts then "1" else "0")
	local res = resolved[key]
	if res == nil then
		res = ZC.ResolveSlots(function(zoneId: string, slot: any): boolean
			local frame, a = annexFrameAt(plotId, zoneId, slot)
			if not checkSlotAt(plotId, zoneId, frame, a) then
				return false
			end
			-- with the fallbacks on, a slot must also have its front apron (kiosk / plaque / run markers); OFF = today
			return not alts or checkApronAt(plotId, zoneId, frame, a)
		end, alts)
		resolved[key] = res
		for zoneId, sl in pairs(res) do
			if sl == false and not warnedBlocked[plotId .. zoneId] then
				warnedBlocked[plotId .. zoneId] = true
				warn(string.format("[RebirthZones] plot %d %s: no free annex slot (%s)", plotId, zoneId, if alts then "ZONE BOARD in the base" else "own slot blocked"))
			end
		end
	end
	return res
end

-- the zone's annex frame on this plot (its own slot or the first free fallback); nil = no slot fits
local function slotFrame(plotId: number, zoneId: string): (CFrame?, any)
	local sl = slotsOf(plotId)[zoneId]
	if not sl then
		return nil, nil
	end
	return annexFrameAt(plotId, zoneId, sl)
end

local function checkSlot(plotId: number, zoneId: string): boolean
	return (slotFrame(plotId, zoneId)) ~= nil
end

local function checkApron(plotId: number, zoneId: string): boolean
	local frame, a = slotFrame(plotId, zoneId)
	return frame ~= nil and checkApronAt(plotId, zoneId, frame, a)
end

-- admin zonereport: every zone of a plot, its slot or BLOCKED
function RebirthZoneService.SlotReport(plotId: number): { string }
	local out = {}
	local res = slotsOf(plotId)
	for _, zoneId in ipairs(ZC.SlotOrder) do
		local sl = res[zoneId]
		local own = Z.Annex[zoneId]
		table.insert(out, string.format("P%d %s: %s", plotId, zoneId,
			if not sl then "BLOCKED (ZONE BOARD)" elseif sl.X == own.X and sl.Z == own.Z then "own slot" else string.format("fallback (%d,%d)", sl.X, sl.Z)))
	end
	return out
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

-- claude-bud JOB 50 A: the gateway plaque (a small board left of the gate): who unlocked it, the rebirth, the run's
-- best, ZONE COMMANDER. SurfaceGui MaxDistance 60 (<= 80), no lights, no Neon.
function RebirthZoneService._BuildPlaque(player: Player, profile: any, zoneId: string, frame: CFrame, D: number, parent: Instance)
	local post = Instance.new("Part")
	post.Name = "ZonePlaquePost"
	post.Anchored = true
	post.CanQuery = false
	post.CanTouch = false
	post.Size = Vector3.new(0.6, 4, 0.6)
	post.Material = Enum.Material.Metal
	post.Color = Color3.fromRGB(60, 62, 58)
	post.CFrame = frame * CFrame.new(-19, 2, D / 2 + 3)
	post.Parent = parent
	local board = Instance.new("Part")
	board.Name = "ZonePlaque"
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.Size = Vector3.new(6, 2.4, 0.3)
	board.Material = Enum.Material.Metal
	board.Color = Color3.fromRGB(150, 120, 60)
	board.CFrame = frame * CFrame.new(-19, 4.6, D / 2 + 3.3)
	board.Parent = parent
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.MaxDistance = 60
	sg.PixelsPerStud = 40
	sg.Parent = board
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(40, 32, 16)
	t.Parent = sg
	plaqueOf[player.UserId] = plaqueOf[player.UserId] or {}
	plaqueOf[player.UserId][zoneId] = t
	RebirthZoneService._RefreshPlaque(player, profile, zoneId)
end

function RebirthZoneService._RefreshPlaque(player: Player, profile: any, zoneId: string)
	local byZone = plaqueOf[player.UserId]
	local t: TextLabel? = if byZone then byZone[zoneId] else nil
	if t == nil or t.Parent == nil or ZoneRuns == nil then
		return
	end
	local z = RebirthConfig.Zones[zoneId]
	local best = if typeof(profile.ZoneBest) == "table" then tonumber(profile.ZoneBest[zoneId]) else nil
	local run = ZC.Runs[zoneId]
	local text = ZoneRuns.PlaqueText(player.DisplayName, if z then z.Tier else 1, best, profile.ZoneCommander == true,
		if run and run.Seconds > 0 then run.Title else nil)
	-- claude-bud JOB 50 C: the run's state on the gateway (READY / IN PROGRESS / NEXT RUN n MIN)
	if run and ZC.RebuildLive(player.UserId, "Signs") then
		local status = RebirthZoneService.RunStatusOf(player, profile, zoneId)
		text ..= "\n" .. status
	end
	if t.Text ~= text then
		t.Text = text
	end
end

-- claude-bud JOB 50 C: one zone's run state for him (READY / IN PROGRESS / NEXT RUN n MIN) + ready flag
function RebirthZoneService.RunStatusOf(player: Player, profile: any, zoneId: string): (string, boolean)
	local active: any = if ZoneRuns then ZoneRuns.Active(player.UserId) else nil
	local left = if ZoneRuns then ZoneRuns.CooldownLeft(profile, zoneId) else 0
	return ZC.RunStatus(left, active ~= nil and active.Zone == zoneId)
end

-- claude-bud JOB 50 C: HIS built zones for the map (his kiosks only; nil when Signs is not live for him)
function RebirthZoneService.MapRows(player: Player): { any }?
	if not ZC.RebuildLive(player.UserId, "Signs") or ZoneRuns == nil then
		return nil
	end
	local mine = kioskOf[player.UserId]
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if mine == nil or profile == nil then
		return nil
	end
	local rows = {}
	for _, zoneId in ipairs(RebirthConfig.ZoneOrder) do
		local panel = mine[zoneId]
		local zc = (Z.Zones :: any)[zoneId]
		if panel and panel.Parent and zc and ZC.Runs[zoneId] then
			local status, ready = RebirthZoneService.RunStatusOf(player, profile, zoneId)
			table.insert(rows, {
				Id = zoneId,
				N = string.upper(zc.Name),
				S = status,
				R = ready,
				X = math.floor(panel.Position.X),
				Y = math.floor(panel.Position.Y),
				Z = math.floor(panel.Position.Z),
			})
		end
	end
	return rows
end

-- claude-bud JOB 50 C: the plaques' status line every StatusRefreshSeconds, and ONE toast when a run comes ready
local wasReady: { [number]: { [string]: boolean } } = {}
function RebirthZoneService._StatusTick()
	if ZoneRuns == nil then
		return
	end
	for uid, byZone in pairs(plaqueOf) do
		local player = Players:GetPlayerByUserId(uid)
		local profile = if player and deps.DataService then deps.DataService.GetProfile(player) else nil
		if player and profile and ZC.RebuildLive(uid, "Signs") then
			local seen = wasReady[uid]
			if seen == nil then
				seen = {}
				wasReady[uid] = seen
			end
			for zoneId in pairs(byZone) do
				RebirthZoneService._RefreshPlaque(player, profile, zoneId)
				if ZC.Runs[zoneId] then
					local _, ready = RebirthZoneService.RunStatusOf(player, profile, zoneId)
					if ready and seen[zoneId] == false and ZC.RunRules.ReadyToast then
						local zc = (Z.Zones :: any)[zoneId]
						notify(player, string.format("%s ready: %s", ZC.Runs[zoneId].Title, string.upper(if zc then zc.Name else zoneId)), "Info")
					end
					seen[zoneId] = ready
				end
			end
		end
	end
end

-- claude-bud JOB 50 A: every zone at MaxLevel -> ZONE COMMANDER (free; a status title, saved once)
function RebirthZoneService._CheckCommander(player: Player, profile: any)
	if profile.ZoneCommander == true or not ZC.RebuildLive(player.UserId, "Plaques") then
		return
	end
	for zoneId in pairs(Z.Zones) do
		if levelOf(profile, zoneId) < Z.MaxLevel then
			return
		end
	end
	profile.ZoneCommander = true
	deps.DataService.MarkDirty(player)
	pcall(function()
		player:SetAttribute("WE_ZoneCommander", true)
	end)
	notify(player, "ZONE COMMANDER! Every rebirth zone at max level", "Success")
	for zoneId in pairs(Z.Zones) do
		RebirthZoneService._RefreshPlaque(player, profile, zoneId)
	end
end

function RebirthZoneService.Activity(player: Player, zoneId: string, nowUnix: number?): (boolean, string)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	local info = ZC.Info[zoneId]
	if profile == nil or info == nil or not zonesLive(player.UserId) then
		return false, "off"
	end
	local lv = activeLevel(profile, player.UserId, zoneId)
	if lv >= 1 and ZoneRuns and ZC.RebuildLive(player.UserId, "Activities") and ZC.Runs[zoneId] then
		-- claude-bud JOB 50 A: the kiosk starts this zone's run (server-timed, server-validated) instead of the one tap
		local bs = deps.BaseService
		local plotId = if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(player) else nil
		local frame, a = nil, nil
		if plotId then
			frame, a = slotFrame(plotId, zoneId)
		end
		if frame and a then
			local kp = kioskOf[player.UserId] and kioskOf[player.UserId][zoneId]
			local parent = if kp and kp.Parent then kp:FindFirstAncestorOfClass("Folder") else nil
			return ZoneRuns.Start(player, zoneId, lv, frame, a.W, a.D, parent or plotFolder(plotId :: number))
		end
	end
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
		local paidOk, paid = false, 0
		if es and es.AddCash then
			paidOk, paid = es.AddCash(player, cash, "rebirthzone_ship")
		end
		-- Code Bot v198: the cash credited (the DOUBLE WEEKEND doubles "rebirthzone_ship") + " · 2x"; display only
		local shown = if es and es.ToastAmount then es.ToastAmount(cash, paidOk, paid) else cash
		local tag = if es and es.ToastTag then es.ToastTag(player, "rebirthzone_ship") else ""
		notify(player, string.format("%s: +$%d%s", info.ActionText, shown, tag), "Success")
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

local function featurePush(player: Player, kind: string, data: any)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(require(Shared.Constants).RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, kind, data)
	end
end

-- claude-bud JOB 69 B: the how-to card before a zone run (Rebuild.HowTo, owner-first)
local function howToLive(uid: number, zoneId: string): boolean
	return ZC.RebuildLive(uid, "HowTo") and ZC.Runs[zoneId] ~= nil and ZC.Info[zoneId] ~= nil and ZC.Info[zoneId].HowTo ~= nil
end

function RebirthZoneService.Intro(player: Player, zoneId: string): boolean
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	local info = ZC.Info[zoneId]
	local run = ZC.Runs[zoneId]
	if profile == nil or info == nil or run == nil or info.HowTo == nil then
		return false
	end
	local H = info.HowTo
	local active: any = if ZoneRuns then ZoneRuns.Active(player.UserId) else nil
	local inProgress = nil
	if active then
		inProgress = { Title = active.Def.Title, Left = math.max(0, math.ceil(active.Deadline - ZoneRuns._clock())) }
	end
	local first = typeof(profile.ZoneFirstClear) == "table" and profile.ZoneFirstClear[zoneId] == true
	featurePush(player, "ZoneRunIntro", {
		Zone = zoneId,
		Title = run.Title,
		Goal = H.What,
		Steps = H.Steps,
		Reward = H.Reward,
		Seconds = H.TimeLimit,
		CooldownLeft = if ZoneRuns then ZoneRuns.CooldownLeft(profile, zoneId) else 0,
		Compact = first, -- the full card until the first clear (profile.ZoneFirstClear), then the compact one
		InProgress = inProgress,
	})
	return true
end

-- the card's buttons: "start" = the run (every server rule in Activity / ZoneRuns.Start); "cancel" = end his run, no
-- reward and NO cooldown
function RebirthZoneService.RequestRun(player: Player, action: any, zoneId: any): boolean
	if typeof(zoneId) ~= "string" or ZC.Info[zoneId] == nil or not ZC.RebuildLive(player.UserId, "HowTo") then
		return false
	end
	if action == "start" then
		local ok = RebirthZoneService.Activity(player, zoneId)
		return ok == true
	elseif action == "cancel" then
		local active: any = if ZoneRuns then ZoneRuns.Active(player.UserId) else nil
		if active == nil then
			return false
		end
		ZoneRuns.Cancel(player.UserId)
		featurePush(player, "ZoneRun", { Zone = active.Zone, Done = true, Won = false, Cancelled = true })
		notify(player, active.Def.Title .. " cancelled (no cooldown)", "Info")
		return true
	end
	return false
end

local function addActivityPrompt(player: Player, zoneId: string, panel: BasePart)
	kioskOf[player.UserId] = kioskOf[player.UserId] or {}
	kioskOf[player.UserId][zoneId] = panel -- claude-bud JOB A: his kiosk (the Recruitment Office's second interaction point)
	local info = ZC.Info[zoneId]
	local z = Z.Zones[zoneId]
	local uid = player.UserId
	local intro = howToLive(uid, zoneId)
	local p = Instance.new("ProximityPrompt")
	p.Name = "WE_ZoneActivity"
	p:SetAttribute("ZoneId", zoneId)
	p.ActionText = if intro then "START" else info.ActionText
	if intro then -- claude-bud JOB 69 B: START + "<RUN TITLE> · N s"
		local run = ZC.Runs[zoneId]
		p.ObjectText = if (tonumber(run.Seconds) or 0) > 0 then string.format("%s · %d s", run.Title, run.Seconds) else run.Title
	else
		p.ObjectText = z.Name
	end
	p.HoldDuration = 0.2
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = panel
	p.Triggered:Connect(function(who: Player)
		if who.UserId == uid then
			if intro then
				RebirthZoneService.Intro(who, zoneId)
			else
				RebirthZoneService.Activity(who, zoneId)
			end
		end
	end)
	-- claude-bud JOB 69 B: Elite Training back on the Elite Barracks kiosk (a second TRAIN prompt)
	if intro and info.Activity == "drill" then
		local t = Instance.new("ProximityPrompt")
		t.Name = "WE_ZoneTrain"
		t.ActionText = "TRAIN"
		t.ObjectText = "Elite Training"
		t.UIOffset = Vector2.new(0, 72)
		t.HoldDuration = 0.2
		t.MaxActivationDistance = 10
		t.RequiresLineOfSight = false
		t.Parent = panel
		t.Triggered:Connect(function(who: Player)
			if who.UserId == uid then
				featurePush(who, "ZoneOpen", { Panel = "Recruits", Zone = zoneId, Point = panel.Position })
			end
		end)
	end
end

-- claude-bud JOB 69: the ZONE BOARD (a small console in the base, BoardSpots by zone order) carrying the zone's prompts
function RebirthZoneService._ZoneBoard(player: Player, plotId: number, zoneId: string, lv: number, locked: boolean?)
	local idx = table.find(ZC.SlotOrder, zoneId) or 1
	local spot = ZC.BoardSpots[math.min(idx, #ZC.BoardSpots)]
	local ok, pos = pcall(PlotFrame.PlotPosition :: any, plotId)
	if not ok or typeof(pos) ~= "Vector3" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Zone_" .. zoneId
	folder:SetAttribute("WE_ZoneBoard", true)
	folder.Parent = plotFolder(plotId)
	local cf = PlotFrame.PlotCFrame(pos) * CFrame.new(spot.X, 0, spot.Z)
	local board = Instance.new("Part")
	board.Name = "ZoneBoard"
	board.Anchored = true
	board.Size = Vector3.new(3, 4, 0.6)
	board.CFrame = cf * CFrame.new(0, 2.5, 0)
	board.Color = Color3.fromRGB(46, 50, 44)
	board.Material = Enum.Material.Metal
	board.Parent = folder
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.MaxDistance = 40
	sg.PixelsPerStud = 40
	sg.Parent = board
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 205, 60)
	local zc = Z.Zones[zoneId]
	t.Text = "ZONE BOARD\n" .. string.upper(if zc then zc.Name else zoneId)
	t.Parent = sg
	if locked then
		local rz = RebirthConfig.Zones[zoneId]
		t.Text ..= string.format("\nUnlocks at Rebirth %d", if rz then rz.Tier or 1 else 1)
		folder:SetAttribute("WE_ZoneLocked", true)
		return
	end
	addPrompts(player, plotId, zoneId, board, lv)
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
		-- claude-bud JOB 69: no slot anywhere (fallbacks on): a ZONE BOARD inside the base so it can still be bought /
		-- upgraded (the zone's own buy / upgrade prompts on a small board; nothing is ever silently skipped)
		if altsFor(plotId) then
			-- Code Bot v219: a zone he has not reached yet gets its board too ("Unlocks at Rebirth N"), never nothing
			pcall(RebirthZoneService._ZoneBoard, player, plotId, zoneId, levelOf(profile, zoneId), not reached(profile, zoneId))
		end
		return
	end
	local frame, a = slotFrame(plotId, zoneId)
	if frame == nil or a == nil or Builder == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Zone_" .. zoneId
	folder:SetAttribute("WE_AnnexCFrame", frame) -- claude-bud JOB 69: where this zone stands (the store-prop dresser reads it)
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
		if ZC.RebuildLive(player.UserId, "Visuals") and Dressing.BuildRunProps then
			pcall(Dressing.BuildRunProps, zoneId, frame, a.W, a.D, trimOf(player, profile), dress) -- claude-bud JOB 50 B
		end
		if ZC.RebuildLive(player.UserId, "Plaques") then
			pcall(RebirthZoneService._BuildPlaque, player, profile, zoneId, frame, a.D, dress) -- claude-bud JOB 50 A
		end
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
	pcall(retryBlocked, plotId) -- Code Bot v219
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
	pcall(RebirthZoneService._CheckCommander, player, profile) -- claude-bud JOB 50 A
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
	-- claude-bud JOB 69 B: the how-to card's START / CANCEL (RemoteGate schema + a rate limit; the server decides)
	pcall(function()
		local ev = d.RemoteSetup and d.RemoteSetup.Get(require(Shared.Constants).RemoteNames.RequestZoneRun)
		if ev and ev:IsA("RemoteEvent") then
			(ev :: RemoteEvent).OnServerEvent:Connect(function(player: Player, action: any, zoneId: any)
				if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestZoneRun", action, zoneId) then
					return
				end
				if d.RateLimitService and not d.RateLimitService.Allow(player, "zone_run", 1, 2) then
					return
				end
				RebirthZoneService.RequestRun(player, action, zoneId)
			end)
		end
	end)
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
	local okZR, ZR = pcall(function(): any
		return require(script.Parent.Parent.Modules.ZoneRuns)
	end)
	ZoneRuns = if okZR then ZR else nil -- claude-bud JOB 50 A
	if ZoneRuns then
		ZoneRuns.Bind({
			DataService = d.DataService, EconomyService = d.EconomyService, CombatService = d.CombatService,
			NotificationService = d.NotificationService, RemoteSetup = d.RemoteSetup, AnalyticsService = d.AnalyticsService,
			OnRunEnded = function(p: Player, zoneId: string)
				local prof = d.DataService.GetProfile(p)
				if prof then
					RebirthZoneService._RefreshPlaque(p, prof, zoneId)
				end
			end,
		})
		if d.CombatService and d.CombatService.OnNPCDeath then
			d.CombatService.OnNPCDeath(ZoneRuns.OnNPCDeath)
		end
	end
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
		plaqueOf[p.UserId] = nil -- claude-bud JOB 50 A
		wasReady[p.UserId] = nil -- claude-bud JOB 50 C
		if ZoneRuns then
			ZoneRuns.Cancel(p.UserId)
		end
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
	task.spawn(function() -- claude-bud JOB 50 C: the gateway status line (every 30 s; text set only when it changed)
		while true do
			task.wait(math.max(5, tonumber(ZC.RunRules.StatusRefreshSeconds) or 30))
			pcall(RebirthZoneService._StatusTick)
		end
	end)
	print("[WAR EMPIRE] RebirthZoneService Init: zones=" .. #RebirthConfig.ZoneOrder)
end

return RebirthZoneService
