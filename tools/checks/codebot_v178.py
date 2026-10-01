# Code Bot Roblox v178 (2026-10-01): cherry-pick claude-bud JOB 49 C (3 core daily missions + free reroll) owner-first.
# MissionConfig.Core.OwnerFirst stays true (NEW-OWNER-FIRST). MissionReroll Id 0 / Robux Enabled=false.
# Untouched: CapBoost Enabled=false; OfflineCap2x Id 0; prices / product Ids; Grace/Day7Scale/Calendar/Card OwnerFirst=false.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes.
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
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 208)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 208)'),
    (S + "Services/DataService.luau", "WE_Build=208"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 208)'),
):
    check(needle in read(rel), "CODEBOT v178: WE_Build=208 " + rel.rsplit("/", 1)[-1])

# JOB 49 C: Core missions owner-first; free reroll; Robux reroll disabled
MCF = shipped_v180(C + "MissionConfig.luau", "c978f41")  # Code Bot v180: as shipped (Robux reroll live since v180)
core = MCF.split("\tCore = {")[1].split("\n\t},\n\n")[0] if "\tCore = {" in MCF else ""
check("Enabled = true," in core and "OwnerFirst = true, -- NEW-OWNER-FIRST" in core and "Count = 3," in core,
      "CODEBOT v178: MissionConfig.Core Enabled + OwnerFirst=true (NEW-OWNER-FIRST) Count=3")
check("Robux = { Enabled = false, OwnerFirst = true, ProductKey = \"MissionReroll\" }" in core and "FreePerDay = 1," in core,
      "CODEBOT v178: Core.Reroll FreePerDay=1 + Robux Enabled=false")
check("Raid = true," in MCF.split("LiveObjectives = {")[1].split("}")[0], "CODEBOT v178: Raid is a live ObjectiveType")

AP = read(S + "Modules/ArmyPlan.luau")
MCS = read(S + "Services/MoneyCollectorService.luau")
check('TrackProgress(player, "Raid", 1)' in AP and 'TrackProgress(thief, "Raid", 1)' in MCS,
      "CODEBOT v178: Raid progress from ArmyPlan SEND loot + MoneyCollector ATM raid")

MON = shipped_v180(C + "MonetizationConfig.luau", "c978f41")  # Code Bot v180: as shipped
for key in ("OfflineCap2x", "MissionReroll"):
    m = re.search(r"\n\t\t" + key + r" = \{([^\n]*)\}", MON)
    row = m.group(1) if m else ""
    check(row.strip().startswith("Id = 0,") and "RobuxPrice" not in row and "HideFromShop = true" in row,
          "CODEBOT v178: DevProducts.%s still Id 0, no RobuxPrice, HideFromShop" % key)
check('RecruitPack = { Id = 3715776659, DisplayName = "Recruit Pack", RobuxPrice = 49,' in MON,
      "CODEBOT v178: no Recruit Pack price / Id change")

# JOB 49 A+B stay live for everyone (v177 flip); CapBoost stays disabled
DR = read(C + "DailyRewardConfig.luau")
for name in ("Grace", "Day7Scale", "Calendar"):
    blk = block(DR, name)
    check("Enabled = true," in blk and "OwnerFirst = false," in blk and "OwnerFirst = true" not in code(blk),
          "CODEBOT v178: DailyRewardConfig.%s still everyone (OwnerFirst=false)" % name)
EC = read(C + "EconomyConfig.luau")
m = re.search(r"\n\t\tCard = \{(.*?)\n\t\t\},", EC, re.S)
card = m.group(1) if m else ""
check("Enabled = true," in card and "OwnerFirst = false," in card and "OwnerFirst = true" not in code(card),
      "CODEBOT v178: OfflineEarnings.Card still everyone (OwnerFirst=false)")
m = re.search(r"\n\t\tCapBoost = \{(.*?)\n\t\t\},", shipped_v180(C + "EconomyConfig.luau", "c978f41"), re.S)  # Code Bot v180: as shipped
cb = m.group(1) if m else ""
check("Enabled = false," in cb and 'ProductKey = "OfflineCap2x"' in cb,
      "CODEBOT v178: CapBoost stays Enabled=false (untouched)")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v178: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v178: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v178: StreamingEnabled stays OFF")

# v178 touches no price / Id lines and no WE_Building* files vs the v177 live tip
prev = os.environ.get("CODEBOT_V178_PREV", "de2bc56")
try:
    r = subprocess.run(["git", "diff", "--name-only", prev, "--", "src"], capture_output=True, text=True, cwd=ROOT)
    touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
    check(r.returncode == 0 and not touched, "CODEBOT v178: no WE_Building* diffs vs " + prev + ((" " + str(touched)) if touched else ""))
    r = subprocess.run(["git", "diff", "-U0", prev, "c978f41", "--", C + "MonetizationConfig.luau"], capture_output=True, text=True, cwd=ROOT)
    # MonetizationConfig should be unchanged (MissionReroll Id 0 already on phase-7 from JOB 49 B)
    changed = [l for l in (r.stdout or "").splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
    check(r.returncode == 0 and not changed, "CODEBOT v178: MonetizationConfig unchanged vs " + prev + " (prices / product Ids)" + ((" " + str(changed[:6])) if changed else ""))
except Exception as e:
    check(False, "CODEBOT v178: git diff check errored: " + str(e))
