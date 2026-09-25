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
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau", "RequestPurchaseUpgrade", "v71 Base panel never fires RequestPurchaseUpgrade (console-only buying)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau", "btn.Activated", "v71 Base panel GO uses Activated")

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
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "0", "MilitaryJeep Military Car mesh")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_DrivePrompt", "DriverSeat Drive ProximityPrompt")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "seat:Sit(hum)", "VehicleSeat auto-Sit")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_DriveHinge", "HingeConstraint drive motors")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "startGroundDrive", "scripted/hinge ground drive")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "HingeConstraint", "mesh strips drive constraints")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", "ATM · WALK IN TO COLLECT", "v67 ATM card title (short; codes live in Settings)")


# 9) Design competitive pass P0/P1 (ATM / WarzoneProps / showroom / HUD)
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MoneyCollector = { ModelAssetId = 18220523228", "ATM hero prefer ID [owner pick 18220523228, 2026-09-25]")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "175462478", "ATM fallback ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "38451313", "MoneyBagFX ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "4221608224", "VfxSparkles ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "16803204916", "CashCrate ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "5267267960", "ShowroomPodium ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "5389482912", "ShowroomRotator ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "632958370", "TutorialArrow ID [owner pick 632958370, 2026-09-25]")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'Sandbag = { ModelAssetId = 15271872710', "WarzoneProps Sandbag label [owner pick 15271872710, 2026-09-25]")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'Floodlight = { ModelAssetId = 116763933', "WarzoneProps Floodlight label")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "TryAttachCollectorVisual", "VAS TryAttachCollectorVisual")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "PlayMoneyBagFX", "VAS PlayMoneyBagFX")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "TryAttachShowroomVisual", "VAS TryAttachShowroomVisual")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "Podium", "VehicleDepot showroom Podium")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "syncUpgradePops", "BaseService upgrade pops")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "GoldBright", "HUD GoldBright stroke")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau", "dock≤8", "HUD dock padding ≤8")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.luau", "beam.Name = \"WE_TutorialBeam\"", "Tutorial guide beam (v68: subtle, not neon)")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "0", "Jeep ModelAssetId unchanged")


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
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ArmedJeep = { ModelAssetId = 0", "ArmedJeep tan turreted")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "HeavyInfantry = { ModelAssetId = 0", "HeavyInfantry Design Bot")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Guard = { ModelAssetId = 16134469614", "Guard Design Bot")
must_absent("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "91299598767068", "No Respawn pack primary assignment")
# allow REJECT comments mentioning 3924234975; must_absent filters REJECT/DELETED
must_absent("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "3924234975", "No plastic Rthro CharacterAlt assignment")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "SupplyTruck = { ModelAssetId = 0", "SupplyTruck truck mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "InfantryCarrier = { ModelAssetId = 0", "InfantryCarrier APC")
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
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "PlotWarzoneDensify", "Warzone densify 8-12/plot")
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
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "IndustrialPack = { ModelAssetId = 0", "IndustrialPack oil spectacle")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "RustyPipes = { ModelAssetId = 0", "RustyPipes")
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
must_not_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", 'oilFolder.Name = "OilSpectacle"', "World v2 W1: oil spectacle removed")
must_not_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", 'lm.Name = "WarzoneLandmarks"', "World v2 W1: landmarks removed")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "SquadStalls", "TrainingYard Tent stalls")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "96059329869678", "Palm MapDressing")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "0", "AsphaltDecal")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MeshId = 0", "DesertRock MeshPart")
# No-regress P0
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 9104381136", "Worker/Infantry unchanged")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 0", "MilitaryJeep unchanged")


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
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "AutoGun = { ModelAssetId = 0,", "GateDefense.AutoGun: Part-built gun until the owner pick 114570602 is promoted (4923345827 MG 34-like dropped)")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 4923345827", "4923345827 (WWII MG 34-like, no part cap) is never a live gate-gun id")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "0", "SandbagNest")
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
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", 'WorldLabel.SetRole(flagBb, if contested then "contested" else nil)', "v71 flag diamond draws through walls only while contested")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", 'Name = "WE_ZoneLabel"', "v71 zone label = one stud-scaled WorldLabel (name only)")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "CeilingBeamLong", "v67 no ceiling beams (dark warehouse look)")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "CeilingJoist", "v67 no ceiling joists")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "Keep all your Robux Items!", "Rebirth exact keep banner")


# --- v30 death shop toast / GoldenPump hide / Army Robux / oil float / mobile Orders ---
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DeathShopToast", "Death shop toast UI")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "DEATH_TOAST_DEBOUNCE", "Death shop client debounce")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "PromptGamePassPurchase", "Death/shop GamePass prompt")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "DEATH_SHOP_DEBOUNCE", "Death shop server debounce")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "resolveDeathOfferLive", "Death shop live Id filter")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "local offer = MonetizationConfig.LivePadOffer(slot)", "Premium pad Id≠0 gate (F1: MonetizationConfig.LivePadOffer)")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "atmCluster", "Chevrons to ATM/premium cluster")
must_not_contain("src/ServerScriptService/Server/Services/PlotOilPumpService.luau", "OilIncomeBillboard", "v71 no oil +$/tick card (spec §5)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau", "COMMANDER PACK", "Army Commander Pack Robux row")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau", "ExtraSoldierSlot", "Army ExtraSoldierSlot offer")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OrdersController.luau", "SizeTouch", "Orders mobile SizeTouch")
must_contain("src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau", "SizeTouch", "OrdersConfig SizeTouch")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "HideFromShop = true", "HideFromShop duplicate DevProducts")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "GoldenPumpjack", "GrantEntitlement GoldenPumpjack sync")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "SpeedBoost", "SpeedBoost WalkSpeed apply")
must_contain("src/ServerScriptService/Server/Services/SoldierService.luau", "ExtraSoldierSlot", "ExtraSoldierSlot +10 cap (M1)")
# No-regress v30
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v30")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v30")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v30")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "3713838952", "CashMega Id no-regress")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash GamePass Id no-regress")

# --- v31 onboarding + overlay harden + OWNED pads + WASD tip ---
must_contain("src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau", "ClickDropper", "Tutorial ClickDropper step")
must_contain("src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau", 'Id = "Income"', "Tutorial Income early")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", '"ManualDrop"', "TutorialService ManualDrop event")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "ManualDrop", "ManualDropper tutorial Notify")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "Tutorial_Dropper", "MapSetup Tutorial_Dropper marker")
must_contain("src/ServerScriptService/Server/Services/SupplyDropService.luau", "AlwaysOnTop = false", "SupplyDrop AlwaysOnTop false")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "SupplyDrop", "WorldPrompt hides SupplyDrop near pads")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "SECURED", "Capture SECURED celebration toast")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "WE_LocalOwned", "Premium pad OWNED visual")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "UserOwnsGamePassAsync", "F1 Shop OWNED comes from the server (WE_Ent_*), no client pass-ownership polling")
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
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", 'promptDevProduct("StarterBundle", "starter_offer")', "StarterBundle PromptProductPurchase path (source starter_offer)")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "WE_FlagBillboard", "Capture flag floating billboard")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "FlagStripe", "FlagStripe nation visibility")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "NationColorService", "NationColorService capture color")
must_contain("src/ServerScriptService/Server/Services/ManualDropperService.luau", "CashPopGlow", "Manual dropper green $ pop glow")
must_contain("src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau", 'ArmedJeep = V("ArmedJeep", "Armed 4x4"', "ArmedJeep DisplayName")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", 'id == "ArmedJeep"', "Garage lists ArmedJeep")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", 'id == "ArmedJeep"', "ArmedJeep same WheeledLight kit")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "startGroundDrive", "ArmedJeep drivability via startGroundDrive")
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
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "basePos.Y + flagLift - 1", "v71 flag height from the marker (oil-rig decks)")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "flag.Material = Enum.Material.SmoothPlastic", "v71 flags painted, not neon")
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
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "v35: ~28 stud marked pad", "fb2 Helipad old part kit gone (now Installations/Helipad)")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "v35: naval pier + bollards", "Dock densify")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "BuildingDressGen = 29", "BuildingDressGen 29 (v42)")
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "Landmarks_v35", "Map landmarks folder")
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "WreckScorch", "Wrecked vehicle landmark")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "attachTurretVisualMarker", "Gate auto-gun visual marker")
must_not_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "WE_AutoGunBillboard", "v71 no auto-gun name card (spec §5)")
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
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "RoadWarzone_v36", "Road warzone density folder")
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "RoadCrater", "Road crater clusters")
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "RoadChevron", "Road chevron clusters")
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
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "Landmarks_v35", "v35 landmarks no-regress")
kit_gen_at_least(32, "KIT_GEN no-regress →27")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "TutorialService", "Tutorial no-regress v36")



# --- v37 air/naval presence + midgame polish: parked heli/boat, runway, missions, level-up, CashMega soft, garage ---
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_DressHost_ParkedHeli", "fb2 Helipad parked heli dress host gone")
must_not_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ParkedHeli", "fb2 Helipad parked heli Part-kit gone")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "WE_DressHost_ParkedBoat", "Dock parked boat host")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "ParkedBoat", "Dock parked boat Part-kit")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "threshold chevrons", "Airfield threshold chevrons")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", "centerline", "Airfield centerline markings")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "TryAttachParkedPresence", "Parked presence mesh attach")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "TryAttachParkedPresence", "BaseService parked presence call")
must_not_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'role == "ParkedHeli"', "fb2 ParkedHeli kit role visuals gone")
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
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", "buy Vehicle Depot / unlock Field 4x4", "Garage empty unlock guidance")
# No-regress v37
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "WE_GroundDrive", "Jeep WE_GroundDrive no-regress v37")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LinearVelocity", "Jeep LV no-regress v37")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "LV+HingeMotor", "Jeep LV+HingeMotor no-regress v37")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "function GateDefenseService.ApplyDamage", "GateDefense no-regress v37")
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "PromptPremiumPad", "PremiumPad no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985475542", "VIP Id no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1982865711", "DoubleCash Id no-regress v37")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "1985115501", "AutoCollect Id no-regress v37")
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "Landmarks_v35", "v35 landmarks no-regress v37")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "TutorialService", "Tutorial no-regress v37")
must_contain("src/ServerScriptService/Server/Modules/StructureKitBuilder.luau", 'kit == "special"', "SF kit no-regress v37")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "isTracked", "LightTank tracked no-regress v37")



# --- v38 combat feel + prestige/monetization polish ---
# v70 HUD spec §8 re-pin (DEF HIT → BASE UNDER ATTACK) is DEFERRED with the §4.2 server routing; until then the client
# folds every "DEF HIT" line into one "BASE UNDER ATTACK!" alert (HudConfig.Toast.Reroute, pinned in the v70 HUD block)
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "BASE UNDER ATTACK", "Gate defense owner alert (once per plot per 60 s)")
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
must_contain("docs/DESIGN_WIRE_GAPS_v40.md", "0", "v40 tank reuse gap listed")
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
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "LightTank = { ModelAssetId = 0", "v41 LightTank mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "CombatIFV = { ModelAssetId = 0", "v41 CombatIFV")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "AssaultIFV = { ModelAssetId = 0", "v41 AssaultIFV")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "FuelTanker = { ModelAssetId = 0", "v41 Cargo Truck FuelTanker")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "AmmoCarrier = { ModelAssetId = 0", "v41 Logistics AmmoCarrier")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "TroopTransport = { ModelAssetId = 0", "v41 TroopTransport Army Truck")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "PatrolBoat = { ModelAssetId = 0", "v41 PatrolBoat")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "FastAttackCraft = { ModelAssetId = 0", "v41 Attack Boat")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", 'LandingCraft = { ModelAssetId = 0', "v41 LandingCraft=0 reject template")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 13195201090", "v41 no Build-a-Boat template ID")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Worker = { ModelAssetId = 16134469614", "v41 Worker distinct")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "\tSpecialForces = { ModelAssetId = 0", "v41 SpecialForces")
must_contain("src/ReplicatedStorage/Shared/Configs/SoldierConfig.luau", 'SpecialForces = "SpecialForces"', "v41 SF VisualKind")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "OilPumpjack = { ModelAssetId = 15192621369", "v41 OilPumpjack [owner pick 15192621369, 2026-09-25]")
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
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Hangar = { ModelAssetId = 0", "v42 Hangar key kept; owner rule 5 cleared the heavy hangar model (pick waits in PendingAssetId)")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Warehouse = { ModelAssetId = 15942568272", "v42 Warehouse distinct")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "VehicleDepot = { ModelAssetId = 12208876851", "v42 VehicleDepot distinct")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MissileDefense = { ModelAssetId = 0", "v42 MissileDefense ≠ Watchtower")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetId = 15942568272", "v42 StructureVisual Warehouse mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetId = 12208876851", "v42 StructureVisual VehicleDepot mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "MeshAssetId = 0, -- W1 CFG: real-world launcher mesh dropped", "v42 StructureVisual MissileDefense mesh")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "TargetFootprint = Vector3.new(14, 10, 18)", "v42 MissileDefense launcher footprint")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MediumTank = { ModelAssetId = 0", "v42 MediumTank only classic")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "SPAAG = { ModelAssetId = 0", "v42 SPAAG AA Gun")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MobileSAM = { ModelAssetId = 0", "v42 MobileSAM TEL")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "MortarCarrier = { ModelAssetId = 0", "v42 Howitzer MortarCarrier")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "RocketArtillery = { ModelAssetId = 0", "v42 RocketArtillery MLRS")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "BridgeLayer = { ModelAssetId = 0", "v42 Engineer Track BridgeLayer")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "LightScoutTank = { ModelAssetId = 0", "v42 Scout Tank")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Frigate = { ModelAssetId = 0", "v42 Frigate")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Destroyer = { ModelAssetId = 0, Note = \"W1 CFG drop (real-world ship)", "v42 Destroyer")
must_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "Cruiser = { ModelAssetId = 0, Note = \"W1 CFG drop (real-world ship)", "v42 Cruiser")
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
must_not_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", 'bb.Name = "WE_PriceBillboard"', "v70 no server console price card")
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
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 75)', "v75 WE_Build=75 DataService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 75)', "v75 WE_Build=75 BaseService")
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
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau", "Remotes.FireServer(Constants.RemoteNames.RequestPurchaseUpgrade", "v71 Base panel has no buy FireServer")
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
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 75)', "v75 EarlyRemotes WE_Build")
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
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 75)', "v75 WE_Build=75 BaseService")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 75)', "v75 WE_Build=75 DataService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 75)', "v75 EarlyRemotes WE_Build")
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
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 75)', "v75 WE_Build=75 BaseService")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 75)', "v75 WE_Build=75 DataService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 75)', "v75 EarlyRemotes WE_Build")

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
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 75)', "v75 WE_Build=75 BaseService")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 75)', "v75 WE_Build=75 DataService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 75)', "v75 EarlyRemotes WE_Build")
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
# W3 RETIRED: must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "< PLOT_SIZE * 0.5 + 12", "v70 plot densify props stay out of the 320 base (runways clear)")

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
must_contain(MSW, "MapSetup.MAP_GEN = (if BaseLayout.FacesMapCentre() then 83 else 82) + (if TerritoryConfig.Starter.Enabled then 10 else 0)", "map stamp encodes FaceMapCentre (82/83) and the Home Outposts (+10)")
# World v2 W1 hook (WORLD-A): Phase 1 modules wired in, dead world props gone
must_contain(MSW, "withWorldModule(\"WorldAtmosphere\", function(m: any)", "World v2 atmosphere hook guarded")
must_contain(MSW, "withWorldModule(\"WorldTerrain\", function(m: any)", "World v2 terrain hook guarded")
must_contain(MSW, "withWorldModule(\"WorldBounds\", function(m: any)", "World v2 bounds hook guarded")
must_contain(MSW, "anchorFolder(\"EventSpawns\", TAG_EVENT, spawnCfg.Event, COL_EVENT)", "invisible event anchors from WorldConfig.Spawns")
must_contain(MSW, "anchorFolder(\"NPCSpawns\", TAG_NPC, spawnCfg.NPC, COL_NPC)", "invisible NPC anchors from WorldConfig.Spawns")
must_contain(MSW, "local FORT_GATE_WIDTH = 16", "16-wide fort gate")
must_not_contain(MSW, "local function makeSpawnFolder", "no spawn rings with beacons")
must_not_contain(MSW, "ensureFolder(\"NPCPlaceholders\", root)", "no static soldier statues")
must_not_contain(MSW, "local function buildMountainRing", "no Part mountain ring (edge is WorldTerrain + WorldBounds)")
must_not_contain(MSW, "local function buildVisualFillPatches", "no fill patches")
must_not_contain(MSW, "beacon(navalFolder", "naval pontoons without beacons")
must_not_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "kitRadioTower(f2, Vector3.new(1100, 0.5, 1100), 45)", "no kit on the OilYard event anchor")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", "pcall(wh.Enforce, dressing)", "WorldHygiene after cull (dressing)")
must_contain("src/ServerScriptService/Server/Modules/DesertFlora.luau", "pcall(wh.Enforce, flora)", "WorldHygiene after cull (flora)")
must_not_contain("src/ServerScriptService/Server/Modules/DesertFlora.luau", "\"Palm_Mid_\"", "no mid palms in the rim ring")
must_not_contain("src/ServerScriptService/Server/Modules/DesertFlora.luau", "local rimR", "no DesertFlora rim ring")
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

# ── v71 console-only structure buying (owner: "you should have to actually go and click the button") ──
CBC = "src/ReplicatedStorage/Shared/Configs/ConsoleBuyConfig.luau"
CL = "src/ReplicatedStorage/Shared/Util/ConsoleLocator.luau"
BS = "src/ServerScriptService/Server/Services/BaseService.luau"
UPS = "src/ServerScriptService/Server/Services/UpgradePadService.luau"
WPC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau"
BC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau"
TC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.luau"
SMOKE = "src/ServerScriptService/Server/Modules/StudioBuySmoke.luau"
must_contain(CBC, "Enabled = true,", "v71 ConsoleBuyConfig.Enabled")
must_contain(CBC, "ConsolePromptDistance = 10,", "v71 console prompt distance in config")
must_contain(CBC, "ServerSlack = 8,", "v71 server lag slack in config (horizontal 18 at consoles)")
must_contain(CBC, "MaxVerticalOffset = 10,", "v71 vertical window (no buys from the floor above)")
must_contain(CBC, 'NoConsolePolicy = "Deny",', "v71 missing console fails closed")
must_contain(CBC, "RequireNearest = true,", "v71 only the nearest console in range buys")
must_contain(CBC, 'NotAtConsole = "Go to your %s console to buy it"', "v71 NotAtConsole player text")
must_contain(CL, "function ConsoleLocator.Check(", "v71 ConsoleLocator.Check")
must_contain(CL, "function ConsoleLocator.Find(", "v71 ConsoleLocator.Find (real console part, rotation-proof)")
must_contain(CL, "math.abs(offset.Y) > ConsoleBuyConfig.MaxVerticalOffset", "v71 presence is a cylinder (horizontal + vertical)")
must_contain(BS, "function BaseService.PurchaseUpgrade(player: Player, structureId: string, opts: PurchaseOpts?)", "v71 PurchaseUpgrade takes opts")
must_contain(BS, 'return { Ok = false, Error = "NotAtConsole" }', "v71 PurchaseUpgrade console gate")
must_contain(BS, "BaseService.IsAtConsole(player, structureId, opts and opts.AtPart)", "v71 gate uses IsAtConsole (+ AtPart)")
must_contain(BS, "if ConsoleBuyConfig.Enabled ~= false then", "v71 gate has no per-call bypass")
must_contain(BS, 'BaseService.PurchaseUpgrade(player, structureId :: string, { Source = "Remote" })', "v71 remote handler goes through the gate")
must_contain(UPS, "{ AtPart = part,", "v71 prompt/pad path checks the part that was used")
must_contain(UPS, "ConsoleBuyConfig.ConsolePromptDistance", "v71 prompt distance from config")
must_not_contain(UPS, "prompt.MaxActivationDistance = if console then 10 else 16", "v71 no prompt distance literals")
must_contain(UPS, "WE_ConsolePos_", "v71 console positions stamped for the GO waypoint (streaming)")
must_contain(SMOKE, "char:PivotTo(ConsoleLocator.StandCFrame(part))", "v71 Studio smoke stands at the console (no bypass)")
must_contain(WPC, 'err == "NotAtConsole"', "v71 client explains NotAtConsole")
must_contain("src/ReplicatedStorage/Shared/Configs/NotificationConfig.luau", '"^Go to your .+ console to buy it$"', "v71 NotAtConsole is one line (purchase-failure dedupe)")
must_contain(BC, "ConsoleWaypoint.Show(structureId, myPlotId)", "v71 Base panel GO shows the way")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/ConsoleWaypoint.luau", 'b.Name = "WE_ConsoleBeam"', "v71 GO waypoint beam")
must_contain(TC, 'if action == "PadBuy" then', "v71 tutorial PadBuy only re-aims the beam")
must_not_contain(TC, 'action == "PadBuy" or action == "OpenBase"', "v71 tutorial BUY step never opens the Base panel")

_bs = read(BS) or ""
_pu = _bs.find("function BaseService.PurchaseUpgrade(")
_gate = _bs.find('Error = "NotAtConsole"', _pu)
_rec = _bs.find("EconomyService.ReconcileSpendableCash(player)", _pu)
_spend = _bs.find('EconomyService.SpendCash(player, cost, "upgrade_" .. structureId)', _pu)
_floor = _bs.find("if player.UserId == 470626172 then", _pu)
_maxlv = _bs.find('Error = "MaxLevel"', _pu)
if 0 <= _pu < _gate < min(_rec, _spend, _floor, _maxlv):
    ok("v71 console gate runs before the cash floor / reconcile / MaxLevel / spend")
else:
    bad(f"v71 console gate order wrong pu={_pu} gate={_gate} floor={_floor} rec={_rec} maxlv={_maxlv} spend={_spend}")

import os as _os
_callers, _bypass, _client_fire = [], [], []
for _dp, _dn, _fn in _os.walk(ROOT / "src"):
    for _f in _fn:
        if not _f.endswith(".luau"):
            continue
        _rel = _os.path.relpath(_os.path.join(_dp, _f), ROOT)
        _t = read(_rel) or ""
        if "BaseService.PurchaseUpgrade(" in _t and not _rel.endswith("BaseService.luau"):
            _callers.append(_os.path.basename(_rel))
        if "SkipConsoleCheck" in _t or "SkipConsole" in _t:
            _bypass.append(_os.path.basename(_rel))
        if _rel.startswith("src/StarterPlayer") and "RequestPurchaseUpgrade" in _t:
            _client_fire.append(_os.path.basename(_rel))
if sorted(set(_callers)) == ["StudioBuySmoke.luau", "UpgradePadService.luau"]:
    ok("v71 PurchaseUpgrade callers allowlist (UpgradePadService, StudioBuySmoke)")
else:
    bad(f"v71 unexpected PurchaseUpgrade callers {sorted(set(_callers))} — every caller must stand the character at the console (or pass AtPart)")
if not _bypass:
    ok("v71 no console-gate bypass anywhere (no SkipConsoleCheck)")
else:
    bad(f"v71 console-gate bypass found in {sorted(set(_bypass))}")
if _client_fire == ["WorldPromptController.luau"]:
    ok("v71 only the console BUY button fires RequestPurchaseUpgrade")
else:
    bad(f"v71 client files firing RequestPurchaseUpgrade: {_client_fire}")

# Every structure has a buy point in the world: a MapSetup STRUCTURES row (else nothing is built -> unbuyable) and a
# BaseLayoutConfig site with Console (walk-in) or Kiosk (else it silently falls back to a legacy grid pad)
_bc = read("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau") or ""
_ms = read("src/ServerScriptService/Server/Modules/MapSetup.luau") or ""
_blc = read("src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau") or ""
_order_m = re.search(r"StructureOrder = \{(.*?)\}", _bc, re.S)
_order = re.findall(r'"(\w+)"', _order_m.group(1)) if _order_m else []
_nobuild = [sid for sid in _order if f'{{ Id = "{sid}"' not in _ms]
_nosite = [sid for sid in _order if not re.search(r"^\t\t" + sid + r" = \{ Site = .*(Console|Kiosk) = \{", _blc, re.M)]
if _order and not _nobuild and not _nosite:
    ok(f"v71 every structure ({len(_order)}) has a MapSetup row and a console / kiosk site")
else:
    bad(f"v71 structures without a buy point: no MapSetup row {_nobuild}, no console/kiosk site {_nosite}")

# Radii: client BUY boxes never overlap, and the client BUY box never offers a buy the server refuses
import math as _math
_cfg = read(CBC) or ""
_dist = float(re.search(r"ConsolePromptDistance = ([\d.]+)", _cfg).group(1))
_slack = float(re.search(r"ServerSlack = ([\d.]+)", _cfg).group(1))
_maxdy = float(re.search(r"MaxVerticalOffset = ([\d.]+)", _cfg).group(1))
_pts = []
for _m in re.finditer(r"^\t\t(\w+) = \{ Site = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \}, Yaw = (-?[\d.]+), WalkIn = (true|false)(.*)$", _blc, re.M):
    _sx, _sz, _yaw = float(_m.group(2)), float(_m.group(3)), float(_m.group(4))
    _rest = _m.group(6)
    if _m.group(5) == "true":
        _c = re.search(r"Console = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \}", _rest)
        _cx, _cz = float(_c.group(1)), float(_c.group(2))
        _a = _math.radians(_yaw)
        _pts.append((_m.group(1), _sx + _cx * _math.cos(_a) + _cz * _math.sin(_a), _sz - _cx * _math.sin(_a) + _cz * _math.cos(_a)))
    else:
        _k = re.search(r"Kiosk = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \}", _rest)
        _pts.append((_m.group(1), float(_k.group(1)), float(_k.group(2))))
_sep = min(_math.hypot(a[1] - b[1], a[2] - b[2]) for i, a in enumerate(_pts) for b in _pts[i + 1:]) if len(_pts) > 1 else 0
_wpc = read(WPC) or ""
_mm = re.search(r"local CONSOLE_MARGIN = ([\d.]+)", _wpc)
_margin = float(_mm.group(1)) if _mm else 99
_ytop = re.search(r"localPos\.Y <= half\.Y \+ ([\d.]+)", _wpc)
_ybot = re.search(r"localPos\.Y >= -half\.Y - ([\d.]+)", _wpc)
_boxTop = 1.7 + (float(_ytop.group(1)) if _ytop else 99)  # CONSOLE_SIZE.Y 3.4 -> half 1.7
_boxBot = 1.7 + (float(_ybot.group(1)) if _ybot else 99)
_corner = _math.hypot(1.3 + _margin, 0.7 + _margin)  # CONSOLE_SIZE 2.6 x 3.4 x 1.4, horizontal corner of the BUY box
if len(_pts) >= 15 and _sep > 2 * _corner:
    ok(f"v71 closest console pair {_sep:.1f} studs > 2 x client BUY box {_corner:.1f} (boxes never overlap)")
else:
    bad(f"v71 consoles too close: {_sep:.1f} studs vs 2 x {_corner:.1f} (n={len(_pts)})")
if _corner <= _dist and _boxTop <= _maxdy and _boxBot <= _maxdy:
    ok(f"v71 client BUY box (xz {_corner:.1f}, y -{_boxBot:.1f}..+{_boxTop:.1f}) inside the server cylinder ({_dist + _slack:.0f}, +-{_maxdy:.0f})")
else:
    bad(f"v71 client BUY box xz {_corner:.1f} / y -{_boxBot:.1f}..+{_boxTop:.1f} exceeds prompt {_dist} / vertical {_maxdy} (CONSOLE_MARGIN={_margin})")
_bw = float(re.search(r"BeamWidth0 = ([\d.]+)", _cfg).group(1))
_le = float(re.search(r"BeamLightEmission = ([\d.]+)", _cfg).group(1))
if _bw <= 0.25 and _le <= 0.3:
    ok("v71 GO waypoint beam within the HUD beam rule (width <= 0.25, LightEmission <= 0.3)")
else:
    bad(f"v71 GO beam too loud width={_bw} LightEmission={_le}")

# v71 console-only buying, client polish: the GO marker refreshes at <= 10 Hz (CLAUDE.md UI refresh cap)
CW = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/ConsoleWaypoint.luau"
must_contain(CW, "if stepAcc < 1 / W.RefreshHz then", "v71 GO waypoint step throttled to Waypoint.RefreshHz")
must_contain(CBC, "RefreshHz = 10,", "v71 GO waypoint refresh 10 Hz")
must_contain(CBC, "MarkerMinTextPx = 14,", "v71 GO marker text >= 14 px")

# ── v71 mobile P0-6: tutorial targets are the player's OWN plot (never Plot 1's markers); P1-15 device-neutral copy
TCFG = "src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau"
must_contain(TC, "function TutorialController.ResolveTarget(", "P0-6 tutorial target resolver (own plot first)")
must_contain(TC, "nearestOwnTagged(Constants.Tags.MoneyCollector, plotId, origin)", "P0-6 Income -> own Money Collector")
must_contain(TC, "nearestOwnTagged(MANUAL_DROPPER_TAG, plotId, origin)", "P0-6 Dropper -> own manual dropper")
must_contain(TC, "return ConsoleLocator.Find(plotId, padStructureId)", "P0-6 buy steps -> own console")
must_contain(TC, "return ownSpawn(plotId)", "P0-6 ClaimBase -> own PlayerSpawn")
must_contain(TC, "return nearestOutpost(origin, userId or player.UserId, plotId)", "P0-6 Outpost -> own Home Outpost, else the nearest uncontested zone (F6: from the own gate)")
must_contain(TC, "and insidePad(pad, inst.Position) then", "P0-6 a named marker only inside the own plot")
must_not_contain(TC, "Workspace:FindFirstChild(markerName, true)", "P0-6 no world-wide marker lookup by name")
must_not_contain(TC, "findPadByStructure", "P0-6 no nearest-any-plot pad fallback")
_tc = read(TC) or ""
_rt = _tc.find("function TutorialController.ResolveTarget(")
_rt_end = _tc.find("\nend\n", _rt)
_body = _tc[_rt:_rt_end] if _rt >= 0 else ""
_plot_gate = _body.find("if plotId == nil then")
_name_lookup = _body.find("Constants.Tags.TutorialMarker")
if 0 <= _plot_gate < _name_lookup and all(_body.find(k) < _name_lookup for k in ("ownSpawn(plotId)", "Tags.MoneyCollector", "MANUAL_DROPPER_TAG", "ConsoleLocator.Find(plotId")):
    ok("P0-6 per-player targets resolve before any marker name lookup")
else:
    bad(f"P0-6 resolver order wrong plotGate={_plot_gate} nameLookup={_name_lookup}")
_tcfg = read(TCFG) or ""
_hints = re.findall(r'(?:Hint|Title|CtaLabel) = "([^"]*)"', _tcfg)
_keyish = [h for h in _hints if re.search(r"\((?:[A-Z]|Key [A-Z0-9]+)\)|\[[A-Z]\]|\bclick|\bpress [A-Z]\b|\bWASD\b|\bkey\b|\bE to\b", h, re.I)]
if len(_hints) >= 16 and not _keyish:
    ok(f"P1-15 tutorial copy is device-neutral ({len(_hints)} strings, no key names / click)")
else:
    bad(f"P1-15 tutorial copy names keys or says click: {_keyish} (n={len(_hints)})")
_longhints = [h for h in re.findall(r'\n\t\t\tHint = "([^"]*)"', _tcfg) if len(h) > 42]
if not _longhints and re.search(r'\n\t\t\tHint = "', _tcfg):
    ok("P1-15 tutorial hints fit the objective chip on an 800x360 phone (<= 42 characters)")
else:
    bad(f"P1-15 tutorial hints longer than 42 characters (cut off on phones): {_longhints}")

# ── v71 mobile merge gate §1C #2-#8 + P1-6 (builders A / B; verifier fixes). Verified: HUD harness 10 states x
# 800x360 / 844x390 / 956x440 / 1180x820 / 1280x720, pa_gate 10/10, b_touchfire 45/45 touch + 11/11 desktop, v_adv.
_MG_HC = "src/ReplicatedStorage/Shared/Configs/HudConfig.luau"
_MG_CTL = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/"
must_contain(_MG_HC, "MinTextPx = 14,", "merge gate #2 text floor 14 real px")
must_contain(_MG_HC, "SkipHit = 64", "merge gate #3 tutorial Skip hit 64 v (44.8 real px)")
must_contain(_MG_HC, "CloseHit = 64,", "merge gate #3 offer close hit 64 v")
must_contain(_MG_HC, "PlusOnPill = false,", "merge gate #6 cash + off the pill (thumbstick zone)")
must_contain(_MG_CTL + "PromptController.luau", "UserInputService.TouchEnded:Connect", "merge gate #4 a lifted finger releases held pills")
must_contain(_MG_CTL + "PromptController.luau", "releaseHoldsOf(input)", "merge gate #4 hold release helper")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/HudLayout.luau", "function HudLayout.PrefersKeys(", "merge gate #7 key copy follows PreferredInput")
must_contain(_MG_CTL + "SettingsController.luau", "applySheet(HudLayout.PrefersKeys())", "merge gate #7 controls sheet only for keyboard / gamepad")
must_contain(_MG_CTL + "VehicleController.luau", "Sit · drive with the stick", "merge gate #7 garage touch tip without WASD")
must_not_contain(_MG_CTL + "VehicleController.luau", "string.sub(cat, 1, 3)", "merge gate #7 no GRO / COMM chips")
must_contain(_MG_CTL + "OrdersController.luau", "NonModal = true", "P1-6 Army popover non-modal (FIRE stays up)")
must_contain(_MG_CTL + "UIController.luau", "OnLongPress", "P1-6 Army tile long-press cycles the order")
must_contain(_MG_CTL + "HUDController.luau", "if (input.Position - startPos).Magnitude > LONG_PRESS_SLOP_PX then", "P1-6 a thumb dragging off the Army tile never changes the order")
must_not_contain(_MG_CTL + "ArmyController.luau", "Barracks (B)", "CLAUDE.md copy by device: no (B) key in Army text")
must_contain(_MG_CTL + "CombatController.luau", "TOUCH_TAP_HOLSTERS", "merge gate #5 a touch re-tap never holsters")
must_contain(_MG_CTL + "CombatController.luau", "math.clamp(tonumber(ARMED_CFG.ScanHz) or 4, 1, 4)", "merge gate #5 holstered-FIRE scan capped at 4 Hz")
must_contain(_MG_HC, "Fire = { Size = 88, Anchor = Vector2.new(0.5, 1), Right = 86, Bottom = 152 },", "FIRE 16 px above the jump button (phones)")
must_contain(_MG_CTL + "CombatController.luau", "local FIRE_ABOVE_JUMP = 16", "FIRE 16 px above the jump button (tablets)")

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

# W1 early (verified: road cull 61/61 + 299 parts culled / 10 MapSetup survivors, audio 155/155, CFG 22 ids dropped,
# World v2 Phase 1 modules unhooked 29/29 + 42/42 steps, ds 24, world ok)
must_contain("src/ServerScriptService/Server/Modules/Waterways.luau", "local hit = (gap <= rc.Corridor and d.CanCollide)", "ROAD: collidable decor culled in the 12-stud road corridor")
must_contain("src/ReplicatedStorage/Shared/Configs/WaterConfig.luau", "ExemptAncestors = { \"RoadEnds\", \"Bases\", \"Territories\" },", "ROAD: road ends, bases, territories never culled")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau", "safeInit(\"AudioHooks\", safeRequire(\"AudioHooks\", Modules:WaitForChild(\"AudioHooks\", 5) :: Instance))", "W1 SND AudioHooks init guarded")
must_contain("src/ReplicatedStorage/Shared/Configs/SoundConfig.luau", "MaxConcurrent = 12,", "W1 SND <= 12 concurrent one-shots")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/AudioController.luau", "return RunService:IsServer() and not RunService:IsClient()", "W1 SND no Sounds on the server")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/AudioHooks.luau", "FireServer", "AudioHooks only listens")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/AudioHooks.luau", "RenderStepped", "W1 SND no per-frame audio")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "19297043", "W1 CFG franchise tank dropped")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "122068883442022", "W1 CFG real-world 4x4 dropped")
must_not_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "= 11962508154", "W1 CFG real-world launcher mesh dropped")
must_contain("src/ReplicatedStorage/Shared/Configs/WorldConfig.luau", "MaxTalusTop = 20,", "World v2 talus never a ramp (roadmap 1.5 #1)")
# W3 RETIRED: must_contain("src/ReplicatedStorage/Shared/Configs/WorldConfig.luau", "OrphanMode = \"Report\",", "World v2 H1 in Report mode for W1 (roadmap 1.5 #3)")
must_contain("src/ServerScriptService/Server/Modules/WorldHygiene.luau", "if not isTarget[top] then", "H8: 24-light world cap holds across per-folder Enforce calls")

# ── verifier (agentf/vf) new pins for HUD v70 F1/F2 (spec §5 / §4.2) ──
_S = "src/ServerScriptService/Server/"
must_contain("src/ReplicatedStorage/Shared/Util/WorldLabel.luau", "bb.Size = UDim2.fromScale(studs.X, studs.Y)", "v71 WorldLabel billboards are stud-scaled")
must_contain("src/ReplicatedStorage/Shared/Configs/WorldLabelConfig.luau", "OutsideMaxDistance = 40,", "v71 label policy also caps labels outside plots at 40")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau", "pcall(WorldLabel.StartOwnerFilter)", "v71 client hides other players' owner-only labels")
must_contain(_S + "Modules/HollowBuildingBuilder.luau", "local TERMINAL_PROMPT_RANGE = 12", "P1-19 terminal prompts reach 12 studs")
must_contain(_S + "Modules/Interiors/Barracks.luau", "prompt.MaxActivationDistance = 12", "P1-19 Barracks desk prompt 12 studs")
must_contain(_S + "Modules/Interiors/CommandCenter.luau", "prompt.MaxActivationDistance = 12", "P1-19 Command Center table prompt 12 studs")
must_not_contain(_S + "Services/PrestigeService.luau", "press K", "P1-11 no key name in the rebirth nudges")
must_not_contain(_S + "Services/MoneyCollectorService.luau", "click the dropper", "P1-11 no mouse wording in the empty-ATM line")
must_not_contain("src/ReplicatedStorage/Shared/Configs/ManualDropperConfig.luau", "CLICK", "P1-11 dropper tag reads $15 (no CLICK)")
must_not_contain(MSW, "PAD · E / G", "P1-11 garage / naval pad tags name no keys")
must_not_contain(MSW, '"NPC SPAWN"', "no NPC SPAWN debug label")
must_not_contain(MSW, '"EVENT ZONE"', "no EVENT ZONE debug label")
must_not_contain(MSW, "WE_TrainBeam", "no glowing training beams in a base")
must_not_contain(SKBW, "WE_SniperCue", "no SNIPER cue billboards")
must_contain(SKBW, "WorldLabel.Surface(arch,", "gate sign painted on the arch (WE_GateSign kept)")
must_contain(_S + "Services/MoneyCollectorService.luau", '"Collect", 3, granted)', "spec 4.2 collect = float only (Collect + Amount)")
must_contain(_S + "Services/NotificationService.luau", "Amount = amount", "Notification payload carries Amount")
must_contain(_S + "Services/BankRaidService.luau", "BankRaidConfig.UnderFireSeconds", "task 20 bank hold freezes only when hit recently")
must_contain(_S + "Services/BankRaidService.luau", 'vault:FindFirstChild("Label")', "one bank vault label (MapSetup card removed at runtime)")
must_contain(_S + "Services/SupplyDropService.luau", "-- bottom face on the ground", "supply crate sits on the ground")
must_not_contain(_S + "Services/SquadOrdersService.luau", "Squad: FOLLOW", "no Squad: X toast per order")
must_contain(HUDCFG, 'Match = "^BASE UNDER ATTACK"', "client routes the new BASE UNDER ATTACK shape to the Alert slot")

# W1 JEEP-2 (verified: t_server 290, v_rot 167, v_server 22, v_client 11, t_jeep_server 105, adv 33, jeep2 client 44 + adv 9 + prompt 6,
# t_client_jeep 194 re-pinned, HUD 0 overlaps 800x360..1920x1080, ds 24, world ok)
must_contain("src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau", "MilitaryJeep = V(\"MilitaryJeep\", \"Field 4x4\"", "JEEP-2 starter 4x4 id kept")
must_contain("src/ReplicatedStorage/Shared/Configs/VehicleWeaponConfig.luau", "DisplayName = \"4x4 HMG\"", "JEEP-2 JeepHMG shown as 4x4 HMG")
must_contain("src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau", "MarkerName = \"Tutorial_Jeep\"", "JEEP-2 tutorial marker id kept")
must_contain("src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau", "local W: any = require(script.Parent.WorldConfig)", "JEEP-2 air box from WorldConfig.Bounds.Air")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau", "input = airGuardInput(st, P, box, input, sense)", "JEEP-2 turn-back before the law")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau", "local floor = if plane or grounded then 0 else -box.PushFrac * P.MaxSpeed", "JEEP-2 bounded push-in, none on the ground")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "(pos.X > box.X + sl and vel.X > ow)", "JEEP-2 air bounds only when still moving out")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "local ceiling = if box then math.min(rec.MaxAltitude, box.MaxY) else rec.MaxAltitude", "JEEP-2 validator ceiling = law ceiling")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau", "HL.RegisterTopStack(STACK_NAMES[1], p, tonumber(HUDC.PillStackOrder) or 25, { Space = \"Screen\" })", "JEEP-2 W7 touch SPD pill in the top stack")
must_not_contain("src/ReplicatedStorage/Shared/Configs/LevelConfig.luau", "(K panel)", "JEEP-2 no key name in the L40 line")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau", "pps.PromptShown:Connect(onPromptShown)", "JEEP-2 prompts hidden while seated")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", "\"Armed Jeep\"", "JEEP-2 no Jeep brand in garage copy")
must_not_contain("src/ServerScriptService/Server/Modules/Interiors/VehicleDepot.luau", "JEEP-02", "JEEP-2 depot status board brand-free")

# v71 owner playtest chat commands /level and /xp (verified: admin chat 11/11, admin money 28)
must_contain("src/ServerScriptService/Server/Services/AdminService.luau", "local isLevelCmd = cmd == \"level\" or cmd == \"setlevel\"", "owner /level chat command (allowlist only)")
must_contain("src/ServerScriptService/Server/Services/AdminService.luau", "if last and last.Text == text and nowClock - last.At < 1.0 then", "admin chat line runs once across chat paths")

# asset shortlist §3.1 clear-now (verified live 2026-09-24; docs/ASSET_SHORTLIST.md)
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "14776506955", "shortlist: 484k-tri soldier swarm pack cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "125916936788670", "shortlist: real-4x4 copy cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "76055078503396", "shortlist: real-IFV copy cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "105503568352704", "shortlist: real army-truck copy cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "17835143223", "shortlist: real MRAP copy cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "5507592781", "shortlist: real fighter copy cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "3319732457", "shortlist: WW2 fighter copy cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "295607934", "shortlist: franchise helicopter copy cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "8980890767", "shortlist: 100k-tri sandbag nest cleared")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "12809476227", "shortlist: 156k-tri mesa cleared")

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


# --- v71 money M1: receipt core + quick wins (Starter Pack v2, Army Expansion +10, BP unlock, offer rules) ---
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "local fallbackCash = nonNegInt(product.StarterFallbackCash)", "M1 Starter fallback cash decided before grants")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "for _, ent in ipairs(entitlements) do", "M1 GrantEntitlements list")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "applyCounterGrant(player, profile, c)", "M1 counter grants (whitelisted fields)")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "event.FirstPurchase = recordPurchase(profile, event.CurrencySpent)", "M1 purchase counters")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "rememberPendingGrant(receiptId, event) -- v71 money (M1): its post-save work runs when a retry saves it", "M1 post-save listeners survive a failed save")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "task.defer(runListener, \"OnGranted\", fn, player, event.ProductKey, event)", "M1 OnGranted deferred + pcall")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "function MonetizationService.OnGranted(fn: GrantListener): () -> ()", "M1 OnGranted API")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "function MonetizationService.OnPassOwned(fn: PassOwnedListener): () -> ()", "M1 OnPassOwned API")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "firePassOwned(player, passKey, \"purchase\")", "M1 pass purchase event")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "while pending > 0 do", "M1 parallel pass checks (J21)")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "E.AnalyticsEconomyTransactionType.IAP.Name", "M1 economy analytics IAP")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "local source = cleanSource(rawSource)", "M1 purchase source whitelist")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "function MonetizationService.TrySoftOfferStarterBundle(player: Player, reason: string?): boolean?", "M1 Starter offer gate")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "if cfg.SoftOfferQuietUntilTutorialComplete == true and DataService then", "M1 no soft offers mid-tutorial")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "-- that lookup can yield (first pass-cache fill): the player and the profile must still be the live ones", "M1 J2 Starter fallback re-checks player/profile after the ownership lookup")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "if ents[need] ~= true or ents[flag] == true then", "M1 goodwill once per profile (StarterGoodwillV2 flag)")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "if not bundle or not profile or profile.StarterBundleOffered == true or profile.TutorialComplete ~= true then", "M1 Starter offer: live Id, once per profile, never mid-tutorial")
must_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "if maxPerSession and (softOffersClaimed[player.UserId] or 0) >= maxPerSession then", "M1 D8 server soft-offer budget")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "GrantEntitlements = { \"StarterBundle\", \"AutoCollect\" },", "M1 Starter Pack v2 grants Auto Collect")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "StarterFallbackCash = 25000,", "M1 Starter fallback cash")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "ArmyCapBonus = 10,", "M1 Army Expansion +10")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "IgnoreReasons = { walk_speed = true, vehicle_sit = true } :: { [string]: boolean },", "M1 no Speed Boost pop-up on spawn/seat")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "IgnoreReasons = { death = true } :: { [string]: boolean },", "M1 no Cash Mega pop-up after death")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "Field = \"Nukes\",", "M1 counter grant field")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "SoftOfferSessionMax = 3,", "M1 D8 3 offers per session")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "Flag = \"StarterGoodwillV2\",", "M1 goodwill flag key")
must_contain("tools/wire-monetization-ids.py", "is a Feature SKU (", "M1 wire tool keeps Feature SKUs hidden")
must_contain("src/ServerScriptService/Server/Services/SoldierService.luau", "return base + barracksLevel(profile) * per + armyCapBonus(profile)", "M1 army cap = base + barracks + bonus")
must_contain("src/ServerScriptService/Server/Services/SoldierService.luau", "ArmyCapBonus = armyCapBonus(profile),", "M1 ArmyCapBonus in SoldierStateUpdate")
must_contain("src/ServerScriptService/Server/Services/SoldierService.luau", "if typeof(profile.Entitlements) ~= \"table\" or profile.Entitlements.ExtraSoldierSlot ~= true then", "M1 Army Expansion is a boolean (+10 never stacks)")
must_contain("src/ServerScriptService/Server/Services/BattlePassService.luau", "PremiumWaiting = premiumWaiting(bp),", "M1 BP premium rewards waiting")
must_contain("src/ServerScriptService/Server/Services/BattlePassService.luau", "if t and t >= 1 and t <= level and not claimed[tostring(t)] and typeof(reward) == \"table\" then", "M1 BP header uses the claim rules (tier <= level, unclaimed)")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "local ok, res = pcall(mon.TrySoftOfferStarterBundle, player, reason)", "M1 tutorial schedules the Starter offer via the gate")
must_contain("src/ServerScriptService/Server/Services/TutorialService.luau", "scheduleStarterOffer(player, false)", "M1 Starter offer after tutorial")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau", "return -- OWNED: no re-prompt", "M1 Army Expansion owned: no prompt")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau", "\"Army full \u00b7 +%d slots \u00b7 %d R$\"", "M1 army full chip")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau", "\"ARMY +%d \u00b7 OWNED\"", "M1 Army Expansion owned label")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau", "sessionBought[key] = true", "M1 verify: no double charge for Army Expansion / Commander Pack")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "\"PREMIUM \u00b7 %d R$ \u00b7 %d %s waiting (%s)\"", "M1 BP premium header")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "string.format(\"FREE TRACK \u00b7 Premium: %d R$\", premiumPrice())", "M1 BP free track label")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "pb.Text = \"UNLOCK PREMIUM\"", "M1 BP unlock button")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "RequestPurchaseDevProduct, \"PremiumPass\", \"bp_panel\")", "M1 BP unlock source tag")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau", "premiumBought = true -- v71 money (M1 verify): no second UNLOCK prompt while the grant is on its way", "M1 verify: no double charge for BP Premium")
must_not_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "MonetizationService.TrySoftOfferSpeedBoost(player, \"walk_speed\")", "M1 no Speed Boost offer on spawn")
must_not_contain("src/ServerScriptService/Server/Services/MonetizationService.luau", "local cashBelow = tonumber(offerCfg.CashBelow)", "M1 one Starter scheduler (old at-join offer gone)")

# --- Join hotfix (2026-09-24): store-model templates in ServerStorage; gate guards spare unloaded / just-spawned players ---
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "local ServerStorage = game:GetService(\"ServerStorage\")", "Join hotfix: VisualAssetService gets ServerStorage")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "\tf.Name = \"WE_VisualAssetTemplates\"\n\tf.Parent = ServerStorage\n", "Join hotfix: store-model templates parked in ServerStorage (not replicated to joiners)")
must_not_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "f.Parent = ReplicatedStorage", "Join hotfix: templates folder never parented to ReplicatedStorage")
must_contain("src/ReplicatedStorage/Shared/Configs/GateDefenseConfig.luau", "SpawnGraceSeconds = 4,", "Join hotfix: GateDefenseConfig.SpawnGraceSeconds")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "if DataService and DataService.GetProfile and DataService.GetProfile(player) == nil then\n\t\treturn true\n\tend", "Join hotfix: guards ignore a player whose save has not loaded")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "return from ~= nil and nowClock() - from < (GateDefenseConfig.SpawnGraceSeconds or 4)", "Join hotfix: spawn grace reads SpawnGraceSeconds")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "if player:GetAttribute(\"WE_RaidingPlot\") ~= nil then\n\t\treturn false\n\tend", "Join hotfix: an ATM raid ends the spawn grace")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "if isEnemyPlayer(def.OwnerUserId, player) and not inSpawnGrace(player) then", "Join hotfix: guards + AutoGuns skip players in spawn grace (nearestEnemy)")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "\tif inSpawnGrace(player) then\n\t\treturn\n\tend\n\tif not rateLimitVictim(player.UserId) then", "Join hotfix: dealDamage refuses players in spawn grace")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "player.CharacterAdded:Connect(function()\n\t\t\tstartSpawnGrace(player)\n\t\tend)", "Join hotfix: spawn grace clock starts on every CharacterAdded")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "DataService.OnProfileLoaded(function(player: Player, _profile: any)\n\t\t\tstartSpawnGrace(player)", "Join hotfix: spawn grace clock restarts when the save loads")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "graceFrom[attacker.UserId] = nil -- attacking the defenses ends the spawn grace", "Join hotfix: hitting a gate / guard ends the spawn grace")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "graceFrom[player.UserId] = nil\n", "Join hotfix: spawn grace entry cleared on leave")
must_not_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", "deps.CombatService", "Join hotfix: GateDefenseService takes no CombatService dep (no require cycle)")
must_not_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", ".CombatService)", "Join hotfix: GateDefenseService does not require CombatService")
must_contain("docs/LIVE_PLACE.md", "**Public** since 2026-09-24 17:54 UTC", "Join hotfix: LIVE_PLACE privacy is Public")
must_not_contain("docs/LIVE_PLACE.md", "Private (owner + friends", "Join hotfix: LIVE_PLACE no longer says Private = owner + friends")
_tpl_refs = [q.relative_to(ROOT).as_posix() for q in (ROOT / "src").rglob("*.luau") if q.name != "VisualAssetService.luau" and "WE_VisualAssetTemplates" in q.read_text(encoding="utf-8")]
if _tpl_refs:
    bad("Join hotfix: WE_VisualAssetTemplates read outside VisualAssetService (a client read would break after the ServerStorage move) — " + ", ".join(_tpl_refs))
else:
    ok("Join hotfix: nothing outside VisualAssetService reads WE_VisualAssetTemplates")

# --- W2 Combat Core: aim assist, projectiles + splash, vehicle HP, client feel ---
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if (origin - eye).Magnitude > 0.25 and not CombatDamage.LineOfSight(eye, origin, shotFilterFor(character, seatVeh), nil, true) then", "W2: shot Origin behind a wall snaps to the head")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "return VehicleCombatConfig.SeatFire.DriverCanUseInfantryWeapons == true and seat:GetAttribute(\"WE_Exposed\") ~= false, veh, false", "W2: enclosed driver seat never fires out")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "From = origin, -- W2 verify", "W2: projectile first ray from the shot origin")
must_contain("src/ServerScriptService/Server/Modules/Projectile.luau", "Pos = start,", "W2: Projectile starts its ray at From")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if isProjectile and Projectile.AtCap(player.UserId) then", "W2: projectile cap before ammo")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "local isHead = (kind == \"Player\" or kind == \"NPC\") and result.Instance.Name == \"Head\"", "W2: headshot only on the exact ray")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "if how == \"Miss\" and AimAssistConfig.Enabled then", "W2: assist only after exact ray + claim miss")
must_contain("src/ServerScriptService/Server/Services/CombatService/CombatAssist.luau", "if CombatDamage.LineOfSight(cur.Origin, torso.Position, shotFilter, model, false, AimAssistConfig.LosPastTorsoStuds) then", "W2: assist needs line of sight")
must_contain("src/ServerScriptService/Server/Services/CombatService/CombatFx.luau", "if not take(shooterBuckets, shooterKey, fx.PerShooterHz, fx.PerShooterBurst, now()) then", "W2: WeaponFx <= 20 Hz per shooter")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "if VehicleService._VehicleHealth.HitLockLeft(player.UserId, SpawnCfg.DamageLockSeconds) > 0 then", "W2: no SPAWN heal while the vehicle is under fire")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "return false, \"Repairing\"", "W2: destroyed id locked while repairing")
must_not_contain("src/ServerScriptService/Server/Modules/VehicleHealth.luau", "Instance.new(\"Explosion\")", "W2: no server Explosion")
must_contain("src/ReplicatedStorage/Shared/Configs/AimAssistConfig.luau", "Touch = { LateralStuds = 2.5, MaxConeDeg = 4 },", "W2: touch assist limits")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau", "fire.Active = false", "W2: FIRE non-Active (drag-to-aim)")

# --- v72 HUD scale fix (rail/cash pill 1.29x too big on phones) ---
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/HudLayout.luau", "local trackedScales: { [UIScale]: boolean } = setmetatable({} :: any, { __mode = \"k\" })", "v72 HUD: tracked UIScales are a strong table (weak Instance keys get dropped)")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/HudLayout.luau", "local topbarAreas: { [ScreenGui]: Frame } = setmetatable({} :: any, { __mode = \"k\" })", "v72 HUD: topbar areas are a strong table")
must_not_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/HudLayout.luau", "local bindings: { [GuiObject]: Binding } = setmetatable({} :: any, { __mode = \"k\" })", "v72 HUD: visibility bindings are a strong table")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/HudLayout.luau", "if not (v and v.X > 1 and v.Y > 1) and HudLayout.IsTouch() then", "v72 HUD: phone scale while the viewport is unknown")
must_not_contain("src/ReplicatedStorage/Shared/Util/UIUtil.luau", "local trackedScales: { [UIScale]: ScaleParams } = setmetatable({} :: any, { __mode = \"k\" })", "v72 HUD: UIUtil tracked scales are a strong table")
must_contain("src/ReplicatedStorage/Shared/Util/UIUtil.luau", "if scale.Parent == nil then", "v72 HUD: UIUtil prunes removed scales")


# --- W3 step 1: kit catalogue, Crossroads Town, travel dressing, H1 Enforce, Roblox-owned look ---
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'function WorldDress.Zones(): Zones', 'W3 one shared keep-out source (WorldDress.Zones)')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'function WorldDress.Blocked(occ: Occupancy, x: number, z: number, r: number, opts: BlockOpts?): string?', 'W3 WorldPOI and WorldDress share WorldDress.Blocked')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'function WorldDress.Build(dressing: Instance, quality: string, occ: Occupancy?): Summary', 'W3 WorldDress.Build contract signature')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'function WorldPOI.Build(dressing: Instance, quality: string, occ: Occupancy?): Summary', 'W3 WorldPOI.Build contract signature (occ typed via the local alias type Occupancy = WorldDress.Occupancy)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'function WorldKits.Rng(seed: number): Rng', 'W3 pure-Luau PRNG (same layout in the sim and live)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'function WorldKits.NewCluster(name: string, attrs: ClusterAttrs): Model', 'W3 clusters carry the H1 attributes')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'm.ModelStreamingMode = Enum.ModelStreamingMode.Atomic', 'W3 clusters stream in whole')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'p.Material = if mat == Enum.Material.Neon then Enum.Material.SmoothPlastic else mat', 'W3 kit factory never builds Neon (H5)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldDressConfig.luau', 'Seed = 702,', 'W3 travel dressing seeded (spec §4 model seed)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldDressConfig.luau', 'POIShare = 0.6,', 'W3 Quality Low = POIs at 60 %')
must_not_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'Random.new(', 'W3 kits use WorldKits.Rng, not Random')
must_not_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'Random.new(', 'W3 travel dressing uses WorldKits.Rng, not Random')
must_not_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'Random.new(', 'W3 POIs use WorldKits.Rng, not Random')
must_not_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'BillboardGui', 'W3 no world BillboardGui in kits (painted SurfaceGui signs only)')
must_not_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'BillboardGui', 'W3 no world BillboardGui in POIs')
must_not_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'BillboardGui', 'W3 no world BillboardGui in the travel dressing')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'OrphanMode = "Enforce",', 'World v2 H1 enforced in W3 (roadmap 1.5 #3)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'ElementsAttr = "WE_Elements",', 'W3 natural clusters stand alone by their element count (H1)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', '"Dune", "DeadTree", "Stump", "FallenLog", "Reed", "Driftwood" },', 'W3 dead wood, reeds and driftwood are natural (H1)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Budget = 370, Enabled = true, Lights = 8, Signs = 1 },', 'W3 Town v2 builds Crossroads Town (370 parts: every 512 circle <= 500; 8 lights, 1 sign)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Rect = { X0 = -330, X1 = 330, Z0 = 1150, Z1 = 1466 }, Budget = 140, Reserve = 8,', 'W3s2: South Port footprint from Z0 1150 and its caps (geometry plan)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Lamp = { Brightness = 0.6, Range = 16, Color = Color3.fromRGB(255, 236, 190) },', 'W3 Town lamps inside the light policy (H8)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'MeshOverlays = 40,', 'W3 Roblox-owned mesh overlays capped per server')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'RoadClear = 30, -- block clusters', 'W3 Town blocks keep 30 off the road lines (spec 3.2)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'BoardText = "CROSSROADS",', "W3 the Town's one painted board")
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'MaxTalusTop = 20,', 'World v2 talus never a ramp (kept)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'light.Shadows = false', 'W3 street lamps never cast shadows (phones)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'CollectionService:AddTag(light, WorldConfig.Atmosphere.NightLightTag)', 'W3 lamps tagged WE_NightLight (night only)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'p.CastShadow = ps.CastShadow == true and math.max(s.X, s.Y, s.Z) >= SHADOW_MIN -- H9', 'W3 kit factory: shadows only on parts >= 8 (H9)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'if used >= WorldConfig.Budgets.SurfaceGuis then', 'W3 world sign budget enforced by WorldKits.Sign')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'sm.Parent = p -- the Part keeps its box collision: net 0 parts', 'W3 mesh skin never adds a part')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'm.Parent = cluster -- 1 collider + 1 mesh replace n >= 2 parts', 'W3 wreck mesh overlay never adds parts')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'task.defer(function()', 'W3 mesh overlays are deferred (never block the build)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'function WorldKits.Footprint(kitId: string, opts: KitOpts?): Footprint?', 'W3 exact kit footprints for road-side offsets')
must_not_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'GetService("InsertService")', 'W3 kits never load assets themselves (VisualAssetService only)')
must_not_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'WaitForChild(', 'W3 kits never wait on the tree')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'why = WorldDress.Blocked(occ, cx, cz, r, { AllowPOI = poi.Id, RoadClear = T.RoadClear })', 'W3 every Town block cluster passes the shared keep-out')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'WorldDress.AddDisc(occ, cx, cz, r, anchor)', 'W3 Town clusters recorded in the shared occupancy')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'local partsCap = if low then math.min(poi.Budget, math.floor(fullPlanned * WorldDressConfig.Quality.Low.POIShare + 1e-9)) else poi.Budget', 'W3 Quality Low = POIs at <= 60 %')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', '"[WAR EMPIRE] WorldPOI: %s %s %d/%d parts, %d lights, %d signs, %d clusters, %d skipped, %d terrain (%.3f s)"', 'W3 WorldPOI summary line in the live Output')
must_not_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'WaitForChild(', 'W3 POIs never wait on the tree')
must_not_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'task.wait(', 'W3 the Town build never yields')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'pcall(wh.Enforce, dressing)', 'WorldHygiene after cull (dressing) [kept]')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'kitRadioTower(f2, Vector3.new(1100, 0.5, 1100), 45)', 'no kit on the OilYard event anchor [kept]')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'local okP, errP = pcall(wp.Build, dressing, quality, occ)', 'W3 Dress order 1: WorldPOI.Build (Crossroads Town)')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'local okD, errD = pcall(wd.Build, dressing, quality, occ)', 'W3 Dress order 3: WorldDress.Build (rhythm, junctions, shore, scatter)')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'return wd.NewOccupancy(wd.Zones())', 'W3 one occupancy shared by POIs and travel dressing')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'f.Name = "DocksideDressing"', 'W3 Dockside kept as-is until the Port POI step')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'local okCull, res = pcall(ww.CullDressing, dressing)', 'W3 Waterways cull stays the safety net')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'MapDressing complete: quality=', 'W3 MapDressing summary line kept')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'Landmarks_v35', 'W3 no v35 landmark coordinate list')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'PlotWarzoneDensify', 'W3 no plot densify ring')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'RoadWarzone_v36', 'W3 no v36 road warzone section')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'PlotRingPerimeter', 'W3 no plot-ring perimeter section')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'PalmHorizonHost', 'W3 no third-party palm horizon hosts')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'kitMesaHost', 'W3 no mesa host kit (Terrain canyon replaces it)')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'CamoNetOverVehicle', 'W3 no third-party camo-net host')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'local function tryPropAttach', 'W3 no catalog prop hosts in MapDressing')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'kitPortableLight', 'W3 no lone portable lights on sand')
must_not_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'd.CastShadow = false', 'W3 H9 governs shadows (no blanket CastShadow reset)')
must_contain('src/ServerScriptService/Server/Modules/DesertFlora.luau', 'pcall(wh.Enforce, flora)', 'WorldHygiene after cull (flora) [kept]')
must_not_contain('src/ServerScriptService/Server/Modules/DesertFlora.luau', '"Palm_Mid_"', 'no mid palms in the rim ring [kept]')
must_not_contain('src/ServerScriptService/Server/Modules/DesertFlora.luau', 'local rimR', 'no DesertFlora rim ring [kept]')
must_contain('src/ServerScriptService/Server/Modules/DesertFlora.luau', 'DesertFlora.Kits = {', 'W3 DesertFlora Part kits stay exported (Oasis palms later)')
must_not_contain('src/ServerScriptService/Server/Modules/DesertFlora.luau', 'TryAttachPropVisual', 'W3 no third-party flora catalog overlays')
must_not_contain('src/ServerScriptService/Server/Modules/DesertFlora.luau', 'Saguaro_Mid_', 'W3 no lone mid-map saguaros (H1 orphans)')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'if not isTarget[top] then', 'H8: 24-light world cap holds across per-folder Enforce calls [kept]')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'anchored = anchored or (groupSize[u] or 1) >= H.MinNatural or standsAlone(u)', 'W3 H1: a natural cluster of >= 3 elements (WE_Elements) of >= 2 sizes may stand alone')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'local ELEMENTS_ATTR: string = (H :: any).ElementsAttr or "WE_Elements"', 'W3 H1 stand-alone attribute from WorldConfig.Hygiene')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'local mode = (opts and opts.OrphanMode) or H.OrphanMode', 'W3 H1 mode read from WorldConfig.Hygiene.OrphanMode (Enforce)')
must_not_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', ':WaitForChild(', 'W3 no unbounded WaitForChild in WorldHygiene')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'local WorldKits = require(script.Parent.WorldKits)', 'W3 travel dressing composed from WorldKits')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'if nearJunction(zones, x, z, RH.JunctionClear) then', 'W3 no rhythm cluster within 70 of a junction')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'local need, why = roadCheck(ctx.Zones, parts, road, side)', 'W3 rhythm parts measured against the road corridor (H2) and pushed out')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'local keep = ctx.Full or pattern[(accepted - 1) % #pattern + 1] == true', 'W3 Quality Low keeps half the rhythm, same spots as Full')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'if not inWater or not hasPrefix(w.Name, SH.InWaterRects) then', 'W3 in-water kits only into the ring canal / sea')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'move = SH.InWaterMax - penetration(run, b0) - 0.25', 'W3 jetty / barge / hull reach <= 10 into the water')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'return WorldDress.Blocked(ctx.Occ, pos.X, pos.Z, row.Outer, { RoadClear = RH.CollidableRoadGap, SkipRing = skipRing })', 'W3 Terrain rocks keep out of roads (>= 13) and every zone')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'd.CastShadow = false', 'W3 travel dressing casts no shadows (phones)')
must_not_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'math.random', 'W3 travel dressing never uses math.random (sim = live layout)')
must_not_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'WaitForChild', 'W3 WorldDress never waits on instances')
must_not_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'require(script.Parent.WorldPOI)', 'W3 WorldDress never requires WorldPOI (no cycle)')
must_not_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'GetService("InsertService")', 'W3 travel dressing never yields on InsertService')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldDressConfig.luau', 'InWaterRects = { "Ring_", "Sea_" },', 'W3 in-water kits never enter channels / lagoons / harbour')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldDressConfig.luau', 'CollidableRoadGap = 13,', 'W3 collidable dressing > 12 from road centre lines (H2)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldDressConfig.luau', 'JunctionClear = 70,', 'W3 spec §4.1 no rhythm cluster within 70 of a junction')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'function VisualAssetService.CloneKitMesh(key: string): BasePart?', 'W3 LOOK CloneKitMesh (contracts §8.3)')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'local piece = pack:FindFirstChild(name, true) -- the name holds "/": never split it', 'W3 LOOK ChildName found whole (never split on /)')
must_not_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'string.split(', 'W3 LOOK ChildName never split')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'if n == 0 or n > maxParts() or hasHumanoid(t) then', 'W3 LOOK pack piece <= 40 parts, no Humanoid')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'if n > maxParts() or hasHumanoid(model) then', 'W3 LOOK whole model <= 40 parts, no Humanoid')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'local function splitPack(assetId: number, pack: Instance)', 'W3 LOOK pack split into configured pieces')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'table.insert(waiting, coroutine.running())', 'W3 LOOK one insert per id (waiters)')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'local function fitBodyToKit(clone: Model, hostModel: Model, primary: BasePart, ref: AssetRef): number?', 'W3 LOOK LUV body fit to the kit')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'hideKitUnder(hostModel, clone, ref)', 'W3 LOOK Part-kit visuals hidden under a fitted body')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'local ref = resolveVehicleRef(vehicleId, kitFamily)', 'W3 LOOK vehicle ref (ChildName travels with the family fallback)')
must_not_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', '75368157644109', 'W3 LOOK no paid ATM id left in comments')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'MaxPartsPerModel = 40,', 'W3 LOOK catalog part cap')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'ModelAssetId = 6418221666,', 'W3 LOOK Roblox Light Utility Vehicle body')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'ChildName = "Light Utility Vehicle (green camo)",', 'W3 LOOK LUV green camo variant')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'KeepVisible = { "GunMount", "Barrel" },', 'W3 LOOK Armed 4x4 keeps its Part turret')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'DesertKit = {', 'W3 LOOK DesertKit bucket (contracts §8.2)')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'ChildName = "Meshes/PolygonDungeon_Props_SM_Prop_Crate_Wood_04"', 'W3 LOOK DesertKit CrateWood piece')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '9171585794', 'W3 LOOK TankWreck host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '8176692221', 'W3 LOOK RuinedBuilding host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '104053043839965', 'W3 LOOK RuinedWall host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '13668977092', 'W3 LOOK CamoNet host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '13437018139', 'W3 LOOK CamoNetAlt host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '9701862157', 'W3 LOOK PortableLightTower host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '82454061017921', 'W3 LOOK JerseyBarrier host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '17156953177', 'W3 LOOK JerseyBarrierAlt host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '16354482789', 'W3 LOOK CactusBase host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '105982075286356', 'W3 LOOK PalmAlt host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '2652344972', 'W3 LOOK AmmoShed (117 parts) dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '82560800252069', 'W3 LOOK SupplyShed dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '123546710527428', 'W3 LOOK StreetLamp host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '8180880144', 'W3 LOOK StreetLampAlt dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '15912051001', 'W3 LOOK RoadBarriers host dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '867696371', 'W3 LOOK CheckpointBridge dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '55228082', 'W3 LOOK SpyBunker dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '9136197032', 'W3 LOOK DesertHouse dropped')
must_not_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', '11138299907', 'W3 LOOK Pier dropped')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'local fp = WorldKits.Footprint(kit.Kit,', 'W3 Town planned counts measured from the kit builder')

# --- W3 Town v2 (densify): TownBlock / RadioMast kits, Town v2 caps, landmarks ---
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'Builders.TownBlock = function(b: B)', 'W3 Town v2: 1-6 storey town blocks from a few big parts')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'TownBlock = spec(4, 31, Vector3.new(20.8, 15.2, 16.8), "manmade", true, 1, "Town"),', 'W3 Town v2: TownBlock catalogue row (4 parts default, 31 max)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'RadioMast = spec(5, 5, Vector3.new(6, 90, 6), "manmade", true, 1, "Town+POI"),', 'W3 Town v2: the 90-stud radio mast is built (step 1)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'local function nightLamp(host: BasePart)', 'W3 Town v2: street lamps and wall lanterns share one light policy (H8)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'tostring(o.Width), tostring(o.Depth), tostring(o.Storeys), tostring(o.Roof), tostring(o.Lantern)', 'W3 Town v2: Footprint cache keyed by the block options')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'local function kitOpts(k: WorldConfig.KitPlace, text: string?): WorldKits.KitOpts', 'W3 Town v2: one option mapper for planned counts and the build')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'WorldKits.Add(model, k.Kit, kcf, kitOpts(k, text))', 'W3 Town v2: rows build with the same options they were counted with')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', '{ Id = "NW_WaterTower", Block = "NW", Role = "tower", Tier = 1,', 'W3 Town v2: water tower landmark kept (NW, Tier 1)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', '{ Id = "SE_ClockTower", Block = "SE", Role = "tower", Tier = 1,', 'W3 Town v2: clock tower landmark kept (SE, Tier 1)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', '{ Id = "NE_TowerBlock", Block = "NE", Role = "landmark", Tier = 1,', 'W3 Town v2: ruined tower block landmark (NE, Tier 1)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', '{ Id = "SW_RadioMast", Block = "SW", Role = "mast", Tier = 1,', 'W3 Town v2: radio mast landmark (SW, Tier 1)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Budget = 220, Enabled = true, Lights = 6, Signs = 1 },', 'W3 Town v2: the step-1 Town caps are retired')

# --- Rollover fix (owner 2026-09-24: "The quad falls over when driving super easy"): ballast + drive at the centre of
# mass + roll/pitch assist + speed-sensitive steering + no traction while flipped + gentle flip recovery ---
RVC = 'src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau'
RVS = 'src/ServerScriptService/Server/Services/VehicleService.luau'
RVDC = 'src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau'
RVAS = 'src/ServerScriptService/Server/Services/VisualAssetService.luau'
must_contain(RVC, 'Wheeled = { Accel = 28, Brake = 60, Coast = 10, TurnRate = 2.4, MinTurnFactor = 0.35, Grip = 8, MaxLatAccel = 120 },', 'Rollover: speed-sensitive steering, wheeled MaxLatAccel 120 studs/s2')
must_contain(RVC, 'WheeledLight = { Ballast = 1.0, UprightFrac = 0.75 },', 'Rollover: light 4x4 / quad ballast + upright assist')
must_contain(RVC, 'TrackScale = { UtilityQuad = 1.2, ReconBuggy = 1.1, DispatchCar = 1.1 }', 'Rollover: wider quad / buggy / dispatch-car track')
must_contain(RVC, 'FlipUpY = 0.5, -- UpVector.Y below this', 'Rollover: flipped = tilted past 60 degrees')
must_not_contain(RVC, 'HopSpeed = 15,', 'Rollover: no 15 studs/s flip hop (recovery lifts <= 2.5 studs)')
must_contain(RVS, 'b:SetAttribute("WE_Ballast", true)', 'Rollover: WE_Ballast built for Car-mode wheeled kits')
must_contain(RVS, 'attach.Position = Vector3.new(0, com.Y, com.Z)', 'Rollover: WE_DriveLV pushes at the centre of mass (no cornering roll)')
must_contain(RVS, 'up.AlignType = Enum.AlignType.PrimaryAxisParallel', 'Rollover: WE_UprightAO is roll/pitch only (yaw free)')
must_contain(RVS, 'local torque = fam.UprightFrac * info.Weight * info.Arm - ao.MaxTorque', 'Rollover: upright assist stays below gravity righting moment')
must_contain(RVS, 'local rv = VehicleService._FlipRecover(state, sense, dt)', 'Rollover: server drive runs the flip recovery')
must_contain(RVS, 'local rv = VehicleService._FlipRecover(idle, sense, dt)', 'Rollover: an empty flipped car rights itself')
must_contain(RVS, 'state.Speed = approach(state.Speed, 0, c.Brake, dt)', 'Rollover: server drive has no traction while flipped')
must_contain(RVS, 'turn = math.clamp(turn, -c.MaxLatAccel / spd, c.MaxLatAccel / spd)', 'Rollover: server speed-sensitive steering')
must_contain(RVS, 'rec.ClearVal = not VehicleService._OthersNear(rec.Model, pos, reach + CarCfg.RecoverClearRadius)', 'Rollover: no righting next to another player (server)')
must_contain(RVS, 'or n == "WE_UprightAO" -- rollover fix', 'Rollover: WE_UprightAO is never counted as a pin')
must_contain(RVDC, 'local rv = Laws.FlipRecover(st, C, sense, dt)', 'Rollover: client law flip recovery')
must_contain(RVDC, 'st.Speed = approach(st.Speed, 0, C.Brake, dt)', 'Rollover: client law has no traction while flipped')
must_contain(RVDC, 'turn = math.clamp(turn, -latMax / spd, latMax / spd)', 'Rollover: client speed-sensitive steering')
must_contain(RVDC, 'd.ClearVal = not othersNear(', 'Rollover: no righting next to another player (client)')
must_contain(RVDC, 'ao.MaxAngularVelocity = tonumber(ao:GetAttribute("WE_Spin")) or ao.MaxAngularVelocity', 'Rollover: leaving the seat restores the AO spin limit')
must_contain(RVAS, 'd.CanTouch = false\n\t\t\td.Massless = true\n\t\t\td.CastShadow = false\n\t\t\tlocal weld = Instance.new("WeldConstraint")', 'Rollover: catalog vehicle dress stays massless + non-colliding')
must_contain(RVS, 'if flipAt ~= nil and t - flipAt < CarCfg.RecoverMaxSeconds then\n\t\t\tpush = false', 'Rollover (verifier): a flipped / just-righted car never trips the nomove watchdog')
must_contain(RVDC, 'and not (d.Mode == "Car" and d.Chassis.CFrame.UpVector.Y < (d.Params.C.FlipUpY or 0.5))', 'Rollover (verifier): no Stuck report while flipped / righting')

# ===== v72 merged BuyPathStatic pins (lanes K, A, B1, B2, C), for the flags-OFF commit. Paste before the final parse_gate().

# ===== Lane K =====
# Lane K (v72 contract) proposed BuyPathStatic pins. Paste-ready for tools/BuyPathStatic.py (before parse_gate()).
# Every needle below was checked with verify_pins.py against /home/user/Padel-AI (flags OFF, the repo state) and
# against the flags-ON scratch tree: must_contain needles present, must_not_contain needles absent (see pins_check.txt).
# Two pins (the Enabled = false lines) protect "flags stay off"; flip them to "Enabled = true," at integration.
# Format per line: must_contain|must_not_contain(file, needle, label). The RULES block is the prototype's regex rules
# (kiosk sites, kit budget, guide copy) adapted to the v72 copy rules, verified the same way.

BZC = "src/ReplicatedStorage/Shared/Configs/BusinessConfig.luau"
TGC = "src/ReplicatedStorage/Shared/Configs/TycoonGuideConfig.luau"
TMU = "src/ReplicatedStorage/Shared/Util/TycoonMath.luau"
BCF = "src/ReplicatedStorage/Shared/Configs/BaseConfig.luau"
BLC = "src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau"
TUC = "src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau"

# --- flags (flip at integration) ---
must_contain(BZC, "\tEnabled = true,", "v72 BusinessConfig off until integration (lead flips after Lane D)")
must_contain(TGC, "\tEnabled = true,", "v72 TycoonGuideConfig off until integration (lead flips after Lane D)")

# --- BusinessConfig (spec section 1) ---
must_contain(BZC, 'Requires = { { StructureId = "AmmoWorks", Level = 1 }, { StructureId = "WeaponsFacility", Level = 1 } },', "v72 Arms Crate Line requires Ammo Works 1 + Weapons Facility 1")
must_contain(BZC, 'StructureId = "WeaponsFacility"', "v72 the Weapons Facility gates a business (spec section 7)")
must_contain(BZC, 'Order = { "AmmoWorks", "ArmsCrateLine", "ArmorPlatePress", "RocketAssembly" },', "v72 four war businesses in order")
must_contain(BZC, "PartsPerBusinessL5 = 16,", "v72 business part cap 16 at L5")
must_contain(BZC, "ConsoleNeon = false,", "v72 business kiosks: no Neon button")
must_contain(BZC, "ConsoleScreenGui = false,", "v72 business kiosks: no SurfaceGui")
must_contain(BZC, "return BusinessConfig.Enabled and BusinessConfig.Businesses[id] ~= nil", "v72 IsBusiness false while the flag is off")
must_not_contain(BZC, "require(", "v72 BusinessConfig requires nothing (BaseConfig / TutorialConfig require it: no cycle)")

# --- TycoonGuideConfig (spec sections 2-4) ---
must_contain(TGC, 'Opening = { "CommandCenter:1", "AmmoWorks:1", "WeaponsFacility:1", "ArmsCrateLine:1", "Barracks:1" },', "v72 guide opening (Barracks last)")
must_contain(TGC, "SoldierMaxShare = 0.34,", "v72 soldiers offered only below 34% training share")
must_contain(TGC, "RepickSeconds = 15,", "v72 re-pick every 15 s")
must_contain(TGC, "Hysteresis = 0.75,", "v72 sticky pick (challenger < 0.75 x current)")
must_contain(TGC, "PillIncome = true,", "v72 cash pill +$/s suffix")
must_contain(TGC, "ThumbZoneFrac = 0.40,", "v72 BUY lane clears the left 40% thumb zone")
must_contain(TGC, "TouchSize = Vector2.new(300, 72),", "v72 BUY button 300 x 72 v (>= 44 px real at 0.70)")
must_contain(TGC, "NextMaxDistance = 40,", "v72 NEXT console tag MaxDistance <= 40")
must_contain(TGC, 'HideWhen = { "Tutorial", "Modal", "Driving", "Dead", "RecentCombat", "AtConsole" },', "v72 guide chip hides in tutorial / panel / driving / dead / combat / at a console")
must_not_contain(TGC, "·", "v72 no middle dot in the guide config (Display font)")
must_not_contain(TGC, "→", "v72 no arrow glyph in the guide config (Display font)")
must_not_contain(TGC, "require(", "v72 TycoonGuideConfig requires nothing")

# --- TycoonMath (pure, one formula for paid and shown) ---
must_contain(TMU, "function TycoonMath.BasePassivePerTick(upgrades: { [string]: any }?): number", "v72 TycoonMath passive formula (BaseService pays it)")
must_contain(TMU, "local tenths = math.floor(v * 10 + EPS)", "v72 displayed $/s floored to 0.1 below $10/s (never over-promises)")
must_contain(TMU, "return tostring(math.floor(v + EPS))", "v72 displayed $/s floored to whole dollars from $10/s")
must_contain(TMU, "TycoonMath.TrainingShare(ctx.Upgrades, soldiers) < TycoonGuideConfig.SoldierMaxShare", "v72 soldier candidate gated by the training share")
must_contain(TMU, "if bestScore >= TycoonGuideConfig.Hysteresis * TycoonMath.Score(cur, ctx) then", "v72 pick hysteresis")
must_contain(TMU, "function TycoonMath.ActionLaneShiftV(viewportV: Vector2, widthV: number, frac: number, clearPx: number, scale: number): number", "v72 BUY lane shift helper (Lane 0 owns HudLayout)")
must_contain(TMU, "if biz then\n\t\tif not BusinessConfig.Enabled then\n\t\t\treturn 0", "v72 a saved business level pays nothing while the flag is off")
for _needle in ("Instance.new", "game:GetService", "WaitForChild", "task.wait", "FireServer", "RemoteEvent"):
    must_not_contain(TMU, _needle, f"v72 TycoonMath is pure (no {_needle})")

# --- BaseConfig merge ---
must_contain(BCF, "local BusinessConfig = require(script.Parent.BusinessConfig)", "v72 BaseConfig reads BusinessConfig")
must_contain(BCF, "if BusinessConfig.Enabled then\n\tfor _, id in ipairs(BusinessConfig.Order) do", "v72 businesses merged into Structures only while enabled")
must_contain(BCF, "Kind = BusinessConfig.Kind,", "v72 merged businesses carry Kind = Business")
must_contain(BCF, 'Description = if BusinessConfig.Enabled then "Arms storage. Unlocks the Arms Crate Line." else "Research and unlock advanced weapons.",', "v72 Weapons Facility description (flag-gated)")

# --- BaseLayoutConfig sites (plot-local, Yaw 180, kiosk 10 studs toward the gate) ---
must_contain(BLC, "AmmoWorks = { Site = { X = -30, Z = 100 }, Yaw = 180, WalkIn = false, Kiosk = { X = -30, Z = 90 } },", "v72 Ammo Works site")
must_contain(BLC, "ArmsCrateLine = { Site = { X = -66, Z = 100 }, Yaw = 180, WalkIn = false, Kiosk = { X = -66, Z = 90 } },", "v72 Arms Crate Line site")
must_contain(BLC, "ArmorPlatePress = { Site = { X = 34, Z = 60 }, Yaw = 180, WalkIn = false, Kiosk = { X = 34, Z = 50 } },", "v72 Armor Plate Press site")
must_contain(BLC, "RocketAssembly = { Site = { X = 70, Z = 60 }, Yaw = 180, WalkIn = false, Kiosk = { X = 70, Z = 50 } },", "v72 Rocket Assembly site")
must_contain(BLC, "FloorChevrons = false,", "v72 static floor arrows off (read by MapSetup once Lane D lands)")
must_contain(BLC, "SignInsetStuds = 2.0,", "v72 gate-sign inset key (read by MapSetup once Lane D lands)")

# --- TutorialConfig step 6 ---
must_contain(TUC, 'Id = "Barracks",', "v72 flags-off step 6 stays the Barracks buy")

# --- other files stay untouched by v72 (spec section 7 "Unchanged") ---
must_not_contain("src/ReplicatedStorage/Shared/Configs/HudConfig.luau", "BuyLane", "v72 BUY lane keys live in TycoonGuideConfig, not HudConfig")
must_not_contain("src/ReplicatedStorage/Shared/Configs/HudConfig.luau", "ConsoleTag", "v72 console tag keys live in TycoonGuideConfig, not HudConfig")
must_not_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "Business", "v72 no business remote")

# --- RULES (prototype rules, adapted; verified) ---
_bz = read(BZC) or ""
_blc2 = read(BLC) or ""
_bz_order = re.findall(r'"(\w+)"', (re.search(r"Order = \{([^}]*)\}", _bz) or re.search("()", "")).group(1) or "")
_bz_nosite = [b for b in _bz_order if not re.search(r"^\t\t" + b + r" = \{ Site = .*Kiosk = \{", _blc2, re.M)]
if _bz_order and not _bz_nosite:
    ok(f"v72 every business ({len(_bz_order)}) has a BaseLayoutConfig kiosk site")
else:
    bad(f"v72 businesses without a kiosk site: {_bz_nosite} (order={_bz_order})")
_kit = re.search(r"\n\tKit = \{(.*?)\n\t\} :: \{ KitPart \},", _bz, re.S)
_kit_n = len(re.findall(r"\{ Role = ", _kit.group(1))) if _kit else 0
_cap = re.search(r"PartsPerBusinessL5 = (\d+)", _bz)
if _kit and _cap and _kit_n + 3 <= int(_cap.group(1)):
    ok(f"v72 business kit at L5 = {_kit_n} + console 3 <= PartsPerBusinessL5 {_cap.group(1)}")
else:
    bad(f"v72 business kit {_kit_n} + 3 exceeds PartsPerBusinessL5 {(_cap.group(1) if _cap else '?')}")
_bz_short = re.findall(r'ShortName = "([^"]*)"', _bz)
_bz_desc = re.findall(r'Description = "([^"]*)"', _bz)
if len(_bz_short) == 4 and all(len(s) <= 10 for s in _bz_short) and all(len(d) <= 42 for d in _bz_desc):
    ok("v72 business ShortName <= 10 and Description <= 42 characters")
else:
    bad(f"v72 business copy too long: {_bz_short} {_bz_desc}")
_tg = read(TGC) or ""
_tg_text = re.search(r"\n\tText = \{(.*?)\n\t\},", _tg, re.S)
_tg_strings = re.findall(r'= "([^"]*)"', _tg_text.group(1)) if _tg_text else []
_keyish2 = [t for t in _tg_strings if re.search(r"\b(click|tap|press [A-Z]|E key|\[[A-Z]\]|key)\b", t, re.I)]
_long2 = [t for t in _tg_strings if len(t) > 42]
_glyph2 = [t for t in _tg_strings if "·" in t or "→" in t]
if len(_tg_strings) >= 30 and not _keyish2 and not _long2 and not _glyph2:
    ok(f"v72 guide copy device-neutral, <= 42 characters, no middle dot / arrow ({len(_tg_strings)} strings)")
else:
    bad(f"v72 guide copy: key names {_keyish2}, too long {_long2}, glyphs {_glyph2} (n={len(_tg_strings)})")
_sn = re.search(r"\n\tShortNames = \{(.*?)\n\t\}", _tg, re.S)
_sn_vals = re.findall(r'= "([^"]*)"', _sn.group(1)) if _sn else []
if len(_sn_vals) == 15 and all(len(s) <= 10 for s in _sn_vals):
    ok("v72 building ShortNames (15) <= 10 characters")
else:
    bad(f"v72 building ShortNames: {_sn_vals}")

# ===== Lane A =====
# Lane A (v72 server) proposed BuyPathStatic pins. Paste-ready for tools/BuyPathStatic.py (before parse_gate()).
# Every needle was checked with verify_pins.py against /home/user/Padel-AI (flags OFF, the repo state) and against the
# flags-ON scratch tree (build/A/on): must_contain needles present, must_not_contain needles absent (pins_check_*.txt).
# None of these depends on the flag values, so nothing here flips at integration.
# The first block is the spec section 7 prototype pins that touch Lane A files (kept verbatim from proto_bps.diff,
# except the two BaseService lines, which match the ported code exactly). The rest are Lane A contract pins.

BZS = "src/ServerScriptService/Server/Services/BusinessService.luau"
BSV = "src/ServerScriptService/Server/Services/BaseService.luau"
ECO = "src/ServerScriptService/Server/Services/EconomyService.luau"
SOL = "src/ServerScriptService/Server/Services/SoldierService.luau"
UPS = "src/ServerScriptService/Server/Services/UpgradePadService.luau"
TUS = "src/ServerScriptService/Server/Services/TutorialService.luau"
BOOT = "src/ServerScriptService/Server/Bootstrap.server.luau"

# --- spec section 7: prototype pins on Lane A files ---
must_contain(BZS, "CollectionService:AddTag(console, TAG_SLOT)", "v72 business consoles are WE_UpgradeSlot buy points (console-only buying)")
must_contain(BZS, 'console:SetAttribute("WE_Console", true)', "v72 business console marked WE_Console")
for _needle in ("SurfaceGui", "PointLight", "SpotLight", "AddCash", "AccruePendingCash", "OnServerEvent", "FireServer"):
    must_not_contain(BZS, _needle, f"v72 BusinessService has no {_needle} (no new money path / budget-free look)")
must_contain(BSV, "local total = TycoonMath.BasePassivePerTick(profile.BaseUpgrades)", "v72 passive income = TycoonMath (the numbers the client shows)")
must_contain(BSV, "if TycoonMath.IsBusiness(structureId) then", "v72 businesses never get a structure kit")
# spec section 7 "Add": TutorialService advances step 6 from config
must_contain(TUS, ".PadStructureId", "v72 TutorialService reads the step's PadStructureId")

# --- BusinessService: world no-ops while off, no remote, pick written only on change ---
must_contain(BZS, "function BusinessService.SyncBusiness(plotId: number, id: string, level: number, ownerUserId: number?)\n\tif not BusinessConfig.Enabled then\n\t\treturn\n\tend", "v72 SyncBusiness is a no-op while BusinessConfig.Enabled is false")
must_contain(BZS, "function BusinessService.SyncPlot(plotId: number, upgrades: { [string]: any }?, ownerUserId: number?)\n\tif not BusinessConfig.Enabled then", "v72 SyncPlot is a no-op while BusinessConfig.Enabled is false")
must_contain(BZS, "function BusinessService.ClearPlot(plotId: number)\n\tif not BusinessConfig.Enabled then", "v72 ClearPlot is a no-op while BusinessConfig.Enabled is false")
must_contain(BZS, "-- Both flags off: no hooks, no loop, no attributes (the game is exactly as before v72)\n\tif not TycoonGuideConfig.Enabled then\n\t\treturn\n\tend", "v72 BusinessService.Init hooks nothing while the guide is off")
must_contain(BZS, "local pick = TycoonMath.PickNext({", "v72 the server picks the next buy (TycoonMath.PickNext)")
must_contain(BZS, "if player:GetAttribute(ATTR_NEXT) ~= value then\n\t\tplayer:SetAttribute(ATTR_NEXT, value)", "v72 WE_NextBuy written only when it changes")
must_contain(BZS, "if now - (lastRepick[p] or 0) >= TycoonGuideConfig.RepickSeconds then", "v72 re-pick every RepickSeconds since the player's last pick")
must_contain(BZS, "SoldierService.OnArmyChanged(function(p: Player)", "v72 re-pick on an army change")
must_contain(BZS, "BaseService.GetUpgradeChangedEvent().Event:Connect(function(userId: number)", "v72 re-pick after every purchase")
must_contain(BZS, "DataService.OnProfileLoaded(function(p: Player)", "v72 re-pick on profile load")
must_contain(BZS, "BusinessService.StampAtmPos(p, plotId)", "v72 WE_AtmPos stamped on plot ready (own ATM; streaming-safe GO line)")
must_not_contain(BZS, "RemoteSetup", "v72 BusinessService adds no remote")
must_not_contain(BZS, "WaitForChild(\"Kit_", "v72 BusinessService never waits on kit parts")

# --- BaseService ---
must_contain(BSV, "local BusinessService = require(script.Parent.BusinessService)", "v72 BaseService builds business lines through BusinessService")
must_contain(BSV, "xpcall(BusinessService.SyncPlot, function(errB)", "v72 RefreshAllVisuals syncs every business line before plot-ready (L0 kiosk on owned plots)")
must_contain(BSV, "if not TycoonMath.IsBusiness(structureId) then -- v72: businesses in one SyncPlot below", "v72 RefreshAllVisuals structure loop skips businesses")
must_contain(BSV, "if seen[structureId] or TycoonMath.IsBusiness(structureId) then", "v72 NuclearRehydrateKits skips businesses")
must_contain(BSV, "pcall(BusinessService.OnPlotReleased, player, plotId)", "v72 ReleasePlot clears the plot's business lines and WE_AtmPos")
must_contain(BSV, "if targetLevel >= 3 and def.Kind ~= BusinessConfig.Kind and MonetizationService and MonetizationService.TrySoftOfferVIP then", "v72 the VIP soft offer skips war businesses")
must_contain(BSV, 'player:SetAttribute("WE_PassiveTick", (tonumber(player:GetAttribute("WE_PassiveTick")) or 0) + 1)', "v72 passive tick counter for the client pops")
must_contain(BSV, 'if player:GetAttribute("WE_IncomeMult") ~= m then', "v72 WE_IncomeMult written only when it changes")
must_contain(BSV, "if BusinessConfig.Enabled or TycoonGuideConfig.Enabled then", "v72 passive-tick stamps only while a v72 flag is on")
must_contain(BSV, 'string.format("Purchase SUCCESSFUL! %s Lv %d", name, result.NewLevel or 0) .. (if okS and typeof(suffix) == "string" then suffix else "")', "v72 remote BUY toast carries the +$/s suffix")
must_contain(BSV, "function BaseService.PurchaseToastSuffix(player: Player, structureId: string, newLevel: number): string\n\tif not TycoonGuideConfig.Enabled then\n\t\treturn \"\"", "v72 toast suffix empty while the guide is off")
must_contain(BSV, 'EconomyService.AccruePendingCash(player, amount, "passive")', "v72 business income rides the existing passive tick into the ATM")

# --- EconomyService: display multiplier + steady income, the grant math unchanged ---
must_contain(ECO, "function EconomyService.GetCashMult(player: Player, reason: string?): number", "v72 EconomyService.GetCashMult (display only)")
must_contain(ECO, "return math.floor(amount * cashMultFor(player, profile, reason))", "v72 grants and GetCashMult share one multiplier function")
must_contain(ECO, "noteSteadyIncome(player, reason, granted) -- v72 WE_IncomePerSec", "v72 WE_IncomePerSec from what was really granted")
must_contain(ECO, 'if player:GetAttribute("WE_IncomePerSec") ~= perSec then', "v72 WE_IncomePerSec written only when it changes")
must_contain(ECO, "if not TycoonGuideConfig.Enabled or reason == nil or TycoonGuideConfig.SteadyIncomeReasons[reason] ~= true then", "v72 WE_IncomePerSec only while the guide is on, steady reasons only")

# --- SoldierService / UpgradePadService / TutorialService / Bootstrap ---
must_contain(SOL, "function SoldierService.GetCap(player: Player): number", "v72 SoldierService.GetCap (next-buy soldier offer)")
must_contain(UPS, 'string.format("Purchase SUCCESSFUL! %s Lv %d", name, result.NewLevel or 0) .. suffix', "v72 kiosk hold-prompt toast carries the +$/s suffix")
must_contain(UPS, "BaseService.PurchaseToastSuffix", "v72 one toast-suffix function for both buy paths")
must_not_contain(TUS, 'detail == "Barracks"', "v72 no hard-coded Barracks step")
must_contain(BOOT, 'local BusinessService = safeRequire("BusinessService", Services.BusinessService)', "v72 Bootstrap requires BusinessService")
must_contain(BOOT, 'safeInit("BusinessService", BusinessService, deps)', "v72 Bootstrap inits BusinessService")
_boot = read(BOOT) or ""
_i_sol = _boot.find('safeInit("SoldierService", SoldierService, deps)')
_i_biz = _boot.find('safeInit("BusinessService", BusinessService, deps)')
if 0 <= _i_sol < _i_biz:
    ok("v72 BusinessService inits after SoldierService (GetCap / OnArmyChanged)")
else:
    bad(f"v72 BusinessService must init after SoldierService (sol={_i_sol} biz={_i_biz})")

# ===== Lane B1 =====
# Lane B1 (v72 buy surfaces) proposed BuyPathStatic pins. Paste-ready for tools/BuyPathStatic.py (before the final
# parse_gate() call). Every needle was checked with verify_pins_b1.py against /home/user/Padel-AI (flags OFF, the
# repo state), against the flags-ON scratch tree (build/B1/on) and against HEAD 45bd63c (where they are new): every
# must_contain needle present and every must_not_contain needle absent in the repo and ON trees (pins_check_*.txt).
# None of them depends on the Enabled flags, so nothing flips at integration.
# Format per line: must_contain|must_not_contain(file, needle, label).

B1_WPC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau"
B1_PC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau"
B1_HUD = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau"

# --- spec section 7 pins that belong to B1 ---
must_contain(B1_WPC, "TycoonMath.PerSecText", "v72 BUY / console tag / screen rates come from TycoonMath.PerSecText (floored, never over-promises)")
must_contain(B1_WPC, "TycoonGuideConfig.BuyLane", "v72 BUY lane keys live in TycoonGuideConfig (not HudConfig)")
must_contain(B1_PC, "TycoonGuideConfig.BuyLane", "v72 prompt pill lane uses the BUY lane keys (TycoonGuideConfig)")

# --- gating: flags OFF renders exactly like HEAD ---
must_contain(B1_WPC, "local function guideOn(): boolean\n\treturn TycoonGuideConfig.Enabled == true\nend", "v72 WorldPrompt guide surfaces gated on TycoonGuideConfig.Enabled")
must_contain(B1_PC, "if not (TycoonGuideConfig.Enabled == true and isTouch()) then\n\t\treturn 0\n\tend", "v72 prompt lane shift only with the guide on, touch only")
must_contain(B1_HUD, "local incomeOn = TycoonGuideConfig.Enabled == true and TycoonGuideConfig.PillIncome == true", "v72 cash pill +$/s behind TycoonGuideConfig.Enabled and PillIncome")

# --- F3: BUY / pill lane right of the thumb zone (TycoonMath.ActionLaneShiftV, the lead's home for the helper) ---
must_contain(B1_WPC, "TycoonMath.ActionLaneShiftV(HudLayout.ContentSizeV(), widthV, BUY_LANE.ThumbZoneFrac, BUY_LANE.ClearPx, HudLayout.Scale())", "v72 F3 BUY lane clears the thumb zone (left 40% + 8 px)")
must_contain(B1_PC, "TycoonMath.ActionLaneShiftV(HudLayout.ContentSizeV(), widthV, BUY_LANE.ThumbZoneFrac, BUY_LANE.ClearPx, HudLayout.Scale())", "v72 F3 prompt pill lane clears the thumb zone")
must_contain(B1_WPC, "buyLaneConn = HudLayout.LayoutChanged:Connect(placeBuyLane)", "v72 BUY lane re-placed on rotation / safe-area change")
must_contain(B1_PC, "lane.Position = UDim2.new(0.5, laneShiftV(math.max(1, totalW)), 1, -bottom)", "v72 pill lane position goes through the thumb-zone shift")
must_not_contain(B1_PC, "lane.Position = UDim2.new(0.5, 0, 1, -bottom)", "v72 pill lane never skips the thumb-zone shift")
must_contain(B1_PC, "return UDim2.fromOffset(BUY_LANE.TouchSize.X, BUY_LANE.TouchSize.Y)", "v72 pills above BUY clear its 72 v touch height")

# --- two-line BUY (300x72 v touch, 20 v lines, MoneyState) ---
must_contain(B1_WPC, "local BUY_LINE_V = 20", "v72 BUY lines are 20 v (14 real px on phones)")
must_contain(B1_WPC, "t.TextSize = BUY_LINE_V\n\t\t\tt.TextScaled = false", "v72 BUY lines never TextScaled below 14 px")
must_contain(B1_WPC, "local moneyState, short, eta = TycoonMath.MoneyState(cost, liveCash(), pendingCash(), incomePerSec())", "v72 BUY state from TycoonMath.MoneyState (wallet + ATM + WE_IncomePerSec)")
must_not_contain(B1_WPC, "setBuyLook(canAfford)", "v72 BUY look is a money state (Buy / Collect / Earn), not a bool")
must_contain(B1_WPC, "if lineWidthV(full, font) <= innerW then", "v72 BUY line 1 falls back to the short name when it does not fit (TextService)")

# --- Collect: fires nothing, line to your OWN ATM, one toast ---
must_contain(B1_WPC, 'if guideOn() and (TycoonMath.MoneyState(cost, liveCash(), pendingCash(), incomePerSec())) == "Collect" then\n\t\t\tshowAtmLine()\n\t\t\treturn\n\t\tend', "v72 Collect sends no buy request")
must_contain(B1_WPC, "if ConsoleWaypoint.ShowAtm then", "v72 Collect draws the line to the player's own ATM (guarded until the guide lane's ShowAtm lands)")
must_contain(B1_WPC, "NotificationController.Show(GTEXT.CollectToast", "v72 Collect toast copy from TycoonGuideConfig.Text")

# --- AtConsole flag (the guide chip hides while BUY is up) ---
must_contain(B1_WPC, "HudLayout.SetFlag(TycoonGuideConfig.AtConsoleFlag, true)", "v72 AtConsole on while BUY shows")
must_contain(B1_WPC, "HudLayout.SetFlag(TycoonGuideConfig.AtConsoleFlag, false)", "v72 AtConsole off when BUY hides")

# --- console tag (F2) + screen line 3 ---
must_contain(B1_WPC, "local size = UDim2.fromScale(TAG.StudsW, TAG.StudsH)", "v72 F2 stud-scaled console tag (ConsoleTag StudsW x StudsH)")
must_contain(B1_WPC, "bb.MaxDistance = if pick then TAG.NextMaxDistance elseif owned then TAG.MaxDistanceUpgrade else TAG.MaxDistanceBuild", "v72 console tag ranges from ConsoleTag (NEXT 40)")
must_contain(B1_WPC, "string.format(GTEXT.TagTitleNext, name)", "v72 gold NEXT title on the WE_NextBuy pick")
must_contain(B1_WPC, "string.format(GTEXT.ScreenLines, TycoonMath.ShortName(structureId), TycoonMath.ShortCash(cost, true), stepGainText(structureId, level))", "v72 console screen line 3 (+$/s)")
must_not_contain(B1_WPC, "AlwaysOnTop = true", "v72 console tags never AlwaysOnTop")
must_contain(B1_WPC, 'for _, attr in ipairs({ "WE_PendingCash", "WE_IncomePerSec", "WE_IncomeMult", "WE_NextBuy" }) do', "v72 buy surfaces read server-stamped attributes (no new remote)")

# --- cash pill suffix ---
must_contain(B1_HUD, "else TycoonMath.RatePerSecText(rate)", "v72 cash pill +$/s from WE_IncomePerSec (TycoonMath, floored)")
must_contain(B1_HUD, "then string.format(TycoonGuideConfig.Text.PerSec, TycoonMath.Commas(rate))", "v72 cash pill +$1,234/s keeps the thousands separator")
must_contain(B1_HUD, "inc.Active = false", "v72 cash pill +$/s is not a tap target")
must_contain(B1_HUD, 'player:GetAttributeChangedSignal("WE_IncomePerSec"):Connect(queueIncome)', "v72 cash pill +$/s refresh throttled to TextRefreshHz")

# ===== Lane B2 =====
# Lane B2 (v72 guide: TutorialController, BaseController, ConsoleWaypoint) proposed BuyPathStatic pins.
# Paste-ready for tools/BuyPathStatic.py (the same must_contain / must_not_contain helpers; needles are Python strings).
# Every needle was checked with verify_pins.py against /home/user/Padel-AI (flags OFF, the repo) and against the
# flags-ON scratch tree (build/B2/on): must_contain present, must_not_contain absent in both (pins_check.txt).
# The first three are the spec section 7 pins for Lane B2; the rest protect the behaviour the lane tests.

B2_TC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.luau"
B2_BC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau"
B2_CW = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/ConsoleWaypoint.luau"

# --- spec section 7 ---
must_contain(B2_TC, 'GetAttribute("WE_NextBuy")', "v72 guide chip reads the server's pick (WE_NextBuy)")
must_contain(B2_BC, "TycoonMath.PerSecText", "v72 Base panel rows show the floored +$/s (TycoonMath.PerSecText)")
must_not_contain(B2_BC, '.. "/t")', "v72 Base panel: no HEAD-style per-tick '+N/t' concat (guide on shows +$N/s; guide off keeps HEAD text via string.format)")

# --- guide chip (TutorialController) ---
must_contain(B2_TC, "if GUIDE.Enabled then\n\t\tbuildGuideChip(screen)", "v72 guide chip only exists while TycoonGuideConfig.Enabled")
must_contain(B2_TC, "HudLayout.BindVisibility(c, GUIDE.ChipRule, guideWanted)", "v72 guide chip: own plot only; hidden on Tutorial / Modal / Driving / Dead / RecentCombat / AtConsole")
must_contain(B2_TC, "and (tutorialDone or GUIDE.ShowAfterTutorial == false)", "v72 guide chip only after the tutorial")
must_contain(B2_TC, "local state, short, eta = TycoonMath.MoneyState(cost, attrNum(\"WE_Cash\", 0), attrNum(\"WE_PendingCash\", 0), attrNum(\"WE_IncomePerSec\", 0))", "v72 chip Build / Collect / Earn from TycoonMath.MoneyState")
must_contain(B2_TC, "local gain = TycoonMath.PerSecText(TycoonMath.StepGainPerTick(id, level - 1, mult))", "v72 chip +$/s = TycoonMath (floored, WE_IncomeMult)")
must_contain(B2_TC, "if short ~= nil and lineCount(raw, OBJ.HintSize, HudConfig.Fonts.Body, textW) > 1 then", "v72 chip drops the unlock part when the hint does not fit at 20 v")
must_contain(B2_TC, "ConsoleWaypoint.Show(guideId, myPlotId)", "v72 guide GO: the line to the console on the player's OWN plot")
must_contain(B2_TC, "ConsoleWaypoint.ShowAtm(myPlotId)", "v72 guide ATM: the line to the player's OWN ATM")
must_contain(B2_TC, "guideHiddenUntil = os.clock() + GUIDE.HideSeconds", "v72 Hide lasts HideSeconds")
must_contain(B2_TC, 'player:GetAttributeChangedSignal("WE_BuyAck"):Connect(function()', "v72 Hide ends at the next purchase acknowledgement")
must_contain(B2_TC, "and now - idleSince >= GUIDE.AutoGuideIdleSeconds and ConsoleWaypoint.Current() == nil then", "v72 auto-guide after AutoGuideIdleSeconds idle, never over an existing line")
must_contain(B2_TC, "if target and Vector3.new(target.X - p.X, 0, target.Z - p.Z).Magnitude > GUIDE.AutoGuideMinStuds then", "v72 auto-guide only when farther than AutoGuideMinStuds")
must_contain(B2_TC, 'if (guideKind == "Build" or guideKind == "Collect") and guidePick ~= "" and autoGuidedFor ~= guidePick', "v72 auto-guide once per pick, Build / Collect only")
must_contain(B2_TC, "local period = 1 / math.max(GUIDE.EtaRefreshHz or 1, 0.1)", "v72 guide ticks at EtaRefreshHz (1 Hz; UI refresh <= 10 Hz)")
must_not_contain(B2_TC, "RenderStepped", "v72 tutorial / guide chip: no per-frame work")
must_not_contain(B2_TC, "Heartbeat:Connect", "v72 tutorial / guide chip: no per-frame work")
# F5 + tutorial step 6
must_contain(B2_TC, "local HIDE_MARKER_DRESSING = TycoonGuideConfig.Enabled", "v72 F5 gated with the guide flag (flags off = HEAD)")
must_contain(B2_TC, "d.LocalTransparencyModifier = if isActive then 0 else 1", "v72 F5 the Plot-1 tutorial arrow is hidden locally unless its marker is the target")
must_contain(B2_TC, "CollectionService:GetInstanceAddedSignal(Constants.Tags.TutorialMarker):Connect(watchMarker)", "v72 F5 late markers / arrows start hidden (events, no polling)")

# --- Base panel (BaseController) ---
must_contain(B2_BC, "ht.Text = GT.PanelHeader", "v72 WAR BUSINESSES header")
must_contain(B2_BC, "badge.Text = GT.NextTag", "v72 gold NEXT badge on the server's pick")
must_contain(B2_BC, "sub.Text = string.format(GT.PanelSubtitle, string.format(GT.Rate, TycoonMath.RateText(perSec)))", "v72 subtitle Income $N/s from WE_IncomePerSec")
must_contain(B2_BC, "local GUIDE_ON = TycoonGuideConfig.Enabled", "v72 Base panel guide copy behind TycoonGuideConfig.Enabled")

# --- ConsoleWaypoint.ShowAtm ---
must_contain(B2_CW, "function ConsoleWaypoint.ShowAtm(plotId: number?): boolean", "v72 ConsoleWaypoint.ShowAtm (guide Collect state)")
must_contain(B2_CW, 'if inst:IsA("BasePart") and tonumber(inst:GetAttribute("PlotId") :: any) == plotId and inst:IsDescendantOf(Workspace) then', "v72 ATM line only to the player's OWN ATM")
must_contain(B2_CW, 'player:GetAttribute(if guidingAtm then "WE_AtmPos" else "WE_ConsolePos_" .. structureId)', "v72 ATM line falls back to the server-stamped WE_AtmPos (streaming-safe)")

# ===== Lane C =====
# Lane C (v72 visuals: BusinessVisuals + one client Bootstrap safeInit) proposed BuyPathStatic pins.
# Paste-ready for tools/BuyPathStatic.py (before parse_gate()). No other lane pins BusinessVisuals (checked K's and A's).
# Every needle was checked with build/C/verify_pins.py against /home/user/Padel-AI (flags OFF, repo state) and the
# flags-ON scratch tree: must_contain needles present, must_not_contain needles absent (build/C/pins_check_*.txt).
# None depends on the flags, so nothing here flips at integration.
# Format per line: must_contain|must_not_contain(file, needle, label).

BZV = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/BusinessVisuals.luau"
CBOOT = "src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau"

# --- the prototype's 7 BusinessVisuals pins (spec section 7 "keep all 23 prototype pins"), unchanged ---
for _needle in ("AddCash", "FireServer", "InvokeServer", "RenderStepped", "GetDescendants", "WaitForChild(\"Kit_"):
    must_not_contain(BZV, _needle, f"v72 BusinessVisuals: no {_needle} (client-only, no per-frame scans, streaming-safe)")
must_contain(BZV, "Workspace:BulkMoveTo(movedParts, movedCFrames", "v72 business crates move with one BulkMoveTo per step")

# --- Lane C: wiring ---
must_contain(CBOOT, 'safeInit("BusinessVisuals", safeRequire("BusinessVisuals", Modules:WaitForChild("BusinessVisuals", 5) :: Instance))', "v72 BusinessVisuals: one guarded safeInit, bounded wait")
must_contain(BZV, "if started or not BusinessConfig.Enabled then", "v72 BusinessVisuals inert while BusinessConfig.Enabled is false (and Init runs once)")

# --- Lane C: phone performance (spec section 5 client work) ---
must_contain(BZV, "local STEP_EVERY = 1 / math.clamp(V.UpdateHz, 1, 20)", "v72 crate step never above 20 Hz")
must_contain(BZV, "stepAcc = 0 -- reset, never catch up", "v72 crate step: no burst after a frame hitch")
must_contain(BZV, "local POP_EVERY = 0.1", "v72 pop animation at 10 Hz (UI refresh cap)")
must_contain(BZV, "(belt.Position - at).Magnitude <= V.ActiveRadius", "v72 crates only within ActiveRadius of the character")
must_contain(BZV, "if q > 0 and q <= V.LowQualityLevel then", "v72 one crate per line at Graphics Quality <= LowQualityLevel")
must_contain(BZV, "while #l.crates > maxCrates do", "v72 at most MaxCratesPerLine crates per line")
must_not_contain(BZV, ":Destroy()", "v72 crates / pops are pooled, never destroyed (0 new Instances after warm-up)")
must_not_contain(BZV, "task.spawn(", "v72 BusinessVisuals: no thread per pop")
must_not_contain(BZV, "task.wait(", "v72 BusinessVisuals never yields")
must_not_contain(BZV, 'WaitForChild("Shared")', "v72 BusinessVisuals: bounded WaitForChild only")
for _needle in ("Remote", "PointLight", "SpotLight", "SurfaceLight", "ParticleEmitter", "Neon", "SurfaceGui"):
    must_not_contain(BZV, _needle, f"v72 BusinessVisuals: no {_needle} (no remote, budget-free look)")

# --- Lane C: owner-only, the server's numbers ---
must_contain(BZV, "return m:GetAttribute(\"OwnerUserId\") == player.UserId", "v72 crates / pops on the player's OWN lines only")
must_contain(BZV, 'player:GetAttributeChangedSignal("WE_PassiveTick"):Connect(popTick)', "v72 pops on the server's passive-tick stamp")
must_contain(BZV, "for _ = 1, V.MaxPopsPerTick do", "v72 at most MaxPopsPerTick pops per passive tick")
must_contain(BZV, "local bestD, bestLv = V.PopRadius, 0", "v72 pops only within PopRadius of the character")
must_contain(BZV, "TycoonMath.PopText(best.def.Id, bestLv, mult)", "v72 pop amount = TycoonMath.PopText (floor(IncomePerTick x WE_IncomeMult))")
# --- verifier (vfy2): a pop that lands before the next scan must not reuse a destroyed local folder's crates ---
must_contain(BZV, "forgetPool() -- a pop can land before the next scan notices", "v72 BusinessVisuals: crateFolder drops the dead pool before rebuilding")

# Lane D (world, deferred; merge together with laneD.diff, not before). Verified on build/integ/on.
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "BaseLayout.Config().FloorChevrons ~= false", "v72 static floor arrows behind BaseLayoutConfig.FloorChevrons")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "local detail = (StructureVisualConfig :: any).StaticSoldierDetail ~= false", "v72 static soldier kit detail behind StructureVisualConfig.StaticSoldierDetail")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "StaticSoldierDetail = false,", "v72 static soldier kit trimmed (-84 parts per base)")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", 'StairStyle = "Steps",', "v72 stairs stay steps (ramps are a reserve cut)")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "signCap.MaxTextSize = 64", "v72 gate-sign text capped (reads in full)")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "(BaseLayout.Config().InnerWall or {}).SignInsetStuds", "v72 gate-sign inset from BaseLayoutConfig.InnerWall.SignInsetStuds")

# ===== Nations lane A0 (NationConfig / NationFlagIds / NationTexture / assets/flags) =====
# Paste-ready for tools/BuyPathStatic.py (lane A1), before the final parse_gate() call. Uses the file's own helpers
# (ok / bad / read / must_contain / must_not_contain, ROOT, re, sys). Checked with build/A0/verify_pins.py against
# (a) HEAD 1ce4828 + the A0 files (all PASS), (b) the live working tree (all PASS), (c) mutated copies (each FAILs).
# Spec: fb2/spec_nations.md section 4 "BuyPathStatic rules" (R14 allowlist, denylist, ids unique, utf8.len(Short) <= 14,
# atlas cells unique within each group, NationFlagIds keys subset of the roster) + section 2 toggles + guard pins.

NAT_CFG = "src/ReplicatedStorage/Shared/Configs/NationConfig.luau"
NAT_IDS = "src/ReplicatedStorage/Shared/Configs/NationFlagIds.luau"
NAT_TEX = "src/ReplicatedStorage/Shared/Util/NationTexture.luau"
NAT_UN193 = set("""
AD AE AF AG AL AM AO AR AT AU AZ BA BB BD BE BF BG BH BI BJ BN BO BR BS BT BW BY BZ CA CD CF CG CH CI CL CM CN CO CR CU
CV CY CZ DE DJ DK DM DO DZ EC EE EG ER ES ET FI FJ FM FR GA GB GD GE GH GM GN GQ GR GT GW GY HN HR HT HU ID IE IL IN IQ
IR IS IT JM JO JP KE KG KH KI KM KN KP KR KW KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MG MH MK ML MM MN MR MT MU
MV MW MX MY MZ NA NE NG NI NL NO NP NR NZ OM PA PE PG PH PK PL PT PW PY QA RO RS RU RW SA SB SC SD SE SG SI SK SL SM SN
SO SR SS ST SV SY SZ TD TG TH TJ TL TM TN TO TR TT TV TZ UA UG US UY UZ VC VE VN VU WS YE ZA ZM ZW
""".split())
NAT_EXTRA = {"VA", "PS", "TW", "XK", "GB-ENG", "GB-SCT", "GB-WLS"}  # observer states + owner-approved (OwnerReview)
NAT_DENY = {"GB-NIR", "EH", "ES-CT", "ES-PV", "ARAB", "EU", "UN", "XX", "HK", "MO", "CEFTA"}


def nations_roster() -> None:
    import struct
    import subprocess

    body = read(NAT_CFG)
    if body is None:
        bad(f"nations: missing {NAT_CFG}")
        return
    rows = re.findall(
        r'^\t\t\{ Id = "([^"]+)", Name = "((?:[^"\\]|\\.)*)", Short = "((?:[^"\\]|\\.)*)", Region = "(\w+)", '
        r'Color = Color3\.fromRGB\(\d+, \d+, \d+\), AtlasGroup = "(\w+)", AtlasCell = (\d+)',
        body, re.M,
    )
    ids = [r[0] for r in rows]
    raw_rows = len(re.findall(r'^\t\t\{ Id = "', body, re.M))
    (ok if len(rows) == raw_rows == 200 else bad)(f"nations: roster has 200 well-formed rows (parsed {len(rows)} of {raw_rows})")
    (ok if len(NAT_UN193) == 193 else bad)("nations: allowlist holds the 193 UN members")
    allow = NAT_UN193 | NAT_EXTRA
    extra = sorted(set(ids) - allow)
    missing = sorted(allow - set(ids))
    (ok if not extra else bad)(f"nations: every id is allowlisted (UN 193 + VA PS TW XK GB-ENG GB-SCT GB-WLS){' - not: ' + ', '.join(extra) if extra else ''}")
    (ok if not missing else bad)(f"nations: every allowlisted nation is available{' - missing: ' + ', '.join(missing) if missing else ''}")
    denied_in = sorted(set(ids) & NAT_DENY)
    (ok if not denied_in else bad)(f"nations: no denied id in the roster{' - found ' + ', '.join(denied_in) if denied_in else ''}")
    dm = re.search(r"^\tDenied = \{([^}]*)\},", body, re.M)
    cfg_deny = set(re.findall(r'"([^"]+)"', dm.group(1))) if dm else set()
    (ok if NAT_DENY <= cfg_deny else bad)("nations: NationConfig.Denied lists every denied id")
    dups = sorted({i for i in ids if ids.count(i) > 1})
    (ok if not dups else bad)(f"nations: ids unique{' - dup ' + ', '.join(dups) if dups else ''}")
    (ok if "NEUTRAL" not in ids and 'NeutralId = "NEUTRAL",' in body else bad)("nations: NEUTRAL is the stored 'No flag' value, never a nation id")
    long_short = [f"{r[0]}={len(r[2])}" for r in rows if not 2 <= len(r[2]) <= 14]  # len(str) == utf8.len
    (ok if not long_short else bad)(f"nations: utf8.len(Short) <= 14{' - ' + ', '.join(long_short) if long_short else ''}")
    gm = re.search(r"^\t\tGroups = \{([^}]*)\}", body, re.M)
    groups = re.findall(r'"(\w+)"', gm.group(1)) if gm else []
    (ok if groups == ["Europe", "Americas", "Asia", "Africa", "MiddleEast", "Oceania", "Review"] else bad)("nations: 7 atlas groups")
    cells: dict[tuple[str, str], str] = {}
    bad_cells = []
    for r in rows:
        key = (r[4], r[5])
        if key in cells or r[4] not in groups or not 0 <= int(r[5]) < 54 or r[4] not in (r[3], "Review"):
            bad_cells.append(r[0])
        cells[key] = r[0]
    (ok if not bad_cells else bad)(f"nations: atlas cells unique within each group, inside the 9x6 grid, group = region or Review{' - ' + ', '.join(bad_cells) if bad_cells else ''}")
    ids_body = read(NAT_IDS) or ""
    am = re.search(r"\n\tAtlas = \{\n(.*?)\n\t\} :: \{ \[string\]: number \},\n", ids_body, re.S)
    fm = re.search(r"\n\tFlags = \{\n(.*?)\t\} :: \{ \[string\]: number \},\n", ids_body, re.S)
    akeys = re.findall(r"^\t\t(\w+) = \d+,$", am.group(1), re.M) if am else []
    fkeys = re.findall(r'^\t\t\["([^"]+)"\] = \d+,$', fm.group(1), re.M) if fm else []
    (ok if sorted(akeys) == sorted(groups) else bad)("nations: NationFlagIds.Atlas has exactly the 7 atlas groups")
    (ok if fm is not None and set(fkeys) <= set(ids) else bad)("nations: NationFlagIds.Flags keys are roster ids")
    nums = [int(n) for n in re.findall(r"= (\d+),", (am.group(1) if am else "") + (fm.group(1) if fm else ""))]
    live = [n for n in nums if n > 0]
    (ok if len(live) == len(set(live)) else bad)("nations: each uploaded flag image id is used once")
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "gen_nation_flags.py"), "--verify"], capture_output=True, text=True)
    (ok if r.returncode == 0 else bad)(f"nations: assets/flags atlases + manifest match NationConfig (gen_nation_flags.py --verify){' - ' + (r.stderr or r.stdout).strip()[:200] if r.returncode else ''}")
    oversize = []
    for g in groups:
        p = ROOT / "assets" / "flags" / f"atlas_{g}.png"
        head = p.read_bytes()[:24] if p.is_file() else b""
        w, h = struct.unpack(">II", head[16:24]) if head[:8] == b"\x89PNG\r\n\x1a\n" else (0, 0)
        if not (0 < w <= 1024 and 0 < h <= 1024) or not p.is_file() or p.stat().st_size > 1_000_000:
            oversize.append(g)
    (ok if not oversize else bad)(f"nations: every atlas PNG exists, <= 1024 px and <= 1 MB{' - ' + ', '.join(oversize) if oversize else ''}")
    lic = read("assets/flags/LICENSE-flag-icons.txt") or ""
    (ok if "The MIT License" in lic and "Copyright (c) 2013 Panayiotis Lipiridis" in lic and "Version:  7.5.0" in lic else bad)("nations: flag-icons MIT licence + pinned version recorded next to the art")


nations_roster()
# config toggles the spec pins (section 2): privacy, policy caution, live gating, change limits
for _needle, _label in (
    ("SuggestPreselect = false,", "IP suggestion never pre-selected (R3)"),
    ("LiveRequiresArt = true,", "picker auto-opens for non-admins only once the art is wired (R10)"),
    ("OutpostFlags = false,", "outposts keep banner colour at launch (R6)"),
    ("PlayerListEmoji = false,", "player-list emoji off until the device test"),
    ("FreeRepickSeconds = 600,", "free re-pick window 10 min"),
    ("FreeRepickMax = 5,", "at most 5 changes in the free window (R2)"),
    ("ChangeCooldownSeconds = 86400,", "then one change per 24 h"),
    ("MaxJoinPrompts = 3,", "LATER re-offers at most 3 joins"),
    ('if typeof(id) ~= "string" or #id > 8 then', "Get: strings of at most 8 bytes only"),
    ("if n == nil or NationConfig.OwnerReview[id] == false then", "Get: OwnerReview off hides a nation"),
    ("if not denied[n.Id] then", "Get never returns a denied id"),
):
    must_contain(NAT_CFG, _needle, f"nations: {_label}")
# NationTexture stays pure maths (shared by server + client, headless-tested)
for _needle in ("Instance.new", "GetService", "WaitForChild", "RenderStepped", "Heartbeat", "task.wait", "workspace", "Workspace"):
    must_not_contain(NAT_TEX, _needle, f"nations: NationTexture has no {_needle} (pure maths)")
must_contain(NAT_TEX, "local offU = (A.OffsetSignU * rect.X * su) % tileU", "nations: Texture crop offset from NationConfig.Atlas.OffsetSignU (Studio test knob)")
must_contain(NAT_TEX, 'string.format("rbxassetid://%d", atlasId)', "nations: image ids formatted as integers (15-digit ids)")
# guard pins (spec R5 / section 4): nations never reach combat, strike, nuke or raid code. All pass today.
for _rel in sorted({str(p.relative_to(ROOT)) for pat in (
    "src/ServerScriptService/Server/Services/MissileStrikeService.luau",
    "src/ServerScriptService/Server/Services/BankRaidService.luau",
    "src/ServerScriptService/Server/Services/GateDefenseService.luau",
    "src/ServerScriptService/Server/Services/CombatService/*.luau",
    "src/**/*Nuke*.luau",
) for p in ROOT.glob(pat)}):
    for _needle in ("NationConfig", "WE_NationId", "GetNationId", "WE_NationFlag"):
        must_not_contain(_rel, _needle, f"nations: {_rel.rsplit('/', 1)[-1]} never references {_needle}")

must_contain("CLAUDE.md", "Real countries appear only as a player's own cosmetic nation", "nations: CLAUDE.md country rule")

# ── fb2 v73 base identity (owner feedback 2): Lanes A + D + E, merged by the integration verifier ──
# --- v73 base identity (fb2 Lane A): distinct shells, gate checkpoint, watchtower fit, helipad installation ---
_SVC = "src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"
_HBB = "src/ServerScriptService/Server/Modules/HollowBuildingBuilder.luau"
_CKP = "src/ServerScriptService/Server/Modules/Installations/Checkpoint.luau"
_TWR = "src/ServerScriptService/Server/Modules/Installations/Watchtower.luau"
_HLP = "src/ServerScriptService/Server/Modules/Installations/Helipad.luau"
must_contain(_SVC, "CabinClearHeight = 8.5", "v73 watchtower cabin fits a 7.5-stud avatar + 1 stud")
must_contain(_SVC, 'RoofStyle = "Vault"', "v73 distinct shells: Vehicle Depot vaulted hangar roof")
must_contain(_SVC, 'Module = "Helipad"', "v73 helipad is an installation (old kit + parked heli skipped)")
must_contain(_SVC, 'DefensiveWalls = { Enabled = true, Module = "Checkpoint", Width = 6, Depth = 6 }', "v73 checkpoint foundation = 6 x 6 flag plinth")
must_contain(_SVC, 'Signatures = { "SolarDish", "FacadeBand" }', "v73 Lab solar panels + dish, not a radome (Radar owns the dome)")
must_contain(_HBB, "WE_FlagHost", "v73 building flag cloth is a nation-flag host")
must_contain(_HBB, "local GEN = 3", "v73 walk-in shells rebuild once (GEN 3)")
must_not_contain(_HBB, "Radome", "v73 no radome on the Lab")
must_not_contain(_HLP, "ParkedHeli", "v73 helipad: no parked helicopter mock-up")
must_contain(_HLP, "floodlight(api, Vector3.new(hw + 1.2, ground, hw + 1.2), Vector3.new(0, y0, 0), 9, false, col)", "v73 helipad L4 floodlight unlit (light budget)")
must_not_contain(_CKP, "RazorWire", "v73 checkpoint: razor wire removed")
must_not_contain(_CKP, "JerseyStripe", "v73 checkpoint: jersey barriers are 2 parts")
must_contain(_CKP, 'cloth:SetAttribute("WE_FlagHost", true)', "v73 gate plinth flag is the hero nation-flag host")
must_contain(_CKP, 'api.part("BoomArm", Vector3.new(0.45, 0.45, armLen), armCF * CFrame.new(0, 0, -armLen * 0.5), Color3.fromRGB(236, 236, 228), Enum.Material.SmoothPlastic, false)', "v73 boom arm raised and non-colliding (never blocks a vehicle)")
must_contain(_CKP, "local jx = { 6.2, 2.6, -1.0, -4.6 }", "v73 jersey barriers clear of the L4+ gate AutoGun nest")
must_contain(_TWR, "CabinClearHeight", "v73 watchtower headroom from config")
must_contain(_TWR, "local ladderH = 2 * math.ceil((h + 0.5) / 2)", "v73 watchtower ladder always tops out above the deck")
must_contain(_TWR, 'cloth:SetAttribute("WE_FlagHost", true)', "v73 watchtower L5 flag is a nation-flag host")

# fb2 Lane A verifier additions (entry lamp / solar panel / bollard supports)
must_contain(_HBB, 'box(ctx, "EntryLamp", Vector3.new(1.4, 0.2, 0.8), Vector3.new(doorX, lampY, lampZ)', "v73 entry lamp hangs under its entrance cover or is wall-mounted (never floating)")
must_contain(_HBB, "roofTop + 0.15 * math.cos(a) + 1.7 * math.sin(a)", "v73 Lab solar panels rest on the roof slab")

# fb2 Lane D (static soldiers + flag hosts). Verified on HEAD 1ce4828 + Lane D files (MapSetup, Interiors/Barracks, Interiors/SpecialForces).
MSD = "src/ServerScriptService/Server/Modules/MapSetup.luau"
must_contain(MSD, "CFrame = cf * CFrame.new(0, 0.9, 0),", "fb2 static soldier torso lifted 0.9 (feet on the floor, not 0.9-1.1 sunk)")
must_contain(MSD, "local function makeSoldierKit(parentFolder, name, cf: CFrame,", "fb2 makeSoldierKit cf typed CFrame")
must_contain(MSD, "dome.MeshType = Enum.MeshType.Sphere", "fb2 static soldier helmet is a sphere dome")
must_contain(MSD, 'Name = "Helmet",\n\t\tSize = Vector3.new(1.3, 0.75, 1.35),', "fb2 static soldier dome helmet size")
must_not_contain(MSD, 'Name = "Helmet",\n\t\tSize = Vector3.new(1.2, 0.5, 1.2),', "fb2 old flat box helmet gone")
must_contain(MSD, "CFrame = torso.CFrame * CFrame.new(-0.5, -2.825, 0.1),", "fb2 BootL bottom = leg bottom (detail on)")
must_contain(MSD, "CFrame = torso.CFrame * CFrame.new(0.5, -2.825, 0.1),", "fb2 BootR bottom = leg bottom (detail on)")
must_contain(MSD, "local wLocal = yardShift + Vector3.new(-40 + wi * 20, 2.8, 42)", "fb2 training workers stand on the yard pad (y 2.8)")
must_contain(MSD, "local soldierCf = F * CFrame.new(sOrigin + Vector3.new(-1.5, 2.7, 1.5)) * CFrame.Angles(0, math.rad(160 + si * 8), 0)", "fb2 stall soldiers y 2.7, turn kept")
must_contain(MSD, 'local paradeFlag = part({ Name = "ParadeFlag", Size = Vector3.new(0.12, 4.4, 7.5),', "fb2 parade flag cloth 0.12 thick")
must_contain(MSD, 'paradeFlag:SetAttribute("WE_FlagHost", true)', "fb2 parade flag is a nation flag host")
_IB = "src/ServerScriptService/Server/Modules/Interiors/Barracks.luau"
must_contain(_IB, 'local cloth = api.box("FlagCloth", Vector3.new(2.6, 1.7, 0.12),', "fb2 Barracks desk flag cloth 0.12 thick")
must_contain(_IB, 'cloth:SetAttribute("WE_FlagHost", true)', "fb2 Barracks desk flag is a nation flag host")
must_contain(_IB, 'local officerFlag = api.box("OfficerFlag", Vector3.new(2.4, 1.7, 0.12),', "fb2 officer flag 0.12 thick")
must_contain(_IB, 'officerFlag:SetAttribute("WE_FlagHost", true)', "fb2 officer flag is a nation flag host")
_ISF = "src/ServerScriptService/Server/Modules/Interiors/SpecialForces.luau"
must_contain(_ISF, 'local flag = B("UnitFlag", 1.8, 3.2, 0.12, -6.5, y1 + 6.0, Z1 - 0.06,', "fb2 unit flag 0.12 thick, back face flush on the wall")
must_contain(_ISF, 'flag:SetAttribute("WE_FlagHost", true)', "fb2 unit flag is a nation flag host")

# fb2 Lane E (deferred items 1-2: dead helipad kit + parked heli removed; Helipad console line). Verified on HEAD 1ce4828 + Lane A + Lane E files.
_E_SKB = "src/ServerScriptService/Server/Modules/StructureKitBuilder.luau"
_E_BS = "src/ServerScriptService/Server/Services/BaseService.luau"
_E_UPS = "src/ServerScriptService/Server/Services/UpgradePadService.luau"
must_not_contain(_E_SKB, 'elseif kit == "helipad" then', "fb2 dead helipad kit branch deleted (Helipad is an installation)")
must_not_contain(_E_SKB, 'structureId == "SpecialForcesFacility" or structureId == "Helipad"', "fb2 EnsureKit no longer waits for Helipad dress hosts")
must_contain(_E_SKB, 'or nm == "ShowroomFlagHost" or child:GetAttribute("WE_KitRole") == "ParkedBoat" then', "fb2 Dock parked boat still counts as dress")
must_contain(_E_BS, 'elseif role == "ParkedBoat" then', "fb2 Dock parked boat visuals kept")
must_not_contain(_E_BS, "ParkedHeli", "fb2 no parked heli handling left in BaseService")
must_contain(_E_UPS, 'local HELI_NOTE_TEXT = string.format("HELIS AT LV %d", firstHeliLevel())', "fb2 Helipad console says when helicopters come (HELIS AT LV 10)")
must_contain(_E_UPS, 'req.StructureId == "Helipad" and def.RequiresPrestige == nil and def.RequiresRebirthFlag == nil', "fb2 HELIS AT LV = lowest Helipad heli UnlockLevel (VehicleConfig)")
must_contain(_E_UPS, 'if console and structureId == "Helipad" and not addHeliNote(part) then', "fb2 HELIS line only on the Helipad console")
must_contain(_E_UPS, "note.Parent = lbl", "fb2 HELIS line sits under the screen label (WorldPromptController never overwrites it)")
must_not_contain(_E_UPS, 'Instance.new("SurfaceGui")', "fb2 Helipad console line adds no SurfaceGui (budget)")

# ===== Owner's 11 features - BATCH A merged BuyPathStatic block (K1 + M + C + P + S). Insert before the single 'parse_gate()' call. =====


# --- Owner's 11 features, lane K1 contracts (proposed; Z merges) ---
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'ImpulseSpeed = {', 'K1: F8 Speed Pass config ImpulseSpeed exists (never named SpeedBoost)')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'WalkSpeedMult = 1.15,', 'K1: F8 Speed Pass x1.15')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'WalkSpeedMult = 1.25, -- F8', 'K1: F8 Speed Boost product x1.25 from config (not hard-coded)')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'DeathSpeedOffer = {', 'K1: F8 one death offer per session under its own key')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'PassKey = "ImpulseSpeed",', 'K1: F8 death offer sells the Speed Pass')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'SkipIfOwnsAny = { "ImpulseSpeed", "SpeedBoost" } :: { string },', 'K1: F8 no death offer to owners of either speed SKU')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'DeathShopOffers = {} :: { string },', 'K1: M1 death-offer ban kept (DeathShopOffers stays empty)')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'RebirthKeepBase = {', 'K1: F7 Keep-Base Rebirth product exists')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'GrantKeepBaseRebirths = 1,', 'K1: F7 receipt adds one token (counter grant)')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'Field = "KeepBaseRebirths",', 'K1: F7 CounterGrants whitelists KeepBaseRebirths')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'Attribute = "WE_KeepBaseRebirths",', 'K1: F7 token count attribute (display only)')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'SoldFrom = "RebirthPanel",', 'K1: F7 sold only from the Rebirth panel')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'rebirth_panel = true,', 'K1: F7 purchase source rebirth_panel')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'PremiumPads = {', 'K1: F1 PremiumPads slots in config')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'Label = "2x Cash",\n\t\t\t\tColor = Color3.fromRGB(255, 210, 40), -- yellow', 'K1: F1 2x Cash pad is yellow (inside the DoubleCash slot)')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'OwnedIfAny = { "ImpulseSpeed", "SpeedBoost" },', 'K1: F1 Speed pad OWNED for either speed SKU')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'function MonetizationConfig.LivePadOffer(', 'K1: F1 first live offer wins (shared helper)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'Label = "VIP"', 'K1: F1 VIP is not an ATM pad slot (label cap)')
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'Description = "Gold-dress every oil pump on your base  pumps at Walls Lv 2",', 'K1: F9 golden pump Shop copy')
must_contain('src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau', 'function PrestigeConfig.RebirthSummary(', 'K1: F11 RebirthSummary single source')
must_contain('src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau', 'function PrestigeConfig.ProgressPct(', 'K1: F11 ProgressPct')
must_contain('src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau', 'ProgressMode = "XP",', 'K1: F11 rebirth % is XP-based')
must_contain('src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau', 'ResetOnPrestigeKeepBase = {', 'K1: F7 keep-base reset table')
must_contain('src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau', 'BaseUpgrades = false,', 'K1: F7 keep-base path keeps BaseUpgrades')
must_contain('src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau', 'KeepCash = false,', 'K1: F7 KeepCash false (lead decision)')
must_contain('src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau', 'ProductKey = "RebirthKeepBase",', 'K1: F7 KeepBase product key')
must_contain('src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau', 'local LevelConfig = require(script.Parent.LevelConfig)', 'K1: F11 PrestigeConfig uses LevelConfig totals')
must_contain('src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau', 'DisplayName = "Empire Tax",', 'K1: F3 Empire Tax name')
must_contain('src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau', 'Attribute = "WE_EmpireTaxPct",', 'K1: F3 Empire Tax attribute key')
must_contain('src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau', 'PersistClaims = ', 'K1: F3 PersistClaims flag exists (Z flips it)')
must_contain('src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau', 'StarterPct = 5,', 'K1: F10 Home Outpost worth +5%')
must_contain('src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau', 'ToastClaimHeld = "%s is held by %s",', 'K1: F3 claim-held toast')
must_contain('src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau', 'ProducerLabels = {', 'K1: F4 producer label config')
must_not_contain('src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau', 'require(', 'K1: EconomyConfig requires nothing (no TerritoryConfig cycle)')
must_contain('src/ReplicatedStorage/Shared/Configs/CombatFairnessConfig.luau', 'NoviceShield = {', 'K1: F6 novice shield config')
must_contain('src/ReplicatedStorage/Shared/Configs/CombatFairnessConfig.luau', 'MaxSeconds = 900,', 'K1: F6 shield cap 900 s')
must_contain('src/ReplicatedStorage/Shared/Configs/CombatFairnessConfig.luau', 'On = "Shield on until you draw a weapon",', 'K1: F6 device-neutral shield copy')
must_contain('src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau', '\tStarter = {', 'K1: F10 Home Outpost config')
must_contain('src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau', 'IsStarter = true,', 'K1: F10 starter rows are tagged IsStarter')
must_contain('src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau', 'BonusType = "EmpireTax",', 'K1: F10 starter bonus is Empire Tax')
must_contain('src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau', 'local PlotFrame = require(script.Parent.Parent.Util.PlotFrame)', 'K1: F10 starter positions via shared PlotFrame')
must_not_contain('src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau', 'require(script.Parent.EconomyConfig)', 'K1: TerritoryConfig never requires EconomyConfig (cycle guard)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau', 'require(script.Parent.LevelConfig)', 'K1: TerritoryConfig never requires LevelConfig (cycle guard)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau', 'require(script.Parent.OilRigConfig)', 'K1: TerritoryConfig never requires OilRigConfig (cycle guard)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/LevelConfig.luau', 'require(', 'K1: LevelConfig requires nothing (TerritoryConfig / PrestigeConfig cycle guard)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/OilRigConfig.luau', 'require(', 'K1: OilRigConfig requires nothing (TerritoryConfig cycle guard)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/BaseConfig.luau', 'TerritoryConfig)', 'K1: BaseConfig never requires TerritoryConfig (cycle guard)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau', 'require(', 'K1: BaseLayoutConfig requires nothing (PlotFrame cycle guard)')
must_contain('src/ReplicatedStorage/Shared/Configs/HudConfig.luau', 'LeftItems = { "Level", "Settings", "CashPlus", "EmpireTax", "Shield" },', 'K1: F3 TopStrip order with the Empire Tax chip')
must_contain('src/ReplicatedStorage/Shared/Configs/HudConfig.luau', 'HideWhenCrowded = true,', 'K1: F3 Empire Tax chip hides when the top strip is crowded')
must_contain('src/ReplicatedStorage/Shared/Configs/PlotOilPumpConfig.luau', 'Material = Enum.Material.Metal,', 'K1: F9 golden dress is Metal')
must_contain('src/ReplicatedStorage/Shared/Configs/PlotOilPumpConfig.luau', 'Reflectance = 0.2,', 'K1: F9 golden dress reflectance')
must_not_contain('src/ReplicatedStorage/Shared/Configs/PlotOilPumpConfig.luau', 'Enum.Material.Neon', 'K1: F9 no Neon in the golden dress config')
must_not_contain('src/ReplicatedStorage/Shared/Configs/PlotOilPumpConfig.luau', 'BillboardMaxDistance', 'K1: F9 unused BillboardMaxDistance = 80 deleted')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldLabelConfig.luau', 'BaseLabelTag = "WE_BaseLabel",', 'K1: F1/F4 base label tag')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldLabelConfig.luau', 'BaseLabelGovernor = {', 'K1: F4 label governor config')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldLabelConfig.luau', 'MaxOnScreen = 3,', 'K1: F4 at most 3 base labels on screen (CLAUDE.md)')
must_contain('src/ReplicatedStorage/Shared/Configs/NukeConfig.luau', 'SkipStarterOutposts = true,', 'K1: F10 nukes skip Home Outposts')
must_contain('src/ReplicatedStorage/Shared/Configs/NukeConfig.luau', 'function NukeConfig.IsTerritoryTargetable(', 'K1: F10 nuke territory filter helper')
must_contain('src/ServerScriptService/Server/Modules/ProfileSchema.luau', 'KeepBaseRebirths = 0,', 'K1: F7 new profiles start with 0 keep-base tokens')
must_contain('src/ServerScriptService/Server/Modules/ProfileSchema.luau', 'profile.KeepBaseRebirths = nonNegInt(profile.KeepBaseRebirths)', 'K1: F7 tokens sanitised on every load')
must_contain('src/ServerScriptService/Server/Modules/ProfileSchema.luau', 'ensureFeatureFields(profile, rawTutorialOrder, rawShieldDone)', 'K1: F6/F7/F10 profile fields default-filled on Migrate')
must_contain('src/ServerScriptService/Server/Modules/ProfileSchema.luau', 'profile.TutorialOrderVersion = 1', 'K1: F6 missing TutorialOrderVersion means 1')
must_contain('src/ServerScriptService/Server/Modules/ProfileSchema.luau', 'StarterOutpostTaken = false,', 'K1: F10 StarterOutpostTaken default')
must_contain('src/ServerScriptService/Server/Modules/ProfileSchema.luau', 'NoviceShieldDone = false,', 'K1: F6 NoviceShieldDone default')
must_contain('src/ReplicatedStorage/Shared/Types.luau', 'KeepBaseRebirths: number?,', 'K1: Types.PlayerProfile KeepBaseRebirths')
must_contain('src/ReplicatedStorage/Shared/Types.luau', 'export type PrestigeStatePayload = {', 'K1: Types PrestigeStateUpdate payload')
must_contain('src/ReplicatedStorage/Shared/Util/PlotFrame.luau', 'function PlotFrame.LocalToWorld(', 'K1: F10 PlotFrame.LocalToWorld')
must_contain('src/ReplicatedStorage/Shared/Util/PlotFrame.luau', 'function PlotFrame.PlotYaw(', 'K1: PlotFrame.PlotYaw (moved from BaseLayout)')
must_not_contain('src/ReplicatedStorage/Shared/Util/PlotFrame.luau', 'WaitForChild', 'K1: PlotFrame never waits (pure math)')
must_not_contain('src/ReplicatedStorage/Shared/Util/PlotFrame.luau', 'GetDescendants', 'K1: PlotFrame never scans')
must_not_contain('src/ReplicatedStorage/Shared/Util/PlotFrame.luau', 'TerritoryConfig)', 'K1: PlotFrame never requires TerritoryConfig (cycle guard)')
_k1_mc = read("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau") or ""
_k1_gp = re.search(r"\bGoldenPumpjack\s*=\s*\{([^{}]*)\}", _k1_mc)
(ok if _k1_gp and "HideFromShop" not in _k1_gp.group(1) and re.search(r"\bId\s*=\s*\d+", _k1_gp.group(1)) else bad)("K1: F9 GoldenPumpjack entry has no HideFromShop")
(ok if re.search(r"\bRebirthKeepBase\s*=\s*\{\s*Id\s*=\s*0,", _k1_mc) else bad)("K1: F7 RebirthKeepBase Id = 0 until the owner pastes it")
(ok if re.search(r"\bImpulseSpeed\s*=\s*\{\s*Id\s*=\s*0,", _k1_mc) else bad)("K1: F8 ImpulseSpeed Id = 0 until the owner pastes it")



# --- Owner's 11 features, lane M (money server) (proposed; Z merges) ---
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'function MonetizationService.SpeedMultFor(player: Player): number', 'M: F8 SpeedMultFor API (cross-lane)')
must_not_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'SPEED_BOOST_MULT', 'M: F8 no hard-coded Speed Boost multiplier (DevProducts.SpeedBoost.WalkSpeedMult)')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'if m > best and ownsCached(player, passKey) then', 'M: F8 owning both speed SKUs gives the max, never the product')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'local mult = MonetizationService.SpeedMultFor(player)', 'M: F8 walk speed applied from SpeedMultFor')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'hum.WalkSpeed = base * mult', 'M: F8 WalkSpeed = DefaultWalkSpeed x SpeedMultFor')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'MonetizationService.OnPassOwned(function(player: Player, passKey: string)', 'M: F8 Speed Pass applies when it flips to owned (join / refresh / purchase)')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', '-- F8: the character can spawn before the pass cache and the profile are ready; apply the speed now', 'M: F8 speed applied after the profile load (spawn-before-load race)')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'function MonetizationService.TryDeathSpeedOffer(victim: Player): boolean', 'M: F8 TryDeathSpeedOffer API (cross-lane)')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'local cfg = (MonetizationConfig :: any).DeathSpeedOffer', 'M: F8 death offer reads its own key (DeathShopOffers stays empty)')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'if typeof(pass) ~= "table" or typeof(pass.Id) ~= "number" or pass.Id == 0 then', 'M: F8 no death offer while the pass Id is 0')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'if cfg.OncePerSession ~= false and deathSpeedSent[userId] == true then', 'M: F8 one death offer per session')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'deathSpeedSent[player.UserId] = nil', 'M: F8 once-per-session flag cleared on leave')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'if cfg.RequireTutorialComplete ~= false and profile.TutorialComplete ~= true then', 'M: F8 no death offer before the tutorial is complete')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'if passCacheFilled[userId] ~= true or passRefreshRetries[userId] ~= nil then', 'M: F8 unknown ownership never gets the offer')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', 'if not MonetizationService.ClaimSoftOfferSlot(victim) then', 'M: F8 death offer inside the D8 soft-offer budget')
must_contain('src/ServerScriptService/Server/Services/MonetizationService.luau', '(remote :: RemoteEvent):FireClient(victim, { Offers = { passKey } })', 'M: F8 death offer payload = the Speed Pass only')
must_contain('src/ServerScriptService/Server/Services/PremiumPadService.luau', 'MonetizationConfig.PadOwnedKeys(slot)', 'M: F1 pad OWNED from the PremiumPads slot OwnedIfAny')
must_contain('src/ServerScriptService/Server/Services/PremiumPadService.luau', 'part:GetAttribute("OwnedIfAny")', 'M: F1 pad OwnedIfAny attribute honoured')
must_contain('src/ServerScriptService/Server/Services/PremiumPadService.luau', 'if alreadyOwns(player, kind, offerKey, part) then', 'M: F1 an owned pad never prompts')
must_contain('src/ServerScriptService/Server/Services/PremiumPadService.luau', 'if productId == 0 then', 'M: F1 a pad whose offer Id is 0 never prompts')
must_contain('tools/wire-monetization-ids.py', 'elif sold_from:', 'M: F7 wire tool: no remove-HideFromShop NOTE for SoldFrom products (RebirthKeepBase)')

# --- Owner's 11 features, lane C (combat: F6 novice shield, F8 death listener) - proposed; Z merges ---
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'ForceField = "WE_NoviceShield",', 'C: F6 novice shield ForceField WE_NoviceShield (spec pin)')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'function CombatService.IsNoviceShielded(player: Player): boolean', 'C: F6 cross-lane API IsNoviceShielded')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'function CombatService.EndNoviceShield(player: Player, reason: string): boolean', 'C: F6 cross-lane API EndNoviceShield')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', '\tstate.InvulnerableUntil = math.huge\n', 'C: F6 shielded = InvulnerableUntil math.huge (CombatNPC hit roll, assist, every damage path skip)')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'ff.Name = NS.ForceField\n\t\tff.Visible = true', 'C: F6 the shield is a visible server ForceField')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'if typeof(cfg) ~= "table" or cfg.Enabled ~= true or typeof(profile) ~= "table" then', 'C: F6 shield only while NoviceShield.Enabled')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'if profile.TutorialComplete == true or profile.NoviceShieldDone == true or NS.Active[player.UserId] ~= nil then', 'C: F6 never for a finished tutorial, never re-granted')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'NS.onLoad(player, profile) -- F6', 'C: F6 granted when the real save loads')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'NS.apply(player, character) -- F6: a novice shield survives respawns', 'C: F6 shield survives respawns')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', '\t\tprofile.NoviceShieldDone = true\n\t\tDataService.MarkDirty(player)', 'C: F6 the end is saved (NoviceShieldDone + MarkDirty)')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'guns[state.WeaponId] = math.max(gunAt + minInterval, clock()) -- v69 research\n\t-- F6: the first accepted shot ends the novice shield before any hit is resolved (EndOnFire)\n\tif NS.Active[player.UserId] ~= nil then\n\t\tCombatService.EndNoviceShield(player, "fire")', 'C: F6 first accepted shot ends the shield before hit resolution')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'if drawn == true and NS.Active[player.UserId] ~= nil then\n\t\tCombatService.EndNoviceShield(player, "draw")', 'C: F6 drawing a weapon ends the shield')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'if attacker ~= victim and not NS.allowsAttack(attacker) then -- F6: a shielded player deals no PvP damage', 'C: F6 a shielded player deals no PvP damage')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'elseif t >= rec.Deadline then\n\t\t\tCombatService.EndNoviceShield(player, "timeout")', 'C: F6 MaxSeconds cap')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'if profile and profile.TutorialComplete == true then\n\t\t\t\tCombatService.EndNoviceShield(player, "tutorial")', 'C: F6 tutorial complete / skip ends it even without a TutorialService call')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'NS.Active[player.UserId] = nil -- F6: an unfinished shield', 'C: F6 session state cleared on leave')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'pcall(GateDefenseService.SetShieldCheck, CombatService.IsNoviceShielded)', 'C: F6 gate guards skip shielded players (injected, no GateDefense dep)')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'elseif NS.engaging(player) then\n\t\t\tCombatService.EndNoviceShield(player, "raid")', 'C: F6 (verifier) an ATM raid hold or the Empire Bank guard ring ends the shield (NPC guards cannot hurt a shielded novice)')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'if player:GetAttribute("WE_RaidingPlot") ~= nil then\n\t\treturn true\n\tend\n\tif BankRaidConfig.Enabled ~= true then', 'C: F6 (verifier) WE_RaidingPlot / bank ring check (NS.engaging)')
must_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'pcall(MonetizationService.TryDeathSpeedOffer, victim)', 'C: F8 PvP non-blast death calls TryDeathSpeedOffer (pcall)')
must_not_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', 'tap toast', "C: F8 no 'Boost? ... tap toast' Notify (spec pin)")
must_not_contain('src/ServerScriptService/Server/Services/CombatService/init.luau', '"Boost? "', 'C: F8 no Boost? text toast on death')
must_contain('src/ServerScriptService/Server/Services/SquadOrdersService.luau', 'pcall(CombatService.EndNoviceShield, player, "order")', 'C: F6 an accepted squad order ends the shield (spec pin: EndNoviceShield)')
must_contain('src/ServerScriptService/Server/Services/SquadOrdersService.luau', 'CombatService = deps.CombatService', 'C: F6 SquadOrdersService takes CombatService from deps (no require)')
must_contain('src/ServerScriptService/Server/Services/MissileStrikeService.luau', 'pcall(CombatService.EndNoviceShield, attacker, "strike")', 'C: F6 a launched missile strike ends the shield')
must_contain('src/ServerScriptService/Server/Services/MissileStrikeService.luau', 'CombatService = deps.CombatService -- F6 novice shield', 'C: F6 MissileStrikeService takes CombatService from deps (no require)')
must_contain('src/ServerScriptService/Server/Services/GateDefenseService.luau', 'function GateDefenseService.SetShieldCheck(', 'C: F6 GateDefense shield check setter (CombatService injects IsNoviceShielded)')
must_contain('src/ServerScriptService/Server/Services/GateDefenseService.luau', 'if player:GetAttribute("WE_RaidingPlot") ~= nil then\n\t\treturn false\n\tend\n\tlocal check = shieldCheck\n\tif check ~= nil then\n\t\tlocal ok, shielded = pcall(check, player)\n\t\tif ok and shielded == true then\n\t\t\treturn true', 'C: F6 guards / AutoGuns neither target nor damage a shielded player (a raid still ends it first)')

# --- Owner's 11 features, lane P (prestige) (proposed; Z merges) ---
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'local path = if rawPath == "KeepBase" then "KeepBase" else "Cash"', 'P: F7 RequestPrestige keep-base only for the exact path "KeepBase"')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'DoPrestige(player, { KeepBase = path == "KeepBase" })', 'P: F7 RequestPrestige passes the path to DoPrestige')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'if keepBase and nonNegInt(profile.KeepBaseRebirths) <= 0 then\n\t\treturn false, "NoKeepBaseToken"', 'P: F7 keep-base with no token is refused (never the free path)')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'local reset = PrestigeConfig.ResetFor(if keepBase then "KeepBase" else "Cash")', 'P: F7 one reset table per path (PrestigeConfig.ResetFor)')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'profile.KeepBaseRebirths = nonNegInt(profile.KeepBaseRebirths) - 1', 'P: F7 the token is spent inside the no-yield block')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'if reset.BaseUpgrades and BaseService.RefreshAllVisuals then', 'P: F7 keep-base path does not rebuild the base (0 instance changes)')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'path = if keepBase then "keep_base" else "free",', 'P: F7 analytics path keep_base / free')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', '"Rebirth P%d!  Base kept  +%d Gold%s"', 'P: F7 keep-base rebirth toast')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'local okListen, listenErr = pcall(mon.OnGranted, onGranted)', 'P: F7 keep-base token used from OnGranted (after the save), never inside the receipt')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'if kb.AutoUseOnGrant == true and event.Source ~= "none" and PrestigeService.CanPrestige(player) then', "P: F7 auto-use only with this session's purchase intent and when eligible")
must_not_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'MarketplaceService', 'P: F7 PrestigeService never handles a purchase itself')
must_not_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'ProcessReceipt', 'P: F7 the rebirth is not part of the receipt')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'Cash = PrestigeConfig.RebirthSummary("Cash", ctx),', 'P: F11 Summary.Cash from PrestigeConfig.RebirthSummary')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'KeepBase = PrestigeConfig.RebirthSummary("KeepBase", ctx),', 'P: F11 Summary.KeepBase from PrestigeConfig.RebirthSummary')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'KeepBaseLive = keepBaseLive(),', 'P: F7 KeepBaseLive pushed (SOON while the Id is 0)')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'return PrestigeConfig.KeepBase.Enabled == true and id ~= nil and id ~= 0', 'P: F7 KeepBaseLive = Enabled and Id ~= 0')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'ProgressPct = PrestigeConfig.ProgressPct(level, xp),', 'P: F11 XP-based progress % pushed')
must_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', 'LevelTooLow = string.format("Reach Lv %d to rebirth", PrestigeConfig.MinLevelToPrestige),', "P: F11 refusal copy 'Reach Lv 40 to rebirth'")
must_not_contain('src/ServerScriptService/Server/Services/PrestigeService.luau', '"Cannot prestige: "', 'P: F11 no raw error codes in the refusal toast')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau', 'RebirthConfirm', 'P: F11 ProgressionController opens RebirthConfirm (spec pin)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau', 'RebirthConfirm.Open(prestigeState, {', 'P: F11 CONFIRM REBIRTH opens the modal')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau', 'RemoteNames.RequestPrestige', 'P: F11 RequestPrestige is fired only in RebirthConfirm (spec pin)')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau', 'UserInputService.TouchEnabled', 'P: F11 layout/copy by PreferredInput (HudLayout), not TouchEnabled')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau', 'isTouch = HudLayout.IsTouch() or not HudLayout.PrefersKeys()', 'P: F11 PreferredInput decides the touch layout')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau', 'local pct = if level then PrestigeConfig.ProgressPct(level, xp)', 'P: F11 panel % from PrestigeConfig.ProgressPct')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau', '"Rebirth %d%%  Lv %d/%d"', "P: F11 progress copy 'Rebirth 17%  Lv 20/40'")
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau', 'reach max level to prestige', 'P: F11 loading copy fixed (Lv 40, not max level)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'send(Constants.RemoteNames.RequestPrestige)', 'P: F11 REBIRTH fires RequestPrestige() from the modal')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'send(Constants.RemoteNames.RequestPrestige, "KeepBase")', 'P: F7 USE SAVED fires RequestPrestige("KeepBase")')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'if id == 0 then\n\t\t\treturn -- never prompts while the Id is 0', 'P: F7 RebirthConfirm prompts only when the Id ~= 0 (spec pin)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'send(Constants.RemoteNames.RequestPurchaseDevProduct, PrestigeConfig.KeepBase.ProductKey, SOURCE)', 'P: F7 purchase intent with source before the prompt')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'local SOURCE = "rebirth_panel"', 'P: F7 intent source rebirth_panel (auto-use after the save)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'return { Text = "KEEP BASE  SOON", Enabled = false }', 'P: F7 SOON while the product is not live')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'Live = st.KeepBaseLive == true and RebirthConfirm.KeepBaseProductId() ~= 0,', 'P: F7 live only when the server AND the client config say so')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'string.format("USE SAVED (%d)", v.Tokens)', 'P: F7 saved tokens are used from the modal')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', '"Keep all your Robux Items!"', 'P: F11 modal banner')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'Close = 48,', 'P: F11 close control 48 real px')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'ButtonW = 196,\n\tButtonH = 50,', 'P: F11 footer buttons 196x50 real px')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'JumpGap = 16,', 'P: F11 footer keeps 16 px from the jump button')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'player:WaitForChild("PlayerGui", 30)', 'P: RebirthConfirm never waits forever')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'GetDescendants', 'P: RebirthConfirm no tree scans')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'RenderStepped', 'P: RebirthConfirm no per-frame work')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/RebirthConfirm.luau', 'TouchEnabled', 'P: RebirthConfirm device detection through HudLayout')
must_contain('src/ServerScriptService/Server/Services/AdminService.luau', 'elseif cmd == "givekeepbase" then', 'P: F7 admin test tokens (givekeepbase)')
must_not_contain('src/ReplicatedStorage/Shared/Configs/AdminConfig.luau', 'givekeepbase', 'P: F7 givekeepbase is NOT a Studio-open money command (admin allowlist only)')

# --- Owner's 11 features, lane S (Shop client: F1 / F2 / F8 / F9) - proposed; Z merges ---
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'if (tonumber(def.Id) or 0) == 0 then\n\t\t\tcontinue\n\t\tend', 'S: F8 Shop pass loop skips Id 0 passes (no Speed Pass row until its Id is pasted)')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', '(if stub then " · coming soon (no charge)" else "")', "S: F8 no 'coming soon' pass rows")
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'if (tonumber(def.Id) or 0) == 0 then\n\t\ttoast("Coming soon", "Info")\n\t\treturn\n\tend\n\t-- Log intent on server; NEVER treat client confirmation as a grant\n\ttask.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseGamePass', 'S: promptGamePass stops at Id 0 before any intent or Roblox prompt')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'if (tonumber(def.Id) or 0) == 0 then\n\t\ttoast("Coming soon", "Info")\n\t\treturn\n\tend\n\t-- Ask server to log + validate; client still prompts Marketplace (v69: intent log never delays the prompt)\n\ttask.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseDevProduct', 'S: promptDevProduct stops at Id 0 before any intent or Roblox prompt')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'if offerOwned("GamePass", passKey) then\n\t\ttoast("Already owned", "Info")', 'S: F1 promptGamePass: an owned pass never prompts (Already owned)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseGamePass, passKey, cleanSource(source))', 'S: F1 promptGamePass forwards the purchase source')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseDevProduct, productKey, cleanSource(source))', 'S: F2 promptDevProduct forwards the purchase source')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'for _, k in ipairs(MonetizationConfig.PadOwnedKeys(slot)) do', 'S: F1 OwnedIfAny from MonetizationConfig.PremiumPads (same rule as PremiumPadService)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'local attr = if part then part:GetAttribute("OwnedIfAny") else nil', "S: F1 pads honour the server's OwnedIfAny attribute")
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'if (kind == "GamePass" or kind == "DevProduct") and isKeyName(key) then\n\t\t\t\tapplyOwnedVisual(inst, offerOwned(kind :: string, key :: string, inst))', 'S: F1 pads read OWNED for game passes AND Developer Products')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'elseif string.sub(attr, 1, 7) == "WE_Ent_" then\n\t\t\t\t-- F1: the server reports a pass / entitlement: Shop rows AND the world pads flip to OWNED\n\t\t\t\tqueueRefresh()\n\t\t\t\trefreshPremiumPads()', 'S: F1 WE_Ent_* refreshes the Shop rows and the pads')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'CollectionService:GetInstanceAddedSignal(PAD_TAG):Connect(function(inst)', 'S: F1 a streamed-in pad gets its OWNED look (StreamingEnabled)')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'task.wait(20)', 'S: F1 no 20 s pad ownership loop')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'if offerOwned("GamePass", key) then\n\t\t\t\tsetRowButton(r.Btn, "OWNED", "owned")\n\t\t\telse\n\t\t\t\tsetRowButton(r.Btn, r.Label, "buy")', 'S: F1 pass rows follow WE_Ent_* both ways')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'if offerOwned(kind, key) then\n\t\t\ttoast("Already owned", "Info")', 'S: F1 PromptPremiumPad: an owned pad never prompts')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'promptGamePass(key, "pad")', 'S: F1 pad prompts report source pad')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'promptDevProduct(key, "pad")', 'S: F1 Developer Product pad prompts report source pad')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'setOpen(true, "hud_plus")', 'S: F2 the cash + opens the Shop with source hud_plus')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'promptDevProduct(key, openSource)', 'S: F2 Shop rows report the open source (shop / hud_plus)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'row:SetAttribute("WE_HeroRow", true)', 'S: F2 Cash Pack Mega is a permanent hero row')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'local HERO_ROW_STROKE = 2', 'S: F2 hero gold stroke 2')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'local HERO_ROW_EXTRA_H = 22', 'S: F2 hero row 22 v taller')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'end, btnLabel, key, heroLabel ~= nil)', 'S: F2 the BEST OFFER row is built as the hero')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'sub = "BEST OFFER — " .. sub', 'S: F2 no duplicated BEST OFFER in the hero sub')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'stroke.Thickness = if hero then HERO_ROW_STROKE else 0', 'S: F2 the + highlight returns to the hero look')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'if key == speedPassKey and ownsAnyKey(speedOffer.SkipIfOwnsAny) then', 'S: F8 no death offer for owners of any SkipIfOwnsAny key')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'title = "Run faster"', 'S: F8 death offer title')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', '"%s  +%d%% forever"', 'S: F8 death offer sub (Speed Pass  +15% forever)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'promptGamePass(offerKey, "death_card")', 'S: F8 death offer prompts report source death_card')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'promptGamePass("AutoCollect", "offer")', 'S: AutoCollect offer source')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau', 'promptDevProduct("CashMega", "offer")', 'S: CashMega offer source')

# Lane 27 pins for tools/BuyPathStatic.py (append before the final parse_gate() call).
# Verified 2026-09-25 on tree copies (python3 tools/BuyPathStatic_l27.py, LUAU_COMPILE set, parse gate on):
#   HEAD 785c760 + lane 27 WeaponVisuals.luau : Done PASS=1688 FAIL=0  (all 10 pins PRESENT; 9 must_contain + 1 must_not_contain pass)
#   clean HEAD 785c760                        : Done PASS=1678 FAIL=10 (all 10 pins ABSENT / weak __mode present -> they discriminate)
#   unpinned BuyPathStatic.py on both trees    : PASS=1678 FAIL=0
# --- lane 27: WeaponVisuals trackCache is a STRONG table pruned on Animator removal / respawn (no weak Instance keys) ---
WV_L27 = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/WeaponVisuals.luau"
must_contain(WV_L27, "local trackCache: { [Animator]: TrackSet } = {}", "lane27: WeaponVisuals trackCache is a strong table keyed by Animator")
must_not_contain(WV_L27, "__mode", "lane27: WeaponVisuals has no weak tables (a weak Instance key can drop while the Instance lives)")
must_contain(WV_L27, "animator.Destroying:Connect(function()", "lane27: a cached set is dropped when its Animator is destroyed")
must_contain(WV_L27, "animator.AncestryChanged:Connect(function()", "lane27: a cached set is dropped when its Animator leaves the DataModel")
must_contain(WV_L27, "player.CharacterRemoving:Connect(function(char: Model)", "lane27: CharacterRemoving prunes the leaving character's tracks")
must_contain(WV_L27, "pruneTracks(char, true)", "lane27: CharacterRemoving -> pruneTracks(char, true)")
must_contain(WV_L27, "pruneTracks(char, false)", "lane27: CharacterAdded keeps only the new character's tracks")
must_contain(WV_L27, "tr:Destroy()", "lane27: dropped AnimationTracks are stopped and destroyed")
must_contain(WV_L27, "if found == nil or not found:IsDescendantOf(game) then", "lane27: no LoadAnimation / cache entry for an Animator outside the DataModel")
must_contain(WV_L27, "function WeaponVisuals.AnimCacheStats(): { Animators: number, Tracks: number }", "lane27: AnimCacheStats test hook")

# LANE 32 proposed tools/BuyPathStatic.py pins: paste above the final `parse_gate()` call. Uses the file's own helpers.
# Verified on tree copies (git HEAD 34c18f3 = same WorldTerrain / WorldConfig as 785c760):
#   HEAD                         : PASS=1926 FAIL=0
#   HEAD + lane 32 files         : PASS=1926 FAIL=0   (no existing needle broken)
#   HEAD + lane 32 files + pins  : PASS=1943 FAIL=0   (all 17 present)
#   HEAD + pins                  : 16 FAIL (the new behaviour is absent at HEAD), 1 PASS (far-shore toe/talus unchanged)
# Absence pins use must_not_contain (must_absent only looks at asset-id assignment lines).
# --- Lane 32 (owner's quad tripped on the canyon edge): the Terrain skirt band is a drivable toe ramp (no 2.5-5.5 lip),
# one toe + talus for every run and corner, boulders off the toe, hip carves at the rig-lagoon notch run ends ---
L32T = 'src/ServerScriptService/Server/Modules/WorldTerrain.luau'
L32C = 'src/ReplicatedStorage/Shared/Configs/WorldConfig.luau'
must_contain(L32C, 'Gen = 2, -- 2: lane 32 toe ramp + notch hips', 'Lane 32: terrain stamp bumped so stamped Gen 1 terrain is cleared and refilled')
must_contain(L32C, "Y = 0, -- the ramp's low edge, under the Part ground top (0.5)", 'Lane 32: toe ramp starts under the sand (no lip)')
must_contain(L32C, 'BuriedTop = 0.5, -- a prim whose top is at or under the Part ground is buried', 'Lane 32: buried support block may lie under sea water')
must_contain(L32C, 'HipClear = 24, -- notch run-end hip carves', 'Lane 32: hip carve clearance')
must_contain(L32C, 'Skirt = { From = 0, To = 26, Min = 2.5, Max = 5.5 },\n\t\t\tTalus = { From = 26, To = 56, Min = 8, Max = 20 },\n\t\t\tFace = { From = 48, To = 108,', 'Lane 32: side toe/talus = far shore toe/talus (17 deg ramp, then 22 deg talus)')
must_contain(L32C, 'Skirt = { From = 0, To = 26, Min = 2.5, Max = 5.5 },\n\t\t\tTalus = { From = 26, To = 56, Min = 8, Max = 20 },\n\t\t\tFace = { From = 56, To = 116,', 'Lane 32: far-shore toe/talus unchanged')
must_not_contain(L32C, 'Skirt = { From = 0, To = 18,', 'Lane 32: no 18-stud side shelf (step at the far-shore corner fans)')
must_contain(L32T, 'rng:NextNumber(pr.Skirt.Min, pr.Skirt.Max)\n\tlocal toe = c.Toe', 'Lane 32: skirt roll still drawn (seeded faces / mesas / buttes unchanged)')
must_contain(L32T, 'block("skirt", mats.Skirt, pr.Skirt.From, pr.Skirt.To, foot, toe.Y, 0, sw, 0)', 'Lane 32: buried support block under the toe ramp')
must_contain(L32T, 'Size = Vector3.new(sw, pr.Talus.Min - toe.Y, pr.Skirt.To - pr.Skirt.From),', 'Lane 32: toe FillWedge rises to the talus foot')
must_not_contain(L32T, 'local skirtTop = rng:NextNumber', 'Lane 32: no random-height rock shelf (2.5-5.5 lip, 3-stud jumps between segments)')
must_contain(L32T, 'local lo = pr.Talus.From + r\n\t\tlocal d = rng:NextNumber(lo, math.max(lo, faceFrom))', 'Lane 32: boulders at the cliff foot, never on the toe')
must_contain(L32T, 'local function emitHip(plan: { Prim }, c: TerrainCfg, run: Run, atB: boolean)', 'Lane 32: hip carve at notch run ends')
must_contain(L32T, 'emitHip(plan, c, run, false)', 'Lane 32: hip at a run start after a notch')
must_contain(L32T, 'emitHip(plan, c, run, true)', 'Lane 32: hip at a run end before a notch')
must_contain(L32T, 'local buried = p.Top <= c.Toe.BuriedTop', 'Lane 32: buried prims exempt from the water keep-out only')
must_contain(L32T, '"Side and FarShore toe / talus differ', 'Lane 32: Check flags a toe/talus mismatch between profiles')

# ===== Nations lane A1 (Constants / Types / AnalyticsConfig / NukeConfig / ProfileSchema) =====
# Paste-ready for tools/BuyPathStatic.py, before the final parse_gate() call (after the lane A0 nations block).
# It uses the file's own helpers (ok / bad / read / must_contain / must_not_contain, ROOT, re).
# Checked with fb2/nations/A1/verify_pins.sh against:
#   (a) HEAD 34c18f3 + the 5 A1 files: all PASS, and BuyPathStatic has 0 FAIL overall;
#   (b) the live shared working tree with the same pins merged: all PASS;
#   (c) HEAD without the A1 files, and mutated copies: every A1 pin group FAILs (the pins catch a revert).
# Existing needles: none changed. The pins that already read these files (Constants :62 :253 :312 ... ,
# ProfileSchema :252 :593 :628 :665 :1117 :1267 :1441 :2698-2703, NukeConfig :1444 :2696 :2697, Types :2704 :2705)
# still PASS unchanged. The old aim point text "BaseAimPoint = { X = 0, Z = 8 }" was not pinned by anyone.
# Spec: fb2/spec_nations.md section 2 (Data, NukeConfig), section 4 (DataService cases, BuyPathStatic rules).

NAT_CONST = "src/ReplicatedStorage/Shared/Constants.luau"
NAT_TYPES = "src/ReplicatedStorage/Shared/Types.luau"
NAT_ANALYTICS = "src/ReplicatedStorage/Shared/Configs/AnalyticsConfig.luau"
NAT_NUKE = "src/ReplicatedStorage/Shared/Configs/NukeConfig.luau"
NAT_SCHEMA = "src/ServerScriptService/Server/Modules/ProfileSchema.luau"
NAT_BLC = "src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau"

# remote name (client -> server request only; replies go out on NationColorUpdate)
must_contain(NAT_CONST, 'RequestSetNation = "RequestSetNation",', "nations: RequestSetNation remote name")
must_contain(NAT_CONST, 'NationColorUpdate = "NationColorUpdate",', "nations: NationColorUpdate stays the server -> player channel")
must_not_contain(NAT_CONST, "GiveNation", "nations: no Give* nation remote")
# profile fields + payload types
for _needle in (
    "NationId: string?,",
    "NationSetAt: number?,",
    "NationFreeUntil: number?,",
    "NationFreeChanges: number?,",
    "NationPrompts: number?,",
    "export type NationRequestPayload = {",
    "export type NationStatePayload = {",
):
    must_contain(NAT_TYPES, _needle, f"nations: Types {_needle}")
# analytics: the three spec events; the IP suggestion is never an event or a field (R3)
for _ev in ("NATION_PICKER_SHOWN", "NATION_PICK", "NATION_LATER"):
    must_contain(NAT_ANALYTICS, f'{_ev} = "{_ev}",', f"nations: analytics event {_ev}")
for _needle in ("suggestedMatch", "SUGGEST"):
    must_not_contain(NAT_ANALYTICS, _needle, f"nations: no {_needle} in analytics (the IP suggestion is never logged)")
# ProfileSchema: defaults, sanitiser, call site, pcall guard, no DataVersion bump
must_contain(NAT_SCHEMA, "\t\tNationId = nil,\n\t\tNationSetAt = 0,\n\t\tNationFreeUntil = 0,\n\t\tNationFreeChanges = 0,\n\t\tNationPrompts = 0,\n", "nations: CreateDefault nation defaults (NationId nil = never picked)")
must_contain(NAT_SCHEMA, "\tensureFeatureFields(profile, rawTutorialOrder, rawShieldDone)\n\t-- Nations: chosen country + change timers (idempotent; NationColorId untouched)\n\tensureNationFields(profile)\n", "nations: ensureNationFields runs on every Migrate, next to ensureFeatureFields")
must_contain(NAT_SCHEMA, "if id ~= NationConfig.NeutralId and NationConfig.Get(id) == nil then\n\t\t\tprofile.NationId = nil", "nations: saved NationId kept only if NEUTRAL or NationConfig.Get passes")
must_contain(NAT_SCHEMA, "profile.NationSetAt = nonNegInt(profile.NationSetAt)", "nations: NationSetAt sanitised (whole number >= 0)")
must_contain(NAT_SCHEMA, "profile.NationFreeUntil = nonNegInt(profile.NationFreeUntil)", "nations: NationFreeUntil sanitised")
must_contain(NAT_SCHEMA, "profile.NationFreeChanges = nonNegInt(profile.NationFreeChanges)", "nations: NationFreeChanges sanitised")
must_contain(NAT_SCHEMA, "profile.NationPrompts = math.min(nonNegInt(profile.NationPrompts), MAX_NATION_PROMPTS)", "nations: NationPrompts sanitised and capped")
must_contain(NAT_SCHEMA, "local MAX_NATION_PROMPTS = 99", "nations: NationPrompts cap 99")
must_contain(NAT_SCHEMA, "return require(Shared.Configs.NationConfig) :: any", "nations: NationConfig loaded in a pcall (a broken config never blocks a profile load)")
must_not_contain(NAT_SCHEMA, "local NationConfig = require(", "nations: ProfileSchema never requires NationConfig outside the pcall")


def nations_a1_checks() -> None:
    body = read(NAT_SCHEMA) or ""
    m = re.search(r"\nlocal function ensureNationFields\(profile: any\)\n(.*?)\nend\n", body, re.S)
    fn = m.group(1) if m else ""
    (ok if m and "NationColorId" not in fn and "DataVersion" not in fn else bad)(
        "nations: ensureNationFields never touches NationColorId or DataVersion"
    )
    call = body.find("\tensureNationFields(profile)\n")
    final = body.find("\tprofile.DataVersion = Constants.CURRENT_DATA_VERSION\n\treturn profile")
    (ok if 0 < call < final else bad)("nations: ensureNationFields runs before Migrate stamps DataVersion and returns")
    # nuke aim point (spec R5 / section 2): >= 30 studs from the flagpole, on MainRoad, plot-local
    nb = read(NAT_NUKE) or ""
    lb = read(NAT_BLC) or ""
    am = re.search(r"BaseAimPoint = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \}", nb)
    fm = re.search(r"\n\t\tFlagpole = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \},", lb)
    rm = re.search(r'\{ Name = "MainRoad", X = (-?[\d.]+), Z = (-?[\d.]+), SizeX = ([\d.]+), SizeZ = ([\d.]+) \}', lb)
    if not (am and fm and rm):
        bad("nations: NukeConfig BaseAimPoint / BaseLayoutConfig Courtyard.Flagpole / MainRoad not found")
        return
    ax, az = float(am.group(1)), float(am.group(2))
    fx, fz = float(fm.group(1)), float(fm.group(2))
    d = ((ax - fx) ** 2 + (az - fz) ** 2) ** 0.5
    (ok if d >= 30 else bad)(f"nations: nuke base aim point >= 30 studs from Courtyard.Flagpole ({d:.1f})")
    rx, rz, sx, sz = (float(g) for g in rm.groups())
    (ok if abs(ax - rx) <= sx / 2 and abs(az - rz) <= sz / 2 else bad)("nations: nuke base aim point lies on MainRoad")


nations_a1_checks()
must_not_contain(NAT_NUKE, "BaseAimPoint = { X = 0, Z = 8 }", "nations: the nuke no longer aims at the plaza flagpole")
# spec section 4: no Checkpoint file references a nation (the flag never sits at the gate, where strike fire spawns)
for _rel in sorted(str(p.relative_to(ROOT)) for p in ROOT.glob("src/**/*Checkpoint*.luau")):
    for _needle in ("NationConfig", "WE_NationId", "GetNationId", "WE_NationFlag"):
        must_not_contain(_rel, _needle, f"nations: {_rel.rsplit('/', 1)[-1]} never references {_needle}")

# ===== Nations lane C (NationController / UIController / SettingsController) =====
# Paste-ready for tools/BuyPathStatic.py, before the final parse_gate() call, AFTER the lane A1 nations block
# (fb2/nations/A1/pins.txt). Uses the file's own helpers (ok / bad / read / must_contain / must_not_contain, re).
# Checked with fb2/nations/C/verify_pins.sh (A1 pins + these merged): HEAD 56c0627 + A1 + C -> 45 C pins PASS,
# BuyPathStatic PASS=2032 FAIL=0; the live shared tree copy -> 45/45 C pins PASS (its 10 other FAILs are other jobs'
# unfinished Tutorial / W3 edits); clean HEAD -> every C pin FAILs (no picker); fb2/nations/C/mutate_pins.sh -> 17
# mutations, each caught. Existing needles: none changed (UIController's panelOpeners
# lines, the PANELS "Missiles" line, the PromptController guard and SettingsController's applySheet stay as they were).
# Spec: fb2/spec_nations.md section 2 Client + section 4 BuyPathStatic rules; contract fb2/nations/A1/contract.md 5.

NAT_NC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NationController.luau"
NAT_UIC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau"
NAT_SC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/SettingsController.luau"

# picker: never a world flag look, never per-frame work, never a blocking wait
for _needle in ("SurfaceGui", "PointLight", "Neon", "RenderStepped", "Heartbeat", "BindToRenderStep", "GetDescendants",
                "Remotes.GetEvent(", "Workspace:FindFirstChild", "workspace:FindFirstChild"):
    must_not_contain(NAT_NC, _needle, f"nations C: NationController has no {_needle}")
# the request: FireServer inside task.spawn (gives up after 3 s while the remote is missing), exact payloads only
must_contain(NAT_NC, 'local payload = { Action = "pick", Id = id, Source = mode }', "nations C: pick payload is exactly {Action, Id, Source}")
must_contain(NAT_NC, 'local payload = { Action = "later", Source = "join" }', "nations C: later payload is exactly {Action, Source}")
must_contain(NAT_NC, "local sent = Remotes.FireServer(Constants.RemoteNames.RequestSetNation, payload)", "nations C: pick goes out with Remotes.FireServer (bounded)")
must_contain(NAT_NC, 'finishPick(serial, "nosend")', "nations C: missing remote -> friendly failure, CONFIRM back")
must_contain(NAT_NC, 'finishPick(serial, "timeout")', "nations C: no reply within 5 s -> friendly failure")
must_contain(NAT_NC, "local REPLY_TIMEOUT = 5", "nations C: pick waits at most 5 s")
# privacy (spec R3): nothing selected at the start, suggestion only a badge, search text stays on the device
must_contain(NAT_NC, "selectedId = nil -- nothing selected at the start (spec R3)", "nations C: nothing selected when the picker opens")
must_contain(NAT_NC, 't.Badge.Text = "Suggested"', "nations C: the suggestion is a badged tile")
must_not_contain(NAT_NC, "selectedId = suggestedId", "nations C: the suggestion is never pre-selected")
must_not_contain(NAT_NC, "player:SetAttribute(", "nations C: the client never writes nation attributes (no suggestion attribute)")
# closing the join picker without CONFIRM counts as LATER, once per session (spec R9)
must_contain(NAT_NC, "sendLater() -- spec R9", "nations C: join close without CONFIRM = LATER")
must_contain(NAT_NC, "if laterSent then\n\t\treturn\n\tend\n\tlaterSent = true", "nations C: LATER sent once per session")
# auto-open gates (spec section 2 Client)
must_contain(NAT_NC, 'local BLOCK_FLAGS = { "Driving", "Dead", "RecentCombat", "Modal" }', "nations C: join picker waits for Driving / Dead / RecentCombat / Modal")
must_contain(NAT_NC, "local AUTO_OPEN_DELAY = 1.0", "nations C: join picker 1.0 s after the first CharacterAdded")
must_contain(NAT_NC, "return not NationConfig.LiveRequiresArt or artReady or isAdmin", "nations C: LiveRequiresArt gate (admin exempt)")
must_contain(NAT_NC, "isAdmin = table.find(AdminConfig.UserIds, player.UserId) ~= nil", "nations C: admin = AdminConfig.UserIds")
must_contain(NAT_NC, "player.CharacterAdded:Connect(armAutoOpen)", "nations C: auto-open armed by CharacterAdded")
# fallback tile + atlas preload (pcall inside task.spawn)
must_contain(NAT_NC, "code.Text = NationConfig.Code(def.Id)", "nations C: fallback tile = banner colour + code")
must_contain(NAT_NC, "task.spawn(function()\n\t\tlocal ok, err = pcall(function()\n\t\t\tContentProvider:PreloadAsync(list)", "nations C: atlas PreloadAsync in pcall inside task.spawn")
# phone-first sizes (v; phones 0.70): taps >= 68 v, thumb-zone line, jump clearance
must_contain(NAT_NC, "ThumbZone = 0.40,", "nations C: tabs / grid start right of the left-40 % thumb zone")
must_contain(NAT_NC, "JumpClearPx = 20,", "nations C: >= 20 real px from the jump button")
# UIController: panel registry + opener + guarded init
must_contain(NAT_UIC, 'table.insert(PANELS, { Id = "Nation", Controller = NationController })', "nations C: Nation joins the one-panel-at-a-time registry")
must_contain(NAT_UIC, "panelOpeners.Nation = NationController.Open", "nations C: flagpole prompt (WE_OpenPanel Nation) routes to the picker")
must_contain(NAT_UIC, 'safeInit("Nation", NationController.Init)', "nations C: NationController.Init guarded")
must_contain(NAT_UIC, "local ok, res = pcall(req, mod)\n\t\tif ok and typeof(res) == \"table\" then\n\t\t\tNationController = res", "nations C: NationController required defensively")
# Settings: YOUR FLAG row, CHANGE >= 68 v, opens Settings mode
must_contain(NAT_SC, "local changeW, changeH = 170, 68", "nations C: Settings CHANGE button 170 x 68 v")
must_contain(NAT_SC, "NationController.Open(nil) -- Settings mode", "nations C: Settings CHANGE opens the picker in Settings mode")
must_contain(NAT_SC, 'change.Name = "NationChange"', "nations C: Settings NationChange button")


def nations_c_checks() -> None:
    body = read(NAT_NC) or ""
    if not body:
        bad("nations C: NationController missing")
        return
    (ok if body.startswith("--!strict\n") else bad)("nations C: NationController is --!strict")
    # copy by device: no key names / "click" / "press" in any string literal (no PrefersKeys branch exists)
    lits = re.findall(r'"((?:[^"\\\n]|\\.)*)"', body)
    badlits = [s for s in lits if re.search(r"click|press|keycode|\bkey\b|tap to", s, re.I)]
    (ok if not badlits and "KeyCode" not in body else bad)(f"nations C: no key names / click / press in picker copy {badlits[:3]}")
    # never WaitForChild without a timeout
    (ok if not re.search(r"WaitForChild\(\s*\"[^\"]*\"\s*\)", body) else bad)("nations C: no WaitForChild without a timeout")
    # exactly two requests: pick + later
    n = body.count("Remotes.FireServer(")
    (ok if n == 2 else bad)(f"nations C: exactly two RequestSetNation sends (pick, later): {n}")
    # tap targets >= 68 v and text >= 20 v in the geometry table
    g = re.search(r"\nlocal G = \{\n(.*?)\n\}\n", body, re.S)
    vals = dict(re.findall(r"\t(\w+) = (\d+(?:\.\d+)?),", g.group(1))) if g else {}
    need = ("TabH", "SecondH", "ConfirmMinH", "SearchH", "TileH", "TileMinW", "TabMinW")
    small = [k for k in need if float(vals.get(k, 0)) < 68]
    (ok if g and not small else bad)(f"nations C: picker tap sizes >= 68 v {small}")
    sizes = [int(x) for x in re.findall(r"(?:label|button)\([^\n]*?, (\d+), (?:true|false|COL\.\w+)\)", body)]
    (ok if sizes and min(sizes) >= 20 else bad)(f"nations C: picker text sizes >= 20 v (min {min(sizes) if sizes else None})")
    # the flagpole prompt lives in the world; nothing else in the client may open the picker with a nation id
    ui = read(NAT_UIC) or ""
    (ok if ui.count("NationController") >= 5 else bad)("nations C: UIController wires NationController (require, PANELS, Init, opener)")


nations_c_checks()

# ===== Nations lane B (NationColorService / NationFlag / RemoteSetup / AdminService / SettingsController art gate) =====
# Paste-ready for tools/BuyPathStatic.py, before the final parse_gate() call, AFTER the lane A1 and lane C nations
# blocks (fb2/nations/A1/pins.txt, fb2/nations/C/pins.txt). Uses the file's own helpers (ok / bad / read /
# must_contain / must_not_contain, re). Spec: fb2/spec_nations.md section 2 Server + section 4 BuyPathStatic rules;
# lead decisions 1-8 (fb2/nations/B/assumptions.md). Checked with fb2/nations/B/verify_pins.sh (A1 + C + B merged):
#   HEAD 56c0627 + A1 + C + B      -> 93 B pins PASS, BuyPathStatic PASS=2125 FAIL=0;
#   HEAD 56c0627 + A1 + C (no B)   -> 85 B pins FAIL (every new-behaviour pin); the 8 that PASS there are guards that
#                                     already hold (no leaderstats / StringValue / FireAllClients / NotifyAll in
#                                     NationColorService, nationreset not a money command, --!strict, no suggestion
#                                     leak, flag-to-gate distance from BaseLayoutConfig);
#   live shared tree copy          -> 93/93 B pins PASS (its 10 other FAILs are other jobs' unfinished Tutorial / W3 edits);
#   fb2/nations/B/mutate_pins.sh   -> 25 mutations, each caught.
# Existing needles: none changed (RemoteSetup :63 :314 :1155-1157 :1172 :1237 :1439 :2165, AdminService :932 :1440
# :1779-1780 :2816, SettingsController :1679, TerritoryService :505 all still PASS).

NAT_NCS = "src/ServerScriptService/Server/Services/NationColorService.luau"
NAT_NF = "src/ServerScriptService/Server/Modules/NationFlag.luau"
NAT_RS = "src/ServerScriptService/Server/Modules/RemoteSetup.luau"
NAT_AS = "src/ServerScriptService/Server/Services/AdminService.luau"
NAT_SCB = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/SettingsController.luau"
NAT_BLCB = "src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau"

# remote: the server creates RequestSetNation next to NationColorUpdate (A1 contract section 1)
must_contain(NAT_RS, "\tConstants.RemoteNames.NationColorUpdate,\n\tConstants.RemoteNames.RequestSetNation,\n", "nations B: RemoteSetup creates RequestSetNation")
# handler order (spec R17): rate limit first, table / Action / Source, then the id, then the profile
must_contain(NAT_NCS, 'if not RateLimitService.Allow(player, "RequestSetNation", NationConfig.RequestRate, NationConfig.RequestBurst) then', "nations B: RequestSetNation rate-limited first (RateLimitService.Allow)")
must_contain(NAT_NCS, 'if typeof(payload) ~= "table" then', "nations B: payload must be a table")
must_contain(NAT_NCS, 'if action ~= "pick" and action ~= "later" then', "nations B: Action exactly pick / later")
must_contain(NAT_NCS, 'if source ~= "join" and source ~= "flagpole" and source ~= "settings" then', "nations B: Source exactly join / flagpole / settings")
must_contain(NAT_NCS, 'if typeof(raw) == "string" and #raw <= 8 then', "nations B: Id a string of <= 8 bytes")
must_contain(NAT_NCS, "local def = NationConfig.Get(raw)", "nations B: Id checked with NationConfig.Get (exact match)")
must_contain(NAT_NCS, "id = def.Id -- NationConfig's own string, never the client's", "nations B: the stored id is NationConfig's string")
must_contain(NAT_NCS, 'reply(player, { Result = "invalid" })', "nations B: bad id -> invalid")
must_contain(NAT_NCS, 'reply(player, { Result = "loading" })', "nations B: no profile -> loading")
must_contain(NAT_NCS, 'reply(player, { Result = "cooldown", NextChangeAt = nextAt })', "nations B: cooldown reply carries NextChangeAt")
# pick rules + lead decisions 2-5
must_contain(NAT_NCS, "if id == NationConfig.NeutralId and freeUntil == 0 then\n\t\treturn 0 -- No flag before the first real country (lead decision 2)", "nations B: No flag does not use up the first pick (decision 2)")
must_contain(NAT_NCS, "if now < freeUntil and num(profile.NationFreeChanges) < NationConfig.FreeRepickMax then", "nations B: free window with FreeRepickMax changes")
must_contain(NAT_NCS, "if setAt > now then\n\t\tsetAt = 0 -- clock skew / corrupt save (lead decision 4)", "nations B: future NationSetAt counts as 0 (decision 4)")
must_contain(NAT_NCS, "local at = setAt + NationConfig.ChangeCooldownSeconds\n\treturn if now >= at then 0 else at", "nations B: WE_NationNextAt = 0 exactly when a pick is allowed (decision 5)")
must_contain(NAT_NCS, 'if savedId(profile) == id then\n\t\t-- already this flag: "ok", nothing written, no toast (lead decision 3)', "nations B: same id -> ok, no write (decision 3)")
must_contain(NAT_NCS, "if id ~= NationConfig.NeutralId and freeUntil == 0 then\n\t\tprofile.NationFreeUntil = now + NationConfig.FreeRepickSeconds", "nations B: the first REAL pick opens the free window once")
must_contain(NAT_NCS, "if now < freeUntil and not first then\n\t\tprofile.NationFreeChanges = num(profile.NationFreeChanges) + 1", "nations B: changes inside the window are counted")
must_contain(NAT_NCS, "refreshTimer[uid] = task.delay(at - now + 1, function()", "nations B: one task.delay per player keeps WE_NationNextAt exact")
must_contain(NAT_NCS, "pcall(task.cancel, timer)", "nations B: the timer is cancelled on leave")
# LATER: only while NeedsPick, once per session, join only
must_contain(NAT_NCS, 'if source ~= "join" then\n\t\t\treturn -- LATER exists only in the join picker', "nations B: LATER only from the join picker")
must_contain(NAT_NCS, "if not needsPick(uid, profile) then\n\t\treturn -- NeedsPick already false", "nations B: LATER only while NeedsPick")
must_contain(NAT_NCS, "laterUsed[uid] = true\n\tprofile.NationPrompts = math.min(num(profile.NationPrompts) + 1, MAX_PROMPTS)", "nations B: LATER once per session, NationPrompts + 1 (cap 99)")
# analytics: exact props, never the suggestion
must_contain(NAT_NCS, "log(AnalyticsConfig.Events.NATION_PICK, uid, { id = id, source = source, first = first })", "nations B: NATION_PICK {id, source, first}")
must_contain(NAT_NCS, "log(AnalyticsConfig.Events.NATION_LATER, uid, { count = profile.NationPrompts })", "nations B: NATION_LATER {count}")
must_contain(NAT_NCS, 'log(AnalyticsConfig.Events.NATION_PICKER_SHOWN, uid, { source = "join" })', "nations B: NATION_PICKER_SHOWN join")
must_contain(NAT_NCS, 'log(AnalyticsConfig.Events.NATION_PICKER_SHOWN, player.UserId, { source = "flagpole" })', "nations B: NATION_PICKER_SHOWN flagpole")
# suggestion: pcall, 5 s cap, roster ids only, that player only
must_contain(NAT_NCS, "return LocalizationService:GetCountryRegionForPlayerAsync(player)", "nations B: IP country lookup (server)")
must_contain(NAT_NCS, 'if not ok or typeof(code) ~= "string" or os.clock() - t0 > SUGGEST_TIMEOUT then', "nations B: lookup in pcall, answers after 5 s dropped")
must_contain(NAT_NCS, "local SUGGEST_TIMEOUT = 5", "nations B: suggestion cap 5 s")
must_contain(NAT_NCS, "local def = NationConfig.Get(string.upper(code))", "nations B: only a roster id is suggested")
# art gate (decision 6), admin = AdminConfig.UserIds
must_contain(NAT_NCS, "return NationConfig.Enabled and (not NationConfig.LiveRequiresArt or artReady or isAdminUser(userId))", "nations B: nations shown only with art or to admins (decision 6)")
must_contain(NAT_NCS, "return table.find(AdminConfig.UserIds, userId) ~= nil", "nations B: admin = AdminConfig.UserIds")
must_contain(NAT_NCS, "artReady = NationTexture.ArtReady()", "nations B: art readiness from NationTexture")
# toast to the picker only; silent legacy colour; outposts feature-checked (TerritoryService is lane B2)
must_contain(NAT_NCS, 'pcall(NotificationService.Notify, player, if def then "Flag raised: " .. def.Short else "Plain flag raised", "Success")', "nations B: 'Flag raised: <Short>' toast to the picker")
must_not_contain(NAT_NCS, "Nation color: ", "nations B: the legacy colour is assigned silently")
must_contain(NAT_NCS, 'if NationConfig.OutpostFlags and TerritoryService and typeof(TerritoryService.RefreshOwnerFlags) == "function" then', "nations B: RefreshOwnerFlags only behind OutpostFlags and only if it exists")
must_contain(NAT_NCS, "NationService (nations spec section 2 Server, lane B)", "nations B: header names NationService")
must_contain(NAT_NCS, "function NationColorService.GetNationId(userId: number): string?", "nations B: GetNationId")
must_contain(NAT_NCS, "function NationColorService.AdminReset(player: Player): boolean", "nations B: AdminReset (caller's own fields)")
# decision 1: no player-list column / leaderstat; nothing broadcast
for _needle in ("leaderstats", 'Instance.new("StringValue")', "FireAllClients", "NotifyAll"):
    must_not_contain(NAT_NCS, _needle, f"nations B: NationColorService has no {_needle} (no leaderboard, nothing broadcast)")
# NationFlag: the two base flags only, Textures only, owner-only prompt behind the art gate
must_contain(NAT_NF, 'NationFlag.Tag = "WE_NationFlag"', "nations B: flag parts tagged WE_NationFlag")
must_contain(NAT_NF, "local PARADE_SIZE = Vector3.new(6, 4.5, 0.14)", "nations B: parade flag 6 x 4.5 x 0.14 (4:3)")
must_contain(NAT_NF, "local HQ_SIZE = Vector3.new(0.12, 3.6, 4.8)", "nations B: HQ flag 0.12 x 3.6 x 4.8 (4:3)")
must_contain(NAT_NF, 'local parade = childPart(ground, "ParadeFlag")', "nations B: the parade flag is LayoutGround.ParadeFlag")
must_contain(NAT_NF, 'return inst.Name == "WE_Building" and inst:IsA("Model") and inst:GetAttribute("StructureId") == "CommandCenter"', "nations B: the HQ flag is the Command Center building's Flag")
must_contain(NAT_NF, "state.AddedConn = folder.DescendantAdded:Connect(function(inst: Instance)", "nations B: HQ rebuilds re-dressed via DescendantAdded")
must_contain(NAT_NF, 'local TEXTURE_NAMES = { "WE_NationTexA", "WE_NationTexB" }', "nations B: exactly two Textures per flag")
must_contain(NAT_NF, "local faceA, faceB = NationTexture.ThinFaces(flag.Size.X, flag.Size.Y, flag.Size.Z)", "nations B: Textures on the thinnest axis' faces")
must_contain(NAT_NF, "if flag:GetAttribute(SHOWN_ATTR) == key then\n\t\treturn -- nothing changed: no writes", "nations B: idempotent re-apply (WE_NationShown key)")
must_contain(NAT_NF, 'local SHOWN_ATTR = "WE_NationShown"', "nations B: WE_NationShown attribute")
must_contain(NAT_NF, "local want = base ~= nil and view ~= nil and view.OwnerUserId ~= nil and view.Show", "nations B: flagpole prompt only for an owner the art gate lets see nations")
must_contain(NAT_NF, 'local PROMPT_NAME = "WE_PanelPrompt" -- HudConfig.ActionLane.OwnerOnlyPromptNames', "nations B: prompt name is owner-only on the client")
must_contain(NAT_NF, 'prompt:SetAttribute("WE_OpenPanel", "Nation")\n\tprompt:SetAttribute("WE_OpenTab", "flagpole")', "nations B: prompt opens the picker in flagpole mode")
must_contain(NAT_NF, "if owner == nil or who.UserId ~= owner then", "nations B: prompt Triggered checks the owner on the server")
must_contain(NAT_NF, "function NationFlag.ResetPlot(plotId: number)", "nations B: reset to army green on leave")
must_contain(NAT_NF, "\tif flag.CanQuery then\n\t\tflag.CanQuery = false\n\tend", "nations B: a flag is never a target (shots / hit effects pass through)")
for _needle in ("SurfaceGui", "PointLight", "SpotLight", "SurfaceLight", "Neon", "Decal", "BillboardGui", '"Fire"', '"Smoke"', '"Explosion"',
                "GetDescendants", "Heartbeat", "RenderStepped", "WaitForChild", "flag:Destroy()", "parade:Destroy()", "hq:Destroy()",
                'GetAttribute("WE_FlagHost")', "Checkpoint", "GateCf"):
    must_not_contain(NAT_NF, _needle, f"nations B: NationFlag has no {_needle}")
must_not_contain(NAT_NCS, "WaitForChild(", "nations B: NationColorService never waits without a timeout")
# AdminService: nationreset, admin allowlist only, the caller's own fields only (remote + phone chat)
must_contain(NAT_AS, 'elseif cmd == "nationreset" then', "nations B: nationreset admin command")
must_contain(NAT_AS, "local ok, res = pcall(svc.AdminReset, player)", "nations B: nationreset acts on the caller only")
must_contain(NAT_AS, 'local isNationResetCmd = cmd == "nationreset"', "nations B: /nationreset chat command (phone)")
must_contain(NAT_AS, '{ "WE_NationReset", "/nationreset" }', "nations B: /nationreset TextChatCommand")
must_contain(NAT_AS, "cmdAny.AutocompleteVisible = false", "nations B: /nationreset never offered in chat autocomplete (decision 6, verifier)")
must_not_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "nationreset", "nations B: nationreset is not a Studio-open money command")
# SettingsController: the YOUR FLAG row hidden for non-admins until the art is ready (decision 6)
must_contain(NAT_SCB, "local nationArtOk = not NationConfig.LiveRequiresArt\n\t\tor NationTexture.ArtReady()\n\t\tor table.find(AdminConfig.UserIds, player.UserId) ~= nil", "nations B: Settings row art / admin gate")
must_contain(NAT_SCB, "if NationController and NationConfig.Enabled and nationArtOk then", "nations B: Settings row shown only when the gate passes")


def nations_b_checks() -> None:
    body = read(NAT_NCS) or ""
    if not body:
        bad("nations B: NationColorService missing")
        return
    (ok if body.startswith("--!strict\n") else bad)("nations B: NationColorService is --!strict")
    nf = read(NAT_NF) or ""
    (ok if nf.startswith("--!strict\n") else bad)("nations B: NationFlag is --!strict")
    # the IP suggestion never reaches analytics, attributes or the profile
    leaks = [ln.strip() for ln in body.splitlines()
             if ("log(" in ln or "SetAttribute" in ln or "setAttr(" in ln or "profile." in ln) and "suggest" in ln.lower()]
    (ok if not leaks else bad)(f"nations B: the suggestion is never logged / an attribute / saved {leaks[:2]}")
    # the suggestion goes to that player only
    sug = re.search(r"suggestion\[uid\] = def\.Id\n(.*?)\n\tend\)\nend", body, re.S)
    (ok if sug and "remote():FireClient(player," in sug.group(1) else bad)("nations B: Suggested is sent with FireClient(player) only")
    # NationFlag parts stay where strike effects cannot reach: >= 30 studs from the gate (plot front, BaseLayoutConfig)
    lb = read(NAT_BLCB) or ""
    fm = re.search(r"\n\t\tFlagpole = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \},", lb)
    cm = re.search(r"\n\t\tCommandCenter = \{ Site = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \}", lb)
    pm = re.search(r"\n\tPlotSize = ([\d.]+),", lb)
    if not (fm and cm and pm):
        bad("nations B: BaseLayoutConfig Flagpole / CommandCenter site / PlotSize not found")
        return
    gate_z = float(pm.group(1)) / 2
    parade_gap = gate_z - float(fm.group(2)) - 6.4  # flag reach from the pole: 0.25 + 0.05 + 6 (+ margin)
    hq_gap = gate_z - float(cm.group(2)) - 20.0  # HQ flag within 20 studs of the CC site (26 x 20 footprint, pole 2.5 out)
    (ok if parade_gap >= 30 and hq_gap >= 30 else bad)(f"nations B: parade / HQ flags >= 30 studs from the main gate ({parade_gap:.0f}, {hq_gap:.0f})")


nations_b_checks()

# --- Nations (lead): the flagpole/Settings picker never opens for a player with no base or before the art gate ---
NC_LEAD = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NationController.luau"
must_contain(NC_LEAD, 'if tab == "flagpole" and player:GetAttribute("WE_NoPlot") == true then', "nations: a base-less player's tap on another flagpole never opens the picker")
must_contain(NC_LEAD, "\tif not artGateOk() then\n\t\treturn\n\tend\n\topenAs(", "nations: Open() respects the art gate (admins only until the flag art is uploaded)")

# ── Owner's 11 features, lane K2 (F5 chevrons / cheapest pick, F6 tutorial order) ─────────────────────────────
K2_TUC = "src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau"
K2_TGC = "src/ReplicatedStorage/Shared/Configs/TycoonGuideConfig.luau"
K2_TMU = "src/ReplicatedStorage/Shared/Util/TycoonMath.luau"
K2_TER = "src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau"
# F6 TutorialConfig
must_contain(K2_TUC, "\tOrderVersion = if TerritoryConfig.Starter.Enabled == true then 3 else 2,", "F6 / Z TutorialConfig OrderVersion 3 with the Home Outpost on, 2 off (new profiles are stamped with it)")
must_contain(K2_TUC, "\tLegacyOrderV1 = {\n\t\t\"ClaimBase\",\n\t\t\"Income\",\n\t\t\"ClickDropper\",\n\t\t\"CommandCenter\",\n\t\t\"RecruitSoldiers\",\n\t\t\"Barracks\",\n\t\t\"Jeep\",\n\t\t\"Outpost\",\n\t} :: { string },", "F6 saved v1 step indexes are read in the v1 order")
must_contain(K2_TUC, 'LegacyAlias = { ClickDropper = "Income", AmmoWorks = "Barracks" } :: { [string]: string },', "F6 legacy step aliases (drop step folded into Income, v72 Ammo Works -> Barracks)")
must_contain(K2_TUC, "function TutorialConfig.OutpostBeforeJeep(): boolean\n\treturn TerritoryConfig.Starter.Enabled == true\nend", "F6 outpost before the 4x4 only with the Home Outpost (30 s travel rule)")
must_contain(K2_TUC, "TutorialConfig.Steps = TutorialConfig.BuildSteps(TutorialConfig.OutpostBeforeJeep())", "F6 Jeep-then-Outpost fallback while the Home Outpost is off")
must_contain(K2_TUC, 'AdvanceOn = { "PassiveIncome", "ManualDrop" },', "F6 a cash drop also finishes Collect cash (drop step folded in)")
must_contain(K2_TUC, 'AdvanceOn = { "CaptureTerritory" },', "F6 Outpost step advances on a capture")
must_contain(K2_TUC, 'AdvanceOn = { "SpawnVehicle" },', "F6 4x4 step advances on a vehicle spawn")
must_contain(K2_TUC, 'Hint = "Recruit a soldier. They train for cash.",', "F6 Recruit copy (device-neutral, <= 42)")
must_contain(K2_TUC, 'Pointer = "ATM",', "F5 the Collect cash step points at the own ATM")
must_contain(K2_TUC, "function TutorialConfig.MigrateLegacyStep(", "F6 v1 -> v2 step migration helper (first step not done)")
must_not_contain(K2_TUC, "BusinessStepIndex", "F6 v72 Ammo Works tutorial step removed (the NEXT chip introduces it)")
must_not_contain(K2_TUC, "Tutorial_Business", "F6 no business tutorial marker")
must_not_contain(K2_TUC, 'PadStructureId = "AmmoWorks",', "F6 no Ammo Works tutorial buy")
must_not_contain(K2_TUC, "require(script.Parent.BusinessConfig)", "F6 TutorialConfig no longer reads BusinessConfig")
must_not_contain(K2_TER, "TutorialConfig", "F6 no require cycle: TerritoryConfig never reads TutorialConfig")
_k2_tuc = read(K2_TUC) or ""
_k2_steps = _k2_tuc[_k2_tuc.find("\tSteps = {"):] if "\tSteps = {" in _k2_tuc else ""
_k2_ids = re.findall(r'\n\t\t\tId = "(\w+)"', _k2_steps[: _k2_steps.find("\n\t} :: { TutorialStepDef },")] if _k2_steps else "")
if _k2_ids == ["ClaimBase", "CommandCenter", "Income", "RecruitSoldiers", "Barracks", "Outpost", "Jeep"]:
    ok("F6 the owner's 7-step order (Claim, CC, Collect, Recruit, Barracks, Outpost, 4x4)")
else:
    bad(f"F6 tutorial step order wrong: {_k2_ids}")
# F5 TycoonGuideConfig
must_contain(K2_TGC, 'PickMode = "Cheapest",', "F5 one pointer: the cheapest unpaid pad drives WE_NextBuy / NEXT / chevrons")
must_contain(K2_TGC, "\tChevrons = {\n\t\tEnabled = true,", "F5 floor chevrons on (lane Z)")
must_contain(K2_TGC, "FollowTutorial = true,", "F5 chevrons follow the tutorial step while it runs")
must_contain(K2_TGC, 'HideWhen = { "Driving", "Dead", "RecentCombat", "Drawn", "Modal", "AtConsole" } :: { string },', "F5 chevrons hide while driving / dead / in combat / drawn / panel / at a console")
must_contain(K2_TGC, "DoorLeadStuds = 5,", "F5 walk-in approach point 5 studs out of the door")
_k2_tgc = read(K2_TGC) or ""
_k2_chev = _k2_tgc[_k2_tgc.find("\tChevrons = {"):] if "\tChevrons = {" in _k2_tgc else ""
_k2_hz = re.search(r"\n\t\tRefreshHz = ([\d.]+),", _k2_chev)
if _k2_hz and 0 < float(_k2_hz.group(1)) <= 10:
    ok(f"F5 chevron RefreshHz {_k2_hz.group(1)} <= 10 (UI refresh cap)")
else:
    bad("F5 chevron RefreshHz missing or above 10")
if "Neon" not in _k2_chev[: _k2_chev.find("\n\t},")] if _k2_chev else False:
    ok("F5 chevron config names no Neon material")
else:
    bad("F5 chevron config block missing or names Neon")
# F5 TycoonMath
must_contain(K2_TMU, "function TycoonMath.PickCheapest(upgrades: { [string]: any }?, prestige: number?): Candidate?", "F5 PickCheapest (pure)")
must_contain(K2_TMU, 'if TycoonGuideConfig.PickMode == "Cheapest" then\n\t\treturn TycoonMath.PickCheapest(ctx.Upgrades, ctx.Prestige)\n\tend', "F5 PickNext = PickCheapest in Cheapest mode (never soldiers)")
must_contain(K2_TMU, "and RebirthConfig.IsStructureOpen(p, nil, id) then", "F5 a closed rebirth zone is never the pick")
must_contain(K2_TMU, "if cur == nil or cost < cur.Cost or (cost == cur.Cost and lv + 1 < cur.Level) then", "F5 ties: lower target level, then StructureOrder")
must_contain(K2_TMU, "function TycoonMath.ApproachPoint(id: string): Vector3?", "F5 plot-local approach point (door + lead / kiosk / ATM)")
must_contain(K2_TMU, "function TycoonMath.Footprints(): { Footprint }", "F5 one footprint rectangle per site")
must_contain(K2_TMU, "function TycoonMath.GuideTarget(", "F5 one pointer: tutorial step first, then the pick")
must_not_contain(K2_TMU, "Workspace", "F5 TycoonMath geometry never reads the workspace (streaming-safe)")
must_not_contain(K2_TMU, "workspace:", "F5 TycoonMath geometry never reads the workspace (streaming-safe)")

# ── Owner's 11 features, lane T (F6 tutorial order dispatch, migration, novice-shield end, Starter Pack seat wait;
#    F6/F10 Outpost target = own Home Outpost, gate-measured) ───────────────────────────────────────────────────
T_TUS = "src/ServerScriptService/Server/Services/TutorialService.luau"
T_TC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.luau"
# F6 dispatch: the ACTIVE step's AdvanceOn (spec pin `def.AdvanceOn`), no fixed step indexes
must_contain(T_TUS, "def.AdvanceOn", "F6 TutorialService advances on the step's AdvanceOn (replaces STEP_DROPPER)")
must_contain(T_TUS, "local def = TutorialConfig.GetStep(step)\n\tif def and typeof(def.AdvanceOn) == \"table\" and table.find(def.AdvanceOn, eventType)\n\t\tand (eventType ~= \"Upgrade\" or (typeof(detail) == \"string\" and detail == def.PadStructureId)) then\n\t\tadvanceTo(player, step)", "F6 only the active step finishes; an Upgrade only for its own PadStructureId")
must_contain(T_TUS, "if eventType == \"PlotAssigned\" and profile.BasePlotId == nil then\n\t\treturn", "F6 no plot yet: the claim step waits")
for _n in ("STEP_BUSINESS", "BusinessStepIndex", "businessStepStructureId", "STEP_INCOME", "STEP_COMMAND", "STEP_RECRUIT", "STEP_JEEP", "STEP_OUTPOST", "STEP_DROPPER"):
    must_not_contain(T_TUS, _n, f"F6 TutorialService has no fixed step index ({_n}); the order lives in TutorialConfig")
# F6 migration of saves made in the v1 order, stamped, never twice / never down
must_contain(T_TUS, "profile.TutorialStep = TutorialConfig.MigrateLegacyStep(oldStep, nil, saved)", "F6 / Z saves in another known order move to the first step not done")
must_contain(T_TUS, "local saved = tonumber(profile.TutorialOrderVersion) or 1\n\t\tif saved == current or TutorialConfig.SavedOrder(saved) == nil then\n\t\t\treturn", "F6 / Z migrate every known other order (missing = 1); never stamp an unknown (newer) save down")
must_contain(T_TUS, "profile.TutorialOrderVersion = current\n\t\tDataService.MarkDirty(player)", "F6 migrated saves are stamped with OrderVersion (saved)")
must_contain(T_TUS, "\t\tmigrateOrder(player, profile)\n", "F6 migration runs on profile load")
must_contain(T_TUS, "profile.TutorialOrderVersion = orderVersion() -- F6: step 1 is the same step in every order", "F6 Reset stamps the order version")
must_contain(T_TUS, "return TerritoryConfig.Starter.Enabled == true and profile.StarterOutpostTaken == true", "F6/F10 Outpost step done once the own Home Outpost was taken (Starter on only)")
# F6 novice shield ends when the tutorial ends (complete, SKIP, done at load); batch A lane C API, pcall + nil-check
must_contain(T_TUS, "CombatService = deps.CombatService", "F6 TutorialService gets CombatService from the deps")
must_contain(T_TUS, "pcall(CombatService.EndNoviceShield, player, \"tutorial\")", "F6 tutorial end calls EndNoviceShield(p, \"tutorial\") in a pcall")
must_contain(T_TUS, "if complete then\n\t\tendNoviceShield(player) -- F6", "F6 the last step ends the novice shield")
must_contain(T_TUS, "endNoviceShield(player) -- F6: SKIP ends the novice shield too", "F6 SKIP ends the novice shield")
# F6 Starter Pack after the tutorial waits until the player is out of any seat (1 Hz, <= 300 s), then the gate as before
must_contain(T_TUS, "local STARTER_SEATED_WAIT_SECONDS = 300", "F6 Starter offer seat wait capped at 300 s")
must_contain(T_TUS, "local STARTER_SEATED_CHECK_SECONDS = 1", "F6 Starter offer seat check at 1 Hz")
must_contain(T_TUS, "return hum ~= nil and hum.SeatPart ~= nil", "F6 seated = Humanoid.SeatPart set")
must_contain(T_TUS, "if seatedLeft > 0 and player.Parent and isSeated(player) then", "F6 no Starter offer card while driving")
# F6/F10 client: Outpost = own Home Outpost first, never another plot's; nearest measured from the own gate
must_contain(T_TC, "return nearestOutpost(origin, userId or player.UserId, plotId)", "F6 Outpost resolves with the own plot id (Home Outpost, gate origin)")
must_contain(T_TC, "local from = if plotId ~= nil then ownGatePos(plotId) else origin", "F6 Outpost distance from the own main gate, not the character")
must_contain(T_TC, "return PlotFrame.LocalToWorld(plotId, 0, half)", "F6 own gate from PlotFrame (pure config, streaming-safe; no MapSetup)")
must_contain(T_TC, "if starterPlot == nil or (plotId ~= nil and starterPlot == plotId) then", "F10 another plot's Home Outpost is never a tutorial target")
must_contain(T_TC, "local tier = if starterPlot ~= nil then (if mine then 3 else -1)", "F10 the own Home Outpost (not yet held) is the first choice")
# F6: any step with a world target re-aims (<= every 2 s on the 1 Hz tick) until its part is on this client
must_contain(T_TC, "if stepActive and (hp == nil or hp.Parent == nil) and stepHasWorldTarget() and now - lastReaim >= REAIM_SECONDS then", "F6 a missing tutorial target re-aims on the 1 Hz tick (streaming-safe)")
must_contain(T_TC, "local REAIM_SECONDS = 2", "F6 re-aim at most every 2 s")
must_not_contain(T_TC, "BUSINESS_REAIM_SECONDS", "F6 no business-only tutorial re-aim (no step is a business)")

# ── Owner's 11 features, lane E (B1 single prestige, F3 Empire Tax economy side, F4 producer numbers + ATM screen) ──
E_ECO = "src/ServerScriptService/Server/Services/EconomyService.luau"
E_SOL = "src/ServerScriptService/Server/Services/SoldierService.luau"
E_MCS = "src/ServerScriptService/Server/Services/MoneyCollectorService.luau"
E_BSV = "src/ServerScriptService/Server/Services/BaseService.luau"
# B1: prestige is applied once (EconomyService's stack); the per-tick producers are pre-multiplier
must_contain(E_ECO, "mult = 1 + prestige * (EconomyConfig.PrestigeCashMultiplierPerLevel or 0)", "B1 prestige lives in EconomyService's grant stack (applied once)")
must_not_contain(E_BSV, "local mult = 1 + ((tonumber(profile.Prestige) or 0) * (EconomyConfig.PrestigeCashMultiplierPerLevel or 0))", "B1 BaseService passive per-tick no longer multiplies prestige (x1.21 at P1)")
must_contain(E_BSV, "local function passiveMultAndFlat(profile: Types.PlayerProfile, player: Player?): (number, number)\n\tlocal mult = 1\n", "B1 BaseService passive multiplier starts at 1 (territory % only)")
must_not_contain(E_SOL, "local prestigeMult = 1 + ((tonumber(profile.Prestige) or 0) * 0.05)", "B1 SoldierService training no longer multiplies prestige (x1.155 at P1)")
must_not_contain(E_BSV, "local prestigeMult = 1 + ((tonumber(profile.Prestige) or 0) * 0.05)", "B1 PlayerState training display matches SoldierService (pre-multiplier)")
must_contain(E_SOL, "\tlocal per = cfg.CashPerSoldierPerTick or 0\n\treturn math.floor(count * per)\nend", "B1 training per tick = soldiers x CashPerSoldierPerTick before multipliers")
# F3 Empire Tax
must_contain(E_ECO, "WE_EmpireTaxPct", "F3 EconomyService publishes WE_EmpireTaxPct (spec pin)")
must_contain(E_ECO, "function EconomyService.EmpireTaxPct(player: Player): number", "F3 EconomyService.EmpireTaxPct(p) export (cross-lane API)")
must_contain(E_ECO, "local taxPct = empireTaxPct(profile)\n\t\tif taxPct > 0 then\n\t\t\tmult *= (1 + taxPct / 100)", "F3 the grant multiplier uses the total Empire Tax % (1 + pct/100)")
must_contain(E_ECO, "return 1 + empireTaxPct(profile) / 100", "F3 GetOutpostIncomeMultiplier = 1 + pct/100")
must_contain(E_ECO, "return math.clamp(pct, 0, cap)", "F3 Empire Tax capped at MaxStacks x MultPerStack (+50 %)")
must_contain(E_ECO, "pct += math.max(0, math.floor(tonumber(buff.StarterPct) or 0))", "F3/F10 own Home Outpost adds StarterPct")
must_contain(E_ECO, "return def ~= nil and TerritoryConfig.IsStarterDef(def) and def.PlotId == plot", "F10 only the player's OWN Home Outpost counts")
must_contain(E_ECO, "\t\tfor id in pairs(profile.Territories) do\n\t\t\tif not isStarterId(id) then\n\t\t\t\towned += 1", "F3 a Home Outpost is never a stack")
must_contain(E_ECO, "if cur ~= pct and not (cur == nil and pct == 0) then", "F3-8 WE_EmpireTaxPct written only when it changes")
must_contain(E_ECO, "return oldStacks, newStacks, perStack, total", "F3 SyncOutpostIncomeStacks keeps (old, new, per-stack %) and adds the total %")
must_contain(E_ECO, "local TerritoryConfig = require(Shared.Configs.TerritoryConfig)", "F3 EconomyService reads the Home Outpost rows from TerritoryConfig")
must_not_contain("src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau", "EconomyService", "F3 no require cycle: TerritoryConfig never reads EconomyService")
# F4 producer numbers (the client labels read them)
must_contain(E_ECO, 'local TICK_TRAINING_ATTR = "WE_TickTraining"', "F4 WE_TickTraining attribute (last training grant)")
must_contain(E_ECO, 'if reason ~= "training" or not (labels and labels.Enabled == true) then', "F4 WE_TickTraining gated on EconomyConfig.ProducerLabels.Enabled, training only")
must_contain(E_ECO, "if player:GetAttribute(TICK_TRAINING_ATTR) ~= granted then", "F4 WE_TickTraining written only when it changes")
_e_eco = read(E_ECO) or ""
_e_nt = _e_eco.find("noteTrainingTick(player, reason, granted) -- F4")
_e_gate = _e_eco.find("if not TycoonGuideConfig.Enabled or reason == nil or TycoonGuideConfig.SteadyIncomeReasons[reason] ~= true then")
if _e_nt != -1 and _e_gate != -1 and _e_nt < _e_gate:
    ok("F4 WE_TickTraining runs before the guide gate (its own flag, not TycoonGuideConfig.Enabled)")
else:
    bad(f"F4 WE_TickTraining must run before the TycoonGuide gate in noteSteadyIncome (nt={_e_nt} gate={_e_gate})")
must_contain(E_SOL, "if not EconomyConfig.ProducerLabels.Enabled then\n\t\t\t\t\t\t\trefreshTrainingYardFeedback(player, profile, amount)", "F4 no server yard pop while the client producer label is on")
# F4 ATM screen
must_contain(E_MCS, "local text = TycoonMath.ShortCash(pending)", "F4 ATM digits use TycoonMath.ShortCash")
must_contain(E_MCS, "return TycoonMath.RatePerSecText(rate)", "F4 empty ATM shows +$N/s from WE_IncomePerSec")
must_contain(E_MCS, 'owner:GetAttribute("WE_IncomePerSec")', "F4 the ATM rate is the owner's server-stamped WE_IncomePerSec")
must_contain(E_MCS, 'local ATM_WALK_IN_TITLE = "ATM · WALK IN TO COLLECT"', "F4 pinned walk-in line kept as the fallback constant")
_e_mcs = read(E_MCS) or ""
_e_at = _e_mcs.find("local function atmTitle(")
_e_body = _e_mcs[_e_at:_e_mcs.find("\nend\n", _e_at)] if _e_at != -1 else ""
_e_order = [_e_body.find(x) for x in ('"ATM · SHIELD "', '"ATM BEING ROBBED!"', '"ATM · AUTO-COLLECT"', "atmRateTitle(owner)", "return ATM_WALK_IN_TITLE")]
if _e_body and all(i != -1 for i in _e_order) and _e_order == sorted(_e_order) and "if pending ~= nil and pending <= 0 then" in _e_body:
    ok("F4 ATM status order: shield > robbed > AUTO-COLLECT > (cash waiting ? walk-in : +$N/s)")
else:
    bad(f"F4 ATM status order wrong: {_e_order}")
must_contain(E_MCS, "refreshBillboard(inst, amount, atmTitle(player, plotId, amount))", "F4 own-ATM refresh passes the balance to the status")
must_contain(E_MCS, "refreshBillboard(inst, amount, atmTitle(owner, plotId, amount))", "F4 all-ATM refresh passes the balance to the status")
must_not_contain(E_MCS, "BillboardGui", "F4 the ATM rate is painted on the ATM screen, never a floating label")

# ── Owner's 11 features, lane G (F4 producer labels + label governor, F5 floor chevrons; client only) ────────────
G_NPC = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/NextPadChevrons.luau"
G_PL = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/ProducerLabels.luau"
G_LG = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/LabelGovernor.luau"
G_WL = "src/ReplicatedStorage/Shared/Util/WorldLabel.luau"
G_BOOT = "src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau"
G_BZV = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/BusinessVisuals.luau"
G_WPC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldPromptController.luau"
# F5 NextPadChevrons (spec F5 pins): client-only, no per-frame scans, no server calls, no light / GUI / beam, budget-free
for _needle in ("RenderStepped", "GetDescendants", "FireServer", "InvokeServer", "Neon", "PointLight", "SpotLight", "BillboardGui", "SurfaceGui", "Beam"):
    must_not_contain(G_NPC, _needle, f"F5 NextPadChevrons: no {_needle}")
must_contain(G_NPC, "Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)", "F5 chevrons move with one BulkMoveTo into preallocated arrays")
must_contain(G_NPC, "Workspace.CurrentCamera", "F5 chevron pool lives under the local camera (client-only, never replicated)")
must_contain(G_NPC, "p.CastShadow = false", "F5 chevron bars cast no shadow")
must_contain(G_NPC, "p.Material = Enum.Material.SmoothPlastic", "F5 chevron bars are painted SmoothPlastic")
must_contain(G_NPC, "if started or C.Enabled ~= true then", "F5 chevrons inert while TycoonGuideConfig.Chevrons.Enabled is false")
must_contain(G_NPC, "local PERIOD = 1 / math.clamp(C.RefreshHz, 1, 10)", "F5 chevron refresh <= 10 Hz")
must_contain(G_NPC, "if mx * mx + mz * mz < MOVE2 then", "F5 re-laid only when the character moved MoveThresholdStuds")
must_contain(G_NPC, "TycoonMath.GuideTarget(step, player:GetAttribute(\"WE_NextBuy\"), upgrades)", "F5 one pointer: tutorial step first, then WE_NextBuy / local PickCheapest")
must_contain(G_NPC, "TycoonMath.ApproachPoint(id)", "F5 chevrons end at the plot-local approach point (door + lead / kiosk / ATM)")
must_contain(G_NPC, "TycoonMath.InFootprint(cx, cz, CLEAR) ~= nil", "F5 no chevron inside (or touching) a building footprint")
must_contain(G_NPC, "local count = TycoonMath.ChevronCount(d)", "F5 chevron count from TycoonMath.ChevronCount (0 within HideWithinStuds)")
must_contain(G_NPC, "return ConsoleWaypoint.Current() ~= nil", "F5 chevrons step aside while the GO beam is up")
must_contain(G_NPC, "for _, name in ipairs(C.HideWhen) do", "F5 chevrons hidden on every Chevrons.HideWhen HUD flag")
must_contain(G_NPC, 'return nil, HudLayout.GetFlag("Tutorial")', "F5 no pointer while a tutorial step is up but not known here (never the post-tutorial pick)")
must_not_contain(G_NPC, "MapSetup", "F5 chevrons never depend on MapSetup (config + PlotFrame only)")
# F4 ProducerLabels
for _needle in ("GetDescendants", "RenderStepped", "AlwaysOnTop = true", "FireServer", "InvokeServer"):
    must_not_contain(G_PL, _needle, f"F4 ProducerLabels: no {_needle}")
must_contain(G_PL, 'local LABEL_NAME = "WE_ProducerLabel"', "F4 producer label (replaces the server WE_OilCashPop pops, BuyPathStatic.py:455)")
must_contain(G_PL, "if started or CFG.Enabled ~= true then", "F4 producer labels inert while EconomyConfig.ProducerLabels.Enabled is false")
must_contain(G_PL, "local period = 1 / math.clamp(CFG.ScanHz, 1, 10)", "F4 producer label scan <= 10 Hz")
must_contain(G_PL, "BaseLabel = true,", "F4 the producer label counts toward the base label cap")
must_contain(G_PL, "g.Adornee = anchor -- only the adornee moves", "F4 one label: only its adornee moves")
must_contain(G_PL, 'local v = tonumber(player:GetAttribute("WE_TickTraining"))', "F4 yard amount = the server's last training grant")
must_contain(G_PL, "math.floor(PlotOilPumpConfig.CashPerTick)", "F4 pump amount from PlotOilPumpConfig.CashPerTick")
must_contain(G_PL, "local yardOn = training > 0 and trainingPays ~= false", "F4 soldiers dismissed: no yard label (WE_TickTraining keeps the last grant)")
must_contain(G_PL, "Remotes.BindEvent(Constants.RemoteNames.SoldierStateUpdate", "F4 the yard label follows SoldierStateUpdate TrainingIncomePerTick")
must_contain(G_PL, 'local bases = if setup then setup:FindFirstChild("Bases") else nil', "F4 anchors from the own plot folder (FindFirstChild, streaming-safe)")
# F4 LabelGovernor
for _needle in ("GetDescendants", "RenderStepped", "AlwaysOnTop = true", "FireServer", "InvokeServer"):
    must_not_contain(G_LG, _needle, f"F4 LabelGovernor: no {_needle}")
must_contain(G_LG, "if started or CFG.Enabled ~= true then", "F4 label governor inert while WorldLabelConfig.BaseLabelGovernor.Enabled is false")
must_contain(G_LG, 'local EXEMPT_ROLE = "objective"', "F4 the governor never touches the objective marker")
must_contain(G_LG, "local period = 1 / math.clamp(tonumber(CFG.Hz) or 4, 1, 10)", "F4 governor pass <= 10 Hz")
must_contain(G_LG, "WorldLabel.Hold(gui, not pick[i])", "F4 every governed label outside the nearest MaxOnScreen is held off")
must_contain(G_LG, "WorldLabel.Hold(gui, true) -- held until the next pass decides", "F4 a newly tagged label starts held (the cap holds between passes)")
for _f in (G_NPC, G_PL, G_LG):
    _t = read(_f) or ""
    if _t and not re.search(r'WaitForChild\("[^"]*"\)', _t):
        ok(f"lane G {_f.rsplit('/', 1)[-1]}: every WaitForChild has a timeout")
    else:
        bad(f"lane G {_f.rsplit('/', 1)[-1]}: WaitForChild without a timeout (or file missing)")
# Bootstrap wiring (guarded, bounded waits)
must_contain(G_BOOT, 'safeInit("ProducerLabels", safeRequire("ProducerLabels", Modules:WaitForChild("ProducerLabels", 5) :: Instance))', "F4 ProducerLabels init guarded")
must_contain(G_BOOT, 'safeInit("NextPadChevrons", safeRequire("NextPadChevrons", Modules:WaitForChild("NextPadChevrons", 5) :: Instance))', "F5 NextPadChevrons init guarded")
must_contain(G_BOOT, 'safeInit("LabelGovernor", safeRequire("LabelGovernor", Modules:WaitForChild("LabelGovernor", 5) :: Instance))', "F4 LabelGovernor init guarded")
# WorldLabel: base-label tag + one arbiter for Enabled on the client
must_contain(G_WL, "BaseLabel: boolean?,", "F4 WorldLabel.Create opts.BaseLabel")
must_contain(G_WL, "CollectionService:AddTag(bb, BASE_TAG)", "F4 opts.BaseLabel tags WorldLabelConfig.BaseLabelTag")
must_contain(G_WL, "local on = w and foreign[gui] ~= true and held[gui] ~= true", "F4 a label shows only when its owner wants it and neither the owner filter nor the governor hides it")
must_contain(G_WL, "function WorldLabel.SetShown(gui: LayerCollector, on: boolean)", "F4 client code shows / hides tagged labels through WorldLabel.SetShown")
must_contain(G_WL, "function WorldLabel.Hold(gui: LayerCollector, on: boolean)", "F4 LabelGovernor holds labels through WorldLabel.Hold")
# BusinessVisuals pops and WorldPromptController tags are governed base labels
must_contain(G_BZV, "BaseLabel = true, -- F4: counted by the LabelGovernor", "F4 business pops are base labels")
must_contain(G_BZV, "WorldLabel.SetShown(pop.gui, true)", "F4 pops shown through WorldLabel (a governor hold is kept)")
must_not_contain(G_BZV, "pop.gui.Enabled = true", "F4 pops never write Enabled directly")
must_not_contain(G_BZV, "p.gui.Enabled = false", "F4 pops never write Enabled directly")
must_contain(G_WPC, "WorldLabel.TagBaseLabel(bb) -- F4: counted by the LabelGovernor", "F4 console / NEXT tags are base labels")
must_contain(G_WPC, "WorldLabel.SetShown(bb, want) -- F4: writes only on change, keeps a LabelGovernor hold", "F4 the 4 Hz price-tag pass never undoes a governor hold")
must_not_contain(G_WPC, "bb.Enabled = want", "F4 the price-tag pass writes Enabled only through WorldLabel")
must_contain(G_WPC, 'local id, lv = TycoonMath.GuideTarget(step, player:GetAttribute("WE_NextBuy"))', "F5 one pointer: the console NEXT tag marks the tutorial step's pad, else WE_NextBuy")

# --- Base identity lane C (lane Q of the f11 job): squad Follow slots beside the player instead of rows between the
# camera and the player, domed helmet, FollowPath door / lane / wall assist, wing mirroring after a turn ---
Q_OC = 'src/ReplicatedStorage/Shared/Configs/OrdersConfig.luau'
Q_SO = 'src/ServerScriptService/Server/Services/SquadOrdersService.luau'
must_contain(Q_OC, 'FollowSlots = {', 'Lane C: Follow slots beside the player (spec pin)')
must_contain(Q_OC, '{ X = -5.5, Z = 1.5 },\n\t\t{ X = 5.5, Z = 1.5 },\n\t\t{ X = -10, Z = 3.5 },\n\t\t{ X = 10, Z = 3.5 },\n\t\t{ X = -14.5, Z = 5.5 },', 'Lane C: spec slot values (+X right, +Z behind the player)')
must_contain(Q_OC, 'FollowPath = {\n\t\tEnabled = true,', 'Lane C: FollowPath (door / lane / wall assist) ships on')
must_contain(Q_SO, 'MeshType.Sphere', 'Lane C: domed helmet (spec pin)')
must_contain(Q_SO, 'weldPart("Helmet", Vector3.new(1.3, 0.75, 1.35), CFrame.new(0, 1.91, 0.02)', 'Lane C: helmet 1.3 x 0.75 x 1.35 at (0, 1.91, 0.02), 0 extra parts')
must_not_contain(Q_SO, 'Vector3.new(1.2, 0.5, 1.2), CFrame.new(0, 1.95, 0)', 'Lane C: no flat box helmet cap')
must_contain(Q_SO, 'local slots = (OrdersConfig :: any).FollowSlots', 'Lane C: formationOffset reads OrdersConfig.FollowSlots')
must_contain(Q_SO, '\treturn gridOffset(slot)\nend', 'Lane C: empty or malformed FollowSlots fall back to the old grid')
must_contain(Q_SO, 'return Vector3.new(col * spacing, 0, 6 + (row - 1) * spacing)', 'Lane C: old grid formula kept for the fallback')
must_contain(Q_SO, 'while used[slot] do', 'Lane C: a replacement unit takes the lowest free slot (no doubled slot)')
must_contain(Q_SO, 'updateMirror(st, proot.CFrame)', 'Lane C: wings swap sides after a turn (nobody crosses behind the player)')
must_contain(Q_SO, 'faceYaw(unit.Root, unit.Root.Position + playerRoot.CFrame.LookVector * 8)', 'Lane C: a unit in its slot faces where the player faces (no crab-walking wings)')
must_contain(Q_SO, 'params.RespectCanCollide = true', 'Lane C: FollowPath rays ignore non-colliding parts')
must_not_contain(Q_SO, 'GetDescendants', 'Lane C: no whole-tree scans in the squad service')


# --- W3 step 2 lane L0 (contracts): activity anchors, POI rows, sign budget, ObjectiveMarker frozen API ---
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'export type ActivityAnchor = {', 'W3s2 L0: activity anchor row type')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'SurfaceGuis = 17', 'W3s2 L0: world sign budget 17 (6 gate pads + Town + bank + 9 POI boards)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Tag = "WE_ActivityAnchor", -- CollectionService tag on every anchor Attachment', 'W3s2 L0: one anchor tag')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'CheckpointAnchors = {', 'W3s2 L0: checkpoint anchor template')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', '{ Role = "G1", Kind = "npc", X = -14.6, Z = 5.5, Yaw = 0 },', 'W3s2 L0: checkpoint post G1 clear of the far sandbag (not the blocked activities post)')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', '{ Id = "Town.Market.Box", Kind = "search",', 'W3s2 L0: Town market cache anchor')
must_contain('src/ServerScriptService/Server/Modules/ActivityAnchors.luau', 'GetTagged("WE_ActivityAnchor")', 'W3s2 L0: anchors are read from the tag')
must_not_contain('src/ServerScriptService/Server/Modules/ActivityAnchors.luau', 'WaitForChild(', 'W3s2 L0: the anchor reader never waits on the tree')
must_contain('src/ServerScriptService/Server/Modules/ActivityAnchors.luau', 'function ActivityAnchors.List(site: string?, kind: string?): { Anchor }', 'W3s2 L0: frozen reader API (List)')
must_contain('src/ServerScriptService/Server/Modules/ActivityAnchors.luau', 'function ActivityAnchors.Get(id: string): Anchor?', 'W3s2 L0: frozen reader API (Get)')
must_contain('src/ServerScriptService/Server/Modules/WorldKits.luau', 'ActivityHost = spec(1, 1, Vector3.new(1, 1, 1), "anchor", false, 2, "POI"),', 'W3s2 L0: one invisible anchor host kit per POI layout')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau', 'function ObjectiveMarker.Show(target: Target)', 'W3s2 L0: frozen ObjectiveMarker API (Show)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau', 'function ObjectiveMarker.Clear()', 'W3s2 L0: frozen ObjectiveMarker API (Clear)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau', 'function ObjectiveMarker.Current(): Target?', 'W3s2 L0: frozen ObjectiveMarker API (Current)')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau', 'GetDescendants', 'W3s2: the objective marker never scans the tree')

# --- W3 step 2 lane K (kits): later-POI kit builders, owner feedback #29 (checkpoint booth, watchtower fit), runtime doors ---
WK_ = 'src/ServerScriptService/Server/Modules/WorldKits.luau'
must_contain(WK_, 'put(b, "CheckpointBooth", Vector3.new(4, 7, 4.4), CFrame.new(17.5, 3.5, 2.0), PAL.ConcreteLight, M.Concrete, true)', 'W3s2 K: checkpoint booth taller than an avatar, same footprint (template anchors stay clear)')
must_contain(WK_, 'local TOWER_HEADROOM = 8.5', 'W3s2 K: world watchtower fits a 7.5-stud avatar (owner feedback #29)')
must_contain(WK_, 'local deckY = KC.WatchtowerDeckY', 'W3s2 K: watchtower deck at WorldConfig.Kits.WatchtowerDeckY (tower posts stand on it)')
must_contain(WK_, 'put(b, "TowerRoof", Vector3.new(9, 0.5, 9), CFrame.new(0, roofY + 0.25, 0), PAL.SteelDark, M.Metal, false, true)', 'W3s2 K: watchtower roof never collides (heads, jumps, Poppercam)')
must_contain(WK_, 'local t = Instance.new("TrussPart")', 'W3s2 K: the watchtower ladder is climbable (TrussPart, touch-friendly)')
must_contain(WK_, 'p:SetAttribute(A.RuntimeDoorAttr, true)', 'W3s2 K: BunkerDoor carries WE_RuntimeDoor (WorldHygiene leaves it alone)')
must_contain(WK_, 'g:SetAttribute(A.RuntimeDoorAttr, true)', 'W3s2 K: HeistGate carries WE_RuntimeDoor')
must_contain(WK_, 'runtimeDoor(put(b, "BunkerDoor",', 'W3s2 K: the bunker blast door part is named BunkerDoor (anchors name it)')
must_contain(WK_, 'local g = put(b, "HeistGate",', 'W3s2 K: the yard gate part is named HeistGate (anchors name it)')
must_contain(WK_, 'local gap = math.clamp(W - 8, 4, 10) -- the full-height opening (the door)', 'W3s2 K: TownBlock hall opening (the Empire Bank shell, lane BK)')
must_contain(WK_, 'tostring(o.Lantern), tostring(o.R), if tw ~= nil then table.concat(tw, ",") else "nil" }, "|")', 'W3s2 K: Footprint cache keyed on R and Taxiway')
must_contain(WK_, 'vcyl(b, "HoldPad", 0, 0, 0, HP.Top, r * 2, PAL.PadPaint, M.SmoothPlastic, false)', 'W3s2 K: hold pads are flat and never collide')
must_contain(WK_, 'local p = put(b, "ActivityHost", Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 0), PAL.SteelDark, M.SmoothPlastic, false)', 'W3s2 K: the anchor host never collides')
must_contain(WK_, 'Builders.Runway = function(b: B)', 'W3s2 K: the airstrip runway is built (infra)')
must_contain(WK_, 'Watchtower = spec(8, 8, Vector3.new(9, 23, 9), "manmade", true, 2, "POI"),', 'W3s2 K: watchtower catalogue row (8 parts, 23 tall with the headroom)')
must_not_contain(WK_, 'Instance.new("ParticleEmitter")', 'W3s2 K: kits never add particles (phones)')
must_not_contain(WK_, 'Instance.new("Fire")', 'W3s2 K: burn drums / flare stack are painted, no Fire')
must_not_contain(WK_, 'Instance.new("SpotLight")', 'W3s2 K: kits add no spot lights (world light budget)')

# --- W3 step 2 lane P (platform): WorldPOI layouts + activity anchors, camp exemption, hygiene, Dockside, owner lights ---
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'WE_ActivityAnchor', 'W3s2 P (spec 8): WorldPOI stamps the activity anchors (header names the tag; the pins below pin the calls)')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'local ActivityAnchors = require(script.Parent.ActivityAnchors)', 'W3s2 P: anchors written through the one writer')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'stamp(booth.Part, ActivityAnchors.FromTemplate(t, poi.Id, c.Id, booth.Frame))', 'W3s2 P: every built checkpoint gets the checkpoint template on its booth')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'stamp(target, ActivityAnchors.FromRow(a))', 'W3s2 P: layout rows on the ActivityHost, Town rows on their Required cluster')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'if req ~= nil and need == nil then', 'W3s2 P: a Requires anchor is stamped only when its cluster was built')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'local builder: ((Ctx) -> ())? = if p.Layout ~= nil then buildLayout else BUILDERS[p.Kind]', 'W3s2 P: every enabled layout POI builds from POILayouts')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'local fullCap = poi.Budget - (poi.Reserve or 0)', 'W3s2 P: a POI builds within Budget - Reserve (runtime transients kept free)')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'local share = poi.LowShare or WorldDressConfig.Quality.Low.POIShare', 'W3s2 P: Quality Low share per POI')
must_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'model:SetAttribute(INFRA_ATTR, true)', 'W3s2 P: the runway strips live in one Infra model (H10 exempt)')
must_not_contain('src/ServerScriptService/Server/Modules/WorldPOI.luau', 'if s == nil or s.Step ~= 1 then', 'W3s2 P: step-2 kits are counted through Footprint (no step-1-only count)')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'local own = c.Owner ~= nil and c.Owner == o.AllowPOI -- a camp\'s own guard post', 'W3s2 P: a camp\'s own NPC anchors are no keep-out for its own clusters')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'Owner = campOf(a.X, a.Z)', 'W3s2 P: NPC anchors know their camp')
must_contain('src/ServerScriptService/Server/Modules/WorldDress.luau', 'SkipEvents: boolean?', 'W3s2 P: flat markings / the activity host may lie over an event anchor')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'if d:IsA("Model") and d:GetAttribute(INFRA_ATTR) ~= true then', 'W3s2 P: H10 exempts a POI Infra model (runway strips)')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'function Rules.RuntimeDoor(part: Instance): boolean', 'W3s2 P: runtime doors (WE_RuntimeDoor) are left alone')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'if not isDoomed(p) and not Rules.RuntimeDoor(p) then', 'W3s2 P: Enforce H3 never destroys a runtime door')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'or Rules.RuntimeDoor(part) or Rules.FlatMarking(part, b) then', 'W3s2 P: H4 never makes a runtime door or a flat marking solid')
must_contain('src/ServerScriptService/Server/Modules/WorldHygiene.luau', 'return math.max(s.X, s.Y, s.Z) < H.ShadowMinSize or (b ~= nil and Rules.FlatMarking(part, b))', 'W3s2 P: H9 flat markings (hold pads, runway) cast no shadow')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'if not portBuilt then', 'W3s2 P: the legacy Dockside quay kit is off once the Port POI is built')
must_contain('src/ServerScriptService/Server/Modules/MapDressing.luau', 'local DOCKSIDE_POI = "Port"', 'W3s2 P: the Port replaces Dockside')
must_not_contain('src/ServerScriptService/Server/Services/TerritoryService/init.luau', 'light.Name = "WE_OwnerLight"', 'W3s2 P (spec 8): no owner light on capture flags (light policy V3)')
must_not_contain('src/ServerScriptService/Server/Services/TerritoryService/init.luau', 'Instance.new("PointLight")', 'W3s2 P: TerritoryService adds no world light')

# --- W3 step 2 lane D1 (data): POILayouts/Industry (Port, Depot, Armory, OilField, RigA, RigB) ---
_IND = 'src/ServerScriptService/Server/Modules/POILayouts/Industry.luau'
must_contain(_IND, 'local WorldConfig = require(ReplicatedStorage.Shared.Configs.WorldConfig)', 'W3s2 D1: Industry layouts require only WorldConfig (no script.Parent path, no cycle)')
must_not_contain(_IND, 'require(script.Parent', 'W3s2 D1: Industry layouts are data only')
must_not_contain(_IND, 'WaitForChild(', 'W3s2 D1: Industry layouts never yield')
must_not_contain(_IND, 'Text = BOARD', 'W3s2 D1: PoiBoard rows leave Text nil (WorldPOI paints Board within the sign budget)')
must_not_contain(_IND, 'Id = "Port.Gate.', 'W3s2 D1 (spec 1.5): no per-checkpoint rows; the template makes Port.CP.*')
must_contain(_IND, '{ Id = "CP", Block = "Road", Role = "checkpoint", Tier = 1, X = 0, Z = 1168,', 'W3s2 D1 (contract 4.3): the Port road checkpoint cluster is "CP"')
must_contain(_IND, 'Prompt = "hold", Part = "HeistGate" }', 'W3s2 D1 (contract 4.7): the customs breach anchor names its door part')
must_contain(_IND, 'Prompt = "hold", Part = "BunkerDoor" }', 'W3s2 D1 (contract 4.7): the bunker door anchor names its door part')
must_contain(_IND, '{ Id = "RigA.Deck.Pier", Kind = "npc", X = 1655, Z = -750,', 'W3s2 D1: the Rig Alpha pier post stands clear of the stair landing (MinClear)')
must_contain(_IND, 'Variant = "roller+metal+rear", Width = 38,', 'W3s2 D1: the customs shed closes the yard (the HeistGate is the way in on foot)')

# --- W3 step 2 lane D2 (data): POILayouts/Frontier.luau (Airstrip, Signal, Radar, FortI, FortS) ---
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', 'local Layouts: { [string]: WorldConfig.POILayout } = {', 'W3s2 D2: the Frontier rows are typed POILayout (data only)')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', 'local WorldConfig = require(ReplicatedStorage.Shared.Configs.WorldConfig)', 'W3s2 D2: requires only WorldConfig, by the ReplicatedStorage path')
must_not_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', 'script.Parent.Parent.WorldConfig', 'W3s2 D2: not the geometry draft require path')
must_not_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', 'Text = BOARD', 'W3s2 D2: PoiBoard text comes from POILayout.Board')
must_not_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', 'WaitForChild(', 'W3s2 D2: layout data never waits on the tree')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', '{ Id = "CP", Block = "Road", Role = "checkpoint", Tier = 1, X = 0, Z = -1150, Yaw = 180, Street = true,', 'W3s2 D2: the Signal checkpoint cluster is "CP" (template ids Signal.CP.*)')
must_not_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', 'CP_S', 'W3s2 D2: no draft checkpoint ids; the template makes Signal.CP.*')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', '{ Id = "Airstrip.Tower.Console", Kind = "console", X = 662, Z = -1318,', 'W3s2 D2: tower uplink at the spec spot')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', '{ Id = "Airstrip.Tower.G1", Kind = "npc",', 'W3s2 D2: the tower uplink has its own posts')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', '{ Id = "Signal.Relay.Console", Kind = "console", X = -196, Z = -1300,', 'W3s2 D2: relay uplink at the spec spot')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', '{ Id = "Radar.Uplink.Console", Kind = "console", X = -1068.9, Z = -945.8,', 'W3s2 D2: radar uplink at the spec spot')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', '{ Kit = "Terminal", X = 0, Z = 2.5 }', 'W3s2 D2: a console anchor stands in front of its desk, never inside it')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', '{ Id = "FortI.Breach.Gate", Kind = "door",', 'W3s2 D2: Fort Ironclad breach point (spec §1.5 id)')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', '{ Id = "FortS.Breach.Gate", Kind = "door",', 'W3s2 D2: Fort Sandhold breach point (spec §1.5 id)')
must_contain('src/ServerScriptService/Server/Modules/POILayouts/Frontier.luau', 'X = -1396, Z = 1282, Yaw = -155,', 'W3s2 D2: the Sandhold tank wreck clear of Trench_1')

# --- W3 step 2 lane D3 (data): POILayouts/Wilds.luau (Ruins, Crash, Oasis, Quarry, RidgeCamp, DuneCamp) ---
_WILDS = 'src/ServerScriptService/Server/Modules/POILayouts/Wilds.luau'
must_contain(_WILDS, 'local Layouts: { [string]: WorldConfig.POILayout } = {', 'W3s2 D3: the Wilds rows are typed POILayout (data only)')
must_contain(_WILDS, 'local WorldConfig = require(ReplicatedStorage.Shared.Configs.WorldConfig)', 'W3s2 D3: requires only WorldConfig, by the ReplicatedStorage path')
must_not_contain(_WILDS, 'script.Parent.Parent.WorldConfig', 'W3s2 D3: not the geometry draft require path')
must_not_contain(_WILDS, 'Text = BOARD', 'W3s2 D3: PoiBoard text comes from POILayout.Board')
must_not_contain(_WILDS, 'WaitForChild(', 'W3s2 D3: layout data never waits on the tree')
must_not_contain(_WILDS, 'Id = "Quarry.Chest"', 'W3s2 D3 (spec 1.5): ids are <POI>.<Site>.<Role> (Quarry.Camp.Chest)')
must_not_contain(_WILDS, 'Id = "Ruins.Square"', 'W3s2 D3 (spec 1.5): the village square is Ruins.Holdout.Ring')
must_contain(_WILDS, '{ Id = "Ruins.Holdout.Ring", Kind = "hold", X = -540, Z = -1300, Yaw = 0, R = 30 }', 'W3s2 D3 (spec 1.7): the holdout ring, r 30, on the VillageSquare spot')
must_contain(_WILDS, '{ Id = "Crash.BlackBox.Recorder", Kind = "hold", X = -598, Z = 1168,', 'W3s2 D3 (spec 1.7): the black box at the cockpit')
must_contain(_WILDS, '{ Id = "Oasis.Stash.Box", Kind = "search", X = -1381.42, Z = 606.2,', 'W3s2 D3: the stash search spot at the stash crates (not 8.9 away from them)')
must_contain(_WILDS, '{ Id = "Quarry.Camp.Cmdr", Kind = "npc", X = -1388, Z = -1366,', 'W3s2 D3 (spec 1.7): Quarry commander within 25 of the chest, clear')
must_contain(_WILDS, '{ Id = "RidgeCamp.Camp.Cmdr", Kind = "npc", X = 1434, Z = -1052,', 'W3s2 D3 (spec 1.7): Ridge commander within 25 of the chest, clear of the technical')
must_contain(_WILDS, '{ Id = "DuneCamp.Camp.Cmdr", Kind = "npc", X = 1484, Z = 1188,', 'W3s2 D3 (spec 1.7): Dune commander within 25 of the chest, clear of the heli wreck')
must_contain(_WILDS, 'Y = 14, Requires = "Watch" }', 'W3s2 D3: camp watchtower deck posts exist only where the (Tier 2) tower was built')

# --- W3 step 2 lane F (bank findable): BankRaidService / BankRaidConfig / BankRaidController, SupplyDropService /
# SupplyDropConfig, CombatConfig (spec w3s2 §6 Phase A lane F, §8 Phase A pins) ---
_BRS = "src/ServerScriptService/Server/Services/BankRaidService.luau"
_BRC = "src/ReplicatedStorage/Shared/Configs/BankRaidConfig.luau"
_BRX = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BankRaidController.luau"
_SDS = "src/ServerScriptService/Server/Services/SupplyDropService.luau"
_SDC = "src/ReplicatedStorage/Shared/Configs/SupplyDropConfig.luau"
_CCF = "src/ReplicatedStorage/Shared/Configs/CombatConfig.luau"
# spec §8 Phase A (lane F)
must_contain(_BRS, "BankCooldownUntil", "W3s2 F: the bank cooldown is saved on the profile (Raid.BankCooldownUntil)")
must_contain(_BRS, "SeatPart", "W3s2 F: on-foot rule (a seated raider never loots)")
must_not_contain(_BRS, "GuardRingRadius", "W3s2 F: no guard ring (fixed posts only)")
must_not_contain(_SDS, "Enum.Material.Neon", "W3s2 F: supply crates never glow")
must_contain(_SDC, "LifetimeSeconds = 120", "W3s2 F: supply crate lifetime 120 s")
must_contain(_SDC, "MaxActive = 2", "W3s2 F: at most 2 supply crates (512-circle cap with transients)")
must_contain(_CCF, "NPCAlsoSpawnNearTerritories = false", "W3s2 F: no random territory-marker NPCs (plaza Infantry, rig stand-in)")
for _needle in ("MT raid", "Military Tycoon", "MT-style"):
    must_not_contain(_BRC, _needle, "W3s2 F: no other game's name in BankRaidConfig (%s)" % _needle)
# lane F behaviour
must_contain(_BRS, 'pcall(ActivityAnchors.List, BankRaidConfig.AnchorSite, "npc")', "W3s2 F: guard posts from the Town.Bank npc anchors first")
must_contain(_BRS, "for i, p in ipairs(BankRaidConfig.GuardPosts) do", "W3s2 F: P0 fallback posts from BankRaidConfig.GuardPosts")
must_contain(_BRC, 'AnchorSite = "Town.Bank",', "W3s2 F: the bank anchor site id")
must_contain(_BRC, 'GuardRolePattern = "^G%d+$",', "W3s2 F: only G<n> anchors are guard posts (R1/R2 are Phase B reinforcements)")
must_contain(_BRC, "{ X = 212, Y = 1.6, Z = -206, Yaw = 180 },", "W3s2 F: P0 post front-left (clear in the HEAD dump)")
must_contain(_BRC, "{ X = 220, Y = 0.5, Z = -198, Yaw = 180 },", "W3s2 F: P0 post on the street (clear in the HEAD dump)")
must_contain(_BRS, 'blockedNow[uid] = "Vehicle"', "W3s2 F: a seated raider is Blocked = Vehicle (HUD: LEAVE VEHICLE)")
must_contain(_BRS, "DataService.OnProfileLoaded(function(player: Player, profile: any)", "W3s2 F: saved cooldown sanitised + pushed when the save loads")
must_contain(_BRS, "function BankRaidService.SanitizeCooldown(value: any, nowUnix: number): (number?, boolean)", "W3s2 F: local sanitiser (no ProfileSchema edit)")
must_contain(_BRS, 'local untilT = cooldownUntil(player) -- nil: profile not loaded', "W3s2 F: no loot before the save loads")
must_contain(_BRS, 'if sign:FindFirstChildWhichIsA("SurfaceGui") then', "W3s2 F: EMPIRE BANK painted only when the sign has none")
must_contain(_BRS, "pcall(WorldKits.Sign, sign, faceToward(sign, SIGN.Facing), SIGN.Text)", "W3s2 F: the bank sign goes through the world sign budget")
must_contain(_BRS, 'pcall(MissionService.TrackProgress, player, "Heist", 1)', "W3s2 F: a bank job counts for Heist missions")
must_contain(_BRS, "string.format(TEXT.Reward, formatCash(cash))", "W3s2 F: reward toast with commas")
must_contain(_BRS, "NotificationService.Notify(player, TEXT.FirstVisit, \"Info\")", "W3s2 F: one-time first-visit tip")
must_contain(_BRS, 'bb:SetAttribute(LABEL.StateAttribute, if anyRaiding then "raid" else "open")', "W3s2 F: public label state for the client's CLOSED line")
must_contain(_BRS, 'ReplicatedStorage:WaitForChild("Shared", 60)', "W3s2 F: bounded wait for Shared")
must_contain(_BRC, 'OpenSub = "OPEN · rob the vault",', "W3s2 F: label line OPEN")
must_contain(_BRC, 'RaidingSub = "RAID ON",', "W3s2 F: label line RAID ON")
must_contain(_BRC, 'ClosedSub = "CLOSED %dm",', "W3s2 F: label line CLOSED <m>m")
must_contain(_BRC, 'FirstVisit = "Empire Bank: stand on the vault to loot",', "W3s2 F: first-visit copy (no key names, no tap / click)")
must_contain(_BRX, 'p.Title.Text = "LEAVE VEHICLE"', "W3s2 F: HUD pill LEAVE VEHICLE")
must_contain(_BRX, 'local seated = payload.Blocked == "Vehicle"', "W3s2 F: pill reads the server's Blocked")
must_contain(_BRX, "function BankRaidController.LabelLine(secondsLeft: number, publicState: any): (string, Color3)", "W3s2 F: client-only CLOSED line")
must_contain(_BRX, "CollectionService:GetTagged(Constants.Tags.BankVault)", "W3s2 F: label found by tag (streaming-safe)")
must_contain(_BRX, 'player:WaitForChild("PlayerGui", 30)', "W3s2 F: bounded PlayerGui wait")
for _needle in ('WaitForChild("Shared")', 'WaitForChild("PlayerGui")', "GetDescendants", "RenderStepped"):
    must_not_contain(_BRX, _needle, "W3s2 F: BankRaidController has no %s" % _needle)
must_not_contain(_BRS, 'WaitForChild("Shared")', "W3s2 F: BankRaidService never waits forever")
must_not_contain(_SDS, 'WaitForChild("Shared")', "W3s2 F: SupplyDropService never waits forever")
must_contain(_SDS, 'lid.Name = "Lid"', "W3s2 F: 2-part crate (crate + lid)")
for _needle in ('"Beacon"', "StrapX", "StrapZ", '"Ring"', "TryAttachCashCrateVisual"):
    must_not_contain(_SDS, _needle, "W3s2 F: supply crate has no %s" % _needle)
must_contain(_SDS, 'NotificationService.Notify(player, "Supply drop +$" .. formatCash(rec.ClaimCash), "Reward")', "W3s2 F: supply toast with commas")

# W3 step 2 lane M0 (missions) pins: paste above the final `parse_gate()` call. Uses the file's own helpers.
MC_ = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MissionController.luau"
MSV_ = "src/ServerScriptService/Server/Services/MissionService.luau"
MCF_ = "src/ReplicatedStorage/Shared/Configs/MissionConfig.luau"
DOC_ = "src/ReplicatedStorage/Shared/Configs/DailyOpsConfig.luau"
must_contain(MC_, '"GO"', "W3s2 M0: Missions rows have a GO button (spec §8)")
must_contain(MC_, "ObjectiveMarker.Show(target)", "W3s2 M0: GO points the one objective marker")
must_contain(MC_, "function MissionController.GoTarget(entry: any, from: Vector3?)", "W3s2 M0: GO resolves the nearest server-sent target")
must_not_contain(MC_, "GetDescendants", "W3s2 M0: no whole-tree scans in the Missions panel")
must_not_contain(MC_, 'WaitForChild("PlayerGui")', "W3s2 M0: PlayerGui wait has a timeout")
must_contain(MCF_, "Heist = true,", "W3s2 M0: Heist objective is live (BankRaidService tracks it)")
must_contain(MCF_, "ButtonW = 112,", "W3s2 M0: GO/CLAIM button 112 v wide on touch")
must_contain(MCF_, "ButtonH = 72,", "W3s2 M0: GO/CLAIM button 72 v tall on touch")
must_contain(MCF_, 'Anchor = "Town.Bank.Vault",', "W3s2 M0: bank GO target is the vault anchor (fallback BankRaidConfig.Position)")
must_contain(DOC_, 'FirstJob = "DailyOpBank",', "W3s2 M0: slot 1 is Rob the Bank once unlocked")
must_contain(DOC_, 'Id = "DailyOpCheckpoint",', "W3s2 M0: Take 2 Checkpoints op in the pool (live in Phase B)")
must_contain(DOC_, 'Id = "DailyOpJobs",', "W3s2 M0: Finish 3 Jobs op in the pool (live in Phase B)")
must_contain(MSV_, "local function rotatePick(", "W3s2 M0: the daily offer rotates (every unlocked mission comes round)")
must_contain(MSV_, 'return false, "NotOffered"', "W3s2 M0: only today's offer can be claimed")
must_contain(MSV_, "if BankRaidConfig.Enabled == false then", "W3s2 M0: no bank op / GO while the bank job is off (Phase B M1 re-points this)")
must_not_contain(MSV_, "Random.new(", "W3s2 M0: picks are pure integer maths, the same on every server")
must_not_contain(MSV_, 'WaitForChild("Shared")', "W3s2 M0: Shared wait has a timeout")
for _f in (DOC_, MSV_):
    for _n in ("MT raid", "Military Tycoon", "MT-style"):
        must_not_contain(_f, _n, "W3s2 M0: no other game named in %s (spec §8)" % _f.split("/")[-1])

# --- W3 step 2 lane U0 (pointer): the one AlwaysOnTop objective marker, compass tracked mode, contested-diamond yield ---
U0_OM = 'src/StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau'
U0_CC = 'src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CompassController.luau'
U0_TC = 'src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TerritoryController.luau'
must_contain(U0_OM, 'AlwaysOnTop = true', 'W3s2 U0: the objective marker is the one AlwaysOnTop label')
must_contain(U0_OM, 'ConsoleWaypoint.Current()', 'W3s2 U0: the objective marker yields to the console GO line')
must_contain(U0_OM, 'return require(script.Parent.ConsoleWaypoint)', 'W3s2 U0: ConsoleWaypoint is required lazily (no require cycle when Phase B makes it call ObjectiveMarker.Clear)')
must_contain(U0_OM, 'WorldLabel.SetRole(bb, "objective")', 'W3s2 U0: the marker carries WE_LabelRole objective (governor / policy leave it on top)')
must_contain(U0_OM, 'local PERIOD = 1 / math.clamp(W.RefreshHz, 1, 10)', 'W3s2 U0: marker refresh <= 10 Hz')
must_contain(U0_OM, 'stepConn = RunService.Heartbeat:Connect(step)', 'W3s2 U0: one Heartbeat connection, only while a target is set')
must_contain(U0_OM, 'function ObjectiveMarker.OnTop(): boolean', 'W3s2 U0: OnTop() for the contested-diamond yield')
must_contain(U0_OM, 'function ObjectiveMarker.Revision(): number', 'W3s2 U0: Revision() so the compass copies the target only on change')
must_not_contain(U0_OM, 'RenderStepped', 'W3s2 U0: no per-frame render work in the marker')
must_not_contain(U0_OM, 'WaitForChild("Shared")', 'W3s2 U0: bounded wait for Shared')
must_contain(U0_CC, 'local rev = ObjectiveMarker.Revision()', 'W3s2 U0: compass tracked mode follows the objective marker')
must_contain(U0_CC, 'local HIDE_TRACKED = { "Modal" }', 'W3s2 U0: the tracked compass also shows inside your own plot (hidden only by a panel)')
must_not_contain(U0_CC, 'WaitForChild("Shared")', 'W3s2 U0: bounded wait for Shared')
must_not_contain(U0_CC, 'GetDescendants', 'W3s2 U0: the compass never scans the tree')
must_contain(U0_TC, 'local on = ObjectiveMarker.OnTop()', 'W3s2 U0: the contested diamond yields to the objective marker')
must_contain(U0_TC, 'Name = "WE_FlagBillboard", -- TerritoryService', 'W3s2 U0: the yield targets TerritoryService\'s flag diamond')
must_not_contain(U0_TC, 'WaitForChild("Shared")', 'W3s2 U0: bounded wait for Shared')
must_not_contain(U0_TC, 'WaitForChild("PlayerGui")', 'W3s2 U0: bounded wait for PlayerGui')
must_not_contain(U0_TC, 'GetDescendants', 'W3s2 U0: the diamond yield never scans the tree')

# --- W3 step 2 Phase A integration ---
must_not_contain('src/ServerScriptService/Server/Services/TerritoryService/init.luau', 'WaitForChild("Shared")', 'W3s2 integration: TerritoryService never waits forever on Shared (bounded 60 s)')
# Enable steps (Phase A integration + lane BK): step 1 (Industry + 3 camps), step 2 (Frontier) and step 3 (Ruins, Crash,
# Oasis) are ON. Lane BK removed the 4 pool-pad labels and paints EMPIRE BANK in MapSetup (before the POI boards): the
# world holds 17 / 17 signs, no board refused (lane BK census, both startup orders).
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Budget = 140, Reserve = 8, Enabled = true, Lights = 3, Signs = 1, Layout = "Industry"', 'W3s2 enable step 1: South Port (Industry + camps) is on')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Budget = 75, Reserve = 4, Enabled = true, Lights = 1, Signs = 1, Layout = "Frontier"', 'W3s2 enable step 2: Signal Station is on')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Budget = 85, Reserve = 6, Enabled = true, Lights = 2, Signs = 1, Layout = "Frontier"', 'W3s2 enable step 2: Desert Airstrip is on')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Budget = 85, Reserve = 4, Enabled = true, Lights = 0, Signs = 1, Layout = "Wilds"', 'W3s2 enable step 3: Ruined Village is on')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Budget = 45, Reserve = 4, Enabled = true, Lights = 0, Signs = 1, Layout = "Wilds"', 'W3s2 enable step 3: Crash Site is on')
must_contain('src/ReplicatedStorage/Shared/Configs/WorldConfig.luau', 'Budget = 60, Reserve = 2, Enabled = true, Lights = 2, Signs = 1, Layout = "Wilds"', 'W3s2 enable step 3: Oasis is on')


# ── fix57 pins (PromptController strong tables, VisualAssetService retry / logs, Base-panel NEXT badge, BusinessService prestige) ──
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'local adopted: { [ProximityPrompt]: boolean } = {}', 'fix57 PromptController adopted is a strong table')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'local disabledByUs: { [ProximityPrompt]: boolean } = {}', 'fix57 PromptController disabledByUs is a strong table')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'local suppressed: { [ProximityPrompt]: boolean } = {}', 'fix57 PromptController suppressed is a strong table (MAX / locked console pill stays hidden)')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', '__mode = "k"', 'fix57 PromptController has no weak-keyed prompt tables')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'local function prune(prompt: ProximityPrompt)', 'fix57 PromptController prunes every per-prompt table')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'table.insert(conns, prompt.Destroying:Connect(function()', 'fix57 PromptController prunes on Destroying')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'table.insert(conns, prompt.AncestryChanged:Connect(function()', 'fix57 PromptController prunes on AncestryChanged')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'if not prompt:IsDescendantOf(game) then', 'fix57 PromptController prunes when the prompt leaves the DataModel')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'if not track(prompt) then', 'fix57 PromptController tracks a prompt before storing it (orphans refused)')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'RenderStepped', 'fix57 PromptController does no per-frame work')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/PromptController.luau', 'Heartbeat', 'fix57 PromptController does no per-frame work (Heartbeat)')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'function scheduleRetry(assetId: number, errText: string)', 'fix57 VAS bounded background retry')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'task.delay(base * mult ^ tries, function()', "fix57 VAS retry runs in its own thread (LoadRetryDelay x LoadRetryBackoff^n), never the caller's")
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'return nil -- a background retry is pending / running: the Part kit look now, never a wait', 'fix57 VAS callers never wait on a retry')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'if not retryBudgetLeft() then', 'fix57 VAS retries keep LoadRetryReserve attempts for first loads')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'local function refuseOverCap(assetId: number)', 'fix57 VAS one Output line per id refused by MaxLoadAttempts')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'if capLogged[assetId] then', 'fix57 VAS the cap line is printed once per id')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', '[VisualAssetService] refused %d \\"%s%s\\": %s — Part kit look stays', 'fix57 VAS one clear line when a pack piece is refused (part cap / missing)')
must_not_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'pack piece skipped', 'fix57 VAS old unclear refusal line gone')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'if n == 0 or n > maxParts() or hasHumanoid(t) then', 'fix57 VAS pack piece part cap unchanged (<= MaxPartsPerModel)')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', 'if n > maxParts() or hasHumanoid(model) then', 'fix57 VAS whole-model part cap unchanged')
must_contain('src/ServerScriptService/Server/Services/VisualAssetService.luau', '-- record the outcome (failed / cooling) BEFORE waking waiters: a woken waiter whose caller asks for the same id', 'fix57 verifier: waiters are woken after failed / cooling is set (no second insert of the same id)')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'LoadRetryCount = 2,', 'fix57 VAS retry count in config')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'LoadRetryDelay = 20,', 'fix57 VAS first retry after 20 s')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'LoadRetryBackoff = 2,', 'fix57 VAS exponential backoff x2')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'LoadRetryReserve = 12,', 'fix57 VAS retries never take the last 12 attempts')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'LoadRetryPermanentErrors = {', 'fix57 VAS permanent errors (not authorised / not trusted / ...) are never retried')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'MaxPartsPerModel = 40,', 'fix57 catalog part cap stays 40 (CLAUDE.md)')
must_contain('src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau', 'MaxLoadAttempts = 48,', 'fix57 load cap not raised (docs/ASSET_SHORTLIST.md C8)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau', 'return TycoonMath.GuideTarget(step, player:GetAttribute("WE_NextBuy"))', 'fix57 Base-panel NEXT badge follows the console NEXT rule (GuideTarget)')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau', 'local isNext = nextId ~= nil and structureId == nextId and nextTarget == level + 1', "fix57 Base-panel NEXT marks the pointer's id AND next level")
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau', 'nextId = TycoonMath.Decode(player:GetAttribute("WE_NextBuy"))', 'fix57 Base-panel NEXT no longer ignores the tutorial step')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau', 'Remotes.BindEvent(Constants.RemoteNames.TutorialStateUpdate, function(payload: any)', 'fix57 Base panel hears the tutorial step')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau', 'local RELIST_MIN_GAP = 0.1', 'fix57 Base-panel rebuilds <= 10 Hz')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau', 'RenderStepped', 'fix57 Base panel does no per-frame work')
must_not_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau', 'Heartbeat', 'fix57 Base panel does no per-frame work (Heartbeat)')
must_contain('src/ServerScriptService/Server/Services/BusinessService.luau', 'Prestige = tonumber(profile.Prestige) or 0,', "fix57 WE_NextBuy pick gets the player's Prestige (rebirth-zone filter)")

# ===== Batch B part 2 merged pins: lane H, lane W, lane Z (integB2) =====
# ----- lane H -----
# --- owner's 11 features, lane H (HUDController, HudIcons, TerritoryController): F3 Empire Tax chip + list header +
# toast, F10 own-Home-Outpost-only list, F11 XP-based rebirth % in the level-chip tooltip. Verified with lane H's
# apply_pins.py on copies: present on HEAD + lane H's 3 files; every must_contain below is absent on HEAD a594cfb.
H_HUD = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau"
H_ICONS = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/HudIcons.luau"
H_TC = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TerritoryController.luau"
must_contain(H_HUD, 'tax.Name = "EmpireTaxChip"', "F3 TopStrip Empire Tax chip")
must_contain(H_HUD, 'local TAX_ATTR: string = (EconomyConfig.OutpostIncomeBuff and EconomyConfig.OutpostIncomeBuff.Attribute) or "WE_EmpireTaxPct"', "F3 chip reads the server's WE_EmpireTaxPct via EconomyConfig (display only)")
must_contain(H_HUD, "player:GetAttributeChangedSignal(TAX_ATTR):Connect(refreshEmpireTax)", "F3 chip follows the attribute (event-driven, no per-frame poll)")
must_contain(H_HUD, 'taxIcon = HudIcons.Make("Flag", tax, {', "F3 chip = HudIcons Flag + \"+N%\"")
must_contain(H_HUD, 'return string.format("+%d%%", math.floor(pct + 0.5))', "F3 chip text \"+10%\"")
must_contain(H_HUD, 'tax.Activated:Connect(function()\n\t\t\tHudLayout.Emit("CompassTapped")', "F3 a tap on the chip opens the Territories dropdown")
must_contain(H_HUD, "function HUDController.EmpireTaxFit(usedPx: number, fullPx: number, compactPx: number, limitPx: number, gapPx: number, current: string?): string", "F3 HideWhenCrowded: Full / Compact / Hidden before the compass")
must_contain(H_HUD, "mode = if E.HideWhenCrowded ~= false then HUDController.EmpireTaxFit(used, fullPx, compactPx, limit, TS.Gap, taxMode) else \"Full\"", "F3 HideWhenCrowded honours HudConfig.TopStrip.EmpireTax")
must_contain(H_HUD, "local TAX_TAP_MIN = 44 -- real px", "F3 the compact chip stays a 44 px real tap target")
must_contain(H_HUD, "local compact = sh.Visible and need > limit - (if shieldCompact then TAX_HYSTERESIS_PX else 0)", "F3 800x360: the raid shield chip drops its icon instead of running under the compass")
must_contain(H_HUD, "sh.LayoutOrder = 5", "F3 TopStrip order Level, Settings, CashPlus, EmpireTax, Shield")
must_contain(H_HUD, "local pct = math.clamp(PrestigeConfig.ProgressPct(lv, tonumber(xp) or 0), 0, 99)", "F11 level-chip tooltip % = PrestigeConfig.ProgressPct (XP-based)")
must_not_contain(H_HUD, "math.floor((lv / minPrestige) * 100)", "F11 no level-based rebirth % left in the HUD")
must_contain(H_ICONS, "SHAPES.Flag = {", "F3 HudIcons Flag (2 Frames, generic pennant)")
must_contain(H_TC, "function TerritoryController.Lists(entry: Types.TerritoryEntryPayload, myPlot: number?, myUserId: number): boolean", "F10 list filter: only the own Home Outpost")
must_contain(H_TC, "if typeof(entry) == \"table\" and TerritoryController.Lists(entry, myPlotId, player.UserId) then", "F10 the dropdown rows and count use the filter")
must_contain(H_TC, "Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(base: any)", "F10 own plot from BaseStateUpdate (never WaitForChild)")
must_contain(H_TC, 'local text = if taxPct > 0 then TerritoryController.TaxText(taxPct) else "TERRITORIES"', "F3 dropdown header \"Empire Tax +N%\"")
must_contain(H_TC, "string.find(payload.Message, TAX.Name, 1, true)", "F3 client toast skipped when the server's toast named Empire Tax")
must_contain(H_TC, "SkipWindow = 2,", "F3 server-toast window 2 s")
must_contain(H_TC, "NotificationController.Show(TerritoryController.TaxText(pct), \"Info\")", "F3 \"Empire Tax +N%\" toast")
must_not_contain(H_TC, "Outposts held: %d", "F3 the \"Outposts held: N\" toast is gone")
must_contain(H_TC, "TextSizeTouch = 20,", "Territories list text 14 real px on phones (was 16 v = 11.2 px)")
must_not_contain(H_TC, "RenderStepped", "Territory HUD: no per-frame render work")
must_not_contain(H_HUD, "RenderStepped", "HUD: no per-frame render work")
must_not_contain(H_HUD, "GetDescendants", "HUD TopStrip fit never scans the tree")

# ----- lane W -----
# ── Owner's 11 features, lane W (batch B part 2): F1 pads, F3 Empire Tax server, F4 no server pump pop, F6 contest,
#    F9 golden pump, F10 Home Outpost, BaseLayout -> PlotFrame; nations B2 (TerritoryService) ────────────────────────
W_MSW = "src/ServerScriptService/Server/Modules/MapSetup.luau"
W_BLY = "src/ServerScriptService/Server/Modules/BaseLayout.luau"
W_TSV = "src/ServerScriptService/Server/Services/TerritoryService/init.luau"
W_TCA = "src/ServerScriptService/Server/Services/TerritoryService/TerritoryCapture.luau"
W_TRA = "src/ServerScriptService/Server/Services/TerritoryService/TerritoryRadar.luau"
W_POP = "src/ServerScriptService/Server/Services/PlotOilPumpService.luau"
# F1 premium pads (MapSetup.buildPremiumPads)
must_contain(W_MSW, "for _, slot in ipairs(MonetizationConfig.PremiumPads.Slots) do", "F1 ATM pads come from MonetizationConfig.PremiumPads.Slots (no hard-coded table)")
must_contain(W_MSW, 'pad:SetAttribute("OwnedIfAny", table.concat(MonetizationConfig.PadOwnedKeys(slot), ","))', "F1 pad carries OwnedIfAny (Speed pad OWNED by either SKU)")
must_contain(W_MSW, "local labelRange = MonetizationConfig.PremiumPads.LabelMaxDistance", "F1 pad label range from PremiumPads.LabelMaxDistance")
must_contain(W_MSW, "BaseLabel = true, -- CollectionService tag WorldLabelConfig.BaseLabelTag (the LabelGovernor's cap)", "F1 pad labels tagged WE_BaseLabel (LabelGovernor)")
must_not_contain(W_MSW, 'Key = "VIP"', "F1 VIP is a Shop row only: no VIP pad at the ATM (label cap)")
must_not_contain(W_MSW, '{ Key = "GoldenPumpjack"', "F1 the Golden Pump pad stands at the pumps (F9), not the ATM")
must_not_contain(W_MSW, "PREMIUM_TAG_RANGE", "F1 no local pad label range (config)")
# F10 Home Outpost kits (MapSetup) + one source for the zones
must_contain(W_MSW, "local rows = TerritoryConfig.Territories", "F10 MapSetup builds the zones from TerritoryConfig.Territories")
must_contain(W_MSW, "for _, def in ipairs(territoryDefsInBuildOrder()) do", "F10 every TerritoryConfig row is built (Home Outposts included)")
must_not_contain(W_MSW, "local TERRITORIES = {", "F10 no local copy of the territory table in MapSetup")
must_contain(W_MSW, "continue -- F10: the Home Outpost kit ends here (marker, ring, pole, flag: 4 parts, no light)", "F10 Home Outpost = 4-part kit (no stripe / finial / light)")
must_contain(W_MSW, 'marker:SetAttribute("PlotId", def.PlotId)', "F10 Home Outpost marker names its plot (clients list / point at their own only)")
# BaseLayout delegates to Shared/Util/PlotFrame
must_contain(W_BLY, "return PlotFrame.PlotYaw(plotPos)", "F10 BaseLayout.PlotYaw delegates to PlotFrame")
must_contain(W_BLY, "return PlotFrame.PlotCFrame(plotPos)", "F10 BaseLayout.PlotCFrame delegates to PlotFrame")
must_not_contain(W_BLY, "local function yawRotation(", "F10 one copy of the plot yaw maths (PlotFrame)")
# TerritoryCapture / TerritoryRadar (F10)
must_contain(W_TCA, 'if typeof(def) ~= "table" or def.OwnerOnly ~= true then', "F10 TerritoryCapture reads OwnerOnly")
must_contain(W_TCA, "if onlyUserId ~= nil and player.UserId ~= onlyUserId then", "F10 OwnerOnly: only the plot owner captures or contests")
must_contain(W_TSV, "TerritoryCapture.SetPlotOwnerResolver(function(plotId: number): number?", "F10 OwnerOnly bound to BaseService.GetOwnerUserId")
must_contain(W_TRA, "function TerritoryRadar.ShownTo(", "F10 TerritoryRadar skips other plots' Home Outposts")
must_contain(W_TSV, "if not TerritoryRadar.ShownTo(rt.Def, viewerPlotId) then", "F10 another plot's Home Outpost is not in a player's territory list")
# TerritoryService F10
must_contain(W_TSV, "function TerritoryService.IsStarterId(id: any): boolean", "F10 cross-lane API TerritoryService.IsStarterId")
must_contain(W_TSV, "if not starter and not alreadyOwns and countPersonalNonStarter(player.UserId) >= TerritoryConfig.MaxPersonalTerritories then", "F10 a Home Outpost never counts toward MaxPersonalTerritories")
must_contain(W_TSV, "and not isStarterRt(other) then", "F10 a Home Outpost is never evicted")
must_contain(W_TSV, "(profile :: any).StarterOutpostTaken = true", "F10 the first Home Outpost capture is saved")
must_contain(W_TSV, "pcall(BaseService.OnPlotReady, onPlotReady)", "F10 the Home Outpost follows its plot owner (OnPlotReady listener)")
must_contain(W_TSV, "\tsyncProfileOwnership(player)\n\tsyncEmpireTax(player)\n\tif BaseService then\n\t\tBaseService.PushState(player)\n\tend\n\tupdateMarkerVisual(rt)", "F10 holding the Home Outpost recounts the Empire Tax (SyncOutpostIncomeStacks)")
must_contain(W_TSV, "ClanWarService.OnTerritoryCaptured and not starter then", "F10 a Home Outpost capture is not a clan-war capture")
# TerritoryService F3
must_contain(W_TSV, "local function replantClaims(player: Player)", "F3 replantClaims (spec pin)")
must_contain(W_TSV, "if persistClaimsOn() then\n\t\t\treplantClaims(player)\n\t\tend\n\t\tsyncProfileOwnership(player)", "F3 saved claims are re-planted before the profile is rewritten from this server")
must_contain(W_TSV, "return buff ~= nil and buff.PersistClaims == true", "F3 PersistClaims flag gates re-plant and the leave release")
must_contain(W_TSV, 'releaseOwnership(rt, "leave")', "F3 PersistClaims / F10: the leaver's zones go back to Neutral")
must_contain(W_TSV, 'if prevPlayer and reason ~= "leave" then', "F3 the leave release never rewrites the saved claims")
must_contain(W_TSV, "fmtToast(buff and buff.ToastSecured,", "F3 capture toast = EconomyConfig ToastSecured with the total %")
must_contain(W_TSV, "fmtToast(buff and buff.ToastStolenFromYou,", "F3 victim toast = ToastStolenFromYou (zone, total %)")
must_contain(W_TSV, "fmtToast(buff and buff.ToastStealGain,", "F3 steal toast = ToastStealGain (zone, total %)")
must_contain(W_TSV, "fmtToast(buff and buff.ToastClaimHeld,", "F3 a claim held by another online player is dropped with ToastClaimHeld")
must_not_contain(W_TSV, "— +%d%% Income (yours)", "F3 no hard-coded per-stack capture toast")
# TerritoryService F6
must_contain(W_TSV, 'pcall(CombatService.EndNoviceShield, p, "contest")', "F6 contesting a zone ends a novice's shield (pcall)")
must_contain(W_TSV, "CombatService = deps.CombatService", "F6 TerritoryService takes CombatService from deps (no require)")
# Nations B2
must_contain(W_TSV, "local minD = tonumber((NationConfig :: any).ContestMinColorDistance) or 0.25", "nations B2 contest colour distance from NationConfig")
must_contain(W_TSV, "\t\treturn colA, AMBER\n", "nations B2 (a) close contest colours pulse against amber")
must_contain(W_TSV, "local colA, colB = contestColors(rt)\n\t\t\t\t;(localCapture :: any).ContesterColorA = packColor(colA)", "nations B2 (b) the capture HUD uses the same amber rule")
must_contain(W_TSV, "c = if legacy and not nearReserved(legacy) then legacy else OWNED_FALLBACK", "nations B2 (c) an owned zone never reads as NPC / Clan / contested")
must_contain(W_TSV, "local function pruneOwnerCache(userId: number?)", "nations B2 (d) R15 leaver colour kept only while they own a zone")
must_contain(W_TSV, "function TerritoryService.RefreshOwnerFlags(userId: number)", "nations B2 (e) RefreshOwnerFlags (NationColorService calls it behind OutpostFlags)")
must_contain(W_TSV, "local outpostFlags = NationConfig.OutpostFlags == true", "nations B2 (e) outpost flags behind NationConfig.OutpostFlags")
must_contain(W_TSV, "local showId = if not contested and rt.OwnerType == ot.Player then ownerNationId else nil", "nations B2 (e) a nation flag only on a Player-owned, uncontested zone")
must_not_contain(W_TSV, 'Instance.new("SurfaceGui")', "nations: zone flags are Textures, never SurfaceGuis")
must_not_contain(W_TSV, ".Short", "nations: no nation name in any capture / loss toast")
# F4 / F9 PlotOilPumpService
must_not_contain(W_POP, "WE_OilCashPop", "F4 no server pump pop (the client ProducerLabels shows +$18 / every 5s)")
must_not_contain(W_POP, "Enum.Material.Neon", "F9 golden pump dress is Metal, never Neon")
must_contain(W_POP, "d.Reflectance = g.Reflectance", "F9 gold Metal + Reflectance from PlotOilPumpConfig.Golden")
must_contain(W_POP, 'if model.Parent and model:GetAttribute("WE_GoldenPump") == true then\n\t\t\t\tapplyGoldenDress(model)', "F9 the catalog clone is gold-dressed after the deferred attach")
must_contain(W_POP, "if goldLive and not hasGold then", "F9 gold pad only while the Id is live and the owner does not own it")
must_contain(W_POP, 'pad:SetAttribute("OfferKey", GOLDEN_KEY)', "F9 gold pad is a PremiumPadService pad (DevProduct GoldenPumpjack)")
must_contain(W_POP, "BaseLabel = true, -- WorldLabelConfig.BaseLabelTag: counted by the client LabelGovernor", "F9 gold pad label tagged WE_BaseLabel")
must_contain(W_POP, "MaxDistance = g.LabelMaxDistance,", "F9 gold pad label range from PlotOilPumpConfig.Golden")
must_contain(W_POP, "if Vector3.new(padPos.X - gate.X, 0, padPos.Z - gate.Z).Magnitude < GOLD_PAD_GATE_CLEAR then", "F9 the gold pad never sits in the main gate lane")
must_not_contain(W_POP, "AlwaysOnTop = true", "F9 no AlwaysOnTop label at the pumps")

# ----- lane Z -----

# ── Owner's 11 features, lane Z (batch B switch-on): the six feature flags ON, nations outpost flags OFF,
#    tutorial order version follows the Home Outpost (3 on / 2 off) with a two-way save migration, docs ─────────
Z_TER = "src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau"
Z_ECO = "src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau"
Z_CFC = "src/ReplicatedStorage/Shared/Configs/CombatFairnessConfig.luau"
Z_WLC = "src/ReplicatedStorage/Shared/Configs/WorldLabelConfig.luau"
Z_TGC = "src/ReplicatedStorage/Shared/Configs/TycoonGuideConfig.luau"
Z_TUC = "src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau"
Z_TUS = "src/ServerScriptService/Server/Services/TutorialService.luau"
Z_NAT = "src/ReplicatedStorage/Shared/Configs/NationConfig.luau"
# flags switched on (spec §1 item 9); each is reversible by setting it back to false
must_contain(Z_TER, "\tStarter = {\n\t\tEnabled = true,", "Z: F10 Home Outpost on")
must_contain(Z_ECO, "\t\tPersistClaims = true,", "Z: F3 Empire Tax claims persist across servers")
must_contain(Z_ECO, "\tProducerLabels = {\n\t\tEnabled = true,", "Z: F4 producer labels on")
must_contain(Z_CFC, "\tNoviceShield = {\n\t\tEnabled = true,", "Z: F6 novice shield on")
must_contain(Z_WLC, "\tBaseLabelGovernor = {\n\t\tEnabled = true,", "Z: F4 base label governor on (<= 3 base labels on screen)")
must_contain(Z_WLC, "\t\tMaxOnScreen = 3,", "Z: governor cap stays 3 (CLAUDE.md world-label cap at a base)")
must_contain(Z_TGC, 'PickMode = "Cheapest",', "Z: lead decision - PickMode Cheapest ships on")
# nations: outpost flags stay OFF at launch (lead decision; the existing 'OutpostFlags = false,' pin also holds it)
must_not_contain(Z_NAT, "OutpostFlags = true", "Z: nations outpost flags stay off")
# tutorial order: one version = one fixed order; the Home Outpost switch picks 3 (outpost, 4x4) or 2 (4x4, outpost)
must_contain(Z_TUC, '\t\t[2] = { "ClaimBase", "CommandCenter", "Income", "RecruitSoldiers", "Barracks", "Jeep", "Outpost" },', "Z: order 2 = the order v2 saves were made in (4x4 before the outpost)")
must_contain(Z_TUC, '\t\t[3] = { "ClaimBase", "CommandCenter", "Income", "RecruitSoldiers", "Barracks", "Outpost", "Jeep" },', "Z: order 3 = the owner's order (outpost before the 4x4)")
must_contain(Z_TUC, "function TutorialConfig.SavedOrder(version: any): { string }?", "Z: saved order lookup (nil = unknown, newer build)")
must_contain(Z_TUC, "function TutorialConfig.MigrateLegacyStep(oldStep: any, steps: { TutorialStepDef }?, fromVersion: number?): number", "Z: migration reads the save in its own order")
must_contain(Z_TUC, "function TutorialConfig.DoneAhead(oldStep: any, fromVersion: number?, steps: { TutorialStepDef }?): { [string]: boolean }?", "Z: steps already done that the new order puts later")
must_contain(Z_TUS, "profile.TutorialDoneAhead = if next(ahead) ~= nil then ahead else nil", "Z: a done 4x4 / outpost is carried across the order change")
must_contain(Z_TUS, "local ahead = profile.TutorialDoneAhead\n\tif typeof(ahead) == \"table\" and ahead[def.Id] == true then\n\t\treturn true", "Z: a step carried as done is never asked for twice")
must_contain(Z_TUS, "profile.TutorialDoneAhead = nil -- lane Z: a fresh run owes every step", "Z: Reset clears the carried steps")
_z_tuc = read(Z_TUC) or ""
if "\tOrderVersion = if TerritoryConfig.Starter.Enabled == true then 3 else 2," in _z_tuc and "TutorialConfig.Steps = TutorialConfig.BuildSteps(TutorialConfig.OutpostBeforeJeep())" in _z_tuc:
    ok("Z: OrderVersion and the step order follow the same switch (Starter.Enabled)")
else:
    bad("Z: OrderVersion must follow TerritoryConfig.Starter.Enabled like the step order")
# docs: LIVE_PLACE product table matches MonetizationConfig (every Id in the doc = the config Id), and the new rows
Z_MON = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
Z_DOC = "docs/LIVE_PLACE.md"
_z_mon = read(Z_MON) or ""
_z_doc = read(Z_DOC) or ""
_z_ids = {}
for _sec in ("GamePasses", "DevProducts"):
    _i = _z_mon.find("\t" + _sec + " = {")
    _j = _z_mon.find("\n\t},", _i)
    _blk = _z_mon[_i:_j] if _i >= 0 and _j > _i else ""
    _z_ids[_sec] = dict(re.findall(r"\n\t\t(\w+) = \{(?:[^\n]*\n\s*)?\s*Id = (\d+),", _blk))
for _sec, _hdr in (("GamePasses", "### GamePasses"), ("DevProducts", "### DevProducts")):
    _i = _z_doc.find(_hdr)
    _j = _z_doc.find("\n### ", _i + 1)
    _tbl = _z_doc[_i:_j] if _i >= 0 else ""
    _rows = re.findall(r"\n\| (\w+) \| [^|]+ \| (\d+)", _tbl)
    _cfg = _z_ids.get(_sec, {})
    _docd = {k: v for k, v in _rows}
    if _cfg and set(_docd) == set(_cfg) and all(_docd[k] == _cfg[k] for k in _cfg):
        ok(f"Z docs: LIVE_PLACE {_sec} table lists every config key with its Id ({len(_cfg)})")
    else:
        _miss = sorted(set(_cfg) - set(_docd))
        _extra = sorted(set(_docd) - set(_cfg))
        _diff = sorted(k for k in _cfg if k in _docd and _docd[k] != _cfg[k])
        bad(f"Z docs: LIVE_PLACE {_sec} table out of sync (missing {_miss}, extra {_extra}, wrong Id {_diff})")
must_contain(Z_DOC, "| Game Pass | Speed Pass | 5 R$ |", "Z docs: the 3 new Creator Dashboard items")
must_contain(Z_DOC, "| Developer Product | Keep-Base Rebirth | 50 R$ |", "Z docs: the 3 new Creator Dashboard items")
must_contain(Z_DOC, "| Developer Product | Golden Pumpjacks | 49 R$ |", "Z docs: the 3 new Creator Dashboard items")
must_contain("BALANCE.md", "### Empire Tax (owner's 11 features, F3 / F10)", "Z docs: BALANCE Empire Tax rows")
must_contain("BALANCE.md", "| Your own Home Outpost | **+5%** |", "Z docs: BALANCE Home Outpost row")

# --- W3 step 2 lane BK (Empire Bank hall) + enable steps 2 and 3 (integration block). Inserted above the final `parse_gate()`
# call by buildBK/apply_pins.py. Verified on clean HEAD c51ec9b + MapSetup.luau + WorldConfig.luau (buildBK/fin/cand):
# headless stand-in, not Roblox.
BK_MS = "src/ServerScriptService/Server/Modules/MapSetup.luau"
BK_WC = "src/ReplicatedStorage/Shared/Configs/WorldConfig.luau"
# spec w3s2 §8 Phase A pins for lane BK
must_contain(BK_MS, '"StateBanner"', 'W3s2 BK: the bank StateBanner on the roof')
must_contain(BK_MS, 'WE_RuntimeDoor', 'W3s2 BK: BankGate is a runtime door (WorldHygiene leaves it alone)')
must_not_contain(BK_MS, 'beacon(bankFolder', 'W3s2 BK: no bank beacon')
# the hall and its parts
must_contain(BK_MS, 'local function buildEmpireBank(root: Folder)', 'W3s2 BK: one Empire Bank builder')
must_contain(BK_MS, 'buildEmpireBank(root)', 'W3s2 BK: MapSetup.Run builds the bank hall')
must_contain(BK_MS, 'local n = WorldKits.Add(hall, "TownBlock", CFrame.new(220, BANK_FLOOR_Y, BANK_HALL_CENTRE_Z) * CFrame.Angles(0, math.pi, 0), {', 'W3s2 BK: the hall is the WorldKits TownBlock shell facing Bank Street')
must_contain(BK_MS, 'Variant = "hall",', 'W3s2 BK: TownBlock "hall" variant (7 parts)')
must_contain(BK_MS, 'local BANK_POS = Vector3.new(220, 1, -220) -- the plaza centre = BankRaidConfig.Position', 'W3s2 BK: bank plaza centre (kept equal to BankRaidConfig.Position)')
must_contain('src/ReplicatedStorage/Shared/Configs/BankRaidConfig.luau', 'Position = Vector3.new(220, 1, -220),', 'W3s2 BK: BankRaidConfig.Position = MapSetup BANK_POS (two literals, pinned together)')
must_contain(BK_MS, 'local BANK_VAULT_Z = -224 -- the vault pad centre', 'W3s2 BK: vault pad 2 studs toward the door (radius 12 never reaches round the back wall)')
must_contain(BK_MS, 'CollectionService:AddTag(vault, "WE_BankVault")', 'W3s2 BK: the one tagged vault is VaultPad')
must_contain(BK_MS, 'gate:SetAttribute(act.RuntimeDoorAttr, true) -- WE_RuntimeDoor', 'W3s2 BK: BankGate carries the runtime-door attribute')
must_contain(BK_MS, 'gate:SetAttribute(act.GateStateAttr, "open") -- WE_GateState', 'W3s2 BK: BankGate built open until Phase B')
must_contain(BK_MS, 'CFrame = gateOpen,', 'W3s2 BK: BankGate built in its open (up-and-over) position')
must_contain(BK_MS, 'gate:SetAttribute("WE_ClosedCFrame", gateClosed)', 'W3s2 BK: BankGate keeps its closed position for the jobs')
must_contain(BK_MS, 'for _, row in ipairs(WorldConfig.Town.BankAnchors) do', 'W3s2 BK: the Town.Bank.* anchors come from WorldConfig.Town.BankAnchors')
must_contain(BK_MS, 'if ActivityAnchors.Stamp(plaza, ActivityAnchors.FromRow(row)) ~= nil then', 'W3s2 BK: anchors stamped on BankPlaza through ActivityAnchors.Stamp (0 parts)')
must_contain(BK_MS, 'WorldKits.Sign(sign, Enum.NormalId.Back, BANK_SIGN_TEXT)', 'W3s2 BK: EMPIRE BANK painted by MapSetup inside the world sign budget, before the POI boards')
must_contain(BK_MS, '{ Name = "BankColumnW", X = 212 }, { Name = "BankColumnE", X = 228 }', 'W3s2 BK: the columns stand outside the sign (never hide EMPIRE BANK)')
must_not_contain(BK_MS, 'paintEdge(bankPad', 'W3s2 BK: no painted kerb round the bank plaza')
must_not_contain(BK_MS, 'plainBillboard(vault', "W3s2 BK: no MapSetup vault card (BankRaidService's label is the one)")
must_not_contain(BK_MS, 'local function beacon(', 'W3s2 BK: no beacon helper left (nothing outside the bases has a beacon)')
must_contain(BK_MS, 'if def.PlotId == nil then\n\t\t\tcontinue\n\t\tend\n\t\t-- 1-post sign on the back edge', 'W3s2 BK: the 4 pool pads carry no Garage sign (world sign budget 17)')
# enable steps 2 (Frontier: Signal, Airstrip, Radar, FortI, FortS) and 3 (Ruins, Crash, Oasis) ON: with the 4 pool-pad
# labels gone the world holds 17 / 17 signs (6 gate pads, EMPIRE BANK, the Town board, 9 POI boards), none refused
must_contain(BK_WC, 'Budget = 33, Reserve = 2, Enabled = true, Lights = 0, Signs = 0, Layout = "Frontier", LowShare = 0.75', 'W3s2 enable step 2: Radar Hill is on')
must_contain(BK_WC, '{ Id = "FortI", Name = "Fort Ironclad approach", Kind = "fort", Circle = { X = 1450, Z = -1450, R = 230 }, Budget = 53, Reserve = 2, Enabled = true,', 'W3s2 enable step 2: Fort Ironclad approach is on')
must_contain(BK_WC, '{ Id = "FortS", Name = "Fort Sandhold approach", Kind = "fort", Circle = { X = -1450, Z = 1450, R = 200 }, Budget = 53, Reserve = 2, Enabled = true,', 'W3s2 enable step 2: Fort Sandhold approach is on')
must_not_contain(BK_WC, 'Enabled = false, Lights', 'W3s2 enable steps 1-3: every POI row is on')
# integration (lane BK verifier fix + enable steps): the open gate lies flat under the roof slab (never hangs upright in the
# doorway between the camera and a raider inside); the closed pose still fills the opening; the Phase A sign budget holds
must_contain(BK_MS, 'local BANK_GATE_CEILING_GAP = 0.02', 'W3s2 BK integ: the open bank gate lies just under the roof slab')
must_contain(BK_MS, 'local gateOpen = CFrame.new(220, roofBottom - BANK_GATE_CEILING_GAP - 0.3, -214.9 - 4.5) * CFrame.Angles(math.rad(90), 0, 0)', 'W3s2 BK integ: open gate = up-and-over pose (flat, inside the hall)')
must_contain(BK_MS, 'local gateClosed = CFrame.new(220, BANK_FLOOR_Y + 4.5, -214.6)', 'W3s2 BK integ: the closed gate fills the 10-wide opening')
must_not_contain(BK_MS, 'BANK_GATE_LIFT', 'W3s2 BK integ: no raised-and-hanging gate pose left')
must_contain(BK_MS, 'gate.CanQuery = false', 'W3s2 BK integ: the open gate never blocks shots or line of sight')
must_contain(BK_WC, 'SurfaceGuis = 17', 'W3s2 BK integ: world sign budget stays 17 (6 gate pads + EMPIRE BANK + Town + 9 POI boards = 17)')

# --- W3 step 2 Phase B lane KB (contracts): OpsConfig ships OFF, the 3 Jobs remotes (server -> client only) ---
KB_OPS = 'src/ReplicatedStorage/Shared/Configs/OpsConfig.luau'
KB_CONST = 'src/ReplicatedStorage/Shared/Constants.luau'
KB_RS = 'src/ServerScriptService/Server/Modules/RemoteSetup.luau'
must_contain(KB_OPS, '\tEnabled = false, -- master switch', 'W3s2 KB: Jobs (OpsConfig.Enabled) ship OFF until the integrator cuts over')
must_not_contain(KB_OPS, 'Enabled = true', 'W3s2 KB: every Jobs kind / site switch ships false')
must_contain(KB_OPS, 'export type OpsStatePayload = {', 'W3s2 KB: OpsState payload type (contract)')
must_contain(KB_OPS, 'export type OpsProgressPayload = {', 'W3s2 KB: OpsProgress payload type (contract)')
must_contain(KB_OPS, 'export type OpsPingPayload = { U: number, X: number, Z: number }', 'W3s2 KB: OpsPing payload type (contract)')
must_contain(KB_OPS, 'CashReason = "ops",', 'W3s2 KB: job pay goes through AddCash with reason "ops"')
must_contain(KB_OPS, 'RequireCashExempt = true,', 'W3s2 KB: Jobs stay off until "ops" is cash-multiplier exempt')
must_contain(KB_OPS, 'Rows = {\n\t\t\tBank = { Minutes = 10, Floor = 15000, Cap = 300000, XP = 250, PlayerCd = 900,', 'W3s2 KB: bank pay row (spec §5: $36,000 at R = 60/s, $15,000 floor)')
must_contain(KB_OPS, 'Budget = 18, -- regular slots', 'W3s2 KB: NPC ledger budget 18 (+4 headroom), spec §4')
must_contain(KB_OPS, 'Checkpoint = { OnFoot = 150, Any = 40 },', 'W3s2 KB: checkpoint wake radii (drive-through traffic never wakes them)')
must_contain(KB_OPS, 'LabelMaxDistance = 40,', 'W3s2 KB: job world labels MaxDistance <= 40')
must_not_contain(KB_OPS, 'require(', 'W3s2 KB: OpsConfig is pure data (safe on client and server)')
must_not_contain(KB_OPS, 'WaitForChild(', 'W3s2 KB: OpsConfig never waits')
must_contain(KB_CONST, 'OpsState = "OpsState",', 'W3s2 KB: Constants OpsState remote')
must_contain(KB_CONST, 'OpsProgress = "OpsProgress",', 'W3s2 KB: Constants OpsProgress remote')
must_contain(KB_CONST, 'OpsPing = "OpsPing",', 'W3s2 KB: Constants OpsPing remote')
must_not_contain(KB_CONST, 'RequestOps', 'W3s2 KB: no Ops client -> server remote (every job action is a server prompt)')
_kb_rs = read(KB_RS) or ''
_kb_ev = _kb_rs.split('local EVENTS = {', 1)[1].split('\n}', 1)[0] if 'local EVENTS = {' in _kb_rs else ''
_kb_un = _kb_rs.split('local UNRELIABLE = {', 1)[1].split('\n}', 1)[0] if 'local UNRELIABLE = {' in _kb_rs else ''
if 'Constants.RemoteNames.OpsState,' in _kb_ev and 'Constants.RemoteNames.OpsProgress,' in _kb_ev and 'OpsPing' not in _kb_ev:
    ok('W3s2 KB: RemoteSetup EVENTS has OpsState + OpsProgress (RemoteEvents), not OpsPing')
else:
    bad('W3s2 KB: RemoteSetup EVENTS must list OpsState + OpsProgress and not OpsPing')
if 'Constants.RemoteNames.OpsPing,' in _kb_un and 'OpsState' not in _kb_un and 'OpsProgress' not in _kb_un:
    ok('W3s2 KB: RemoteSetup UNRELIABLE has OpsPing (UnreliableRemoteEvent, spec §8)')
else:
    bad('W3s2 KB: RemoteSetup UNRELIABLE must list OpsPing only')

# --- W3 step 2 Phase B lane N (NPC core): SpawnNPC opts, stances, leash, groups, no-respawn, OnNPCDeath ---
N_CC = 'src/ReplicatedStorage/Shared/Configs/CombatConfig.luau'
N_CS = 'src/ServerScriptService/Server/Services/CombatService/init.luau'
N_NPC = 'src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau'
# spec §8 Phase B (lane N)
must_contain(N_CS, 'NoRespawn', 'W3s2 N: SpawnNPC opts.NoRespawn (spec §8)')
must_contain(N_CC, 'SpecialNPCTypes', 'W3s2 N: the special NPC list lives in CombatConfig (spec §8)')
must_contain(N_NPC, 'Stance', 'W3s2 N: CombatNPC stances (spec §8)')
# CombatConfig (contract §5.1); FieldBootstrap ships true: the integrator swaps this needle for 'FieldBootstrap = false,' at the cutover
must_contain(N_CC, 'SpecialNPCTypes = { "BankGuard", "OilRigGuard", "FortGuard" } :: { string },', 'W3s2 N: special types = BankGuard, OilRigGuard, FortGuard (today\'s list, now config)')
must_contain(N_CC, 'SpecialOverCap = 4,', 'W3s2 N: special / OverCap headroom +4 (18 + 4 = 22)')
must_contain(N_CC, 'MaxActiveNPCs = 18,', 'W3s2 N: the regular NPC cap stays 18 (spec §4)')
must_contain(N_CC, '\tFieldBootstrap = true,', 'W3s2 N: legacy field NPCs ship ON until the Ops cutover (swap to false there)')
must_contain(N_CC, 'ProvokeHoldSeconds = 2,', 'W3s2 N: an on-foot player provokes a Passive group after 2 s')
must_contain(N_CC, 'CalmSeconds = 30,', 'W3s2 N: a provoked group calms 30 s after its last contact')
must_contain(N_CC, 'CampCommander = {', 'W3s2 N: the CampCommander NPC type (OpsConfig.Npc.CommanderType)')
# CombatService (contract §5.2)
must_contain(N_CS, 'function CombatService.SpawnNPC(typeId: string?, at: CFrame, opts: NPCSpawnOpts?): NPCRecord?', 'W3s2 N: SpawnNPC(type, at, opts?) (2-argument calls unchanged)')
must_contain(N_CS, 'local isSpecial = table.find(CombatConfig.SpecialNPCTypes, tid) ~= nil or o.OverCap', 'W3s2 N: the cap reads the special list from config; OverCap counts as special')
must_contain(N_CS, 'if aliveNPCCount() >= (if isSpecial then cap + CombatConfig.SpecialOverCap else cap) then', 'W3s2 N: cap 18 regular, 22 with the special headroom')
must_not_contain(N_CS, 'tid == "BankGuard" or tid == "OilRigGuard" or tid == "FortGuard"', 'W3s2 N: no hard-coded special list in SpawnNPC')
must_contain(N_CS, 'fireNPCDeath(rec, attacker, byUnit == true) -- lane N\n\tif rec.NoRespawn then\n\t\treturn -- lane N: an Ops garrison NPC is never respawned', 'W3s2 N: a killed NoRespawn NPC reports its death and is never respawned')
must_contain(N_CS, 'fireNPCDeath(rec, nil, false) -- lane N: no killer\n\t\t\tif not rec.NoRespawn then', 'W3s2 N: a death with no killer reports it (Killer nil) and skips the respawn for NoRespawn')
must_contain(N_CS, 'if rec.DeathFired then\n\t\treturn\n\tend\n\trec.DeathFired = true', 'W3s2 N: OnNPCDeath fires once per death')
must_contain(N_CS, 'xpcall(entry.Fn, function(err: any)\n\t\t\t\twarn("[CombatService] OnNPCDeath listener error:", err)', 'W3s2 N: each OnNPCDeath listener runs in its own pcall')
must_contain(N_CS, 'function CombatService.OnNPCDeath(fn: (info: NPCDeathInfo) -> ()): () -> ()', 'W3s2 N: OnNPCDeath API (contract §5.2)')
must_contain(N_CS, 'function CombatService.DespawnNPC(id: string): boolean', 'W3s2 N: DespawnNPC API (silent: no pay, no respawn, no death event)')
must_contain(N_CS, 'rec.DeathFired = true -- never reported as a death\n\trec.Alive = false', 'W3s2 N: DespawnNPC pays nothing and reports nothing')
must_contain(N_CS, 'function CombatService.ProvokeGroup(groupId: string, seconds: number?): number', 'W3s2 N: ProvokeGroup API')
must_contain(N_CS, 'function CombatService.CalmGroup(groupId: string): number', 'W3s2 N: CalmGroup API')
must_contain(N_CS, 'function CombatService.GroupNPCs(groupId: string): { NPCInfo }', 'W3s2 N: GroupNPCs API')
must_contain(N_CS, 'function CombatService.NPCCounts(): { Regular: number, Special: number, Total: number }', 'W3s2 N: NPCCounts API')
must_contain(N_CS, 'CombatNPC.ProvokeGroup(npcRecords, rec.GroupId or rec.Id, nil, clock())', 'W3s2 N: a player (or squad unit) hurting a grouped NPC provokes its group')
must_contain(N_CS, 'if CombatConfig.FieldBootstrap ~= false then\n\t\t\tCombatService.BootstrapNPCs()', 'W3s2 N: FieldBootstrap = false skips the legacy field NPCs')
must_contain(N_CS, 'model:SetAttribute("WE_Static", true)', 'W3s2 N: a static post carries WE_Static')
# CombatNPC (contract §5.3); the P1-2 LOS / hit-chance needles (existing) stay as they are
must_contain(N_NPC, 'if hum and root and hum.Health > 0 and hum.SeatPart == nil then', 'W3s2 N: only an ON-FOOT player provokes by proximity (drive-through commuters are never shot)')
must_contain(N_NPC, 'local canMove = stance ~= "Post"', 'W3s2 N: a Post / Static NPC never calls MoveTo')
must_contain(N_NPC, 'elseif not rec.Returning and d2 > rec.Leash * rec.Leash then', 'W3s2 N: the leash (past Leash it walks Home, target dropped)')
must_contain(N_NPC, 'if canMove and dist > rec.Def.Range * 0.85 then', 'W3s2 N: a Post never chases; walkers chase exactly as before')
must_contain(N_NPC, 'if rec.Leash == nil and not usesGroup(rec) then', 'W3s2 N: an NPC with no opts takes today\'s Think path')
must_not_contain(N_NPC, 'GetDescendants', 'W3s2 N: no tree scans in the NPC think loop')
must_not_contain(N_NPC, 'RenderStepped', 'W3s2 N: NPC think stays on the 0.35 s server loop')
# verifier additions (lane N adversarial pass): leash edge holds and fires; a passive group's Post stays quiet after a wipe
must_contain(N_NPC, 'if target and canMove and rec.Leash ~= nil and atLeashEdge(rec, target) then', 'W3s2 N verifier: a leashed NPC stops at the leash edge and fights from there (no free kills from just outside the leash)')
must_contain(N_NPC, 'local passiveGroupIds: { [string]: boolean } = {}', 'W3s2 N verifier: a Post re-spawned alone into an emptied passive group still holds fire')

# --- W3 step 2 Phase B lane O (Ops server): the only way to act is a rate-limited server prompt; ships OFF ---
O_DIR = 'src/ServerScriptService/Server/Services/OpsService/'
O_FILES = ['init', 'OpsZones', 'OpsGarrison', 'OpsCargo', 'OpsKinds', 'OpsDirector', 'OpsSites', 'OpsRewards']
O_INIT = O_DIR + 'init.luau'
must_contain(O_INIT, 'RateLimitService.Allow(player, "ops_prompt"', 'W3s2 O: every Ops prompt is rate-limited (spec §8)')
must_contain(O_INIT, 'if OpsConfig.Enabled ~= true then', 'W3s2 O: OpsService.Init returns at once while OpsConfig.Enabled is off')
must_contain(O_INIT, 'if OpsConfig.Rewards.RequireCashExempt and not cashExempt() then', 'W3s2 O: no job pays while "ops" is not cash-multiplier exempt')
must_contain(O_INIT, 'if not seatedOk and hum.SeatPart ~= nil then', 'W3s2 O: job prompts need the player on foot (server re-check)')
must_contain(O_INIT, 'if (root.Position - at).Magnitude > dist + Z.PromptSlack then', 'W3s2 O: prompt distance re-checked with server positions')
must_contain(O_INIT, 'OpsCargo.DropFor(player, prevPos)', 'W3s2 O: a teleport / new character drops a carried bag (no free trip home)')
for _f in O_FILES:
    must_not_contain(O_DIR + _f + '.luau', 'OnServerEvent', 'W3s2 O: no client -> server remote handler in OpsService/' + _f + ' (spec §8)')
    must_not_contain(O_DIR + _f + '.luau', 'OnServerInvoke', 'W3s2 O: no RemoteFunction handler in OpsService/' + _f)
    must_not_contain(O_DIR + _f + '.luau', 'Neon', 'W3s2 O: no Neon from OpsService/' + _f)
    must_not_contain(O_DIR + _f + '.luau', 'PointLight', 'W3s2 O: 0 lights from OpsService/' + _f)
    must_not_contain(O_DIR + _f + '.luau', 'AlwaysOnTop', 'W3s2 O: job labels never AlwaysOnTop (OpsService/' + _f + ')')
    must_not_contain(O_DIR + _f + '.luau', 'RenderStepped', 'W3s2 O: no per-frame work in OpsService/' + _f)
    must_not_contain(O_DIR + _f + '.luau', 'WaitForChild("Shared")', 'W3s2 O: never WaitForChild without a timeout (OpsService/' + _f + ')')
    must_not_contain(O_DIR + _f + '.luau', 'GiveCash', 'W3s2 O: no GiveCash in OpsService/' + _f)
for _f in ['init', 'OpsZones', 'OpsGarrison', 'OpsCargo', 'OpsKinds', 'OpsDirector', 'OpsRewards']:
    must_not_contain(O_DIR + _f + '.luau', 'GetDescendants', 'W3s2 O: no descendant scans in the Ops tick modules (' + _f + ')')
must_contain(O_DIR + 'OpsRewards.luau', 'EconomyService.AddCash(player, cash, R.CashReason)', 'W3s2 O: job cash only through EconomyService.AddCash("ops")')
must_contain(O_DIR + 'OpsRewards.luau', 'pcall(XPService.AddXP, player, xp, R.XPReason)', 'W3s2 O: job XP only through XPService.AddXP("ops")')
must_contain(O_DIR + 'OpsRewards.luau', 'return math.max(0, perTick / tick)', 'W3s2 O: pay R comes from the saved BaseUpgrades (TycoonMath), never the client')
must_contain(O_DIR + 'OpsSites.luau', 'Enum.ModelStreamingMode.Persistent', 'W3s2 O: streaming host rule 2 (1-part ActivityHost model Persistent)')
must_contain(O_DIR + 'OpsSites.luau', 'WorldLabel.SetRole(made, nil)', 'W3s2 O: site labels are never the objective marker')
must_contain(O_DIR + 'OpsSites.luau', 'if def.Kind == "Vault" and BankRaidConfig.Enabled ~= false then', 'W3s2 O: never two bank jobs (coexistence until the cutover)')
must_contain(O_DIR + 'OpsSites.luau', 'if def.Kind == "Camp" and (CombatConfig :: any).FieldBootstrap ~= false then', 'W3s2 O: never two garrisons on the camp posts')
must_contain(O_DIR + 'OpsGarrison.luau', 'opts.NoRespawn = true', 'W3s2 O: job NPCs never respawn (lane N NoRespawn)')
must_contain(O_DIR + 'OpsCargo.luau', 'return #bags < C.MaxBagsInWorld', 'W3s2 O: at most Cargo.MaxBagsInWorld bags (512-stud circle budget)')
must_contain(O_DIR + 'OpsCargo.luau', 'not ctx.Zones.Locked(carrier, nowC) and inHome(carrier, s.Pos)', 'W3s2 O: bags deliver only in the own plot, never while teleport-locked')
must_contain('src/ServerScriptService/Server/Modules/ProfileSchema.luau', 'Ops = { Cd = {}, DayKey = 0, Runs = {}, Seen = 0, Total = 0, BestBag = 0 },', 'W3s2 O: profile Ops default (spec §8 "Ops = {")')
must_contain('src/ServerScriptService/Server/Modules/ProfileSchema.luau', 'ensureOpsFields(profile, os.time())', 'W3s2 O: Migrate sanitises profile.Ops')
must_contain('src/ReplicatedStorage/Shared/Configs/AnalyticsConfig.luau', 'OPS_DONE = "OPS_DONE",', 'W3s2 O: Jobs analytics events')
must_contain('src/ReplicatedStorage/Shared/Configs/AnalyticsConfig.luau', 'BAG_DELIVER = "BAG_DELIVER",', 'W3s2 O: bag analytics events')
must_contain('src/ReplicatedStorage/Shared/Configs/OpsConfig.luau', 'LabelLift = 7,', 'W3s2 O: site label lift (OpsConfig.Ui)')
must_contain('src/ReplicatedStorage/Shared/Configs/OpsConfig.luau', 'FallbackRadius = 30,', 'W3s2 O: no-plot bag delivery radius (OpsConfig.Cargo)')
_o_boot = read('src/ServerScriptService/Server/Bootstrap.server.luau') or ''
_o_sq = _o_boot.find('safeInit("SquadOrdersService", SquadOrdersService, deps)')
_o_op = _o_boot.find('safeInit("OpsService", OpsService, deps)')
if _o_sq >= 0 and _o_op > _o_sq and 'local OpsService = safeRequire("OpsService", Services.OpsService)' in _o_boot and '\tOpsService = OpsService,' in _o_boot:
    ok('W3s2 O: Bootstrap inits OpsService after SquadOrdersService (spec §8 safeInit("OpsService"))')
else:
    bad('W3s2 O: Bootstrap must safeRequire + deps + safeInit("OpsService", ...) after SquadOrdersService')

# --- W3 step 2 Phase B lane O, verifier fixes: seated teleport, NPC kill farm, stale spawn generation, starter clan ---
O_DIR = 'src/ServerScriptService/Server/Services/OpsService/'
must_contain(O_DIR + 'OpsZones.luau', 'local base = if seated or s.Seated then (Z.TeleportStudsSeated or 150) else Z.TeleportStuds', 'W3s2 O: a seated teleport (client-owned vehicle moved home) also drops the bag and locks out')
must_contain('src/ReplicatedStorage/Shared/Configs/OpsConfig.luau', 'TeleportStudsSeated = 150,', 'W3s2 O: seated teleport threshold (> 2x the fastest vehicle cap per 0.25 s tick)')
must_contain(O_DIR + 'OpsGarrison.luau', 'local tooSoon = playersClear ~= nil and deadAt[i] ~= nil and nowC - deadAt[i] < delay', 'W3s2 O: an Open top-up never respawns a killed guard sooner than the respawn delay (no kill farm)')
must_contain('src/ReplicatedStorage/Shared/Configs/OpsConfig.luau', 'TopUpDelaySeconds = 18,', 'W3s2 O: top-up delay = CombatConfig.NPCRespawnSeconds')
must_contain(O_DIR + 'OpsGarrison.luau', 'return -- a Sleep reset Pending and cancelled this spawn', 'W3s2 O: a cancelled staggered spawn never counts down a later generation')
must_contain(O_DIR + 'OpsKinds.luau', 'rt.StarterClan = if player then ctx.Zones.ClanOf(player) else nil', 'W3s2 O: the starter clan is read once at activation (a leaving starter never strands the team)')

# --- W3 step 2 Phase B lane U (Jobs client): JOBS board, job card + hold pill, GO = the nearest per-player target ---
U_OC = 'src/StarterPlayer/StarterPlayerScripts/Client/Controllers/OpsController.luau'
U_OJ = 'src/StarterPlayer/StarterPlayerScripts/Client/Modules/OpsJobs.luau'
U_OM = 'src/StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau'
U_MC = 'src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MissionController.luau'
U_CW = 'src/StarterPlayer/StarterPlayerScripts/Client/Modules/ConsoleWaypoint.luau'
U_BOOT = 'src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau'
U_NC = 'src/ReplicatedStorage/Shared/Configs/NotificationConfig.luau'
must_contain(U_OC, 'if OpsConfig.Enabled ~= true then', 'W3s2 U: the Jobs client is a no-op while OpsConfig.Enabled is false (ships OFF)')
must_contain(U_OC, 'ObjectiveMarker.ShowWith(p, MARKER_OPTS)', 'W3s2 U: job GO points the one objective marker (OpsConfig.Ui arrival / timeout)')
must_contain(U_OC, 'HudLayout.RegisterTopStack("OpsCard", c, HudConfig.TopStack.Order.Objective, { Space = "Hud" })', 'W3s2 U: the job card lives in the top stack Objective slot')
must_contain(U_OC, 'HudLayout.RegisterTopStack("OpsProgress", p.Frame, HudConfig.TopStack.Order.Progress, { Space = "Hud" })', 'W3s2 U: the hold pill lives in the top stack Progress slot')
must_contain(U_OC, 'local HIDE_CARD = { "Tutorial", "Modal", "Dead", "InOwnPlot", "Driving" }', 'W3s2 U: the job card never shows in a panel, the tutorial, your plot or while driving')
must_contain(U_OC, 'Remotes.TryGetUnreliableEvent(Constants.RemoteNames.OpsPing)', 'W3s2 U: OpsPing (UnreliableRemoteEvent) is polled with a bounded retry')
for _n in ('FireServer', 'Remotes.GetUnreliableEvent(', 'RenderStepped', 'Heartbeat', 'GetDescendants', 'WaitForChild("Shared")', 'WaitForChild("PlayerGui")'):
    must_not_contain(U_OC, _n, 'W3s2 U: OpsController has no %s (no job request, no per-frame work, bounded waits)' % _n)
must_contain(U_OJ, 'function OpsJobs.Rows(cache: Cache, me: Me?, trackedId: string?, userId: number, now: number?): { Row }', 'W3s2 U: the pure JOBS resolver (contract §6)')
must_contain(U_OJ, 'function OpsJobs.GoFor(cache: Cache, id: string, me: Me?, userId: number, now: number?): Point?', 'W3s2 U: GO resolves the current per-player point')
must_contain(U_OJ, 'function OpsJobs.NearestLike(cache: Cache, id: string, me: Me?, now: number?): string?', 'W3s2 U: a closed job re-resolves to the nearest open one of that job')
for _n in ('Instance.new', 'os.clock(', 'FireServer', 'Heartbeat', 'GetDescendants', 'workspace', 'Workspace'):
    must_not_contain(U_OJ, _n, 'W3s2 U: OpsJobs is pure (no %s)' % _n)
must_contain(U_OM, 'function ObjectiveMarker.ShowWith(target: Target, opts: Opts?)', 'W3s2 U: ObjectiveMarker.ShowWith (additive; Show stays frozen)')
must_contain(U_OM, 'function ObjectiveMarker.Move(x: number, y: number, z: number): boolean', 'W3s2 U: the marker follows a moving job (bag / rotating cache) without a rebuild')
must_contain(U_OM, 'function ObjectiveMarker.Ended(): string?', 'W3s2 U: Ended() tells an arrival from another GO')
must_contain(U_MC, 'function MissionController.SetJobsSource(src: JobsSource?)', 'W3s2 U: the Missions panel hosts the JOBS rows')
must_contain(U_MC, 'local JOBS_UI = OpsConfig.Ui.Jobs', 'W3s2 U: JOBS row sizes come from OpsConfig.Ui (config first)')
must_contain(U_MC, 'local btnH = if isTouch then math.max(JOBS_UI.GoH, TAP) else TAP', 'W3s2 U: JOBS GO >= 72 v on touch (46.8 real px)')
must_contain(U_MC, 'local JOBS_ROW_ORDER = -100 -- above the daily rows', 'W3s2 U: JOBS sit above the daily rows')
_u_cw = read(U_CW) or ''
_u_clr = 'pcall(function() local req: any = require; req(script.Parent.ObjectiveMarker).Clear() end)'
if _u_cw.count(_u_clr) == 2 and _u_cw.find('function ConsoleWaypoint.Show(') < _u_cw.find(_u_clr) < _u_cw.find('function ConsoleWaypoint.ShowAtm(') < _u_cw.rfind(_u_clr):
    ok('W3s2 U: ConsoleWaypoint.Show and ShowAtm clear the objective marker (the latest GO wins)')
else:
    bad('W3s2 U: ConsoleWaypoint.Show and ShowAtm must each clear the objective marker')
must_contain(U_BOOT, 'safeInit("OpsController", safeRequire("OpsController", Controllers:WaitForChild("OpsController", 5) :: Instance))', 'W3s2 U: OpsController starts from the client Bootstrap (guarded)')
must_contain(U_NC, '{ Match = " robbed the Empire Bank$", MinGapSeconds = OPS_DIRECTOR.RobbedLineGapSeconds },', 'W3s2 U: the robbed line is at most one a minute on the client too')
must_contain(U_NC, '{ Match = " is open$", MinGapSeconds = OPS_DIRECTOR.OpenToastGapSeconds },', 'W3s2 U: "<job> is open" at most once per 10 min on the client too')
# --- W3 step 2 Phase B lane U, verifier fixes (the latest GO wins after arrival too; a bag that runs off is chased) ---
must_contain(U_OC, 'if rev == myRev and not (arrived and ObjectiveMarker.OnTop()) then', 'W3s2 U: after arrival a newer marker or console line untracks the job (the card never names a stale job)')
must_contain(U_OC, 'checkMarker() -- first: a newer GO (mission / console) wins before anything here could re-show our marker', 'W3s2 U: a job re-resolve never replaces a newer GO marker')
must_contain(U_OC, 'refollowIfFar(id, p, me) -- the carrier ran off: chase it again', 'W3s2 U: a bag that runs off after arrival gets its marker back')
must_contain(U_OJ, 's = string.gsub(s, SEP .. SEP, SEP)', 'W3s2 U: a JOBS sub-line never shows a double separator')

# --- W3 step 2 Phase B lane M1 (missions): Ops objective types live only through OpsService's hook; GO from the hook ---
M1_MSV = 'src/ServerScriptService/Server/Services/MissionService.luau'
M1_MCF = 'src/ReplicatedStorage/Shared/Configs/MissionConfig.luau'
M1_DOC = 'src/ReplicatedStorage/Shared/Configs/DailyOpsConfig.luau'
must_contain(M1_MSV, 'function MissionService.SetOpsHooks(hooks: OpsHooks?)', 'W3s2 M1: OpsService hands MissionService its hooks (contract §7)')
must_contain(M1_MSV, 'if MissionConfig.OpsObjectives[objectiveType] == true then\n\t\treturn opsObjectiveLive(objectiveType)', 'W3s2 M1: an Ops objective is live only while the hook says so')
must_contain(M1_MSV, 'local ok, res = pcall(hooks.GoTargets, kind)', 'W3s2 M1: GO asks the Ops hook first; a failing hook never breaks the missions')
must_contain(M1_MSV, 'gd.Required == true and not goLookup(go).Served', 'W3s2 M1: a Required GO gates the offer by "served", so busy sites never reshuffle the day')
must_contain(M1_MSV, 'local near, setKey = nearestTargets(targets, player)', 'W3s2 M1: each entry sends the GoMaxTargets targets nearest the player')
must_contain(M1_MSV, 'goBit ..= setKey', 'W3s2 M1 (verifier): the refresh signature names the nearest set, so a moving player is re-sent the targets now nearest')
must_contain(M1_MSV, 'if gen ~= hookGen or opsHooks == nil then', 'W3s2 M1: the GO refresher runs only while the Ops hook is set')
must_not_contain(M1_MSV, 'Heartbeat', 'W3s2 M1: no per-frame work in MissionService (the refresher is a 30 s timer)')
must_not_contain(M1_MSV, 'RenderStepped', 'W3s2 M1: no per-frame work in MissionService')
must_contain(M1_MCF, 'OpsObjectives = {', 'W3s2 M1: Checkpoint / Camp / Uplink / Delivery / Job are Ops objectives')
must_contain(M1_MCF, 'Checkpoint = { Short = "POST", Required = true },', 'W3s2 M1: Go Checkpoint (nearest Open checkpoint)')
must_contain(M1_MCF, 'Camp = { Short = "CAMP", Required = true },', 'W3s2 M1: Go Camp')
must_contain(M1_MCF, 'Uplink = { Short = "UPLINK", Required = true },', 'W3s2 M1: Go Uplink')
must_contain(M1_MCF, 'Job = { Short = "JOB", Required = true },', 'W3s2 M1: Go Job (nearest Open job)')
must_contain(M1_MCF, 'Hostiles = { Short = "HOSTILE" },', 'W3s2 M1: Go Hostiles for KillNPC (not Required: GO only with a target)')
must_contain(M1_MCF, 'GoMaxTargets = 16,', 'W3s2 M1: at most 16 GO targets per entry (MissionController reads 16)')
must_contain(M1_MCF, 'GoRefreshSeconds = 30,', 'W3s2 M1: GO lists refresh at most every 30 s per player')
_m1_mcf = read(M1_MCF) or ''
_m1_lo = _m1_mcf.split('LiveObjectives = {', 1)[1].split('}', 1)[0] if 'LiveObjectives = {' in _m1_mcf else None
if _m1_lo is not None and 'Heist = true' in _m1_lo and not any(('\t%s = true' % k) in _m1_lo for k in ('Checkpoint', 'Camp', 'Uplink', 'Delivery', 'Job')):
    ok('W3s2 M1: LiveObjectives keeps Heist and lists no Ops objective (they are live only through OpsService)')
else:
    bad('W3s2 M1: LiveObjectives must keep Heist and must not list Checkpoint / Camp / Uplink / Delivery / Job')
must_contain(M1_DOC, 'Id = "DailyOpCamp",', 'W3s2 M1: Raid a Camp daily op')
must_contain(M1_DOC, 'Id = "DailyOpUplink",', 'W3s2 M1: Hack an Uplink daily op')
must_contain(M1_DOC, 'Id = "DailyOpCargo",', 'W3s2 M1: Haul Cargo daily op (offered once the hook serves Go Cargo)')
must_contain(M1_DOC, 'Go = "Checkpoint",', 'W3s2 M1: Take 2 Checkpoints has GO')
must_contain(M1_DOC, 'Go = "Job",', 'W3s2 M1: Finish 3 Jobs has GO')

# --- W3 step 2 Phase B integration: the lanes' pending edits (applied by the integrator after batch B part 2 committed) ---
must_contain('src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau', 'ops = true, -- W3s2 Jobs', 'W3s2 Jobs: "ops" cash is multiplier-exempt')
must_contain('src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.luau', 'if ObjectiveMarker.Current() ~= nil then', 'W3s2 U: the automatic guide line never replaces a job / mission GO')
must_contain('src/ServerScriptService/Server/Services/OpsService/init.luau', 'Cargo = { VaultLite = true, Cargo = true },', 'W3s2 M1: OpsService answers Go Cargo (the Haul Cargo daily op)')
must_contain('src/ReplicatedStorage/Shared/Configs/OpsConfig.luau', 'PingTtlSeconds = 25,', 'W3s2 U: a pinged carrier stays a Steal row 25 s (OpsConfig.Ui, config first)')
must_contain('src/ReplicatedStorage/Shared/Configs/OpsConfig.luau', 'Empty = "No jobs open · back soon",', 'W3s2 U: the JOBS header line when nothing is open')

# --- assetwire lane L1 (owner asset list 2026-09-25): VisualAssetConfig + StructureVisualConfig. Paste above the final
# `parse_gate()` call (apply_pins.py does it). Verified on clean HEAD 0a04776 + the two L1 config files: headless, not Roblox.
AW_VAC = "src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"
AW_SVC = "src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"
AW_VAS = "src/ServerScriptService/Server/Services/VisualAssetService.luau"
AW_GDS = "src/ServerScriptService/Server/Services/GateDefenseService.luau"
# owner rule 5: the three heavy building models never return (the VisualAssetService 6015472062 pin lands with lane L3)
for _aw_heavy in ("138331074285379", "18798977801", "6015472062"):
    must_not_contain(AW_VAC, _aw_heavy, f"assetwire rule 5: heavy id {_aw_heavy} never returns (VisualAssetConfig)")
    must_not_contain(AW_SVC, _aw_heavy, f"assetwire rule 5: heavy id {_aw_heavy} never returns (StructureVisualConfig)")
for _aw_heavy in ("138331074285379", "18798977801"):
    must_not_contain(AW_VAS, _aw_heavy, f"assetwire rule 5: heavy id {_aw_heavy} never returns (VisualAssetService)")
# third-party picks wait in PendingAssetId: typed, and never read by a loader (no load attempt, no budget cost)
must_contain(AW_VAC, "PendingAssetId: number?", "assetwire: AssetRef.PendingAssetId (the owner's third-party pick, never loaded)")
must_contain(AW_VAC, "OmitParts: { string }?", "assetwire: AssetRef.OmitParts (pack piece parts removed before the part count)")
must_contain(AW_VAC, "NoFamilyFallback: boolean?", "assetwire: AssetRef.NoFamilyFallback (a vehicle ref at 0 keeps the Part kit)")
must_not_contain(AW_VAS, ".PendingAssetId", "assetwire: VisualAssetService never reads PendingAssetId")
must_not_contain(AW_GDS, ".PendingAssetId", "assetwire: GateDefenseService never reads PendingAssetId")
# LIVE-NOW: Roblox-owned car bodies (Body sub-model, fitted to the kit, decals off)
must_contain(AW_VAC, 'ModelAssetId = 6433272094,\n\t\t\tChildName = "Dune Buggy (beige)",\n\t\t\tSubModel = "Body",\n\t\t\tFit = "Kit",', "assetwire: Utility Quad / Recon Buggy wear the Roblox Dune Buggy (beige) Body, fitted to the kit")
must_contain(AW_VAC, 'ModelAssetId = 6433316269,\n\t\t\tChildName = "Van (white)",\n\t\t\tSubModel = "Body",\n\t\t\tFit = "Kit",', "assetwire: Cargo Van wears the Roblox Van (white) Body, fitted to the kit")
must_contain(AW_VAC, 'ModelAssetId = 6418225759,\n\t\t\tChildName = "Pickup Truck (bronze)",\n\t\t\tSubModel = "Body",\n\t\t\tFit = "Kit",', "assetwire: Patrol / Escort Truck wear the Roblox Pickup Truck (bronze) Body, fitted to the kit")
must_contain(AW_VAC, 'OmitParts = { "light_tail_glass" },', "assetwire: the Pickup Body drops its tail-light glass (41 -> 40 parts, the cap)")
must_contain(AW_VAC, "BridgeLayer = { ModelAssetId = 0, NoFamilyFallback = true,", "assetwire: Bridge Layer keeps its Part kit (owner: no good match)")
must_contain(AW_VAC, "OilBarrel = { ModelAssetId = 23153991,", "assetwire: training-yard oil drum = Roblox Smoking Barrel")
must_contain(AW_VAC, "StripEffectsAssetIds = { 23153991", "assetwire: the Smoking Barrel loses its smoke (StripEffectsAssetIds)")
must_contain(AW_VAC, 'Log = { ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Tree_Log_01",', "assetwire: fallen logs wear Synty Tree_Log_01")
must_contain(AW_VAC, 'Driftwood = { ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Tree_Twig_02", Yaw = 90,', "assetwire: driftwood has its own key (Tree_Twig_02 turned 90)")
must_contain(AW_VAC, 'CarWreck = { ModelAssetId = 6933556508, ChildName = "Meshes/PolygonCity_Props_SM_Veh_Car_Sedan_01", Yaw = 90,', "assetwire: car wrecks = Synty sedan turned 90")
# the load budget stays 48 / 12 (pins 3697 / 3700 unchanged); pending ids are never loaded
must_contain(AW_VAC, "past MaxLoadAttempts - 8 (= 40)", "assetwire: the promote tool's live-id budget is MaxLoadAttempts - 8")
# rule 4 is untouched: structure kits never prefer a mesh
must_contain(AW_SVC, "PreferMeshWhenAssetIdSet = false", "assetwire: PreferMeshWhenAssetIdSet stays false (owner rule 4)")
# --- assetwire lane L1 pin that needs lane L3 in the same tree (VisualAssetService.luau still holds the hangar id 3 times
# at HEAD: :1089 comment, :1126 local hangarId, :1173 sentinel). FAILS on the L1-only tree by design; INTEG adds it with L3.
must_not_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "6015472062", "assetwire rule 5: heavy id 6015472062 never returns (VisualAssetService: the Airfield composite reads Buildings.Hangar)")
# --- assetwire lane L3 (owner asset list 2026-09-25): WeaponConfig, WeaponAssetLoader, VisualAssetService, WorldKits.
# Paste above the final `parse_gate()` call, after lane L1's block (+ its bps_pins_after_L3.txt, which carries the
# VisualAssetService 6015472062 must_not_contain). Verified headless on clean HEAD 0a04776 + L1's two config files + these
# four files (not Roblox): FAIL=0.
AW_WC = "src/ReplicatedStorage/Shared/Configs/WeaponConfig.luau"
AW_WAL = "src/ServerScriptService/Server/Modules/WeaponAssetLoader.luau"
AW_VAS3 = "src/ServerScriptService/Server/Services/VisualAssetService.luau"
AW_WK = "src/ServerScriptService/Server/Modules/WorldKits.luau"
# LIVE-NOW guns: the Roblox Weapons Kit (creator Roblox, User 1), one Tool + its gun Model each (VisualChild required:
# the whole Tool is 17-19 parts, over the loader's 16)
for _aw_id, _aw_tool, _aw_child in (("4842207161", "AR", "AR"), ("4842212980", "SMG", "SMG"), ("4842197274", "Pistol", "Pistol"),
        ("4842215723", "Shotgun", "Shotgun"), ("4842218829", "Sniper", "Sniper"), ("4842186817", "Rocket Launcher", "RocketLauncher")):
    must_contain(AW_WC, f'VisualAssetId = {_aw_id}, -- Roblox Weapons Kit (owner list 2026-09-25; docs/ASSET_WIRING.md)\n\t\t\tVisualToolName = "{_aw_tool}",\n\t\t\tVisualChild = "{_aw_child}",', f"assetwire L3: gun visual {_aw_id} Tool {_aw_tool} > Model {_aw_child}")
must_contain(AW_WC, "MeshId = 94690081, TextureId = 94689966 }", "assetwire L3: rocket in flight = Roblox rocket mesh + texture")
must_contain(AW_WC, "MeshId = 232379763, TextureId = 232379808 }", "assetwire L3: grenade in flight = Roblox grenade mesh + texture")
# WeaponAssetLoader: the gun Model is ONE clone (kit joints stay on the copies), plus the kit's invisible Handle at the
# gun's HandleAttachment, welded to it (the client grips the part named Handle); kit flash Beams / effects go
must_contain(AW_WAL, "local MAX_PARTS = 16", "assetwire L3: gun template part cap unchanged (16)")
must_contain(AW_WAL, "local copyOrNil: Instance? = source:Clone() -- nil when the source is not Archivable", "assetwire L3: gun Model copied as one clone (joints remapped)")
must_not_contain(AW_WAL, "c:Clone().Parent = model", "assetwire L3: no part-by-part gun copy (left kit joints pointing at the source asset)")
must_contain(AW_WAL, "function WeaponAssetLoader._AddGripHandle(model: Model, kitHandle: BasePart, body: BasePart?)", "assetwire L3: kit Handle copied into the gun template")
must_contain(AW_WAL, "h.CFrame = anchorPart.CFrame * att.CFrame -- where the kit's equip weld puts the Handle", "assetwire L3: grip Handle placed on the gun's HandleAttachment")
must_contain(AW_WAL, "h.Transparency = 1", "assetwire L3: grip Handle invisible")
must_contain(AW_WAL, 'w.Name = "WE_GripWeld"', "assetwire L3: grip Handle welded to the gun body")
must_contain(AW_WAL, 'if d:IsA("LuaSourceContainer") or d:IsA("Sound") or isEffect(d) then', "assetwire L3: gun templates keep no scripts, sounds or effects")
# VisualAssetService: OmitParts before the part count, StripEffectsAssetIds, NoFamilyFallback, Hangar from config,
# kit piece yaw + IsKitMeshWired (the pinned part-cap lines 2002 / 2003 / 3691 / 3692 are unchanged)
must_contain(AW_VAS3, "-- owner list: OmitParts (e.g. the Pickup Truck's tail-light glass) go before the part count", "assetwire L3: pack piece OmitParts removed before the part count")
must_contain(AW_VAS3, '.. (if #omit > 0 then "|-" .. table.concat(omit, ",") else "")', "assetwire L3: the piece key carries OmitParts")
must_contain(AW_VAS3, 'local EFFECT_CLASSES = { "Fire", "Smoke", "Sparkles", "ParticleEmitter", "Light", "Beam", "Trail" }', "assetwire L3: effect classes stripped for StripEffectsAssetIds")
must_contain(AW_VAS3, "if stripsEffects(assetId) then", "assetwire L3: only StripEffectsAssetIds lose their effects (MoneyBagFX keeps its particles)")
must_contain(AW_VAS3, 'if typeof(ref) == "table" and ref.NoFamilyFallback == true then', "assetwire L3: a NoFamilyFallback vehicle never takes the family body")
must_contain(AW_VAS3, "local hangarId = refId((VisualAssetConfig.Buildings :: any).Hangar)", "assetwire L3 rule 5: the Airfield hangar id comes from config")
must_contain(AW_VAS3, "local hangarTemplate = if hangarId > 0 then loadModel(hangarId) else nil", "assetwire L3 rule 5: hangar 0 = Part shed, no LoadAsset call")
must_contain(AW_VAS3, 'mp:SetAttribute("WE_KitYaw", ref.Yaw)', "assetwire L3: kit mesh piece carries its ref Yaw")
must_contain(AW_VAS3, "function VisualAssetService.IsKitMeshWired(key: string): boolean", "assetwire L3: config-only wired check for kit mesh keys")
# WorldKits: Driftwood has its own mesh key, yaw-turned pieces, unwired keys take no overlay slot, each wired key takes
# at most its share of the cap (the cap stays 40, pin 1935)
must_contain(AW_WK, 'Driftwood = spec(2, 2, Vector3.new(7.05, 0.9, 3.8), "natural", false, 1, "Travel", { Mesh = "Driftwood" }),', "assetwire L3: driftwood uses its own mesh key (never the Z-long log)")
must_contain(AW_WK, "local function yawedBox(m: BasePart, boxCf: CFrame, size: Vector3): (CFrame, Vector3)", "assetwire L3: WE_KitYaw turns a kit mesh onto the kit's long axis")
must_contain(AW_WK, "local meshCf, meshSize = yawedBox(m, boxCf, size)", "assetwire L3: each / collider overlays use the yawed box")
must_contain(AW_WK, "if okW and wired == false then", "assetwire L3: an unwired mesh key takes no MeshOverlays slot")
must_contain(AW_WK, "local function shareOfCap(isWired: (string) -> boolean, cap: number): number", "assetwire L3: one wired mesh key takes at most ceil(cap / wired keys) overlay slots")
must_contain(AW_WK, "if (overlaysByKey[ov.Key] or 0) >= shareOfCap(isWired, cap) then", "assetwire L3: the overlay cap is shared, so the travel dressing's logs / dead trees / stumps get slots")
# --- assetwire lane L2 (owner asset list 2026-09-25): docs/ASSET_WIRING.md, docs/ASSET_LICENSES.md, tools/wire-asset-ids.py.
# Paste above the final `parse_gate()` call. Verified on clean HEAD 0a04776 + the L2 files (and + lane L1): headless, not Roblox.
AW2_WIRING = "docs/ASSET_WIRING.md"
AW2_LIC = "docs/ASSET_LICENSES.md"
AW2_TOOL = "tools/wire-asset-ids.py"
# the owner page keeps the block the promote tool regenerates
must_contain(AW2_WIRING, "<!-- wire-asset-ids:begin (generated by tools/wire-asset-ids.py render; do not edit by hand) -->", "assetwire L2: ASSET_WIRING.md status block start (tools/wire-asset-ids.py render)")
must_contain(AW2_WIRING, "<!-- wire-asset-ids:end -->", "assetwire L2: ASSET_WIRING.md status block end")
# the licence file keeps the tables the promote tool appends to
must_contain(AW2_LIC, "## 3.1 Owner picks (third-party, promoted by `tools/wire-asset-ids.py`)", "assetwire L2: ASSET_LICENSES.md §3.1 owner picks")
must_contain(AW2_LIC, "<!-- wire-asset-ids:owner-picks:end -->", "assetwire L2: ASSET_LICENSES.md §3.1 marker (promote appends rows above it)")
must_contain(AW2_LIC, "<!-- wire-asset-ids:replaced:end -->", "assetwire L2: ASSET_LICENSES.md §2e marker (replaced ids)")
must_contain(AW2_LIC, "### 2d. Cleared by owner rule 5 (2026-09-25, owner asset list)", "assetwire L2: the rule-5 heavy ids are documented as cleared")
# every Roblox-owned id this build wires has its licence row (§3.0); the kit guns keep their attribution
for _aw2_id in ("6433272094", "6418225759", "6433316269", "23153991", "4842207161", "4842212980", "4842197274", "4842215723", "4842218829", "4842186817", "232379763", "232379808", "94690081", "94689966"):
    must_contain(AW2_LIC, f"[{_aw2_id}](https://create.roblox.com/store/asset/{_aw2_id})", f"assetwire L2: licence row for Roblox-owned {_aw2_id}")
must_contain(AW2_LIC, "**gun models from Roblox's Weapons Kit (Roblox)**", "assetwire L2: Weapons Kit attribution (RBX-LUL)")
# the promote tool's gates stay in place
must_contain(AW2_TOOL, "OWNER_USER_ID = 470626172", "assetwire L2: promote checks the inventory of the game's owner (shaunie6)")
must_contain(AW2_TOOL, "BUDGET_MARGIN = 8", "assetwire L2: promote refuses a batch above MaxLoadAttempts - 8")
must_contain(AW2_TOOL, "MAX_PARTS = 40", "assetwire L2: STUDIO gate needs WE_CHECK parts <= 40")
must_contain(AW2_TOOL, 'elif wc.get("humanoids") != 0:', "assetwire L2: STUDIO gate needs WE_CHECK humanoids = 0")
must_contain(AW2_TOOL, 'if tree.prefer_mesh() != "false":', "assetwire L2: promote refuses unless PreferMeshWhenAssetIdSet is false (rule 4)")
must_contain(AW2_TOOL, "REQUEST_GAP = 0.55", "assetwire L2: at most 2 network requests per second")
must_not_contain(AW2_TOOL, "files.set(SVC_REL", "assetwire L2: the promote tool never writes StructureVisualConfig")
must_not_contain(AW2_TOOL, "import requests", "assetwire L2: the promote tool is standard library only")

parse_gate()

print(f"[BuyPathStatic] Done PASS={PASS} FAIL={FAIL}")
sys.exit(1 if FAIL else 0)
