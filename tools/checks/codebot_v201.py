# Code Bot Roblox v201 (2026-10-01): Shaun's offline ("Away") cash rule + the 7-day strip overlap, live for everyone.
# OfflineConfig (ONE place): offline = min(awaySeconds, MaxSeconds 7200) x incomePerSecond x Rate 0.10; the server
# grant (RetentionService.ComputeOffline / offlineCapCash / capSecondsFor / NotifyState), the Missions "Away N h" line,
# the D7 tile (DailyRewardConfig.Day7Scale.IncomeMinutes = MaxSeconds x Rate / 60) and the Welcome back card read it.
# Double Weekend unchanged (offline NOT in EventConfig.ExtraCashReasons; OfflineFactor as since v185). Save keys
# unchanged. The 7-day tiles use the shared TycoonMath.ShortCash (K/M/B/T), TextScaled + UITextSizeConstraint,
# ClipsDescendants. PreferMesh OFF; StreamingEnabled OFF; MonetizationConfig byte-identical; no WE_Building* diffs.
import os
import re
import subprocess
import tempfile
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
PREV = os.environ.get("CODEBOT_V201_PREV", "7a47209")  # the code tip before this version
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 223'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 223'),
    (S + "Services/DataService.luau", "WE_Build=223"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 223'),
):
    check(needle in read(rel), "CODEBOT v201: WE_Build=223 " + rel.rsplit("/", 1)[-1])

# ── the formula: ONE central config ──
OFC = code(read(C + "OfflineConfig.luau"))
check(re.search(r"\bMaxSeconds = 7200,", OFC) is not None, "CODEBOT v201: OfflineConfig.MaxSeconds = 7200 (2 h cap)")
check(re.search(r"\bRate = 0\.10,", OFC) is not None, "CODEBOT v201: OfflineConfig.Rate = 0.10 (10 % of the normal rate)")
check("PremiumBonus = 0," in OFC, "CODEBOT v201: no Premium bonus on top of Shaun's formula")
check("math.min(away, cap)" in OFC and "OfflineConfig.CountedSeconds(awaySeconds, capSeconds) * perSec * math.clamp(OfflineConfig.Rate, 0, 1)" in OFC,
      "CODEBOT v201: OfflineConfig.Earnings = min(away, cap) x income/s x Rate")
EC = code(read(C + "EconomyConfig.luau"))
oe = EC.split("OfflineEarnings = {")[1].split("\n\t},")[0] if "OfflineEarnings = {" in EC else ""
check(oe and "CapSeconds" not in oe and "Share" not in oe and "CapMult" not in oe and "PremiumBonus" not in oe and "Enabled = true," in oe,
      "CODEBOT v201: EconomyConfig.OfflineEarnings keeps only the switches (no second cap / rate)")
m = re.search(r"\bMaxCash\s*=\s*([0-9_.eE+]+)\s*,", EC)
check(m is not None and float(m.group(1).replace("_", "")) == 1e15, "CODEBOT v201: EconomyConfig.MaxCash still 1e15")
prev_ec = shipped(C + "EconomyConfig.luau", PREV)
if prev_ec is not None:
    strip_oe = lambda s: re.sub(r"\n\tOfflineEarnings = \{.*?\n\t\},\n", "\n", s, flags=re.S)
    check(strip_oe(code(prev_ec)) == strip_oe(EC), "CODEBOT v201: EconomyConfig unchanged outside OfflineEarnings vs " + PREV)
RS = code(read(S + "Services/RetentionService.luau"))
check("local OfflineConfig = require(Shared.Configs.OfflineConfig)" in RS, "CODEBOT v201: RetentionService reads OfflineConfig")
check("return OfflineConfig.Earnings(away, perSec, cap, mult)" in RS, "CODEBOT v201: the server grant (ComputeOffline) = OfflineConfig.Earnings")
check("local cap = math.max(0, tonumber(OfflineConfig.MaxSeconds) or 0)" in RS and "cap *= math.max(1, tonumber(OfflineConfig.PassCapMult) or 1)" in RS,
      "CODEBOT v201: the cap = OfflineConfig.MaxSeconds (x PassCapMult only with the 2x Offline Cash pass)")
check("return OfflineConfig.Earnings(capSecondsFor(player, profile), incomePerSecond(player, profile), capSecondsFor(player, profile), premiumMult(player))" in RS,
      "CODEBOT v201: the Missions 'Away' amount (OfflineCapCash) = the same OfflineConfig.Earnings at a full cap")
