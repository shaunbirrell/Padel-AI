# Code Bot Roblox v179 (2026-10-01): cherry-pick claude-bud JOB 49 D (return sequence) + JOB A (recruitment office P0).
# RetentionConfig.ReturnSequence.OwnerFirst stays true (NEW-OWNER-FIRST). MissionConfig.Core.OwnerFirst stays true.
# Untouched: CapBoost Enabled=false; OfflineCap2x / MissionReroll Id 0; prices / product Ids.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes.
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


def block(src, name):
    m = re.search(r"\b" + name + r" = \{(.*?)\n\t\},", src, re.S)
    return m.group(1) if m else ""


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 179)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 179)'),
    (S + "Services/DataService.luau", "WE_Build=179"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 179)'),
):
    check(needle in read(rel), "CODEBOT v179: WE_Build=179 " + rel.rsplit("/", 1)[-1])

# JOB 49 D: ReturnSequence owner-first
RCF = read(C + "RetentionConfig.luau")
rsq = block(RCF, "ReturnSequence")
check("Enabled = true," in rsq and "OwnerFirst = true, -- NEW-OWNER-FIRST" in rsq,
      "CODEBOT v179: RetentionConfig.ReturnSequence Enabled + OwnerFirst=true (NEW-OWNER-FIRST)")

RCC = read("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RetentionController.luau")
check("enqueueCard(1," in RCC and "enqueueCard(2," in RCC and "enqueueCard(3," in RCC,
      "CODEBOT v179: RetentionController one card queue (Welcome back / streak / missions toast)")

# JOB A: Recruitment Office open/close API + RecruitCloseRange
EC = read("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/EndgameController.luau")
check("function EndgameController.OpenRecruitmentOffice" in EC and "function EndgameController.CloseRecruitmentOffice" in EC,
      "CODEBOT v179: OpenRecruitmentOffice / CloseRecruitmentOffice present")
EGC = read(C + "EndgameConfig.luau")
check("RecruitCloseRange = 17," in EGC, "CODEBOT v179: EndgameConfig.Station.RecruitCloseRange=17")

# MissionConfig.Core still owner-first from JOB 49 C
MCF = read(C + "MissionConfig.luau")
core = MCF.split("\tCore = {")[1].split("\n\t},\n\n")[0] if "\tCore = {" in MCF else ""
check("Enabled = true," in core and "OwnerFirst = true, -- NEW-OWNER-FIRST" in core,
      "CODEBOT v179: MissionConfig.Core still OwnerFirst=true (NEW-OWNER-FIRST)")

MON = read(C + "MonetizationConfig.luau")
for key in ("OfflineCap2x", "MissionReroll"):
    m = re.search(r"\n\t\t" + key + r" = \{([^\n]*)\}", MON)
    row = m.group(1) if m else ""
    check(row.strip().startswith("Id = 0,") and "RobuxPrice" not in row and "HideFromShop = true" in row,
          "CODEBOT v179: DevProducts.%s still Id 0, no RobuxPrice, HideFromShop" % key)

Eco = read(C + "EconomyConfig.luau")
m = re.search(r"\n\t\tCapBoost = \{(.*?)\n\t\t\},", Eco, re.S)
cb = m.group(1) if m else ""
check("Enabled = false," in cb and 'ProductKey = "OfflineCap2x"' in cb,
      "CODEBOT v179: CapBoost stays Enabled=false (untouched)")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v179: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v179: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v179: StreamingEnabled stays OFF")

# v179 touches no price / Id lines and no WE_Building* files vs the v178 live tip
prev = os.environ.get("CODEBOT_V179_PREV", "c8db098")
try:
    r = subprocess.run(["git", "diff", "--name-only", prev, "--", "src"], capture_output=True, text=True, cwd=ROOT)
    touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
    check(r.returncode == 0 and not touched, "CODEBOT v179: no WE_Building* diffs vs " + prev + ((" " + str(touched)) if touched else ""))
    r = subprocess.run(["git", "diff", "-U0", prev, "--", C + "MonetizationConfig.luau"], capture_output=True, text=True, cwd=ROOT)
    changed = [l for l in (r.stdout or "").splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
    check(r.returncode == 0 and not changed, "CODEBOT v179: MonetizationConfig unchanged vs " + prev + " (prices / product Ids)" + ((" " + str(changed[:6])) if changed else ""))
except Exception as e:
    check(False, "CODEBOT v179: git diff check errored: " + str(e))
