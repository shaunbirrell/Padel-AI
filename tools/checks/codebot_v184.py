# Code Bot Roblox v184 (2026-10-01): cherry-pick claude-bud JOB 52 (ARMY ATTACK at range OwnerFirst).
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V184_PREV", "744c18f")  # v183 live tip (place 181)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"


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
    check(needle in read(rel), "CODEBOT v184: WE_Build=192 " + rel.rsplit("/", 1)[-1])

AOC = read(C + "ArmyOrdersConfig.luau")
ar = AOC.split("AttackRange = {")[1].split("\n\t},\n")[0] if "AttackRange = {" in AOC else ""
check("Enabled = true," in ar and "OwnerFirst = true," in ar,
      "CODEBOT v184: ArmyOrdersConfig.AttackRange Enabled + OwnerFirst=true (phone test)")
check(Path(S + "Modules/ArmyPlan.luau").is_file() and "AttackRadii" in read(S + "Modules/ArmyPlan.luau"),
      "CODEBOT v184: ArmyPlan uses AttackRadii")
check(Path("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyNearestController.luau").is_file(),
      "CODEBOT v184: ArmyNearestController present")
check(Path("tools/checks/claude_bud_job52.py").is_file(),
      "CODEBOT v184: tools/checks/claude_bud_job52.py present")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
check(prev_mon is not None and prev_mon == MON, "CODEBOT v184: MonetizationConfig byte-identical to " + PREV)
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v184: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v184: no WE_Building* diffs vs " + PREV)

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v184: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v184: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v184: StreamingEnabled stays OFF")
print("CODEBOT v184: all checks passed")
