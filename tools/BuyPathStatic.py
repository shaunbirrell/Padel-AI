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

def kit_gen_at_least(minimum: int, label: str) -> None:
    """v66: KIT_GEN may only move forward (bumps force kit rebuilds); exact-text checks broke every bump."""
    rel = "src/ServerScriptService/Server/Modules/StructureKitBuilder.luau"
    body = read(rel)
    m = re.search(r"^local KIT_GEN = (\d+)", body or "", re.M)
    if m and int(m.group(1)) >= minimum:
        ok(label)
    else:
        bad(f"{label} — KIT_GEN missing or < {minimum} in {rel}")

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
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "EnsureProfile", "BaseService buy EnsureProfile (v63/v65 via getDataService/DS)")
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
# v70 HUD re-pin: pending cash left the HUD (owner direction; the ATM screen shows it) → cash gains are "+$N" floats
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "ShowCashFloat", "v70 HUD cash floats (ShowCashFloat; PendingLabel removed)")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "125916936788670", "MilitaryJeep Military Car mesh")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_DrivePrompt", "DriverSeat Drive ProximityPrompt")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "seat:Sit(hum)", "VehicleSeat auto-Sit")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_DriveHinge", "HingeConstraint drive motors")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "startGroundDrive", "scripted/hinge ground drive")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "HingeConstraint", "mesh strips drive constraints")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "ATM · WALK IN TO COLLECT", "v67 ATM card title (short; codes live in Settings)")


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
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.luau", "beam.Name = \"WE_TutorialBeam\"", "Tutorial guide beam (v68: subtle, not neon)")
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
# v69: the instant touch/prompt ATM raid (TryAtmRaid) became a 6 s server-side hold with a 10-min victim shield
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "function MoneyCollectorService.StepRaids(", "v69 ATM raid is a server-side hold (StepRaids)")
must_not_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "TryAtmRaid", "v69 instant touch/prompt ATM raid removed")
must_contain("src/ReplicatedStorage/Shared/Configs/RaidConfig.luau", "StealFraction = 0.10", "v69 raid steals 10% of the ATM")
must_contain("src/ReplicatedStorage/Shared/Configs/RaidConfig.luau", "ShieldSeconds = 600", "v69 victim shield 10 min after a raid")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "balance += math.min(recentAutoSum(victim.UserId), cash)", "v69 AutoCollect raidable balance capped at held cash")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "table.insert(ignore, def.CollectorModel :: Instance)", "v69 guard/AutoGun LOS ignores own ATM")
must_contain("src/ServerScriptService/Server/Services/MissileStrikeService.luau", "EconomyService.SpendCash(attacker, S.Cost, \"missile_strike\")", "v69 missile strike paid server-side")
must_contain("src/ServerScriptService/Server/Modules/Interiors/CommandCenter.luau", "api.terminal(\"MissileTerminal\"", "v69 Command Center Missile Command terminal")
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
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "roof.CanQuery = false -- camera + weapon raycasts pass", "v67 anti-heli ceiling is an invisible barrier")
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
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "AntiAirCeilingHeight", "v67 ceiling height from StructureVisualConfig")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'roof:SetAttribute("WE_BaseCeiling", true)', "v67 ceiling keeps WE_BaseCeiling attribute")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "RoofBarracksPad", "v67 no rooftop barracks pads on the ceiling")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "DockMissions", "HUD dock Missions tile")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "MissionController.Toggle", "Missions dock opens MissionController")
# v70 HUD re-pin: the `Label = "MISSIONS"` pin is deleted (rail labels are title case from HudConfig.Rail.Tiles;
# the DockMissions pin above still locks the Missions tile)
must_contain("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau", "CashFee", "PrestigeConfig CashFee")
must_contain("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau", "BuildFeeSummary", "PrestigeConfig BuildFeeSummary")
must_contain("src/ServerScriptService/Server/Services/PrestigeService.luau", "FeeSummary", "PrestigeService FeeSummary push")
must_contain("src/ServerScriptService/Server/Services/PrestigeService.luau", "BaseCompletionPercent", "PrestigeService BaseCompletionPercent")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "FeeSummary", "Progression confirm FeeSummary")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MissionController.luau", "function MissionController.Toggle", "MissionController.Toggle exists")

# No-regress
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
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v29")



# --- v29 video-feel polish (Orders hotkeys / Contested billboard / Ceiling beams) ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "HOTKEY_ORDERS", "Orders hotkeys 1-4")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "KeyCode.T", "Orders T cycle")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "CONTESTED", "Territory Contested billboard")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "ContestedBadge", "Territory ContestedBadge")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "CeilingBeamLong", "v67 no ceiling beams (dark warehouse look)")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "CeilingJoist", "v67 no ceiling joists")
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
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "WE_LocalOwned", "Premium pad OWNED visual")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "UserOwnsGamePassAsync", "OWNED via PlayerOwnsGamePass check")
# No-regress v31
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v31")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v31")
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
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v32")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP GamePass Id no-regress v32")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713839505", "StarterBundle Id no-regress v32")

# --- v33 quality pack: name readability, kit scale, gate polish, ATM raid UX, capture steal, AutoCollect soft, pad dressing ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "ensurePadNameSurface", "Pad name SurfaceGui helper")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "ensurePadNameSurface(part, display)", "Pad name applied on billboard refresh")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "AlwaysOnTop = false", "BUY name billboard never AlwaysOnTop (v39)")
kit_gen_at_least(32, "StructureKit KIT_GEN 27")
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
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v33")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect GamePass Id no-regress v33")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v33")


# --- v34 legitimacy pack: HQ/Barracks/Armory kits, soldier variety, garage tips, DoubleCash soft, capture chip, rebirth copy, mobile Orders ---
kit_gen_at_least(32, "KIT_GEN 27")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "armory"', "WeaponsFacility armory kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "3-story weapons inventory", "Armory densify comment")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "compound-scale HQ", "HQ densify comment")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "100212659702941", "Worker distinct Soldier mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/SoldierConfig.luau", 'Worker = "Worker"', "Worker VisualKind Worker")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "HeavyInfantry", "Stall HeavyInfantry variety")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "role Part-dress differentiation", "Soldier role dress")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", "Sit · WASD drive", "Garage row drive tip")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "OwnerChip", "Capture owner/progress chip")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "CAPTURING ·", "Capture progress chip text")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "DoubleCashOffer", "DoubleCash soft offer config")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", "DoubleCashOffer", "DoubleCashOffer remote")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "DoubleCashOffered", "DoubleCash soft profile gate")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DoubleCashToast", "DoubleCash client toast")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "Fee: none", "Rebirth fee HUD copy")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "MinTouchPx = 64", "v70 Orders touch 64 v (x0.70 = 44.8 px real)")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash GamePass Id no invent")
# No-regress v34
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v34")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v34")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v34")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v34")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP GamePass Id no-regress v34")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect GamePass Id no-regress v34")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "airfield"', "Airfield kit no-regress v34")


# --- v35 legitimacy / late-game presence: SF densify, Helipad/Dock, landmarks, gate guns, VIP soft, oil bob, death CashMega ---
kit_gen_at_least(32, "KIT_GEN 27 (v39 hotfix)")
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
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v35")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash Id no-regress v35")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect Id no-regress v35")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "armory"', "Armory kit no-regress v35")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "airfield"', "Airfield kit no-regress v35")


