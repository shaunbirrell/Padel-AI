# Code Bot Roblox v156 (2026-10-01, Shaun's phone screenshots):
#  1. Price mismatch: the Supply Depot said "Commander Starter Pack  149 R$", Roblox's prompt "Commander Starter Bundle 249".
#     Root cause: every Shop / Supply Depot / stand / offer price was the hand-typed MonetizationConfig RobuxPrice (the v71
#     D2 repricing to 149 never reached the Creator Hub). Now Shared/Util/LivePrices: MarketplaceService:GetProductInfo on
#     the server (cached, published on ReplicatedStorage), config value only as the fallback. Audit (public Roblox APIs,
#     2026-10-01 00:15 Dublin): 2 mismatches, both dev products: StarterBundle (config 149 "Commander Starter Pack" vs
#     Roblox 249 "Commander Starter Bundle") and ExtraSoldierSlot (config 99 "Army Expansion (+10)" vs Roblox 79 "Extra
#     Soldier Slot"). The config fallbacks now equal Roblox. No Creator Hub price was changed.
#  2. Plain player text on every Robux row (no "ProcessReceipt only"); phone-width budget checked by the Shop render test.
#  3. ARMY KILLS board live for everyone (LeaderboardConfig.ArmyKillsBoardLive), army orders stay owner-first; kills from
#     the army's normal fire count; admin / owner stay off every board.
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def block(text, key):
    m = re.search(r"(?m)^\s*" + re.escape(key) + r"\s*=\s*\{", text)
    if not m:
        return ""
    depth = 0
    for i in range(m.end() - 1, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[m.end():i]
    return ""


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/"

# build pins
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 207)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 207)'),
    (S + "Services/DataService.luau", "WE_Build=207"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 207)'),
):
    check(needle in read(rel), "CODEBOT v156: WE_Build=207 " + rel.rsplit("/", 1)[-1])

# 1. the live price cache
LP = read("src/ReplicatedStorage/Shared/Util/LivePrices.luau")
check("MarketplaceService:GetProductInfo(id, infoType)" in LP and "pcall(function()" in LP, "CODEBOT v156: LivePrices asks GetProductInfo (pcall'd)")
check("Enum.InfoType.GamePass" in LP and "Enum.InfoType.Product" in LP, "CODEBOT v156: LivePrices looks up passes and dev products")
check('PricePrefix = "WE_Px_"' in LP and 'NamePrefix = "WE_PxN_"' in LP and "ReplicatedStorage:SetAttribute(LivePrices.PricePrefix" in LP,
      "CODEBOT v156: LivePrices publishes the cache on ReplicatedStorage")
check("RefreshSeconds = 600" in LP and "if started or not RunService:IsServer() then" in LP, "CODEBOT v156: one cache per server, refreshed every 10 min")
check("return math.max(0, math.floor(tonumber(d and d.RobuxPrice) or 0))" in LP, "CODEBOT v156: the config RobuxPrice is only the fallback")
MS = read(S + "Services/MonetizationService.luau")
check("LivePrices.StartServer()" in MS, "CODEBOT v156: MonetizationService.Init starts the price cache")
check('RobuxPrice = LivePrices.Price("DevProduct", "StarterBundle")' in MS and 'DisplayName = LivePrices.Name("DevProduct", "StarterBundle")' in MS,
      "CODEBOT v156: the 2-minute Starter offer sends the real price and name")
check("tostring(dc.RobuxPrice)" not in MS and "tostring(ba.RobuxPrice)" not in MS and "tostring(ex.RobuxPrice)" not in MS,
      "CODEBOT v156: moment offers use the real price")
SC = read(CL + "ShopController.luau")
check("ProcessReceipt only" not in SC, "CODEBOT v156: no developer text in the Shop")
check('local robux = LivePrices.Price("DevProduct", key)' in SC and 'local robux = LivePrices.Price("GamePass", key)' in SC,
      "CODEBOT v156: Supply Depot dev / pass rows show the real price")
check('local displayName = LivePrices.Name("DevProduct", "StarterBundle")' in SC and 'LivePrices.ForOffer("DevProduct", "StarterBundle", p.RobuxPrice)' in SC,
      "CODEBOT v156: the Starter Pack offer card shows the Roblox name and real price")
check(SC.count("LivePrices.ForOffer(") >= 6, "CODEBOT v156: every offer card reads the real price")
check("LivePrices.Changed(applyLivePrices)" in SC, "CODEBOT v156: rows built before the lookup take the live price")
check("tonumber(def.RobuxPrice)" not in SC.split("local function sortedKeys", 1)[0].split("local function addDevRow", 1)[-1],
      "CODEBOT v156: the dev row never prints the config price")
