# Code Bot Roblox v164 (2026-10-01): ship Claude JOB 42 part C + JOB 43 owner-first.
#  C. Recruit Pack cash = Cash30m time-pack amount while TimePacks live (CashFromTimePack);
#     JOB 41 clamp when off. 49 R$ / Id 0 / boost / trim unchanged.
#  JOB 43. Army vs army brawl (ArmyConfig.ArmyBrawl OwnerFirst=true): enemy soldiers are
#     Unit candidates under ArmyHostility; CombatService.ApplyUnitUnitHit re-checks per shot;
#     kills -> ARMY KILLS + XP (pair-capped). Board already live (v156).
# PreferMesh OFF. Do NOT flip TimePacks / Guided / RecruitPackOffer / Rival / RatePrompt /
# ArmyOrders / ArmyBrawl OwnerFirst. No Creator Hub products.
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"

for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 218'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 218'),
    (S + "Services/DataService.luau", "WE_Build=218"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 218'),
):
    check(needle in read(rel), "CODEBOT v164: WE_Build=218 " + rel.rsplit("/", 1)[-1])

# PreferMesh OFF
svc = read(C + "StructureVisualConfig.luau")
check("PreferMeshWhenAssetIdSet = false" in svc, "CODEBOT v164: PreferMeshWhenAssetIdSet stays false")

# JOB 42 C: Recruit Pack cash from Cash30m while TimePacks live
MC = read(C + "MonetizationConfig.luau")
check('CashFromTimePack = "Cash30m"' in MC, "CODEBOT v164: RecruitPack CashFromTimePack=Cash30m")
check("function cfg.RecruitPackCashFor" in MC and "function cfg.RecruitPackUsesTimePack" in MC,
      "CODEBOT v164: RecruitPackCashFor + RecruitPackUsesTimePack helpers")
RPS = read(S + "Services/RecruitPackService.luau")
check("MC.RecruitPackUsesTimePack" in RPS and "MC.RecruitPackCashFor" in RPS,
      "CODEBOT v164: RecruitPackService uses the time-pack cash helpers")
MS = read(S + "Services/MonetizationService.luau")
check("RecruitPackCashFor" in MS, "CODEBOT v164: MonetizationService ProcessReceipt uses RecruitPackCashFor")

# JOB 43: ArmyBrawl owner-first
AC = read(C + "ArmyConfig.luau")
check("ArmyBrawl = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in AC,
      "CODEBOT v164: ArmyConfig.ArmyBrawl Enabled + OwnerFirst=false (v166 flip-all-live)")
check((ROOT / (S + "Modules/ArmyBrawl.luau")).is_file(),
      "CODEBOT v164: Modules/ArmyBrawl.luau present")
AB = read(S + "Modules/ArmyBrawl.luau")
check("function ArmyBrawl.Candidates" in AB and "function ArmyBrawl.LiveFor" in AB,
      "CODEBOT v164: ArmyBrawl.Candidates + LiveFor")
CS = read(S + "Services/CombatService/init.luau")
check("function CombatService.ApplyUnitUnitHit" in CS, "CODEBOT v164: CombatService.ApplyUnitUnitHit")
SO = read(S + "Services/SquadOrdersService.luau")
check("local ArmyBrawl = require(script.Parent.Parent.Modules.ArmyBrawl)" in SO,
      "CODEBOT v164: SquadOrdersService requires ArmyBrawl")
check("local ArmyState = require(script.Parent.Parent.Modules.ArmyState)" in SO
      and "local ArmyCommand = require(script.Parent.Parent.Modules.ArmyCommand)" in SO,
      "CODEBOT v164: SquadOrdersService keeps ArmyState + ArmyCommand (v162)")
check("ArmyBrawl.Candidates" in SO and ('Kind = "Unit"' in SO or 'kind == "Unit"' in SO),
      "CODEBOT v164: SquadOrdersService adds Unit candidates via ArmyBrawl")

# Prior OwnerFirst flags still true
for rel, needle, label in (
    (C + "ShopOverhaulConfig.luau", "OwnerFirst = false", "CODEBOT v164: TimePacks OwnerFirst=false (v166 flip-all-live)"),
    (C + "RivalConfig.luau", "OwnerFirst = false", "CODEBOT v164: RivalConfig OwnerFirst=false (v166 flip-all-live)"),
):
    check(needle in read(rel), label)

# Sims
env = os.environ.copy()
for script, label in (
    ("tools/sim/run_recruit_pack_test.py", "CODEBOT v164: run_recruit_pack_test"),
    ("tools/sim/run_army_brawl_test.py", "CODEBOT v164: run_army_brawl_test"),
):
    if not (ROOT / script).is_file():
        check(False, label + " missing")
        continue
    r = subprocess.run([sys.executable, script], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=600)
    tail = [ln for ln in (r.stdout or "").splitlines() if ln.strip()][-3:] or [((r.stderr or "")[-200:])]
    check(r.returncode == 0, label + " " + (tail[-1] if tail else f"exit={r.returncode}"))
