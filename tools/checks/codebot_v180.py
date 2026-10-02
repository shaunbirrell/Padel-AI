# Code Bot Roblox v180 (2026-10-01): wire the two monetization items Shaun approved and created (universe 10767159222).
#   GamePasses.OfflineCap2x  "2x Offline Cash"  Id 2002664894  149 R$  (was a DevProducts stub at Id 0; it is a Game Pass)
#   DevProducts.MissionReroll "Mission Reroll"  Id 3715836569   19 R$  (the paid reroll after the free daily one)
# EconomyConfig.OfflineEarnings.CapBoost live for everyone; MissionConfig.Core.Reroll.Robux live.
# Untouched: MissionConfig.Core.OwnerFirst, RetentionConfig.ReturnSequence.OwnerFirst, every other Id / price.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes.
import os as _cb180_os
import re as _cb180_re
import subprocess as _cb180_sp
from pathlib import Path as _cb180_Path

_cb180_ROOT = _cb180_Path(__file__).resolve().parents[2] if "__file__" in globals() and __file__.endswith("codebot_v180.py") else _cb180_Path.cwd()
_cb180_PREV = _cb180_os.environ.get("CODEBOT_V180_PREV", "5e9649b")  # the v179 live tip (place 177)
_cb180_C = "src/ReplicatedStorage/Shared/Configs/"
_cb180_S = "src/ServerScriptService/Server/"
_cb180_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"


def _cb180_read(rel):
    return (_cb180_ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def _cb180_shipped(rel, rev="719f957"):
    # Code Bot v182: the file as v180 shipped it (719f957); the current OwnerFirst state is pinned in codebot_v182.py
    _r = _cb180_sp.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=_cb180_ROOT)
    return (_r.stdout or "").replace("\r\n", "\n") if _r.returncode == 0 else ""


def _cb180_check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _cb180_code(src):
    src = _cb180_re.sub(r"--\[\[.*?\]\]", "", src, flags=_cb180_re.S)
    return "\n".join(l.split("--", 1)[0] for l in src.splitlines())


def _cb180_skus(src):
    """(section, key) -> {"Id": n, "RobuxPrice": n, "OverhaulRobuxPrice": n} for GamePasses / DevProducts."""
    out = {}
    section = None
    cur = None
    for line in _cb180_code(src).splitlines():
        m = _cb180_re.match(r"^\t(GamePasses|DevProducts) = \{\s*$", line)
        if m:
            section = m.group(1)
            continue
        if section and _cb180_re.match(r"^\t\}", line):
            section = None
            cur = None
            continue
        if not section:
            continue
        m = _cb180_re.match(r"^\t\t([A-Za-z_][A-Za-z0-9_]*) = \{(.*)$", line)
        if m:
            cur = (section, m.group(1))
            out[cur] = {}
            rest = m.group(2)
        elif cur and line.startswith("\t\t\t"):
            rest = line
        else:
            if _cb180_re.match(r"^\t\t\},?\s*$", line):
                cur = None
            continue
        for f in ("Id", "RobuxPrice", "OverhaulRobuxPrice"):
            fm = _cb180_re.search(r"(?<![A-Za-z])" + f + r" = (\d+)", rest)
            if fm and f not in out[cur]:
                out[cur][f] = int(fm.group(1))
        if _cb180_re.search(r"\}\s*,?\s*$", rest) and m:
            cur = None
    return out


