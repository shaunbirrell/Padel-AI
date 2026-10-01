# claude-bud JOB 66 (2026-10-01): the two 5 R$ starter products (Recruit Starter Pack one-time, 10-minute 2x income
# boost), the one-time offer at ~5 min, the HUD boost chip. Owner-first. Executed inside tools/BuyPathStatic.py.
import os as _j66_os
import subprocess as _j66_sp
import sys as _j66_sys
from pathlib import Path as _J66P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j66_src(p):
    q = _J66P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_MC = _j66_src("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
(ok if ('StarterRecruit5 = { Id = 0, DisplayName = "Recruit Starter Pack", RobuxPrice = 5,' in _MC and 'Boost2x10m = { Id = 0, DisplayName = "2x Income 10 min", RobuxPrice = 5,' in _MC) else bad)(
    "CLAUDE-BUD J66: both products are 5 R$ (Shaun approved) and Id 0 until created")
_s5 = _MC.split("Starter5 = {")[1].split("\n}\n")[0] if "Starter5 = {" in _MC else ""
(ok if ("Enabled = true," in _s5 and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _s5 and "OfferAfterPlaySeconds = 300," in _s5) else bad)("CLAUDE-BUD J66: MonetizationConfig.Starter5 is owner-first; the offer at 5 min")
(ok if "if row and typeof(row.LiveBlock) == \"string\" then" in _MC else bad)("CLAUDE-BUD J66: SkuLiveFor follows a row's owner-first switch (Shop + purchase intent)")
_MS = _j66_src("src/ServerScriptService/Server/Services/MonetizationService.luau")
_pr = _MS.split("local function processReceipt")[1] if "local function processReceipt" in _MS else ""
_g = _pr.split("-- claude-bud JOB 66: the 5 R$ products.")[1].split("-- claude-bud JOB 41 part B")[0] if "-- claude-bud JOB 66: the 5 R$ products." in _pr else ""
(ok if ("SS.GrantFree, player" in _g and 'EconomyService.AddCash(player, cash, "devproduct")' in _g and "CS.GrantCashBoost, player, product.GrantsCashBoostMinutes" in _g
    and _pr.index("-- claude-bud JOB 66: the 5 R$ products.") < _pr.index("markProcessed(profile, receiptId)")) else bad)(
    "CLAUDE-BUD J66: the receipt grants soldiers (army cap), cash as devproduct (never multiplied) and the boost (one boost path), before markProcessed")
_RP = _j66_src("src/ServerScriptService/Server/Services/RecruitPackService.luau")
(ok if ('profile.Starter5Offered = true' in _RP and 'AfterSeconds = if s5 then MC.Starter5.OfferAfterPlaySeconds else nil' in _RP) else bad)(
    "CLAUDE-BUD J66: the 5 R$ offer rides the Recruit Pack offer path (slot budget, onboarding / combat guards, shown-ack) with its own once flag")
_PS = _j66_src("src/ServerScriptService/Server/Modules/ProfileSchema.luau")
(ok if "profile.Starter5Offered = if profile.Starter5Offered == true then true else nil" in _PS else bad)("CLAUDE-BUD J66: the offer flag is a sanitised save key (no wipe)")
_H = _j66_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController.luau")
(ok if ('bc.Name = "BoostChip"' in _H and "Starter5LiveFor(player.UserId)" in _H and "RenderStepped" not in _H.split("local function refreshBoost")[1].split("\nend\n")[0]) else bad)(
    "CLAUDE-BUD J66: the HUD boost chip (2x m:ss) is owner-first and ticks 1 Hz only while a boost runs")
_e = dict(_j66_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j66_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j66_sp.run([_j66_sys.executable, "tools/sim/run_starter5_test.py"], capture_output=True, text=True, env=_e, timeout=150)
    (ok if (_r.returncode == 0 and "STARTER5 TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J66: run_starter5_test.py (rows, cash sizing, owner-first SKU, the 5-min one-time offer, others unchanged)")
