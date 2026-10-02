# Code Bot Roblox v198 (2026-10-01): DOUBLE WEEKEND reward toasts show the cash actually CREDITED (display only).
#  * EconomyService.AddCash returns (ok, credited): credited = the grant after cashMultFor (callers that read one value are
#    unchanged). EconomyService.ToastAmount(base, ok, credited) / ToastTag(player, reason) / EventCashMult(player, reason):
#    display only; ToastTag = " · 2x" (EventConfig.ToastTag) while the DOUBLE WEEKEND doubles that reason for him.
#  * Toasts fixed: supply drop / airdrop, bank job (bank_raid; a kit's bank_raid_kit never tagged), clan war win /
#    participation, jobs (ops pay + checkpoint), daily missions, the 3-mission chest, timed missions, the daily reward
#    (Day N), plaza bounty, capture stipend, rebirth zone shipments, PvP / NPC / vehicle kill "(+$N)" floats (no tag:
#    the client's Reroute patterns end at "$N)"), and the oil pump label (+$N · 2x via the server's WE_OilMult).
#  * Amounts granted unchanged: every grant still goes through the same AddCash / AccruePendingCash call with the same
#    base and reason; cashMultFor / DoubleEvent untouched. No prices, save keys or WE_Building* touched.
# PreferMesh OFF; StreamingEnabled OFF.
import os as _v198_os
import re as _v198_re
import subprocess as _v198_sp
import sys as _v198_sys
from pathlib import Path as _v198_Path

_v198_ROOT = _v198_Path.cwd()
_v198_C = "src/ReplicatedStorage/Shared/Configs/"
_v198_S = "src/ServerScriptService/Server/"


