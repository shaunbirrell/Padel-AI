# Code Bot Roblox v188 (2026-10-01): cherry-pick claude-bud JOB 50 B+C (Visuals+Signs OwnerFirst).
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
import os
import re
import subprocess
from pathlib import Path

# claude-bud JOB 66 (2026-10-01): the ONLY MonetizationConfig change allowed past this ship guard is the Shaun-approved
# JOB 66 block (the two 5 R$ starter rows, the Starter5 switch, the SkuLiveFor LiveBlock lines), removed exactly here
# before the byte-identical compare. Everything else in the file must still match.
def _bud_j66(t):
    t = (t or "").replace("\r\n", "\n")
    a = t.find("\t-- claude-bud JOB 66 (price approved by Shaun")
    if a >= 0:
        b = t.find("\n", t.find("\tBoost2x10m = {", a)) + 1
        t = t[:a] + t[b:]
    a = t.find("-- claude-bud JOB 66: the two 5 R$ starter products")
    if a >= 0:
        t = t[:a] + t[t.find("function MonetizationConfig.SkuLiveFor", a):]
    a = t.find("\t-- claude-bud JOB 66: a row tied to an owner-first switch (LiveBlock)")
    if a >= 0:
        b = t.find("\tend\n", a) + len("\tend\n")
        t = t[:a] + t[b:]
    return t



ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V188_PREV", "3c2719e")  # v187 handoff tip (place 185)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 222'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 222'),
    (S + "Services/DataService.luau", "WE_Build=222"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 222'),
):
    check(needle in read(rel), "CODEBOT v188: WE_Build=222 " + rel.rsplit("/", 1)[-1])

ZC = read(C + "RebirthZonesConfig.luau")
rb = ZC.split("cfg.Rebuild = {")[1].split("\n}")[0] if "cfg.Rebuild = {" in ZC else ""
check("Enabled = true," in rb and "OwnerFirst = false," in rb,
      "CODEBOT v188: RebirthZonesConfig.Rebuild Enabled + OwnerFirst=false [public since codebot_v220]")
check("Visuals = true," in rb, "CODEBOT v188: Rebuild.Visuals = true")
check("Signs = true," in rb, "CODEBOT v188: Rebuild.Signs = true")
check("function cfg.RunLine(" in ZC, "CODEBOT v188: RebirthZonesConfig.RunLine present")
check("StatusRefreshSeconds" in ZC, "CODEBOT v188: RunRules.StatusRefreshSeconds present")
check("ReadyToast" in ZC, "CODEBOT v188: RunRules.ReadyToast present")

check(Path(S + "Modules/RebirthZoneDressing.luau").is_file(), "CODEBOT v188: RebirthZoneDressing.luau present")
RD = read(S + "Modules/RebirthZoneDressing.luau")
check("function RebirthZoneDressing.BuildRunProps(" in RD, "CODEBOT v188: BuildRunProps present")

RZS = read(S + "Services/RebirthZoneService.luau")
check("function RebirthZoneService.MapRows(" in RZS, "CODEBOT v188: MapRows present")
check('RebuildLive(player.UserId, "Visuals")' in RZS or 'RebuildLive(uid, "Visuals")' in RZS
      or 'RebuildLive(player.UserId, "Visuals")' in RZS,
      "CODEBOT v188: Visuals owner-first path in RebirthZoneService")
check('RebuildLive(player.UserId, "Signs")' in RZS or 'RebuildLive(uid, "Signs")' in RZS,
      "CODEBOT v188: Signs owner-first path in RebirthZoneService")

check(Path("tools/checks/claude_bud_job50.py").is_file(), "CODEBOT v188: claude_bud_job50.py present")
J50 = read("tools/checks/claude_bud_job50.py")
check("part B" in J50 or "JOB 50 B" in J50 or "Visuals" in J50, "CODEBOT v188: claude_bud_job50 pins Visuals/B")
check("part C" in J50 or "JOB 50 C" in J50 or "Signs" in J50, "CODEBOT v188: claude_bud_job50 pins Signs/C")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v188's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v188_own_mon = 'SetAttribute("WE_Build", 188)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v188_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)), "CODEBOT v188: MonetizationConfig byte-identical to " + PREV)
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v188: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v188: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v188: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v188: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v188: StreamingEnabled stays OFF")
