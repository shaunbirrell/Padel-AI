# Code Bot Roblox v197 (2026-10-01): DOUBLE WEEKEND payout fixes.
#  * MonetizationService.PassivePerMin(excludeTimed) divides the DOUBLE WEEKEND factor out (with the code boost and the
#    weekly event): Robux time packs / Recruit Pack no longer pay 2x in the window; income-scaled missions / chest /
#    Day 7 / zone runs apply the event once (2x), not twice (4x). Legacy cash packs pass excludeTimed=true too.
#  * EventConfig.ExtraCashReasons: the event doubles the 2x-pass-exempt fixed payouts oil (plot_oil, at accrue), jobs
#    (ops), supply drops, bank raid without a kit (bank_raid; a kit pays "bank_raid_kit", NEVER_MULTIPLIED) and clan war
#    cash. The 2x pass still skips them; codes / battle pass / onboarding / invite / spinner / dropper are never doubled.
# Static pins here; the real-module Luau harness is tools/sim/event_double_weekend_verify.py (run below when the Luau
# CLI is there). PreferMesh OFF; StreamingEnabled OFF; no prices / WE_Building* / save keys changed.
import os as _v197_os
import re as _v197_re
import subprocess as _v197_sp
import sys as _v197_sys
from pathlib import Path as _v197_Path

_v197_ROOT = _v197_Path.cwd()
_v197_C = "src/ReplicatedStorage/Shared/Configs/"
_v197_S = "src/ServerScriptService/Server/"