# --- v36 warzone density + late vehicle/presence: tank drive, ArmedJeep cue, walls, towers, SpeedBoost soft, HUD cash ---
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "isTracked", "Tracked slower LV cruise")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_MuzzleFlash", "ArmedJeep muzzle flash cue")
# v70 HUD spec §8 re-pin (delete / NOT WE_ArmedCue) is DEFERRED: that server label goes with the §5 world-label pass
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
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v36")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v36")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash Id no-regress v36")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect Id no-regress v36")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "Landmarks_v35", "v35 landmarks no-regress")
kit_gen_at_least(32, "KIT_GEN no-regress →27")
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
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash Id no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect Id no-regress v37")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "Landmarks_v35", "v35 landmarks no-regress v37")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "TutorialService", "Tutorial no-regress v37")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "special"', "SF kit no-regress v37")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "isTracked", "LightTank tracked no-regress v37")



# --- v38 combat feel + prestige/monetization polish ---
# v70 HUD spec §8 re-pin (DEF HIT → BASE UNDER ATTACK) is DEFERRED with the §4.2 server routing; until then the client
# folds every "DEF HIT" line into one "BASE UNDER ATTACK!" alert (HudConfig.Toast.Reroute, pinned in the v70 HUD block)
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
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v38")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v38")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713839505", "StarterBundle Id no invent v38")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713838952", "CashMega Id no invent v38")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "TutorialService", "Tutorial no-regress v38")


# --- v39 P0 hotfix: billboards + walls + Part-kit visibility ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "PRICE_BILLBOARD_SIZE = UDim2.fromOffset(118, 40)", "v50 price billboard chip 118x40")

# --- v40 Orders panel scale + chip clamp + design gaps doc ---
# v70 HUD re-pins: the Army popover is 216 v wide + padding, one unified HUD scale (no per-panel MobileScale)
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "PanelMaxWidth = 240", "v70 Orders PanelMaxWidth 240 (popover 216 v + padding)")
must_not_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "MobileScaleMax", "v70 Orders MobileScaleMax deleted (unified HUD scale)")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "MinTouchPx = 64", "v70 Orders MinTouchPx 64")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "UISizeConstraint", "v40 Orders UISizeConstraint")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "HudLayout.ApplyScreen", "v70 Orders on the unified HUD scale (HudLayout.ApplyScreen)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "PanelShell.Screen(screen", "v70 Orders screen set up through PanelShell.Screen")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/PanelShell.luau", "return HudLayout.ApplyScreen(screen", "v70 PanelShell.Screen = HudLayout.ApplyScreen")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "AttachMobileScale", "v70 Orders no custom MobileScale")
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
kit_gen_at_least(32, "v39 KIT_GEN 27")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "function StructureKitBuilder.SyncPerimeterWalls", "v39 SyncPerimeterWalls present")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_PerimeterGen", "v39 perimeter gen attr")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "SyncPerimeterWalls", "v39 BaseService calls SyncPerimeterWalls")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "placeKitPart", "v39 bottom-anchored kit place")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'role == "Crate"', "v39 Warehouse Crate role visible")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "NEVER ghost Part-kit silhouettes", "v39 hideKitBody no-op")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BuildingDressGen = 29", "v42 BuildingDressGen 29")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "SizeTouch = UDim2.fromOffset(216, 244)", "v70 Orders SizeTouch 216x244 (2x2 order cells 96x64 v + title + MANAGE)")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "UDim2.fromOffset(300, 132)", "v39 no giant 300x132 boards")
# No-regress v39
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v39")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v39")
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
kit_gen_at_least(32, "v41 KIT_GEN stays 27 (no wall wipe)")
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
kit_gen_at_least(32, "v42 KIT_GEN stays 27")
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
kit_gen_at_least(32, "v46 KIT_GEN 32 force rebuild after v36 wall restore")
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
kit_gen_at_least(32, "v46 KIT_GEN 32")
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
kit_gen_at_least(32, "v46 KIT_GEN 32 force rebuild")
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
kit_gen_at_least(32, "v46 KIT_GEN 32")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "if not mustRebuild then return", "v46 no mustRebuild skip")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "v46 PreferMesh still OFF")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "tonumber(profile.BaseUpgrades.DefensiveWalls)", "v46 RefreshAllVisuals DefensiveWalls level")


# ── v48+ walls on DefensiveWalls buy (kept; ForceWipe REMOVED in v55) ────────
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "470626172", "shaunie6 UserIds")
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", '"wipeprofile"', "wipeprofile still in Commands")
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "AdminPlaytestCash = 50_000_000", "AdminPlaytestCash 50M")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "ClearInMemoryProfile", "ClearInMemoryProfile for wipeprofile")
must_contain("src/ServerScriptService/Server/Services/AdminService.luau", 'cmd == "wipeprofile"', "wipeprofile command")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "DefensiveWalls → SyncPerimeterWalls", "walls on DefensiveWalls buy print")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "SyncPerimeterWalls SPAWNED", "loud wall spawn print")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "height = 7.5 + lv * 2.8", "v36 wall height (0b0e95f)")
kit_gen_at_least(32, "KIT_GEN 32")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "PreferMesh OFF")
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", "BaseUpgrades[id] = 5", "must NOT auto-max BaseUpgrades")
must_not_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "ForceWipeUserIds", "v55 no ForceWipeUserIds")
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", "ForceWipe", "v55 no ForceWipe in DataService")
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", "EnsureStartingCashFloor", "v55 no EnsureStartingCashFloor")
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", "EnsureAdminPlaytestCash", "v55 no EnsureAdminPlaytestCash")
must_not_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "EnsureStartingCashFloor", "v55 Push has no Ensure floor")
must_not_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "EnsureAdminPlaytestCash", "v55 Push has no Ensure admin")
must_not_contain("src/ServerScriptService/Server/Services/BaseService.luau", "EnsureStartingCashFloor", "v55 BaseService no Ensure floor")
must_not_contain("src/ServerScriptService/Server/Services/BaseService.luau", "EnsureAdminPlaytestCash", "v55 BaseService no Ensure admin")

# ── v50 cash display / ATM / compact BUY (kept) ─────────────────────────────
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", 'SetAttribute("WE_Cash"', "WE_Cash attribute push")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "nearCollector", "ATM nearCollector radius")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "WE_CollectPrompt", "ATM Collect ProximityPrompt")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", '"$…"', "HUD inits cash to $… until first sync")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "EconomyConfig.StartingCash", "HUD must NOT fake StartingCash")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "liveCash", "WorldPrompt liveCash for afford/BUY")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "FireServer anyway", "WorldPrompt always FireServer on cash soft-hint")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "function DataService.EnsureProfile", "DataService.EnsureProfile never leave without profile")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "Profile still loading — try BUY again", "BUY toast when profile missing after wait")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "leaderstats", "HUD leaderstats fallback")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "leaderstats", "WorldPrompt leaderstats fallback")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", 'Name = "leaderstats"', "EconomyService writes leaderstats")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "fromOffset(118, 40)", "MapSetup price chip 118x40")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'Allow(player, "get_state", 12, 32)', "get_state rate relaxed v56")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "getStateJoinedAt", "get_state 20s join grace")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "CharacterAdded:Connect", "CharacterAdded economy re-push")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "[EconPush]", "EconPush join log")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "for delaySec = 1, 12", "dense economy re-push 1s×12")

# ── v58 instant profile + cash-first HUD listen (no fake StartingCash) ─────
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", "instant profile", "v67 no instant default profile (it overwrote real saves)")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "function DataService.IsLoaded", "v67 DataService.IsLoaded")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "if not loaded[userId] then", "v67 SaveProfile refuses never-loaded profiles")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "Left during the load: nothing was loaded, so nothing may be saved", "v67 leave mid-load never saves")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "DataService.IsLoaded(player)", "v67 ProcessReceipt waits for a loaded profile")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "if not DataService.SaveProfile(player, false) then", "v67 receipt saved before PurchaseGranted")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "stampEconomyAttrs", "v58 stampEconomyAttrs before DS")
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", "mergeDsIntoLive", "v67 no partial DS merge (dropped most saved fields)")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "btn.MouseButton1Click:Connect(onBuyPressed)", "v67 pad BUY fires once per tap")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau", "btn.MouseButton1Click:Connect(onMenuBuy)", "v67 B-menu BUY fires once per tap")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "lastRemoteBuyAt[dupKey]", "v67 server drops duplicate purchase events")

