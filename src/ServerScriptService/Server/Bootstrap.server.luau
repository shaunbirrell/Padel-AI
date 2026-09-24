--!strict
--[[
	WAR EMPIRE — Server Bootstrap
	Wires remotes + services. Request/action remotes only.

	v65 CRITICAL: DataService.Init FIRST; then Economy/Base; remotes before MapSetup.
	Map densify InsertService must never block EconomyUpdate (HUD $… forever).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local DevConfig = require(Shared.Configs.DevConfig)

local ServerFolder = script.Parent
local Modules = ServerFolder:WaitForChild("Modules")
local Services = ServerFolder:WaitForChild("Services")

print("[WAR EMPIRE] Server Bootstrap starting...")

-- ── 1. REMOTES FIRST (before any MapSetup / InsertService) ─────────────────
local RemoteSetup = require(Modules.RemoteSetup)
RemoteSetup.Init() -- client Remotes.GetEvent / EconomyUpdate must never hang on empty folder
print("[WAR EMPIRE] Remotes ready BEFORE map (v60 WE_Remotes + cash-first)")

local function safeRequire(label: string, moduleScript: ModuleScript): any
	local ok, mod = pcall(require, moduleScript)
	if not ok then
		warn("[WAR EMPIRE] require FAILED:", label, mod)
		return nil
	end
	return mod
end

local DataService = safeRequire("DataService", Services.DataService)
local EconomyService = safeRequire("EconomyService", Services.EconomyService)
local BaseService = safeRequire("BaseService", Services.BaseService)
local XPService = safeRequire("XPService", Services.XPService)
local RateLimitService = safeRequire("RateLimitService", Services.RateLimitService)
local AnalyticsService = safeRequire("AnalyticsService", Services.AnalyticsService)
local AdminService = safeRequire("AdminService", Services.AdminService)
local NotificationService = safeRequire("NotificationService", Services.NotificationService)
local AntiExploitService = safeRequire("AntiExploitService", Services.AntiExploitService)
local CombatService = safeRequire("CombatService", Services.CombatService)
local VehicleService = safeRequire("VehicleService", Services.VehicleService)
local TerritoryService = safeRequire("TerritoryService", Services.TerritoryService)
local MissionService = safeRequire("MissionService", Services.MissionService)
local PrestigeService = safeRequire("PrestigeService", Services.PrestigeService)
local ClanService = safeRequire("ClanService", Services.ClanService)
local MonetizationService = safeRequire("MonetizationService", Services.MonetizationService)
local TutorialService = safeRequire("TutorialService", Services.TutorialService)
local BattlePassService = safeRequire("BattlePassService", Services.BattlePassService)
local SoldierService = safeRequire("SoldierService", Services.SoldierService)
local SquadOrdersService = safeRequire("SquadOrdersService", Services.SquadOrdersService)
local SeasonService = safeRequire("SeasonService", Services.SeasonService)
local ClanWarService = safeRequire("ClanWarService", Services.ClanWarService)
local CodesService = safeRequire("CodesService", Services.CodesService)
local NationColorService = safeRequire("NationColorService", Services.NationColorService)
local CaptureStipendService = safeRequire("CaptureStipendService", Services.CaptureStipendService)
local SupplyDropService = safeRequire("SupplyDropService", Services.SupplyDropService)
local BankRaidService = safeRequire("BankRaidService", Services.BankRaidService)
local SpinnerService = safeRequire("SpinnerService", Services.SpinnerService)
local UpgradePadService = safeRequire("UpgradePadService", Services.UpgradePadService)
local PremiumPadService = safeRequire("PremiumPadService", Services.PremiumPadService)
local FallSafetyService = safeRequire("FallSafetyService", Services.FallSafetyService)
local MoneyCollectorService = safeRequire("MoneyCollectorService", Services.MoneyCollectorService)
local ManualDropperService = safeRequire("ManualDropperService", Services.ManualDropperService)
local VisualAssetService = safeRequire("VisualAssetService", Services.VisualAssetService)
local GateDefenseService = safeRequire("GateDefenseService", Services.GateDefenseService)
local PlotOilPumpService = safeRequire("PlotOilPumpService", Services.PlotOilPumpService)
local StudioBuySmoke = safeRequire("StudioBuySmoke", Modules.StudioBuySmoke)

RemoteSetup.Init() -- idempotent; ensure remotes still present after requires

local deps: { [string]: any } = {
	RemoteSetup = RemoteSetup,
	DataService = DataService,
	EconomyService = EconomyService,
	BaseService = BaseService,
	XPService = XPService,
	RateLimitService = RateLimitService,
	AnalyticsService = AnalyticsService,
	AdminService = AdminService,
	NotificationService = NotificationService,
	AntiExploitService = AntiExploitService,
	CombatService = CombatService,
	VehicleService = VehicleService,
	TerritoryService = TerritoryService,
	MissionService = MissionService,
	PrestigeService = PrestigeService,
	ClanService = ClanService,
	MonetizationService = MonetizationService,
	TutorialService = TutorialService,
	BattlePassService = BattlePassService,
	SoldierService = SoldierService,
	SquadOrdersService = SquadOrdersService,
	SeasonService = SeasonService,
	ClanWarService = ClanWarService,
	CodesService = CodesService,
	NationColorService = NationColorService,
	CaptureStipendService = CaptureStipendService,
	SupplyDropService = SupplyDropService,
	BankRaidService = BankRaidService,
	SpinnerService = SpinnerService,
	UpgradePadService = UpgradePadService,
	PremiumPadService = PremiumPadService,
	FallSafetyService = FallSafetyService,
	MoneyCollectorService = MoneyCollectorService,
	VisualAssetService = VisualAssetService,
	ManualDropperService = ManualDropperService,
	GateDefenseService = GateDefenseService,
	PlotOilPumpService = PlotOilPumpService,
}

local function safeInit(label: string, svc: any, ...: any)
	if svc == nil then
		warn("[WAR EMPIRE] skip Init (nil):", label)
		return
	end
	local args = { ... }
	local ok, err = pcall(function()
		if #args > 0 then
			svc.Init(table.unpack(args))
		else
			svc.Init()
		end
	end)
	if not ok then
		warn("[WAR EMPIRE] Init FAILED:", label, err)
	end
end

-- v45: set after BaseService Init — refresh kits/walls after any map rebuild (race fix)
local afterMapRebuild: (() -> ())? = nil

local function notifyMapRebuilt(label: string)
	if afterMapRebuild then
		print("[WAR EMPIRE] afterMapRebuild → RefreshAllOnlinePlayers (" .. label .. ")")
		task.defer(afterMapRebuild)
	end
end

-- ── 2. CASH PATH FIRST (instant profile + Push; map must not block) ─────────
-- v65: warn loudly if safeRequire failed (nil module → Buy GetProfile crash)
if DataService == nil then
	warn("[WAR EMPIRE] CRITICAL: DataService safeRequire FAILED — buy path will break until fixed")
end
if EconomyService == nil then
	warn("[WAR EMPIRE] CRITICAL: EconomyService safeRequire FAILED")
end
if BaseService == nil then
	warn("[WAR EMPIRE] CRITICAL: BaseService safeRequire FAILED")
end

safeInit("RateLimitService", RateLimitService)
safeInit("AnalyticsService", AnalyticsService)
if DataService and AnalyticsService and DataService.SetAnalytics then
	pcall(DataService.SetAnalytics, AnalyticsService)
end

-- v65 CRITICAL: DataService.Init FIRST before Economy/Base/UpgradePad
-- (module-local DataService in BaseService was nil when Init order raced / deps cleared)
safeInit("DataService", DataService)
print("[WAR EMPIRE] DataService Init FIRST (v65) — before Economy/Base/UpgradePad")

-- v66: warn only. The v65 assert killed this whole script when DataService failed to load
-- (ProfileSchema parse error since v50), so no purchase handler, map or later service ever ran.
if deps.DataService == nil then
	warn("[WAR EMPIRE] CRITICAL: deps.DataService is nil before BaseService.Init — buy will fail")
end

safeInit("NotificationService", NotificationService, deps)
-- v69: TutorialService right after its deps (DataService, RemoteSetup, RateLimit, Notification) and BEFORE every
-- service that calls TutorialService.Notify (Economy, MoneyCollector, ManualDropper, Base …). BaseService's
-- OnProfileLoaded fires at once for already-loaded players and used to call Notify before this Init → threw.
-- (TutorialService.Init only needs BaseService.GetUpgradeChangedEvent, which works before BaseService.Init.)
safeInit("TutorialService", TutorialService, deps)
safeInit("AntiExploitService", AntiExploitService, deps)
safeInit("MonetizationService", MonetizationService, deps)
safeInit("EconomyService", EconomyService, deps)
safeInit("XPService", XPService, deps)
safeInit("MoneyCollectorService", MoneyCollectorService, deps)
safeInit("ManualDropperService", ManualDropperService, deps)
safeInit("BaseService", BaseService, deps) -- registers OnProfileLoaded + PurchaseUpgrade remote
afterMapRebuild = function()
	if BaseService and BaseService.RefreshAllOnlinePlayers then
		pcall(BaseService.RefreshAllOnlinePlayers)
	end
end
print("[WAR EMPIRE] DataService/EconomyService ready BEFORE map (v61)")
print("[WAR EMPIRE] v65 DataService-first + getDataService fallback + attribute-ack buy")
safeInit("UpgradePadService", UpgradePadService, deps)
safeInit("PremiumPadService", PremiumPadService, deps)
safeInit("FallSafetyService", FallSafetyService, deps)

-- Belt: EconomyService.Push within first second regardless of map state
do
	local Players = game:GetService("Players")
	local function earlyCashPush(player: Player)
		task.spawn(function()
			local deadline = os.clock() + 1.0
			while os.clock() < deadline do
				local profile = nil
				if DataService and DataService.GetProfile then
					profile = DataService.GetProfile(player)
				end
				if profile then
					if EconomyService and EconomyService.Push then
						pcall(EconomyService.Push, player)
					end
					return
				end
				task.wait(0.05)
			end
			if DataService and DataService.EnsureProfile then
				pcall(DataService.EnsureProfile, player)
			end
			if EconomyService and EconomyService.Push then
				pcall(EconomyService.Push, player)
			end
		end)
	end
	Players.PlayerAdded:Connect(earlyCashPush)
	for _, plr in ipairs(Players:GetPlayers()) do
		earlyCashPush(plr)
	end
end

-- ── 3. MAP AFTER REMOTES + CASH (densify InsertService is deferred inside MapSetup) ─
-- NEVER let MapSetup parse/require failure abort remotes + HUD (live void bug).
local MapSetup: any = nil
do
	local okMap, mapOrErr = pcall(require, Modules.MapSetup)
	if okMap then
		MapSetup = mapOrErr
	else
		warn("[WAR EMPIRE] CRITICAL: require(MapSetup) FAILED — remotes already live. Err:", mapOrErr)
	end
end

local function ensureVoidFallback(reason: string)
	warn("[WAR EMPIRE] CRITICAL: MapSetup failed — installing void fallback. Reason: " .. tostring(reason))
	print("[WAR EMPIRE] ERROR: MapSetup did not build WarEmpireSetup. Creating emergency baseplate + spawn so players do not void-fall.")

	Workspace.Gravity = 196.2

	local existing = Workspace:FindFirstChild("WE_VoidFallback")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "WE_VoidFallback"
	folder.Parent = Workspace

	local baseplate = Instance.new("Part")
	baseplate.Name = "Baseplate"
	baseplate.Size = Vector3.new(7000, 6, 7000)
	baseplate.Position = Vector3.new(0, -3, 0)
	baseplate.Anchored = true
	baseplate.CanCollide = true
	baseplate.Material = Enum.Material.Grass
	baseplate.Color = Color3.fromRGB(40, 80, 40)
	baseplate.TopSurface = Enum.SurfaceType.Smooth
	baseplate.BottomSurface = Enum.SurfaceType.Smooth
	baseplate.Parent = folder

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "EmergencySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 5, 0)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.BrickColor = BrickColor.new("Bright green")
	spawn.Material = Enum.Material.Neon
	spawn.Parent = folder

	print("[WAR EMPIRE] Void fallback ready: WE_VoidFallback Baseplate + EmergencySpawn at (0,5,0)")
end

local function runMapSetupOrFallback(reasonIfNil: string)
	if MapSetup == nil then
		ensureVoidFallback(reasonIfNil)
		return
	end
	local ok, err = pcall(function()
		MapSetup.Run()
	end)
	if not ok then
		ensureVoidFallback(err)
	elseif not Workspace:FindFirstChild("WarEmpireSetup") then
		ensureVoidFallback("MapSetup.Run returned but WarEmpireSetup missing")
	end
end

local function healOrRebuildMap(label: string)
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	if not setup then
		print("[WAR EMPIRE] Map heal (" .. label .. "): WarEmpireSetup missing — Run()")
		runMapSetupOrFallback("MapSetup nil during heal (" .. label .. ")")
		notifyMapRebuilt(label .. ":missing-run")
		return
	end
	if MapSetup == nil then
		local map = setup:FindFirstChild("Map")
		local g = map and map:FindFirstChild("Ground")
		if not (g and g:IsA("BasePart") and g.CanCollide) then
			ensureVoidFallback("MapSetup nil and Ground unhealthy (" .. label .. ")")
		end
		return
	end
	Workspace.Gravity = 196.2
	if MapSetup.EnsureGroundHealthy then
		pcall(function()
			MapSetup.EnsureGroundHealthy(setup)
		end)
	end
	if MapSetup.ForceRebuildGround then
		local okRebuild, rebuildResult = pcall(function()
			return MapSetup.ForceRebuildGround(setup)
		end)
		if not (okRebuild and rebuildResult == true) then
			warn("[WAR EMPIRE] ForceRebuildGround failed (" .. label .. ") — full MapSetup.Run")
			pcall(function()
				setup:Destroy()
				MapSetup.Run()
			end)
			notifyMapRebuilt(label .. ":ForceRebuildGround-Run")
			if not Workspace:FindFirstChild("WarEmpireSetup") then
				ensureVoidFallback("ForceRebuildGround failed (" .. label .. ")")
			end
		end
	end
end

-- Run map build/heal AFTER remotes exist (never blocks EconomyUpdate creation)
if not Workspace:FindFirstChild("WarEmpireSetup") then
	runMapSetupOrFallback("MapSetup module failed to load")
else
	print("[WAR EMPIRE] WarEmpireSetup already present — skipping MapSetup.Run (FORCE rebuild Ground + SafetyCatch)")
	Workspace.Gravity = 196.2
	local CollectionService = game:GetService("CollectionService")
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local targetSize = (MapSetup and MapSetup.GROUND_SIZE) or 6400

	healOrRebuildMap("bootstrap-existing")

	setup = Workspace:FindFirstChild("WarEmpireSetup")
	local mapFolder = setup and setup:FindFirstChild("Map")
	local g = mapFolder and mapFolder:FindFirstChild("Ground")
	local catch = mapFolder and mapFolder:FindFirstChild("SafetyCatch")
	if g and g:IsA("BasePart") then
		g.CanCollide = true
		g.Anchored = true
		print(string.format(
			"[WAR EMPIRE] Ground AFTER heal: size=%.0fx%.0fx%.0f CanCollide=%s SafetyCatch=%s",
			g.Size.X,
			g.Size.Y,
			g.Size.Z,
			tostring(g.CanCollide),
			tostring(catch ~= nil)
		))
		if g.Size.X < targetSize - 1 or g.CanCollide ~= true then
			warn("[WAR EMPIRE] Ground still unhealthy after force rebuild — run admin resetmap (Studio)")
		end
	else
		warn("[WAR EMPIRE] Ground MISSING after force rebuild — run admin resetmap (Studio) MANDATORY")
	end

	setup = Workspace:FindFirstChild("WarEmpireSetup")
	if setup then
		local tagged = CollectionService:GetTagged(Constants.Tags.UpgradeSlot)
		local taggedCount = #tagged
		if taggedCount == 0 then
			local bases = setup:FindFirstChild("Bases")
			local retagged = 0
			if bases then
				for _, desc in ipairs(bases:GetDescendants()) do
					if desc:IsA("BasePart") then
						local sid = desc:GetAttribute("StructureId")
						local pid = desc:GetAttribute("PlotId")
						if typeof(sid) == "string" and typeof(pid) == "number" then
							CollectionService:AddTag(desc, Constants.Tags.UpgradeSlot)
							desc.CanTouch = true
							retagged += 1
						end
					end
				end
			end
			if retagged == 0 then
				warn("[WAR EMPIRE] WarEmpireSetup present but no upgrade pads — rebuilding via MapSetup")
				pcall(function()
					setup:Destroy()
				end)
				runMapSetupOrFallback("Missing upgrade pads and MapSetup nil")
				notifyMapRebuilt("bootstrap-missingPads")
			else
				print("[WAR EMPIRE] Re-tagged", retagged, "upgrade pads with WE_UpgradeSlot")
			end
		else
			for _, inst in ipairs(tagged) do
				if inst:IsA("BasePart") then
					inst.CanTouch = true
				end
			end
			print("[WAR EMPIRE] Upgrade slots OK:", taggedCount)
		end
	end
end

-- v67: base labels stop drawing over everything (AlwaysOnTop off, capped range) — map exists now,
-- and DescendantAdded catches labels services create later (ATM, droppers, soldiers, gate).
do
	local WorldLabelPolicy = safeRequire("WorldLabelPolicy", Modules.WorldLabelPolicy)
	if WorldLabelPolicy and WorldLabelPolicy.Init then
		local okLabels, errLabels = pcall(WorldLabelPolicy.Init)
		if not okLabels then
			warn("[WAR EMPIRE] WorldLabelPolicy.Init failed:", errLabels)
		end
	end
end

-- PlayerAdded: heal map if somehow missing (late join / rare destroy)
do
	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")
	local function ensureMapForPlayer(player: Player)
		task.defer(function()
			local okHeal, errHeal = pcall(function()
				local setup = Workspace:FindFirstChild("WarEmpireSetup")
				if not setup and not Workspace:FindFirstChild("WE_VoidFallback") then
					warn("[WAR EMPIRE] PlayerAdded map missing for", player.Name, "— healing")
					healOrRebuildMap("PlayerAdded:" .. player.Name)
					notifyMapRebuilt("PlayerAdded:" .. player.Name)
					return
				end
				if not setup then
					return
				end
				local padCount = 0
				pcall(function()
					padCount = #CollectionService:GetTagged(Constants.Tags.UpgradeSlot)
				end)
				if padCount == 0 then
					local bases = setup:FindFirstChild("Bases")
					local hasPlotPad = false
					if bases then
						for _, d in ipairs(bases:GetDescendants()) do
							if d:IsA("BasePart") and d.Name == "PlotPad" then
								hasPlotPad = true
								break
							end
						end
					end
					if not hasPlotPad then
						warn("[WAR EMPIRE] PlayerAdded: WarEmpireSetup has no PlotPad/upgrade pads — full MapSetup rebuild for", player.Name)
						pcall(function()
							setup:Destroy()
						end)
						local voidFb = Workspace:FindFirstChild("WE_VoidFallback")
						if voidFb then
							pcall(function()
								voidFb:Destroy()
							end)
						end
						healOrRebuildMap("PlayerAdded-missingPads:" .. player.Name)
						notifyMapRebuilt("PlayerAdded-missingPads:" .. player.Name)
						return
					end
				end
				if MapSetup and MapSetup.EnsureGroundHealthy then
					MapSetup.EnsureGroundHealthy(setup)
				end
			end)
			if not okHeal then
				warn("[WAR EMPIRE] PlayerAdded map heal error (remotes continue):", errHeal)
			end
		end)
	end
	Players.PlayerAdded:Connect(ensureMapForPlayer)
	for _, plr in ipairs(Players:GetPlayers()) do
		ensureMapForPlayer(plr)
	end
end

-- ── 4. Remaining services ───────────────────────────────────────────────────
safeInit("StudioBuySmoke", StudioBuySmoke, deps)
safeInit("AdminService", AdminService, deps)
safeInit("VisualAssetService", VisualAssetService)
safeInit("CombatService", CombatService, deps)
safeInit("VehicleService", VehicleService, deps)
safeInit("NationColorService", NationColorService, deps)
safeInit("TerritoryService", TerritoryService, deps)
safeInit("MissionService", MissionService, deps)
safeInit("PrestigeService", PrestigeService, deps)
safeInit("ClanService", ClanService, deps)
safeInit("BattlePassService", BattlePassService, deps)
safeInit("SoldierService", SoldierService, deps)
safeInit("SquadOrdersService", SquadOrdersService, deps)
safeInit("SeasonService", SeasonService, deps)
safeInit("ClanWarService", ClanWarService, deps)
safeInit("CodesService", CodesService, deps)
safeInit("CaptureStipendService", CaptureStipendService, deps)
safeInit("SupplyDropService", SupplyDropService, deps)
safeInit("BankRaidService", BankRaidService, deps)
safeInit("GateDefenseService", GateDefenseService, deps)
safeInit("PlotOilPumpService", PlotOilPumpService, deps)
safeInit("SpinnerService", SpinnerService, deps)

if DevConfig.VerboseLogging then
	print("[WAR EMPIRE] Services initialized. Plots:", Constants.MaxBasePlots)
end

print("[WAR EMPIRE] Server Bootstrap ready.")
print("[WAR EMPIRE] CHECKLIST: 1) resetmap MANDATORY if void/dead-space persists (stale WarEmpireSetup keeps old holes)  2) Output must show Ground AFTER heal size/CanCollide  3) stand on YOUR Command Center pad — big BUY button + [UpgradePad] BUY ATTEMPT/OK  4) dock tiles toast + B menu BUY")
