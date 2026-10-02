# Code Bot Roblox v182 (2026-10-01): Shaun approved the launch of claude-bud JOB 49 C + D for everyone.
#   MissionConfig.Core.OwnerFirst           true -> false  (3 core daily missions + free reroll for everyone)
#   RetentionConfig.ReturnSequence.OwnerFirst true -> false  (one return-sequence card queue for everyone)
# The Mission Reroll dev product (3715836569, 19 R$) already had its own OwnerFirst = false (v180), so it opens with Core.
# Untouched: MonetizationConfig (every pass / product Id + price), every other OwnerFirst flag.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes.
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
PREV = os.environ.get("CODEBOT_V182_PREV", "9529c70")  # v181 live tip (place 179)
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
    # every "<Key> = { ... Id = N ... RobuxPrice = N ..." entry (one-line and multi-line) -> {key: (id, price)}
    out = {}
    for m in re.finditer(r"\n\t\t(\w+) = \{(.*?)(?:\},|\n\t\t\},)", src, re.S):
        body = code(m.group(2))
        i = re.search(r"\bId = (\d+)", body)
        p = re.search(r"\bRobuxPrice = (\d+)", body)
        if i:
            out[m.group(1)] = (int(i.group(1)), int(p.group(1)) if p else None)
    return out


# ── build pins ──
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 213'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 213'),
    (S + "Services/DataService.luau", "WE_Build=213"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 213'),
):
    check(needle in read(rel), "CODEBOT v182: WE_Build=213 " + rel.rsplit("/", 1)[-1])

# ── the two flips ──
MCF = read(C + "MissionConfig.luau")
core = MCF.split("\tCore = {")[1].split("\n\t},\n\n")[0] if "\tCore = {" in MCF else ""
cc = code(core)
check(re.search(r"\n\t\tEnabled = true,", cc) and re.search(r"\n\t\tOwnerFirst = false,", cc)
      and not re.search(r"\n\t\tOwnerFirst = true", cc) and "Count = 3," in cc,
      "CODEBOT v182: MissionConfig.Core Enabled + OwnerFirst=false (everyone), Count 3")
RCF = read(C + "RetentionConfig.luau")
rs = re.search(r"\bReturnSequence = \{(.*?)\n\t\},", RCF, re.S)
rsb = code(rs.group(1)) if rs else ""
check("Enabled = true," in rsb and "OwnerFirst = false," in rsb and "OwnerFirst = true" not in rsb,
      "CODEBOT v182: RetentionConfig.ReturnSequence Enabled + OwnerFirst=false (everyone)")
check("if block.OwnerFirst ~= true then\n\t\treturn true\n\tend" in RCF, "CODEBOT v182: RetentionConfig.Live: OwnerFirst ~= true -> everyone")

# ── the reroll stays wired ──
check('Robux = { Enabled = true, OwnerFirst = false, ProductKey = "MissionReroll" },' in core and "FreePerDay = 1," in core,
      "CODEBOT v182: Core.Reroll FreePerDay 1 + Robux reroll Enabled, OwnerFirst=false, ProductKey MissionReroll")
MON = read(C + "MonetizationConfig.luau")
m = re.search(r"\n\t\tMissionReroll = \{([^\n]*)\}", MON)
row = m.group(1) if m else ""
check(row.strip().startswith("Id = 3715836569,") and "RobuxPrice = 19," in row and "GrantsMissionReroll = true" in row,
      "CODEBOT v182: DevProducts.MissionReroll Id 3715836569, 19 R$, GrantsMissionReroll")
MSV = read(S + "Services/MonetizationService.luau")
check("GrantsMissionReroll == true" in MSV and "GrantRerollToken(player)" in MSV,
      "CODEBOT v182: ProcessReceipt still grants one reroll token per MissionReroll receipt")

# ── nothing else moved vs v181 ──
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v182's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v182_own_mon = 'SetAttribute("WE_Build", 182)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v182_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)), "CODEBOT v182: MonetizationConfig byte-identical to " + PREV + " (the approved JOB 66 block aside)")
if prev_mon is not None:
    a, b = skus(prev_mon), skus(MON)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(len(b) >= 40 and not diff, "CODEBOT v182: all %d pass/product Ids + prices unchanged vs %s%s"
          % (len(b), PREV, (" " + str(diff[:6])) if diff else ""))
try:
    # scoped to the two files v182 touched (claude/desktop-bud carries its own NEW-OWNER-FIRST blocks elsewhere)
    two = [C + "MissionConfig.luau", C + "RetentionConfig.luau"]
    r = subprocess.run(["git", "diff", "-U0", PREV, "--"] + two, capture_output=True, text=True, cwd=ROOT)
    changed = [l for l in (r.stdout or "").splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
    price = [l for l in changed if re.search(r"(Id|Price|Robux\w*) = \d", code(l[1:]))]
    owner = [l for l in changed if re.search(r"OwnerFirst = (true|false)", code(l[1:]))]
    check(r.returncode == 0 and not price, "CODEBOT v182: no Id / price line changed in MissionConfig / RetentionConfig" + ((" " + str(price[:4])) if price else ""))
    check(len(owner) == 4 and sum(1 for l in owner if l.startswith("+") and "OwnerFirst = false" in l) == 2,
          "CODEBOT v182: exactly two OwnerFirst lines flipped (Core, ReturnSequence)" + ((" " + str(owner)) if len(owner) != 4 else ""))
    r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
    touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
    check(r.returncode == 0 and not touched, "CODEBOT v182: no WE_Building* diffs vs " + PREV)
except Exception as e:
    check(False, "CODEBOT v182: git diff check errored: " + str(e))

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v182: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v182: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v182: StreamingEnabled stays OFF")
