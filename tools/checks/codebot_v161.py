# Code Bot Roblox v161 (2026-10-01): ship Claude JOB 42 parts A+B owner-first.
#  A. ShopOverhaulConfig.TimePacks Enabled+OwnerFirst=true; MonetizationConfig Cash15m..Cash4h Id=0
#     prices 25/49/89/159/279; server grant max(Floor, Minutes x income) at receipt.
#  B. Shop + offers UI for time packs (only while TimePacksLiveFor + all five Ids).
# PreferMesh stays OFF. Do NOT require TimePacksReady / live shop swap (Ids are 0).
# Leave Guided / RecruitPackOffer / RivalConfig / RatePromptConfig OwnerFirst=true. No Creator Hub products.
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def check(cond, label):
    print(("PASS " if cond else "FAIL ") + label)
    if not cond:
        raise SystemExit(1)


def block(text, key):
    m = re.search(r"(?m)^\s*" + re.escape(key) + r"\s*=\s*\{", text)
    if not m:
        return ""
    depth = 0
    for i in range(m.end() - 1, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[m.end():i]
    return ""


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/"

for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 199)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 199)'),
    (S + "Services/DataService.luau", "WE_Build=199"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 199)'),
):
    check(needle in read(rel), "CODEBOT v161: WE_Build=199 " + rel.rsplit("/", 1)[-1])

SOC = read(C + "ShopOverhaulConfig.luau")
tp = block(SOC, "TimePacks") or block(SOC, "ShopOverhaulConfig.TimePacks")
check("Enabled = true," in tp and "OwnerFirst = false," in tp,
      "CODEBOT v161: ShopOverhaulConfig.TimePacks Enabled + OwnerFirst=false (v166 flip-all-live)")
check('BestValueKey = "Cash4h"' in tp or "BestValueKey = \"Cash4h\"" in tp,
      "CODEBOT v161: TimePacks BestValueKey Cash4h")

MC = read(C + "MonetizationConfig.luau")
want = {
    "Cash15m": 25,
    "Cash30m": 49,
    "Cash1h": 89,
    "Cash2h": 159,
    "Cash4h": 279,
}
for key, price in want.items():
    m = re.search(r"\b" + key + r" = \{ (.*?) \},", MC)
    row = m.group(1) if m else ""
    # codebot_v167: Id=0 retired (Creator Hub Ids set; exact Ids pinned in codebot_v167.py)
    check(re.search(r"\bId = [1-9]\d*,", row) is not None and ("RobuxPrice = %d," % price) in row,
          f"CODEBOT v161: {key} Id set (codebot_v167) RobuxPrice={price}")

# PreferMesh OFF
svc = read(C + "StructureVisualConfig.luau")
check("PreferMeshWhenAssetIdSet = false" in svc, "CODEBOT v161: PreferMeshWhenAssetIdSet stays false")

# Prior OwnerFirst flags still true (do not flip)
TC = read(C + "TutorialConfig.luau")
guided = block(TC, "TutorialConfig.Guided") or block(TC, "Guided")
check("Enabled = true," in guided and "OwnerFirst = false," in guided,
      "CODEBOT v161: TutorialConfig.Guided OwnerFirst=false (v166 flip-all-live)")
offer = block(MC, "cfg.RecruitPackOffer") or block(MC, "RecruitPackOffer")
check("Enabled = true," in offer and "OwnerFirst = false," in offer,
      "CODEBOT v161: RecruitPackOffer OwnerFirst=false (v166 flip-all-live)")
check(re.search(r"RecruitPack = \{ Id = 3715776659,", MC) is not None,
      "CODEBOT v161: RecruitPack Id = 3715776659 (codebot_v167 Creator Hub; was 0)")
RC = read(C + "RivalConfig.luau")
check("Enabled = true," in RC and "OwnerFirst = false," in RC,
      "CODEBOT v161: RivalConfig OwnerFirst=false (v166 flip-all-live)")
RPC = read(C + "RatePromptConfig.luau")
check("Enabled = true," in RPC and "OwnerFirst = false," in RPC,
      "CODEBOT v161: RatePromptConfig OwnerFirst=false (v166 flip-all-live)")

# no WE_Building* since v160 tip (d024178 / 37b94b0 era)
base = "d024178"
wd = subprocess.run(["git", "diff", "--name-only", base + "..HEAD"], capture_output=True, text=True).stdout
wd2 = subprocess.run(["git", "diff", "--name-only", base], capture_output=True, text=True).stdout
names = set(wd.splitlines()) | set(wd2.splitlines())
check(not any("WE_Building" in line for line in names),
      "CODEBOT v161: no WE_Building* file touched since v160 tip")

# Do NOT require TimePacksReady / live shop swap — Ids are 0 by design this ship.
# Just confirm helpers exist and ShopController has time-pack UI path (part B).
check("function ShopOverhaulConfig.TimePacksReady()" in SOC,
      "CODEBOT v161: TimePacksReady helper present (not required true)")
check("function ShopOverhaulConfig.TimePacksShown" in SOC,
      "CODEBOT v161: TimePacksShown helper present")
SC = read(CL + "ShopController.luau")
check("TimePacks" in SC or "TimePack" in SC,
      "CODEBOT v161: ShopController has time-pack UI path (part B)")

r = subprocess.run([sys.executable, "tools/checks/claude_bud_job42.py"], capture_output=True, text=True)
check(r.returncode == 0, "CODEBOT v161: claude_bud_job42.py PASS")
if r.stdout.strip():
    print(r.stdout.strip()[-800:])
if r.returncode != 0 and r.stderr:
    print(r.stderr[-500:])
