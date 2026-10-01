# Code Bot Roblox v185 (2026-10-01): DOUBLE WEEKEND (EventConfig DoubleWeekend1): 2x XP / 2x cash / 2x kills,
# Fri 2 Oct 2026 21:00 -> Sun 4 Oct 2026 21:00 Dublin (20:00 UTC). Owner-first preview BEFORE the start only.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged (no price change).
import datetime as dt
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V185_PREV", "36b0f31")  # v184 live tip (place 182)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 196)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 196)'),
    (S + "Services/DataService.luau", "WE_Build=196"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 196)'),
):
    check(needle in read(rel), "CODEBOT v185: WE_Build=196 " + rel.rsplit("/", 1)[-1])

# --- the config: times and multipliers ---
EC = code(read(C + "EventConfig.luau"))
start = int(dt.datetime(2026, 10, 2, 20, 0, tzinfo=dt.timezone.utc).timestamp())
end = int(dt.datetime(2026, 10, 4, 20, 0, tzinfo=dt.timezone.utc).timestamp())
check((start, end) == (1790971200, 1791144000), "CODEBOT v185: python UTC 2026-10-02/04 20:00 = 1790971200 / 1791144000")
check('Id = "DoubleWeekend1"' in EC, "CODEBOT v185: EventConfig.Id DoubleWeekend1")
check(f"StartUnix = {start}," in EC and f"EndUnix = {end}," in EC, "CODEBOT v185: EventConfig Start/End = Fri 21:00 .. Sun 21:00 Dublin")
for k in ("XPMult = 2,", "CashMult = 2,", "KillMult = 2,", "OwnerUserId = 470626172,"):
    check(k in EC, "CODEBOT v185: EventConfig " + k)
check(re.search(r"OwnerFirst = (true|false),", EC) is not None, "CODEBOT v185: EventConfig.OwnerFirst present")
check(re.search(r'EventId = "\d*",', EC) is not None, "CODEBOT v185: EventConfig.EventId is a string")
af = EC.split("function EventConfig.ActiveFor")[1].split("\nend")[0]
check("if EventConfig.InWindow(now) then" in af and af.index("if EventConfig.InWindow(now)") < af.index("previewOn == true"),
      "CODEBOT v185: inside the window it is live for everyone BEFORE any OwnerFirst / preview test")
check("now < EventConfig.StartUnix and previewOn == true and tonumber(userId) == EventConfig.OwnerUserId" in af,
      "CODEBOT v185: preview = owner only, before StartUnix only")
for r in ("devproduct", "purchase_refund", "admin"):
    check(f"\t\t{r} = true," in EC.split("CashExemptReasons")[1].split("}")[0], "CODEBOT v185: event cash exempt " + r)

# --- server module ---
DE = code(read(S + "Modules/DoubleEvent.luau"))
check("os.time()" in DE and "EventConfig.ActiveFor" in DE, "CODEBOT v185: DoubleEvent uses the server os.time()")
check("EventConfig.KillReasons[key]" in DE and "EventConfig.KillMult" in DE, "CODEBOT v185: kill reasons take KillMult (not 2x on top of 2x)")

# --- the grant hooks ---
ECO = code(read(S + "Services/EconomyService.luau"))
cm = ECO.split("local function cashMultFor")[1].split("\nend")[0]
check("if not isExempt then" in cm and "DE.CashMult(player, reason)" in cm.split("if not isExempt then")[1],
      "CODEBOT v185: cash hook inside cashMultFor's NON-exempt stack (multiplies with the 2x pass)")
check("applyCashMult(player, profile, amount, reason)" in ECO.split("function EconomyService.AddCash")[1].split("\nend")[0],
      "CODEBOT v185: AddCash still grants through applyCashMult")
check("applyCashMult(player, profile, amount, reason)" in ECO.split("function EconomyService.AccruePendingCash")[1].split("\nend")[0],
      "CODEBOT v185: passive accrual multiplied at accrue time (doubled only while it accrues in the window)")
XP = code(read(S + "Services/XPService.luau"))
ax = XP.split("function XPService.AddXP")[1].split("\nend")[0]
check("DE.XPMult, player, reason" in ax and ax.index("GetXPMultiplier") < ax.index("DE.XPMult") < ax.index("profile.XP += amount"),
      "CODEBOT v185: XP hook in AddXP after the pass multiplier, before the grant")
MS = code(read(S + "Services/MissionService.luau"))
check('objectiveType == "KillPlayer" or objectiveType == "KillNPC"' in MS and "DE.KillCount" in MS,
      "CODEBOT v185: kill missions count KillMult")
ES = code(read(S + "Services/EngagementService.luau"))
check(ES.count("+ kc") == 6, "CODEBOT v185: MOST KILLS (pvp + defender) and ARMY KILLS boards count KillMult")
CS = code(read(S + "Services/CombatService/init.luau"))
check('grantRewards(attacker, CombatConfig.PlayerKill.Cash, CombatConfig.PlayerKill.XP, "pvp_kill")' in CS,
      "CODEBOT v185: pvp kill grant unchanged (doubled inside AddCash/AddXP)")
RS = code(read(S + "Services/RetentionService.luau"))
check("OfflineFactor(" in RS and "mult /= em" in RS, "CODEBOT v185: offline pay doubled only for the in-window span")
AD = code(read(S + "Services/AdminService.luau"))
check('cmd == "eventpreview"' in AD and "player.UserId ~= EC.OwnerUserId" in AD, "CODEBOT v185: /eventpreview owner-only")
for rel in ("Services/MonetizationService.luau",):
    check("DoubleEvent" not in read(S + rel), "CODEBOT v185: no event hook in " + rel)

# --- client banner ---
UI = code(read(CL + "Controllers/DoubleWeekendController.luau"))
check("Heartbeat" not in UI and "RenderStepped" not in UI and "task.wait(1)" in UI, "CODEBOT v185: banner = one 1 s task.wait loop")
# v192 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v192.py (no banner: one-time pop-up + chip under TARGETS): #check("RegisterTopStack" in UI, "CODEBOT v185: banner in the HUD top stack (no overlap)")
check("PromptRsvpToEventAsync" in UI and "GetEventRsvpStatusAsync" in UI and "pcall" in UI, "CODEBOT v185: NOTIFY ME RSVP calls pcall'd")
check("DoubleWeekendController" in read(CL + "Bootstrap.client.luau"), "CODEBOT v185: Bootstrap inits the banner")

# --- unchanged rules ---
prj = read("default.project.json")
check('"StreamingEnabled": true' not in prj, "CODEBOT v185: StreamingEnabled stays OFF")
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v185: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v185: PreferMeshWhenAssetIdSet false")
prev = shipped(C + "MonetizationConfig.luau", PREV)
check(prev is None or prev == read(C + "MonetizationConfig.luau"), "CODEBOT v185: MonetizationConfig byte-identical to v184 (no price change)")
r = subprocess.run(["git", "diff", "--name-only", PREV, "--"], capture_output=True, text=True, cwd=ROOT)
check("WE_Building" not in (r.stdout or ""), "CODEBOT v185: no WE_Building* files touched")
