# Code Bot Roblox v206 (2026-10-02, Shaun approved): the Supply Depot 'SUPPLY · R$' tab is sorted by Robux price,
# cheapest first (the two 5 R$ rows on top), price read from MonetizationConfig RobuxPrice; rows with no price (FREE rows,
# Favorite WAR EMPIRE, the locked Supply Crate) at the bottom; at the same price an OWNED one-time product / pass after the
# unowned ones. DISPLAY ORDER ONLY: no price / Id / prompt change; the Starter5 rows stay owner-only. Also the Starter5
# pop-up delay (MonetizationConfig.Starter5.OfferAfterPlaySeconds) goes back from the 60 s phone test to 300 s.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* diffs.
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V206_PREV", "fe6792b")  # v205 code tip (place 203)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
SHOP = CL + "Controllers/ShopController.luau"


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


def prices(src):
    """{(section, key): RobuxPrice} for every GamePasses / DevProducts entry (one-line and block form)."""
    out = {}
    for sec in ("GamePasses", "DevProducts"):
        body = src.split("\n\t" + sec + " = {", 1)[1] if ("\n\t" + sec + " = {") in src else ""
        body = body.split("\n\t}", 1)[0]
        cur = None
        for line in body.split("\n"):
            m1 = re.match(r"^\t{1,2}(\w+) = \{(.*)$", line)
            if m1:
                cur = m1.group(1)
                p = re.search(r"\bRobuxPrice = (\d+)", m1.group(2))
                if p:
                    out[(sec, cur)] = int(p.group(1))
                continue
            p = re.match(r"^\t{2,3}RobuxPrice = (\d+)", line)
            if p and cur:
                out[(sec, cur)] = int(p.group(1))
            q = re.match(r"^\t{2,3}OverhaulRobuxPrice = (\d+)", line)
            if q and cur:
                out[(sec, cur + ".Overhaul")] = int(q.group(1))
    return out


BUD = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()  # claude/desktop-bud: ship-only pins skip
OWN = 'SetAttribute("WE_Build", 206)' in read(S + "Services/DataService.luau")  # this build's own scope
CURRENT_BUILD = int((re.search(r'WE_Build", (\d+)\)', read(S + "Services/DataService.luau")) or [0, "0"])[1])

for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 213'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 213'),
    (S + "Services/DataService.luau", "WE_Build=213"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 213'),
):
    check(BUD or needle in read(rel), "CODEBOT v206: WE_Build=213 " + rel.rsplit("/", 1)[-1] + (" [bud: skipped]" if BUD else ""))

# ── the 300 s delay (one value) ──
MON = read(C + "MonetizationConfig.luau")
s5 = MON.split("(MonetizationConfig :: any).Starter5 = {")[1].split("\n}\n")[0] if "(MonetizationConfig :: any).Starter5 = {" in MON else ""
m = re.findall(r"\n\tOfferAfterPlaySeconds = (\d+),", "\n" + s5)
check(len(m) == 1 and int(m[0]) == (120 if CURRENT_BUILD >= 209 else 300), "CODEBOT v206: Starter5.OfferAfterPlaySeconds is ONE value, 120 s in v209 (300 s through v208)")
check("OfferAfterPlaySeconds = 60," not in MON, "CODEBOT v206: no 60 s pop-up delay left in MonetizationConfig")
# Code Bot v207: Starter5 OwnerFirst true (owner-only) was v206 scope; v207 made it public (codebot_v207.py)
check("Enabled = true," in s5 and (("OwnerFirst = true, -- NEW-OWNER-FIRST" in s5) if OWN else True), "CODEBOT v206: Starter5 Enabled" + (" + OwnerFirst kept (owner-only)" if OWN else " [OwnerFirst pin: v206 scope]"))
check('StarterRecruit5 = { Id = 3715888533, DisplayName = "Recruit Starter Pack", RobuxPrice = 5,' in MON and 'LiveBlock = "Starter5"' in MON
      and 'Boost2x10m = { Id = 3715888566, DisplayName = "2x Income 10 min", RobuxPrice = 5,' in MON,
      "CODEBOT v206: the two 5 R$ rows keep their Ids, 5 R$ and LiveBlock Starter5")

# ── the sort (static) ──
SC = read(SHOP)
blk = SC.split("local function applyPriceOrder()", 1)[1].split("\n\tapplyPriceOrder()\n", 1)[0] if "local function applyPriceOrder()" in SC else ""
check("local function rowRobuxPrice(rowKey: string): number" in SC and "MonetizationConfig.GamePasses :: any)[string.sub(rowKey, 6)]" in SC
      and "MonetizationConfig.DevProducts :: any)[rowKey]" in SC and "tonumber(def.RobuxPrice)" in SC,
      "CODEBOT v206: the row price is MonetizationConfig RobuxPrice (pass rows Pass_<key>, product rows <key>)")
check("return if p and p > 0 then p else SORT_NO_PRICE" in SC and "local SORT_NO_PRICE = 1e9" in SC,
      "CODEBOT v206: a row with no Robux price sorts to the bottom")
check("return a.Price < b.Price" in blk and "return not a.Owned" in blk and "return a.Base < b.Base" in blk,
      "CODEBOT v206: price ascending, then unowned before OWNED, then the build order")