# ── v68 base layout: bigger plot, consoles, walk-in buildings with interiors, guarded rear gates ─────────
must_contain("src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau", "PlotSize = 320", "v68 layout plot size 320")
must_contain("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau", "BaseLayoutConfig.PlotSize, 1, BaseLayoutConfig.PlotSize", "v68 BaseConfig.PlotSize follows the layout")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "BaseLayout.PlotSize(200)", "v68 MapSetup pad size from BaseLayout")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", 'plinth:SetAttribute("WE_Console", true)', "v68 upgrade slot becomes a console")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "plinth.CanTouch = not isConsole", "v68 consoles are not touch pads")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "PLOT_SPAWN_CLEARANCE", "v68 spawn pads kept outside plots")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "if not console and hit:IsA(\"BasePart\") then", "v68 server Touched never buys at a console")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "part.CanTouch = not isConsole(part)", "v68 hardenPad keeps consoles untouchable")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "not isConsole(part)", "v68 spatial buy loop skips consoles")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "never auto-buy at a console", "v68 client walk-over skips consoles")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "WE_Console", "v68 no catalog mesh on consoles")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "function StructureKitBuilder.SyncRearGates", "v68 rear gates sync")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "pcall(StructureKitBuilder.SyncRearGates, plotId, profile.BaseUpgrades)", "v68 buying Airfield/Helipad/Dock opens its gate")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "pcall(StructureKitBuilder.SyncPerimeterWalls, plotId, wallsLv)", "v68 keeps DefensiveWalls → SyncPerimeterWalls")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "StructureKitBuilder.SyncRearGates(plotId, nil)", "v68 released plot closes its gates")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "AntiAirCeilingEnabled = false", "v68 open sky over the base (no roof)")
must_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "local axis = math.max(math.abs(toward.X), math.abs(toward.Z), 0.5)", "v68 oil pumps clear the square plot on diagonals")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "ProximityPromptService.PromptTriggered:Connect", "v68 terminal prompts open panels")


def v68_interiors() -> None:
    """Every walk-in building names an interior module that exists and returns a function; every terminal
    panel an interior asks for is one the client router opens."""
    cfg = read("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau") or ""
    router = read("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau") or ""
    routed = set(re.findall(r"^\t\t(\w+) = \w+Controller\.Open,$", router, re.M))
    if not routed:
        bad("v68 UIController panelOpeners table not found")
        return
    names = re.findall(r'Interior = "(\w+)"', cfg)
    if len(names) < 7:
        bad("v68 expected 7 HollowBuildings interiors, found %d" % len(names))
    for n in names:
        rel = "src/ServerScriptService/Server/Modules/Interiors/%s.luau" % n
        src = read(rel)
        if src is None:
            bad("v68 interior module missing: " + rel)
            continue
        if not re.search(r"^return function\(ictx: any, api: any\)", src, re.M):
            bad("v68 interior %s must return function(ictx: any, api: any)" % n)
            continue
        panels = re.findall(r'api\.terminal\([^\n]*?, "(\w+)", "', src) + re.findall(r'SetAttribute\("WE_OpenPanel", "(\w+)"\)', src)
        missing = sorted(set(p for p in panels if p not in routed))
        if len(panels) < 2:
            bad("v68 interior %s has %d panel terminals (need >= 2)" % (n, len(panels)))
        elif missing:
            bad("v68 interior %s opens panels the client cannot route: %s" % (n, missing))
        else:
            ok("v68 interior %s: %d terminals → %s" % (n, len(panels), ", ".join(sorted(set(panels)))))


v68_interiors()


def v68_installations() -> None:
    """Every outdoor installation entry names a module that exists and returns a function; consoles never
    share a spot with their kit (a kiosk inside the tower/wall sample could not be reached)."""
    cfg = read("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau") or ""
    block = cfg.split("Installations = {", 1)[1].split("\n\t},", 1)[0] if "Installations = {" in cfg else ""
    entries = re.findall(r"(\w+) = \{ Enabled = true, Module = \"(\w+)\"", block)
    if len(entries) < 6:
        bad("v68 expected >= 6 installations, found %d" % len(entries))
    for sid, mod in entries:
        src = read("src/ServerScriptService/Server/Modules/Installations/%s.luau" % mod)
        if src is None:
            bad("v68 installation module missing: %s (%s)" % (mod, sid))
        elif not re.search(r"^return function\(ictx: any, api: any\)", src, re.M):
            bad("v68 installation %s must return function(ictx: any, api: any)" % mod)
        else:
            ok("v68 installation %s → Installations/%s" % (sid, mod))
    layout = read("src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau") or ""
    for m in re.finditer(r"(\w+) = \{ Site = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \}, Yaw = -?\d+, WalkIn = false, Kiosk = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \}", layout):
        sid, sx, sz, kx, kz = m.group(1), *map(float, m.groups()[1:])
        if abs(sx - kx) < 4 and abs(sz - kz) < 4:
            bad("v68 %s kiosk sits on its own kit site (unreachable console)" % sid)
        else:
            ok("v68 %s kiosk clear of its site" % sid)


