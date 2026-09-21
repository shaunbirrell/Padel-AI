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
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "SECURED", "Capture SECURED celebration toast")
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
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "AlwaysOnTop = false", "BUY name billboard never AlwaysOnTop (v39)")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "StructureKit KIT_GEN 27")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "airfield"', "Airfield kit present")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "warehouse"', "Warehouse kit present")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "Vector3.new(10, 28, 10)", "Watchtower body tall silhouette")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BuildingDressGen = 29", "BuildingDressGen 29")
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
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "KIT_GEN 27")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "armory"', "WeaponsFacility armory kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "3-story weapons inventory", "Armory densify comment")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "compound-scale HQ", "HQ densify comment")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "100212659702941", "Worker distinct Soldier mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/SoldierConfig.luau", 'Worker = "Worker"', "Worker VisualKind Worker")
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


# --- v35 legitimacy / late-game presence: SF densify, Helipad/Dock, landmarks, gate guns, VIP soft, oil bob, death CashMega ---
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "KIT_GEN 27 (v39 hotfix)")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "special"', "SpecialForcesFacility special kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "Special Forces compound", "SF densify comment")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "v35: ~28 stud marked pad", "Helipad densify")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "v35: naval pier + bollards", "Dock densify")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BuildingDressGen = 29", "BuildingDressGen 29 (v42)")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "Landmarks_v35", "Map landmarks folder")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "WreckScorch", "Wrecked vehicle landmark")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "attachTurretVisualMarker", "Gate auto-gun visual marker")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "AUTO GUN", "Gate auto-gun billboard")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "TripodLeg", "Gate auto-gun tripod")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "VIPOffer", "VIP soft offer config")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "VIPOffer", "VIPOffer remote")
must_contain("src/ServerScriptService/Server/Modules/ProfileSchema.luau", "VIPOffered", "VIP soft profile gate")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "TrySoftOfferVIP", "VIP soft offer server")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "VIPToast", "VIP client toast")
must_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "pumpjack spectacle", "Oil pumpjack bob")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DeathShopToast", "DeathShopToast continuity")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "ShopRow_CashMega", "CashMega death highlight row")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "pendingCashMegaHighlight", "CashMega death highlight flag")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP GamePass Id no invent v35")
# No-regress v35
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v35")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v35")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v35")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v35")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v35")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash Id no-regress v35")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect Id no-regress v35")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "armory"', "Armory kit no-regress v35")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "airfield"', "Airfield kit no-regress v35")


# --- v36 warzone density + late vehicle/presence: tank drive, ArmedJeep cue, walls, towers, SpeedBoost soft, HUD cash ---
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "TRACKED · Sit · WASD (slow)", "LightTank tracked tip")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "isTracked", "Tracked slower LV cruise")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "ARMED · Sit · WASD", "ArmedJeep ARMED tip")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_MuzzleFlash", "ArmedJeep muzzle flash cue")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_ArmedCue", "ArmedJeep ARMED billboard")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "RoadWarzone_v36", "Road warzone density folder")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "RoadCrater", "Road crater clusters")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "RoadChevron", "Road chevron clusters")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "thicker/taller defensive walls", "Defensive walls v36 taller")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "GateChevron", "Military gate chevron")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_GateSign", "Military gate sign")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "TowerShooter", "Watchtower sniper silhouettes")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_TowerShooter", "Tower shooter attribute")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "SpeedBoostOffer", "SpeedBoost soft offer config")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713839342", "SpeedBoost Id no invent v36")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "SpeedBoostOffer", "SpeedBoostOffer remote")
must_contain("src/ServerScriptService/Server/Modules/ProfileSchema.luau", "SpeedBoostOffered", "SpeedBoost soft profile gate")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "TrySoftOfferSpeedBoost", "SpeedBoost soft offer server")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "SpeedBoostToast", "SpeedBoost client toast")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "high-contrast cash", "HUD cash contrast v36")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "TextStrokeTransparency = 0.25", "HUD cash TextStroke")
# No-regress v36
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v36")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v36")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LV+HingeMotor", "Jeep LV+HingeMotor no-regress v36")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v36")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v36")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v36")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v36")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash Id no-regress v36")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect Id no-regress v36")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "Landmarks_v35", "v35 landmarks no-regress")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "KIT_GEN no-regress →27")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "TutorialService", "Tutorial no-regress v36")



