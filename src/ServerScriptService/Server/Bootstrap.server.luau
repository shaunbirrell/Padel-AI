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

	-- Match playtest ground scale (~4800) so large-map void-fall still lands on plate
	local baseplate = Instance.new("Part")
	baseplate.Name = "Baseplate"
	baseplate.Size = Vector3.new(5000, 4, 5000)
	baseplate.Position = Vector3.new(0, -2, 0)
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
	print("[WAR EMPIRE] WarEmpireSetup already present — skipping MapSetup.Run")
	-- Re-assert gravity + Ground presence so scale upgrades / partial setups never void-fall
	Workspace.Gravity = 196.2
	local CollectionService = game:GetService("CollectionService")
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local map = setup and setup:FindFirstChild("Map")
	local ground = map and map:FindFirstChild("Ground")
	if not (ground and ground:IsA("BasePart") and ground.Size.X >= 4000) then
		warn("[WAR EMPIRE] WarEmpireSetup present but Ground missing/small (<4800 scale) — rebuilding via MapSetup")
		pcall(function()
			if setup then
				setup:Destroy()
			end
			MapSetup.Run()
		end)
		if not Workspace:FindFirstChild("WarEmpireSetup") then
			ensureVoidFallback("Existing setup invalid and rebuild failed")
		end
	else
		-- Ensure WE_UpgradeSlot tags exist (stale place files / partial builds skip MapSetup)
		local tagged = CollectionService:GetTagged(Constants.Tags.UpgradeSlot)
		local taggedCount = #tagged
		if taggedCount == 0 then
			local bases = setup and setup:FindFirstChild("Bases")
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
					if setup then
						setup:Destroy()
					end
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
MonetizationService.Init(deps) -- GamePass cache on join
TutorialService.Init(deps) -- tutorial step on join + upgrade hook

-- Now load profiles (fires OnProfileLoaded for joiners)
DataService.Init()

AdminService.Init(deps)
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
