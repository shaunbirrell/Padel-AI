"""Code Bot v171 (Shaun 2026-10-01 12:08 Dublin, R10, v169/v170): the three live bugs, on the REAL code.

1. TARGETS card gone: the REAL v170 RivalController (git d38c766) on a Roblox-faithful GUI stand-in (Roblox throws when a
   typed property is assigned nil) dies in build() at `f.AnchorPoint = spec[5]` (the crosshair specs have 4 fields):
   the TargetsPill is parented with no Size / Position / labels / tap -> nothing on screen. The v171 source builds a
   180x64 card under the compass with TARGETS, the empty line and one tap handler, and a push fills it.
2. Scout report "did nothing": the endgame harness (run_endgame_test.py, the real EndgameService + EndgameController):
   the report is built before the charge (a failure charges nothing), saved in profile.Endgame (survives a rejoin /
   server move), pushed once as a "ScoutReport" result card, leads the Intel list (VIEW).
3. Recruit Pack gold trim: the real BaseTierBuilder builds gold Metal bands on every wall body + the gate posts (no
   collision / ray), only with the saved RecruitPack entitlement while live; the receipt's WE_Ent_RecruitPack attribute
   rebuilds it at once; the cash (Cash30m-sized) and the 2x / 30 min boost stay on the receipt path.
Run: LUAU=path/to/luau python tools/sim/run_codebot_v171_test.py   (exit 1 on any failure)"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from rival_controller_harness import run_controller  # noqa: E402

RIVAL = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RivalController.luau"
SV = ROOT / "src/ServerScriptService/Server"
FAILS = []


def check(cond, msg):
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        FAILS.append(msg)


# ── 1. the TARGETS card ──
old = subprocess.run(["git", "show", "d38c766:" + RIVAL], cwd=ROOT, capture_output=True, text=True)
if old.returncode == 0 and old.stdout:
    _, ro, _ = run_controller(old.stdout)
    check("AnchorPoint" in ro.get("spawn_err", "") and ro.get("w") == "-1" and ro.get("title") == "nil" and ro.get("taps") == "0",
          "v171 TARGETS: the v170 source dies in build() at the crosshair's nil AnchorPoint -> a sizeless, empty, untappable card (%s)" % ro.get("spawn_err"))
else:
    print("NOTE  git d38c766 not available here: the v170 repro is skipped")
_, rn, outn = run_controller((ROOT / RIVAL).read_text(encoding="utf-8"))
check(rn.get("spawn_err") == "nil" and rn.get("w") == "180" and rn.get("h") == "64" and rn.get("title") == "TARGETS"
      and rn.get("rival") == "No target now" and rn.get("taps") == "1" and rn.get("pushed_rival") == "Rival",
      "v171 TARGETS: the card builds (180x64 at %s,%s), TARGETS / No target now, 1 tap, a push fills it" % (rn.get("x"), rn.get("y")))
src = (ROOT / RIVAL).read_text(encoding="utf-8")
check("f.AnchorPoint = spec[5]" not in src and "f.AnchorPoint = spec[4]" in src, "v171 TARGETS: the crosshair reads its 4th field")

# ── 2 + 3. the endgame harness (real EndgameService / EndgameController / BaseTierBuilder) ──
env = dict(os.environ, VERBOSE="1")
r = subprocess.run([sys.executable, str(HERE / "run_endgame_test.py")], capture_output=True, text=True, env=env, cwd=ROOT)
lines = [l for l in r.stdout.splitlines() if "v171" in l]
check(len(lines) >= 13 and all(l.startswith("ok") for l in lines) and "ENDGAME TEST: 0 failed" in r.stdout,
      "v171 scout + recruit trim: %d harness checks ok (run_endgame_test.py)" % sum(1 for l in lines if l.startswith("ok")))
for l in lines:
    if not l.startswith("ok"):
        print("      " + l)

# ── 3b. the receipt path (static, the real file) ──
mon = (SV / "Services/MonetizationService.luau").read_text(encoding="utf-8")
es = (SV / "Services/EndgameService.luau").read_text(encoding="utf-8")
rp = mon.split('if productKey == "RecruitPack" then')
check(len(rp) >= 3 and "cashGrant = nonNegInt(MCx.RecruitPackCashFor(player.UserId, perMin))" in rp[1]
      and "pcall(CS.GrantCashBoost, player, o.BoostMinutes, o.BoostMult)" in rp[2] and "pcall(BSS.Refresh, profile.BasePlotId)" in rp[2],
      "v171 recruit: the receipt grants the Cash30m-sized cash, the 2x boost and refreshes his base sign at once")
check('player:GetAttributeChangedSignal("WE_Ent_RecruitPack"):Connect' in es and "pcall(EndgameService.SyncBaseTier, player)" in es
      and "EndgameService.HasRecruitTrim(player, profile)" in es and "tostring(recruit), #ctx.Walls)" in es,
      "v171 recruit: the trim is rebuilt the moment the entitlement lands, keyed on it (and on the wall count)")
check('w:GetAttribute("WE_WallLevel") ~= nil' in es, "v171 recruit: only the wall BODIES get the trim (not caps / wire / gate posts)")
check("Endgame" not in mon, "v171 recruit: MonetizationService still never touches the endgame (no Robux path)")

print("CODEBOT V171 TEST: %d failed" % len(FAILS))
sys.exit(1 if FAILS else 0)
