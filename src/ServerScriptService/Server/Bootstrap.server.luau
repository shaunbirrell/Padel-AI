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
local MapSetup = require(Modules.MapSetup)

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

if not Workspace:FindFirstChild("WarEmpireSetup") then
	local ok, err = pcall(function()
		MapSetup.Run()
	end)
	if not ok then
		ensureVoidFallback(err)
	elseif not Workspace:FindFirstChild("WarEmpireSetup") then
		ensureVoidFallback("MapSetup.Run returned but WarEmpireSetup missing")
	end
else
	print("[WAR EMPIRE] WarEmpireSetup already present — skipping MapSetup.Run (FORCE rebuild Ground + SafetyCatch)")
	-- Re-assert gravity; soft-heal first, then ALWAYS delete+recreate Ground/SafetyCatch
	-- so stale place files / prior soft-heals cannot leave void holes.
	Workspace.Gravity = 196.2
	local CollectionService = game:GetService("CollectionService")
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local targetSize = MapSetup.GROUND_SIZE or 6400

	if setup and MapSetup.EnsureGroundHealthy then
		pcall(function()
			MapSetup.EnsureGroundHealthy(setup)
		end)
	end

	local rebuilt = false
	if setup and MapSetup.ForceRebuildGround then
		local okRebuild, rebuildResult = pcall(function()
			return MapSetup.ForceRebuildGround(setup)
		end)
		rebuilt = okRebuild and rebuildResult == true
		if not rebuilt then
			warn("[WAR EMPIRE] ForceRebuildGround failed — full MapSetup.Run rebuild")
			pcall(function()
				if setup then
					setup:Destroy()
				end
				MapSetup.Run()
			end)
			if not Workspace:FindFirstChild("WarEmpireSetup") then
				ensureVoidFallback("ForceRebuildGround failed and full rebuild failed")
			end
		end
	elseif setup then
		warn("[WAR EMPIRE] ForceRebuildGround missing — full MapSetup.Run rebuild")
		pcall(function()
			setup:Destroy()
			MapSetup.Run()
		end)
	end

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
					MapSetup.Run()
				end)
				if not Workspace:FindFirstChild("WarEmpireSetup") then
					ensureVoidFallback("Missing upgrade pads and rebuild failed")
				end
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


-- ── Remotes + services (AFTER map so require failures don't block terrain) ─
local RemoteSetup = require(Modules.RemoteSetup)
RemoteSetup.Init() -- MUST run before any service require that can throw

local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local BaseService = require(Services.BaseService)
local XPService = require(Services.XPService)
local RateLimitService = require(Services.RateLimitService)
local AnalyticsService = require(Services.AnalyticsService)
local AdminService = require(Services.AdminService)
local NotificationService = require(Services.NotificationService)
local AntiExploitService = require(Services.AntiExploitService)
local CombatService = require(Services.CombatService)
local VehicleService = require(Services.VehicleService)
local TerritoryService = require(Services.TerritoryService)
local MissionService = require(Services.MissionService)
local PrestigeService = require(Services.PrestigeService)
local ClanService = require(Services.ClanService)
local MonetizationService = require(Services.MonetizationService)
local TutorialService = require(Services.TutorialService)
local BattlePassService = require(Services.BattlePassService)
local SoldierService = require(Services.SoldierService)
local SeasonService = require(Services.SeasonService)
local ClanWarService = require(Services.ClanWarService)
local CodesService = require(Services.CodesService)
local NationColorService = require(Services.NationColorService)
local CaptureStipendService = require(Services.CaptureStipendService)
local SupplyDropService = require(Services.SupplyDropService)
local BankRaidService = require(Services.BankRaidService)
local SpinnerService = require(Services.SpinnerService)
local UpgradePadService = require(Services.UpgradePadService)
local FallSafetyService = require(Services.FallSafetyService)
local VisualAssetService = require(Services.VisualAssetService)
local StudioBuySmoke = require(Modules.StudioBuySmoke)

RemoteSetup.Init()

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
}

RateLimitService.Init()
AnalyticsService.Init()
DataService.SetAnalytics(AnalyticsService)

-- Init services that OnProfileLoaded depends on BEFORE DataService loads players
EconomyService.Init(deps)
XPService.Init(deps)
NotificationService.Init(deps)
AntiExploitService.Init(deps)
BaseService.Init(deps) -- registers OnProfileLoaded
UpgradePadService.Init(deps) -- server walk-over buy (Touched + spatial)
FallSafetyService.Init(deps) -- void fall → teleport to plot spawn
MonetizationService.Init(deps) -- GamePass cache on join
TutorialService.Init(deps) -- tutorial step on join + upgrade hook

-- Now load profiles (fires OnProfileLoaded for joiners)
DataService.Init()

-- Studio-only auto BUY smoke (IsStudio gated inside module)
StudioBuySmoke.Init(deps)

AdminService.Init(deps)
VisualAssetService.Init()
CombatService.Init(deps)
VehicleService.Init(deps)
NationColorService.Init(deps)
TerritoryService.Init(deps)
MissionService.Init(deps)
PrestigeService.Init(deps)
ClanService.Init(deps)
BattlePassService.Init(deps)
SoldierService.Init(deps)
SeasonService.Init(deps)
ClanWarService.Init(deps)
CodesService.Init(deps)
CaptureStipendService.Init(deps)
SupplyDropService.Init(deps)
BankRaidService.Init(deps)
SpinnerService.Init(deps)

if DevConfig.VerboseLogging then
	print("[WAR EMPIRE] Services initialized. Plots:", Constants.MaxBasePlots)
end

print("[WAR EMPIRE] Server Bootstrap ready.")
print("[WAR EMPIRE] CHECKLIST: 1) resetmap MANDATORY if void/dead-space persists (stale WarEmpireSetup keeps old holes)  2) Output must show Ground AFTER heal size/CanCollide  3) stand on YOUR Command Center pad — big BUY button + [UpgradePad] BUY ATTEMPT/OK  4) dock tiles toast + B menu BUY")