check("it.Row.LayoutOrder = i" in blk and "for _, r in ipairs(builtRows) do" in blk, "CODEBOT v206: every SUPPLY row gets its sorted LayoutOrder")
check(SC.count("\n\tapplyPriceOrder()\n") == 1 and "applyPriceOrder() -- Code Bot v206: an OWNED row moves" in SC,
      "CODEBOT v206: sorted once after the build and again on every OWNED refresh")
check("Price" not in blk.replace("Price = rowRobuxPrice(r.Key)", "").replace("a.Price", "").replace("b.Price", "").replace("Price: number", ""),
      "CODEBOT v206: the sort never writes a price")
check("SetAttribute" not in blk and "Text" not in blk and "promptDevProduct" not in blk, "CODEBOT v206: the sort only moves rows (no text / prompt)")
if not BUD and OWN:
    prev_sc = shipped(SHOP, PREV) or ""
    cut = lambda t: re.sub(r"\n\t-- Code Bot v206 \(Shaun\): the SUPPLY.*?\n\tapplyPriceOrder\(\)\n", "", t, flags=re.S).replace(
        "\t\tapplyPriceOrder() -- Code Bot v206: an OWNED row moves after the unowned rows at its price\n", "")
    check(prev_sc != "" and cut(SC) == prev_sc, "CODEBOT v206: ShopController identical to " + PREV + " outside the sort block (rows / gates / prompts unchanged)")

# ── no price changed ──
now_p, prev_mon = prices(MON), shipped(C + "MonetizationConfig.luau", PREV)
_blk = MON.split("\n\tGamePasses = {", 1)[1].split("\n\tCounterGrants", 1)[0]
check(len(now_p) == len(re.findall(r"\bRobuxPrice = \d+", _blk)) + len(re.findall(r"OverhaulRobuxPrice = \d+", _blk)) and now_p[("DevProducts", "StarterRecruit5")] == 5 and now_p[("GamePasses", "VIP")] == 199, "CODEBOT v206: price parser sees every SKU (%d)" % len(now_p))
if prev_mon is not None:
    check(prices(prev_mon) == now_p, "CODEBOT v206: every RobuxPrice identical to " + PREV + " (no price change)")
    if not BUD and OWN:
        a, b = prev_mon.split("\n"), MON.split("\n")
        diff = [(x, y) for x, y in zip(a, b) if x != y]
        check(len(a) == len(b) and len(diff) == 1 and diff[0][0].strip().startswith("OfferAfterPlaySeconds = 60,")
              and diff[0][1].strip().startswith("OfferAfterPlaySeconds = 300,"),
              "CODEBOT v206: MonetizationConfig vs " + PREV + ": only the Starter5 delay line changed")
        for rel in (C + "ShopOverhaulConfig.luau", "src/ReplicatedStorage/Shared/Util/LivePrices.luau", S + "Services/MonetizationService.luau",
                    S + "Services/RecruitPackService.luau", C + "EconomyConfig.luau", S + "Modules/ProfileSchema.luau"):
            check(shipped(rel, PREV) == read(rel), "CODEBOT v206: " + rel.rsplit("/", 1)[-1] + " byte-identical to " + PREV)
        _pds = shipped(S + "Services/DataService.luau", PREV) or ""
        check(_pds.replace('WE_Build", 205)', 'WE_Build", 206)').replace("WE_Build=205", "WE_Build=206") == read(S + "Services/DataService.luau"),
              "CODEBOT v206: DataService: only the WE_Build number changed (save keys kept)")

# ── executed: the real ShopController in Luau (owner + another player; sorted, 5 R$ on top for the owner only) ──
r = subprocess.run([sys.executable, "tools/sim/run_shop_render_test.py"], capture_output=True, text=True, cwd=ROOT,
                   env=dict(os.environ, VERBOSE="1"))
out = r.stdout or ""
check(r.returncode == 0 and out.count("SHOP RENDER TEST") == 6 and "FAIL " not in out, "CODEBOT v206: run_shop_render_test 0 failed (6 runs)")
check((out.count("SUPPLY rows sorted by Robux price ascending, no-price rows last") == 6 and out.count("ok    uid 470626172: the two 5 R$ rows are the top two rows") == 3) if OWN else True,
      "CODEBOT v206: sim: every run sorted ascending; the owner's top two rows are the 5 R$ rows")
check(("ok    uid 9: the 5 R$ rows only where Starter5 is live (owner-only): false" in out) if OWN else True, "CODEBOT v206: sim: no 5 R$ row for another player (owner-only kept)" + ("" if OWN else " [v206 scope; v207: FREE top + public]"))
r = subprocess.run([sys.executable, "tools/sim/run_starter5_test.py"], capture_output=True, text=True, cwd=ROOT)
check(r.returncode == 0 and "STARTER5 TEST: 0 failed" in (r.stdout or ""), "CODEBOT v206: run_starter5_test 0 failed")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v206: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v206: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v206: StreamingEnabled stays OFF")
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
check(r.returncode == 0 and not [n for n in (r.stdout or "").splitlines() if "WE_Building" in n], "CODEBOT v206: no WE_Building* diffs vs " + PREV)
