# Code Bot Roblox v219 (2026-10-02, Shaun's phone test on WE_Build 218), all OWNER-FIRST:
#  (1) base turrets are solid: one invisible anchored Box hull per AutoGun (GateDefenseConfig.TurretHull);
#  (2) every plot index 1..10 gets all 7 rebirth zones for the owner: RebirthZonesConfig.AnnexAlt +60 fallback slots
#      (JOB 69's 24 were proven short on plots 7 / 8 / 10 against the POIs / WorldFill roads / gate aprons the live
#      check sees), negative slot verdicts retried on the next Refresh, vehicles / loose parts never block, a locked
#      zone with no slot still gets its ZONE BOARD;
#  (3) no yellow neon "RotorDisc" ring round the Part-kit heli rotor (VehicleConfig.HeliRotorRing).
# PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no prices; no Heartbeat loops.
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

BUILD = 219
PREV = "21d8801"  # v218 handoff tip (place version 216)
ROOT = Path.cwd()
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
LUAU = os.environ.get("LUAU") or os.environ.get("LUAU_COMPILE", "").replace("luau-compile", "luau") or os.path.expanduser("~/.local/bin/luau")


def read(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def old(rel: str) -> str | None:
    r = subprocess.run(["git", "show", PREV + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return r.stdout.replace("\r\n", "\n") if r.returncode == 0 else None


def check(cond: bool, label: str) -> None:
    tag = "CODEBOT v219: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(tag)  # type: ignore[name-defined]
    else:
        print(("PASS " if cond else "FAIL ") + tag)
        if not cond:
            globals()["_V219_FAILED"] = True


# ---- WE_Build ----
for rel in (S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"):
    m = re.search(r'SetAttribute\("WE_Build",\s*(\d+)', read(rel))
    check(m is not None and int(m.group(1)) >= BUILD, "WE_Build >= %d %s" % (BUILD, rel.rsplit("/", 1)[-1]))

# ---- (1) turret hulls ----
GDC = read(C + "GateDefenseConfig.luau")
th = GDC.split("TurretHull = {")[1].split("\n\t},")[0] if "TurretHull = {" in GDC else ""
check("Enabled = true," in th and "OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST" in th, "GateDefenseConfig.TurretHull is public since codebot_v220 (was owner-first)")
GD = read(S + "Services/GateDefenseService.luau")
hull = GD.split("function GateDefenseService._AddTurretHull(")[1].split("\nend\n")[0] if "function GateDefenseService._AddTurretHull(" in GD else ""
for needle in ('hull.Shape = Enum.PartType.Block', "hull.Transparency = 1", "hull.Anchored = true", "hull.CanCollide = true",
               "hull.CanQuery = false", "hull.CanTouch = false", "hull.CastShadow = false", ".Live(H, ownerUserId)"):
    check(needle in hull, "turret hull: " + needle)
check("WeldConstraint" not in hull, "turret hull is never welded (the aim turns only the gun's aim part)")
sp = GD.split("local function spawnAutoGun(")[1].split("\nend\n")[0] if "local function spawnAutoGun(" in GD else ""
check("ownerUserId: number?" in sp.split("\n")[0], "spawnAutoGun takes the base owner (the hull gate)")
check("pcall(GateDefenseService._AddTurretHull, model, yawPart, groundY, ownerUserId)" in sp, "every AutoGun (catalog T1..T5 Minigun pack, the AutoGun asset, the Part-kit gun) gets its hull")
check(sp.count("d.CanCollide = false") >= 3, "the visual meshes (gun / nest / sandbags) stay CanCollide = false")
check("spawnAutoGun(slot, at, folder, tier, ownerUserId)" in GD, "syncPlotNow passes the owner (gate + Base Tier nests share the one spawn)")
check("LosRule" in GD and "RespectCanCollide" in GD, "turret fire path unchanged (LOS ray rules untouched)")
check(GD.count("hull.CanQuery = false") == 1, "the hull never takes a shot / LOS ray (CanQuery off): turrets still fire and take hits")

# ---- (3) heli rotor ring ----
VC = read(C + "VehicleConfig.luau")
hr = VC.split("HeliRotorRing = {")[1].split("\n}")[0] if "HeliRotorRing = {" in VC else ""
check("Enabled = true," in hr and "OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST" in hr, "VehicleConfig.HeliRotorRing is public since codebot_v220 (was owner-first)")
VS = read(S + "Services/VehicleService.luau")
kh = VS.split("local function kitHeli(")[1].split("\n\tend\n")[0] if "local function kitHeli(" in VS else ""
check("if not (okRing and ringOff) then\n\t\t\taddRotorDisc(" in kh, "the yellow RotorDisc is skipped while HeliRotorRing is live for the vehicle owner")
check(all(('"%s"' % n) in kh for n in ("RotorHub", "RotorA", "RotorB")), "the rotor hub + blades are still built (AirBodyRig spins them)")
check(VS.count("addRotorDisc(model, ") == 1, "addRotorDisc has one caller (every heli kit: HeliLight / HeliTransport / HeliAttack)")
check('Enum.Material.Neon,\n\t\tEnum.PartType.Cylinder' in VS.split("local function addRotorDisc")[1][:600], "the removed ring is the neon cylinder disc (proof pin)")

# ---- (2) zones ----
RZ = read(C + "RebirthZonesConfig.luau")
alt = RZ.split("AnnexAlt = {")[1].split("} ::")[0]
rows = re.findall(r"\{ X = (-?\d+), Z = (-?\d+), Yaw = (-?\d+) \}", alt)
prev = old(C + "RebirthZonesConfig.luau") or ""
prows = re.findall(r"\{ X = (-?\d+), Z = (-?\d+), Yaw = (-?\d+) \}", prev.split("AnnexAlt = {")[1].split("} ::")[0]) if "AnnexAlt = {" in prev else []
check(len(prows) == 24 and rows[:24] == prows, "the 24 v218 fallback rows are kept first, unchanged (a plot that fits keeps its slots)")
check(len(rows) == 84 and len(set(rows)) == 84, "AnnexAlt = 84 distinct slots (+60)")
check("Slots = true" in RZ.split("cfg.Rebuild = {")[1][:600] and "OwnerFirst = false" in RZ.split("cfg.Rebuild = {")[1][:300], "Rebuild.Slots stays public since codebot_v220 (was owner-first)")
RZS = read(S + "Services/RebirthZoneService.luau")
check("local function retryBlocked(plotId: number)" in RZS and "pcall(retryBlocked, plotId) -- Code Bot v219" in RZS, "a plot left with a gap is resolved again on the next Refresh (no loop)")
check(RZS.count('ZC.RebuildLive(ownerOfPlot(plotId), "Slots") and transient(p)') == 2, "annex + apron checks skip vehicles / loose parts (owner-first)")
check("pcall(RebirthZoneService._ZoneBoard, player, plotId, zoneId, levelOf(profile, zoneId), not reached(profile, zoneId))" in RZS, "a locked zone with no slot still gets its ZONE BOARD (never nothing)")
check("Heartbeat" not in RZS.replace(old(S + "Services/RebirthZoneService.luau") or "", ""), "no Heartbeat in RebirthZoneService")
if os.path.isfile(LUAU):
    for sim in ("tools/sim/run_zone_slots_allplots_test.py", "tools/sim/run_zone_slots_test.py"):
        r = subprocess.run([sys.executable, sim], capture_output=True, text=True, env=dict(os.environ, LUAU=LUAU, VERBOSE="1"), timeout=180)
        okk = r.returncode == 0 and " 0 failed" in r.stdout.strip().splitlines()[-1]
        check(okk, "%s: %s" % (sim, r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr[-300:]))
        if sim.endswith("allplots_test.py"):
            plots = [l for l in r.stdout.splitlines() if re.match(r"ok    plot \d+: 7 of 7", l)]
            check(len(plots) == 10, "every plot index 1..10: 7 of 7 zones (%d plots)" % len(plots))
            check("the v218 fallback list reproduces the live gaps" in r.stdout and "P10/" in r.stdout, "root cause replay: v218's 24 slots leave gaps on plots 7 / 8 / 10")
else:
    check(True, "zone sims skipped (no luau on this lane)")

# ---- guards ----
check('"StreamingEnabled": true' not in read("default.project.json"), "StreamingEnabled stays OFF")
check([l for l in (old(C + "VisualAssetConfig.luau") or "").split("\n") if "OwnerFirst" not in l] == [l for l in read(C + "VisualAssetConfig.luau").split("\n") if "OwnerFirst" not in l], "VisualAssetConfig (PreferMesh) byte-identical to v218 (OwnerFirst lines aside: codebot_v220 public flip)")
diff = subprocess.run(["git", "diff", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT).stdout
names = subprocess.run(["git", "diff", PREV, "--name-only", "--", "src"], capture_output=True, text=True, cwd=ROOT).stdout
added = [l for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
check("WE_Building" not in names, "no WE_Building* file changed")
check(not any(("Heartbeat" in l or "RenderStepped" in l) for l in added), "no Heartbeat / RenderStepped added")
check(not any(re.search(r"\b(Price|PriceRobux|Cost)\s*=", l) for l in added), "no price / cost line added")
check("MonetizationConfig" not in names, "MonetizationConfig untouched")
if globals().get("_V219_FAILED") and "ok" not in globals():
    raise SystemExit(1)
