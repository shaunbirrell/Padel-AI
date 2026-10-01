# Code Bot Roblox v168 (2026-10-01, owner Shaun): 1 the TARGETS card + list redesign (crosshair, the suggested
# rival's name / distance / loot, the empty reason; rows name / level / army / loot / distance, SEND ARMY + VIEW);
# 2 owner-only /setrebirth N (+ gear -> ADMIN SET REBIRTH) via PrestigeService.AdminSetRebirth (cash / items kept,
# saved); 3 the AIRDROP / BASE world label steps aside from a locked rebirth-zone sign (WE_ObjectiveYield);
# 4 "Contract done": the tracker / compass pill points at the Intel Office (WE_IntelGuide) until claimed.
# PreferMesh OFF, StreamingEnabled OFF, no fast travel, no price changes.
from pathlib import Path
import os
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
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 179)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 179)'),
    (S + "Services/DataService.luau", "WE_Build=179"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 179)'),
):
    check(needle in read(rel), "CODEBOT v168: WE_Build=179 " + rel.rsplit("/", 1)[-1])

ADM = read(S + "Services/AdminService.luau")
PS = read(S + "Services/PrestigeService.luau")
EG = read(S + "Services/EndgameService.luau")
RC = read(C + "RivalConfig.luau")
RCt = read(CL + "Controllers/RivalController.luau")
OM = read(CL + "Modules/ObjectiveMarker.luau")
RZB = read(S + "Modules/RebirthZoneBuilder.luau")
SC = read(CL + "Controllers/SettingsController.luau")
for cond, label in (
    ("function PrestigeService.AdminSetRebirth(" in PS, "PrestigeService.AdminSetRebirth"),
    ('cmd == "setrebirth"' in ADM and '"/setrebirth"' in ADM, "AdminService /setrebirth (chat + remote, allowlist only)"),
    ('"setrebirth"' in SC and "SET REBIRTH" in SC, "gear -> ADMIN SET REBIRTH"),
    ("function EndgameService.SyncIntelGuide(" in EG and '"WE_IntelGuide"' in EG, "EndgameService.SyncIntelGuide"),
    ((ROOT / CL / "Modules/IntelGuide.luau").is_file(), "Client IntelGuide module"),
    ('"WE_ObjectiveYield"' in RZB and "BoxesOverlap" in OM, "the locked-zone sign yields the objective label"),
    ("function RivalConfig.Layout(" in RC and "function RivalConfig.PillLines(" in RC, "RivalConfig.Layout / PillLines"),
    ("RivalConfig.Layout(cs.X, cs.Y, #rows)" in RCt and "RequestArmySend" in RCt, "RivalController card + SEND ARMY"),
):
    check(cond, "CODEBOT v168: " + label)

env = os.environ.copy()
for script, label in (
    ("tools/sim/run_codebot_v168_test.py", "CODEBOT v168: run_codebot_v168_test"),
    ("tools/sim/run_rival_targets_test.py", "CODEBOT v168: run_rival_targets_test"),
    ("tools/sim/run_endgame_test.py", "CODEBOT v168: run_endgame_test"),
    ("tools/sim/run_rebirth_test.py", "CODEBOT v168: run_rebirth_test"),
    ("tools/sim/run_base_marker_test.py", "CODEBOT v168: run_base_marker_test"),
):
    if not (ROOT / script).is_file():
        check(False, label + " missing")
        continue
    r = subprocess.run([sys.executable, script], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=900)
    tail = [ln for ln in (r.stdout or "").splitlines() if ln.strip()][-3:] or [((r.stderr or "")[-200:])]
    check(r.returncode == 0 and " 0 failed" in (r.stdout or ""), label + " " + (tail[-1] if tail else f"exit={r.returncode}"))