def _v198_read(rel):
    return (_v198_ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def _v198(cond, label):
    label = "CODEBOT v198: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


for _rel, _needle in (
    (_v198_S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 214'),
    (_v198_S + "Services/DataService.luau", 'SetAttribute("WE_Build", 214'),
    (_v198_S + "Services/DataService.luau", "WE_Build=214"),
    (_v198_S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 214'),
):
    _v198(_needle in _v198_read(_rel), "WE_Build=214 " + _rel.rsplit("/", 1)[-1])

_v198_ECO = _v198_read(_v198_S + "Services/EconomyService.luau")
_v198_ac = _v198_ECO.split("function EconomyService.AddCash(")[1].split("\nend\n")[0]
_v198("player: Player, amount: number, reason: string?): (boolean, number)" in _v198_ac
      and "return true, granted" in _v198_ac and _v198_ac.count("return false, 0") == 2
      and "local granted = applyCashMult(player, profile, amount, reason)" in _v198_ac,
      "AddCash returns (ok, credited = applyCashMult's grant); the grant itself unchanged")
_v198_cmf = _v198_re.search(r"local function cashMultFor.*?\nend\n", _v198_ECO, _v198_re.S).group(0)
_v198(_v198_cmf.count("DE.CashMult(") == 1 and _v198_cmf.count("DE.ExtraCashMult(") == 1,
      "cashMultFor unchanged (one DE.CashMult, one DE.ExtraCashMult)")
_v198_ecm = _v198_re.search(r"function EconomyService.EventCashMult.*?\nend\n", _v198_ECO, _v198_re.S)
_v198(_v198_ecm is not None and "NEVER_MULTIPLIED[key] == true" in _v198_ecm.group(0)
      and "DE.ExtraCashMult(player, reason)" in _v198_ecm.group(0) and "DE.CashMult(player, reason)" in _v198_ecm.group(0)
      and "profile" not in _v198_ecm.group(0) and "Cash +=" not in _v198_ecm.group(0),
      "EventCashMult mirrors cashMultFor's event part (display only: no profile write)")
_v198("function EconomyService.ToastAmount(base: any, ok: any, credited: any): number" in _v198_ECO
      and "function EconomyService.ToastTag(player: Player, reason: string?): string" in _v198_ECO,
      "ToastAmount / ToastTag helpers")
_v198('ToastTag = "2x",' in _v198_read(_v198_C + "EventConfig.luau"), 'EventConfig.ToastTag = "2x"')

_v198_SD = _v198_read(_v198_S + "Services/SupplyDropService.luau")
_v198('local paidOk, paid = EconomyService.AddCash(player, rec.ClaimCash, "supply_drop")' in _v198_SD
      and '"Supply drop +$" .. formatCash(shown) .. tag' in _v198_SD and '"Airdrop +$" .. formatCash(shown) .. tag' in _v198_SD
      and "formatCash(rec.ClaimCash)" not in _v198_SD.split("local function claim")[1].split("\nend\n")[0],
      "supply drop / airdrop toast = credited + tag")
_v198_BR = _v198_read(_v198_S + "Services/BankRaidService.luau")
_v198("local paidOk, paid = EconomyService.AddCash(player, cash, raidReason)" in _v198_BR
      and "toastCash(EconomyService, player, cash, raidReason, paidOk, paid)" in _v198_BR
      and "string.format(TEXT.Reward, formatCash(shown)) .. tag" in _v198_BR,
      "bank job toast = credited + tag (the reason paid: bank_raid doubled, bank_raid_kit never)")
_v198_CW = _v198_read(_v198_S + "Services/ClanWarService.luau")
_v198('winOk, winPaid = EconomyService.AddCash(player, winCash + bonus, "clan_war_win")' in _v198_CW
      and 'partOk, partPaid = EconomyService.AddCash(player, partCash, "clan_war_participate")' in _v198_CW
      and '"clan_war_win", winOk, winPaid)' in _v198_CW and '"clan_war_participate", partOk, partPaid)' in _v198_CW,
      "clan war win / participation toasts = credited + tag")
_v198_OR = _v198_read(_v198_S + "Services/OpsService/OpsRewards.luau")
_v198_g = _v198_OR.split("function OpsRewards.Grant(")[1].split("\nend\n")[0]
_v198("return true, credited" in _v198_g and "ops.Total = math.min(nonNeg(ops.Total) + cash, 1e15)" in _v198_g
      and "pcall(entry.Fn :: any, player, site.Id, site.Kind, cash)" in _v198_g,
      "ops Grant returns the credited cash; totals / best bag / listeners keep the job pay")
_v198("OpsRewards.ToastCash(player, value, paid)" in _v198_read(_v198_S + "Services/OpsService/init.luau")
      and "ctx.Rewards.ToastCash(p, cash, credited)" in _v198_read(_v198_S + "Services/OpsService/OpsKinds.luau"),
      "job pay / checkpoint / bag delivery toasts = credited + tag")
_v198_MS = _v198_read(_v198_S + "Services/MissionService.luau")
for _r in ("mission", "mission_chest", "timed_mission"):
    _v198('paidOk, paid = EconomyService.AddCash(player, cash, "%s")' % _r in _v198_MS
          and 'toastCash(EconomyService, player, cash, "%s", paidOk, paid)' % _r in _v198_MS, _r + " toast = credited + tag")
_v198('dailyOk, dailyPaid = EconomyService.AddCash(player, cashPaid, "daily")' in _v198_MS
      and 'toastCash(EconomyService, player, cashPaid, "daily", dailyOk, dailyPaid)' in _v198_MS, "daily reward toast = credited + tag")
_v198_CS = _v198_read(_v198_S + "Services/CombatService/init.luau")
_v198("eventKillMult" not in _v198_CS and 'local shownCash = grantRewards(attacker, CombatConfig.PlayerKill.Cash, CombatConfig.PlayerKill.XP, "pvp_kill")' in _v198_CS
      and 'string.format("Eliminated %s (+$%d)", victim.DisplayName, shownCash)' in _v198_CS
      and "string.format(fmt, rec.Def.DisplayName, shownCash)" in _v198_CS,
      "PvP / NPC kill floats = credited (was base x KillCount: missed the pass / prestige)")
_v198("shownCash = econ.ToastAmount(cash, paidOk, paid)" in _v198_read(_v198_S + "Modules/VehicleHealth.luau"), "vehicle kill float = credited")
_v198('econ.ToastTag(player, "plaza_bounty")' in _v198_read(_v198_S + "Modules/PlazaBounty.luau"), "plaza bounty toast = credited + tag")
_v198('EconomyService.ToastTag(player, "capture_stipend")' in _v198_read(_v198_S + "Services/CaptureStipendService.luau"), "capture stipend = credited + tag")
_v198('es.ToastTag(player, "rebirthzone_ship")' in _v198_read(_v198_S + "Services/RebirthZoneService.luau"), "zone shipment toast = credited + tag")
_v198_PO = _v198_read(_v198_S + "Services/PlotOilPumpService.luau")
_v198("EconomyService.AccruePendingCash(owner, total, reason)\n\t\t\t\t\t\t\tpublishOilMult(owner)" in _v198_PO
      and 'owner:SetAttribute("WE_OilMult", m)' in _v198_PO, "oil: the grant unchanged; WE_OilMult published for the label")
_v198_PL = _v198_read("src/StarterPlayer/StarterPlayerScripts/Client/Modules/ProducerLabels.luau")
_v198("math.floor(math.floor(PlotOilPumpConfig.CashPerTick) * pumpMult)" in _v198_PL and 'GetAttribute("WE_OilMult")' in _v198_PL,
      "oil pump label = CashPerTick x WE_OilMult (+ 2x)")
# every grant keeps its base + reason (display-only change)
for _rel, _needle in (
    ("Services/SupplyDropService.luau", 'AddCash(player, rec.ClaimCash, "supply_drop")'),
    ("Services/ClanWarService.luau", 'AddCash(player, winCash + bonus, "clan_war_win")'),
    ("Services/ClanWarService.luau", 'AddCash(player, partCash, "clan_war_participate")'),
    ("Services/OpsService/OpsRewards.luau", "AddCash(player, cash, R.CashReason)"),
    ("Services/MissionService.luau", 'AddCash(player, def.RewardCash, "achievement")'),
    ("Services/CombatService/init.luau", "EconomyService.AddCash(attacker, cash, reason)"),
    ("Modules/PlazaBounty.luau", 'econ.AddCash(player, math.floor(PlazaBountyConfig.Cash * mult), "plaza_bounty")'),
    ("Services/PlotOilPumpService.luau", "AccruePendingCash(owner, total, reason)"),
):
    _v198(_needle in _v198_read(_v198_S + _rel), "grant unchanged: " + _needle)

_v198_luau = _v198_os.environ.get("LUAU")
if _v198_luau is None and _v198_os.environ.get("LUAU_COMPILE"):
    _v198_cand = _v198_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _v198_luau = _v198_cand if _v198_os.path.isfile(_v198_cand) else None
if _v198_luau:
    # behavioural: ToastAmount / ToastTag under the luau CLI with a stub event multiplier
    _v198_fn = _v198_re.search(r"function EconomyService.ToastAmount.*?\nend\n", _v198_ECO, _v198_re.S).group(0)
    _v198_tt = _v198_re.search(r"function EconomyService.ToastTag.*?\nend\n", _v198_ECO, _v198_re.S).group(0)
    _v198_h = ("local EconomyService = {}\nlocal MULT = 1\nfunction EconomyService.EventCashMult() return MULT end\n"
               "local Shared = { Configs = { EventConfig = 'EC' } }\nlocal require = function() return { ToastTag = '2x' } end\n"
               + _v198_fn + _v198_tt +
               "local f = 0\nlocal function t(c, n) if not c then f += 1 print('FAIL ' .. n) else print('PASS ' .. n) end end\n"
               "t(EconomyService.ToastAmount(10000, true, 20000) == 20000, 'credited wins')\n"
               "t(EconomyService.ToastAmount(10000, false, 0) == 10000, 'refused grant: base')\n"
               "t(EconomyService.ToastAmount(10000, true, nil) == 10000, 'old boolean AddCash: base')\n"
               "t(EconomyService.ToastAmount(10000, true, 0/0) == 10000, 'NaN: base')\n"
               "t(EconomyService.ToastTag({}, 'supply_drop') == '', 'no tag outside the event')\n"
               "MULT = 2\nt(EconomyService.ToastTag({}, 'supply_drop') == ' · 2x', 'tag in the event')\n"
               "print('V198_FAILS=' .. f)\n")
    _v198_p = "/tmp/codebot_v198_toast.luau"
    with open(_v198_p, "w", encoding="utf-8") as _fh:
        _fh.write(_v198_h)
    _v198_o = _v198_sp.run([_v198_luau, _v198_p], capture_output=True, text=True)
    _v198(_v198_o.returncode == 0 and "V198_FAILS=0" in _v198_o.stdout, "ToastAmount / ToastTag behaviour (luau) " + _v198_o.stdout.strip().replace("\n", " | ")[-300:])
    _v198_r = _v198_sp.run([_v198_sys.executable, "tools/sim/event_double_weekend_verify.py"], capture_output=True, text=True,
                           env=dict(_v198_os.environ, LUAU=_v198_luau, WE_ROOT=str(_v198_ROOT)))
    _v198(_v198_r.returncode == 0 and "TOTAL FAIL=0" in _v198_r.stdout,
          "tools/sim/event_double_weekend_verify.py TOTAL FAIL=0 (grants unchanged)")
else:
    print("SKIP CODEBOT v198: luau behaviour + event_double_weekend_verify.py (set LUAU)")

_v198("PreferMeshWhenAssetIdSet = false" in _v198_read(_v198_C + "StructureVisualConfig.luau"), "PreferMesh OFF")
_v198('"StreamingEnabled": true' not in _v198_read("default.project.json"), "StreamingEnabled stays OFF")
