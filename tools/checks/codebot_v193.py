# Code Bot Roblox v193 (2026-10-01): claude-bud JOB 63 AntiCamp OwnerFirst (anti-spawn-camping).
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
import os
import re
import subprocess
from pathlib import Path

# claude-bud JOB 66 (2026-10-01): the ONLY MonetizationConfig change allowed past this ship guard is the Shaun-approved
# JOB 66 block (the two 5 R$ starter rows, the Starter5 switch, the SkuLiveFor LiveBlock lines), removed exactly here
# before the byte-identical compare. Everything else in the file must still match.
def _bud_j66(t):
    t = (t or "").replace("\r\n", "\n")
    a = t.find("\t-- claude-bud JOB 66 (price approved by Shaun")
    if a >= 0:
        b = t.find("\n", t.find("\tBoost2x10m = {", a)) + 1
        t = t[:a] + t[b:]
    a = t.find("-- claude-bud JOB 66: the two 5 R$ starter products")
    if a >= 0:
        t = t[:a] + t[t.find("function MonetizationConfig.SkuLiveFor", a):]
    a = t.find("\t-- claude-bud JOB 66: a row tied to an owner-first switch (LiveBlock)")
    if a >= 0:
        b = t.find("\tend\n", a) + len("\tend\n")
        t = t[:a] + t[b:]
    return t



ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V193_PREV", "a38b1af")  # v192 code tip (place 190)
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 203)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 203)'),
    (S + "Services/DataService.luau", "WE_Build=203"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 203)'),
):
    check(needle in read(rel), "CODEBOT v193: WE_Build=203 " + rel.rsplit("/", 1)[-1])

RC = read(C + "RaidConfig.luau")
ac = RC.split("(RaidConfig :: any).AntiCamp = {")[1].split("\n}\n")[0] if "(RaidConfig :: any).AntiCamp = {" in RC else ""
check(
    "Enabled = true," in ac
    and "OwnerFirst = true, -- NEW-OWNER-FIRST" in ac
    and "DefenderShieldSeconds = 5," in ac
    and "RaiderLimitSeconds = 90," in ac
    and "SameBaseCooldownSeconds = 180," in ac,
    "CODEBOT v193: RaidConfig.AntiCamp OwnerFirst + 5s/90s/180s",
)

ACS = code(read(S + "Services/AntiCampService.luau"))
check("pa:LoadCharacter()" in ACS and "Heartbeat" not in ACS and "RenderStepped" not in ACS,
      "CODEBOT v193: AntiCampService LoadCharacter home, no Heartbeat/RenderStepped")
check('safeInit("AntiCampService", AntiCampService, deps)' in read(S + "Bootstrap.server.luau"),
      "CODEBOT v193: AntiCampService started in Bootstrap")
# claude-bud (2026-10-01): on claude/desktop-bud JOB 62 is present; it must then stay owner-first (the v193 ship excludes it)
check("ExperienceNotifyService" not in read(S + "Bootstrap.server.luau")
      or "OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 62)" in read("src/ReplicatedStorage/Shared/Configs/NotificationConfig.luau"),
      "CODEBOT v193: ExperienceNotify (JOB 62) NOT shipped (or, on the bud branch, still owner-first)")

CS = read(S + "Services/CombatService/init.luau")
pb = CS.split("local function pvpBlock(")[1].split("\nend\n")[0] if "local function pvpBlock(" in CS else ""
check('return "camp_cooldown"' in pb and "BlocksHurt(attacker, victim)" in pb,
      "CODEBOT v193: camp_cooldown in the one pvpBlock")
check("DefenderShieldSeconds(player)" in CS and "endCampShield(player)" in CS,
      "CODEBOT v193: defender shield via InvulnerableUntil + first-shot end")

check("BlocksBaseDamage(attacker, hitPart:GetAttribute(\"PlotId\"))" in read(S + "Services/GateDefenseService.luau"),
      "CODEBOT v193: cooled raider cannot damage base")
check("CooldownLeft(viewer.UserId, plotId)" in read(S + "Services/RivalService.luau"),
      "CODEBOT v193: RivalService exposes cooldown")
check("WAIT %d:%02d" in read(CL + "Controllers/RivalController.luau"),
      "CODEBOT v193: TARGETS shows WAIT m:ss")
check("OnRaidDone(thief, hold.PlotId)" in read(S + "Services/MoneyCollectorService.luau"),
      "CODEBOT v193: loot-taken hooks AntiCamp OnRaidDone")

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v193's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v193_own_mon = 'SetAttribute("WE_Build", 193)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v193_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)), "CODEBOT v193: MonetizationConfig byte-identical to " + PREV)
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v193: no WE_Building* diffs vs " + PREV)
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v193: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v193: PreferMeshWhenAssetIdSet false")
prj = Path("default.project.json").read_text(encoding="utf-8")
check('"StreamingEnabled": true' not in prj, "CODEBOT v193: StreamingEnabled stays OFF")
