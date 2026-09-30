# Code Bot Roblox v147 (2026-09-30): live error report fixes + a phone per-frame cost (Creator Hub, last 7 days).
#  * DataStore "request was added to queue": the leave save wrote lock_<userId> twice back to back (Refresh + Release),
#    and the 15 s heartbeat Refresh landed in the same instant as the 60 s autosave Refresh.
#  * [ArmyDebug] SLOT CHANGE / REPOSITION warns only for a player with the army debug on.
#  * not authorized (live LoadAsset in place 97112936860418): Floodlight/Lamp 116763933, Flag/UpgradeFlag 1679839739,
#    GateDefense.Sandbags 3525056989 -> 0 (the Part kit that was already showing stays).
#  * client HTTP 429 sound loads: AudioController warms each distinct asset id once, staggered, after join.
#  * WorldPromptController pad overlap loop: far pads skipped with an exact bounding-sphere test (no per-frame strings).
# Unchanged: prices, passes, shop, ads, server size 10, PreferMesh OFF, WE_Building*, no fast travel. WE_Build 147.
from pathlib import Path as _P147


def _cb147(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd147(p):
	q = _P147(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S147 = "src/ServerScriptService/Server/"
_C147 = "src/ReplicatedStorage/Shared/Configs/"
_CL147 = "src/StarterPlayer/StarterPlayerScripts/Client/"

# v148 (Code Bot Roblox): the WE_Build=147 pins are superseded in tools/checks/codebot_v148.py (WE_Build=148).

# DataStore queue
_DS = _rd147(_S147 + "Services/DataService.luau")
_SL = _rd147(_S147 + "Modules/SessionLock.luau")
_cb147("if ok and not releaseLock then\n" in _DS and "SessionLock.Refresh(userId)\n\telseif not ok then" in _DS,
	"CODEBOT v147: a releasing save does not Refresh the lock right before Release (one write on lock_<id>)")
_cb147("SessionLock.Release(userId)" in _DS, "CODEBOT v147: the leave save still releases the lock")
_cb147("local REFRESH_MIN_GAP = 7" in _SL and "nowClock - (lastLockWriteAt[userId] or -math.huge) < REFRESH_MIN_GAP" in _SL,
	"CODEBOT v147: SessionLock.Refresh skips a second write within 7 s")
_cb147("Constants.SessionLockTtlSeconds = 45" in _rd147("src/ReplicatedStorage/Shared/Constants.luau")
	and "Constants.SessionLockRefreshSeconds = 15" in _rd147("src/ReplicatedStorage/Shared/Constants.luau"),
	"CODEBOT v147: lock TTL 45 > heartbeat 15 + skip gap 7 (lock stays fresh)")

# ArmyDebug
_AC = _rd147(_S147 + "Modules/ArmyController.luau")
_SC = _rd147(_S147 + "Modules/SoldierController.luau")
_cb147("\t\t\t\t\tif debugOn then\n\t\t\t\t\t\twarn(string.format(\"[ArmyDebug] SLOT CHANGE" in _AC, "CODEBOT v147: SLOT CHANGE warn only with debugOn")
_cb147("if loud then warn(string.format(\"[ArmyDebug] REPOSITION" in _SC and 'GetAttribute("WE_ArmyDebug") == true' in _SC,
	"CODEBOT v147: REPOSITION warn only for an owner with WE_ArmyDebug")
_cb147("unit.Model:PivotTo(cf)" in _SC, "CODEBOT v147: the reposition itself is unchanged")

# unauthorized ids
_VA = _rd147(_C147 + "VisualAssetConfig.luau")
for _id in ("116763933", "1679839739", "3525056989"):
	_cb147(("ModelAssetId = " + _id) not in _VA, "CODEBOT v147: not-authorized id " + _id + " is no longer a live ModelAssetId")
_cb147("else 3525056989" not in _rd147(_S147 + "Services/GateDefenseService.luau"), "CODEBOT v147: GateDefense sandbag fallback id gone")
_cb147("Flag = { ModelAssetId = 0," in _VA and "Floodlight = { ModelAssetId = 0," in _VA, "CODEBOT v147: WarzoneProps Flag + Floodlight = Part kit")

# sounds
_AU = _rd147(_CL147 + "Modules/AudioController.luau")
_SN = _rd147(_C147 + "SoundConfig.luau")
_cb147("elseif not seenIds[id] then" in _AU and "task.delay(warmDelay, function()" in _AU and "task.wait(warmGap)" in _AU,
	"CODEBOT v147: warm-up loads each distinct asset id once, staggered")
_cb147("WarmDelaySeconds = 4," in _SN and "WarmGapSeconds = 0.35," in _SN, "CODEBOT v147: SoundConfig.Mix warm-up knobs")

# pad loop
_WP = _rd147(_CL147 + "Controllers/WorldPromptController.luau")
_cb147("local PAD_MAX_MARGIN = math.max(OVERLAP_MARGIN, CONSOLE_MARGIN)" in _WP and "and ck ~= nil and not lastOverlap[ck] then\n\t\t\t\t\tcontinue" in _WP,
	"CODEBOT v147: far pads skipped (exact sphere bound), an entered pad still gets its leave")
_cb147("local rx, ry, rz = h.X + PAD_MAX_MARGIN, h.Y + 8, h.Z + PAD_MAX_MARGIN" in _WP and "localPos.Y <= half.Y + 8" in _WP,
	"CODEBOT v147: the skip bound covers pointInPad's box (+8 up)")

# guard rails
_SV = _rd147(_C147 + "StructureVisualConfig.luau")
_cb147("PreferMeshWhenAssetIdSet = false," in _SV, "CODEBOT v147: PreferMesh stays OFF")
_cb147("MaxPlayersPerServer = 10," in _rd147(_C147 + "GameConfig.luau") and "MaxPlots = 10," in _rd147(_C147 + "BaseConfig.luau"),
	"CODEBOT v147: server size 10 / 10 plots unchanged")
_RC = _rd147(_C147 + "RigConfig.luau")
_cb147("Hold = 182393478," in _RC and "Idle = 180435571," in _RC and "Walk = 180426354," in _RC and "Aim = 183817498," in _RC,
	"CODEBOT v147: soldier animation ids unchanged (Roblox-owned, verified loadable in the live place)")