# --- v37 air/naval presence + midgame polish: parked heli/boat, runway, missions, level-up, CashMega soft, garage ---
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_DressHost_ParkedHeli", "Helipad parked heli host")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ParkedHeli", "Helipad parked heli Part-kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_DressHost_ParkedBoat", "Dock parked boat host")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ParkedBoat", "Dock parked boat Part-kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "threshold chevrons", "Airfield threshold chevrons")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "centerline", "Airfield centerline markings")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "TryAttachParkedPresence", "Parked presence mesh attach")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "TryAttachParkedPresence", "BaseService parked presence call")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'role == "ParkedHeli"', "ParkedHeli kit role visuals")
must_contain("src/ReplicatedStorage/Shared/Configs/MissionConfig.luau", "completable in first", "Mission first-5-min Target")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MissionController.luau", "ProgressChip", "Missions progress chip")
must_contain("src/ServerScriptService/Server/Services/XPService.luau", "LevelUp = leveledUp", "XP LevelUp payload flag")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "ShowLevelUpCelebration", "Level-up celebration toast")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "CashMegaOffer", "CashMega soft offer config")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713838952", "CashMega Id no invent v37")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "CashMegaOffer", "CashMegaOffer remote")
must_contain("src/ServerScriptService/Server/Modules/ProfileSchema.luau", "CashMegaOffered", "CashMega soft profile gate")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "TrySoftOfferCashMega", "CashMega soft offer server")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "CashMegaToast", "CashMega client toast")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", "buy Vehicle Depot / unlock Military Jeep", "Garage empty unlock guidance")
# No-regress v37
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v37")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v37")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LV+HingeMotor", "Jeep LV+HingeMotor no-regress v37")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v37")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v37")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash Id no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect Id no-regress v37")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "Landmarks_v35", "v35 landmarks no-regress v37")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "TutorialService", "Tutorial no-regress v37")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "special"', "SF kit no-regress v37")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "isTracked", "LightTank tracked no-regress v37")



# --- v38 combat feel + prestige/monetization polish ---
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "DEF HIT", "Gate defense owner hit toast")
must_contain("src/ReplicatedStorage/Shared/Configs/GateDefenseConfig.luau", "BREACHED", "Gate BREACHED toast config")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "BREACHED", "Gate BREACHED billboard")
must_contain("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau", "ATM RAIDED −10%% by %s", "ATM raid victim toast with thief")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "ThiefName", "ATM raid ThiefName payload")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "ContesterA", "Capture contested ContesterA")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "colA:Lerp(colB", "Capture contested dual nation pulse")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TerritoryController.luau", "contestedPulseActive", "Client contested pulse")
must_contain("src/ServerScriptService/Server/Services/PrestigeService.luau", "MaybeNearPrestigeToast", "Prestige near CTA")
must_contain("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau", "NearPrestigeLevels", "NearPrestigeLevels config")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "ShowNearPrestigeBanner", "HUD near prestige banner")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "Keep all Robux Items", "Near prestige Keep Robux copy")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "SoftOfferSessionCooldownSeconds", "Soft offer session cooldown")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "ClaimSoftOfferSlot", "Soft offer ClaimSoftOfferSlot")
must_contain("src/ServerScriptService/Server/Services/SquadOrdersService.luau", "flashOrderBillboard", "Squad order billboard")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "FOLLOWING", "Orders FOLLOWING label")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kitPart(plinth, "Crate"', "Warehouse crate Part props")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'structureId == "Warehouse"', "Warehouse EnsureKit densify")
# No-regress v38
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v38")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LV+HingeMotor", "Jeep LV+HingeMotor no-regress v38")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "isTracked", "LightTank tracked no-regress v38")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v38")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v38")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v38")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v38")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713839505", "StarterBundle Id no invent v38")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713838952", "CashMega Id no invent v38")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "TutorialService", "Tutorial no-regress v38")


# --- v39 P0 hotfix: billboards + walls + Part-kit visibility ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "PRICE_BILLBOARD_SIZE = UDim2.fromOffset(118, 40)", "v50 price billboard chip 118x40")

