# Code Bot Roblox v172 (2026-10-01, Shaun approved keeping BOTH Recruit Pack base trims): the v171 gold wall bands /
# gate post bands / finials (BaseTierBuilder RecruitTrim, inside WE_BaseTier) AND claude-bud JOB 45's gold gate arch
# with the RECRUIT banner (Services/RecruitTrimService, Workspace.WE_RecruitTrim), brought over from claude/desktop-bud
# (64dd380). Code Bot v172 fixed the arch's placement: JOB 45 stood it 4 studs in from the PLOT edge, which is inside
# the front wall's body (the wall stands 1.5 in, 3.5-6.3 thick) at every walls level, and raycast its height, which
# could land on the GateArch and float it. It now reads the real gate (the GatePost parts), stands clear of the wall,
# the v171 bands, the posts' roofs, the gatehouse / crest and the guards, rises above the wall, hangs the banner above
# the gate opening, and is rebuilt when the walls change. Proof: tools/sim/run_recruit_trim_test.py (section 7).
# No price / Id change. PreferMesh OFF, StreamingEnabled OFF; WE_Building* untouched.
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
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 211'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 211'),
    (S + "Services/DataService.luau", "WE_Build=211"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 211'),
):
    check(needle in read(rel), "CODEBOT v172: WE_Build=211 " + rel.rsplit("/", 1)[-1])

# 1. the v171 trim is still there (walls, posts, finials) and is built at ANY tier from the saved entitlement
BT = read(S + "Modules/BaseTierBuilder.luau")
for name in ("RecruitWallBand", "RecruitWallStripe", "RecruitPostBand", "RecruitPostFinial"):
    check('"%s"' % name in BT, "CODEBOT v172: v171 trim part %s kept" % name)
check("if ctx.RecruitTrim then" in BT and 'd.Name == "GateRoofFinial"' in BT, "CODEBOT v172: v171 trim block + the Tier 1 roof finial turning Recruit gold kept")
ES = read(S + "Services/EndgameService.luau")
check("if tier <= 0 and not crest and not trophy and banner == nil and not recruit then" in ES and "ctx.RecruitTrim = recruit" in ES,
      "CODEBOT v172: the v171 trim is built at every base tier (tier 0 included) for an owner")
check('player:GetAttributeChangedSignal("WE_Ent_RecruitPack"):Connect' in ES, "CODEBOT v172: the v171 trim goes on the moment the entitlement lands")

# 2. the JOB 45 arch is wired, and placed from the real gate
RT = read(S + "Services/RecruitTrimService.luau")
RTc = code(RT)
BS = read(S + "Bootstrap.server.luau")
check('safeRequire("RecruitTrimService", Services.RecruitTrimService)' in BS and 'safeInit("RecruitTrimService", RecruitTrimService, deps)' in BS,
      "CODEBOT v172: Bootstrap requires + inits RecruitTrimService (the JOB 45 arch)")
RC = read(C + "RecruitTrimConfig.luau")
check("local RecruitTrimConfig = {\n\tEnabled = true," in RC and 'Text = "RECRUIT",' in RC, "CODEBOT v172: RecruitTrimConfig on, banner text RECRUIT")
for k in ("GateFurnitureStuds = 2.6,", "WallClearStuds = 1.0,", "HeightOverWall = 5,"):
    check(k in RC, "CODEBOT v172: arch clearance knob " + k.rstrip(","))
for name in ("Plinth", "Shaft", "Rib", "Collar", "Capital", "Cap", "FinialStem", "Finial", "Beam", "BeamBand", "Banner", "BannerRod", "BannerSide", "BannerEdge"):
    check('"%s"' % name in RT, "CODEBOT v172: arch part %s" % name)
check('l.Text = "★ " .. t.Text .. " ★"' in RT and "Enum.NormalId.Front, Enum.NormalId.Back" in RT, "CODEBOT v172: the RECRUIT banner reads on both faces")
check('d.Name == "GatePost"' in RT and 'kid(plotFolder, "WE_PerimeterWalls")' in RT and 'string.sub(d.Name, 1, 8) == "WallGate"' in RT,
      "CODEBOT v172: the arch is placed from the real gate posts + the gate-face wall")
check("Raycast" not in RTc, "CODEBOT v172: no raycast ground height (it could land on the GateArch and float the arch)")
check("math.max(wallT * 0.5 + 0.8, t.GateFurnitureStuds) + t.WallClearStuds + plinthHalf" in RT and "H = math.max(H, wallH + t.HeightOverWall)" in RT,
      "CODEBOT v172: the arch stands behind the wall + gate furniture and rises above the wall")
check("moved = key ~= cur.Key" in RT, "CODEBOT v172: a walls upgrade / map rebuild moves the arch with the gate")
check("p.CanCollide = false" in RTc and "p.CanTouch = false" in RTc and "p.CanQuery = false" in RTc, "CODEBOT v172: the arch never collides / touches / blocks rays")
check("WE_Building" not in RTc and "MeshPart" not in RTc and "Light" not in RTc.replace("LightInfluence", "") and "Neon" not in RTc,
      "CODEBOT v172: the arch is plain Parts (no WE_Building*, no meshes, no lights, no Neon)")
check('"WE_RecruitTrim"' in RT and '"WE_RecruitTrim"' not in BT and '"RecruitTrim"' not in RT,
      "CODEBOT v172: the two trims live apart (Workspace.WE_RecruitTrim vs WE_BaseTier.RecruitTrim)")
check("MC.RecruitPackLiveFor(player.UserId) == true" in RT and "MC.RecruitPackLiveFor(player.UserId) ~= true" in ES,
      "CODEBOT v172: both trims follow the same live gate (RecruitPackLiveFor) + the RecruitPack entitlement")

# 3. nothing else moved
MC = read(C + "MonetizationConfig.luau")
check('RecruitPack = { Id = 3715776659, DisplayName = "Recruit Pack", RobuxPrice = 49,' in MC and "RecruitTrim" not in MC,
      "CODEBOT v172: no Recruit Pack price / Id change")
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v172: PreferMesh stays OFF")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v172: StreamingEnabled stays OFF")
MS = read(S + "Services/MonetizationService.luau")
check("pcall(BSS.Refresh, profile.BasePlotId)" in MS and '"[RECRUIT] boost %s: %s (until %s)"' in MS,
      "CODEBOT v172: the receipt keeps the v171 sign refresh + the JOB 45 [RECRUIT] logs")

luau = os.environ.get("LUAU")
if luau is None and os.environ.get("LUAU_COMPILE"):
    cand = os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    luau = cand if os.path.isfile(cand) else None
if luau:
    r = subprocess.run([sys.executable, "tools/sim/run_recruit_trim_test.py"], capture_output=True, text=True, env=dict(os.environ, LUAU=luau))
    check(r.returncode == 0 and "RECRUIT TRIM TEST: 0 failed" in r.stdout, "CODEBOT v172: run_recruit_trim_test.py (both gates, walls Lv 1-5, no overlap / z-fighting)")
else:
    print("SKIP CODEBOT v172: Luau CLI test (set LUAU)")
