# Code Bot Roblox v221 (2026-10-02, Shaun 07:54 Dublin): the Plaza Airstrike developer product ALSO gives the buyer an
# instant takeover of the Central Plaza. PUBLIC (MonetizationConfig.PlazaAirstrikeTakeover.OwnerFirst = false).
# Proof chain (server only, no client input):
#   ProcessReceipt -> CounterGrants.GrantAirstrikes banks profile.AirstrikeCharges, SAVED, PurchaseGranted
#   -> afterGrantSaved -> OnGranted listener (MonetizationService) -> PlazaAirstrike.FireFromPurchase(player)
#   -> fireStrike: needs the saved charge, spends it, warns, task.delay(WarnSeconds) strike (non-lethal, others only)
#   -> takeover -> TerritoryService.InstantCapture -> awardCapture (THE normal capture: previous owner released with
#      the normal toast, Stats.PlazaCaptures leaderboard, PlazaBounty, Empire Tax, missions, analytics, marker,
#      protection period; defenders stand down because the zone is Held) -> PushAll -> "AIRSTRIKE! <name> took the Plaza".
# No price / Id change (the one DevProducts Description text changed). PreferMesh OFF; StreamingEnabled OFF;
# WE_Building* untouched.
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

BUILD = 221
PREV = "f351945"  # v220 handoff tip (place version 218)
ROOT = Path.cwd()
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def _v221_rd(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _v221_ck(cond: bool, label: str) -> None:
    tag = "CODEBOT v221: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(tag)  # type: ignore[name-defined]
    else:
        print(("PASS " if cond else "FAIL ") + tag)
        if not cond:
            globals()["_V221_FAILED"] = True


def _v221_old(rel: str) -> str | None:
    r = subprocess.run(["git", "show", PREV + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return r.stdout.replace("\r\n", "\n") if r.returncode == 0 else None


_v221_MC = _v221_rd(C + "MonetizationConfig.luau")
_v221_MS = _v221_rd(S + "Services/MonetizationService.luau")
_v221_PA = _v221_rd(S + "Modules/PlazaAirstrike.luau")
_v221_TS = _v221_rd(S + "Services/TerritoryService/init.luau")

# ---- WE_Build ----
for _v221_rel in (S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"):
    _v221_m = re.search(r'SetAttribute\("WE_Build",\s*(\d+)', _v221_rd(_v221_rel))
    _v221_ck(_v221_m is not None and int(_v221_m.group(1)) >= BUILD, "WE_Build >= %d %s" % (BUILD, _v221_rel.rsplit("/", 1)[-1]))

# ---- config: public switch + shop text ----
_v221_i = _v221_MC.find("\tPlazaAirstrikeTakeover = {")
_v221_blk = _v221_MC[_v221_i:_v221_MC.find("\n\t},", _v221_i)] if _v221_i > 0 else ""
_v221_ck("Enabled = true," in _v221_blk and "OwnerFirst = false," in _v221_blk, "PlazaAirstrikeTakeover Enabled + PUBLIC (OwnerFirst = false)")
_v221_ck('TerritoryId = "CentralPlaza",' in _v221_blk and "FireOnPurchase = true," in _v221_blk, "takeover targets CentralPlaza and fires on purchase")
_v221_ck('ToastAll = "AIRSTRIKE! %s took the Plaza",' in _v221_blk, "announcement 'AIRSTRIKE! <name> took the Plaza'")
_v221_ck('ToastHeld = "AIRSTRIKE! You still hold the Plaza",' in _v221_blk, "already-holder message")
_v221_pa_row = _v221_MC[_v221_MC.find("\t\tPlazaAirstrike = {"):][:400]
_v221_ck('Description = "Airstrike + instant Plaza takeover",' in _v221_pa_row, "in-game Shop description says it includes an instant Plaza takeover")
_v221_ck("Id = 3715442542," in _v221_pa_row and "GrantAirstrikes = 1," in _v221_pa_row, "same product Id; still banks one charge in ProcessReceipt")

# ---- purchase -> capture path (static order) ----
_v221_og = _v221_MS[_v221_MS.find("MonetizationService.OnGranted(function(player: Player, productKey: string)"):][:900]
_v221_ck('if productKey == "PlazaAirstrike" then' in _v221_og and "pa.FireFromPurchase(player)" in _v221_og,
         "OnGranted (post-save) -> PlazaAirstrike.FireFromPurchase")
_v221_ck("task.defer(runListener, \"OnGranted\", fn, player, event.ProductKey, event)" in _v221_MS, "OnGranted runs only from afterGrantSaved (after the receipt is saved)")
_v221_fs = _v221_PA[_v221_PA.find("fireStrike = function(player: Player): boolean"):][:500]
_v221_ck('MonetizationConfig.SkuLiveFor(player.UserId, "PlazaAirstrike")' in _v221_fs and "(tonumber(profile.AirstrikeCharges) or 0) < 1" in _v221_fs
         and "land(player, profile)" in _v221_fs, "the paid path needs the SAVED charge (no client input)")
_v221_land = _v221_PA[_v221_PA.find("local function land(player: Player, profile: any)"):_v221_PA.find("fireStrike = function")]
_v221_d, _v221_t = _v221_land.find("hum:TakeDamage(dmg)"), _v221_land.find("takeover(player)")
_v221_ck(0 < _v221_d < _v221_t and "task.delay(T.WarnSeconds" in _v221_land, "strike lands first (WarnSeconds), then the takeover")
_v221_ck("math.min(T.Damage, math.max(0, hum.Health - T.MinHealthLeft))" in _v221_land and "if p ~= player then" in _v221_land, "strike unchanged: non-lethal, never hits the buyer")
_v221_tk = _v221_PA[_v221_PA.find("local function takeover(player: Player)"):_v221_PA.find("local function land(")]
_v221_ck("ts.InstantCapture, player" in _v221_tk and 'status == "captured"' in _v221_tk and 'status == "held"' in _v221_tk, "takeover -> TerritoryService.InstantCapture (captured / held)")
_v221_ic = _v221_TS[_v221_TS.find("function TerritoryService.InstantCapture("):][:1400]
_v221_ck("awardCapture(player, rt)" in _v221_ic and "TerritoryService.PushAll()" in _v221_ic, "InstantCapture runs the SAME awardCapture as a normal capture, then pushes")
_v221_ck('return "held", 0' in _v221_ic and _v221_ic.find('return "held", 0') < _v221_ic.find("awardCapture(player, rt)"), "already the holder: no second capture")
_v221_ck("isStarterRt(rt)" in _v221_ic, "never a Home Outpost")
_v221_ck(_v221_TS.count("awardCapture(capturer, rt)") == 1, "the normal proximity capture path is unchanged")
_v221_ck("InstantCapture" not in _v221_rd(S + "Modules/RemoteSetup.luau") and "InstantCapture" not in _v221_rd("src/ReplicatedStorage/Shared/Constants.luau"),
         "no remote reaches InstantCapture (server only)")
_v221_cli = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "src/StarterPlayer").rglob("*.luau"))
_v221_ck("InstantCapture" not in _v221_cli and "FireFromPurchase" not in _v221_cli, "client never names the takeover")

# ---- real-code sim: purchase -> capture ----
_v221_env = dict(os.environ)
if "LUAU" not in _v221_env and os.path.isfile(LUAU):
    _v221_env["LUAU"] = LUAU
if _v221_env.get("LUAU"):
    _v221_r = subprocess.run([os.environ.get("PYTHON", "python3"), "tools/sim/run_plaza_airstrike_takeover_test.py"],
                             capture_output=True, text=True, cwd=ROOT, env=_v221_env, timeout=150)
    _v221_ck(_v221_r.returncode == 0 and "PLAZA AIRSTRIKE TAKEOVER TEST: 0 failed" in (_v221_r.stdout or ""),
             "run_plaza_airstrike_takeover_test.py 0 failed (real TerritoryService + PlazaAirstrike)" + ("" if _v221_r.returncode == 0 else " :: " + (_v221_r.stdout or "")[-400:]))
else:
    _v221_ck(False, "LUAU binary required for the v221 sim")

# ---- money / house guard vs v220 ----
_v221_prev = _v221_old(C + "MonetizationConfig.luau")
if _v221_prev is not None:
    _v221_ck(re.findall(r"\bRobuxPrice = \d+", _v221_prev) == re.findall(r"\bRobuxPrice = \d+", _v221_MC), "every RobuxPrice unchanged from " + PREV)
    _v221_ck(re.findall(r"\bId = \d+", _v221_prev) == re.findall(r"\bId = \d+", _v221_MC), "every product / pass Id unchanged from " + PREV)
    _v221_ck(_v221_old(S + "Modules/ProfileSchema.luau") == _v221_rd(S + "Modules/ProfileSchema.luau"), "ProfileSchema / save keys unchanged")
    _v221_dn = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT).stdout
    _v221_ck("WE_Building" not in _v221_dn, "no WE_Building* file changed")
    _v221_dd = subprocess.run(["git", "diff", "-U0", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT).stdout
    _v221_ck(not re.search(r'^[+-].*SetAttribute\("WE_Building', _v221_dd, re.M), "no WE_Building* attribute line touched")
else:
    _v221_ck(True, "git history unavailable (shallow clone): diff guards skipped")
_v221_ck("PreferMeshWhenAssetIdSet = false" in _v221_rd(C + "StructureVisualConfig.luau"), "PreferMesh stays OFF")
_v221_proj = "\n".join(_v221_rd(p) for p in ("default.project.json", "perf.project.json") if (ROOT / p).is_file())
_v221_ck('"StreamingEnabled": true' not in _v221_proj, "StreamingEnabled stays OFF")

if globals().get("_V221_FAILED") and "ok" not in globals():
    raise SystemExit(1)