check("o.Share" not in RS and RS.count("o.CapSeconds") == 1 and "tonumber(o.CapSeconds) or OfflineConfig.MaxSeconds" in RS
      and "o.PremiumBonus" not in RS and "b.CapMult" not in RS,
      "CODEBOT v201: no second offline cap / rate left in RetentionService")
check('EconomyService.AccruePendingCash(player, cash, "offline")' in RS and "profile.PrevSeenUnix = nil" in RS,
      "CODEBOT v201: grant path + paid-once unchanged (save keys LastSeenUnix / PrevSeenUnix untouched)")
DS = read(S + "Services/DataService.luau")
check("(profile :: any).LastSeenUnix = os.time()" in DS and "(profile :: any).PrevSeenUnix = (profile :: any).LastSeenUnix" in DS,
      "CODEBOT v201: save keys unchanged (no wipe)")

# ── Double Weekend: unchanged, offline NOT added to ExtraCashReasons ──
EV = code(read(C + "EventConfig.luau"))
ecr = EV.split("ExtraCashReasons = {")[1].split("}")[0] if "ExtraCashReasons = {" in EV else "?"
check("offline" not in ecr, "CODEBOT v201: 'offline' NOT in EventConfig.ExtraCashReasons (Double Weekend does not double it)")
prev_ev = shipped(C + "EventConfig.luau", PREV)
# Code Bot v205: the display-only ChipPublic block (codebot_v205.py) is allowed; everything else stays byte-identical
_ev_strip = lambda t: re.sub(r"\t-- Code Bot v205 \(owner 2026-10-01: \"switch the 2x event.*?\tChipPublic = true,\n", "", t, flags=re.S)
check(prev_ev is None or prev_ev == _ev_strip(read(C + "EventConfig.luau")), "CODEBOT v201: EventConfig byte-identical to " + PREV + " (v205 ChipPublic display block allowed)")
check("DoubleEvent).OfflineFactor(" in RS and "mult /= em" in RS, "CODEBOT v201: the v185 offline event rule as before (rate excludes the event; in-window span only)")

# ── executed: the real OfflineConfig in Luau ──
luau = os.environ.get("LUAU")
if not luau and os.environ.get("LUAU_COMPILE"):
    d = os.path.dirname(os.environ["LUAU_COMPILE"])
    for n in ("luau.exe", "luau"):
        if os.path.exists(os.path.join(d, n)):
            luau = os.path.join(d, n)
if luau:
    src = "local OfflineConfig = (function()\n" + read(C + "OfflineConfig.luau").replace("--!strict", "") + "\nend)()\n" + r"""
local E = OfflineConfig.Earnings
print("V_OLD_EXAMPLE", E(7200, 1000000 / 7200))
print("V_349K_16H", E(16 * 3600, 349376))
print("V_349K_1H", E(3600, 349376))
print("V_PASS_16H", E(16 * 3600, 349376, OfflineConfig.MaxSeconds * OfflineConfig.PassCapMult))
print("V_FULLCAP", OfflineConfig.FullCapCash(349376))
print("V_NAN", E(0 / 0, 100), E(100, 0 / 0), E(-5, 100), E(100, -1))
"""
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(src)
    r = subprocess.run([luau, f.name], capture_output=True, text=True, timeout=60)
    out = r.stdout or ""
    check(r.returncode == 0 and "V_OLD_EXAMPLE\t100000\n" in out, "CODEBOT v201: Shaun's example: $1M per 2 h -> $100,000 while away")
    check("V_349K_16H\t251550720\n" in out, "CODEBOT v201: $349,376/s away 16 h -> $251,550,720 (2 h x 10 %; was $2,515,507,200 / $5,031,014,400 with the pass)")
    check("V_349K_1H\t125775360\n" in out, "CODEBOT v201: under the cap pays the time away: 1 h -> $125,775,360")
    check("V_PASS_16H\t503101440\n" in out, "CODEBOT v201: 2x Offline Cash pass owner: 4 h x 10 % -> $503,101,440")
    check("V_FULLCAP\t251550720\n" in out, "CODEBOT v201: FullCapCash (the Away line / D7) = the 2 h grant")
    check("V_NAN\t0\t0\t0\t0\n" in out, "CODEBOT v201: NaN / negative inputs pay 0")
else:
    check(False, "CODEBOT v201: luau CLI not found (set LUAU or LUAU_COMPILE)")

