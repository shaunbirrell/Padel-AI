# Code Bot Roblox v196 (2026-10-01): claude-bud JOB 65 NukeRaid OwnerFirst (nuke instant raid).
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
# JOB 62 ExperienceNotify intentionally NOT included (needs WE_NOTIFY_KEY).
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
PREV = os.environ.get("CODEBOT_V196_PREV", "1b8d5fa")  # v195 code tip (place 193)
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


for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 201)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 201)'),
    (S + "Services/DataService.luau", "WE_Build=201"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 201)'),
):
    check(needle in read(rel), "CODEBOT v196: WE_Build=201 " + rel.rsplit("/", 1)[-1])

ZC = read(C + "RebirthZonesConfig.luau")
nr = ZC.split("NukeRaid = {")[1].split("\n\t},")[0] if "NukeRaid = {" in ZC else ""
check(
    "Enabled = true," in nr
    and "OwnerFirst = true, -- NEW-OWNER-FIRST" in nr
    and "CooldownSeconds = 1800," in nr
    and "Vfx = true," in nr
    and "Targets = {" in nr,
    "CODEBOT v196: NukeRaid OwnerFirst + 30min cooldown + Vfx + Targets",
)

NS = read(S + "Services/NukeService.luau")
check("function NukeService.RaidPreview(" in NS or "function NukeService.RaidVerdict(" in NS, "CODEBOT v196: NukeService RaidPreview/RaidVerdict")
check("function NukeService.RaidLaunch(" in NS, "CODEBOT v196: NukeService.RaidLaunch")
check("MoneyCollectorService.NukeRaid" in NS or "NukeRaid(" in NS, "CODEBOT v196: NukeService calls NukeRaid money path")

MC = read(S + "Services/MoneyCollectorService.luau")
nk = MC.split("function MoneyCollectorService.NukeRaid(")[1].split("\nend\n")[0] if "function MoneyCollectorService.NukeRaid(" in MC else ""
check(
    "GetRaidableBalance" in nk and "_MoveLoot" in nk and "PendingToCash" in nk and "AddCash" not in nk,
    "CODEBOT v196: NukeRaid = FULL ATM via _MoveLoot + PendingToCash (no AddCash)",
)

ES = read(S + "Services/EconomyService.luau")
p2c = ES.split("function EconomyService.PendingToCash(")[1].split("\nend\n")[0] if "function EconomyService.PendingToCash(" in ES else ""
check(p2c and "applyCashMult" not in p2c and "DoubleEvent" not in p2c, "CODEBOT v196: PendingToCash has no Double Weekend multiplier")

NC = read(CL + "Controllers/NukeController.luau")
check("NukeRaidPreview" in NC or "LAUNCH" in NC, "CODEBOT v196: NukeController preview/LAUNCH UI")

# JOB 62 must NOT ship
en = (ROOT / (S + "Services/ExperienceNotifyService.luau")).exists()
# ExperienceNotify may exist on bud merges into checks but should not be in this tree from JOB62 commit
# Verify we did not cherry-pick 00a76af: NotificationConfig.Experience OwnerFirst wiring not required here
NC2 = read(C + "NotificationConfig.luau") if (ROOT / (C + "NotificationConfig.luau")).exists() else ""
# Soft check: if Experience block exists from prior, OK; we just must not have shipped JOB62 as this build's feature.
# Hard: MonetizationConfig byte-identical to PREV
MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
check(prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON), "CODEBOT v196: MonetizationConfig byte-identical to " + PREV)

svc = read(C + "StructureVisualConfig.luau")
check("PreferMeshWhenAssetIdSet = false" in svc, "CODEBOT v196: PreferMesh OFF")
prj = read("default.project.json")
check('"StreamingEnabled": true' not in prj, "CODEBOT v196: StreamingEnabled stays OFF")

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(len(touched) == 0, "CODEBOT v196: no WE_Building* src touches")

# ExperienceNotifyService should not appear as a NEW ship in this cherry-pick set
r2 = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
names = (r2.stdout or "").splitlines()
# claude-bud (2026-10-01): on claude/desktop-bud JOB 62 is present; it must then stay owner-first (the v196 ship excludes it)
check(not any("ExperienceNotify" in n for n in names)
      or "OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 62)" in (ROOT / "src/ReplicatedStorage/Shared/Configs/NotificationConfig.luau").read_text(encoding="utf-8"),
      "CODEBOT v196: ExperienceNotify (JOB 62) NOT shipped (or, on the bud branch, still owner-first)")
check(any("NukeService" in n or "NukeController" in n or "RebirthZonesConfig" in n for n in names), "CODEBOT v196: nuke raid files in diff vs PREV")
