# Code Bot Roblox v211 (2026-10-02): the owner asked for the "AIRDROP FRENZY · 2d 23h left" top-of-screen banner to be
# removed for everyone. The banner is WE_EventBanner (Client/Modules/EngagementClient), the weekly event rotation from
# EngagementConfig. New switch EngagementConfig.ShowEventBanner = false: the client does not build the banner. DISPLAY
# ONLY: the rotation, EventAt, AIRDROP FRENZY's AirdropIntervalSeconds = 180 (server, EngagementService) and the
# normal airdrop (SupplyDropConfig.Airdrop) are unchanged; the DOUBLE WEEKEND "2x WEEKEND" chip (EventConfig /
# DoubleWeekendController) is untouched. No WE_Building*, PreferMesh OFF, StreamingEnabled OFF.
import os as _v211_os
import subprocess as _v211_sp
import tempfile as _v211_tf
from pathlib import Path as _V211Path

_V211_BUILD = 211
_V211_ROOT = _V211Path.cwd()
_V211_PREV = _v211_os.environ.get("CODEBOT_V211_PREV", "08d3f8f")  # v210 handoff tip (place 208)
_V211_C = "src/ReplicatedStorage/Shared/Configs/"
_V211_S = "src/ServerScriptService/Server/"
_V211_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"


