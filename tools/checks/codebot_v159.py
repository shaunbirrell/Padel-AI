# Code Bot Roblox v159 (2026-10-01): ship Claude JOB 41 part C owner-first.
#  C. RivalConfig OwnerFirst=true — TARGETS pill + list; SEND ARMY uses JOB 38 remote (army walks); VIEW = map card (no travel).
# PreferMesh stays OFF. Do not flip RivalConfig.OwnerFirst without owner ask.
# A+B remain OwnerFirst=true (Guided + RecruitPackOffer Id 0) from v158.
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 222'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 222'),
    (S + "Services/DataService.luau", "WE_Build=222"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 222'),
):
    check(needle in read(rel), "CODEBOT v159: WE_Build=222 " + rel.rsplit("/", 1)[-1])

RC = read(C + "RivalConfig.luau")
check("Enabled = true," in RC and "OwnerFirst = false," in RC,
      "CODEBOT v159: RivalConfig Enabled + OwnerFirst=false (v166 flip-all-live)")
check(Path(S + "Services/RivalService.luau").is_file(), "CODEBOT v159: RivalService.luau present")
check(Path(CL + "RivalController.luau").is_file(), "CODEBOT v159: RivalController.luau present")
# SEND ARMY reuses JOB 38 remote; VIEW opens map (no travel)
rvc = read(CL + "RivalController.luau")
check("RequestArmySend" in rvc or "ArmySend" in rvc,
      "CODEBOT v159: RivalController uses army SEND remote")
check("OpenBase" in rvc, "CODEBOT v159: RivalController VIEW = MapController.OpenBase")
check("Teleport" not in rvc and "PivotTo" not in rvc,
      "CODEBOT v159: RivalController has no teleport / PivotTo")

# A+B still owner-first from v158
TC = read(C + "TutorialConfig.luau")
guided = block(TC, "TutorialConfig.Guided") or block(TC, "Guided")
check("Enabled = true," in guided and "OwnerFirst = false," in guided,
      "CODEBOT v159: TutorialConfig.Guided OwnerFirst=false (v166 flip-all-live)")
MC = read(C + "MonetizationConfig.luau")
offer = block(MC, "cfg.RecruitPackOffer") or block(MC, "RecruitPackOffer")
check("Enabled = true," in offer and "OwnerFirst = false," in offer,
      "CODEBOT v159: RecruitPackOffer OwnerFirst=false (v166 flip-all-live)")

# PreferMesh OFF; no WE_Building* in this ship vs v158 tip
svc = read(C + "StructureVisualConfig.luau")
check("PreferMeshWhenAssetIdSet = false" in svc, "CODEBOT v159: PreferMeshWhenAssetIdSet stays false")
base = "9d2e8db"
wd = subprocess.run(["git", "diff", "--name-only", base + "..HEAD"], capture_output=True, text=True).stdout
check(not any("WE_Building" in line for line in wd.splitlines()),
      "CODEBOT v159: no WE_Building* file touched since v158 tip")

r = subprocess.run([sys.executable, "tools/checks/claude_bud_job41.py"], capture_output=True, text=True)
check(r.returncode == 0, "CODEBOT v159: claude_bud_job41.py PASS")
if r.stdout.strip():
    print(r.stdout.strip()[-500:])
if r.returncode != 0 and r.stderr:
    print(r.stderr[-500:])
