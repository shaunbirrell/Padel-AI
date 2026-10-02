"""claude-bud JOB A (2026-10-01, P0): "the Recruitment Office menu opens, then closes by itself ~0.5 s later".

1. ROOT CAUSE (numbers from the real configs): the Recruitment Office opens from two interaction points: the plaza NPC
   (PlazaServicesConfig, NE_E1 at WorldConfig X 131.5 / Z -43.8) and the DRILL kiosk on the player's own Elite Barracks
   zone (JOB 46, on his plot). The OLD close loop (EndgameController setListOpen, a 0.5 s tick) measured the distance
   to the PLAZA point for every open. For every plot, even the plot's nearest edge is far beyond CloseRange (22), so
   the first tick (0.5 s) always closed it. Printed per plot.
2. THE RULE NOW (the real EndgameConfig.RecruitShouldClose): measured from the point it was OPENED from; open inside
   the prompt (10 / 12 studs), stays open walking around (up to 17), closes only past 17 (hysteresis).
3. 10 opens in a row from the kiosk: never closed by the loop; a little walk (8 studs): open; a real walk-away (40):
   one close "WalkAway"; another player's kiosk never becomes my anchor (static: the server sends ZoneOpen only to the
   prompt's owner, and KioskPoint is keyed by HIS UserId).
4. STATIC: one Open / one Close function, the [RECRUITMENT OPEN] / [RECRUITMENT CLOSE] Reason logs, the prompt hiding
   never closes it (no PromptHidden / TriggerEnded listener on it), X / OtherMenu / WalkAway / Death are the only
   reasons, a damage scratch no longer closes it, the server's AtStation accepts his own kiosk.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_recruitment_office_test.py   (exit 1 on any failure)"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
CL = ROOT / "src/StarterPlayer/StarterPlayerScripts/Client"
MODS = {"Util/PlotFrame": SH / "Util/PlotFrame.luau"}
for c in ("EndgameConfig", "BaseConfig", "BaseLayoutConfig", "PlazaServicesConfig", "AdminConfig", "RetentionConfig", "WorldConfig"):
    p = SH / ("Configs/%s.luau" % c)
    if p.is_file():
        MODS["Configs/" + c] = p

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local EC = require(node("Configs/EndgameConfig"))
local PF = require(node("Util/PlotFrame"))
local BL = require(node("Configs/BaseLayoutConfig"))
local plaza = { X = 131.5, Z = -43.8 } -- WorldConfig NE_E1 (the Recruitment Office inside it)
local half = (BL.PlotSize or 320) / 2
local minEdge, rows = math.huge, {}
for plotId = 1, 10 do
  local p = PF.PlotPosition(plotId)
  if p then
    local d = math.sqrt((p.X - plaza.X) ^ 2 + (p.Z - plaza.Z) ^ 2)
    local edge = d - half * math.sqrt(2) -- the plot corner nearest to the plaza: the kiosk can be no closer
    minEdge = math.min(minEdge, edge)
    table.insert(rows, string.format("P%d %.0f", plotId, edge))
  end
end
print("ROOT CAUSE  nearest possible kiosk -> plaza office distance per plot (studs): " .. table.concat(rows, ", "))
check(minEdge > EC.Station.CloseRange, string.format("OLD rule: from ANY plot the kiosk is >= %.0f studs from the plaza office (> CloseRange %d): the 0.5 s tick always closed it", minEdge, EC.Station.CloseRange))
-- the new rule
check(not EC.RecruitShouldClose(9) and not EC.RecruitShouldClose(12) and not EC.RecruitShouldClose(16.9), "NEW: open inside the prompt and walking around (9 / 12 / 16.9 studs from where it was opened): stays open")
check(EC.RecruitShouldClose(17.5) and EC.RecruitShouldClose(40), "NEW: a real walk-away (17.5 / 40 studs): closes")
check(not EC.RecruitShouldClose(nil), "NEW: no anchor known yet: never a close")
check(EC.Station.RecruitCloseRange >= 15 and EC.Station.RecruitCloseRange <= 18, "the close range is in the 15-18 hysteresis band (" .. EC.Station.RecruitCloseRange .. ")")
-- 10 opens from the kiosk while standing beside it (2 studs), each followed by 20 ticks (10 s) of the close loop
local closes = 0
for i = 1, 10 do
  for t = 1, 20 do if EC.RecruitShouldClose(2 + (t % 3)) then closes += 1 end end
end
check(closes == 0, "10 opens in a row beside my kiosk, 10 s each: the loop never closes it")
local walk = 0
for d = 2, 10 do if EC.RecruitShouldClose(d) then walk += 1 end end
check(walk == 0, "walking a little (up to 10 studs) while it is open: still open")
local away, at = 0, nil
for d = 2, 40, 2 do if EC.RecruitShouldClose(d) and at == nil then at = d; away += 1 end end
check(away == 1 and at == 18, "walking genuinely away: exactly one close, at " .. tostring(at) .. " studs")
print(string.format("RECRUITMENT OFFICE TEST: %d failed", fails))
RO_FAILS = fails
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    print(r.stdout.strip())
    fails = 0 if (r.returncode == 0 and "RECRUITMENT OFFICE TEST: 0 failed" in r.stdout) else 1
    if r.returncode != 0:
        print(r.stderr.strip()[-2000:])

    def check(ok, msg):
        nonlocal fails
        print(("ok    " if ok else "FAIL  ") + msg)
        if not ok:
            fails += 1

    E = (CL / "Controllers/EndgameController.luau").read_text(encoding="utf-8")
    Z = (CL / "Controllers/RebirthZoneController.luau").read_text(encoding="utf-8")
    RZS = (SV / "Services/RebirthZoneService.luau").read_text(encoding="utf-8")
    ES = (SV / "Services/EndgameService.luau").read_text(encoding="utf-8")
    check(E.count("function EndgameController.OpenRecruitmentOffice(") == 1 and E.count("function EndgameController.CloseRecruitmentOffice(") == 1,
          "one central OpenRecruitmentOffice / CloseRecruitmentOffice")
    check('warn("[RECRUITMENT OPEN]", source, os.clock())' in E and 'warn("[RECRUITMENT CLOSE] Reason:", reason, os.clock())' in E, "the [RECRUITMENT OPEN] / [RECRUITMENT CLOSE] Reason logs")
    check('EndgameController.OpenRecruitmentOffice("Plaza"' in E and 'EC.OpenRecruitmentOffice("Zone"' in Z and 'EC.OpenStation("Recruits")' not in Z,
          "both interaction points open through it (plaza prompt, the zone kiosk's ZoneOpen with its point)")
    reasons = set(re.findall(r'CloseRecruitmentOffice\("(\w+)"\)', E)) | set(re.findall(r'closeList\("(\w+)"\)', E))
    check(reasons == {"WalkAway", "Death", "X", "OtherMenu"}, "the only close reasons: X, WalkAway, Death, OtherMenu (" + ", ".join(sorted(reasons)) + ")")
    check(not re.search(r"PromptHidden|TriggerEnded|PromptButtonHoldEnded", E), "nothing listens to the prompt hiding / ending (it can never close the menu)")
    check('listOpen ~= "Recruits" then' in E and "a scratch" in E, "a damage scratch no longer closes the Recruitment Office (death does)")
    check("if listOpen == \"Recruits\" then\n\t\trecruitSource, recruitAnchor = source, point or recruitAnchor\n\t\treturn" in E.replace("\r\n", "\n"),
          "a second open while it is open adds no second loop / connection (only re-points the anchor)")
    check("kioskOf[player.UserId][zoneId] = panel" in RZS and "function RebirthZoneService.KioskPoint(player: Player, activity: string)" in RZS
          and "if who.UserId == uid then" in RZS, "the kiosk point is HIS (keyed by UserId; only his prompt trigger opens it): another player's office cannot affect mine")
    check('KioskPoint(player, "drill")' in ES and "EndgameConfig.Station.BuyRange" in ES, "the server's AtStation accepts his own kiosk for Recruitment buys (was plaza-only: kiosk buys were refused)")
    print("RECRUITMENT OFFICE TEST (all): %d failed" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
