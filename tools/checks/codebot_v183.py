# Code Bot Roblox v183 (2026-10-01): cherry-pick claude-bud JOB 51 (SharedHostility OwnerFirst) + JOB 61 (Creator Hub analytics).
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
PREV = os.environ.get("CODEBOT_V183_PREV", "4952138")  # v182 live tip (place 180)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"




def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def check(cond, label):
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 216'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 216'),
    (S + "Services/DataService.luau", "WE_Build=216"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 216'),
):
    check(needle in read(rel), "CODEBOT v183: WE_Build=216 " + rel.rsplit("/", 1)[-1])

CC = read(C + "CombatConfig.luau")
blk = CC.split("SharedHostility = {")[1].split("\n}")[0] if "SharedHostility = {" in CC else ""
check("Enabled = true," in blk and "OwnerFirst = true," in blk,
      "CODEBOT v183: CombatConfig.SharedHostility Enabled + OwnerFirst=true (phone test)")
check(Path(S + "Modules/Hostility.luau").is_file(), "CODEBOT v183: Server/Modules/Hostility.luau present")
I = read(S + "Services/CombatService/init.luau")
check("Hostility.Bind({" in I and "mayTarget = CombatService.NpcMayTarget" in I,
      "CODEBOT v183: CombatService binds Hostility / NpcMayTarget")
A = read(S + "Services/AnalyticsService.luau")
AC = read(C + "AnalyticsConfig.luau")
check("LogEconomyEvent" in A and "LogOnboardingFunnelStepEvent" in A and "Funnel = {" in AC,
      "CODEBOT v183: AnalyticsService + AnalyticsConfig funnel/economy path")
check("RunService.Heartbeat" not in A and "RunService.Stepped" not in A,
      "CODEBOT v183: AnalyticsService has no Heartbeat/Stepped")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v183's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v183_own_mon = 'SetAttribute("WE_Build", 183)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v183_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)), "CODEBOT v183: MonetizationConfig byte-identical to " + PREV + " (the approved JOB 66 block aside)")
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v183: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v183: no WE_Building* diffs vs " + PREV)

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v183: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v183: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v183: StreamingEnabled stays OFF")
print("CODEBOT v183: all checks passed")
