# Code Bot Roblox v174 (2026-10-01): ships claude-bud JOB 48 onto phase-7-polish.
# JOB 48 (62e1d1e): first 2 minutes hook — TutorialConfig.Guided.Hook (owner-first, NEW-OWNER-FIRST):
# OrderVersion 5 = v4 + RAID A RIVAL BASE (JOB 38 verdicts / TARGETS outline / real fast-raid bonus) or Clear-hostiles
# fallback + Open Missions; +2 free reward soldiers via SoldierService.GrantFree; FirstMinutes funnel 12-16 +
# SessionMilestone / FtueTimeToFight. PreferMesh OFF, StreamingEnabled OFF; WE_Building* untouched. No price / Id change.
# Hook.OwnerFirst stays true until Shaun's phone test; codebot_v166 skips NEW-OWNER-FIRST lines.
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def code(src):
    src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
    return "\n".join(l.split("--", 1)[0] for l in src.splitlines())


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 178)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 178)'),
    (S + "Services/DataService.luau", "WE_Build=178"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 178)'),
):
    check(needle in read(rel), "CODEBOT v174: WE_Build=178 " + rel.rsplit("/", 1)[-1])

# JOB 48 — Hook owner-first
TC = read(C + "TutorialConfig.luau")
hook = TC.split("\tHook = {")[1].split("\n\t},\n}")[0] if "\tHook = {" in TC else ""
check("Enabled = true," in hook and "OwnerFirst = false," in hook and "OrderVersion = 5," in hook,
      "CODEBOT v174: Guided.Hook Enabled + OwnerFirst (codebot_v175 flipped it to false) + OrderVersion 5")
check('FunnelSteps = { "ArmyGrew", "GoalRaidShown", "RaidSent", "RaidWon", "NextGoal" },' in hook
      and 'FallbackWonName = "GoalFallbackWon"' in hook,
      "CODEBOT v174: Hook FirstMinutes funnel steps 12-16 + FallbackWonName")
check('"Reward", "RaidRival",\n\t\t\t"Barracks", "Jeep", "Missions" },' in TC,
      "CODEBOT v174: SavedOrders[5] = v4 + RaidRival + Missions")
check("function SoldierService.GrantFree" in read(S + "Services/SoldierService.luau"),
      "CODEBOT v174: SoldierService.GrantFree present")
check("NEW-OWNER-FIRST" in read("tools/checks/codebot_v166.py"),
      "CODEBOT v174: codebot_v166 skips NEW-OWNER-FIRST OwnerFirst=true lines")

# standing rules
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v174: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v174: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v174: StreamingEnabled stays OFF")
MC = read(C + "MonetizationConfig.luau")
check('RecruitPack = { Id = 3715776659, DisplayName = "Recruit Pack", RobuxPrice = 49,' in MC,
      "CODEBOT v174: no Recruit Pack price / Id change")

# no WE_Building* diffs vs previous tip (5d1230b / phase-7 pre-JOB48)
prev = os.environ.get("CODEBOT_V174_PREV", "5d1230b")
try:
    r = subprocess.run(
        ["git", "diff", "--name-only", prev, "--", "src"],
        capture_output=True, text=True, cwd=ROOT,
    )
    touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
    check(not touched, "CODEBOT v174: no WE_Building* diffs vs " + prev + ((" " + str(touched)) if touched else ""))
except Exception as e:
    check(False, "CODEBOT v174: WE_Building* diff check errored: " + str(e))

luau = os.environ.get("LUAU")
if luau is None and os.environ.get("LUAU_COMPILE"):
    cand = os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    luau = cand if os.path.isfile(cand) else None
if luau is None and Path("/home/box/.local/bin/luau").is_file():
    luau = "/home/box/.local/bin/luau"
if luau:
    r = subprocess.run([sys.executable, "tools/sim/run_first_minutes_test.py"],
                       capture_output=True, text=True, env=dict(os.environ, LUAU=luau))
    check(r.returncode == 0 and "FIRST MINUTES TEST: 0 failed" in r.stdout,
          "CODEBOT v174: run_first_minutes_test.py 0 failed")
else:
    print("SKIP CODEBOT v174: Luau CLI tests (set LUAU)")