check("LivePrices.Price(kind, key)" in read(S + "Modules/PurchaseStands.luau"), "CODEBOT v156: purchase stands show the real price")

# the audited Creator Hub prices (public Roblox APIs, 2026-10-01): config fallback == Roblox for every live Id
REAL = {
    "GamePasses": {
        "VIP": (1985475542, 199), "WarChest": (2002640637, 799), "SuperSoldiers": (1998231741, 349), "DoubleHP": (2002214665, 199),
        "DoubleCash": (1982865711, 149), "DoubleXP": (1982487698, 99), "ExtraPlotCosmetic": (1983357731, 79),
        "AutoCollect": (1985115501, 99), "ImpulseSpeed": (1998656357, 99), "PV_Razorfang": (2002484380, 199),
        "PV_Warlord": (2001320428, 799), "PV_Stormwing": (2001722392, 999), "PV_Tidebreaker": (1999263465, 299),
        "PV_Skylance": (2001602422, 899), "BiggerArmy": (2001734404, 249), "ExtraGarageSlot": (1999359549, 199),
        "PV_Leviathan": (2001398410, 1199), "PG_Sovereign": (2002154652, 99), "PG_Quake": (2003492417, 249),
        "PG_Longshot": (2003180431, 299), "PG_Havoc": (2002250646, 349), "PG_Thunderhead": (1999305818, 399),
        "PG_Tempest": (2002682646, 499), "PG_ArmoryPass": (2002868467, 1299),
    },
    "DevProducts": {
        "CashSmall": (3713838744, 49), "CashMedium": (3713838815, 149), "CashLarge": (3713838888, 399),
        "CashMega": (3713838952, 799), "GoldSmall": (3713839003, 49), "GoldMedium": (3713839048, 149),
        "GoldLarge": (3713839090, 349), "PremiumPass": (3713839151, 499), "ExtraSoldierSlot": (3713839210, 79),
        "InstantBarracks": (3713839278, 129), "SpeedBoost": (3713839342, 99), "StarterBundle": (3713839505, 249),
        "RebirthKeepBase": (3714663721, 50), "GoldenPumpjack": (3714663783, 49), "SoldierRefill": (3715442523, 49),
        "PlazaAirstrike": (3715442542, 79),
    },
}
MC = read(C + "MonetizationConfig.luau")
for sect, items in REAL.items():
    body = block(MC, sect)
    for key, (pid, price) in items.items():
        b = block(body, key)
        mi = re.search(r"\bId\s*=\s*(\d+)", b)
        mp = re.search(r"\bRobuxPrice\s*=\s*(\d+)", b)
        check(mi is not None and int(mi.group(1)) == pid and mp is not None and int(mp.group(1)) == price,
              "CODEBOT v156: %s.%s Id %d, config fallback %d R$ == Roblox" % (sect, key, pid, price))
