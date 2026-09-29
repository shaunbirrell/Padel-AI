# Code Bot v102 (2026-09-29): redeem codes for launch, live for ALL players (no owner gate).
# Server-only CodesConfig (BUDSTUDIOS = $50,000 + 30 min 2x Cash), CodesService RedeemCode RemoteFunction (5 tries/min,
# server validation, once per player, saved in the profile), the ONE timed Cash boost (profile.CashBoost ->
# EconomyService.CashBoostMult), the "Codes" rail tile + CodesController panel, SocialConfig.DiscordText (no URL in-game).
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb102_.
import os as _cb102_os
import re as _cb102_re
import subprocess as _cb102_sp
import sys as _cb102_sys

_cb102_S = "src/ServerScriptService/Server/"
_cb102_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_cb102_SH = "src/ReplicatedStorage/Shared/"
_cb102_CFG = _cb102_S + "Configs/CodesConfig.luau"
_cb102_SVC = _cb102_S + "Services/CodesService.luau"
_cb102_CTL = _cb102_CL + "Controllers/CodesController.luau"

# ── build ──
# v103 (Code Bot): retired, superseded in tools/checks/codebot_v103.py: #for _f in (_cb102_S + "Services/DataService.luau", _cb102_S + "Services/BaseService.luau", _cb102_S + "EarlyRemotes.server.luau"):
# v103 (Code Bot): retired, superseded in tools/checks/codebot_v103.py: #    must_contain(_f, 'SetAttribute("WE_Build", 102)', "CODEBOT v102: WE_Build=102 " + _f.rsplit("/", 1)[-1])
# v103 (Code Bot): retired, superseded in tools/checks/codebot_v103.py: #must_contain(_cb102_S + "Services/DataService.luau", "WE_Build=102", "CODEBOT v102: DataService profile-loaded log says WE_Build=102")

# ── CodesConfig: server only, BUDSTUDIOS ──
_cb102_C = read(_cb102_CFG) or ""
(ok if _cb102_C else bad)("CODEBOT v102: CodesConfig lives in ServerScriptService (Server/Configs/CodesConfig.luau)")
(ok if read(_cb102_SH + "Configs/CodesConfig.luau") is None else bad)("CODEBOT v102: no CodesConfig in ReplicatedStorage (clients never see the code list)")
must_contain(_cb102_CFG, '\t\tBUDSTUDIOS = {\n\t\t\tActive = true,\n\t\t\tExpires = nil,\n\t\t\tDisplayName = "Bud Studios",\n\t\t\tRewards = { Cash = 50000, CashBoostMinutes = 30 },\n\t\t},',
             "CODEBOT v102: BUDSTUDIOS = $50,000 + 30 min 2x Cash, active, no expiry")
must_contain(_cb102_CFG, "\tTriesPerMinute = 5,", "CODEBOT v102: 5 redeem tries per minute")
must_contain(_cb102_CFG, "\tCashBoostMult = 2,", "CODEBOT v102: the code boost is 2x Cash")
must_contain(_cb102_CFG, "HOW TO ADD A CODE (owner):", "CODEBOT v102: CodesConfig explains how to add a code")
for _root in (_cb102_SH, _cb102_CL):
    for _dp, _dn, _fn in _cb102_os.walk(ROOT / _root):
        for _n in _fn:
            if _n.endswith(".luau"):
                _rel = _cb102_os.path.relpath(_cb102_os.path.join(_dp, _n), ROOT)
                _t = read(_rel) or ""
                if "BUDSTUDIOS" in _t or "WARFOUNDING" in _t or "BUILDCONQUER" in _t:
                    bad("CODEBOT v102: a client-visible file names a redeem code: " + _rel)
ok("CODEBOT v102: scanned Shared + Client for leaked code names")

# ── CodesService ──
_cb102_V = read(_cb102_SVC) or ""
must_contain(_cb102_SVC, "require(script.Parent.Parent.Configs.CodesConfig)", "CODEBOT v102: CodesService reads the server CodesConfig")
must_contain(_cb102_SVC, "RemoteSetup.Get(Constants.RemoteNames.RedeemCode) :: RemoteFunction", "CODEBOT v102: RedeemCode is a RemoteFunction")
must_contain(_cb102_SVC, "fn.OnServerInvoke = function(player: Player, code: any): RedeemResult", "CODEBOT v102: RedeemCode OnServerInvoke")
must_contain(_cb102_SVC, 'RateLimitService.Allow(player, "redeem_code", perMin / 60, perMin)', "CODEBOT v102: rate limit (bucket of TriesPerMinute, refilled per minute)")
for _r in ("Success", "AlreadyUsed", "Invalid", "Expired", "RateLimited"):
    must_contain(_cb102_SVC, 'result("%s"' % _r, "CODEBOT v102: CodesService answers " + _r)
must_contain(_cb102_SVC, 'not string.match(code, "^[%w_]+$")', "CODEBOT v102: server validates the code characters")
_cb102_mark = _cb102_V.find("profile.RedeemedCodes[code] = os.time()")
_cb102_pay = _cb102_V.find('EconomyService.AddCash(player, cash, "code")')
(ok if 0 < _cb102_mark < _cb102_pay else bad)("CODEBOT v102: the code is marked redeemed BEFORE any reward is paid (no double grant)")
must_contain(_cb102_SVC, "pcall(DataService.SaveProfile, player, false)", "CODEBOT v102: profile saved right after a redeem")
must_contain(_cb102_SVC, "CodesService.GrantCashBoost(player, mins, CodesConfig.CashBoostMult)", "CODEBOT v102: CashBoostMinutes uses the one timed boost")
for _f in (_cb102_SVC, _cb102_CTL, _cb102_CFG):
    for _gate in ("IsPlaytestOwner", "Rollout", "LiveFor"):
        must_not_contain(_f, _gate, "CODEBOT v102: no owner gate (%s) in %s" % (_gate, _f.rsplit("/", 1)[-1]))
