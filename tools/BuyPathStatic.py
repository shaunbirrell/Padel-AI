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

print(f"[BuyPathStatic] Done PASS={PASS} FAIL={FAIL}")
sys.exit(1 if FAIL else 0)