# ── build pins ──
for _rel, _needle in (
    (_cb180_S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 212'),
    (_cb180_S + "Services/DataService.luau", 'SetAttribute("WE_Build", 212'),
    (_cb180_S + "Services/DataService.luau", "WE_Build=212"),
    (_cb180_S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 212'),
):
    _cb180_check(_needle in _cb180_read(_rel), "CODEBOT v180: WE_Build=212 " + _rel.rsplit("/", 1)[-1])

# ── the two new SKUs: Ids + display prices ──
_cb180_MON = _cb180_read(_cb180_C + "MonetizationConfig.luau")

_cb180_now = _cb180_skus(_cb180_MON)
_cb180_check(_cb180_now.get(("GamePasses", "OfflineCap2x"), {}).get("Id") == 2002664894
             and _cb180_now[("GamePasses", "OfflineCap2x")].get("RobuxPrice") == 149,
             "CODEBOT v180: GamePasses.OfflineCap2x Id 2002664894, RobuxPrice 149 (2x Offline Cash)")
_cb180_check(("DevProducts", "OfflineCap2x") not in _cb180_now,
             "CODEBOT v180: OfflineCap2x is a Game Pass only (no DevProducts.OfflineCap2x stub left)")
_cb180_check(_cb180_now.get(("DevProducts", "MissionReroll"), {}).get("Id") == 3715836569
             and _cb180_now[("DevProducts", "MissionReroll")].get("RobuxPrice") == 19,
             "CODEBOT v180: DevProducts.MissionReroll Id 3715836569, RobuxPrice 19")
_cb180_mr = _cb180_re.search(r"\n\t\tMissionReroll = \{([^\n]*)\}", _cb180_MON)
_cb180_check(bool(_cb180_mr) and "GrantsMissionReroll = true" in _cb180_mr.group(1) and "OneTime" not in _cb180_mr.group(1)
             and "GrantEntitlement" not in _cb180_mr.group(1),
             "CODEBOT v180: MissionReroll is a consumable (GrantsMissionReroll, no OneTime / entitlement)")
_cb180_op = _cb180_re.search(r"\n\t\tOfflineCap2x = \{(.*?)\n\t\t\},", _cb180_MON, _cb180_re.S)
_cb180_check(bool(_cb180_op) and "HideFromShop" not in _cb180_op.group(1) and "Feature =" not in _cb180_op.group(1),
             "CODEBOT v180: the 2x Offline Cash pass is listed in the Shop (no HideFromShop / Feature gate)")
_cb180_check("OfflineCap2x" not in _cb180_re.search(r"RolloutKeys = \{[^\n]*\}", _cb180_MON).group(0)
             and "MissionReroll" not in _cb180_re.search(r"RolloutKeys = \{[^\n]*\}", _cb180_MON).group(0),
             "CODEBOT v180: neither new SKU is behind a RolloutKeys gate (SkuLiveFor = everyone)")

# ── every other MonetizationConfig Id / price unchanged vs the previous tip ──
try:
    _r = _cb180_sp.run(["git", "show", _cb180_PREV + ":" + _cb180_C + "MonetizationConfig.luau"], capture_output=True, text=True, cwd=_cb180_ROOT)
    _cb180_check(_r.returncode == 0 and "DevProducts = {" in (_r.stdout or ""), "CODEBOT v180: previous tip " + _cb180_PREV + " MonetizationConfig readable")
    _cb180_prev = _cb180_skus(_r.stdout or "")
    _cb180_new = {("GamePasses", "OfflineCap2x"), ("DevProducts", "MissionReroll"), ("DevProducts", "OfflineCap2x")}
    _cb180_diff = []
    for _k in sorted(set(_cb180_prev) | set(_cb180_now)):
        if _k in _cb180_new:
            continue
        if _cb180_prev.get(_k) != _cb180_now.get(_k):
            _cb180_diff.append("%s.%s %s -> %s" % (_k[0], _k[1], _cb180_prev.get(_k), _cb180_now.get(_k)))
    _cb180_check(len(_cb180_prev) == 56 and len(_cb180_now) == 56 and not _cb180_diff,
                 "CODEBOT v180: every other GamePasses / DevProducts Id + price unchanged vs %s (%d SKUs)%s"
                 % (_cb180_PREV, len(_cb180_prev), (" " + str(_cb180_diff[:6])) if _cb180_diff else ""))
    _cb180_check(_cb180_prev.get(("DevProducts", "OfflineCap2x"), {}).get("Id") == 0
                 and _cb180_prev.get(("DevProducts", "MissionReroll"), {}).get("Id") == 0,
                 "CODEBOT v180: previous tip had both stubs at Id 0 (only they changed)")
    # any other numeric Id / Price line in the file (outside the two SKUs) unchanged
    _r = _cb180_sp.run(["git", "diff", "-U0", _cb180_PREV, "--", _cb180_C + "MonetizationConfig.luau"], capture_output=True, text=True, cwd=_cb180_ROOT)
    _cb180_bad = [l for l in (_r.stdout or "").splitlines()
                  if l[:1] in "+-" and not l.startswith(("+++", "---"))
                  and _cb180_re.search(r"(Id|Price) = \d", _cb180_code(l[1:]))
                  and not _cb180_re.search(r"OfflineCap2x|MissionReroll|Id = 2002664894|RobuxPrice = 149,$", l)
                  and not (l.startswith("+") and _cb180_re.match(r"^\+	(StarterRecruit5 = \{ Id = (0|3715888533)|Boost2x10m = \{ Id = (0|3715888566)),.*RobuxPrice = 5,", l))]  # claude-bud JOB 66 (Shaun-approved 5 R$ rows; Code Bot v204: Creator Hub Ids)
    _cb180_check(_r.returncode == 0 and not _cb180_bad,
                 "CODEBOT v180: no other Id / price line changed in MonetizationConfig" + ((" " + str(_cb180_bad[:4])) if _cb180_bad else ""))
except Exception as _e:
    _cb180_check(False, "CODEBOT v180: git compare errored: " + str(_e))

# ── switches ──
_cb180_ECO = _cb180_read(_cb180_C + "EconomyConfig.luau")
_cb180_cb = _cb180_re.search(r"\n\t\tCapBoost = \{(.*?)\n\t\t\},", _cb180_ECO, _cb180_re.S)
_cb180_cbb = _cb180_code(_cb180_cb.group(1)) if _cb180_cb else ""
_cb180_check(_cb180_re.search(r"Enabled = true,", _cb180_cbb) and _cb180_re.search(r"OwnerFirst = false,", _cb180_cbb)
             and 'ProductKey = "OfflineCap2x"' in _cb180_cbb
             # Code Bot (Shaun 2026-10-01): CapMult moved to OfflineConfig.PassCapMult (superseded in codebot_v201.py)
             and "PassCapMult = 2," in _cb180_read(_cb180_C + "OfflineConfig.luau"),
             "CODEBOT v180: EconomyConfig CapBoost Enabled=true, OwnerFirst=false (everyone), OfflineCap2x, OfflineConfig.PassCapMult 2")
_cb180_oe = _cb180_re.search(r"\n\tOfflineEarnings = \{(.*?)\n\t\tCard = \{", _cb180_ECO, _cb180_re.S)
_cb180_check(bool(_cb180_oe) and "Enabled = true," in _cb180_oe.group(1) and "OwnerFirst = false," in _cb180_oe.group(1)
             # Code Bot (Shaun 2026-10-01): retired "CapSeconds = 8 * 3600," / "Share = 0.25," (superseded in codebot_v201.py:
             # OfflineConfig MaxSeconds 7200 / Rate 0.10)
             and "CapSeconds" not in _cb180_code(_cb180_oe.group(1)) and "Share = " not in _cb180_code(_cb180_oe.group(1)),
             "CODEBOT v180: OfflineEarnings live for everyone (cap + rate now in OfflineConfig)")
_cb180_MCF = _cb180_shipped(_cb180_C + "MissionConfig.luau")  # Code Bot v182: as v180 shipped it (Core live since v182)
_cb180_core = _cb180_MCF.split("\tCore = {")[1].split("\n\t},\n\n")[0] if "\tCore = {" in _cb180_MCF else ""
_cb180_check("Enabled = true," in _cb180_core and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _cb180_core,
             "CODEBOT v180: MissionConfig.Core.OwnerFirst left true (NEW-OWNER-FIRST, not flipped)")
_cb180_check('Robux = { Enabled = true, OwnerFirst = false, ProductKey = "MissionReroll" },' in _cb180_core
             and "FreePerDay = 1," in _cb180_core,
             "CODEBOT v180: Core.Reroll FreePerDay 1 + Robux reroll Enabled (only gate left = Core.OwnerFirst)")
_cb180_RCF = _cb180_shipped(_cb180_C + "RetentionConfig.luau")  # Code Bot v182: as v180 shipped it (ReturnSequence live since v182)
_cb180_rs = _cb180_re.search(r"\bReturnSequence = \{(.*?)\n\t\},", _cb180_RCF, _cb180_re.S)
_cb180_check(bool(_cb180_rs) and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _cb180_rs.group(1),
             "CODEBOT v180: RetentionConfig.ReturnSequence.OwnerFirst left true (not flipped)")

# ── 2x cap: server-authoritative Game Pass ownership ──
_cb180_MS = _cb180_code(_cb180_read(_cb180_S + "Services/MonetizationService.luau"))
_cb180_RS = _cb180_code(_cb180_read(_cb180_S + "Services/RetentionService.luau"))
_cb180_own = _cb180_re.search(r"function MonetizationService\.OwnsGamePassNow\(player: Player, passKey: string\): boolean(.*?)\nend\n", _cb180_MS, _cb180_re.S)
_cb180_ob = _cb180_own.group(1) if _cb180_own else ""
_cb180_check("if ownsCached(player, passKey) then" in _cb180_ob and "MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)" in _cb180_ob
             and "if not (ok and owns == true) or not player.Parent then" in _cb180_ob and "setEntitlementAttr(player, passKey)" in _cb180_ob
             and _cb180_ob.find("UserOwnsGamePassAsync") < _cb180_ob.find("cache[passKey] = true"),
             "CODEBOT v180: OwnsGamePassNow = pass cache, else ONE UserOwnsGamePassAsync before caching + WE_Ent_<key>")
_cb180_check("function MonetizationService.OwnsCached(player: Player, key: string): boolean\n\treturn ownsCached(player, key)\nend" in _cb180_MS,
             "CODEBOT v180: OwnsCached exported (non-yielding)")
_cb180_check("MarketplaceService.PromptGamePassPurchaseFinished:Connect" in _cb180_MS and "confirmPassPurchase(player, passKey, passId, passName)" in _cb180_MS
             and "for passKey, def in pairs(MonetizationConfig.GamePasses) do" in _cb180_MS,
             "CODEBOT v180: the generic pass path (join UserOwnsGamePassAsync + PromptGamePassPurchaseFinished confirm) covers GamePasses.OfflineCap2x")
_cb180_cap = _cb180_re.search(r"local function capSecondsFor\(player: Player, profile: any, fresh: boolean\?\): number(.*?)\nend\n", _cb180_RS, _cb180_re.S)
_cb180_check(bool(_cb180_cap) and "RetentionConfig.Live(b, player.UserId) and ownsCapBoost(player, profile, b.ProductKey or CAP_BOOST_PASS, fresh)" in _cb180_cap.group(1),
             "CODEBOT v180: capSecondsFor doubles only while CapBoost is live AND the pass is owned (server check)")
_cb180_ocb = _cb180_re.search(r"local function ownsCapBoost\((.*?)\nend\n", _cb180_RS, _cb180_re.S)
_cb180_check(bool(_cb180_ocb) and "M.OwnsGamePassNow" in _cb180_ocb.group(1) and "M.OwnsCached" in _cb180_ocb.group(1)
             and "GetAttribute" not in _cb180_ocb.group(1),
             "CODEBOT v180: ownsCapBoost reads the server pass cache / Roblox, never the WE_Ent display attribute")
_cb180_check("local capSec = capSecondsFor(player, profile, true)" in _cb180_RS
             and "if not player.Parent or (DataService and DataService.GetProfile(player) ~= profile) then" in _cb180_RS,
             "CODEBOT v180: the offline payout waits for the ownership answer, then re-checks player + profile")

# ── reroll: granted once per receipt in ProcessReceipt (idempotent), never by the client ──
_cb180_pr = _cb180_re.search(r"local function processReceipt\(receiptInfo: any, receiptId: string\): Enum\.ProductPurchaseDecision(.*?)\nend\n", _cb180_MS, _cb180_re.S)
_cb180_prb = _cb180_pr.group(1) if _cb180_pr else ""
_cb180_check(_cb180_prb.find("if hasProcessed(profile, receiptId) then") >= 0
             and _cb180_prb.find("if hasProcessed(profile, receiptId) then") < _cb180_prb.find("GrantsMissionReroll == true")
             < _cb180_prb.find("markProcessed(profile, receiptId)"),
             "CODEBOT v180: ProcessReceipt: hasProcessed -> GrantsMissionReroll token -> markProcessed (once per receipt)")
_cb180_check("return Enum.ProductPurchaseDecision.NotProcessedYet" in _cb180_prb.split("GrantsMissionReroll == true", 1)[-1].split("markProcessed", 1)[0],
             "CODEBOT v180: a failed reroll grant is NotProcessedYet (Roblox re-delivers, nothing acked)")
_cb180_MSS = _cb180_code(_cb180_read(_cb180_S + "Services/MissionService.luau"))
_cb180_gt = _cb180_re.search(r"function MissionService\.GrantRerollToken\(player: Player\): boolean(.*?)\nend\n", _cb180_MSS, _cb180_re.S)
_cb180_check(bool(_cb180_gt) and "math.floor(tonumber(profile.MissionRerollTokens) or 0)) + 1" in _cb180_gt.group(1),
             "CODEBOT v180: GrantRerollToken adds exactly one token")
_cb180_grants = [l for l in _cb180_MSS.splitlines() if "GrantRerollToken" in l]
_cb180_check(len(_cb180_grants) == 1, "CODEBOT v180: GrantRerollToken is called from nowhere else in MissionService (receipt only)")
_cb180_check("e.CanBuyReroll = if not claimed and not complete and not e.CanReroll and MissionService.RerollBuyLive(player) then true else nil" in _cb180_MSS
             and "function MissionService.RerollBuyLive(player: Player): boolean" in _cb180_MSS,
             "CODEBOT v180: the server decides when the 19 R$ reroll button shows (free reroll used, no token, product live)")
_cb180_MCC = _cb180_code(_cb180_read(_cb180_CL + "Controllers/MissionController.luau"))
_cb180_check('SC.PromptDevProduct("MissionReroll", "missions")' in _cb180_MCC and "elseif goEntry.CanBuyReroll == true then" in _cb180_MCC
             and "GrantRerollToken" not in _cb180_MCC and "MissionRerollTokens" not in _cb180_MCC,
             "CODEBOT v180: the Missions row only prompts the product (ShopController); the client never grants")
_cb180_check("missions = true," in _cb180_MON, "CODEBOT v180: PurchaseSources.missions (analytics source)")

# ── guards ──
_cb180_check("PreferMesh = true" not in _cb180_read(_cb180_C + "VisualAssetConfig.luau"), "CODEBOT v180: PreferMesh stays OFF")
_cb180_check("PreferMeshWhenAssetIdSet = false" in _cb180_read(_cb180_C + "StructureVisualConfig.luau"), "CODEBOT v180: PreferMeshWhenAssetIdSet false")
_cb180_check('"StreamingEnabled": true' not in _cb180_read("default.project.json"), "CODEBOT v180: StreamingEnabled stays OFF")
try:
    _r = _cb180_sp.run(["git", "diff", "--name-only", _cb180_PREV, "--", "src"], capture_output=True, text=True, cwd=_cb180_ROOT)
    _t = [ln for ln in (_r.stdout or "").splitlines() if "WE_Building" in ln]
    _cb180_check(_r.returncode == 0 and not _t, "CODEBOT v180: no WE_Building* diffs vs " + _cb180_PREV + ((" " + str(_t)) if _t else ""))
except Exception as _e:
    _cb180_check(False, "CODEBOT v180: git diff errored: " + str(_e))
