# Code Bot Roblox v176 (2026-10-01): claude-bud JOB 49 A+B owner-first (daily streak grace + welcome-back collect card).
# Cherry-pick d4672cd (A) + febd2a8 (B) onto phase-7-polish. PreferMesh OFF; StreamingEnabled OFF; no WE_Building* /
# price / Id changes. OfflineCap2x / MissionReroll stay Id 0 + disabled. NEW-OWNER-FIRST flags stay true until phone OK.
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def shipped_v180(rel, rev):
    # Code Bot v180: the file as this version shipped it (its snapshot checks of CapBoost / OfflineCap2x / MissionReroll
    # moved on in v180: both items wired + live; the current state is pinned in tools/checks/codebot_v180.py)
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else ""


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


def block(src, name):
    m = re.search(r"\b" + name + r" = \{(.*?)\n\t\},", src, re.S)
    return m.group(1) if m else ""


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 202)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 202)'),
    (S + "Services/DataService.luau", "WE_Build=202"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 202)'),
):
    check(needle in read(rel), "CODEBOT v176: WE_Build=202 " + rel.rsplit("/", 1)[-1])

# JOB 49 A — DailyRewardConfig Grace / Day7Scale / Calendar owner-first
DR = read(C + "DailyRewardConfig.luau")
for name in ("Grace", "Day7Scale", "Calendar"):
    blk = block(DR, name)
    check("Enabled = true," in blk and "OwnerFirst = false," in blk,
          "CODEBOT v176: DailyRewardConfig.%s Enabled (OwnerFirst=false since codebot_v177 flip)" % name)
check("MissedDaysAllowed = 1," in block(DR, "Grace") and "PerCycle = 1," in block(DR, "Grace"),
      "CODEBOT v176: Grace = 1 missed day per 7-day cycle")

# JOB 49 B — OfflineEarnings.Card owner-first; CapBoost disabled; Id 0 products
EC = read(C + "EconomyConfig.luau")
card = block(EC, "Card")
check("Enabled = true," in card and "OwnerFirst = false," in card,
      "CODEBOT v176: OfflineEarnings.Card Enabled (OwnerFirst=false since codebot_v177 flip)")
cb = block(shipped_v180(C + "EconomyConfig.luau", "574b455"), "CapBoost")  # Code Bot v180: as shipped
check("Enabled = false," in cb and "OwnerFirst = true," in cb and 'ProductKey = "OfflineCap2x"' in cb,
      "CODEBOT v176: CapBoost Enabled=false (sidegrade hook off) + OwnerFirst=true")
# CapSeconds stays 8h
oe = EC.split("OfflineEarnings = {")[1].split("\n\t},")[0] if "OfflineEarnings = {" in EC else ""
# Code Bot (Shaun 2026-10-01, offline cap): retired, superseded in tools/checks/codebot_v201.py (OfflineConfig MaxSeconds 7200 / Rate 0.10): #check("CapSeconds = 8 * 3600" in oe ..., "CODEBOT v176: OfflineEarnings CapSeconds = 8 h")

MC = shipped_v180(C + "MonetizationConfig.luau", "574b455")  # Code Bot v180: as shipped
for key in ("OfflineCap2x", "MissionReroll"):
    m = re.search(r"\n\t\t" + key + r" = \{([^\n]*)\}", MC)
    row = m.group(1) if m else ""
    check(row.strip().startswith("Id = 0,") and "RobuxPrice" not in row and "HideFromShop = true" in row,
          "CODEBOT v176: DevProducts.%s Id 0, no RobuxPrice, HideFromShop" % key)

# Hook stays false (v175 Shaun-approved) — do not regress
TC = read(C + "TutorialConfig.luau")
hook = TC.split("\tHook = {")[1].split("\n\t},\n}")[0] if "\tHook = {" in TC else ""
check("OwnerFirst = false," in hook and "OwnerFirst = true" not in code(hook) and "Enabled = true," in hook,
      "CODEBOT v176: Guided.Hook still OwnerFirst=false (v175 live for everyone)")

# standing rules
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v176: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v176: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v176: StreamingEnabled stays OFF")
check('RecruitPack = { Id = 3715776659, DisplayName = "Recruit Pack", RobuxPrice = 49,' in MC,
      "CODEBOT v176: no Recruit Pack price / Id change")

prev = os.environ.get("CODEBOT_V176_PREV", "f1e5707")
try:
    r = subprocess.run(["git", "diff", "--name-only", prev, "--", "src"], capture_output=True, text=True, cwd=ROOT)
    touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
    check(not touched, "CODEBOT v176: no WE_Building* diffs vs " + prev + ((" " + str(touched)) if touched else ""))
except Exception as e:
    check(False, "CODEBOT v176: WE_Building* diff check errored: " + str(e))

luau = os.environ.get("LUAU")
if luau is None and os.environ.get("LUAU_COMPILE"):
    cand = os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    luau = cand if os.path.isfile(cand) else None
if luau is None and Path("/home/box/.local/bin/luau").is_file():
    luau = "/home/box/.local/bin/luau"
if luau:
    for script, needle in (("tools/sim/run_daily_return_test.py", "DAILY RETURN TEST: 0 failed"),
                           ):
        r = subprocess.run([sys.executable, script], capture_output=True, text=True, env=dict(os.environ, LUAU=luau))
        check(r.returncode == 0 and needle in (r.stdout or ""),
              "CODEBOT v176: " + script.rsplit("/", 1)[-1] + " 0 failed")
else:
    print("SKIP CODEBOT v176: Luau CLI tests (set LUAU)")
