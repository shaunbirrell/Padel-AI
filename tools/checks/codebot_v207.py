# Code Bot Roblox v207 (2026-10-02, Shaun approved, LIVE FOR EVERYONE):
# 1. Supply Depot 'SUPPLY · R$' tab: the FREE rows (FREE · Daily Reward, FREE · Airdrop, FREE · Invite friends; and
#    FREE · Join our group when a GroupId is set) back on TOP in their build order, then the paid rows cheapest first
#    (v206 sort), then the rows with no price (Favorite WAR EMPIRE, the locked Supply Crate) at the bottom.
# 2. The two 5 R$ offers public: MonetizationConfig.Starter5.OwnerFirst = false (StarterRecruit5 'Recruit Starter Pack'
#    3715888533 + Boost2x10m '2x Income 10 min' 3715888566, both LiveBlock = "Starter5"). The pop-up delay stays 300 s
#    and the one-time-per-player card (profile.Starter5Offered). No other OwnerFirst flag, no price changed.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* diffs.
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V207_PREV", "b95305c")  # v206 code tip (place 204)
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
OWN = 'SetAttribute("WE_Build", 207)' in read(S + "Services/DataService.luau")  # this build's own scope  # Code Bot v208: stays 207 (v207 scope only)
CURRENT_BUILD = int((re.search(r'WE_Build", (\d+)\)', read(S + "Services/DataService.luau")) or [0, "0"])[1])

for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 214'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 214'),
    (S + "Services/DataService.luau", "WE_Build=214"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 214'),
):
    check(BUD or needle in read(rel), "CODEBOT v207: WE_Build=214 " + rel.rsplit("/", 1)[-1] + (" [bud: skipped]" if BUD else ""))

# ── 2. the two 5 R$ offers public ──
MON = read(C + "MonetizationConfig.luau")
s5 = MON.split("(MonetizationConfig :: any).Starter5 = {")[1].split("\n}\n")[0] if "(MonetizationConfig :: any).Starter5 = {" in MON else ""
check("Enabled = true," in s5 and re.search(r"\n\tOwnerFirst = false, -- PUBLIC \(Code Bot v207", "\n" + s5) is not None
      and "OwnerFirst = true" not in s5, "CODEBOT v207: Starter5 Enabled, OwnerFirst = false (public for every player)")
m = re.findall(r"\n\tOfferAfterPlaySeconds = (\d+),", "\n" + s5)
check(len(m) == 1 and int(m[0]) == (120 if CURRENT_BUILD >= 209 else 300), "CODEBOT v207: Starter5 pop-up delay is 120 s in v209 (300 s through v208)")
check('StarterRecruit5 = { Id = 3715888533, DisplayName = "Recruit Starter Pack", RobuxPrice = 5,' in MON
      and 'Boost2x10m = { Id = 3715888566, DisplayName = "2x Income 10 min", RobuxPrice = 5,' in MON
      and MON.count('LiveBlock = "Starter5"') == 2, "CODEBOT v207: both rows keep Id, 5 R$ and LiveBlock Starter5 (follow the public switch)")
_sr5 = [l for l in MON.split("\n") if "StarterRecruit5 = { Id = 3715888533" in l]
check(len(_sr5) == 1 and "OneTime = true" in _sr5[0], "CODEBOT v207: Recruit Starter Pack stays OneTime")
RP = read(S + "Services/RecruitPackService.luau")
check("profile.Starter5Offered = true" in RP and "Offered = if s5 then profile.Starter5Offered == true" in RP,
      "CODEBOT v207: the 5 R$ card is still once per player (profile.Starter5Offered)")
RC = read(C + "RetentionConfig.luau")
check("if block.OwnerFirst ~= true then\n\t\treturn true" in RC, "CODEBOT v207: RetentionConfig.Live: OwnerFirst false = live for everyone")

