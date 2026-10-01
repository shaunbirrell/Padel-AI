# Code Bot Roblox v186 (2026-10-01): cherry-pick claude-bud JOB 50 D (hotbar weapon labels overlap).
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V186_PREV", "5508896")  # v185 live tip (place 183)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 201)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 201)'),
    (S + "Services/DataService.luau", "WE_Build=201"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 201)'),
):
    check(needle in read(rel), "CODEBOT v186: WE_Build=201 " + rel.rsplit("/", 1)[-1])

CC = read(CL + "Controllers/CombatController.luau")
check("fitCaption" in CC, "CODEBOT v186: CombatController fitCaption present")
HC = read(C + "HudConfig.luau")
check("CaptionMinTextPx" in HC or "NameSize" in HC, "CODEBOT v186: HudConfig caption sizing present")
WC = read(C + "WeaponConfig.luau")
check('"LongshotDMR", "Longshot DMR", "DMR"' in WC and '"HavocLauncher", "Havoc Launcher", "HAVOC RL"' in WC
      and '"SovereignRifle", "Sovereign Rifle", "SOV RIFLE"' in WC,
      "CODEBOT v186: rebirth gun ShortNames distinct (DMR / HAVOC RL / SOV RIFLE)")
check(Path("tools/checks/claude_bud_job50.py").is_file(), "CODEBOT v186: tools/checks/claude_bud_job50.py present")
check(Path("tools/sim/run_hotbar_caption_test.py").is_file(), "CODEBOT v186: run_hotbar_caption_test.py present")

r = subprocess.run([os.environ.get("PYTHON", "python3"), "tools/sim/run_hotbar_caption_test.py"],
                   capture_output=True, text=True, cwd=ROOT)
check(r.returncode == 0 and "HOTBAR CAPTION TEST: 0 failed" in (r.stdout or ""),
      "CODEBOT v186: hotbar caption sim 0 failed")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
check(prev_mon is not None and prev_mon == MON, "CODEBOT v186: MonetizationConfig byte-identical to " + PREV)
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v186: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v186: no WE_Building* diffs vs " + PREV)

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v186: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v186: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v186: StreamingEnabled stays OFF")
