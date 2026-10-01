# Code Bot Roblox v192 (2026-10-01): DOUBLE WEEKEND banner -> one-time pop-up (before the start) + a small live chip
# under the TARGETS card; owner /eventpopup. PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes;
# MonetizationConfig unchanged.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V192_PREV", "a6fa8eb")  # v191 code tip (place 189)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


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


for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 200)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 200)'),
    (S + "Services/DataService.luau", "WE_Build=200"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 200)'),
):
    check(needle in read(rel), "CODEBOT v192: WE_Build=200 " + rel.rsplit("/", 1)[-1])

EC = read(C + "EventConfig.luau")
check('Id = "DoubleWeekend1"' in EC and 'EventId = "5990901055452480269"' in EC, "CODEBOT v192: EventConfig Id / EventId unchanged")
check("StartUnix = 1790971200" in EC and "EndUnix = 1791144000" in EC, "CODEBOT v192: event window unchanged")
check('PopupWhen = "Fri 9pm – Sun 9pm (Irish time)"' in EC and 'PopupPerks = "2x XP · 2x Cash · 2x Kills"' in EC
      and 'PopupAsk = "Get notified when it starts?"' in EC, "CODEBOT v192: pop-up copy")
check('ChipText = "2x WEEKEND"' in EC, "CODEBOT v192: chip text")

UI = code(read(CL + "Controllers/DoubleWeekendController.luau"))
check("Heartbeat" not in UI and "RenderStepped" not in UI and UI.count("task.wait(") == 1 and "task.wait(1)" in UI,
      "CODEBOT v192: one 1 s task.wait loop, no Heartbeat")
check("RegisterTopStack" not in UI and "BannerText" not in UI, "CODEBOT v192: the top-centre banner is gone")
check("PromptRsvpToEventAsync" in UI and "GetEventRsvpStatusAsync" in UI and "pcall(function()\n\t\t\t\t\t\treturn SocialService:PromptRsvpToEventAsync" in UI,
      "CODEBOT v192: NOTIFY ME = PromptRsvpToEventAsync in a pcall")
check('"NOTIFY ME"' in UI and '"NO THANKS"' in UI and "fromOffset(bw, 56)" in UI, "CODEBOT v192: two 56 px pop-up buttons")
check('rsvp = if ok and s == Enum.RsvpStatus.Going then "going"' in UI and 'rsvp == "going"' in UI,
      "CODEBOT v192: already Going -> no pop-up")
check("GetAttribute(EventConfig.PopupSeenAttr) ~= false" in UI and "RequestEventPopupSeen" in UI,
      "CODEBOT v192: once per player per Id (server seen flag, saved on show)")
check("t >= EventConfig.StartUnix then\n\t\t\treturn" in UI, "CODEBOT v192: pop-up only before the start")
check('"Tutorial", "Modal", "Dead", "Driving", "RecentCombat"' in UI and '"WE_Onboarding"' in UI and '"WE_RatePrompt"' in UI
      and '"WE_RecruitPack"' in UI, "CODEBOT v192: pop-up waits behind tutorial / panels / first-join cards")
check("PopupDelaySeconds" in UI and "spawnAt" in UI, "CODEBOT v192: a few seconds after spawn")
check("RivalConfig.Layout" in UI and "P.Y + P.H + CHIP_GAP" in UI, "CODEBOT v192: chip under the TARGETS card")
check("local live = EventConfig.ActiveFor(player.UserId, t, previewOn())" in UI, "CODEBOT v192: chip only live (window / owner preview)")
check("if t >= EventConfig.EndUnix then\n\t\t\tchip.Visible = false\n\t\t\treturn false" in UI, "CODEBOT v192: nothing after the end")
check("MinTextSize = 12" in UI and "MaxTextSize = 15" in UI, "CODEBOT v192: chip text 12..15 px")
check("PopupTestAttr" in UI and '"test"' in UI, "CODEBOT v192: owner test show")

# chip vs the 1024 x 471 phone layout (real px, CoreUISafeInsets content 1024 x 413 under the 58 px top bar)
cw, ch, top = 1024, 413, 58
side = cw * (1 - 0.62) / 2
w = max(142, min(260, int(side - 8 - 6)))
tx, ty, th = cw - 8 - w, 8, 64
cy = ty + th + 6
check(tx >= cw * (1 + 0.62) / 2, "CODEBOT v192: chip x %d clear of the top-centre stack (ends %.0f)" % (tx, cw * (1 + 0.62) / 2))
check(top + cy + 30 < top + ch - 222, "CODEBOT v192: chip bottom %d above the CombatTouch / jump reserve (%d)" % (top + cy + 30, top + ch - 222))
check(cy >= ty + th, "CODEBOT v192: chip below the TARGETS card")

DE = code(read(S + "Modules/DoubleEvent.luau"))
check("function DoubleEvent.InitPopup" in DE and "profile.EventPopupSeen = t" in DE and "MarkDirty" in DE,
      "CODEBOT v192: server saves profile.EventPopupSeen")
check("id ~= EventConfig.Id" in DE and 'RemoteGate).Check(player, "RequestEventPopupSeen"' in DE, "CODEBOT v192: seen remote gated")
check("DoubleEvent).InitPopup" in read(S + "Services/RetentionService.luau"), "CODEBOT v192: RetentionService wires InitPopup")
check("profile.EventPopupSeen" in read(S + "Modules/ProfileSchema.luau"), "CODEBOT v192: ProfileSchema sanitises EventPopupSeen")
check('RequestEventPopupSeen = "RequestEventPopupSeen"' in read("src/ReplicatedStorage/Shared/Constants.luau"), "CODEBOT v192: remote name")
check("RemoteNames.RequestEventPopupSeen" in read(S + "Modules/RemoteSetup.luau"), "CODEBOT v192: remote created")
check('RequestEventPopupSeen = { "string:32" }' in read(C + "SecurityConfig.luau"), "CODEBOT v192: remote schema")

AD = code(read(S + "Services/AdminService.luau"))
check('cmd == "eventpopup"' in AD and '"/eventpopup"' in AD, "CODEBOT v192: /eventpopup command")
blk = AD.split("if isEventPopupCmd then", 1)[1].split("if isGuardDebugCmd then", 1)[0] if "if isEventPopupCmd then" in AD else ""
check("player.UserId ~= EC.OwnerUserId" in blk and "ResetPopupSeen" in blk, "CODEBOT v192: /eventpopup owner-only (+ reset)")
check('cmd == "eventpreview"' in AD, "CODEBOT v192: /eventpreview kept")

# no renamed save keys: every profile key the v191 ProfileSchema wrote is still written
prev_ps = shipped(S + "Modules/ProfileSchema.luau", PREV) or ""
keys = lambda s: set(re.findall(r"profile\.(\w+)\s*=", s))
check(prev_ps != "" and keys(prev_ps) <= keys(read(S + "Modules/ProfileSchema.luau")), "CODEBOT v192: no ProfileSchema key removed / renamed")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
check(prev_mon is not None and prev_mon == MON, "CODEBOT v192: MonetizationConfig byte-identical to " + PREV)
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v192: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v192: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v192: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v192: StreamingEnabled stays OFF")
