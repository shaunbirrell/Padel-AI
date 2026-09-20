--!strict
--[[
	WAR EMPIRE — Server Bootstrap
	Wires remotes + services. Request/action remotes only.

	CRITICAL: MapSetup runs BEFORE heavy service requires so a failed
	Combat/Vehicle/etc. module never leaves the player falling in void.
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

-- ── Map FIRST (before any heavy service require) ──────────────────────────
-- NEVER let MapSetup parse/require failure abort remotes + HUD (live void bug).
local MapSetup: any = nil
do
	local okMap, mapOrErr = pcall(require, Modules.MapSetup)
	if okMap then
		MapSetup = mapOrErr
	else
		warn("[WAR EMPIRE] CRITICAL: require(MapSetup) FAILED — remotes will still init. Err:", mapOrErr)
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

	-- Match playtest ground scale (≥6000) so large-map void-fall still lands on plate
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
	--[[ Idempotent: ensure WarEmpireSetup + collide Ground exist (server start + PlayerAdded). ]]
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	if not setup then
		print("[WAR EMPIRE] Map heal (" .. label .. "): WarEmpireSetup missing — Run()")
		runMapSetupOrFallback("MapSetup nil during heal (" .. label .. ")")
		return
	end
	if MapSetup == nil then
		-- Keep existing setup; still force a collide plate if Ground gone
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
			if not Workspace:FindFirstChild("WarEmpireSetup") then
				ensureVoidFallback("ForceRebuildGround failed (" .. label .. ")")
			end
		end
	end
end

if not Workspace:FindFirstChild("WarEmpireSetup") then
	runMapSetupOrFallback("MapSetup module failed to load")
else
	print("[WAR EMPIRE] WarEmpireSetup already present — skipping MapSetup.Run (FORCE rebuild Ground + SafetyCatch)")
	-- Re-assert gravity; soft-heal first, then ALWAYS delete+recreate Ground/SafetyCatch
	-- so stale place files / prior soft-heals cannot leave void holes.
	Workspace.Gravity = 196.2
	local CollectionService = game:GetService("CollectionService")
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local targetSize = (MapSetup and MapSetup.GROUND_SIZE) or 6400

	healOrRebuildMap("bootstrap-existing")

	setup = Workspace:FindFirstChild("WarEmpireSetup")
	-- Mandatory Output status after heal/rebuild
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
		-- Ensure WE_UpgradeSlot tags exist (stale place files / partial builds skip MapSetup)
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
			else
				print("[WAR EMPIRE] Re-tagged", retagged, "upgrade pads with WE_UpgradeSlot")
			end
		else
			-- Soft-heal: CanTouch on existing tagged pads
			for _, inst in ipairs(tagged) do
				if inst:IsA("BasePart") then
					inst.CanTouch = true
				end
			end
			print("[WAR EMPIRE] Upgrade slots OK:", taggedCount)
		end
	end
end


-- PlayerAdded: heal map if somehow missing (late join / rare destroy)
do
	local Players = game:GetService("Players")
	local function ensureMapForPlayer(player: Player)
		task.defer(function()
			if not Workspace:FindFirstChild("WarEmpireSetup") and not Workspace:FindFirstChild("WE_VoidFallback") then
				warn("[WAR EMPIRE] PlayerAdded map missing for", player.Name, "— healing")
				healOrRebuildMap("PlayerAdded:" .. player.Name)
			elseif Workspace:FindFirstChild("WarEmpireSetup") and MapSetup and MapSetup.EnsureGroundHealthy then
				local setup = Workspace:FindFirstChild("WarEmpireSetup")
				if setup then
					pcall(function()
						MapSetup.EnsureGroundHealthy(setup)
					end)
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(ensureMapForPlayer)
	for _, plr in ipairs(Players:GetPlayers()) do
		ensureMapForPlayer(plr)
	end
end

-- ── Remotes FIRST (before any service require that can throw) ───────────────
local RemoteSetup = require(Modules.RemoteSetup)
RemoteSetup.Init() -- client Remotes.GetEvent must never hang on empty folder

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
local SeasonService = safeRequire("SeasonService", Services.SeasonService)
local ClanWarService = safeRequire("ClanWarService", Services.ClanWarService)
local CodesService = safeRequire("CodesService", Services.CodesService)
local NationColorService = safeRequire("NationColorService", Services.NationColorService)
local CaptureStipendService = safeRequire("CaptureStipendService", Services.CaptureStipendService)
local SupplyDropService = safeRequire("SupplyDropService", Services.SupplyDropService)
local BankRaidService = safeRequire("BankRaidService", Services.BankRaidService)
local SpinnerService = safeRequire("SpinnerService", Services.SpinnerService)
local UpgradePadService = safeRequire("UpgradePadService", Services.UpgradePadService)
local FallSafetyService = safeRequire("FallSafetyService", Services.FallSafetyService)
local MoneyCollectorService = safeRequire("MoneyCollectorService", Services.MoneyCollectorService)
local VisualAssetService = safeRequire("VisualAssetService", Services.VisualAssetService)
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
	SeasonService = SeasonService,
	ClanWarService = ClanWarService,
	CodesService = CodesService,
	NationColorService = NationColorService,
	CaptureStipendService = CaptureStipendService,
	SupplyDropService = SupplyDropService,
	BankRaidService = BankRaidService,
	SpinnerService = SpinnerService,
	UpgradePadService = UpgradePadService,
	FallSafetyService = FallSafetyService,
	MoneyCollectorService = MoneyCollectorService,
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

safeInit("RateLimitService", RateLimitService)
safeInit("AnalyticsService", AnalyticsService)
if DataService and AnalyticsService and DataService.SetAnalytics then
	pcall(DataService.SetAnalytics, AnalyticsService)
end

-- Init services that OnProfileLoaded depends on BEFORE DataService loads players
safeInit("NotificationService", NotificationService, deps)
safeInit("AntiExploitService", AntiExploitService, deps)
safeInit("MonetizationService", MonetizationService, deps)
safeInit("EconomyService", EconomyService, deps)
safeInit("XPService", XPService, deps)
safeInit("MoneyCollectorService", MoneyCollectorService, deps)
safeInit("BaseService", BaseService, deps) -- registers OnProfileLoaded + PurchaseUpgrade remote
safeInit("UpgradePadService", UpgradePadService, deps) -- server walk-over buy
safeInit("FallSafetyService", FallSafetyService, deps)
safeInit("TutorialService", TutorialService, deps)

-- Now load profiles (fires OnProfileLoaded for joiners)
safeInit("DataService", DataService)

-- Studio-only auto BUY smoke (IsStudio gated inside module)
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
safeInit("SeasonService", SeasonService, deps)
safeInit("ClanWarService", ClanWarService, deps)
safeInit("CodesService", CodesService, deps)
safeInit("CaptureStipendService", CaptureStipendService, deps)
safeInit("SupplyDropService", SupplyDropService, deps)
safeInit("BankRaidService", BankRaidService, deps)
safeInit("SpinnerService", SpinnerService, deps)

if DevConfig.VerboseLogging then
	print("[WAR EMPIRE] Services initialized. Plots:", Constants.MaxBasePlots)
end

print("[WAR EMPIRE] Server Bootstrap ready.")
print("[WAR EMPIRE] CHECKLIST: 1) resetmap MANDATORY if void/dead-space persists (stale WarEmpireSetup keeps old holes)  2) Output must show Ground AFTER heal size/CanCollide  3) stand on YOUR Command Center pad — big BUY button + [UpgradePad] BUY ATTEMPT/OK  4) dock tiles toast + B menu BUY")
