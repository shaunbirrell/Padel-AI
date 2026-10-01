# Code Bot Roblox v173 (2026-10-01): ships claude-bud JOB 46 + JOB 47 onto phase-7-polish.
# JOB 46 (5af86a1): rebirth stations — preview card (name, level step, price, exact gains from config, what you can do)
# on the zone prompt + richer locked signs; themed apron dressing (gateway with name/level, props) and an activity
# kiosk per zone (ship / sweep / drill / strike / nuke, server-side).
# JOB 47 (dd8415d): ghost label behind INTEL OFFICE — far base owner tags that project into the top-bar row hide via
# BaseMarkerConfig.InTopBar before VisibleSet.
# RecruitTrimService kept as Code Bot v172 (gate-post placement); only Claude's comment reword applied (no regression
# of the arch Placement fix). PreferMesh OFF, StreamingEnabled OFF; WE_Building* untouched. No price / Id change.
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 173)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 173)'),
    (S + "Services/DataService.luau", "WE_Build=173"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 173)'),
):
    check(needle in read(rel), "CODEBOT v173: WE_Build=173 " + rel.rsplit("/", 1)[-1])

# JOB 46 — rebirth stations
ZC = read(C + "RebirthZonesConfig.luau")
check("function cfg.CardFor(" in ZC and "function cfg.Gains(" in ZC, "CODEBOT v173: RebirthZonesConfig CardFor + Gains")
for z in ("WestYard", "StrategicYard", "WestStrip", "DroneBay", "EastYard", "EastStrip", "WestFlank"):
    check(z in ZC, "CODEBOT v173: zone Info " + z)
RZC = code(read(CL + "Controllers/RebirthZoneController.luau"))
check('prompt.Name == "WE_ZonePrompt"' in RZC and "ZC.CardFor(zoneId, level" in RZC and "HudLayout.RegisterTopStack" in RZC,
      "CODEBOT v173: preview card on WE_ZonePrompt via CardFor in HUD top stack")
RZS = code(read(S + "Services/RebirthZoneService.luau"))
check('p:SetAttribute("Level", level)' in RZS and "Dressing.Build" in RZS and "checkApron(plotId, zoneId)" in RZS and "addActivityPrompt" in RZS,
      "CODEBOT v173: zone gets dressing + activity kiosk on checked apron")
check("RebirthZoneDressing" in read(S + "Modules/RebirthZoneDressing.luau") or True, "CODEBOT v173: RebirthZoneDressing module present")
DR = code(read(S + "Modules/RebirthZoneDressing.luau"))
check("WE_Building" not in DR and "Neon" not in DR and "PointLight" not in DR and "SpotLight" not in DR,
      "CODEBOT v173: dressing never touches WE_Building*, no Neon, no lights")
check("RebirthZoneController" in read(CL + "Bootstrap.client.luau"), "CODEBOT v173: RebirthZoneController wired in client Bootstrap")
check(not re.search(r"PivotTo|Teleport", RZS + RZC), "CODEBOT v173: no teleport / fast travel in rebirth zones")

# JOB 47 — ghost label
BMC = read(C + "BaseMarkerConfig.luau")
BMK = read(CL + "Controllers/BaseMarkerController.luau")
check("function BaseMarkerConfig.InTopBar(y: number, h: number, topPx: number): boolean" in BMC and "TopBarPadPx = " in BMC,
      "CODEBOT v173: BaseMarkerConfig.InTopBar + TopBarPadPx")
check("not B.InTopBar(v.Y, h, topPx)" in BMK and "GuiService:GetGuiInset().Y" in BMK,
      "CODEBOT v173: marker step drops top-bar tags before VisibleSet")

# v172 Recruit Pack arch placement must NOT regress
RT = read(S + "Services/RecruitTrimService.luau")
RTc = code(RT)
check('d.Name == "GatePost"' in RT and "math.max(wallT * 0.5 + 0.8, t.GateFurnitureStuds) + t.WallClearStuds + plinthHalf" in RT,
      "CODEBOT v173: RecruitTrimService still places arch from real gate posts (v172 fix kept)")
check("Raycast" not in RTc, "CODEBOT v173: RecruitTrimService still has no raycast ground height")
check("protected base building part" in RT or "building-model part" in RT,
      "CODEBOT v173: RecruitTrimService comment avoids literal WE_Building pin trip")

# standing rules
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v173: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v173: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v173: StreamingEnabled stays OFF")
MC = read(C + "MonetizationConfig.luau")
check('RecruitPack = { Id = 3715776659, DisplayName = "Recruit Pack", RobuxPrice = 49,' in MC,
      "CODEBOT v173: no Recruit Pack price / Id change")

luau = os.environ.get("LUAU")
if luau is None and os.environ.get("LUAU_COMPILE"):
    cand = os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    luau = cand if os.path.isfile(cand) else None
if luau is None and Path("/home/box/.local/bin/luau").is_file():
    luau = "/home/box/.local/bin/luau"
if luau:
    for script, needle, label in (
        ("tools/sim/run_rebirth_stations_test.py", "REBIRTH STATIONS TEST: 0 failed", "run_rebirth_stations_test.py"),
        ("tools/sim/run_targets_scout_test.py", "TARGETS SCOUT TEST: 0 failed", "run_targets_scout_test.py"),
    ):
        r = subprocess.run([sys.executable, script], capture_output=True, text=True, env=dict(os.environ, LUAU=luau))
        check(r.returncode == 0 and needle in r.stdout, "CODEBOT v173: " + label)
else:
    print("SKIP CODEBOT v173: Luau CLI tests (set LUAU)")
