# Code Bot Roblox v191 (2026-10-01): cherry-pick claude-bud JOB 58 HangarDock + JOB 59 Pass59 sounds OwnerFirst (+ JOB 60 audit docs/checks).
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V191_PREV", "8397dc7")  # v190 code tip (place 188)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"


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


def code(src):
    src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
    return "\n".join(l.split("--", 1)[0] for l in src.splitlines())


def skus(src):
    out = {}
    for m in re.finditer(r"\n\t\t(\w+) = \{(.*?)(?:\},|\n\t\t\},)", src, re.S):
        body = code(m.group(2))
        i = re.search(r"\bId = (\d+)", body)
        p = re.search(r"\bRobuxPrice = (\d+)", body)
        if i:
            out[m.group(1)] = (int(i.group(1)), int(p.group(1)) if p else None)
    return out


for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 192)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 192)'),
    (S + "Services/DataService.luau", "WE_Build=192"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 192)'),
):
    check(needle in read(rel), "CODEBOT v191: WE_Build=192 " + rel.rsplit("/", 1)[-1])

HC = read(C + "HangarDockConfig.luau")
check("Enabled = true," in HC and "OwnerFirst = true," in HC,
      "CODEBOT v191: HangarDockConfig Enabled + OwnerFirst=true")
check(Path(S + "Services/HangarDockDisplayService.luau").is_file(),
      "CODEBOT v191: HangarDockDisplayService.luau present")
HDS = read(S + "Services/HangarDockDisplayService.luau")
check("function HangarDockDisplayService.Init" in HDS or "HangarDockDisplayService.Init" in HDS,
      "CODEBOT v191: HangarDockDisplayService.Init present")
VAS = read(S + "Services/VisualAssetService.luau")
check("function VisualAssetService.CloneDisplayBody" in VAS,
      "CODEBOT v191: VisualAssetService.CloneDisplayBody present")

SC = read(C + "SoundConfig.luau")
p59 = SC.split("SoundConfig.Pass59 = {")[1].split("\n}\n")[0] if "SoundConfig.Pass59 = {" in SC else ""
check("Enabled = true," in p59 and "OwnerFirst = true," in p59,
      "CODEBOT v191: SoundConfig.Pass59 Enabled + OwnerFirst=true")
check(Path(CL + "Controllers/AmbienceController.luau").is_file(),
      "CODEBOT v191: AmbienceController.luau present")
AM = read(CL + "Controllers/AmbienceController.luau")
check("function AmbienceController.Init" in AM or "AmbienceController.Init" in AM,
      "CODEBOT v191: AmbienceController.Init present")

BOOT = read(S + "Bootstrap.server.luau")
check("HangarDockDisplayService" in BOOT, "CODEBOT v191: Bootstrap wires HangarDockDisplayService")
CBOOT = read(CL + "Bootstrap.client.luau")
check("AmbienceController" in CBOOT, "CODEBOT v191: client Bootstrap wires AmbienceController")

check(Path("tools/checks/claude_bud_job58.py").is_file(), "CODEBOT v191: claude_bud_job58.py present")
check(Path("tools/checks/claude_bud_job59.py").is_file(), "CODEBOT v191: claude_bud_job59.py present")
check(Path("tools/checks/claude_bud_job60.py").is_file(), "CODEBOT v191: claude_bud_job60.py present")
J58 = read("tools/checks/claude_bud_job58.py")
J59 = read("tools/checks/claude_bud_job59.py")
J60 = read("tools/checks/claude_bud_job60.py")
check("HangarDock" in J58 and "OwnerFirst" in J58, "CODEBOT v191: claude_bud_job58 pins HangarDock")
check("Pass59" in J59 and "OwnerFirst" in J59, "CODEBOT v191: claude_bud_job59 pins Pass59")
check("AnchorPoint" in J60 and "LoadAnimation" in J60, "CODEBOT v191: claude_bud_job60 pins AnchorPoint/LoadAnimation")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
check(prev_mon is not None and prev_mon == MON, "CODEBOT v191: MonetizationConfig byte-identical to " + PREV)
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v191: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v191: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v191: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v191: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v191: StreamingEnabled stays OFF")
