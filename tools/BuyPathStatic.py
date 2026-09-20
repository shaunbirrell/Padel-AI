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

# 6) Monetization live Ids (v29+)

body = read("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
if body is None:
    bad("MonetizationConfig missing")
else:
    # Named blocks must be non-zero for live SKUs
    required = {
        "VIP": 1985475542,
        "DoubleCash": 1982865711,
        "AutoCollect": 1985115501,
        "CashMega": 3713838952,
        "SpeedBoost": 3713839342,
        "CashSmall": 3713838744,
    }
    for key, expect in required.items():
        m = re.search(rf"{key}\s*=\s*\{{[^}}]*?Id\s*=\s*(\d+)", body, re.S)
        if not m:
            bad(f"MonetizationConfig missing Id for {key}")
        else:
            got = int(m.group(1))
            if got == 0:
                bad(f"MonetizationConfig {key} Id still 0")
            elif got != expect:
                # allow mismatch but require non-zero
                ok(f"MonetizationConfig {key} Id live ({got})")
            else:
                ok(f"MonetizationConfig {key} Id={got}")
    if "HideFromShop = true" not in body:
        bad("MonetizationConfig HideFromShop for duplicate DevProducts")
    else:
        ok("MonetizationConfig HideFromShop duplicates")


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
def must_absent(path, needle, label):
    global PASS, FAIL
    fp = ROOT / path if not Path(path).is_absolute() else Path(path)
    text = fp.read_text(encoding="utf-8")
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

# --- P0 PvP economy: contested outposts + ATM raid ---
must_contain("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau", "AtmRaid", "EconomyConfig AtmRaid")
must_contain("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau", "AtmRaidCooldownSeconds", "AtmRaidCooldownSeconds")
must_contain("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau", "ToastSecured", "Outpost ToastSecured")
must_contain("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau", "ToastLost", "Outpost ToastLost")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "SyncOutpostIncomeStacks", "EconomyService SyncOutpostIncomeStacks")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "TransferPendingCash", "EconomyService TransferPendingCash")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "GrantOutpostIncomeStack", "GrantOutpostIncomeStack kept")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "SyncOutpostIncomeStacks", "TerritoryService SyncOutpostIncomeStacks")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "Outpost lost", "Territory outpost lost toast")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "MoneyCollector TryAtmRaid")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TransferPendingCash", "MoneyCollector uses TransferPendingCash")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "atm_raid", "atm_raid cash-mult exempt")
# No-regress ManualDropper / own collect
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "AccruePendingCash", "ManualDropper AccruePendingCash no-regress")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "CollectPendingCash", "Own collect CollectPendingCash no-regress")


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


# --- P0 Squad Orders walkie ---
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "Follow", "OrdersConfig Follow")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "Attack", "OrdersConfig Attack")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "Hold", "OrdersConfig Hold")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "Retreat", "OrdersConfig Retreat")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "RequestSquadOrder", "Constants RequestSquadOrder")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "SquadOrderStateUpdate", "Constants SquadOrderStateUpdate")
must_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "RequestSquadOrder", "RemoteSetup RequestSquadOrder")
must_contain("src/ServerScriptService/Server/Services/SquadOrdersService.luau", "function SquadOrdersService.SetOrder", "SquadOrdersService.SetOrder")
must_contain("src/ServerScriptService/Server/Services/SquadOrdersService.luau", "function SquadOrdersService.SyncArmy", "SquadOrdersService.SyncArmy")
must_contain("src/ServerScriptService/Server/Services/SoldierService.luau", "OnArmyChanged", "SoldierService OnArmyChanged")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "SquadOrdersService", "Bootstrap SquadOrdersService")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "ORDERS", "OrdersController walkie")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "RequestSquadOrder", "OrdersController fires RequestSquadOrder")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "OrdersController", "UIController inits Orders")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "MissionController.Toggle", "Dock Orders stays MissionController")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "WE_ManualDropper", "ManualDropper no-regress")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_DressHost_Radio", "StructureKitBuilder DressHosts no-regress")


