# Code Bot Roblox v203 (2026-10-01, Shaun approved): the "2x Offline Cash" game pass DESCRIPTION only.
# Rule since v201 (OfflineConfig): free players earn up to 2 h of away cash at 10 % of income; pass owners 4 h
# (OfflineConfig.PassCapMult = 2). Old text "Offline cash builds for 16 h instead of 8 h" was stale.
# Price (149 R$), DisplayName and Id unchanged. PreferMesh OFF; StreamingEnabled OFF; no WE_Building* diffs.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V203_PREV", "f14a4db")  # v202 code tip (place 200)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
NEW_DESC = "Offline cash for 4 hours instead of 2 hours"  # in-game (phone row budget); Creator Hub carries the long sentence
OLD_DESC = "Offline cash builds for 16 h instead of 8 h"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def pass_block(t):
    m = re.search(r"\n\t\tOfflineCap2x = \{\n(.*?)\n\t\t\},", t or "", re.S)
    return m.group(1) if m else ""


BUD = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()  # claude/desktop-bud: ship-only pins skip

for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 222'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 222'),
    (S + "Services/DataService.luau", "WE_Build=222"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 222'),
):
    check(BUD or needle in read(rel), "CODEBOT v203: WE_Build=222 " + rel.rsplit("/", 1)[-1] + (" [bud: skipped]" if BUD else ""))

MON = read(C + "MonetizationConfig.luau")
blk = pass_block(MON)
check(blk != "", "CODEBOT v203: GamePasses.OfflineCap2x block present")
check("\t\t\tId = 2002664894," in blk, "CODEBOT v203: OfflineCap2x Id 2002664894 unchanged")
check('\t\t\tDisplayName = "2x Offline Cash",' in blk, "CODEBOT v203: OfflineCap2x name '2x Offline Cash' unchanged")
check("\t\t\tRobuxPrice = 149," in blk and len(re.findall(r"RobuxPrice\s*=", blk)) == 1, "CODEBOT v203: OfflineCap2x price 149 R$ unchanged")
check('\t\t\tDescription = "' + NEW_DESC + '",' in blk and len(NEW_DESC) <= 44,
      "CODEBOT v203: OfflineCap2x Description = new 4 h / 2 h text")
check(OLD_DESC not in MON and "16 h" not in blk and "8 h" not in blk, "CODEBOT v203: old 16 h / 8 h description gone")

# The rule the text describes (OfflineConfig unchanged): 2 h x 10 %, pass doubles the time.
OFC = read(C + "OfflineConfig.luau")
check(re.search(r"MaxSeconds\s*=\s*7200\b", OFC) is not None, "CODEBOT v203: OfflineConfig.MaxSeconds 7200 (2 h)")
check(re.search(r"Rate\s*=\s*0\.10?\b", OFC) is not None, "CODEBOT v203: OfflineConfig.Rate 0.10")
check(re.search(r"PassCapMult\s*=\s*2\b", OFC) is not None, "CODEBOT v203: OfflineConfig.PassCapMult stays 2 (4 h)")

# Money guard: vs v202 the ONLY MonetizationConfig changes are that Description line and its comment line.
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v204: the diff / scope pins below are v203's own ship scope (v204 fills the Starter5 Ids + the 60 s test
# delay); the newest codebot_vNNN.py carries the live money guard. The pass text / price pins above stay live.
_v203_own = 'SetAttribute("WE_Build", 203)' in read(S + "Services/DataService.luau")
if not BUD and _v203_own:
    pb = pass_block(prev_mon)
    check("\t\t\tRobuxPrice = 149," in pb and '\t\t\tDisplayName = "2x Offline Cash",' in pb and "\t\t\tId = 2002664894," in pb,
          "CODEBOT v203: v202 had the same Id / name / 149 R$")
    a = (prev_mon or "").split("\n")
    b = MON.split("\n")
    diff = [(x, y) for x, y in zip(a, b) if x != y]
    check(prev_mon is not None and len(a) == len(b) and len(diff) == 2
          and all(("Description = " in x and "Description = " in y) or ("8 h -> 16 h" in x and "2 h -> 4 h" in y) for x, y in diff),
          "CODEBOT v203: MonetizationConfig vs " + PREV + ": only the OfflineCap2x Description (+ its comment) changed")
    for rel in (C + "OfflineConfig.luau", C + "EconomyConfig.luau", S + "Services/MonetizationService.luau"):
        check(shipped(rel, PREV) == read(rel), "CODEBOT v203: " + rel.rsplit("/", 1)[-1] + " byte-identical to " + PREV)
    _pds = shipped(S + "Services/DataService.luau", PREV) or ""
    check(_pds.replace('WE_Build", 202)', 'WE_Build", 203)').replace("WE_Build=202", "WE_Build=203") == read(S + "Services/DataService.luau"),
          "CODEBOT v203: DataService: only the WE_Build number changed (save keys kept)")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v203: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v203: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v203: StreamingEnabled stays OFF")
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
check(r.returncode == 0 and not [n for n in (r.stdout or "").splitlines() if "WE_Building" in n], "CODEBOT v203: no WE_Building* diffs vs " + PREV)