# ── 1. the order (static) ──
SC = read(SHOP)
blk = SC.split("local function applyPriceOrder()", 1)[1].split("\n\tapplyPriceOrder()\n", 1)[0] if "local function applyPriceOrder()" in SC else ""
tier = SC.split("local function rowTier(rowKey: string): number", 1)[1].split("\n\tend\n", 1)[0] if "local function rowTier(" in SC else ""
check('string.sub(rowKey, 1, 3) == "fr_" and rowKey ~= "fr_favorite"' in tier and "return 0" in tier
      and "return if rowRobuxPrice(rowKey) < SORT_NO_PRICE then 1 else 2" in tier,
      "CODEBOT v207: rowTier: FREE fr_* rows 0 (not Favorite), paid 1, no-price 2")
_ti, _pi = blk.find("if a.Tier ~= b.Tier then"), blk.find("if a.Price ~= b.Price then")
check(0 <= _ti < _pi and "return a.Tier < b.Tier" in blk and "return a.Price < b.Price" in blk and "return not a.Owned" in blk
      and "return a.Base < b.Base" in blk and "Tier = rowTier(r.Key)" in blk,
      "CODEBOT v207: sort = tier (FREE, paid, no price), then price ascending, then unowned first, then build order")
for k in ("fr_daily", "fr_airdrop", "fr_invite", "fr_favorite"):
    check('"' + k + '", false)' in SC, "CODEBOT v207: row key " + k + " present")
check("SetAttribute" not in blk and "Text" not in blk and "promptDevProduct" not in blk, "CODEBOT v207: the sort only moves rows")
if not BUD and OWN:
    prev_sc = shipped(SHOP, PREV) or ""
    def cut(t):
        t = re.sub(r"\n\t-- Code Bot v207 \(Shaun\): the FREE rows.*?\n\tlocal rowBuildOrder", "\n\tlocal rowBuildOrder", t, flags=re.S)
        t = t.replace("Tier: number, ", "").replace("Tier = rowTier(r.Key), ", "")
        t = t.replace("\t\t\tif a.Tier ~= b.Tier then\n\t\t\t\treturn a.Tier < b.Tier -- Code Bot v207: FREE rows first, paid, then no-price rows\n\t\t\tend\n", "")
        return t
    check(prev_sc != "" and cut(SC) == prev_sc, "CODEBOT v207: ShopController identical to " + PREV + " outside the tier lines (rows / gates / prompts unchanged)")

# ── no price changed, only the one OwnerFirst line ──
now_p, prev_mon = prices(MON), shipped(C + "MonetizationConfig.luau", PREV)
check(now_p[("DevProducts", "StarterRecruit5")] == 5 and now_p[("DevProducts", "Boost2x10m")] == 5 and now_p[("GamePasses", "VIP")] == 199 and len(now_p) > 40,
      "CODEBOT v207: price parser sees every SKU (%d)" % len(now_p))
