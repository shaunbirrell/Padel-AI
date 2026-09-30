# Code Bot Roblox v136 (2026-09-30): owner (Shaun, 14:17 Dublin) "switch everything on for everyone" + launch the
# JOB 35 premium guns as they are. OwnerFirst=false on JOB 29 retention, JOB 30 map, JOB 31 sites, store props and the
# premium guns armory. Kill switches (Enabled) stay on and in place. Pass Ids stay 0 until pasted (SOON, never
# prompted). Fast travel stays REMOVED. PreferMesh OFF. WE_Building* untouched. No Robux price changes.
import re as _re136
from pathlib import Path as _P136


def _cb136(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd136(p):
	q = _P136(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S136 = "src/ServerScriptService/Server/"
_C136 = "src/ReplicatedStorage/Shared/Configs/"
for _f in (_S136 + "Services/DataService.luau", _S136 + "Services/BaseService.luau", _S136 + "EarlyRemotes.server.luau"):
	_cb136('SetAttribute("WE_Build", 136)' in _rd136(_f), "CODEBOT v136: WE_Build=136 " + _f.rsplit("/", 1)[-1])
_cb136("WE_Build=136" in _rd136(_S136 + "Services/DataService.luau"), "CODEBOT v136: DataService profile-loaded log says WE_Build=136")

_L = "OwnerFirst = false, -- codebot_v136 launch"
_cb136("TutorialConfig.FastStart = {\n\tEnabled = true,\n\t" + _L in _rd136(_C136 + "TutorialConfig.luau"), "CODEBOT v136: FastStart live for everyone (kill switch kept)")
_cb136("\tOfflineEarnings = {\n\t\tEnabled = true,\n\t\t" + _L in _rd136(_C136 + "EconomyConfig.luau"), "CODEBOT v136: OfflineEarnings live for everyone (kill switch kept)")
_cb136("\tStreakCard = {\n\t\tEnabled = true,\n\t\t" + _L in _rd136(_C136 + "DailyRewardConfig.luau"), "CODEBOT v136: daily StreakCard live for everyone (kill switch kept)")
_cb136("\tNotifications = {\n\t\tEnabled = true,\n\t\t" + _L in _rd136(_C136 + "RetentionConfig.luau"), "CODEBOT v136: notification opt-in live for everyone (kill switch kept)")
_MC136 = _rd136(_C136 + "MapConfig.luau")
_cb136("local MapConfig = {\n\tEnabled = true,\n\t" + _L in _MC136, "CODEBOT v136: world map live for everyone (kill switch kept)")
_cb136("\tFastTravelEnabled = false,\n" in _MC136 and "FastTravelEnabled = true" not in _MC136, "CODEBOT v136: fast travel stays REMOVED")
_cb136("local SiteActivityConfig = {\n\tEnabled = true,\n\t" + _L in _rd136(_C136 + "SiteActivityConfig.luau"), "CODEBOT v136: site activities live for everyone (kill switch kept)")
_SP136 = _rd136(_C136 + "StorePropsConfig.luau")
_cb136("\tEnabled = true, -- KILL SWITCH" in _SP136 and "\t" + _L in _SP136 and 'LiveAttribute = "WE_StorePropsOff"' in _SP136,
       "CODEBOT v136: store props live for everyone (Enabled kill switch + WE_StorePropsOff live kill kept)")
_PG136 = _rd136(_C136 + "PremiumGunsConfig.luau")
_cb136("\tLive = {\n\t\tEnabled = true,\n\t\t" + _L in _PG136, "CODEBOT v136: premium guns armory live for everyone (kill switch kept)")
_PGS136 = _rd136(_S136 + "Services/PremiumGunService.luau")
_cb136('if passId(entry.PassKey) == 0 then\n\t\t\treturn "Soon", "SOON", ""' in _PGS136 and "if id == 0 then\n\t\treturn -- SOON" in _PGS136
       and "pp.Enabled = action ~= \"\"" in _PGS136, "CODEBOT v136: an Id-0 armory case shows SOON with the prompt disabled (never prompted)")
_cb136("(tonumber(premiumPass.Id) or 0) ~= 0 and PremiumGunsConfig.LiveFor" in _rd136("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"),
       "CODEBOT v136: Shop gold rows stay hidden while a pass Id is 0")
_cb136("AdminConfig.IsPlaytestOwner(player.UserId) or RunService:IsStudio()" in _PGS136, "CODEBOT v136: OwnerTestGrant stays owner / Studio only (never everyone)")

# Robux prices unchanged (the JOB 35 prices)
_MON136 = _rd136(_C136 + "MonetizationConfig.luau")
for _k, _p in (("PG_Sovereign", 99), ("PG_Quake", 249), ("PG_Longshot", 299), ("PG_Havoc", 349), ("PG_Thunderhead", 399), ("PG_Tempest", 499), ("PG_ArmoryPass", 1299)):
	_blk = _MON136.split("\t\t" + _k + " = {", 1)[1].split("},", 1)[0] if ("\t\t" + _k + " = {") in _MON136 else ""
	_cb136(("RobuxPrice = %d," % _p) in _blk, "CODEBOT v136: %s price R$ %d unchanged" % (_k, _p))

# left gated on purpose (not owner-first launch gates): kill switches / unfinished systems / mesh work
_cb136("WeaponsLive = false" in _rd136(_C136 + "AircraftWeaponConfig.luau"), "CODEBOT v136: AircraftWeaponConfig.WeaponsLive left as is (not in this launch)")
_cb136('BodyRollout = "owner"' in _rd136(_C136 + "VisualAssetConfig.luau"), "CODEBOT v136: VisualAssetConfig.BodyRollout left owner (needs WE_CHECK2)")
_cb136(_re136.search(r"^\tEnabled = false, -- master switch", _rd136(_C136 + "OpsConfig.luau"), _re136.M) is not None, "CODEBOT v136: OpsConfig (W3 Jobs) left off")
_cb136("PreferMeshWhenAssetIdSet = false" in _rd136(_C136 + "StructureVisualConfig.luau"), "CODEBOT v136: PreferMesh stays OFF")
_cb136("PreferMesh = true" not in _rd136(_C136 + "VisualAssetConfig.luau"), "CODEBOT v136: VisualAssetConfig PreferMesh not true")