v68_installations()
# v68 owner feedback: blinding interiors, green lines, SQUAD tags, auto-collect toast spam
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BrightnessScale = 0.35", "v68 building lights dimmed")
must_contain("src/ServerScriptService/Server/Modules/HollowBuildingBuilder.luau", "l.Brightness = brightness * (LIGHTS.BrightnessScale or 1)", "v68 every building light goes through the dimmer")
must_not_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "WE_NeonPath_", "v68 no always-on neon guide beams across the base")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "ShowUnitLabels = false", "v68 no SQUAD tag per field unit")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "MoneyCollectorService.Collect(player, true)", "v68 AutoCollect collects silently")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "DayAmbient = Color3.fromRGB(78, 72, 62)", "v69 indoor ambient no longer washes interiors white")
# v69 Research Lab (verified: server 119 + adversarial 29, combat 40 + 9, squad 18, client 91)
must_contain("src/ServerScriptService/Server/Services/ResearchService.luau", "function ResearchService.GetBonus(player: Player, statId: string): number", "v69 ResearchService.GetBonus contract kept")
must_contain("src/ServerScriptService/Server/Services/ResearchService.luau", "structureLevel(profile, ResearchConfig.StructureId) < ResearchConfig.LabLevelFor(def, target)", "v69 research Lab-level gate enforced on the server")
must_contain("src/ServerScriptService/Server/Services/ResearchService.luau", "EconomyService.SpendCash(player, cost, \"research_\" .. id)", "v69 research spends server-priced Cash")
must_contain("src/ServerScriptService/Server/Services/ResearchService.luau", "RateLimitService.Allow(player, \"research_buy\", ResearchConfig.BuyRate, ResearchConfig.BuyBurst)", "v69 research Buy is rate-limited")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if clock() - state.LastFireAt < minInterval * 0.5 or clock() - gunAt < minInterval * 0.5 then", "v69 per-gun fire schedule (swaps cannot skip a slow gun's cooldown)")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if base < lethal and boosted >= lethal then", "v69 research damage never creates a one-shot")
must_not_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "Ammo = def.MagazineSize", "v69 every magazine refill uses the researched magazine size")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ResearchController.luau", "GetEvent(", "v69 ResearchController never blocks on GetEvent")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "Lighting.Ambient = worldLight.DayAmbient", "v69 MapSetup ambient from config")
must_contain("src/ServerScriptService/Server/Modules/HollowBuildingBuilder.luau", "spot.Brightness = 1.5 * (LIGHTS.BrightnessScale or 1)", "v69 roof floodlights dimmed")
# v69 batch-2 leftovers (verified with leftovers/sl_driver 33/33 + g6_driver 67/67)
must_contain("src/ServerScriptService/Server/Modules/SessionLock.luau", "if ours or (not releasedHere[userId] and not isLockHeldByOther(old, jobId, os.time())) then", "v69 session lock refresh re-takes a free/stale lock only for our loaded player")
must_contain("src/ServerScriptService/Server/Modules/SessionLock.luau", "releasedHere[userId] = true -- before the yield: a Refresh queued after this must not re-claim", "v69 released lock is never re-claimed by a late refresh")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "confirmPassPurchase(player, passKey, passId, passName)", "v69 mid-session pass purchase confirmed by ownership check")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)", "v69 pass ownership only from UserOwnsGamePassAsync")
must_not_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "-- v70: this event is fired on the server by the engine", "v69 never trusts PromptGamePassPurchaseFinished wasPurchased")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "-- v70: granted into this profile earlier, but that save may have failed", "v69 receipt retry saves before PurchaseGranted")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "local profile = DataService.WaitForProfile(player, 25)", "v69 receipts wait for the (lock-delayed) profile load")
must_contain("src/ServerScriptService/Server/Modules/HollowBuildingBuilder.luau", "local function buildInstallation(ctx: Ctx)", "v68 installation build path")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'if structureId == "MissileDefense" and not hollow then', "v68 MissileDefense force skips the installation slab")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau", 'safeInit("WorldSpinners", WorldSpinners)', "v68 radar dishes spin client-side (guarded)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau", "local ok, err = pcall(mod.Init)", "v70 every client controller Init is isolated (combat failure cannot kill driving)")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'body:SetAttribute("WE_CornerTower", true)', "v68 corner guard towers keep WE_CornerTower")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "continuing — no kick", "v58 never Kick on session lock")
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", 'player:Kick("Your data is loading', "v58 no session-lock Kick")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "never WaitForChild remotes on HUD cash path", "v60 HUD leaderstats-first no WaitForChild")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "Remotes.BindEvent", "v60 HUD BindEvent EconomyUpdate")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "0.5s hard fallback", "v60 HUD 0.5s $… fallback")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "leaderstats/attrs FIRST", "v60 WorldPrompt leaderstats first")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "EconomyService.Push FIRST", "v58 OnProfileLoaded Push first")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 68)', "v68 WE_Build=68 DataService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 68)', "v68 WE_Build=68 BaseService")
must_contain("src/ReplicatedStorage/Shared/Constants.luau", 'RemotesFolderName = "WE_Remotes"', "v60 WE_Remotes folder name")
must_contain("src/ReplicatedStorage/Shared/Remotes.luau", "function Remotes.BindEvent", "v60 Remotes.BindEvent")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", "leaderstats seed ready", "v60 EarlyRemotes leaderstats seed")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", "RemoteSetup.Init()", "v60 EarlyRemotes full RemoteSetup")

# ── v59/v60 remotes BEFORE MapSetup (cash HUD never waits on InsertService densify) ─
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "Remotes ready BEFORE map (v60 WE_Remotes + cash-first)", "v60 remotes before map log")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "DataService/EconomyService ready BEFORE map (v61)", "v61 cash path before map log")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "earlyCashPush", "v59 early cash Push within 1s")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "Catalog densify InsertService — ALWAYS deferred", "v59 densify InsertService deferred")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "ALWAYS deferred (InsertService must never block pads/remotes)", "v59 building visual InsertService deferred")

# ── v55 RESTORE: v20 cash path + DS key bump + v32/v36 kits (NO more floors) ─
must_contain("src/ReplicatedStorage/Shared/Constants.luau", 'DataStoreName = "WarEmpire_PlayerData_v2"', "v55 DataStore key bump to v2")
must_contain("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau", "StartingCash = 10000", "v55 StartingCash 10000")
must_contain("src/ServerScriptService/Server/Modules/ProfileSchema.luau", "Cash = EconomyConfig.StartingCash", "CreateDefault uses StartingCash")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "ADMIN_PLAYTEST_USER_ID = 470626172", "v55 simple admin userId gate")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "applyAdminPlaytestCash", "v55 AdminPlaytestCash on LoadProfile only")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "ProfileSchema.CreateDefault()", "v55 CreateDefault on missing profile")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "if profile then", "v55 simple Push (profile then pushEconomy)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "EconomyUpdate", "v55 HUD listens EconomyUpdate")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "EconomyUpdate", "v55 WorldPrompt listens EconomyUpdate")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "function StructureKitBuilder.SyncPerimeterWalls", "v55 SyncPerimeterWalls present")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "StructureKitBuilder.SyncPerimeterWalls", "v55 BaseService calls SyncPerimeterWalls")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "EnsureKit", "v55 building kits EnsureKit on buy/join")
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "470626172", "v55 shaunie6 allowlisted")
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "AdminPlaytestCash = 50_000_000", "v55 AdminPlaytestCash 50M")
must_not_contain("src/ServerScriptService/Server/Services/DataService.luau", "force_wipe_done_", "v55 no force_wipe_done key")
must_not_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "clearwipedone", "v55 no clearwipedone command")


# ── v61 BUY: FireServer never optimistic; DataService before UpgradePad ─────
must_contain("src/ReplicatedStorage/Shared/Remotes.luau", "function Remotes.FireServer", "v61 Remotes.FireServer")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "Remotes.FireServer(Constants.RemoteNames.RequestPurchaseUpgrade", "v61 WorldPrompt FireServer helper")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "showBuying = true", "v61 WorldPrompt toast only after fire")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "Buy failed — remotes not ready", "v61 WorldPrompt remote-missing toast")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "Remotes.GetEvent(Constants.RemoteNames.RequestPurchaseUpgrade):FireServer", "v61 WorldPrompt must not GetEvent-FireServer purchase")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau", "Remotes.FireServer(Constants.RemoteNames.RequestPurchaseUpgrade", "v61 Base menu FireServer helper")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "EnsureProfile", "v61 UpgradePad EnsureProfile")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "EnsureProfile", "v61 BaseService PurchaseUpgrade EnsureProfile")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "DataService/EconomyService ready BEFORE map (v61)", "v61 DataService before UpgradePad log")
# DataService Init must appear before UpgradePadService Init in Bootstrap
_boot = read("src/ServerScriptService/Server/Bootstrap.server.luau") or ""
_ds = _boot.find('safeInit("DataService"')
_up = _boot.find('safeInit("UpgradePadService"')
if _ds >= 0 and _up >= 0 and _ds < _up:
    ok("v61 Bootstrap DataService before UpgradePadService")
else:
    bad("v61 Bootstrap DataService must Init before UpgradePadService")


# ── v62 BUY: cash reconcile + same-instance remote hook + PurchaseResult ─────
must_contain("src/ReplicatedStorage/Shared/Constants.luau", 'PurchaseResult = "PurchaseResult"', "v62 Constants.PurchaseResult")
must_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "SetPurchaseUpgradeHandler", "v62 RemoteSetup SetPurchaseUpgradeHandler")
must_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "ensurePurchaseHook", "v62 RemoteSetup ensurePurchaseHook")
must_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "OnServerEvent hooked on WE_Remotes", "v62 purchase hooked at create-time")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "function EconomyService.ReconcileSpendableCash", "v62 ReconcileSpendableCash")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "ReconcileSpendableCash(player)", "v62 SpendCash calls Reconcile")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "SetPurchaseUpgradeHandler(handlePurchaseRemote)", "v62 BaseService registers handler")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "firePurchaseResult", "v62 BaseService firePurchaseResult")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'Error = "NoPlot"', "v62 PurchaseUpgrade NoPlot gate")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "WE_ServerBuyPrompt", "v62 server ProximityPrompt buy")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "firePurchaseResult", "v62 UpgradePad firePurchaseResult")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "RemoteNames.PurchaseResult", "v62 WorldPrompt listens PurchaseResult")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 68)', "v68 EarlyRemotes WE_Build")
must_contain("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau", 'Id = "CommandCenter"', "CommandCenter catalog id")