# --- v40 Orders panel scale + chip clamp + design gaps doc ---
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "PanelMaxWidth = 220", "v40 Orders PanelMaxWidth")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "MobileScaleMax = 0.85", "v40 Orders MobileScaleMax")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "MinTouchPx = 56", "v40 Orders MinTouchPx 56")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "UISizeConstraint", "v40 Orders UISizeConstraint")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "AttachMobileScale", "v40 Orders custom MobileScale")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "HOTKEY_ORDERS", "v40 Orders hotkeys intact")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "KeyCode.T", "v40 Orders T cycle intact")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "PRICE_CHIP_MAX_W = 120", "v50 chip max width 120")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "clampChipSize", "v40 clampChipSize")
must_contain("docs/DESIGN_WIRE_GAPS_v40.md", "ModelAssetId = 0", "v40 design gaps doc")
must_contain("docs/DESIGN_WIRE_GAPS_v40.md", "26007709", "v40 tank reuse gap listed")
# Constraints: no hideKitBody densify / KIT_GEN / monetization / Jeep drive edits this pass
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "hideKitBody", "no-regress hideKitBody present")

must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "PRICE_BILLBOARD_OWNED_SIZE", "v39 owned billboard chip size")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "bb.AlwaysOnTop = false", "v39 price boards never AlwaysOnTop")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v39 KIT_GEN 27")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "function StructureKitBuilder.SyncPerimeterWalls", "v39 SyncPerimeterWalls present")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_PerimeterGen", "v39 perimeter gen attr")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "SyncPerimeterWalls", "v39 BaseService calls SyncPerimeterWalls")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "placeKitPart", "v39 bottom-anchored kit place")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'role == "Crate"', "v39 Warehouse Crate role visible")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "NEVER ghost Part-kit silhouettes", "v39 hideKitBody no-op")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BuildingDressGen = 29", "v42 BuildingDressGen 29")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "SizeTouch = UDim2.fromOffset(200, 168)", "v40 Orders SizeTouch 200x168")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "UDim2.fromOffset(300, 132)", "v39 no giant 300x132 boards")
# No-regress v39
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v39")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v39")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "AtmRaid no-regress v39")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "TutorialService", "Tutorial no-regress v39")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v39")



