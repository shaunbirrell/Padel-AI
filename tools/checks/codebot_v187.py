# Code Bot Roblox v187 (2026-10-01): cherry-pick claude-bud JOB 50 A (ZoneRuns OwnerFirst).
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V187_PREV", "12bcd18")  # v186 handoff tip (place 184)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 189)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 189)'),
    (S + "Services/DataService.luau", "WE_Build=189"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 189)'),
):
    check(needle in read(rel), "CODEBOT v187: WE_Build=189 " + rel.rsplit("/", 1)[-1])

ZC = read(C + "RebirthZonesConfig.luau")
rb = ZC.split("cfg.Rebuild = {")[1].split("\n}")[0] if "cfg.Rebuild = {" in ZC else ""
check("Enabled = true," in rb and "OwnerFirst = true," in rb,
      "CODEBOT v187: RebirthZonesConfig.Rebuild Enabled + OwnerFirst=true")
check(Path(S + "Modules/ZoneRuns.luau").is_file(), "CODEBOT v187: ZoneRuns.luau present")
ZR = read(S + "Modules/ZoneRuns.luau")
check("function ZoneRuns.Step(" in ZR and "insideAnnex" in ZR, "CODEBOT v187: ZoneRuns.Step server-validates")
check(Path("tools/checks/claude_bud_job50.py").is_file() and "part A" in read("tools/checks/claude_bud_job50.py"),
      "CODEBOT v187: claude_bud_job50.py pins part A")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
check(prev_mon is not None and prev_mon == MON, "CODEBOT v187: MonetizationConfig byte-identical to " + PREV)
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v187: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v187: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v187: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v187: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v187: StreamingEnabled stays OFF")