def _v197_read(rel):
    return (_v197_ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def _v197(cond, label):
    label = "CODEBOT v197: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


for _rel, _needle in (
    (_v197_S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 206)'),
    (_v197_S + "Services/DataService.luau", 'SetAttribute("WE_Build", 206)'),
    (_v197_S + "Services/DataService.luau", "WE_Build=206"),
    (_v197_S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 206)'),
):
    _v197(_needle in _v197_read(_rel), "WE_Build=206 " + _rel.rsplit("/", 1)[-1])

_v197_MS = _v197_read(_v197_S + "Services/MonetizationService.luau")
_v197_ppm = _v197_re.search(r"function MonetizationService.PassivePerMin.*?\nend\n", _v197_MS, _v197_re.S).group(0)
_v197("(require :: any)(script.Parent.Parent.Modules.DoubleEvent).CashMult(player, \"passive\")" in _v197_ppm
      and "m = m / math.max(1, b) / math.max(1, e) / math.max(1, d)" in _v197_ppm,
      "PassivePerMin(excludeTimed) divides CashBoost, the weekly event AND the DOUBLE WEEKEND out")
_v197(_v197_ppm.index("if excludeTimed == true then") < _v197_ppm.index("DoubleEvent") < _v197_ppm.index("local v = t * m / tick * 60"),
      "the DOUBLE WEEKEND divide is inside the excludeTimed branch only")
_v197('ShopOverhaulConfig.CashPackAmount("CashLarge", MonetizationService.PassivePerMin(player, prof, true))' in _v197_MS,
      "legacy CashLarge offer amount: excludeTimed=true")
_v197(_v197_re.search(r"CashPacks\[productKey :: string\] ~= nil and .*?\n(?:\t+--[^\n]*\n)*\t+local perMin = MonetizationService\.PassivePerMin\(player, profile, true\)\n", _v197_MS) is not None,
      "legacy cash pack receipt: excludeTimed=true")
_v197(_v197_MS.count("MonetizationService.PassivePerMin(player, profile, ShopOverhaulConfig.TimePacks.ExcludeTimedBoosts == true)") == 1
      and "PassivePerMin(player, profile, useTime and ShopOverhaulConfig.TimePacks.ExcludeTimedBoosts == true)" in _v197_MS,
      "time pack + Recruit Pack receipts still use excludeTimed (unchanged)")

_v197_EC = _v197_read(_v197_C + "EventConfig.luau")
_v197_m = _v197_re.search(r"ExtraCashReasons = \{(.*?)\n\t\}", _v197_EC, _v197_re.S)
_v197_extra = sorted(_v197_re.findall(r"^\s*(\w+)\s*=\s*true", _v197_m.group(1), _v197_re.M)) if _v197_m else []
_v197(_v197_extra == ["bank_raid", "clan_war_participate", "clan_war_win", "ops", "plot_oil", "supply_drop"],
      "EventConfig.ExtraCashReasons = oil, jobs, supply drops, bank raid (no kit), clan war " + ",".join(_v197_extra))
_v197(not (set(_v197_extra) & {"code", "battlepass", "onboarding", "invite_welcome", "invite_reward", "friends_bonus",
                                "comeback", "spinner", "manual_dropper", "devproduct", "admin", "purchase_refund",
                                "collector", "offline", "bank_raid_kit"}),
      "ExtraCashReasons lists no code / battle pass / onboarding / invite / friends / comeback / spinner / dropper / Robux / admin / refund")
_v197_MC = _v197_read(_v197_C + "MonetizationConfig.luau")
_v197_ex = _v197_re.search(r"CashMultExemptReasons = \{(.*?)\n\t\}", _v197_MC, _v197_re.S).group(1)
_v197(all(_v197_re.search(r"^\s*" + r + r"\s*=\s*true", _v197_ex, _v197_re.M) for r in _v197_extra),
      "ExtraCashReasons all stay 2x-pass exempt (MonetizationConfig.CashMultExemptReasons)")

_v197_ECO = _v197_read(_v197_S + "Services/EconomyService.luau")
_v197_cmf = _v197_re.search(r"local function cashMultFor.*?\nend\n", _v197_ECO, _v197_re.S).group(0)
_v197(_v197_re.search(r"elseif NEVER_MULTIPLIED\[reasonKey\] ~= true then.*?mult \*= DE\.ExtraCashMult\(player, reason\)", _v197_cmf, _v197_re.S) is not None
      and _v197_cmf.count("DE.CashMult(") == 1 and _v197_cmf.count("DE.ExtraCashMult(") == 1,
      "cashMultFor: exempt branch applies DE.ExtraCashMult only (never a NEVER_MULTIPLIED reason)")
_v197(_v197_re.search(r"local NEVER_MULTIPLIED.*?\n\tbank_raid_kit = true,.*?\n\}", _v197_ECO, _v197_re.S) is not None,
      "bank_raid_kit (heist kit payout, income-scaled) is NEVER_MULTIPLIED")
_v197("applyCashMult" not in _v197_re.search(r"function EconomyService.CollectPendingCash.*?\nend\n", _v197_ECO, _v197_re.S).group(0),
      "CollectPendingCash adds no multiplier (oil doubled once, at accrue)")
_v197_DE = _v197_read(_v197_S + "Modules/DoubleEvent.luau")
_v197(_v197_re.search(r"function DoubleEvent\.ExtraCashMult\(player: Player, reason: string\?\): number.*?ExtraCashReasons.*?CashExemptReasons.*?KillReasons.*?ActiveFor\(player\).*?\nend", _v197_DE, _v197_re.S) is not None,
      "DoubleEvent.ExtraCashMult: listed reasons only, in the window only")
_v197_BR = _v197_read(_v197_S + "Services/BankRaidService.luau")
_v197('local raidReason = if okK and (tonumber(kit) or 0) > 0 then "bank_raid_kit" else "bank_raid"' in _v197_BR
      and "EconomyService.AddCash(player, cash, raidReason)" in _v197_BR,
      "bank raid: no kit -> bank_raid (doubled), heist kit -> bank_raid_kit (not doubled again)")

_v197_luau = _v197_os.environ.get("LUAU")
if _v197_luau is None and _v197_os.environ.get("LUAU_COMPILE"):
    _v197_cand = _v197_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _v197_luau = _v197_cand if _v197_os.path.isfile(_v197_cand) else None
if _v197_luau:
    _v197_r = _v197_sp.run([_v197_sys.executable, "tools/sim/event_double_weekend_verify.py"], capture_output=True, text=True,
                           env=dict(_v197_os.environ, LUAU=_v197_luau, WE_ROOT=str(_v197_ROOT)))
    _v197(_v197_r.returncode == 0 and "TOTAL FAIL=0" in _v197_r.stdout,
          "tools/sim/event_double_weekend_verify.py (real EventConfig + DoubleEvent under a fake clock) TOTAL FAIL=0")
else:
    print("SKIP CODEBOT v197: event_double_weekend_verify.py (set LUAU)")

_v197("PreferMeshWhenAssetIdSet = false" in _v197_read(_v197_C + "StructureVisualConfig.luau"), "PreferMesh OFF")
_v197('"StreamingEnabled": true' not in _v197_read("default.project.json"), "StreamingEnabled stays OFF")
