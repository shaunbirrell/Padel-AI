# Code Bot Roblox v158 (2026-10-01): ship Claude JOB 41 A+B owner-first.
#  A. TutorialConfig.Guided OwnerFirst=true (OrderVersion 4 guided first minutes + GuidedService).
#  B. MonetizationConfig.RecruitPackOffer OwnerFirst=true; DevProducts.RecruitPack Id=0 (no Creator Hub yet).
# PreferMesh stays OFF. Do not flip OwnerFirst without owner ask.
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 217'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 217'),
    (S + "Services/DataService.luau", "WE_Build=217"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 217'),
):
    check(needle in read(rel), "CODEBOT v158: WE_Build=217 " + rel.rsplit("/", 1)[-1])

TC = read(C + "TutorialConfig.luau")
guided = block(TC, "TutorialConfig.Guided") or block(TC, "Guided")
check("Enabled = true," in guided and "OwnerFirst = false," in guided,
      "CODEBOT v158: TutorialConfig.Guided Enabled + OwnerFirst=false (v166 flip-all-live)")
check(Path(S + "Services/GuidedService.luau").is_file(), "CODEBOT v158: GuidedService.luau present")

MC = read(C + "MonetizationConfig.luau")
offer = block(MC, "cfg.RecruitPackOffer") or block(MC, "RecruitPackOffer")
check("Enabled = true," in offer and "OwnerFirst = false," in offer,
      "CODEBOT v158: RecruitPackOffer Enabled + OwnerFirst=false (v166 flip-all-live)")
rp = block(MC, "DevProducts")
# RecruitPack row Id must stay 0 until Creator Hub product exists
m = re.search(r"RecruitPack\s*=\s*\{[^}]*Id\s*=\s*(\d+)", rp, re.S)
# codebot_v167: retired "stays 0" (the Creator Hub product exists now); superseded by codebot_v167.py
check(m is not None and m.group(1) == "3715776659", "CODEBOT v158: DevProducts.RecruitPack.Id = 3715776659 (codebot_v167 Creator Hub)")
check(Path(S + "Services/RecruitPackService.luau").is_file(), "CODEBOT v158: RecruitPackService.luau present")
check(Path(CL + "RecruitPackController.luau").is_file(), "CODEBOT v158: RecruitPackController.luau present")

# PreferMesh OFF
svc = read(C + "StructureVisualConfig.luau")
check("PreferMeshWhenAssetIdSet = false" in svc, "CODEBOT v158: PreferMeshWhenAssetIdSet stays false")

# claude_bud_job41 pins
r = subprocess.run([sys.executable, "tools/checks/claude_bud_job41.py"], capture_output=True, text=True)
check(r.returncode == 0, "CODEBOT v158: claude_bud_job41.py PASS")
if r.stdout.strip():
    print(r.stdout.strip()[-500:])
if r.returncode != 0 and r.stderr:
    print(r.stderr[-500:])
