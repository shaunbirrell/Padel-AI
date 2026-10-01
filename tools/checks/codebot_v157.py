# Code Bot Roblox v157 (2026-10-01, owner-approved): the weekly Black Market is live for EVERY player while every other
# Endgame part stays owner-first (UserId 470626172 + Studio).
#  1. EndgameConfig.PublicParts = { BlackMarket = true }: LiveFor skips the owner-first rule for a public part only
#     (Live.Enabled and the part's own Parts switch still turn it off for everyone). Live.OwnerFirst stays true.
#  2. The camo wear path (CamoFor / EquipCamo) is live with Mastery OR the Black Market; without the Armory only the
#     Black Market camos (Urban / Tiger / Gold) show or go on. Buying at the Armory stays Mastery-only. A Black Market
#     camo goes on the gun in his hand when bought; the Black Market list has PUT ON / TAKE OFF rows for it.
#  3. Banners show on the gate posts below Tier 4 (the base-tier look is built for a banner alone); berets / paint
#     already follow the equipped item with no other part.
#  4. The stall on SW_S1's upper floor gets its own BLACK MARKET door sign while the Armory downstairs is not live.
# Runtime proof: tools/sim/run_blackmarket_public_test.py (real config / service / client list / base builder).
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 179)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 179)'),
    (S + "Services/DataService.luau", "WE_Build=179"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 179)'),
):
    check(needle in read(rel), "CODEBOT v157: WE_Build=179 " + rel.rsplit("/", 1)[-1])

# 1. the gate
EC = read(C + "EndgameConfig.luau")
live = block(EC, "Live")
check("Enabled = true," in live and "OwnerFirst = false," in live, "CODEBOT v157: EndgameConfig.Live Enabled + OwnerFirst=false (v166 flip-all-live) (every other part owner-only)")
pub = block(EC, "PublicParts")
pub_on = re.findall(r"(?m)^\s*(\w+)\s*=\s*true\b", pub)
check(pub_on == ["BlackMarket"], "CODEBOT v157: PublicParts = { BlackMarket = true } only (" + ",".join(pub_on) + ")")
parts = block(EC, "Parts")
check(re.search(r"(?m)^\s*BlackMarket\s*=\s*true,", parts) is not None, "CODEBOT v157: Parts.BlackMarket stays true")
lf = EC.split("function EndgameConfig.LiveFor", 1)[1].split("\nend", 1)[0]
check("if parts[part] ~= true then" in lf and "pub[part] == true and EndgameConfig.Live.Enabled == true" in lf
      and "return RetentionConfig.Live(EndgameConfig.Live, userId)" in lf, "CODEBOT v157: LiveFor = part on AND (public + Enabled OR the owner-first rule)")
al = EC.split("function EndgameConfig.AnyLiveFor", 1)[1].split("\nend", 1)[0]
check("EndgameConfig.LiveFor(userId, part)" in al, "CODEBOT v157: AnyLiveFor asks LiveFor per part (a public part counts)")
check('return EndgameConfig.LiveFor(userId, "Mastery") or EndgameConfig.LiveFor(userId, "BlackMarket")' in EC, "CODEBOT v157: CamoLiveFor = Mastery or Black Market")

# 2. the server: every purchase still gated per part; camo wear path; market camo auto-equip
ES = read(S + "Services/EndgameService.luau")
plan = ES.split("function EndgameService._Plan", 1)[1].split("\nfunction EndgameService.Purchase", 1)[0]
for kind, part in (("Elite", "Elite"), ("Workshop", "Workshop"), ("Warhead", "Warheads"), ("Heist", "Heist"), ("Market", "BlackMarket"),
                   ("Claim", "Contracts"), ("Heal", "Hospital"), ("Retrain", "Elite"), ("Empire", "EmpireLevel"), ("Tier", "BaseTier"),
                   ("Defence", "Defence"), ("Rebuild", "Defence")):
    seg = plan.split('kind == "%s"' % kind, 1)[1][:400] if ('kind == "%s"' % kind) in plan else ""
    check('EndgameConfig.LiveFor(uid, "%s")' % part in seg, "CODEBOT v157: purchase kind %s gated by Parts.%s" % (kind, part))
