# Code Bot Roblox v163 (2026-10-01): Shaun's three asks.
#  1. TARGETS (JOB 41 C, RivalConfig OwnerFirst=true): the pill top-right under the top-bar pills (Right 16, Top 64 real
#     px under the topbar inset; 1024x471 phone: x 880..1008, y 122..170) was hidden whenever the server listed 0
#     targets (no other player online / everyone shielded or new-player protected / under $10k in the ATM / too
#     strong / no soldiers / the Guided hold), which for the owner is almost always. Now always visible for a live
#     player, dimmed with no badge when empty, and the list opens on "No targets right now - rivals appear when other
#     players have cash to raid" + the server's one-line reason (RivalTargets.Why). Steps aside for Modal / Dead / the
#     Recruit Pack card in the same corner.
#  2. Owner / admin Guided replay in TEST MODE: /replaytutorial (alias /replayguided) or Settings > ADMIN > REPLAY GUIDED
#     TUTORIAL (test); server-authoritative (AdminService allowlist), TutorialService.ReplayGuided snapshots the tutorial
#     fields (profile.GuidedReplay) and restores them at the end / SKIP / the next load; no cash, no analytics.
#  3. TOP SUPPORTERS: every saved Robux grant (OnGranted) and confirmed pass (OnPassOwned) writes the board at once
#     (the 90 s throttle + throttled leave flush lost a buyer who left soon after buying); never-counted passes owned
#     on Roblox are credited once at their real price (profile.LB.PassCredit ledger; legacy profiles never double).
# Do not flip Rival / Guided / RecruitPack / RatePrompt / Army OwnerFirst. PreferMesh OFF.
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/"

for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 192)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 192)'),
    (S + "Services/DataService.luau", "WE_Build=192"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 192)'),
):
    check(needle in read(rel), "CODEBOT v163: WE_Build=192 " + rel.rsplit("/", 1)[-1])

_RC = read(C + "RivalConfig.luau")
_RCTL = read(CL + "RivalController.luau")
_RS = read(S + "Services/RivalService.luau")
check("OwnerFirst = false, -- codebot_v166" in _RC, "CODEBOT v163: RivalConfig OwnerFirst=false (v166 flip-all-live)")
check('EmptyText = "No targets right now — rivals appear when other players have cash to raid"' in _RC,
      "CODEBOT v163: TARGETS empty-state text")
check("b.Visible = true" in _RCTL and "pl.Visible = #rows > 0" not in _RCTL, "CODEBOT v163: TARGETS pill always visible (not hidden when empty)")
check('GetFlag("Modal") and not open' in _RCTL and "WE_RecruitPack" in _RCTL, "CODEBOT v163: the pill steps aside for other panels / the Recruit Pack card")
check("function RivalService.WhyEmpty" in _RS and "Why = if #rows == 0 then why else nil" in _RS, "CODEBOT v163: an empty push carries the reason")
# v168 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v168.py (the TARGETS card: RivalConfig.Layout,
# the same 1024x471 checks on the new geometry):
## phone 1024x471 geometry (real px; topbar inset 58): the pill clears the top-centre stack and the touch FIRE button
#_P = re.search(r"Pill = \{ Width = (\d+), Height = (\d+), Top = (\d+), Right = (\d+) \}", _RC)
#check(_P is not None, "CODEBOT v163: RivalConfig.Pill geometry")
#if _P:
#    w, h, top, right = (int(x) for x in _P.groups())
#    W, H, INSET, S07 = 1024, 471, 58, 0.70
#    pill = (W - right - w, INSET + top, W - right, INSET + top + h)
#    stack_right = W / 2 + (W * 0.62) / 2  # HudConfig.TopStack.MaxWidthScale
#    fire_top = H - (152 + 88) * S07  # HudConfig.TouchCombat.Fire (content bottom = screen bottom)
#    check(pill[0] > stack_right, "CODEBOT v163: 1024x471 the pill (x %d) is right of the top-centre stack (x %.0f)" % (pill[0], stack_right))
#    check(pill[3] + 16 <= fire_top, "CODEBOT v163: 1024x471 the pill (bottom %d) is clear of FIRE (top %.0f)" % (pill[3], fire_top))
#    check(pill[1] >= INSET + 8, "CODEBOT v163: 1024x471 the pill sits under the topbar row (compass)")

_TS = read(S + "Services/TutorialService.luau")
_GS = read(S + "Services/GuidedService.luau")
_AD = read(S + "Services/AdminService.luau")
_ST = read(CL + "SettingsController.luau")
_TC = read(C + "TutorialConfig.luau")
check("function TutorialService.ReplayGuided(player: Player): (boolean, string)" in _TS and "profile.GuidedReplay = { Fields = fields" in _TS,
      "CODEBOT v163: TutorialService.ReplayGuided snapshots the tutorial fields")
check("restoreReplay(player, profile)\n\t\tif not tutorialEnabled() then" in _TS, "CODEBOT v163: a load always restores a left-over replay")
check("if isReplay(profile) then 0 else GuidedService.RecruitGap" in _GS and "if isReplay(profile) then 0 else math.max(0, math.floor(tonumber(G.GuidedRewardCash)" in _GS,
      "CODEBOT v163: no cash in a replay")
check('elseif cmd == "replaytutorial" or cmd == "replayguided" then' in _AD and '"WE_ReplayTutorial", "/replaytutorial", "/replayguided"' in _AD,
      "CODEBOT v163: admin remote + chat command")
check('section("ADMIN")' in _ST and "REPLAY GUIDED TUTORIAL (test)" in _ST and "table.find(AdminConfig.UserIds, player.UserId) ~= nil then\n\t\tsection(\"ADMIN\")" in _ST,
      "CODEBOT v163: Settings ADMIN row only for AdminConfig.UserIds")
check(re.search(r"TutorialConfig\.Guided = \{[^}]*?OwnerFirst = false", _TC, re.S) is not None, "CODEBOT v163: Guided OwnerFirst=false (v166 flip-all-live)")

_ES = read(S + "Services/EngagementService.luau")
check("MS.OnGranted(EngagementService.OnGranted)" in _ES and "MS.OnPassOwned(EngagementService.OnPassOwned)" in _ES,
      "CODEBOT v163: TOP SUPPORTERS hears every saved grant + pass")
check("pcall(writeSupporters, p, leaving" in _ES,  # Code Bot v175: + the why argument ("leave")
      "CODEBOT v163: the leave flush always writes a changed supporter value")
check("lb.PassCredit" in _ES and "passLegacy[player.UserId] = (math.floor(tonumber(m.Purchases) or 0) - receiptCount(profile)) > 0" in _ES,
      "CODEBOT v163: pass credit ledger, legacy profiles never double counted")
check("if isBoardExcluded(uid) then\n\t\treturn false" in _ES, "CODEBOT v163: admin / owner never written to TOP SUPPORTERS")
_VAS = read(C + "StructureVisualConfig.luau")
check("PreferMeshWhenAssetIdSet = false" in _VAS, "CODEBOT v163: PreferMeshWhenAssetIdSet stays false (PreferMesh off)")

if os.environ.get("SKIP_SIM") != "1":
    env = dict(os.environ)
    env.setdefault("LUAU", os.path.expanduser("~/.local/bin/luau"))
    r = subprocess.run([sys.executable, "tools/sim/run_codebot_v163_test.py"], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=600)
    tail = (r.stdout or "").strip().splitlines()[-1:] or ["(no output)"]
    check(r.returncode == 0, "CODEBOT v163: tools/sim/run_codebot_v163_test.py " + tail[0])
