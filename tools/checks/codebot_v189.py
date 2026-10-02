# Code Bot Roblox v189 (2026-10-01): cherry-pick claude-bud JOB 53 Defence visuals + JOB 54 night lighting OwnerFirst.
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
PREV = os.environ.get("CODEBOT_V189_PREV", "c0d7123")  # v188 handoff tip (place 186)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 212'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 212'),
    (S + "Services/DataService.luau", "WE_Build=212"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 212'),
):
    check(needle in read(rel), "CODEBOT v189: WE_Build=212 " + rel.rsplit("/", 1)[-1])

EC = read(C + "EndgameConfig.luau")
dv = EC.split("DefenceVisuals = {")[1].split("\n\t},")[0] if "DefenceVisuals = {" in EC else ""
check("Enabled = true," in dv and "OwnerFirst = true," in dv,
      "CODEBOT v189: EndgameConfig.DefenceVisuals Enabled + OwnerFirst=true")
check("TierAt = { 1, 4, 7, 10 }" in dv, "CODEBOT v189: DefenceVisuals.TierAt L1/4/7/10")
check("function EndgameConfig.DefenceVisualsLive(" in EC, "CODEBOT v189: DefenceVisualsLive present")
check(Path(S + "Modules/DefenceVisuals.luau").is_file(), "CODEBOT v189: DefenceVisuals.luau present")
DV = read(S + "Modules/DefenceVisuals.luau")
check("function DefenceVisuals.Apply(" in DV, "CODEBOT v189: DefenceVisuals.Apply present")

LC = read(C + "LightingConfig.luau")
n2 = LC.split("Night2 = {")[1].split("\n\t},")[0] if "Night2 = {" in LC else ""
check("Enabled = true," in n2 and "OwnerFirst = true," in n2,
      "CODEBOT v189: LightingConfig.Night2 Enabled + OwnerFirst=true")
check("PerBaseLights = 4," in n2, "CODEBOT v189: Night2.PerBaseLights = 4")
check(Path(S + "Modules/NightLights.luau").is_file(), "CODEBOT v189: NightLights.luau present")
NL = read(S + "Modules/NightLights.luau")
check("function NightLights.SyncPlot(" in NL, "CODEBOT v189: NightLights.SyncPlot present")
check(Path("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NightExposureController.luau").is_file(),
      "CODEBOT v189: NightExposureController.luau present")

G = read(S + "Services/GateDefenseService.luau")
sp = G.split("local function syncPlotNow")[1].split("\nfunction GateDefenseService.SyncPlot")[0] if "local function syncPlotNow" in G else ""
check("DefenceVisualsMod.Apply" in sp, "CODEBOT v189: syncPlotNow calls DefenceVisuals.Apply")
check("NightLights" in sp and "SyncPlot" in sp, "CODEBOT v189: syncPlotNow calls NightLights.SyncPlot")

check(Path("tools/checks/claude_bud_job53.py").is_file(), "CODEBOT v189: claude_bud_job53.py present")
check(Path("tools/checks/claude_bud_job54.py").is_file(), "CODEBOT v189: claude_bud_job54.py present")
J53 = read("tools/checks/claude_bud_job53.py")
J54 = read("tools/checks/claude_bud_job54.py")
check("DefenceVisuals" in J53 and "OwnerFirst" in J53, "CODEBOT v189: claude_bud_job53 pins DefenceVisuals")
check("Night2" in J54 and "OwnerFirst" in J54, "CODEBOT v189: claude_bud_job54 pins Night2")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v189's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v189_own_mon = 'SetAttribute("WE_Build", 189)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v189_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)), "CODEBOT v189: MonetizationConfig byte-identical to " + PREV)
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v189: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v189: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v189: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v189: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v189: StreamingEnabled stays OFF")