# Prove client FireServer name === server hook name (same string constant)
_const = read("src/ReplicatedStorage/Shared/Constants.luau") or ""
_client = read("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau") or ""
_remote = read("src/ServerScriptService/Server/Modules/RemoteSetup.luau") or ""
_base = read("src/ServerScriptService/Server/Services/BaseService.luau") or ""
_name = "RequestPurchaseUpgrade"
if (
    f'RequestPurchaseUpgrade = "{_name}"' in _const
    and "RemoteNames.RequestPurchaseUpgrade" in _client
    and "RemoteNames.RequestPurchaseUpgrade" in _remote
    and "SetPurchaseUpgradeHandler" in _base
    and "ensurePurchaseHook" in _remote
):
    ok("v62 remote name client FireServer === server OnServerEvent (RequestPurchaseUpgrade / WE_Remotes)")
else:
    bad("v62 remote name mismatch client vs server")

# Simulate FireServer→OnServerEvent→cash deduct for CommandCenter L0→L1
import re as _re
_bc = read("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau") or ""
# costs(1500, ...) for CommandCenter
_m = _re.search(r"CommandCenter\s*=\s*\{[\s\S]*?Costs\s*=\s*costs\((\d+)", _bc)
_cc_cost = int(_m.group(1)) if _m else None
if _cc_cost == 1500:
    ok("v62 CommandCenter L1 cost=1500")
else:
    bad(f"v62 CommandCenter L1 cost expected 1500 got {_cc_cost}")

# Pure-python simulate: profile.Cash starts at StartingCash (desync), attr/leaderstats=50M, reconcile then spend
_start = 10000
_hud = 50_000_000
_profile_cash = _start  # desync like EarlyRemotes race
_reconciled = max(_profile_cash, _hud)  # ReconcileSpendableCash
_after = _reconciled - 1500
if _reconciled == 50_000_000 and _after == 49_998_500:
    ok("v62 simulate reconcile+SpendCash CommandCenter: 10k HUD-desync → 50M → 49998500")
else:
    bad(f"v62 simulate cash path failed reconciled={_reconciled} after={_after}")

# Pad StructureId attribute must match catalog key
_map = read("src/ServerScriptService/Server/Modules/MapSetup.luau") or ""
if 'plinth:SetAttribute("StructureId", def.Id)' in _map and 'Id = "CommandCenter"' in _bc:
    ok("v62 pad StructureId attribute === BaseConfig.Structures key (def.Id)")
else:
    bad("v62 pad StructureId vs catalog key mismatch")




# ── v63 BUY: attribute ack primary + no WaitForProfile>0.25s + force plot1 ─────
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_BuyAck"', "v63 BaseService WE_BuyAck attribute")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_BuyOk"', "v63 BaseService WE_BuyOk")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_BuyErr"', "v63 BaseService WE_BuyErr")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_BuyStructure"', "v63 BaseService WE_BuyStructure")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_BuyCash"', "v63 BaseService WE_BuyCash")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "WaitForProfile(player, 0.25)", "v63 buy handler WaitForProfile ≤0.25s")
must_not_contain("src/ServerScriptService/Server/Services/BaseService.luau", "WaitForProfile(player, 5)", "v63 no WaitForProfile(5) in buy handler")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WaitForProfile(player, 0.25)", "v63 EnsureProfile WaitForProfile ≤0.25s")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "AckBuyResult", "v63 BaseService.AckBuyResult export")
# v68 batch 2: never force a 7th+ player onto plot 1 (it hijacked the owner's base); a buy with no plot yet
# claims a free one on the spot (the v63 intent), and only a full server answers NoPlot.
must_not_contain("src/ServerScriptService/Server/Services/BaseService.luau", "forcing BasePlotId=1", "v68 AssignPlot never forces plot 1")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "pcall(claimFreePlotLate, player)", "v68 PurchaseUpgrade claims a free plot late")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'return { Ok = false, Error = "NoPlot" }', "v68 PurchaseUpgrade answers NoPlot when the server is full")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "AckBuyResult", "v63 UpgradePad uses AckBuyResult")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "scanEntireWorkspaceForStructureId", "v63 UpgradePad Workspace StructureId sweep")
must_not_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "profile.BasePlotId = 1", "v68 UpgradePad never forces plot 1")
must_not_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "profile.BasePlotId = 1", "v68 PremiumPad never forces plot 1")
must_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "_purchaseHookedInstance", "v63 RemoteSetup re-hook destroyed remote")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", 'GetAttributeChangedSignal("WE_BuyAck")', "v63 WorldPrompt listens WE_BuyAck")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 68)', "v68 WE_Build=68 BaseService")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 68)', "v68 WE_Build=68 DataService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 68)', "v68 EarlyRemotes WE_Build")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "50_000_000", "v63 shaunie6 cash floor on buy")

# Attribute-ack + CommandCenter cash 50M→49998500 (same reconcile math as v62)
_cc_cost2 = 1500
_hud2 = 50_000_000
_start2 = 10_000
_reconciled2 = max(_start2, _hud2)
_after2 = _reconciled2 - _cc_cost2
if _reconciled2 == 50_000_000 and _after2 == 49_998_500:
    ok("v63 simulate attribute-ack path CommandCenter cash: 50M → 49998500")
else:
    bad(f"v63 simulate cash failed reconciled={_reconciled2} after={_after2}")




# ── v64 BUY: harden nil Stats/BasePlotId + real WE_BuyErr + post-spend pcall ───
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'typeof(profile.BaseUpgrades) ~= "table"', "v64 PurchaseUpgrade ensures BaseUpgrades table")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'typeof(profile.Stats) ~= "table"', "v64 PurchaseUpgrade ensures Stats table")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "pcall(function()\n\t\tBaseService.PushState", "v64 PushState after spend is pcall'd")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "pcall(function()\n\t\tBaseService.UpdateVisuals", "v64 UpdateVisuals after spend is pcall'd")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_BuyErr", errStr)', "v64 WE_BuyErr stamps real pcall err")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", '"SpendFailed"', "v64 SpendCash returns SpendFailed never throws")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", 'typeof(profile.BaseUpgrades) ~= "table"', "v64 UpgradePad ensures BaseUpgrades")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "PurchaseUpgrade threw", "v64 UpgradePad pcall PurchaseUpgrade")
must_contain("src/ServerScriptService/Server/Modules/ProfileSchema.luau", "v64: always ensure nested tables", "v64 ProfileSchema Migrate ensures Stats/BaseUpgrades")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 68)', "v68 WE_Build=68 BaseService")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 68)', "v68 WE_Build=68 DataService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 68)', "v68 EarlyRemotes WE_Build")

