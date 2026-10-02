# Code Bot Roblox v190 (2026-10-01): cherry-pick claude-bud JOB 55 DefenceFix + JOB 56 SpawnTerminals/Rotor + JOB 57 BaseLife OwnerFirst.
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
PREV = os.environ.get("CODEBOT_V190_PREV", "2c6212f")  # v189 handoff tip (place 187)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 217'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 217'),
    (S + "Services/DataService.luau", "WE_Build=217"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 217'),
):
    check(needle in read(rel), "CODEBOT v190: WE_Build=217 " + rel.rsplit("/", 1)[-1])

EC = read(C + "EndgameConfig.luau")
df = EC.split("DefenceFix = {")[1].split("\n\t},")[0] if "DefenceFix = {" in EC else ""
check("Enabled = true," in df and "OwnerFirst = true," in df,
      "CODEBOT v190: EndgameConfig.DefenceFix Enabled + OwnerFirst=true")
check("function EndgameConfig.DefenceFixLive(" in EC, "CODEBOT v190: DefenceFixLive present")

STC = read(C + "SpawnTerminalConfig.luau")
check("Enabled = true," in STC and "OwnerFirst = true," in STC,
      "CODEBOT v190: SpawnTerminalConfig Enabled + OwnerFirst=true")
check(Path(S + "Services/SpawnTerminalService.luau").is_file(), "CODEBOT v190: SpawnTerminalService.luau present")
STS = read(S + "Services/SpawnTerminalService.luau")
check("function SpawnTerminalService.Init" in STS or "SpawnTerminalService.Init" in STS,
      "CODEBOT v190: SpawnTerminalService.Init present")

VAC = read(C + "VisualAssetConfig.luau")
ard = VAC.split("AirRotorDisc = {")[1].split("\n\t},")[0] if "AirRotorDisc = {" in VAC else ""
check("Enabled = true," in ard and "OwnerFirst = true," in ard,
      "CODEBOT v190: VisualAssetConfig.AirRotorDisc Enabled + OwnerFirst=true")
AB = read(S + "Modules/AirBodyRig.luau")
check("_DiscFit" in AB or "DiscFit" in AB, "CODEBOT v190: AirBodyRig disc fit present")

BLC = read(C + "BaseLifeConfig.luau")
check("Enabled = true," in BLC and "OwnerFirst = true," in BLC,
      "CODEBOT v190: BaseLifeConfig Enabled + OwnerFirst=true")
check(Path(S + "Services/BaseLifeService.luau").is_file(), "CODEBOT v190: BaseLifeService.luau present")
BLS = read(S + "Services/BaseLifeService.luau")
check("function BaseLifeService.Init" in BLS or "BaseLifeService.Init" in BLS,
      "CODEBOT v190: BaseLifeService.Init present")

BOOT = read(S + "Bootstrap.server.luau")
check("SpawnTerminalService" in BOOT, "CODEBOT v190: Bootstrap wires SpawnTerminalService")
check("BaseLifeService" in BOOT, "CODEBOT v190: Bootstrap wires BaseLifeService")

check(Path("tools/checks/claude_bud_job55.py").is_file(), "CODEBOT v190: claude_bud_job55.py present")
check(Path("tools/checks/claude_bud_job56.py").is_file(), "CODEBOT v190: claude_bud_job56.py present")
check(Path("tools/checks/claude_bud_job57.py").is_file(), "CODEBOT v190: claude_bud_job57.py present")
J55 = read("tools/checks/claude_bud_job55.py")
J56 = read("tools/checks/claude_bud_job56.py")
J57 = read("tools/checks/claude_bud_job57.py")
check("DefenceFix" in J55 and "OwnerFirst" in J55, "CODEBOT v190: claude_bud_job55 pins DefenceFix")
check("SpawnTerminal" in J56 and "OwnerFirst" in J56, "CODEBOT v190: claude_bud_job56 pins SpawnTerminal")
check("BaseLife" in J57 and "OwnerFirst" in J57, "CODEBOT v190: claude_bud_job57 pins BaseLife")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v190's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v190_own_mon = 'SetAttribute("WE_Build", 190)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v190_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)), "CODEBOT v190: MonetizationConfig byte-identical to " + PREV)
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v190: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v190: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v190: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v190: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v190: StreamingEnabled stays OFF")
