# Code Bot Roblox v194 (2026-10-01): $1B cash cap bug fix (for everyone, not OwnerFirst).
# EconomyConfig.MaxCash 1e9 -> 1e15; CollectPendingCash credits only what fits and leaves the rest in PendingCash;
# TotalCashEarned counts only the credited amount; "T" step in the short cash formatters.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged; save keys unchanged.
import os
import re
import subprocess
from pathlib import Path

# claude-bud JOB 66 (2026-10-01): the ONLY MonetizationConfig change allowed past this ship guard is the Shaun-approved
# JOB 66 block (the two 5 R$ starter rows, the Starter5 switch, the SkuLiveFor LiveBlock lines), removed exactly here
# before the byte-identical compare. Everything else in the file must still match.
def _bud_j66(t):
    t = (t or "").replace("\r\n", "\n")
    # Code Bot v212: the one new remote NAME (RequestAirdropGuideSetting; no save key) is not a save-key change
    t = "".join(ln for ln in t.splitlines(True) if "-- Code Bot board-text: Settings -> airdrop guide line off" not in ln)
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
PREV = os.environ.get("CODEBOT_V194_PREV", "a42fc12")  # v193 code tip (place 191)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 212'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 212'),
    (S + "Services/DataService.luau", "WE_Build=212"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 212'),
):
    check(needle in read(rel), "CODEBOT v194: WE_Build=212 " + rel.rsplit("/", 1)[-1])

EC = code(read(C + "EconomyConfig.luau"))
m = re.search(r"\bMaxCash\s*=\s*([0-9_.eE+]+)\s*,", EC)
check(m is not None and float(m.group(1).replace("_", "")) == 1e15, "CODEBOT v194: EconomyConfig.MaxCash == 1e15")

ES = code(read(S + "Services/EconomyService.luau"))
cp = ES.split("function EconomyService.CollectPendingCash(")[1].split("\nend\n")[0] if "function EconomyService.CollectPendingCash(" in ES else ""
check("local room = math.max(0, EconomyConfig.MaxCash - profile.Cash)" in cp
      and "local credited = math.min(pending, room)" in cp,
      "CODEBOT v194: CollectPendingCash credits only min(pending, MaxCash - Cash)")
check("(profile :: any).PendingCash = pending - credited" in cp and "PendingCash = 0" not in cp,
      "CODEBOT v194: CollectPendingCash leaves the remainder in PendingCash (no zeroing before the clamp)")
check("profile.Stats.TotalCashEarned += credited" in cp and "TotalCashEarned += pending" not in cp
      and "return credited" in cp,
      "CODEBOT v194: CollectPendingCash TotalCashEarned / return = credited")
ac = ES.split("function EconomyService.AddCash(")[1].split("\nend\n")[0] if "function EconomyService.AddCash(" in ES else ""
check("TotalCashEarned += math.max(0, profile.Cash - before)" in ac and "TotalCashEarned += granted" not in ac,
      "CODEBOT v194: AddCash TotalCashEarned counts only the credited amount")


# behavioural model of the collect remainder (mirrors the Luau above)
def collect(cash, pending, maxc=1e15):
    room = max(0, maxc - cash)
    credited = min(pending, room)
    if credited <= 0:
        return cash, pending, 0
    return cash + credited, pending - credited, credited


check(collect(1e15 - 100, 250) == (1e15, 150, 100), "CODEBOT v194: model: collect at cap keeps remainder 150")
check(collect(1e15, 500) == (1e15, 500, 0), "CODEBOT v194: model: full wallet keeps all pending")
check(collect(2_000_000_000, 5_000_000_000) == (7_000_000_000, 0, 5_000_000_000), "CODEBOT v194: model: $7B wallet ok (past old $1B wall)")

for rel, fmt in (
    (CL + "Modules/EngagementClient.luau", 'string.format("%.1fT", n / 1e12)'),
    (CL + "Controllers/EndgameController.luau", 'string.format("$%.2fT", n / 1e12)'),
    (S + "Services/EndgameService.luau", 'string.format("%.2fT", n / 1e12)'),
):
    check(fmt in read(rel), "CODEBOT v194: T step in short() " + rel.rsplit("/", 1)[-1])

check(m is not None and "OwnerFirst" not in cp and "OwnerFirst" not in ac and "IsOwner" not in cp,
      "CODEBOT v194: cap fix is for everyone (no OwnerFirst gate on MaxCash / AddCash / CollectPendingCash)")
MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v194's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v194_own_mon = 'SetAttribute("WE_Build", 194)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v194_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)), "CODEBOT v194: MonetizationConfig byte-identical to " + PREV)
for rel in ("src/ReplicatedStorage/Shared/Constants.luau", C + "LeaderboardConfig.luau"):
    if (ROOT / rel).exists():
        check(_bud_j66(shipped(rel, PREV)) == _bud_j66(read(rel)), "CODEBOT v194: save keys unchanged " + rel.rsplit("/", 1)[-1])
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v194: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v194: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v194: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v194: StreamingEnabled stays OFF")