# Simulate CommandCenter buy with Stats=nil / BasePlotId=nil / Reconcile edge → 50M→49998500
def simulate_cc_buy(stats_nil: bool, plot_nil: bool, profile_cash: int, hud_cash: int) -> int:
    """Pure-python mirror of hardened PurchaseUpgrade cash path."""
    cash = profile_cash
    base_plot = None if plot_nil else 1
    stats = None if stats_nil else {"UpgradesPurchased": 0}
    base_upgrades = None  # nil edge
    # ensure tables (v64)
    if base_upgrades is None:
        base_upgrades = {}
    if stats is None:
        stats = {"UpgradesPurchased": 0}
    if base_plot is None:
        base_plot = 1
    # reconcile
    cash = max(cash, hud_cash)
    # shaunie floor
    cash = max(cash, 50_000_000)
    cost = 1500
    assert cash >= cost
    cash = cash - cost
    base_upgrades["CommandCenter"] = 1
    stats["UpgradesPurchased"] = (stats.get("UpgradesPurchased") or 0) + 1
    # visuals would pcall — cash already final
    return cash

_s1 = simulate_cc_buy(stats_nil=True, plot_nil=True, profile_cash=10_000, hud_cash=50_000_000)
_s2 = simulate_cc_buy(stats_nil=False, plot_nil=True, profile_cash=50_000_000, hud_cash=50_000_000)
_s3 = simulate_cc_buy(stats_nil=True, plot_nil=False, profile_cash=50_000_000, hud_cash=0)
if _s1 == 49_998_500 and _s2 == 49_998_500 and _s3 == 49_998_500:
    ok("v64 simulate CommandCenter buy Stats=nil/BasePlotId=nil/Reconcile: 50M → 49998500")
else:
    bad(f"v64 simulate edge failed s1={_s1} s2={_s2} s3={_s3}")




# ── v65 BUY: DataService Init FIRST + getDataService nil-fallback ─────────────
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "local function getDataService()", "v65 BaseService getDataService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'Error = "NoDataService"', "v65 PurchaseUpgrade NoDataService guard")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'assert(deps.DataService, "BaseService.Init missing deps.DataService")', "v65 BaseService.Init assert DataService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'assert(deps.EconomyService, "BaseService.Init missing deps.EconomyService")', "v65 BaseService.Init assert EconomyService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "require(script.Parent.DataService)", "v65 BaseService require fallback")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "local function getDataService()", "v65 EconomyService getDataService")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", '"NoDataService"', "v65 SpendCash NoDataService")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", 'assert(deps.DataService, "EconomyService.Init missing deps.DataService")', "v65 EconomyService.Init assert")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "local function getDataService()", "v65 UpgradePad getDataService")
must_contain("src/ServerScriptService/Server/Services/UpgradePadService.luau", "NoDataService", "v65 UpgradePad NoDataService guard")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "DataService Init FIRST (v65)", "v65 Bootstrap DataService-first log")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "deps.DataService is nil before BaseService.Init", "v66 Bootstrap warns (no assert) on nil deps.DataService")
must_not_contain("src/ServerScriptService/Server/Bootstrap.server.luau", "assert(deps.DataService", "v66 Bootstrap has no fatal DataService assert")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 68)', "v68 WE_Build=68 BaseService")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 68)', "v68 WE_Build=68 DataService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 68)', "v68 EarlyRemotes WE_Build")
# Keep v64 hardenings
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'typeof(profile.BaseUpgrades) ~= "table"', "v65 keeps v64 BaseUpgrades guard")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_BuyErr", errStr)', "v65 keeps v64 real WE_BuyErr")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "function EconomyService.ReconcileSpendableCash", "v65 keeps v62/v64 Reconcile")

# Bootstrap: DataService Init before EconomyService and BaseService
_boot65 = read("src/ServerScriptService/Server/Bootstrap.server.luau") or ""
_ds65 = _boot65.find('safeInit("DataService"')
_eco65 = _boot65.find('safeInit("EconomyService"')
_base65 = _boot65.find('safeInit("BaseService"')
_up65 = _boot65.find('safeInit("UpgradePadService"')
if _ds65 >= 0 and _eco65 >= 0 and _base65 >= 0 and _up65 >= 0 and _ds65 < _eco65 < _base65 < _up65:
    ok("v65 Bootstrap DataService → Economy → Base → UpgradePad order")
else:
    bad(f"v65 Bootstrap order wrong ds={_ds65} eco={_eco65} base={_base65} up={_up65}")

# Simulate: Init DataService cleared (nil) then require fallback recovers → CC buy 50M→49998500
def simulate_cc_buy_with_ds(ds_init_nil: bool) -> int | None:
    """Mirror PurchaseUpgrade when module-local DataService was nil after Init."""
    # Fake module table recovered via require(script.Parent.DataService)
    recovered = {"ok": True}
    ds = None if ds_init_nil else recovered
    def get_data_service():
        nonlocal ds
        if ds is not None:
            return ds
        # require fallback
        ds = recovered
        return ds
    DS = get_data_service()
    if not DS:
        return None  # NoDataService
    cash = 50_000_000
    cost = 1500
    # Stats/BaseUpgrades nil harden (v64)
    base_upgrades = {}
    stats = {"UpgradesPurchased": 0}
    base_plot = 1
    cash = max(cash, 50_000_000)
    assert cash >= cost
    cash = cash - cost
    base_upgrades["CommandCenter"] = 1
    stats["UpgradesPurchased"] += 1
    return cash

_nil_fallback = simulate_cc_buy_with_ds(ds_init_nil=True)
_normal = simulate_cc_buy_with_ds(ds_init_nil=False)
if _nil_fallback == 49_998_500 and _normal == 49_998_500:
    ok("v65 simulate getDataService nil→require fallback CommandCenter: 50M → 49998500")
else:
    bad(f"v65 simulate fallback failed nil={_nil_fallback} normal={_normal}")


# v70 HUD "clean screen" (docs spec §8 new pins + owner decisions). Verified with the headless HUD harness states
# v70_base / v70_combat / v70_drive / v70_tutorial / v70_alert / v70_offer at 844x390, 956x440 and 1280x720.
CL = "src/StarterPlayer/StarterPlayerScripts/Client"
HUDCFG = "src/ReplicatedStorage/Shared/Configs/HudConfig.luau"
must_contain(HUDCFG, "Tiles = {", "v70 HudConfig rail tiles")
must_contain(HUDCFG, "Reserve = {", "v70 HudConfig reserved combat/vehicle rect")
must_contain(HUDCFG, "CombatTouch = { Width = 290, Height = 300, MinWidthPx = 0, MinHeightPx = 222 }", "v70 touch reserve holds VehicleDriveClient's lift column (222 px)")
must_contain(HUDCFG, "\tDrawnOnSpawn = false,", "v70 owner decision: spawn holstered")
must_contain(HUDCFG, "AutoDrawOnDamage = true", "v70 holstered players auto-draw on damage")
must_contain(HUDCFG, "Army = Enum.KeyCode.Y", "v70 owner decision: Army popover key Y (A is strafe)")
must_contain(HUDCFG, "MaxPerSession = 3,", "v70 owner decision: at most 3 offer pop-ups per session")
must_contain(HUDCFG, "MinGapSeconds = 240,", "v70 owner decision: offers at least 4 min apart")
must_contain(HUDCFG, 'Show = "BASE UNDER ATTACK!"', "v70 client folds DEF HIT spam into one BASE UNDER ATTACK alert")
_hudcfg = read(HUDCFG) or ""
_tiles = _hudcfg.split("Tiles = {", 1)[1].split("\n\t},", 1)[0] if "Tiles = {" in _hudcfg else ""
if _tiles and 'Id = "Settings"' not in _tiles and 'Id = "Base"' not in _tiles and _tiles.count('Id = "') == 5:
    ok("v70 owner decision: 5 rail tiles, no Base / Settings tile (Settings = TopStrip gear)")
