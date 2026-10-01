"""Code Bot v175 (Shaun 2026-10-01 16:00): TOP SUPPORTERS still 'ALL-TIME - no entries yet' after Laumartinez26
(UserId 11718087109, not an admin) bought the Speed Boost DEVELOPER PRODUCT (99 R$) at 15:55 Dublin.

End to end on the REAL modules (Luau CLI, run_first_offer_test's virtual clock + scheduler, stand-ins only around
them): the REAL MonetizationService.ProcessReceipt (Speed Boost Id 3713839342) -> OnGranted -> the REAL
EngagementService (writer + the shared reader loop) -> the published ReplicatedStorage.WE_Leaderboards rows, with a
DataStore stand-in that keeps Roblox's request budgets (GetSortedAsync 5 + 2 x players per minute,
SetIncrementSortedAsync 30 + 5 x players per minute, banked up to 3 minutes).
SCENARIO (env V175_SCENARIO): the owner (shaunie6, admin) and Laumartinez26 are Roblox friends in one server.
Run: LUAU=path/to/luau python tools/sim/run_codebot_v175_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import run_first_offer_test as FO  # noqa: E402

LUAU = os.environ.get("LUAU", "luau")
CFG = ROOT / "src/ReplicatedStorage/Shared/Configs"
SRV = ROOT / "src/ServerScriptService/Server"
MODS = dict(FO.MODS)
MODS["Shared/Configs/EngagementConfig"] = CFG / "EngagementConfig.luau"
MODS["Shared/Configs/LeaderboardConfig"] = CFG / "LeaderboardConfig.luau"
MODS["Server/Services/EngagementService"] = SRV / "Services/EngagementService.luau"

TEST = (HERE / "codebot_v175_e2e.luau").read_text(encoding="utf-8")


def run(scen, old=False, expect_ok=True):
    mods = dict(MODS)
    if old:  # the evidence run: the v173 EngagementService (git), everything else current
        src = subprocess.run(["git", "-C", str(ROOT), "show", "3d93cc4:src/ServerScriptService/Server/Services/EngagementService.luau"],
                             capture_output=True, text=True, check=True).stdout
        oldp = Path(tempfile.gettempdir()) / "v173_EngagementService.luau"
        oldp.write_text(src, encoding="utf-8")
        mods["Server/Services/EngagementService"] = oldp
        lbsrc = subprocess.run(["git", "-C", str(ROOT), "show", "3d93cc4:src/ReplicatedStorage/Shared/Configs/LeaderboardConfig.luau"],
                               capture_output=True, text=True, check=True).stdout
        oldl = Path(tempfile.gettempdir()) / "v173_LeaderboardConfig.luau"
        oldl.write_text(lbsrc, encoding="utf-8")
        mods["Shared/Configs/LeaderboardConfig"] = oldl
    chunks = [FO.PRELUDE]
    for key, path in mods.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, Path(path).read_text(encoding="utf-8")))
    chunks.append(TEST.replace("@SCEN@", scen).replace("@OLD@", "true" if old else "false"))
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=300)
    os.unlink(path)
    out = (r.stdout + r.stderr).strip()
    lines = out.splitlines()
    shown = lines if os.environ.get("VERBOSE") else [l for l in lines if l.startswith(("FAIL", "ok", "[")) or "V175" in l or "error" in l.lower()]
    label = "%s%s" % (scen, " (v173 EngagementService)" if old else "")
    print("== %s ==" % label)
    print("\n".join(shown) or out[-3000:])
    ok = r.returncode == 0 and "V175 SUPPORTERS: 0 failed" in out
    return ok


def main():
    fails = []
    for scen in ("friends", "busy", "payfail"):
        if not run(scen):
            fails.append(scen)
    # the evidence: the same busy-server timeline on the v173 reader leaves TOP SUPPORTERS stale
    old_busy = run("busy", old=True)
    print("v173 reader on the busy server: %s" % ("also refreshes in the model" if old_busy else "TOP SUPPORTERS stale after the purchase (starved)"))
    print("CODEBOT V175 TEST: %d failed%s" % (len(fails), (" (" + ", ".join(fails) + ")") if fails else ""))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