check('DisplayName = "Commander Starter Bundle",' in block(block(MC, "DevProducts"), "StarterBundle"), "CODEBOT v156: Starter display name = the Roblox product name")
check('"Unlock premium rewards on every Battle Pass tier"' in MC and '"$50,000 cash plus Auto Collect forever"' in MC, "CODEBOT v156: plain descriptions")
# no product Id changed since the v155 tip; the only RobuxPrice lines changed are the two corrected fallbacks
try:
    d = subprocess.run(["git", "diff", "-U0", "2dc0534", "--", C + "MonetizationConfig.luau"], capture_output=True, text=True).stdout
    lines = [l for l in d.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
    # claude-bud JOB 41 part B: retired the unfiltered form (the brief adds ONE new SKU row, RecruitPack = { Id = 0, 49 R$ });
    # replacement: the same two checks with that one new row left out (its Id 0 / 49 are pinned in claude_bud_job41.py)
    #check(not any(re.search(r"(^|[\s{,])Id\s*=\s*\d", l) for l in lines), "CODEBOT v156: no product Id changed since v155")
    # claude-bud JOB 42: + the five new time-pack rows (Cash15m .. Cash4h, all Id 0; pinned in claude_bud_job42.py)
    # codebot_v167: + their Creator Hub Ids (were 0; pinned in codebot_v167.py)
    lines = [l for l in lines if not (l.startswith("+") and (re.search(r"RecruitPack = \{ Id = (0|3715776659),", l) or re.search(r"Cash(15m|30m|1h|2h|4h) = \{ Id = (0|\d{10}),", l)))]
    # claude-bud JOB 49: + the two DISABLED sidegrade rows (OfflineCap2x / MissionReroll: Id 0, no price; pinned in claude_bud_job49.py)
    lines = [l for l in lines if not (l.startswith("+") and re.search(r"(OfflineCap2x|MissionReroll) = \{ Id = 0,", l))]
    # Code Bot v180: the two wired items (GamePasses.OfflineCap2x 2002664894 / 149, DevProducts.MissionReroll 3715836569 / 19)
    # + PurchaseSources.missions: the lines v180 added vs its base 5e9649b are left out (pinned in codebot_v180.py)
    _v180 = set(l for l in subprocess.run(["git", "diff", "-U0", "5e9649b", "--", C + "MonetizationConfig.luau"], capture_output=True, text=True).stdout.splitlines() if l.startswith("+") and not l.startswith("+++"))
    lines = [l for l in lines if l not in _v180]
    check(not any(re.search(r"(^|[\s{,])Id\s*=\s*\d", l) for l in lines), "CODEBOT v156: no product Id changed since v155 (claude-bud JOB 41: the new RecruitPack row aside)")
    pr = sorted(re.sub(r"\s+", " ", l.split("--")[0]).strip() for l in lines if re.search(r"(?<!Overhaul)RobuxPrice\s*=", l))
    check(pr in ([], sorted(["- RobuxPrice = 149,", "- RobuxPrice = 99,", "+ RobuxPrice = 249,", "+ RobuxPrice = 79,"])),
          "CODEBOT v156: only the StarterBundle / ExtraSoldierSlot fallbacks changed (" + "; ".join(pr) + ")")
except Exception:
    pass

# 3. the ARMY KILLS board
LB = read(C + "LeaderboardConfig.luau")
check("LeaderboardConfig.ArmyKillsBoardLive = true" in LB and "AOC.LiveForAll()" not in LB, "CODEBOT v156: ARMY KILLS board live for everyone (own switch)")
check('{ Id = "Army", Title = "TOP ARMY"' in LB, "CODEBOT v156: TOP ARMY stays defined (switch off = the old board)")
ES = read(S + "Services/EngagementService.luau")
nak = ES.split("function EngagementService.NoteArmyKill", 1)[1].split("\nend", 1)[0]
check("LeaderboardConfig.ArmyKillsBoardLive ~= true" in nak and "AOC.LiveFor" not in nak, "CODEBOT v156: army kills count for everyone (not only army-orders players)")
check("if isBoardExcluded(player.UserId) then" in ES and "not isBoardExcluded(uid)" in ES, "CODEBOT v156: admin / owner stay off the boards")
check('_info.WeaponId == "Squad"' in ES and "info.ByUnit == true" in ES, "CODEBOT v156: player + guard kills by the army credit the board")
check("OwnerFirst = false," in block(read(C + "ArmyOrdersConfig.luau"), "Live"), "CODEBOT v156: army orders live for everyone (v166 flip-all-live)")

# owner-first rails unchanged
for rel, key, label in ((C + "EndgameConfig.luau", "Live", "Endgame"), (C + "GuardConfig.luau", "Posts", "GuardConfig.Posts"),
                        (C + "MonetizationConfig.luau", "cfg.SpeedV2", "SpeedV2")):
    check("OwnerFirst = false," in block(read(rel), key), "CODEBOT v156: " + label + " OwnerFirst=false (v166 flip-all-live)")
check(re.search(r"Live\s*=\s*\{[^}]*OwnerFirst\s*=\s*false\s*,", read(C + "BaseMarkerConfig.luau"), re.S) is not None, "CODEBOT v156: BaseMarker stays live for everyone (v155)")

# the real ShopController in the Luau CLI: every row's text / price at phone width, the live price refresh
luau = os.environ.get("LUAU")
if luau is None and os.environ.get("LUAU_COMPILE"):
    cand = os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    luau = cand if os.path.isfile(cand) else None
if luau:
    r = subprocess.run([sys.executable, "tools/sim/run_shop_render_test.py"], capture_output=True, text=True, env=dict(os.environ, LUAU=luau))
    check(r.returncode == 0 and "SHOP RENDER TEST uid 9: 0 failed" in r.stdout and "SHOP RENDER TEST uid 470626172: 0 failed" in r.stdout,
          "CODEBOT v156: run_shop_render_test.py (real prices / names / plain text / phone width)")