check('local masteryLive = EndgameConfig.LiveFor(uid, "Mastery")' in plan
      and 'if not masteryLive and not (kind == "EquipCamo" and EndgameConfig.CamoLiveFor(uid)) then' in plan,
      "CODEBOT v157: Mastery / Attach / Camo buys stay Armory-only; EquipCamo also with the Black Market")
check('if camo ~= "None" and not masteryLive and EndgameConfig.MarketCamos()[camo] == nil then' in plan, "CODEBOT v157: without the Armory only Black Market camos go on")
cf = ES.split("function EndgameService.CamoFor", 1)[1].split("\nend", 1)[0]
check("EndgameConfig.CamoLiveFor(player.UserId)" in cf and "EndgameConfig.MarketCamos()[eq] == nil" in cf, "CODEBOT v157: CamoFor shows Black Market camos without the Armory")
check('table.find(ownedGuns(player), held) ~= nil' in plan and "cc.Equip[held] = item.Camo" in plan, "CODEBOT v157: a bought Black Market camo goes on the owned gun in his hand")
check('or key == "camo_equip" or key == "market" then' in ES, "CODEBOT v157: a market buy re-syncs the drawn gun's camo")
check("if not EndgameService.AtStation(player, \"BlackMarket\") then" in plan and "if EndgameService.RecentlyHurt(player) then" in plan, "CODEBOT v157: market buys need the stall, not hurt")
pur = ES.split("function EndgameService.Purchase", 1)[1].split("\nend\n", 1)[0]
check("eco.SpendGold(player, price, \"endgame_\" .. key)" in pur and "eco.SpendCash(player, price, \"endgame_\" .. key)" in pur, "CODEBOT v157: Gold slot = SpendGold, Cash slots = SpendCash (never Robux)")
check("Endgame" not in read(S + "Services/MonetizationService.luau"), "CODEBOT v157: no Robux path to the Black Market")
check("Held = held, HeldName =" in ES and "Camos = camoRows }" in ES, "CODEBOT v157: State.Market carries the held gun and his Black Market camos")
# codebot_v171: the early-return line also checks the Recruit trim (`and not recruit`); the pin follows it
check("if tier <= 0 and not crest and not trophy and banner == nil and not recruit then" in ES, "CODEBOT v157: a banner alone builds the base look")
BTB = read(S + "Modules/BaseTierBuilder.luau")
check('m.Name = "MarketBanners"' in BTB and "if ctx.BannerColor and t < 4 then" in BTB, "CODEBOT v157: Black Market banners on the gate posts below Tier 4")

# 3. the client
CT = read(CL + "EndgameController.luau")
check('local want = live and EndgameConfig.LiveFor(player.UserId, st.Part)' in CT, "CODEBOT v157: stations are built per part (only the Black Market for others)")
check('if st and EndgameConfig.LiveFor(player.UserId, st.Part) then' in CT, "CODEBOT v157: the EMPIRE list shows only live stations")
check('Kind = "EquipCamo", Id = held .. ":" ..' in CT, "CODEBOT v157: Black Market list PUT ON / TAKE OFF for his camo")
check('if not EndgameConfig.LiveFor(player.UserId, "Mastery") then\n\t\tdoorSign(m, house, st.Sign)' in CT, "CODEBOT v157: BLACK MARKET door sign while the Armory is not live")

# rails unchanged
for rel, key, label in ((C + "GuardConfig.luau", "Posts", "GuardConfig.Posts"), (C + "MonetizationConfig.luau", "cfg.SpeedV2", "SpeedV2"),
                        (C + "ArmyOrdersConfig.luau", "Live", "ArmyOrders")):
    check("OwnerFirst = false," in block(read(rel), key), "CODEBOT v157: " + label + " OwnerFirst=false (v166 flip-all-live)")

# the real code in the Luau CLI
luau = os.environ.get("LUAU")
if luau is None and os.environ.get("LUAU_COMPILE"):
    cand = os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    luau = cand if os.path.isfile(cand) else None
if luau:
    r = subprocess.run([sys.executable, "tools/sim/run_blackmarket_public_test.py"], capture_output=True, text=True, env=dict(os.environ, LUAU=luau))
    check(r.returncode == 0 and "BLACK MARKET PUBLIC TEST: 0 failed" in r.stdout,
          "CODEBOT v157: run_blackmarket_public_test.py (non-owner sees the Black Market only; buys, camo / beret / banner apply)")
