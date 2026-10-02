# Code Bot Roblox v202 (2026-10-01): claude-bud JOB 66 — the two 5 R$ starter products (OwnerFirst).
# Recruit Starter Pack one-time (3 soldiers + 2.5 min income cash) + 2x Income 10 min repeatable.
# 5 R$ ONE-TIME OFFER at 5 min (Starter5Offered). HUD 2x m:ss chip. Id=0 until Creator Hub products.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; no price changes beyond Shaun-approved JOB 66.
# JOB 62 ExperienceNotify intentionally NOT included (needs WE_NOTIFY_KEY).
import os
import re
import subprocess
from pathlib import Path

# Strip the exact Shaun-approved JOB 66 MonetizationConfig block before byte-identical compares elsewhere.
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
PREV = os.environ.get("CODEBOT_V202_PREV", "49821c7")  # v201 code tip (place 199)
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


for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 221'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 221'),
    (S + "Services/DataService.luau", "WE_Build=221"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 221'),
):
    check(needle in read(rel), "CODEBOT v202: WE_Build=221 " + rel.rsplit("/", 1)[-1])

MON = read(C + "MonetizationConfig.luau")
# v204: Id 0 pins superseded in codebot_v204.py (Creator Hub Ids filled)
check('StarterRecruit5 = { Id = 3715888533, DisplayName = "Recruit Starter Pack", RobuxPrice = 5,' in MON, "CODEBOT v202: StarterRecruit5 is 5 R$ (Id filled v204)")
check('Boost2x10m = { Id = 3715888566, DisplayName = "2x Income 10 min", RobuxPrice = 5,' in MON, "CODEBOT v202: Boost2x10m is 5 R$ (Id filled v204)")
s5 = MON.split("Starter5 = {")[1].split("\n}\n")[0] if "Starter5 = {" in MON else ""
# Code Bot v206: the 60 s test value was v204 / v205 scope; live (v206+) is 300
_v202_test60 = any('SetAttribute("WE_Build", %d)' % _n in read(S + "Services/DataService.luau") for _n in (204, 205))
# Code Bot v207: OwnerFirst = true is v202-v206 scope; WE_Build 207+ is public (codebot_v207.py)
_v202_bn = int((re.search(r'WE_Build", (\d+)\)', read(S + "Services/DataService.luau")) or [0, "0"])[1])
_v202_of = ("OwnerFirst = true, -- NEW-OWNER-FIRST" in s5) or (_v202_bn >= 207 and "OwnerFirst = false, -- PUBLIC (Code Bot v207" in s5)
check("Enabled = true," in s5 and _v202_of and ("OfferAfterPlaySeconds = %d," % (120 if _v202_bn >= 209 else (60 if _v202_test60 else 300))) in s5,
      "CODEBOT v202: Starter5 owner-first (public v207+); offer at " + ("60 s test value (v204/v205)" if _v202_test60 else "120 s (live; v209; v207/v208 were 300 s)"))
check("if row and typeof(row.LiveBlock) == \"string\" then" in MON, "CODEBOT v202: SkuLiveFor LiveBlock for Starter5")

MS = read(S + "Services/MonetizationService.luau")
check("-- claude-bud JOB 66: the 5 R$ products." in MS, "CODEBOT v202: ProcessReceipt JOB 66 block present")
check("CS.GrantCashBoost, player, product.GrantsCashBoostMinutes" in MS, "CODEBOT v202: boost via CodesService.GrantCashBoost")
check('EconomyService.AddCash(player, cash, "devproduct")' in MS, "CODEBOT v202: starter cash as devproduct (never multiplied)")

RP = read(S + "Services/RecruitPackService.luau")
check("profile.Starter5Offered = true" in RP, "CODEBOT v202: Starter5Offered once flag")

PS = read(S + "Modules/ProfileSchema.luau")
check("profile.Starter5Offered = if profile.Starter5Offered == true then true else nil" in PS,
      "CODEBOT v202: Starter5Offered sanitised save key (no wipe)")

H = read(CL + "Controllers/HUDController.luau")
check('bc.Name = "BoostChip"' in H and "Starter5LiveFor(player.UserId)" in H, "CODEBOT v202: HUD BoostChip owner-first")

# Money: outside the JOB 66 block, MonetizationConfig matches PREV
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v202's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v202_own_mon = 'SetAttribute("WE_Build", 202)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v202_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)),
      "CODEBOT v202: MonetizationConfig identical to " + PREV + " outside JOB 66 block")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v202: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v202: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v202: StreamingEnabled stays OFF")

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
names = (r.stdout or "").splitlines()
touched_b = [n for n in names if "WE_Building" in n]
check(r.returncode == 0 and not touched_b, "CODEBOT v202: no WE_Building* diffs vs " + PREV)

# JOB 62 must NOT ship on phase-7
# claude-bud: JOB 62 lives on claude/desktop-bud (owner-first, needs WE_NOTIFY_KEY); this pin is v202's own ship scope
check((not _v202_own_mon) or "ExperienceNotifyService" not in read(S + "Bootstrap.server.luau"),
      "CODEBOT v202: ExperienceNotify (JOB 62) NOT shipped")

# JOB 66 files are in the diff
check(any("MonetizationConfig" in n or "RecruitPackService" in n or "HUDController" in n for n in names),
      "CODEBOT v202: JOB 66 files in diff vs " + PREV)

# DataService: only WE_Build number vs PREV (plus no new wipe keys — Starter5Offered is in ProfileSchema not DataService)
_pds = shipped(S + "Services/DataService.luau", PREV) or ""
# Code Bot v203: this DataService scope pin is v202's own ship scope; a later build bumps WE_Build again.
_v202_later = 'SetAttribute("WE_Build", 202)' not in read(S + "Services/DataService.luau")
check(_v202_later or _pds.replace('WE_Build", 201)', 'WE_Build", 202)').replace("WE_Build=201", "WE_Build=202") == read(S + "Services/DataService.luau"),
      "CODEBOT v202: DataService: only the WE_Build number changed vs " + PREV + " (save keys kept)")