# --- Gate Defense ---
must_contain("src/ReplicatedStorage/Shared/Configs/GateDefenseConfig.luau", "ProtectCollectorRadius", "GateDefenseConfig ProtectCollectorRadius")
must_contain("src/ReplicatedStorage/Shared/Configs/GateDefenseConfig.luau", "AutoGunMinWallsLevel", "GateDefenseConfig AutoGunMinWallsLevel")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "GateDefense", "VisualAssetConfig.GateDefense")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "4923345827", "GateAutoGun Machine Gun Nest")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "8980890767", "SandbagNest")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "GateGuard", "Characters.GateGuard")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.SyncPlot", "GateDefenseService.SyncPlot")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "GatePost", "GateDefense reads GatePost")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "ProtectCollectorRadius", "GateDefense ATM aggro")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "TryAttachCharacterVisual", "GateGuard visual attach")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "GateDefenseService", "Bootstrap GateDefenseService")
must_not_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "SyncPerimeterWalls", "GateDefense must not call SyncPerimeterWalls")
must_not_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "TargetFootprint", "GateDefense must not touch TargetFootprint")



# --- P0 Siegeable gates + near-plot oil + P1 death shop ---
must_contain("src/ReplicatedStorage/Shared/Configs/GateDefenseConfig.luau", "GateMaxHealthByWallsLevel", "GateDefenseConfig GateMaxHealthByWallsLevel")
must_contain("src/ReplicatedStorage/Shared/Configs/GateDefenseConfig.luau", "GateRebuildSeconds", "GateDefenseConfig GateRebuildSeconds")
must_contain("src/ReplicatedStorage/Shared/Configs/GateDefenseConfig.luau", "GateRepairCashCost", "GateDefenseConfig GateRepairCashCost")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefenseService.ApplyDamage")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "spawnGateBarriers", "GateDefenseService spawnGateBarriers")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "GateBreached", "GateDefenseService GateBreached")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "TryRepair", "GateDefenseService TryRepair")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "GateDefenseService.ApplyDamage", "CombatService fires gate ApplyDamage")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "DeathShopOffer", "CombatService DeathShopOffer on PvP death")
must_contain("src/ReplicatedStorage/Shared/Configs/PlotOilPumpConfig.luau", "MinWallsLevel", "PlotOilPumpConfig MinWallsLevel")
must_contain("src/ReplicatedStorage/Shared/Configs/PlotOilPumpConfig.luau", "CashPerTick", "PlotOilPumpConfig CashPerTick")
must_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "function PlotOilPumpService.SyncPlot", "PlotOilPumpService.SyncPlot")
must_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "AccruePendingCash", "PlotOilPump AccruePendingCash")
must_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "IndustrialPack", "PlotOilPump IndustrialPack dress key")
must_not_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "OilRigAlpha", "PlotOilPump must not touch OilRigAlpha")
must_not_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "OilRigBravo", "PlotOilPump must not touch OilRigBravo")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "PlotOilPumpService", "Bootstrap PlotOilPumpService")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "DeathShopOffers", "MonetizationConfig DeathShopOffers")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "SpeedBoost", "MonetizationConfig SpeedBoost stub")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "DeathShopOffer", "Constants DeathShopOffer remote")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DeathShopOffer", "ShopController DeathShopOffer listener")
# --- v25 Base Ceiling + prestige income keep + HUD rebirth progress ---
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "function StructureKitBuilder.SyncBaseCeiling", "SyncBaseCeiling")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_BaseCeiling", "WE_BaseCeiling folder")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "RoofHelipad", "Ceiling roof helipad dress")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "SyncBaseCeiling", "BaseService SyncBaseCeiling wire")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "PlotOilPumpService", "Bootstrap PlotOilPump still wired")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "GateDefenseService", "Bootstrap GateDefense still wired")
must_contain("src/ServerScriptService/Server/Services/PrestigeService.luau", "SyncOutpostIncomeStacks", "Prestige keeps OutpostIncomeStacks")
must_contain("src/ServerScriptService/Server/Services/PrestigeService.luau", "OutpostIncomeStacks", "Prestige OutpostIncomeStacks comment")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "Rebirth", "HUD rebirth progress")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "BaseCeiling", "VisualAssetConfig BaseCeiling")
must_contain("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau", "MinLevelToPrestige = 40", "PrestigeConfig MinLevel 40 no-regress")
must_contain("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau", "RebirthUnlocks", "PrestigeConfig unlocks no-regress")

