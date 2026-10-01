# Code Bot Roblox v160 (2026-10-01): ship Claude JOB 41 part D owner-first.
#  D. RatePromptConfig OwnerFirst=true — FirstCapture / RaidWin one-time triggers on the EXISTING
#     RatePromptService (JOB 40 D system); no second rate system; no reward. Recruit Pack card goes first.
# PreferMesh stays OFF. Do not flip RatePromptConfig.OwnerFirst / Guided / RecruitPack / Rival without owner ask.
# A+B+C remain OwnerFirst=true from v158/v159. RecruitPack Id stays 0.
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 190)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 190)'),
    (S + "Services/DataService.luau", "WE_Build=190"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 190)'),
):
    check(needle in read(rel), "CODEBOT v160: WE_Build=190 " + rel.rsplit("/", 1)[-1])

RPC = read(C + "RatePromptConfig.luau")
check("Enabled = true," in RPC and "OwnerFirst = false," in RPC,
      "CODEBOT v160: RatePromptConfig Enabled + OwnerFirst=false (v166 flip-all-live)")
check("FirstCapture = true" in RPC and "RaidWin = true" in RPC,
      "CODEBOT v160: RatePromptConfig FirstCapture + RaidWin triggers")
check("OneTimeTriggers = { FirstCapture = true, RaidWin = true }," in RPC,
      "CODEBOT v160: OneTimeTriggers FirstCapture + RaidWin")
# Same card copy as JOB 40 D (Title lives only in RatePromptConfig; comments elsewhere stripped by claude_bud_job41)
check('Title = "Enjoying WAR EMPIRE?"' in RPC,
      "CODEBOT v160: RatePromptConfig Title Enjoying WAR EMPIRE?")

# A+B+C still owner-first
TC = read(C + "TutorialConfig.luau")
guided = block(TC, "TutorialConfig.Guided") or block(TC, "Guided")
check("Enabled = true," in guided and "OwnerFirst = false," in guided,
      "CODEBOT v160: TutorialConfig.Guided OwnerFirst=false (v166 flip-all-live)")
MC = read(C + "MonetizationConfig.luau")
offer = block(MC, "cfg.RecruitPackOffer") or block(MC, "RecruitPackOffer")
check("Enabled = true," in offer and "OwnerFirst = false," in offer,
      "CODEBOT v160: RecruitPackOffer OwnerFirst=false (v166 flip-all-live)")
check("RecruitPack = { Id = 3715776659," in MC,
      "CODEBOT v160: RecruitPack Id = 3715776659 (codebot_v167 Creator Hub; was 0)")
RC = read(C + "RivalConfig.luau")
check("Enabled = true," in RC and "OwnerFirst = false," in RC,
      "CODEBOT v160: RivalConfig OwnerFirst=false (v166 flip-all-live)")

# PreferMesh OFF; no WE_Building* since v159 tip
svc = read(C + "StructureVisualConfig.luau")
check("PreferMeshWhenAssetIdSet = false" in svc, "CODEBOT v160: PreferMeshWhenAssetIdSet stays false")
base = "70057f8"
wd = subprocess.run(["git", "diff", "--name-only", base + "..HEAD"], capture_output=True, text=True).stdout
# also include working tree
wd2 = subprocess.run(["git", "diff", "--name-only", base], capture_output=True, text=True).stdout
names = set(wd.splitlines()) | set(wd2.splitlines())
check(not any("WE_Building" in line for line in names),
      "CODEBOT v160: no WE_Building* file touched since v159 tip")

r = subprocess.run([sys.executable, "tools/checks/claude_bud_job41.py"], capture_output=True, text=True)
check(r.returncode == 0, "CODEBOT v160: claude_bud_job41.py PASS")
if r.stdout.strip():
    print(r.stdout.strip()[-500:])
if r.returncode != 0 and r.stderr:
    print(r.stderr[-500:])