if prev_mon is not None:
    check(prices(prev_mon) == now_p, "CODEBOT v207: every RobuxPrice identical to " + PREV + " (no price change)")
    # Code Bot v210: the new owner-first GoldenBoost block (codebot_v210.py) is a later, separate flag, not a v207 flip
    _gb209 = MON.count("OwnerFirst = true, -- NEW-OWNER-FIRST (Code Bot v210)")
    # Code Bot v212: the new owner-first PremiumPads.BigSign block (codebot_v212.py) is a later, separate flag too
    _gb209 += MON.count("OwnerFirst = true, -- NEW-OWNER-FIRST (Code Bot board-text)")
    # Code Bot v213: GoldenBoost is now public; exclude that later public flip from this v207 scope pin.
    _later_public = MON.count("OwnerFirst = false, -- Code Bot v213: Shaun approved Golden Pumpjacks for everyone")
    check(prev_mon.count("OwnerFirst = true") - 1 == MON.count("OwnerFirst = true") - _gb209 and
          prev_mon.count("OwnerFirst = false") + 1 + _later_public == MON.count("OwnerFirst = false"),
          "CODEBOT v207: exactly one OwnerFirst flag flipped in its scope (later public flips excluded)")
    if not BUD and OWN:
        a, b = prev_mon.split("\n"), MON.split("\n")
        diff = [(x, y) for x, y in zip(a, b) if x != y]
        check(len(a) == len(b) and len(diff) == 1 and diff[0][0].startswith("\tOwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 66)")
              and diff[0][1].startswith("\tOwnerFirst = false, -- PUBLIC (Code Bot v207"),
              "CODEBOT v207: MonetizationConfig vs " + PREV + ": only the Starter5 OwnerFirst line changed")
        r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
        _ch = sorted(n for n in (r.stdout or "").splitlines() if n)
        _allowed = {C + "MonetizationConfig.luau", SHOP, S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"}
        check(r.returncode == 0 and set(_ch) <= _allowed, "CODEBOT v207: src diff vs " + PREV + " only config / shop / WE_Build pins: " + ", ".join(n.rsplit("/", 1)[-1] for n in _ch))
        for rel in (S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"):
            _p = shipped(rel, PREV) or ""
            check(_p.replace('WE_Build", 206)', 'WE_Build", 208)').replace("WE_Build=206", "WE_Build=214") == read(rel),
                  "CODEBOT v207: " + rel.rsplit("/", 1)[-1] + ": only the WE_Build number changed")
        # no other OwnerFirst flag anywhere in src
        r = subprocess.run(["git", "diff", "-U0", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
        _of = [l for l in (r.stdout or "").splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---")) and "OwnerFirst" in l]
        check(len(_of) == 2, "CODEBOT v207: the only OwnerFirst line changed in src is Starter5 (%d diff lines)" % len(_of))

# ── executed: the real ShopController (owner + another player) and the real RecruitPackService ──
r = subprocess.run([sys.executable, "tools/sim/run_shop_render_test.py"], capture_output=True, text=True, cwd=ROOT,
                   env=dict(os.environ, VERBOSE="1"))
out = r.stdout or ""
check(r.returncode == 0 and out.count("SHOP RENDER TEST") == 6 and "FAIL " not in out, "CODEBOT v207: run_shop_render_test 0 failed (6 runs)")
check(out.count("SUPPLY rows FREE first, then by Robux price ascending, no-price rows last") == 6,
      "CODEBOT v207: sim: every run FREE rows first, then ascending, then no-price rows")
check(out.count("FREE Daily Reward, FREE Airdrop, FREE Invite friends are the top rows") == 6, "CODEBOT v207: sim: the FREE rows on top (owner and uid 9)")
check(out.count("ok    uid 9: the 5 R$ rows only where Starter5 is live: true") == 3 and out.count("ok    uid 470626172: the 5 R$ rows only where Starter5 is live: true") == 3,
      "CODEBOT v207: sim: both 5 R$ rows shown to a non-owner (uid 9) and the owner")
check(out.count("ok    uid 9: the two 5 R$ rows are the first two paid rows") == 3, "CODEBOT v207: sim: non-owner: the 5 R$ rows right under the FREE rows")
r = subprocess.run([sys.executable, "tools/sim/run_starter5_test.py"], capture_output=True, text=True, cwd=ROOT, env=dict(os.environ, VERBOSE="1"))
o5 = r.stdout or ""
check(r.returncode == 0 and "STARTER5 TEST: 0 failed" in o5, "CODEBOT v207: run_starter5_test 0 failed")
check("ok    public: the owner AND every other player can see / buy them" in o5
      and ("ok    another player 1 s past the 120 s delay: the same 5 R$ ONE-TIME OFFER" if CURRENT_BUILD >= 209 else "ok    another player 1 s past the 300 s delay: the same 5 R$ ONE-TIME OFFER") in o5
      and "ok    another player: once shown, never again (one time per player)" in o5,
      "CODEBOT v207: sim: non-owner gets the 5 R$ card at the live delay, once")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v207: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v207: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v207: StreamingEnabled stays OFF")
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
check(r.returncode == 0 and not [n for n in (r.stdout or "").splitlines() if "WE_Building" in n], "CODEBOT v207: no WE_Building* diffs vs " + PREV)