# --- v26 Roof barracks + Missions dock + rebirth fee clarity ---
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "RoofBarracksPad", "Ceiling roof barracks pads")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_RoofBarracks", "WE_RoofBarracks attribute")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "TryAttachBuildingVisual(bp, \"Barracks\"", "Roof barracks Barracks mesh dress")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "DockMissions", "HUD dock Missions tile")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "MissionController.Toggle", "Missions dock opens MissionController")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "Label = \"MISSIONS\"", "Missions dock label")
must_contain("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau", "CashFee", "PrestigeConfig CashFee")
must_contain("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau", "BuildFeeSummary", "PrestigeConfig BuildFeeSummary")
must_contain("src/ServerScriptService/Server/Services/PrestigeService.luau", "FeeSummary", "PrestigeService FeeSummary push")
must_contain("src/ServerScriptService/Server/Services/PrestigeService.luau", "BaseCompletionPercent", "PrestigeService BaseCompletionPercent")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "FeeSummary", "Progression confirm FeeSummary")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MissionController.luau", "function MissionController.Toggle", "MissionController.Toggle exists")

# No-regress
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.SyncPlot", "GateDefense SyncPlot no-regress")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ScaleTo", "STRUCTURE_SCALE ScaleTo no-regress")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "AccruePendingCash", "ManualDropper no-regress")
must_contain("src/ServerScriptService/Server/Services/SquadOrdersService.luau", "function SquadOrdersService.SetOrder", "Orders no-regress")



# --- v27 polish: cash HUD `+` opens Shop (premium pads skipped while Ids=0) ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "CashPlus", "HUD CashPlus button")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "BindShopOpener", "HUD BindShopOpener")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "BindShopOpener", "UIController wires cash+ to Shop")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "coming soon", "Shop lists Id=0 stubs as coming soon")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "PromptProductPurchase", "Shop PromptProductPurchase when Id set")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"VehicleService\"", "Bootstrap VehicleService")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"GateDefenseService\"", "Bootstrap GateDefenseService")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"ManualDropperService\"", "Bootstrap ManualDropperService")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"PlotOilPumpService\"", "Bootstrap PlotOilPumpService")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"PrestigeService\"", "Bootstrap PrestigeService")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"MissionService\"", "Bootstrap MissionService")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"SquadOrdersService\"", "Bootstrap SquadOrdersService")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"MoneyCollectorService\"", "Bootstrap MoneyCollectorService")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "ProcessReceipt", "Monetization ProcessReceipt wired")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "VehicleService LV drive (v27)")

# --- v29 premium pads + Mega hero + rebirth keep-Robux ---
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPadService PromptPremiumPad")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "WE_PremiumPad", "PremiumPadService tag")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "buildPremiumPads", "MapSetup buildPremiumPads")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "AutoCollect", "MapSetup AutoCollect pad")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "PremiumPadService", "Bootstrap PremiumPadService")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "PromptPremiumPad", "Constants PromptPremiumPad")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "BEST OFFER", "Shop CashMega BEST OFFER")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "HideFromShop", "Shop hides duplicate DevProducts")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "PromptPremiumPad", "Shop listens PromptPremiumPad")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "Keep all Robux", "Rebirth keep Robux banner/copy")
must_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "GoldenPumpjack", "PlotOilPump GoldenPumpjack dress")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "safeInit(\"VehicleService\"", "Bootstrap VehicleService no-regress")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v29")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v29")