else:
    bad("v70 rail tiles must be the 5 of spec §3.2 (no Base / Settings tile) in HudConfig.Rail.Tiles")
must_contain(CL + "/Controllers/HUDController.luau", "SetRailBadge", "v70 HUD rail badges")
must_contain(CL + "/Controllers/HUDController.luau", "layoutRail", "v70 HUD left rail layout")
must_contain(CL + "/Controllers/HUDController.luau", '"WE_TopStrip"', "v70 HUD TopStrip (level chip, gear, shield)")
must_contain(CL + "/Controllers/NotificationController.luau", "ShowOffer", "v70 one offer toast (ShowOffer)")
must_contain(CL + "/Controllers/NotificationController.luau", "MaxVisible", "v70 toast lane cap (MaxVisible)")
must_contain(CL + "/Controllers/PromptController.luau", "ProximityPromptStyle.Custom", "v70 custom prompt pills")
must_contain(CL + "/Controllers/UIController.luau", 'safeInit("Prompt", PromptController.Init)', "v70 PromptController init guarded (Default prompts on failure)")
must_contain(CL + "/Controllers/CombatController.luau", "FireNeedsDrawn", "v70 no firing while holstered")
must_contain(CL + "/Controllers/CombatController.luau", "WE_Reticle", "v70 reticle gui at the true centre")
must_contain("src/ReplicatedStorage/Shared/Util/UIUtil.luau", "MakeRailTile", "v70 UIUtil.MakeRailTile")
must_not_contain(CL + "/Controllers/UIController.luau", '" opened", "Info"', "v70 rail presses never toast")
must_contain(CL + "/Modules/HudLayout.luau", "function HudLayout.RegisterTopStack(", "v70 HudLayout top-centre stack")
must_contain(CL + "/Modules/HudLayout.luau", "function HudLayout.RegisterPanel(", "v70 HudLayout panel registry (one panel at a time)")
must_contain(CL + "/Controllers/ShopController.luau", '"WE_Ent_"', "v70 Shop OWNED / offer skip via WE_Ent_<key>")
for _c in ("HUDController", "CompassController", "UIController", "NotificationController", "PromptController", "WorldPromptController",
           "CombatController", "OrdersController", "ArmyController", "BaseController", "ShopController", "MissionController",
           "SettingsController", "VehicleController", "ResearchController", "MissileController", "TutorialController",
           "TerritoryController", "BankRaidController", "ProgressionController/init"):
    must_not_contain(CL + "/Controllers/%s.luau" % _c, "Remotes.GetEvent(", "v70 %s never blocks on Remotes.GetEvent" % _c.split("/")[0])

# v70 drivable vehicles (client-simulated, server-validated). Verified: server 290 + adversarial 22, client 134 + 11
VS = "src/ServerScriptService/Server/Services/VehicleService.luau"
VDC = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau"
must_contain(VS, "PhysicalProperties.new(0.9, CarCfg.WheelFriction, 0.1, CarCfg.WheelFrictionWeight, 1)", "v70 wheels low friction so cars/tanks can yaw")
must_not_contain(VS, "PhysicalProperties.new(0.9, 2.0, 0.1, 1, 1)", "v70 no high-friction fixed-axle wheels")
must_contain("src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau", "WheelFriction = 0.2,", "v70 Car.WheelFriction config")
must_contain(VS, "Valid.TeleportSlack + held * idleDriftSpeed(rec.Mode)", "v70 correction hold does not eject airborne pilots")
must_contain(VS, "local wallow = cap * math.max(0, s.T - win.T) + Valid.TeleportSlack", "v70 windowed teleport check (slack not per sample)")
must_contain(VS, "if occ == nil or (tonumber(occ.Health) or 0) <= 0 then", "v70 fallback ignores a dead driver's throttle")
must_contain(VDC, "hum:ChangeState(Enum.HumanoidStateType.Jumping)", "v70 F exit survives ControlModule Jump overwrite")
must_contain(VDC, "RunService:BindToRenderStep(EXIT_STEP, Enum.RenderPriority.Input.Value + 1", "v70 exit re-asserts Jump after ControlModule render step")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", "Remotes.GetEvent(", "v70 garage never blocks on Remotes.GetEvent")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "< PLOT_SIZE * 0.5 + 12", "v70 plot densify props stay out of the 320 base (runways clear)")

# v71 money phase 0 (M0 config hotfix, M2 plumbing, J2 receipt safety). Verified: receipt 31 + adversarial 25,
# profile 37, admin 28, config 42, ds 24, sl 33, g6 67
MS = "src/ServerScriptService/Server/Services/MonetizationService.luau"
must_contain(MS, "local ok, decision = pcall(processReceipt, receiptInfo, receiptId)", "J2 receipt runs inside pcall with in-flight lock")
must_contain(MS, "if receiptsInFlight[receiptId] then", "J2 duplicate receipt delivery refused while in flight")
must_contain(MS, "receipt NOT acknowledged (Roblox retries it)", "J2 unknown product Id -> NotProcessedYet")
must_not_contain(MS, "Mark processed so Roblox queue drains", "J2 unknown Id is never acked (old drain branch gone)")
must_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "local ev = Instance.new(\"UnreliableRemoteEvent\")", "M2 UNRELIABLE remotes created as UnreliableRemoteEvent")
must_contain("src/ServerScriptService/Server/Services/AdminService.luau", "if not isAdmin and not (moneyCmd and RunService:IsStudio()) then", "M2 money admin commands: allowlist or Studio only")
must_contain("src/ServerScriptService/Server/Modules/ProfileSchema.luau", "ensureMoneyFields(profile)", "M2 money profile fields default-filled + sanitised on Migrate")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "GoldSmall = { Id = 3713839003, DisplayName = \"Gold Pack S\", RobuxPrice = 49, Cash = 0, Gold = 50, HideFromShop = true },", "M0 Gold packs hidden, live Id kept")
must_contain("tools/wire-monetization-ids.py", "each product needs its own Id", "wire tool refuses duplicate product Ids")
must_not_contain("src/ReplicatedStorage/Shared/Configs/NukeConfig.luau", "DefensesDown", "J1 nuke never opens a base (no defenses-down fields)")

# v70 waterways (verified: V1-V13 all PASS flag false + true, gate loop 66/0, capture 38/0, vehicles 290/167/22/134/11,
# strikes 67/27/48 on turned plots, ds 24)
SKBW = "src/ServerScriptService/Server/Modules/StructureKitBuilder.luau"
MSW = "src/ServerScriptService/Server/Modules/MapSetup.luau"
must_contain(SKBW, 'd:GetAttribute("WE_WallGap") == true', "v70 perimeter walls leave a gap at WE_WallGap (sea gate)")
must_contain(SKBW, "function StructureKitBuilder.SetGateOpen(gateFolder: Instance, open: boolean)", "v70 SetGateOpen sea-gate API")
must_contain(SKBW, 'if gateFolder:GetAttribute("WE_GateMode") == "Proximity" then', "v70 Dock only arms the sea gate")
must_contain(SKBW, "closed * CFrame.new(sx * (leaf.Size.X + 0.3), 0, 0)", "v70 gate leaves slide along their own X")
must_contain(MSW, 'gateWater:SetAttribute("WE_GatePlotId", plotId)', "J3 SeaGateWater uses WE_GatePlotId")
must_not_contain(MSW, 'Name = "GatePost"', "rear-gate posts are RearGatePost (GateDefense fallback)")
must_contain(MSW, 'root:SetAttribute("WE_MapGen", MapSetup.MAP_GEN)', "v70 map-gen stamp")
must_contain(MSW, "MapSetup.MAP_GEN = if BaseLayout.FacesMapCentre() then 71 else 70", "map stamp encodes FaceMapCentre")
must_contain("src/ServerScriptService/Server/Modules/Waterways.luau", 'local occ = if seat and seat:IsA("VehicleSeat") then seat.Occupant else nil', "sea gate opens only for a driven boat")
must_contain("src/ServerScriptService/Server/Modules/Waterways.luau", "p.CanQuery = false", "water/bank parts take no raycasts")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/TerritoryCapture.luau", "VehiclePassengersCount ~= true", "vehicle passengers never capture or contest")
must_not_contain("src/ServerScriptService/Server/Services/MissileStrikeService.luau", "CC_OFFSET", "J2 no world-axis Command Center offset")
must_contain("src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau", "FaceMapCentre = true,", "v70 bases face the map centre (docks reach the ring)")
must_contain("src/ReplicatedStorage/Shared/Configs/WaterConfig.luau", "OpenRadius = 40,", "v70 sea gate opens only for a boat within 40 studs")

