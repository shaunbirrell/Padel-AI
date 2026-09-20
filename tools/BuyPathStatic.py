#!/usr/bin/env python3
"""CLI static wiring checks for BUY + BankGuard + BankRaid HUD + mobile HUD (no Roblox runtime).
Run: python3 tools/BuyPathStatic.py
Exit 0 if all PASS; 1 if any FAIL.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0

def ok(msg: str) -> None:
    global PASS
    PASS += 1
    print("[BuyPathStatic] PASS", msg)

def bad(msg: str) -> None:
    global FAIL
    FAIL += 1
    print("[BuyPathStatic] FAIL", msg, file=sys.stderr)

def read(rel: str) -> str | None:
    p = ROOT / rel
    if not p.is_file():
        return None
    return p.read_text(encoding="utf-8")

def must_contain(rel: str, needle: str, label: str) -> None:
    body = read(rel)
    if body is None:
        bad(f"{label} — missing file {rel}")
        return
    if needle in body:
        ok(label)
    else:
        bad(f"{label} — missing `{needle}` in {rel}")

def must_not_contain(rel: str, needle: str, label: str) -> None:
    body = read(rel)
    if body is None:
        bad(f"{label} — missing file {rel}")
        return
    if needle in body:
        bad(f"{label} — found forbidden `{needle}` in {rel}")
    else:
        ok(label)

# 1) BUY path
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "RequestPurchaseUpgrade", "Constants.RequestPurchaseUpgrade")
must_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "RequestPurchaseUpgrade", "RemoteSetup lists RequestPurchaseUpgrade")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "function BaseService.PurchaseUpgrade", "BaseService.PurchaseUpgrade")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "RemoteGuard.IsIdString", "BaseService uses RemoteGuard.IsIdString")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "RemoteGuard.RequireProfile", "BaseService remote RequireProfile")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "RequestPurchaseUpgrade", "BaseService binds RequestPurchaseUpgrade")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "BaseService.PurchaseUpgrade", "UpgradePadService → PurchaseUpgrade")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "RequestPurchaseUpgrade", "WorldPrompt BUY FireServer")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "btn.Activated", "WorldPrompt BUY Activated")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau", "RequestPurchaseUpgrade", "Base menu BUY FireServer")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau", "btn.Activated", "Base menu BUY Activated")

# 2) PERF
must_contain("src/ReplicatedStorage/Shared/Configs/DevConfig.luau", "StudioSkipWorldDressing = true", "StudioSkipWorldDressing=true")

# 3) BankGuard
must_contain("src/ReplicatedStorage/Shared/Configs/CombatConfig.luau", "BankGuard", "CombatConfig.BankGuard")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "BankGuard", "VisualAssetConfig.Characters.BankGuard")
must_contain("src/ServerScriptService/Server/Services/BankRaidService.luau", "CombatService.SpawnNPC", "BankRaidService SpawnNPC")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "TryAttachCharacterVisual", "SpawnNPC VisualAsset attach")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "MaxTorque = Vector3.new(0, 4e5, 0)", "BodyGyro yaw-only (MoveTo)")
must_contain("src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau", "Humanoid:MoveTo", "CombatNPC MoveTo")
must_contain("src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau", "TakeDamage", "CombatNPC shoots (TakeDamage)")
must_not_contain("src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau", "rec.Root.CFrame = look", "Think must not teleport Root.CFrame")

# 4) Mobile HUD
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "DisplayOrder = 55", "HUD dock DisplayOrder 55")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "btn.Activated", "Dock tiles Activated")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "BindActionBar", "UIController BindActionBar")
for name, rel in [
    ("Shop", "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"),
    ("Army", "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau"),
    ("Progression", "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau"),
    ("Garage", "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau"),
    ("Base", "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau"),
]:
    must_contain(rel, "panel.Visible", f"{name} panel.Visible")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DisplayOrder = 60", "Shop DisplayOrder 60")

# 5) BankRaid HUD
must_contain("src/ServerScriptService/Server/Services/BankRaidService.luau", "HoldProgress", "BankRaidService HoldProgress payload")
must_contain("src/ServerScriptService/Server/Services/BankRaidService.luau", "UnderFire", "BankRaidService UnderFire payload")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BankRaidController.luau", "BankRaidStateUpdate", "BankRaidController listens BankRaidStateUpdate")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "BankRaidController", "UIController wires BankRaidController")
must_contain("src/ReplicatedStorage/Shared/Remotes.luau", "Waiting for", "Remotes patient WaitForChild poll")

# 6) Monetization stubs

body = read("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
if body is None:
    bad("MonetizationConfig missing")
else:
    ids = [int(x) for x in re.findall(r"Id\s*=\s*(\d+)", body)]
    nonzero = [i for i in ids if i != 0]
    if not nonzero:
        ok(f"MonetizationConfig product Ids all 0 (checked {len(ids)})")
    else:
        bad(f"MonetizationConfig non-zero Ids: {nonzero}")


# 7) Structure kit spawn / perimeter (BaseService visual pipeline)
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "EnsureKit", "StructureKitBuilder.EnsureKit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "SyncPerimeterWalls", "StructureKitBuilder.SyncPerimeterWalls")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "GATE_CLEAR", "perimeter GATE_CLEAR opening")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "PlayerSpawn", "gate faces PlayerSpawn")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "GateArch", "non-collide GateArch visual")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_GateAxis", "per-plot gate axis attribute")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "BuildKitOnPlinth", "StructureKitBuilder.BuildKitOnPlinth")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "StructureKitBuilder.EnsureKit", "BaseService EnsureKit on apply")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "SyncPerimeterWalls", "BaseService SyncPerimeterWalls")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "RefreshAllVisuals", "BaseService RefreshAllVisuals")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "BaseService.UpdateVisuals(player, structureId, targetLevel)", "PurchaseUpgrade → UpdateVisuals")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "findUpgradeSlots", "BaseService findUpgradeSlots fallback")


# 8) P0 competitive + jeep drive / mesh
must_contain("src/ServerScriptService/Server/Services/SoldierService.luau", 'AccruePendingCash(player, amount, "training")', "Training → AccruePendingCash")
must_contain("src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau", 'Id = "RecruitSoldiers"', "Tutorial RecruitSoldiers step")
must_contain("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau", "MinLevelToPrestige = 40", "MinLevelToPrestige 40")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "buildMoneyCollector", "MapSetup ATM MoneyCollector")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "TAG_COLLECTOR", "MapSetup TAG_COLLECTOR")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "PendingLabel", "HUD PendingLabel")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "125916936788670", "MilitaryJeep Military Car mesh")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_DrivePrompt", "DriverSeat Drive ProximityPrompt")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "seat:Sit(hum)", "VehicleSeat auto-Sit")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_DriveHinge", "HingeConstraint drive motors")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "startGroundDrive", "scripted/hinge ground drive")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "HingeConstraint", "mesh strips drive constraints")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "Codes in Settings", "ATM codes hint P1-7")


# 9) Design competitive pass P0/P1 (ATM / WarzoneProps / showroom / HUD)
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "75368157644109", "ATM hero prefer ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "175462478", "ATM fallback ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "38451313", "MoneyBagFX ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "4221608224", "VfxSparkles ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "16803204916", "CashCrate ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "5267267960", "ShowroomPodium ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "5389482912", "ShowroomRotator ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "1143305733", "TutorialArrow ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'Sandbag = { ModelAssetId = 3525056989', "WarzoneProps Sandbag label")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'Floodlight = { ModelAssetId = 116763933', "WarzoneProps Floodlight label")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "TryAttachCollectorVisual", "VAS TryAttachCollectorVisual")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "PlayMoneyBagFX", "VAS PlayMoneyBagFX")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "TryAttachShowroomVisual", "VAS TryAttachShowroomVisual")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "Podium", "VehicleDepot showroom Podium")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "syncUpgradePops", "BaseService upgrade pops")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "GoldBright", "HUD GoldBright stroke")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "dock≤8", "HUD dock padding ≤8")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.luau", "NeonAccent", "Tutorial NeonAccent beam")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "125916936788670", "Jeep ModelAssetId unchanged")


# 10) Design visual overhaul wire + levels progression
must_not_contain = getattr(__import__('builtins'), 'must_not_contain', None)
def must_absent(path, needle, label):
    global PASS, FAIL
    text = open(path, encoding="utf-8").read()
    # allow REJECT comments mentioning the id
    lines = [ln for ln in text.splitlines() if needle in ln and "REJECT" not in ln and "DELETED" not in ln and "NO JeepFallback" not in ln]
    # also allow comment-only lines with Design P0
    lines = [ln for ln in lines if not ln.strip().startswith("--") or ("ModelAssetId" in ln)]
    # filter config assignment lines
    bad = [ln for ln in lines if "ModelAssetId" in ln or "JeepFallback =" in ln or "= 59524622" in ln]
    if bad:
        FAIL += 1
        print(f"[BuyPathStatic] FAIL {label}: still present -> {bad[0][:120]}")
    else:
        PASS += 1
        print(f"[BuyPathStatic] PASS {label}")

must_absent("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "59524622", "No JeepFallback 59524622 assignment")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Soldier = { ModelAssetId = 100212659702941", "Soldier Design Bot primary")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Infantry = { ModelAssetId = 9104381136", "Infantry Design Bot")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ArmedJeep = { ModelAssetId = 122068883442022", "ArmedJeep tan turreted")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "HeavyInfantry = { ModelAssetId = 14776506955", "HeavyInfantry Design Bot")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Guard = { ModelAssetId = 16134469614", "Guard Design Bot")
must_absent("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "91299598767068", "No Respawn pack primary assignment")
# allow REJECT comments mentioning 3924234975; must_absent filters REJECT/DELETED
must_absent("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "3924234975", "No plastic Rthro CharacterAlt assignment")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "SupplyTruck = { ModelAssetId = 105503568352704", "SupplyTruck truck mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "InfantryCarrier = { ModelAssetId = 17835143223", "InfantryCarrier APC")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "FloodlightTower = { ModelAssetId = 107381977457431", "FloodlightTower prop")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "CharacterAlt = { ModelAssetId = 0", "CharacterAlt disabled")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "PlotFloorChevrons", "Plot floor chevrons to next pad")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NotificationController.luau", "Purchase SUCCESSFUL", "High-contrast success toast styling")
must_contain("src/ReplicatedStorage/Shared/Configs/SoldierConfig.luau", "VisualPlaceholder", "Soldier R15-ready visual keys")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshMinLevel = 1", "PreferMesh L1+")
must_contain("src/ReplicatedStorage/Shared/Configs/LevelConfig.luau", "Milestones", "Level milestones")
must_contain("src/ReplicatedStorage/Shared/Configs/LevelConfig.luau", "GetHudGoal", "Level GetHudGoal")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "GoalLabel", "HUD GoalLabel")
must_contain("src/ServerScriptService/Server/Services/XPService.luau", "GetUnlockMessage", "XP unlock toasts")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "PlotWarzoneDensify", "Warzone densify 8-12/plot")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "PlotWarzone", "MapSetup PlotWarzone always-on")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "NO JeepFallback", "VAS no jeep fallback")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_DriveHinge", "Hinge drive kept")



# --- P0 early-game: manual dropper + outpost income buff ---
must_contain("src/ReplicatedStorage/Shared/Configs/ManualDropperConfig.luau", "AwardAmount", "ManualDropperConfig AwardAmount")
must_contain("src/ReplicatedStorage/Shared/Configs/ManualDropperConfig.luau", "CooldownSeconds", "ManualDropperConfig CooldownSeconds")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "AccruePendingCash", "ManualDropper AccruePendingCash")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "ClickDetector", "ManualDropper ClickDetector")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "ProximityPrompt", "ManualDropper ProximityPrompt")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "ManualDropperService", "Bootstrap ManualDropperService")
must_contain("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau", "OutpostIncomeBuff", "EconomyConfig OutpostIncomeBuff")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "GrantOutpostIncomeStack", "EconomyService GrantOutpostIncomeStack")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "GrantOutpostIncomeStack", "TerritoryService grants outpost income stack")
must_contain("src/ServerScriptService/Server/Modules/ProfileSchema.luau", "OutpostIncomeStacks", "ProfileSchema OutpostIncomeStacks")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "CURRENT_DATA_VERSION = 8", "Data version 8")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "manual_dropper", "manual_dropper cash-mult exempt")


# --- Design Bot QUALITY TIER 2 ---
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "103734805361054", "IndustrialPack oil spectacle")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "131322292868756", "RustyPipes")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 25623924", "OilBarrel ring")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 119021509", "RadioTower landmark")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 67444725", "SmallFort landmark")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Ultrapump 1837698074 REJECT", "REJECT Ultrapump")
must_absent("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "1837698074", "No Ultrapump ModelAssetId")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "ShowroomPedestalHost", "Showroom densify pedestals")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "TryDressStructureInterior", "HQ interior dress")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_CommandDesk", "Gunmetal HQ desk")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_DressHost_Radio", "HQ RadioAntenna host")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ShowroomPedestalHost", "Depot pedestal hosts")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ShowroomFlagHost", "Depot flag host")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "OilSpectacle", "Near-plot oil spectacle")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "WarzoneLandmarks", "Map landmarks folder")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "SquadStalls", "TrainingYard Tent stalls")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "96059329869678", "Palm MapDressing")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "10197707775", "AsphaltDecal")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MeshId = 6562523344", "DesertRock MeshPart")
# No-regress P0
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 9104381136", "Worker/Infantry unchanged")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 122068883442022", "ArmedJeep unchanged")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 125916936788670", "MilitaryJeep unchanged")

print(f"[BuyPathStatic] Done PASS={PASS} FAIL={FAIL}")
sys.exit(1 if FAIL else 0)