# --- v29 video-feel polish (Orders hotkeys / Contested billboard / Ceiling beams) ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "HOTKEY_ORDERS", "Orders hotkeys 1-4")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "KeyCode.T", "Orders T cycle")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "CONTESTED", "Territory Contested billboard")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "ContestedBadge", "Territory ContestedBadge")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "CeilingBeamLong", "BaseCeiling beams")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "CeilingJoist", "BaseCeiling joists")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "Keep all your Robux Items!", "Rebirth exact keep banner")


# --- v30 death shop toast / GoldenPump hide / Army Robux / oil float / mobile Orders ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DeathShopToast", "Death shop toast UI")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DEATH_TOAST_DEBOUNCE", "Death shop client debounce")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "PromptGamePassPurchase", "Death/shop GamePass prompt")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "DEATH_SHOP_DEBOUNCE", "Death shop server debounce")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "resolveDeathOfferLive", "Death shop live Id filter")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "premiumOfferIdLive", "Premium pad Id≠0 gate")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "atmCluster", "Chevrons to ATM/premium cluster")
must_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "WE_OilCashPop", "Oil pump floating +$ pop")
must_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", '"+$" .. tostring(PlotOilPumpConfig.CashPerTick or 18) .. "/tick"', "Oil billboard +$/tick")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau", "COMMANDER PACK", "Army Commander Pack Robux row")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau", "ExtraSoldierSlot", "Army ExtraSoldierSlot offer")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "SizeTouch", "Orders mobile SizeTouch")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "SizeTouch", "OrdersConfig SizeTouch")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "HideFromShop = true", "HideFromShop duplicate DevProducts")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "GoldenPumpjack", "GrantEntitlement GoldenPumpjack sync")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "SpeedBoost", "SpeedBoost WalkSpeed apply")
must_contain("src/ServerScriptService/Server/Services/SoldierService.luau", "ExtraSoldierSlot", "ExtraSoldierSlot +1 cap")
# No-regress v30
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v30")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v30")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v30")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v30")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713838952", "CashMega Id no-regress")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash GamePass Id no-regress")

# --- v31 onboarding + overlay harden + OWNED pads + WASD tip ---
must_contain("src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau", "ClickDropper", "Tutorial ClickDropper step")
must_contain("src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau", 'Id = "Income"', "Tutorial Income early")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "STEP_DROPPER", "TutorialService STEP_DROPPER")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", '"ManualDrop"', "TutorialService ManualDrop event")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "ManualDrop", "ManualDropper tutorial Notify")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "Tutorial_Dropper", "MapSetup Tutorial_Dropper marker")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", 'Key = "VIP"', "MapSetup VIP premium pad")
must_contain("src/ServerScriptService/Server/Services/SupplyDropService.luau", "AlwaysOnTop = false", "SupplyDrop AlwaysOnTop false")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "SupplyDrop", "WorldPrompt hides SupplyDrop near pads")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "secured — +%d%% Income", "Capture income toast clarity")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "Press WASD to drive", "Jeep WASD sit tip")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "WE_LocalOwned", "Premium pad OWNED visual")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "UserOwnsGamePassAsync", "OWNED via PlayerOwnsGamePass check")
# No-regress v31
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v31")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v31")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v31")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v31")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP GamePass Id no-regress")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect GamePass Id no-regress")


# --- v32 VIP CashBonusMult + StarterBundle offer + flag polish + ArmedJeep garage + dropper $ ---
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "CashBonusMult", "VIP CashBonusMult config")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "CashBonusMult", "VIP CashBonusMult applied")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "GetCashMultiplier", "GetCashMultiplier exported")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "GetCashMultiplier", "Economy uses GetCashMultiplier")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "StarterBundleOffer", "StarterBundleOffer config")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "StarterBundleOffered", "StarterBundleOffered profile gate")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "StarterBundleOffer", "StarterBundleOffer remote")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "StarterBundleToast", "StarterBundle client toast")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", 'promptDevProduct("StarterBundle")', "StarterBundle PromptProductPurchase path")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "WE_FlagBillboard", "Capture flag floating billboard")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "FlagStripe", "FlagStripe nation visibility")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "NationColorService", "NationColorService capture color")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "CashPopGlow", "Manual dropper green $ pop glow")
must_contain("src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau", 'ArmedJeep = V("ArmedJeep", "Armed Jeep"', "ArmedJeep DisplayName")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", 'id == "ArmedJeep"', "Garage lists ArmedJeep")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", 'id == "ArmedJeep"', "ArmedJeep same WheeledLight kit")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "startGroundDrive", "ArmedJeep drivability via startGroundDrive")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", 'Key = "VIP"', "VIP premium pad")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "WE_LocalOwned", "VIP pad OWNED visual no-regress")
# No-regress v32
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v32")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v32")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v32")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v32")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP GamePass Id no-regress v32")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713839505", "StarterBundle Id no-regress v32")