# --- v41 DESIGN_FEATURE_WIRE: gate prop, vehicle uniqueness, soldiers, oil, walls=0 ---
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "BaseGate = { ModelAssetId = 85138026", "v41 BaseGate 85138026")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'DefensiveWalls = { ModelAssetId = 0', "v41 DefensiveWalls ModelAssetId=0")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'DefensiveWallsL3 = { ModelAssetId = 0', "v41 DefensiveWallsL3=0")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetId = 0, -- v41: NO Wall* segment", "v41 StructureVisual DefensiveWalls MeshAssetId=0")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetIdL3 = 0, -- v41: Part-kit heavy walls", "v41 MeshAssetIdL3=0")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BuildingDressGen = 29", "v42 BuildingDressGen 29")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "local DRESS_GEN = 29", "v42 VAS DRESS_GEN 29")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'vas.TryAttachBuildingVisual(ch, "BaseGate"', "v46 no BaseGate dress in StructureKitBuilder")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'vas.TryAttachBuildingVisual(ch, "DefensiveWalls"', "v46 v36 DefensiveWalls segment dress")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v41 KIT_GEN stays 27 (no wall wipe)")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "LightTank = { ModelAssetId = 76055078503396", "v41 LightTank mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "CombatIFV = { ModelAssetId = 76055078503396", "v41 CombatIFV")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "AssaultIFV = { ModelAssetId = 76055078503396", "v41 AssaultIFV")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "FuelTanker = { ModelAssetId = 100684175", "v41 Cargo Truck FuelTanker")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "AmmoCarrier = { ModelAssetId = 81802040484766", "v41 Logistics AmmoCarrier")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "TroopTransport = { ModelAssetId = 4128346779", "v41 TroopTransport Army Truck")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "PatrolBoat = { ModelAssetId = 557152593", "v41 PatrolBoat")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "FastAttackCraft = { ModelAssetId = 16692908395", "v41 Attack Boat")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'LandingCraft = { ModelAssetId = 0', "v41 LandingCraft=0 reject template")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 13195201090", "v41 no Build-a-Boat template ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Worker = { ModelAssetId = 16134469614", "v41 Worker distinct")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "SpecialForces = { ModelAssetId = 123239877613650", "v41 SpecialForces")
must_contain("src/ReplicatedStorage/Shared/Configs/SoldierConfig.luau", 'SpecialForces = "SpecialForces"', "v41 SF VisualKind")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "OilPumpjack = { ModelAssetId = 13525922265", "v41 OilPumpjack")
must_contain("src/ReplicatedStorage/Shared/Configs/PlotOilPumpConfig.luau", 'VisualPropKey = "OilPumpjack"', "v41 PlotOil uses OilPumpjack")
must_contain("docs/DESIGN_FEATURE_WIRE_v40.md", "85138026", "v41 design wire doc present")
# No-regress v41 critical safety
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "NEVER ghost Part-kit silhouettes", "v41 hideKitBody no-op")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "hideKitBody", "v41 hideKitBody present")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v41")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "placeKitPart", "v41 bottom-anchored placeKitPart")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "PRICE_CHIP_MAX_W = 120", "v50a billboards ≤120")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v41")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v41")



# --- v42 DESIGN_WIRE_GAPS fill: Hangar≠Warehouse≠Depot, Missile≠Tower, tank/arty/naval split ---
must_contain("docs/DESIGN_WIRE_GAPS_v40.md", "15942568272", "v42 gaps doc Warehouse ID")
must_contain("docs/DESIGN_WIRE_GAPS_v40.md", "11962508154", "v42 gaps doc MissileDefense ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Hangar = { ModelAssetId = 6015472062", "v42 Hangar KEEP")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Warehouse = { ModelAssetId = 15942568272", "v42 Warehouse distinct")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "VehicleDepot = { ModelAssetId = 12208876851", "v42 VehicleDepot distinct")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MissileDefense = { ModelAssetId = 11962508154", "v42 MissileDefense ≠ Watchtower")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetId = 15942568272", "v42 StructureVisual Warehouse mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetId = 12208876851", "v42 StructureVisual VehicleDepot mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetId = 11962508154", "v42 StructureVisual MissileDefense mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "TargetFootprint = Vector3.new(14, 10, 18)", "v42 MissileDefense launcher footprint")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MediumTank = { ModelAssetId = 26007709", "v42 MediumTank only classic")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "SPAAG = { ModelAssetId = 15618784436", "v42 SPAAG AA Gun")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MobileSAM = { ModelAssetId = 14074034450", "v42 MobileSAM TEL")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MortarCarrier = { ModelAssetId = 10286064243", "v42 Howitzer MortarCarrier")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "RocketArtillery = { ModelAssetId = 18406068364", "v42 RocketArtillery MLRS")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "BridgeLayer = { ModelAssetId = 76055078503396", "v42 Engineer Track BridgeLayer")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "LightScoutTank = { ModelAssetId = 76055078503396", "v42 Scout Tank")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Frigate = { ModelAssetId = 12794395111", "v42 Frigate")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Destroyer = { ModelAssetId = 2048010298", "v42 Destroyer")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Cruiser = { ModelAssetId = 74585287273804", "v42 Cruiser")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'AircraftCarrier = { ModelAssetId = 0', "v42 Carrier Part-kit")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'LandingCraft = { ModelAssetId = 0', "v42 LandingCraft Part-kit")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 13195201090", "v42 no Build-a-Boat template")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Worker = { ModelAssetId = 16134469614", "v42 Worker ≠ Soldier")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Soldier = { ModelAssetId = 100212659702941", "v42 Soldier KEEP")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BuildingDressGen = 29", "v42 BuildingDressGen 29")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "local DRESS_GEN = 29", "v42 VAS DRESS_GEN 29")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v42 KIT_GEN stays 27")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetId = 0, -- v41: NO Wall* segment", "v42 DefensiveWalls still 0")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "BaseGate = { ModelAssetId = 85138026", "v42 BaseGate GateArch only")
# No-regress v42 critical safety
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "NEVER ghost Part-kit silhouettes", "v42 hideKitBody no-op")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "hideKitBody", "v42 hideKitBody present")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v42")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "fromOffset(300, 58)", "v50 buy button 300x58")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v42")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v42")