def _v211_r(rel):
    p = _V211_ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _v211_old(rel):
    r = _v211_sp.run(["git", "show", _V211_PREV + ":" + rel], capture_output=True, text=True, cwd=_V211_ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def _v211(cond, label):
    label = "CODEBOT v%d: %s" % (_V211_BUILD, label)
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


_v211_bud = (_V211_ROOT / _V211_S / "Services/ExperienceNotifyService.luau").is_file()
_v211_own = ('SetAttribute("WE_Build", %d)' % _V211_BUILD) in _v211_r(_V211_S + "Services/DataService.luau")
if not _v211_bud:
    for _rel, _needle in (
        (_V211_S + "Services/BaseService.luau", 'SetAttribute("WE_Build", %d)' % _V211_BUILD),
        (_V211_S + "Services/DataService.luau", 'SetAttribute("WE_Build", %d)' % _V211_BUILD),
        (_V211_S + "Services/DataService.luau", "WE_Build=%d" % _V211_BUILD),
        (_V211_S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", %d)' % _V211_BUILD),
    ):
        _v211(_needle in _v211_r(_rel) or not _v211_own, "WE_Build=%d %s" % (_V211_BUILD, _rel.rsplit("/", 1)[-1]))

_V211_EC = _v211_r(_V211_C + "EngagementConfig.luau")
_V211_CLI = _v211_r(_V211_CL + "Modules/EngagementClient.luau")
_v211("\tShowEventBanner = false,\n" in _V211_EC, "EngagementConfig.ShowEventBanner = false (the weekly event banner is hidden for everyone)")
_v211(_V211_EC.count("ShowEventBanner") == 1, "ShowEventBanner is set in exactly one place")
_v211("\t\tif E.ShowEventBanner == false then\n\t\t\treturn" in _V211_CLI
      and _V211_CLI.find("if E.ShowEventBanner == false then") < _V211_CLI.find('gui.Name = "WE_EventBanner"'),
      "EngagementClient returns before building WE_EventBanner when the switch is off")
_v211('pcall((HudLayout :: any).RegisterTopStack, "EventBanner", label, 45)' in _V211_CLI, "the banner system itself is kept (true = as before)")
_v211("task.spawn(noticeBoards)" in _V211_CLI and _V211_CLI.find("task.spawn(noticeBoards)") < _V211_CLI.find("if E.ShowEventBanner == false"),
      "leaderboards are still started before the banner switch")

# gameplay unchanged: the Events rotation (incl. AIRDROP FRENZY's 180 s), Rollout, EventAt; server files byte-identical
_v211_prev_ec = _v211_old(_V211_C + "EngagementConfig.luau")
if _v211_prev_ec is not None:
    _v211_stripped = _V211_EC
    _v211_i = _v211_stripped.find("\t-- Code Bot v211 (owner 2026-10-02")
    _v211_j = _v211_stripped.find("\tShowEventBanner = false,\n")
    if _v211_i >= 0 and _v211_j > _v211_i:
        _v211_stripped = _v211_stripped[:_v211_i] + _v211_stripped[_v211_j + len("\tShowEventBanner = false,\n"):]
    _v211(_v211_stripped == _v211_prev_ec, "EngagementConfig identical to v210 outside the ShowEventBanner block")
    for _rel in (
        _V211_S + "Services/EngagementService.luau",
        _V211_C + "SupplyDropConfig.luau",
        _V211_S + "Services/SupplyDropService.luau",
        _V211_C + "EventConfig.luau",
        _V211_CL + "Controllers/DoubleWeekendController.luau",
    ):
        _prev = _v211_old(_rel)
        if _prev is not None or (_V211_ROOT / _rel).is_file():
            _v211(_prev == _v211_r(_rel), "byte-identical to v210: " + _rel.rsplit("/", 1)[-1])
_v211('{ Id = "AirdropFrenzy", Name = "AIRDROP FRENZY", Window = "Weekend", AirdropIntervalSeconds = 180 },' in _V211_EC,
      "AIRDROP FRENZY gameplay kept (airdrop every 180 s on its weekend)")
_v211("ShowEventBanner" not in _v211_r(_V211_S + "Services/EngagementService.luau"), "no server file reads ShowEventBanner (display only)")

# Luau sim of the real EngagementConfig: Frenzy is the event of 2 Oct 2026 (Fri 00:00 UTC) and still runs, banner off
_v211_luau = _v211_os.environ.get("LUAU", _v211_os.path.expanduser("~/.local/bin/luau"))
if _v211_os.path.isfile(_v211_luau):
    _v211_src = _V211_EC.replace("--!strict", "")
    _v211_sim = ("local EngagementConfig = (function()\n" + _v211_src + "\nend)()\n" + r'''
local E = EngagementConfig
local now = 1790899200 + 3600 -- 2026-10-02 01:00 UTC (Friday)
local ev, t = E.EventAt(now)
print("EV", ev and ev.Id or "nil", ev and ev.AirdropIntervalSeconds or 0, t - now)
print("BANNER", tostring(E.ShowEventBanner))
''')
    with _v211_tf.NamedTemporaryFile("w", suffix=".luau", delete=False) as _fh:
        _fh.write(_v211_sim)
        _v211_tmp = _fh.name
    _v211_out = _v211_sp.run([_v211_luau, _v211_tmp], capture_output=True, text=True, timeout=60)
    _v211_os.unlink(_v211_tmp)
    _v211_o = _v211_out.stdout
    _v211(_v211_o.split()[:3] == ["EV", "AirdropFrenzy", "180"] and 255000 < int(_v211_o.split()[3]) < 256000, "Luau sim: AIRDROP FRENZY runs this weekend with 180 s airdrops (%s)" % _v211_o.strip().replace("\n", " | "))
    _v211("BANNER\tfalse" in _v211_o, "Luau sim: ShowEventBanner = false")

# guards
_v211('"StreamingEnabled": true' not in _v211_r("default.project.json"), "StreamingEnabled stays OFF")
_v211(_v211_old(_V211_C + "VisualAssetConfig.luau") == _v211_r(_V211_C + "VisualAssetConfig.luau"), "VisualAssetConfig (PreferMesh) byte-identical to v210")
_v211_diff = _v211_sp.run(["git", "diff", _V211_PREV, "--name-only", "--", "src"], capture_output=True, text=True, cwd=_V211_ROOT).stdout
_v211("WE_Building" not in _v211_diff, "no WE_Building* file changed")
_v211("PreferMeshWhenAssetIdSet = false," in _v211_r(_V211_C + "StructureVisualConfig.luau"), "PreferMesh stays OFF (StructureVisualConfig)")
