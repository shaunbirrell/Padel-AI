# Code Bot Roblox v175 (2026-10-01): TOP SUPPORTERS pipeline + purchase stand signs + JOB 48 Hook for everyone.
# BUG 1 (TOP SUPPORTERS empty after Laumartinez26's Speed Boost): ProcessReceipt -> RobuxSpent -> WE_LB2_Supporters is
#   proven end to end in tools/sim/run_codebot_v175_test.py (real MonetizationService + EngagementService, budgeted
#   DataStore stand-in). Hardening: budgetOk asks the modern OrderedList / OrderedWrite budget types (legacy types are
#   documented as returning 0), round-robin board reads, join backfill from saved RobuxSpent, THIS WEEK tab
#   (Supporters_W via LB.SupWBase), one-time pass credit, [SUPPORTERS] log lines, friends payout under pcall.
# BUG 2 (stand labels overlapping): the camera-facing BillboardGuis are replaced by ONE physical SurfaceGui panel per
#   stand facing the plot inside, never wider than Depot.Step minus 5 studs.
# Shaun approved: TutorialConfig.Guided.Hook.OwnerFirst = false (JOB 48's first 2 minutes for everyone).
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def code(src):
    src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
    return "\n".join(l.split("--", 1)[0] for l in src.splitlines())



S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 204)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 204)'),
    (S + "Services/DataService.luau", "WE_Build=204"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 204)'),
):
    check(needle in read(rel), "CODEBOT v175: WE_Build=204 " + rel.rsplit("/", 1)[-1])

# Hook for everyone (Shaun approved)
TC = read(C + "TutorialConfig.luau")
hook = TC.split("\tHook = {")[1].split("\n\t},\n}")[0] if "\tHook = {" in TC else ""
check("OwnerFirst = false," in hook and "OwnerFirst = true" not in code(hook) and "Enabled = true," in hook,
      "CODEBOT v175: Guided.Hook Enabled, OwnerFirst = false (for everyone)")

# BUG 1 supporters
ES = code(read(S + "Services/EngagementService.luau"))
check("Enum.DataStoreRequestType.OrderedList" in ES or "OrderedList" in ES, "CODEBOT v175: budgetOk asks the modern OrderedList type")
check("SupWBase" in ES and "Supporters_W" in ES, "CODEBOT v175: weekly supporters from LB.SupWBase")
check('"join"' in ES and '"leave"' in ES, "CODEBOT v175: supporters written on join (backfill) and leave")
check("[SUPPORTERS]" in read(S + "Services/EngagementService.luau"), "CODEBOT v175: [SUPPORTERS] log lines")
check("pcall(pay" in ES, "CODEBOT v175: friends payout cannot kill the board loop")
LC = read(C + "LeaderboardConfig.luau")
sup = LC.split("Key = \"Supporters\"")[1].split("}")[0] if "Key = \"Supporters\"" in LC else ""
check("Weekly = true" in sup or re.search(r"Supporters.{0,400}Weekly = true", LC, re.S) is not None,
      "CODEBOT v175: Supporters has a THIS WEEK tab")
check("SupWBase" in read(S + "Modules/ProfileSchema.luau"), "CODEBOT v175: ProfileSchema keeps LB.SupWBase")

# BUG 2 stand signs
PS = code(read(S + "Modules/PurchaseStands.luau"))
build = PS.split("function PurchaseStands.Build(")[1] if "function PurchaseStands.Build(" in PS else ""
check('Instance.new("BillboardGui")' not in PS, "CODEBOT v175: purchase stands build no BillboardGui")
check('Instance.new("SurfaceGui")' in PS and "WE_PremiumBillboard" in PS and "BuildSign(" in build,
      "CODEBOT v175: one SurfaceGui sign (WE_PremiumBillboard) per stand")
MC = read(C + "MonetizationConfig.luau")
m_w = re.search(r"SignW = ([\d.]+),", MC)
m_s = re.search(r"Depot = \{ X0 = -?[\d.]+, Step = ([\d.]+),", MC)
check(m_w is not None and m_s is not None and float(m_w.group(1)) <= float(m_s.group(1)) - 5,
      "CODEBOT v175: sign width <= Depot.Step - 5 (neighbours never overlap)")
m_d = re.search(r"LabelMaxDistance = (\d+)", MC)
check(m_d is not None and int(m_d.group(1)) <= 40 and "sg.MaxDistance = S.LabelMaxDistance" in PS,
      "CODEBOT v175: sign MaxDistance from LabelMaxDistance (<= 40)")
check("FaceDir = F:VectorToWorldSpace(Vector3.new(0, 0, -1))" in read(S + "Modules/MapSetup.luau"),
      "CODEBOT v175: depot stand signs face the plot inside")
check('FindFirstChild("Edge")' in read(CL + "Controllers/ShopController.luau"), "CODEBOT v175: owned stand sign edge turns green")

# standing rules
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v175: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v175: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v175: StreamingEnabled stays OFF")
check('RecruitPack = { Id = 3715776659, DisplayName = "Recruit Pack", RobuxPrice = 49,' in MC,
      "CODEBOT v175: no Recruit Pack price / Id change")
check("AdminConfig" in read(S + "Services/EngagementService.luau"), "CODEBOT v175: admins stay off the boards")

prev = os.environ.get("CODEBOT_V175_PREV", "d4f776d")
try:
    r = subprocess.run(["git", "diff", "--name-only", prev, "--", "src"], capture_output=True, text=True, cwd=ROOT)
    touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
    check(not touched, "CODEBOT v175: no WE_Building* diffs vs " + prev + ((" " + str(touched)) if touched else ""))
except Exception as e:
    check(False, "CODEBOT v175: WE_Building* diff check errored: " + str(e))

luau = os.environ.get("LUAU")
if luau is None and os.environ.get("LUAU_COMPILE"):
    cand = os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    luau = cand if os.path.isfile(cand) else None
if luau is None and Path("/home/box/.local/bin/luau").is_file():
    luau = "/home/box/.local/bin/luau"
if luau:
    for script, needle in (("tools/sim/run_codebot_v175_test.py", "CODEBOT V175 TEST: 0 failed"),
                           ("tools/sim/run_first_minutes_test.py", "FIRST MINUTES TEST: 0 failed")):
        r = subprocess.run([sys.executable, script], capture_output=True, text=True, env=dict(os.environ, LUAU=luau))
        check(r.returncode == 0 and needle in r.stdout, "CODEBOT v175: " + script.rsplit("/", 1)[-1] + " 0 failed")
else:
    print("SKIP CODEBOT v175: Luau CLI tests (set LUAU)")