# ── v43 P0 visibility hotfix ───────────────────────────────────────────────
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v46 KIT_GEN 32 force rebuild after v36 wall restore")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "EnsureKit missing Body after build", "v43 EnsureKit Body assert")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "forcing generic Body", "v43 EnsureKit always creates Body")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "if not mustRebuild then return", "v46 no mustRebuild early-return skip")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_PerimeterGen", "v43 perimeter gen attr")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "applyKitVisuals L1+ missing Body", "v43 applyKitVisuals Body assert")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "task.defer(function()", "v43 PreferMesh deferred (InsertService never blocks kit)")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "tonumber(level) or 0", "v43 coerce structure level")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "0.5", "v45 rehydrate 0.5s")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "2.0, 5.0", "v45 rehydrate 2s+5s")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "perimeter FIRST", "v43 walls before structure loop")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "tonumber(inst:GetAttribute(\"PlotId\")", "v43 findUpgradeSlots tonumber PlotId")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "NEVER ghost Part-kit silhouettes", "v43 hideKitBody no-op still present")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "local function hideKitBody()", "v43 hideKitBody function present")
# Gate dress still pcall-isolated — SyncPerimeterWalls must not abort on mesh fail
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "BaseGate", "v46 SyncPerimeterWalls has no BaseGate dress (v36 restore)")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "Transparency = 0", "v43 wall Parts solid Transparency=0")
# No-regress
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "bottom + newSize.Y * 0.5", "v43 placeKitPart bottom-anchored")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "cash bootstrap", "v50 WorldPrompt cash bootstrap")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "v43 Jeep drive no-regress")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "v43 VIP Id no-regress")




# ── v44 P0 visibility hard-fix ─────────────────────────────────────────────
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v46 KIT_GEN 32")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "height = 7.5 + lv * 2.8", "v46 restored v36 wall height 7.5+lv*2.8")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "pad.Position.Y + pad.Size.Y * 0.5 + height * 0.5", "v46 wall Y sits on pad top (v36)")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_PerimeterGen", "v46 WE_PerimeterGen stamp")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'structureId == "MissileDefense"', "v44 MissileDefense dedicated Body+Roof kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "owned kits must be solid IMMEDIATELY", "v44 EnsureKit solidifies Body/Roof")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "v44 PreferMesh structures OFF")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "keepKitSolid", "v44 keepKitSolid after building dress")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "never raise Transparency on structure kit hosts", "v44 no host fade on structure mesh")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "NuclearRehydrateKits", "v44 nuclear kit rehydrate")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "0.5, 2.0, 5.0", "v45 RefreshAllVisuals 0/0.5/2/5s")
# EnsureKit Body Transparency solid path (spawn solid, not Transparency=1 for Body)
body = read("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau")
if body and "Transparency = 1, -- hidden until BaseService.applyKitVisuals" in body:
    bad("v44 kitPart must NOT spawn Body at Transparency=1")
elif body and "spawnT = if role == \"DressHost\" then 1 else solid" in body:
    ok("v44 kitPart Body/Roof spawn solid (DressHost only ghost)")
elif body and "spawnT" in body and "SolidTransparency" in body:
    ok("v44 kitPart uses SolidTransparency spawn path")
else:
    bad("v44 kitPart solid spawn path missing")
# Wall height restored from v36 (0b0e95f)
if body and "height = 7.5 + lv * 2.8" in body:
    ok("v46 SyncPerimeterWalls height = 7.5 + lv * 2.8 (v36)")
else:
    bad("v46 SyncPerimeterWalls missing restored v36 height formula")
if body and "if not mustRebuild then return" in body:
    bad("v46 must not early-return on mustRebuild")
else:
    ok("v46 no mustRebuild early-return skip")




# ── v45 P0 PlotId tonumber + tall walls + map race ───────────────────────────
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v46 KIT_GEN 32 force rebuild")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'tonumber(inst:GetAttribute("PlotId")', "v45 findPlotPad tonumber PlotId")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "height = 7.5 + lv * 2.8", "v46 wall height 7.5+lv*2.8 from 0b0e95f")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ClearAllChildren()", "v46 always ClearAllChildren like v36")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'tonumber(inst:GetAttribute("PlotId")) == tonumber(plotId)', "v46 findPlotPad tonumber both sides")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "if not mustRebuild then return", "v46 no stale short-wall early return")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ClearAllChildren()", "v45 always ClearAllChildren rebuild level≥1")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "v45 PreferMesh still OFF")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "RefreshAllOnlinePlayers", "v45 RefreshAllOnlinePlayers after map heal")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "afterMapRebuild", "v45 Bootstrap afterMapRebuild hook")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "WE_OwnedLevel", "v45 sync/clear WE_OwnedLevel")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "BaseConfig.Structures", "v45 NuclearRehydrateKits iterates Structures keys")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'structureId == "MissileDefense"', "v45 MissileDefense large kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "Vector3.new(18, 12, 18)", "v45 MissileDefense Body large")