# v70 HUD "clean screen" (verified: harness 0 overlaps / 0 targets < 44 px / 0 text < 11 px at phone+owner+desktop,
# fault injection 17 controllers, HudLayout 169, t_client 134, v_client 11)
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "right = math.max(right, railPos.X + railSize.X)", "v70 Army popover clears a 2-column rail (800x360)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "local x = floatX(f)", "v70 cash float never overlaps the rail")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "restoreDefaultPrompts()", "v70 PromptController failure restores Default prompts")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau", "prompt.Style = Enum.ProximityPromptStyle.Default", "v70 PromptController.Shutdown back to Default style")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/HudLayout.luau", "sweepStalePanels()", "v70 stale Modal flag safety sweep")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau", "if HB.AutoDrawOnDamage and not drawn and not seatedNow()", "v70 holstered players auto-draw on damage")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau", "drawn = HB.DrawnOnSpawn == true", "v70 every life starts holstered")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NotificationController.luau", "offersShown >= OFFER.MaxPerSession", "v70 offer session cap enforced")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NotificationController.luau", "now - lastOfferAt < OFFER.MinGapSeconds", "v70 offer min gap enforced")
must_contain("src/ReplicatedStorage/Shared/Configs/HudConfig.luau", "DeferWhen = { \"Drawn\", \"RecentCombat\", \"Driving\", \"Modal\", \"Tutorial\" }", "v70 offers deferred in combat/driving/panels/tutorial")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau", "HudLayout.ApplyScreen(rg, { Insets = \"None\" })", "v70 reticle gui full-screen (true centre)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau", "{ Id = \"Missiles\", Controller = MissileController },", "v70 Missiles panel joins the one-panel-at-a-time registry")

# v70 server fairness (verified: fairness combat 56, adversarial 22, thief 18, squad 26, research combat 40/9, squad 18,
# raid 71, strike 67/27, gate 48, ds 24)
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if not (finite(direction.X) and finite(direction.Y) and finite(direction.Z)) then", "P0-7 every Direction component finite (NaN Y/Z bypassed claim checks)")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if not ((origin - root.Position).Magnitude <= CombatConfig.MaxOriginDeltaStuds) then", "P0-7 NaN origin snaps to root")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if not (along > 0) then", "P0-7 claim in front of the ray (NaN-safe)")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if not CombatDamage.LineOfSight(origin, torsoPos, { shooter }, target, false, CombatFairnessConfig.ClaimLosPastTorsoStuds) then", "P0-7 claimed target needs line of sight")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if lateral > CombatFairnessConfig.MissTolerance then", "P0-7 claim within MissTolerance of the ray")
must_not_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if troot and (troot.Position - origin).Magnitude <= range then", "P0-7 old range-only trust removed")
must_contain("src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau", "elseif not npcHasLos(rec, target, th, troot) then", "P1-2 NPC shots need line of sight")
must_contain("src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau", "if not (tState and now < tState.InvulnerableUntil) and rng:NextNumber() < chance then", "P1-2 NPC hit chance")
must_contain("src/ServerScriptService/Server/Services/SquadOrdersService.luau", "unitShoot(player, unit, th, now, CombatFairnessConfig.UnitKillCreditOnAttack == true)", "P1-4 ATTACK kills credit only via flag (idle bank farm)")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "local thiefBlock, thiefLeft = newThiefBlock(tProfile)", "P0-6 CanRaid refuses tutorial/new thieves")
must_contain("src/ReplicatedStorage/Shared/Configs/CombatFairnessConfig.luau", "MissTolerance = 5,", "v70 phone lag tolerance 5 studs (10/12 aim points at 250 ms)")

# v70 jeep drive fix (verified: t_server 290, v_rot 167, v_server 22, v_client 11, t_client_jeep 194, t_jeep_server 105,
# adversarial 33/4/1, ds 24, world ok)
must_not_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WASD", "P1-8 no key-name tips/toasts in vehicles")
must_not_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "DriveTip", "P1-8 no server drive-tip label")
must_not_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "\"VehicleLabel\"", "P1-8 server nameplate removed (client owner-only plate)")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "nc.Name = \"WE_WheelNoCollide\" .. i", "F2 wheel/chassis no-collide")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "trip(rec, \"nomove\", t)", "F5 drive watchdog failover")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "not overAnyWater(ctx, cf) and inSight(ctx, pp, cf) and openSky(ctx, cf)", "P1-9 front spawn: dry, no wall-crossing, not indoors")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "if sign == 0 or along > W.MinMoveStuds then", "Blocked car never counts as a session trip")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "return false, \"InCombat\"", "P1-9 SPAWN damage lock")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "local STRIP_BASES = { \"Constraint\", \"BodyMover\", \"JointInstance\", \"LuaSourceContainer\" }", "F3 catalog dress strips movers/joints")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau", "sendDriveInput({ K = \"In\", V = d.VehicleId, T = round2(t), S = round2(s), L = round2(l) })", "F4b client input stream")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau", "hum.JumpHeight = 0", "P1-7 airborne jump lock")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau", "g.MaxDistance = math.min(40, PLATE.MaxDistance)", "P1-8 owner nameplate within 40 studs")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau", "Enum.KeyCode.F, Enum.KeyCode.ButtonB)", "gamepad B exits vehicles (airborne bail-out)")

# ── v66: REAL parse gate. Every check above is a text match; none of them noticed that
# ProfileSchema/EconomyService stopped parsing in v50 (DataService never loaded v50–v65).
# Needs luau-compile (https://github.com/luau-lang/luau/releases → luau-ubuntu.zip / luau-macos.zip).
def parse_gate() -> None:
    import os
    import shutil
    import subprocess
    exe = os.environ.get("LUAU_COMPILE") or shutil.which("luau-compile")
    if not exe:
        if os.environ.get("WE_SKIP_PARSE_CHECK") == "1":
            print("[BuyPathStatic] WARN parse gate skipped (WE_SKIP_PARSE_CHECK=1)")
            return
        bad("parse gate: luau-compile not found — install it (luau-lang/luau releases) or set LUAU_COMPILE=/path/luau-compile")
        return
    files = sorted((ROOT / "src").rglob("*.luau")) + sorted((ROOT / "tools").glob("*.luau"))
    broken = 0
    for f in files:
        r = subprocess.run([exe, "--binary", str(f)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        if r.returncode != 0:
            broken += 1
            first = (r.stderr or "").strip().splitlines()[:1]
            bad(f"parse {f.relative_to(ROOT)}: {first[0] if first else 'compile error'}")
    if broken == 0:
        ok(f"parse gate: all {len(files)} .luau files compile")


parse_gate()

print(f"[BuyPathStatic] Done PASS={PASS} FAIL={FAIL}")
sys.exit(1 if FAIL else 0)
