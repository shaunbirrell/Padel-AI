# Code Bot Roblox v195 (2026-10-01): cash pill shows 3 decimals from $1B up ("1.003B", "2.500T") so income is
# visible above the old $1B wall (2 decimals sat on "1.00B" for ~57 s at $174,688/s). Display only:
# no economy change, no price change, save keys unchanged, PreferMesh OFF, StreamingEnabled OFF, no WE_Building*.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V195_PREV", "c288e7a")  # v194 code tip (place 192)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 195)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 195)'),
    (S + "Services/DataService.luau", "WE_Build=195"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 195)'),
):
    check(needle in read(rel), "CODEBOT v195: WE_Build=195 " + rel.rsplit("/", 1)[-1])

HC = code(read(C + "HudConfig.luau"))
check(re.search(r"\bAbbreviateDecimalsBig\s*=\s*3\s*,", HC) is not None, "CODEBOT v195: HudConfig.CashPill.AbbreviateDecimalsBig = 3")
check(re.search(r"\bAbbreviateAbove\s*=\s*1e9\s*,", HC) is not None, "CODEBOT v195: AbbreviateAbove stays 1e9")
HUD = code(read(CL + "Controllers/HUDController.luau"))
fc = HUD.split("local function formatCash(")[1].split("\nend\n")[0] if "local function formatCash(" in HUD else ""
check('if a.Value >= 1e9 then (tonumber(P.AbbreviateDecimalsBig) or 3) else 2' in fc
      and 'string.format("%." .. tostring(dp) .. "f%s", v / a.Value, a.Suffix)' in fc
      and 'string.format("%.2f%s", v / a.Value, a.Suffix)' not in fc,
      "CODEBOT v195: formatCash uses 3 decimals for B/T, 2 for M/K")


def fmt(v):  # mirrors formatCash body
    v = int(v + 0.5)
    if abs(v) >= 1e9:
        for val, suf in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
            if abs(v) >= val:
                return ("%." + str(3 if val >= 1e9 else 2) + "f%s") % (v / val, suf)
    return f"{v:,}"


check(fmt(1_000_000_000) == "1.000B", "CODEBOT v195: model: 1e9 -> 1.000B")
check(fmt(1_000_000_000 + 174_688 * 6) == "1.001B", "CODEBOT v195: model: +6 s of $174,688/s visible (1.001B)")
check(fmt(1_003_400_000) == "1.003B", "CODEBOT v195: model: 1,003,400,000 -> 1.003B")
check(fmt(2_500_000_000_000) == "2.500T", "CODEBOT v195: model: 2.5e12 -> 2.500T")
check(fmt(999_999_999) == "999,999,999", "CODEBOT v195: model: below 1B keeps commas")

EC = code(read(C + "EconomyConfig.luau"))
m = re.search(r"\bMaxCash\s*=\s*([0-9_.eE+]+)\s*,", EC)
check(m is not None and float(m.group(1).replace("_", "")) == 1e15, "CODEBOT v195: EconomyConfig.MaxCash still 1e15")
for rel in (C + "MonetizationConfig.luau", C + "EconomyConfig.luau", S + "Services/EconomyService.luau",
            "src/ReplicatedStorage/Shared/Constants.luau", C + "LeaderboardConfig.luau"):
    if (ROOT / rel).exists():
        check(shipped(rel, PREV) == read(rel), "CODEBOT v195: byte-identical to " + PREV + " " + rel.rsplit("/", 1)[-1])
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v195: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v195: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v195: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v195: StreamingEnabled stays OFF")
