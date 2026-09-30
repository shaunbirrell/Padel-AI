# Code Bot Roblox v153 (2026-09-30, Shaun approved "ship the sales fixes"): live for EVERYONE (timing / bug fixes).
#  1. First offer at ~2 minutes of play whatever the tutorial state (MonetizationConfig.FirstOffer.AtPlaySeconds 120;
#     the old quiet window was "tutorial done, or 900 s"); not held for the tutorial card, still waits out combat.
#  2. The Starter Pack is marked StarterBundleOffered only when the client confirms it SHOWED (OfferResult remote +
#     Server/Modules/OfferLedger); dropped / refused / unanswered = re-queued 45 s later, slot refunded, max 4 sends.
#  3. Analytics: ProductPrompted now gets productKey (it sent only `key`); custom PassBought / OfferShown / OfferDropped.
# Prices / passes / products unchanged. Owner-first flags unchanged. WE_Build 153.
import os as _os153
import subprocess as _sp153
import re as _re153
from pathlib import Path as _P153


def _cb153(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd153(p):
	q = _P153(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S153 = "src/ServerScriptService/Server/"
_C153 = "src/ReplicatedStorage/Shared/Configs/"
_CL153 = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/"

for _f in (_S153 + "Services/DataService.luau", _S153 + "Services/BaseService.luau", _S153 + "EarlyRemotes.server.luau"):
	_cb153('SetAttribute("WE_Build", 153)' in _rd153(_f), "CODEBOT v153: WE_Build=153 " + _f.rsplit("/", 1)[-1])
_cb153("WE_Build=153" in _rd153(_S153 + "Services/DataService.luau"), "CODEBOT v153: DataService profile-loaded log says WE_Build=153")

_MC = _rd153(_C153 + "MonetizationConfig.luau")
_MS = _rd153(_S153 + "Services/MonetizationService.luau")
_TS = _rd153(_S153 + "Services/TutorialService.luau")
_NC = _rd153(_CL153 + "NotificationController.luau")
_SHC = _rd153(_CL153 + "ShopController.luau")
_AC = _rd153(_C153 + "AnalyticsConfig.luau")

# 1. first-offer timing
_fo = _MC.split("\tFirstOffer = {", 1)[1].split("\n\t},", 1)[0] if "\tFirstOffer = {" in _MC else ""
_cb153("Enabled = true," in _fo and "AtPlaySeconds = 120," in _fo, "CODEBOT v153: FirstOffer Enabled, AtPlaySeconds 120 (live for everyone, no OwnerFirst)")
_cb153("OwnerFirst" not in _fo, "CODEBOT v153: FirstOffer is not owner-first (Shaun: bug / timing fix for everyone)")
_cb153("MaxSendsPerSession = 4," in _fo and "RequeueSeconds = 45," in _fo and "AckTimeoutSeconds = 100," in _fo, "CODEBOT v153: re-queue limits in config")
_cb153("SoftOfferSessionCooldownSeconds = 240," in _MC and "SoftOfferSessionMax = 3," in _MC, "CODEBOT v153: the D8 budget stays (240 s apart, 3 a session)")
_hc = _rd153(_C153 + "HudConfig.luau")
_cb153("MaxPerSession = 3," in _hc and "MinGapSeconds = 240," in _hc, "CODEBOT v153: the client offer throttle stays (3 / 240 s)")
_cb153("if started == nil or now - started < (tonumber(first.AtPlaySeconds) or 120) then" in _MS, "CODEBOT v153: ClaimSoftOfferSlot quiet window = first 120 s of play, tutorial-independent")
_cb153("mon.ScheduleFirstOffer(player, if afterTutorial then \"tutorial_complete\" else \"first_offer\", delaySec)" in _TS
	and "if profile.TutorialComplete == true or firstOn then" in _TS, "CODEBOT v153: TutorialService schedules the first offer at load for every player")
_cb153("local FIRST_IGNORES: { [string]: boolean } = { Tutorial = true, Drawn = true }" in _NC, "CODEBOT v153: a First offer is not held for the tutorial card / a drawn gun (RecentCombat still defers)")
_cb153('HudLayout.BindVisibility(f, { HideWhen = { "Modal", "Driving", "Dead" } }' in _NC, "CODEBOT v153: the offer pill still hides while driving / modal / dead")

# 2. Starter Pack: marked only on the client's "shown"
_cb153(_P153(_S153 + "Modules/OfferLedger.luau").is_file(), "CODEBOT v153: Server/Modules/OfferLedger present")
_try = _MS.split("function MonetizationService.TrySoftOfferStarterBundle", 1)[1].split("\nend\n", 1)[0] if "function MonetizationService.TrySoftOfferStarterBundle" in _MS else ""
_cb153("ackId = offerLedger:Sent(player.UserId, \"StarterBundle\"" in _try and "else\n\t\tprofile.StarterBundleOffered = true" in _try,
	"CODEBOT v153: the Starter send records a pending ack; the flag at send only when FirstOffer is off")
_cb153("profile.StarterBundleOffered = true" in _MS.split("function MonetizationService._OfferResult", 1)[1][:1200], "CODEBOT v153: StarterBundleOffered set on the client's 'shown'")
_cb153('"OfferResult", key, result, ackId' in _MS, "CODEBOT v153: OfferResult handler behind RemoteGate")
_cb153('OfferResult = { "string:32", "string:12", "number?" }' in _rd153(_C153 + "SecurityConfig.luau"), "CODEBOT v153: OfferResult schema")
_cb153('starterAnswer(ackId, "shown")' in _SHC and 'starterAnswer(ackId, "dropped")' in _SHC and 'starterAnswer(ackId, "refused")' in _SHC, "CODEBOT v153: the client answers shown / dropped / refused")

# 3. analytics
_cb153(_MS.count("productKey = productKey, -- Code Bot v153") == 1 and "productKey = passKey, -- Code Bot v153: AnalyticsConfig Custom ProductPrompted" in _MS,
	"CODEBOT v153: SHOP_PROMPT (DevProduct + GamePass) sends productKey")
_cb153('SHOP_PROMPT = { Name = "ProductPrompted", Field = "productKey" }' in _AC, "CODEBOT v153: ProductPrompted reads productKey")
_cb153('PASS_OWNED = { Name = "PassBought", Value = "price", Field = "productKey" }' in _AC and 'OFFER_SHOWN = { Name = "OfferShown", Field = "productKey" }' in _AC,
	"CODEBOT v153: custom PassBought + OfferShown events")

# the sim (real MonetizationService + OfferLedger in a virtual clock)
_lu = _os153.environ.get("LUAU") or str(_P153.home() / ".local/bin/luau")
if _P153(_lu).is_file():
	_r = _sp153.run(["python3", "tools/sim/run_first_offer_test.py"], capture_output=True, text=True, env=dict(_os153.environ, LUAU=_lu))
	_cb153(_r.returncode == 0 and "FIRST OFFER TEST: 0 failed" in _r.stdout, "CODEBOT v153: tools/sim/run_first_offer_test.py 0 failed")

# unchanged: prices, owner-first flags
_cb153("		VIP = {" in _MC and "RobuxPrice = 199," in _MC.split("VIP = {", 1)[1][:400], "CODEBOT v153: VIP RobuxPrice stays 199")
_sb = _MC.split("\t\tStarterBundle = {", 1)[1][:300] if "\t\tStarterBundle = {" in _MC else ""
_cb153("Id = 3713839505," in _sb and "RobuxPrice = 149," in _sb, "CODEBOT v153: Starter Pack Id / 149 R$ unchanged")
_cb153("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _rd153(_C153 + "BaseMarkerConfig.luau"), "CODEBOT v153: BaseMarker OwnerFirst stays true")
_cb153("cfg.SpeedV2 = {\n\tEnabled = true,\n\tOwnerFirst = true," in _MC, "CODEBOT v153: SpeedV2 OwnerFirst stays true")
_cb153("FastTravelEnabled = false" in _rd153(_C153 + "MapConfig.luau"), "CODEBOT v153: fast travel stays REMOVED")
_cb153("PreferMeshWhenAssetIdSet = false" in _rd153(_C153 + "StructureVisualConfig.luau"), "CODEBOT v153: PreferMesh stays OFF")
try:
	_wd = _sp153.run(["git", "diff", "-U0", "e2d82d6", "--", "src"], capture_output=True, text=True).stdout
	if _wd:
		_cb153(not any(l.startswith(("+", "-")) and "WE_Building" in l for l in _wd.splitlines()), "CODEBOT v153: no WE_Building* line changed since v152 tip")
		_cb153(not any(l.startswith(("+", "-")) and not l.startswith(("+++", "---")) and _re153.search(r"RobuxPrice\s*=|\bId\s*=\s*\d{6,}", l) for l in _wd.splitlines()),
			"CODEBOT v153: no RobuxPrice / product Id line changed since v152")
except Exception:
	pass