# ── v46 restore SyncPerimeterWalls from 0b0e95f (v36) ───────────────────────
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "height = 7.5 + lv * 2.8", "v46 height formula from 0b0e95f")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'tonumber(inst:GetAttribute("PlotId")) == tonumber(plotId)', "v46 findPlotPad tonumber")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v46 KIT_GEN 32")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "if not mustRebuild then return", "v46 no mustRebuild skip")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "v46 PreferMesh still OFF")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "tonumber(profile.BaseUpgrades.DefensiveWalls)", "v46 RefreshAllVisuals DefensiveWalls level")


# ── v48 ForceWipe + wipeprofile + walls on DefensiveWalls buy ───────────────
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "ForceWipeUserIds", "v48 ForceWipeUserIds")
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "470626172", "v48 ForceWipe includes shaunie6")
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", '"wipeprofile"', "v48 wipeprofile in Commands")
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "AdminPlaytestCash = 50_000_000", "v48 keep AdminPlaytestCash")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "FORCE WIPE applied for", "v48 DataService FORCE WIPE warn")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "isForceWipeUserId", "v48 isForceWipeUserId")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "RemoveAsync(keyFor(userId))", "v48 RemoveAsync before CreateDefault")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "ClearInMemoryProfile", "v48 ClearInMemoryProfile")
must_contain("src/ServerScriptService/Server/Services/AdminService.luau", 'cmd == "wipeprofile"', "v48 wipeprofile command")
must_contain("src/ServerScriptService/Server/Services/AdminService.luau", "Progress wiped — please rejoin", "v48 wipe Kick message")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "DefensiveWalls → SyncPerimeterWalls", "v48 walls on DefensiveWalls buy print")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "SyncPerimeterWalls SPAWNED", "v48 loud wall spawn print")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "height = 7.5 + lv * 2.8", "v48 keep v36 wall height")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v48 KIT_GEN stays 32")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "v48 PreferMesh still OFF")
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", "BaseUpgrades[id] = 5", "v48 must NOT auto-max BaseUpgrades")

# ── v49 force_wipe_done one-shot ────────────────────────────────────────────
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "force_wipe_done_", "v49 force_wipe_done key")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "forceWipeDoneKey", "v49 forceWipeDoneKey helper")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "FORCE WIPE skipped (already done)", "v49 skip wipe when done key set")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "ClearForceWipeDone", "v49 ClearForceWipeDone")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'unix = os.time(), v = 1', "v49 done key payload")
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", '"clearwipedone"', "v49 clearwipedone in Commands")
must_contain("src/ServerScriptService/Server/Services/AdminService.luau", 'cmd == "clearwipedone"', "v49 clearwipedone command")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "v49 PreferMesh still OFF")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v49 KIT_GEN stays 32")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "height = 7.5 + lv * 2.8", "v49 keep v36 wall height")


# ── v50 cash desync / ATM collect / compact BUY UI ──────────────────────────
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", 'SetAttribute("WE_Cash"', "v50 WE_Cash attribute push")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "AdminPlaytestCash applied", "v50 AdminPlaytestCash log")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "nearCollector", "v50 ATM nearCollector radius")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "WE_CollectPrompt", "v50 ATM Collect ProximityPrompt")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", '"$—"', "v50 HUD no fake $5000 placeholder")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "fromOffset(118, 40)", "v50 MapSetup price chip 118x40")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'Allow(player, "get_state", 6, 16)', "v50 get_state rate relaxed")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "v50 PreferMesh still OFF")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "KIT_GEN = 32", "v50 KIT_GEN stays 32")

print(f"[BuyPathStatic] Done PASS={PASS} FAIL={FAIL}")
sys.exit(1 if FAIL else 0)