must_contain(_cb102_S + "Bootstrap.server.luau", 'safeInit("CodesService", CodesService, deps)', "CODEBOT v102: CodesService init")
must_contain(_cb102_S + "Modules/RemoteSetup.luau", "\tConstants.RemoteNames.RedeemCode, -- Code Bot v102", "CODEBOT v102: RemoteSetup creates the RedeemCode RemoteFunction")
must_contain(_cb102_SH + "Constants.luau", '\tRedeemCode = "RedeemCode",', "CODEBOT v102: RemoteNames.RedeemCode")

# ── profile + economy (reuse, no duplicate boost system) ──
must_contain(_cb102_S + "Modules/ProfileSchema.luau", "CashBoost = { Until = 0, Mult = 1 },", "CODEBOT v102: new profiles carry CashBoost")
must_contain(_cb102_S + "Modules/ProfileSchema.luau", "\tensureCodesFields(profile)\n", "CODEBOT v102: Migrate fills RedeemedCodes + CashBoost")
must_contain(_cb102_S + "Services/EconomyService.luau", "\t\tmult *= EconomyService.CashBoostMult(profile)\n", "CODEBOT v102: the timed boost multiplies non-exempt Cash (EconomyService)")
must_contain(_cb102_SH + "Configs/MonetizationConfig.luau", "\t\tcode = true,", "CODEBOT v102: code Cash is multiplier-exempt ($50,000 pays $50,000)")

# ── UI: Codes rail tile + panel ──
must_contain(_cb102_SH + "Configs/HudConfig.luau", '{ Id = "Codes", Name = "DockCodes", Label = "Codes", Icon = "Gift",', "CODEBOT v102: Codes rail tile")
must_contain(_cb102_CL + "Modules/HudIcons.luau", "SHAPES.Gift = {", "CODEBOT v102: Gift icon")
must_contain(_cb102_CL + "Controllers/UIController.luau", 'dockPress("Codes", CodesController.Toggle, "Codes")', "CODEBOT v102: the tile opens the Codes panel")
must_contain(_cb102_CL + "Controllers/UIController.luau", "panelOpeners.Codes = CodesController.Open", "CODEBOT v102: terminals can open Codes")
must_contain(_cb102_CL + "Controllers/UIController.luau", '{ Id = "Codes", Controller = CodesController }', "CODEBOT v102: Codes joins the one-panel-at-a-time registry")
must_contain(_cb102_CTL, "fn:InvokeServer(string.sub(code, 1, 64))", "CODEBOT v102: panel invokes RedeemCode")
must_contain(_cb102_CTL, "SocialConfig.DiscordText", "CODEBOT v102: panel shows the Discord line from SocialConfig")
must_contain(_cb102_CTL, "PanelShell.Attach({", "CODEBOT v102: Codes panel uses PanelShell (dim, safe area, one panel)")
must_contain(_cb102_CTL, "box.TextSize = PanelShell.Text(22)", "CODEBOT v102: phone-size text box")
must_not_contain(_cb102_CTL, "Remotes.GetEvent(", "CODEBOT v102: CodesController never blocks on Remotes.GetEvent")
must_contain(_cb102_SH + "Configs/SocialConfig.luau", '\tDiscordText = "Join Bud Studios Discord for free codes!",', "CODEBOT v102: SocialConfig.DiscordText")
must_contain(_cb102_SH + "Configs/SocialConfig.luau", '\tDiscordInvite = "",', "CODEBOT v102: Discord invite left as an empty placeholder")
for _f in (_cb102_CTL, _cb102_SH + "Configs/SocialConfig.luau"):
    _t = read(_f) or ""
    (bad if _cb102_re.search(r"https?://|discord\.gg|discord\.com/invite", _t) else ok)("CODEBOT v102: no URL in-game (%s)" % _f.rsplit("/", 1)[-1])
must_contain(_cb102_CL + "Controllers/SettingsController.luau", 'button("Redeem", "ENTER A CODE"', "CODEBOT v102: Settings REDEEM CODE opens the Codes panel")

# ── standing rules ──
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false,", "CODEBOT v102: PreferMesh stays OFF")
must_contain(_cb102_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v102: WE_Building untouched")

# ── executed: the real CodesService under the Luau CLI ──
try:
    _cb102_r = _cb102_sp.run([_cb102_sys.executable, str(ROOT / "tools/codes_gate_test.py")], capture_output=True, text=True, timeout=120)
    _cb102_out = _cb102_r.stdout + _cb102_r.stderr
    _cb102_last = [l for l in _cb102_out.splitlines() if l.startswith("codes_gate_test") or l.startswith("SKIP")]
    (ok if _cb102_r.returncode == 0 else bad)("CODEBOT v102: tools/codes_gate_test.py " + (_cb102_last[-1] if _cb102_last else _cb102_out[-300:]))
except Exception as _e:
    bad("CODEBOT v102: tools/codes_gate_test.py did not run: %s" % _e)