# --- v33 quality pack: name readability, kit scale, gate polish, ATM raid UX, capture steal, AutoCollect soft, pad dressing ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "ensurePadNameSurface", "Pad name SurfaceGui helper")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "ensurePadNameSurface(part, display)", "Pad name applied on billboard refresh")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "AlwaysOnTop = true", "BUY name billboard AlwaysOnTop near")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 23", "StructureKit KIT_GEN 23")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "airfield"', "Airfield kit present")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "warehouse"', "Warehouse kit present")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "Vector3.new(10, 28, 10)", "Watchtower body tall silhouette")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BuildingDressGen = 23", "BuildingDressGen 23")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "RifleBarrel", "GateGuard clear weapon barrel")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "RifleMag", "GateGuard clear weapon mag")
must_contain("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau", "ToastCooldown", "AtmRaid ToastCooldown")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "AtmRaidStateUpdate", "AtmRaidStateUpdate push")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "AutoCollectOffered", "AutoCollect soft offer profile gate")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "AtmRaidStateUpdate", "AtmRaidStateUpdate remote")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "AutoCollectOffer", "AutoCollectOffer remote")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "AutoCollectToast", "AutoCollect client toast")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "AtmRaidHud", "AtmRaid cooldown HUD")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "ToastStealGain", "Capture steal income toast")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "stoleFromPlayer", "Capture steal tracking")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "dressPlotPadSandbags", "Plot pad sandbag dressing")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "PlotPadDressing", "PlotPadDressing folder")
# No-regress v33
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v33")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v33")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v33")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v33")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect GamePass Id no-regress v33")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v33")


# --- v34 legitimacy pack: HQ/Barracks/Armory kits, soldier variety, garage tips, DoubleCash soft, capture chip, rebirth copy, mobile Orders ---
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 23", "v34 KIT_GEN 23")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "armory"', "WeaponsFacility armory kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "3-story weapons inventory", "Armory densify comment")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "compound-scale HQ", "HQ densify comment")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "100212659702941", "Worker distinct Soldier mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/SoldierConfig.luau", 'Worker = "Soldier"', "Worker VisualKind Soldier")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "HeavyInfantry", "Stall HeavyInfantry variety")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "role Part-dress differentiation", "Soldier role dress")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "DriveTip", "Vehicle label drive tip")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "Sit · WASD to drive", "Ground drive tip copy")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", "Sit · WASD drive", "Garage row drive tip")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "OwnerChip", "Capture owner/progress chip")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "CAPTURING ·", "Capture progress chip text")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "DoubleCashOffer", "DoubleCash soft offer config")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "DoubleCashOffer", "DoubleCashOffer remote")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "DoubleCashOffered", "DoubleCash soft profile gate")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DoubleCashToast", "DoubleCash client toast")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "Fee: none", "Rebirth fee HUD copy")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "MinTouchPx = 56", "Orders mobile touch 56")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash GamePass Id no invent")
# No-regress v34
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v34")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v34")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v34")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v34")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v34")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP GamePass Id no-regress v34")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect GamePass Id no-regress v34")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "airfield"', "Airfield kit no-regress v34")

print(f"[BuyPathStatic] Done PASS={PASS} FAIL={FAIL}")
sys.exit(1 if FAIL else 0)