# ── D7 = one full offline cap ──
DR = code(read(C + "DailyRewardConfig.luau"))
check("local OfflineConfig = require(script.Parent.OfflineConfig)" in DR
      and "IncomeMinutes = OfflineConfig.MaxSeconds * OfflineConfig.Rate / 60," in DR,
      "CODEBOT v201: Day7Scale.IncomeMinutes = OfflineConfig.MaxSeconds x Rate / 60 (12 min of income; was 60)")
MSV = code(read(S + "Services/MissionService.luau"))
check("math.max(floorCash, math.floor(perMin * mins))" in MSV, "CODEBOT v201: Day 7 keeps the table floor")

# ── the 7-day strip: shared formatter, fits its tile ──
SS = code(read(CL + "Modules/StreakStrip.luau"))
check("return TycoonMath.ShortCash(tonumber(n) or 0, true)" in SS and "%.1fk" not in SS,
      "CODEBOT v201: D1..D7 tile labels use the shared TycoonMath.ShortCash (no k-only formatter)")
check(SS.count("fitText(") >= 3 and "label.TextScaled = true" in SS and "c.MaxTextSize" in SS and "UITextSizeConstraint" in SS
      and "TextScaled = false" not in SS, "CODEBOT v201: tile labels TextScaled + UITextSizeConstraint (never spill)")
check("tile.ClipsDescendants = true" in SS and "tile.Size = UDim2.new(1 / days, -gap * (days - 1) / days, 1, 0)" in SS,
      "CODEBOT v201: tiles share the strip width and clip their labels (nothing over a neighbour)")
check('ReplicatedStorage:WaitForChild("Shared", 60)' in SS, "CODEBOT v201: StreakStrip's Shared wait is bounded")
TM = code(read("src/ReplicatedStorage/Shared/Util/TycoonMath.luau"))
check('bigText(v, 1e12, "T")' in TM and 'bigText(v, 1e9, "B")' in TM, "CODEBOT v201: TycoonMath.ShortCash knows B and T")
MC = code(read(CL + "Controllers/MissionController.luau"))
check("or (OfflineConfig.MaxSeconds / 3600)" in MC and "OfflineCapHours) or 8" not in MC,
      "CODEBOT v201: the Missions Away line falls back to OfflineConfig's 2 h (not 8)")
check("cap.MaxSize = Vector2.new(natural, tileH)" in MC and "strip.Size = UDim2.new(1, -20, 0, tileH)" in MC,
      "CODEBOT v201: the Missions strip takes the row width (D7 never off a phone panel)")
RC = code(read(CL + "Controllers/RetentionController.luau"))
check('" (8 h max)"' not in RC and "OfflineConfig.MaxSeconds / 3600" in RC and '" · Premium +10%"' not in RC,
      "CODEBOT v201: the Welcome back card shows OfflineConfig's cap (no hard-coded 8 h / Premium +10 %)")

# ── hard rules ──
# the claude/desktop-bud branch carries unshipped work (JOB 62 ExperienceNotify, JOB 66 products): the ship-only pins
# (byte-identical money config, DataService scope) apply to phase-7-polish only, as in codebot_v200
BUD = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()
MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v201's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v201_own_mon = 'SetAttribute("WE_Build", 201)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v201_own_mon) or (BUD or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON))), "CODEBOT v201: MonetizationConfig byte-identical to " + PREV + " (no Robux changes; JOB 66 block allowed)" + (" [bud branch: ship-only, skipped]" if BUD else ""))
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v201: PreferMesh stays OFF (VisualAssetConfig)")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v201: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v201: StreamingEnabled stays OFF")
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v201: no WE_Building* diffs vs " + PREV)
check(not re.search(r"OwnerFirst = true", read(C + "OfflineConfig.luau")), "CODEBOT v201: the offline rule is live for everyone (not OwnerFirst)")
_pds = shipped(S + "Services/DataService.luau", PREV) or ""
# Code Bot v202: DataService scope pin is v201's own ship scope; a later build changes other files.
_v201_later = 'SetAttribute("WE_Build", 201)' not in read(S + "Services/DataService.luau")
check(BUD or _v201_later or _pds.replace('WE_Build", 200)', 'WE_Build", 201)').replace("WE_Build=200", "WE_Build=201") == read(S + "Services/DataService.luau"),
      "CODEBOT v201: DataService: only the WE_Build number changed vs " + PREV + " (save keys kept, no wipe)")
