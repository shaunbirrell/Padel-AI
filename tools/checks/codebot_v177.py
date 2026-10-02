# Code Bot Roblox v177 (2026-10-01): flip claude-bud JOB 49 A+B from owner-first to everyone (Shaun approved).
# DailyRewardConfig.Grace / Day7Scale / Calendar + EconomyConfig.OfflineEarnings.Card OwnerFirst true -> false.
# Untouched: CapBoost Enabled=false; OfflineCap2x / MissionReroll Id 0; prices / Ids; TutorialConfig Hook OwnerFirst=false.
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 220'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 220'),
    (S + "Services/DataService.luau", "WE_Build=220"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 220'),
):
    check(needle in read(rel), "CODEBOT v177: WE_Build=220 " + rel.rsplit("/", 1)[-1])

# JOB 49 A flipped: DailyRewardConfig Grace / Day7Scale / Calendar live for everyone
DR = read(C + "DailyRewardConfig.luau")
for name in ("Grace", "Day7Scale", "Calendar"):
    blk = block(DR, name)
    check("Enabled = true," in blk and "OwnerFirst = false," in blk and "OwnerFirst = true" not in code(blk),
          "CODEBOT v177: DailyRewardConfig.%s Enabled + OwnerFirst=false (everyone)" % name)

# JOB 49 B flipped: OfflineEarnings.Card live for everyone; CapBoost stays disabled
EC = read(C + "EconomyConfig.luau")
m = re.search(r"\n\t\tCard = \{(.*?)\n\t\t\},", EC, re.S)
card = m.group(1) if m else ""
check("Enabled = true," in card and "OwnerFirst = false," in card and "OwnerFirst = true" not in code(card),
      "CODEBOT v177: OfflineEarnings.Card Enabled + OwnerFirst=false (everyone)")
m = re.search(r"\n\t\tCapBoost = \{(.*?)\n\t\t\},", shipped_v180(C + "EconomyConfig.luau", "2ed90ae"), re.S)  # Code Bot v180: as shipped
cb = m.group(1) if m else ""
check("Enabled = false," in cb and 'ProductKey = "OfflineCap2x"' in cb,
      "CODEBOT v177: CapBoost stays Enabled=false (untouched)")

MC = shipped_v180(C + "MonetizationConfig.luau", "2ed90ae")  # Code Bot v180: as shipped
for key in ("OfflineCap2x", "MissionReroll"):
    m = re.search(r"\n\t\t" + key + r" = \{([^\n]*)\}", MC)
    row = m.group(1) if m else ""
    check(row.strip().startswith("Id = 0,") and "RobuxPrice" not in row and "HideFromShop = true" in row,
          "CODEBOT v177: DevProducts.%s still Id 0, no RobuxPrice, HideFromShop" % key)
check('RecruitPack = { Id = 3715776659, DisplayName = "Recruit Pack", RobuxPrice = 49,' in MC,
      "CODEBOT v177: no Recruit Pack price / Id change")

TC = read(C + "TutorialConfig.luau")
hook = TC.split("\tHook = {")[1].split("\n\t},\n}")[0] if "\tHook = {" in TC else ""
check("OwnerFirst = false," in hook and "OwnerFirst = true" not in code(hook) and "Enabled = true," in hook,
      "CODEBOT v177: Guided.Hook still OwnerFirst=false")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v177: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v177: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v177: StreamingEnabled stays OFF")

# v177 touches no price / Id lines and no WE_Building* files vs the v176 live tip
prev = os.environ.get("CODEBOT_V177_PREV", "008c529")
try:
    r = subprocess.run(["git", "diff", "--name-only", prev, "--", "src"], capture_output=True, text=True, cwd=ROOT)
    touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
    check(r.returncode == 0 and not touched, "CODEBOT v177: no WE_Building* diffs vs " + prev + ((" " + str(touched)) if touched else ""))
    r = subprocess.run(["git", "diff", "-U0", prev, "2ed90ae", "--", C + "MonetizationConfig.luau"], capture_output=True, text=True, cwd=ROOT)
    check(r.returncode == 0 and not [l for l in (r.stdout or "").splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))],
          "CODEBOT v177: MonetizationConfig unchanged vs " + prev + " (prices / product Ids)")
except Exception as e:
    check(False, "CODEBOT v177: git diff check errored: " + str(e))
