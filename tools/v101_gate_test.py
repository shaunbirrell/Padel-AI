#!/usr/bin/env python3
"""Code Bot v101 (2026-09-29): executes the real rollout gates with the Luau CLI for a NON-owner account, with
MonetizationConfig.LaunchAll left false (v101 flips each gate's own Rollout to "all" instead).

For a second account (UserId 1234567, not the owner 470626172) every live gate must be open: the 13 RolloutKeys SKUs,
VIP perks, placement prompts, retention (incl. the Premium perk), airdrop, daily auto-claim, plaza bounty, army
upgrades, guards fight back, NPC unstick, first minutes, quality tier, juice, the balance curve and the army parts
(Escort / Army / Fix / ThreatStandingFor / Follow2 / Tidy). The switches that stay off must stay off for him:
AircraftWeaponConfig.WeaponsLive (and its LiveFor for him).
Uses the harness of tools/launch_gate_test.py. Prints PASS / FAIL lines, exits 1 on any FAIL; SKIP without luau.
"""
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("lgt", HERE / "launch_gate_test.py")
lgt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lgt)
lgt.MODULES = lgt.MODULES + ["CombatConfig", "ArmyConfig", "AircraftWeaponConfig"]


def tutorial_slice() -> str:
    """TutorialConfig needs half the game to load; take only its FirstMinutes block and gate (the real source text)."""
    src = (lgt.CFG / "TutorialConfig.luau").read_text(encoding="utf-8")
    i = src.index("TutorialConfig.FirstMinutes = {")
    j = src.index("\nend\n", src.index("function TutorialConfig.FirstMinutesLiveFor(")) + 5
    eq = "=" * 8
    return "SRC['TutorialConfig'] = [%s[local TutorialConfig = {}\n%s\nreturn TutorialConfig]%s]\n" % (eq, src[i:j], eq)

BODY = r'''
local OWNER, OTHER = %d, %d
check(M.LaunchAll == false, "LaunchAll stays false (each gate's own Rollout is \"all\")")
check(M.Rollout == "all", "MonetizationConfig.Rollout = all")
local n = 0
for key in pairs(M.RolloutKeys) do
	n += 1
	check(M.SkuLiveFor(OTHER, key) == true, "non-owner can buy " .. key)
	local def = M.GamePasses[key] or M.DevProducts[key]
	check(def ~= nil and typeof(def.Id) == "number" and def.Id ~= 0, "live SKU " .. key .. " has a real Id")
end
check(n == 13, "13 RolloutKeys SKUs (" .. n .. ")")
local C = load("CombatConfig")
local T = load("TutorialConfig")
local A = load("ArmyConfig")
local W = load("AircraftWeaponConfig")
local gates = {
	{ "VIPPerks", function(u) return M.VIPPerksLiveFor(u) end },
	{ "Placement", function(u) return M.PlacementLiveFor(u) end },
	{ "Retention (+ Premium perk)", function(u) return M.RetentionLiveFor(u) end },
	{ "Airdrop", function(u) return load("SupplyDropConfig").AirdropLiveFor(u) end },
	{ "DailyAutoClaim", function(u) return load("DailyRewardConfig").AutoClaimLiveFor(u) end },
	{ "PlazaBounty", function(u) return load("PlazaBountyConfig").LiveFor(u) end },
	{ "ArmyUpgrades", function(u) return load("ArmyUpgradeConfig").LiveFor(u) end },
	{ "QualityTier", function(u) return load("QualityConfig").LiveFor(u) end },
	{ "Juice", function(u) return load("JuiceConfig").LiveFor(u) end },
	{ "BalanceCurve", function(u) return load("BalanceConfig").LiveFor(u) end },
	{ "GuardsFightBack", function(u) return C.LiveFor(C.GuardsFightBack, u) end },
	{ "NpcUnstick", function(u) return C.LiveFor(C.NpcUnstick, u) end },
	{ "FirstMinutes", function(u) return T.FirstMinutesLiveFor(u) end },
	{ "Army.Escort", function(u) return A.LiveFor("Escort", u) end },
	{ "Army.Army", function(u) return A.LiveFor("Army", u) end },
	{ "Army.Fix", function(u) return A.LiveFor("Fix", u) end },
	{ "Army.ThreatStandingFor", function(u) return A.ThreatStandingFor(u) end },
	{ "Army.Follow2", function(u) return A.Follow2.Enabled == true and A.Follow2.Rollout == "all" end },
	{ "Army.Follow2.Tidy", function(u) return A.Follow2.Tidy.Rollout == "all" end },
}
for _, g in ipairs(gates) do
	check(g[2](OTHER) == true, "non-owner gate " .. g[1] .. " open")
	check(g[2](OWNER) == true, "owner gate " .. g[1] .. " open")
end
check(W.WeaponsLive == false and W.LiveFor(OTHER) == false, "AircraftWeaponConfig.WeaponsLive stays off for a non-owner")
print("fails=" .. fails)
'''


def run(luau: str) -> int:
    code = lgt.harness(False) + tutorial_slice() + BODY % (lgt.OWNER, lgt.OTHER)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(code)
        path = f.name
    r = subprocess.run([luau, path], capture_output=True, text=True, timeout=60)
    os.unlink(path)
    text = r.stdout + r.stderr
    print(text.strip())
    m = re.search(r"fails=(\d+)", text)
    return int(m.group(1)) if m else 1


if __name__ == "__main__":
    luau = os.environ.get("LUAU") or shutil.which("luau")
    if not luau:
        print("SKIP: no luau CLI (set LUAU=/path/luau)")
        sys.exit(0)
    sys.exit(1 if run(luau) else 0)
