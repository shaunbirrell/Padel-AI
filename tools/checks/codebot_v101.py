# Code Bot v101 (2026-09-29, owner: "enable everything for ALL players now"): every owner-only rollout flipped to "all"
# (each gate's own Rollout; MonetizationConfig.LaunchAll from claude-bud JOB 12 stays false and is redundant), the owner's
# UserId-only test shortcuts kept (they never reach another account), Id 0 items hidden, and the switches with a clear
# reason to stay off pinned off. Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb101_.
import importlib.util as _cb101_il
import re as _cb101_re
import shutil as _cb101_sh
import subprocess as _cb101_sp
import sys as _cb101_sys

_cb101_C = "src/ReplicatedStorage/Shared/Configs/"
_cb101_mc = _cb101_C + "MonetizationConfig.luau"
_cb101_M = read(_cb101_mc) or ""

# ── build ──
# v102 (Code Bot): retired, superseded in tools/checks/codebot_v102.py: #for _f in ("src/ServerScriptService/Server/Services/DataService.luau", "src/ServerScriptService/Server/Services/BaseService.luau",
# v102 (Code Bot): retired, superseded in tools/checks/codebot_v102.py: #           "src/ServerScriptService/Server/EarlyRemotes.server.luau"):
# v102 (Code Bot): retired, superseded in tools/checks/codebot_v102.py: #    must_contain(_f, 'SetAttribute("WE_Build", 101)', "CODEBOT v101: WE_Build=101 " + _f.rsplit("/", 1)[-1])
# v102 (Code Bot): retired, superseded in tools/checks/codebot_v102.py: #must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WE_Build=101", "CODEBOT v101: DataService profile-loaded log says WE_Build=101")

# ── 1. every listed gate ships "all" (no owner-only gate left on a live item) ──
for _f, _needle, _label in (
    ("MonetizationConfig.luau", '\tRollout = "all", -- v101', "Sales: MonetizationConfig.Rollout (13 RolloutKeys SKUs + premium weapons)"),
    ("MonetizationConfig.luau", '\tRetention = {\n\t\tRollout = "all",', "Retention (FREE rows, group reward, Premium perk)"),
    ("MonetizationConfig.luau", '\tPlacement = {\n\t\tRollout = "all",', "Placement (purchase prompts at moments)"),
    ("MonetizationConfig.luau", '\tVIPPerks = {\n\t\tRollout = "all",', "VIP perks (tag, lounge)"),
    ("SupplyDropConfig.luau", '\tAirdrop = {\n\t\tRollout = "all",', "JOB 4 airdrop"),
    ("DailyRewardConfig.luau", '\tAutoClaim = {\n\t\tRollout = "all",', "JOB 4 daily reward auto-claim"),
    ("PlazaBountyConfig.luau", 'local PlazaBountyConfig = {\n\tRollout = "all",', "JOB 4 plaza bounty"),
    ("ArmyUpgradeConfig.luau", 'local ArmyUpgradeConfig = {\n\tRollout = "all",', "JOB 4 army upgrades"),
    ("CombatConfig.luau", '\tGuardsFightBack = {\n\t\tRollout = "all",', "guards fight back"),
    ("CombatConfig.luau", '\tNpcUnstick = {\n\t\tRollout = "all",', "NpcUnstick"),
    ("OpsConfig.luau", 'PickupLosRollout = "all",', "bag-pickup LOS"),
    ("TutorialConfig.luau", 'TutorialConfig.FirstMinutes = {\n\tRollout = "all",', "tutorial first minutes"),
    ("QualityConfig.luau", 'local QualityConfig = {\n\tRollout = "all",', "QualityGovernor low tier"),
    ("JuiceConfig.luau", 'local JuiceConfig = {\n\tRollout = "all",', "juice"),
    ("BalanceConfig.luau", 'local BalanceConfig = {\n\tRollout = "all",', "balance curve + income XP"),
    ("ArmyConfig.luau", '\t\tEscort = "all",', "army Rollout.Escort"),
    ("ArmyConfig.luau", '\t\tArmy = "all",', "army Rollout.Army"),
    ("ArmyConfig.luau", '\t\tFix = "all",', "army Rollout.Fix"),
    ("ArmyConfig.luau", 'ThreatStandingFor = "all",', "army Follow.ThreatStandingFor"),
    ("ArmyConfig.luau", '\tFollow2 = {\n\t\tEnabled = true,\n\t\tRollout = "all",', "army Follow2 (v91 + v99 follow rewrite)"),
    ("ArmyConfig.luau", '\t\tTidy = {\n\t\t\tRollout = "all",', "army Follow2.Tidy"),
    ("VehicleConfig.luau", 'AmphibiousRollout = { BridgeLayer = "all" }', "Bridge Layer wading"),
):
    must_contain(_cb101_C + _f, _needle, "CODEBOT v101: live for all: " + _label)
must_contain(_cb101_C + "WorldFillConfig.luau", "local WorldFillConfig = {\n\tEnabled = true,", "CODEBOT v101: WorldFill on (world-wide, no per-player gate)")

# no config value is still "owner" except the store bodies (v104: EngagementConfig is back in the scan, all live)
import glob as _cb101_glob
_cb101_left = []
for _p in sorted(_cb101_glob.glob(_cb101_C + "*.luau")):
    # v104: EngagementConfig is "all" now (JOB 13 live for everyone), so it is scanned again like every other config
    for _ln in (read(_p) or "").split("\n"):
        _s = _ln.strip()
        if _s.startswith("--"):
            continue
        if _cb101_re.search(r'[^=~<>]=\s*"owner"', _s) and "BodyRollout" not in _s:
            _cb101_left.append(_p.rsplit("/", 1)[-1] + ": " + _s[:80])
(ok if not _cb101_left else bad)(f"CODEBOT v101: no owner-only rollout value left in Shared/Configs (except BodyRollout) {_cb101_left}")

# ── 2. every RolloutKeys SKU has a real Id (a live item never prompts Id 0) ──
_cb101_rk = _cb101_re.search(r"RolloutKeys = \{([^}]*)\}", _cb101_M)
_cb101_keys = _cb101_re.findall(r"(\w+) = true", _cb101_rk.group(1)) if _cb101_rk else []
(ok if len(_cb101_keys) == 13 else bad)(f"CODEBOT v101: 13 RolloutKeys SKUs ({len(_cb101_keys)})")
for _k in _cb101_keys:
    _m = _cb101_re.search(r"\n\t\t" + _k + r" = \{[^\n]*\n\t\t\tId = (\d+),", _cb101_M)
    (ok if _m and int(_m.group(1)) != 0 else bad)(f"CODEBOT v101: live SKU {_k} has a real Creator Hub Id ({_m.group(1) if _m else 'missing'})")
# the 6 Garage premium vehicles all point at a wired pass
_cb101_vc = read(_cb101_C + "VehicleConfig.luau") or ""
for _pk in sorted(set(_cb101_re.findall(r'\), "(PV_\w+)", "\w+"\),', _cb101_vc))):
    _m = _cb101_re.search(r"\n\t\t" + _pk + r" = \{[^\n]*\n\t\t\tId = (\d+),", _cb101_M)
    (ok if _m and int(_m.group(1)) != 0 else bad)(f"CODEBOT v101: Garage premium vehicle pass {_pk} has a real Id")

# ── 3. Id 0 items stay hidden ──
_cb101_sc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"
must_contain(_cb101_sc, "\t\tif robuxFeature and (tonumber(def.Id) or 0) == 0 then\n\t\t\tcontinue\n\t\tend", "CODEBOT v101: an Id 0 Robux feature (PV_Bastion / PV_MotorPool) has no Shop row for anyone")
must_not_contain(_cb101_sc, 'end, "SOON", "Pass_" .. key, true)', "CODEBOT v101: no SOON row for Id 0 passes")
must_contain(_cb101_sc, "\t\tif (tonumber(def.Id) or 0) == 0 then\n\t\t\treturn\n\t\tend", "CODEBOT v101: Id 0 dev products get no Shop row")
must_contain(_cb101_sc, "\t\tif (tonumber(def.Id) or 0) == 0 then\n\t\t\tcontinue\n\t\tend", "CODEBOT v101: Id 0 passes get no Shop row")
must_contain(_cb101_sc, "if (tonumber(def.Id) or 0) == 0 or not MonetizationConfig.SkuLiveFor(player.UserId, passKey) then", "CODEBOT v101: nothing prompts an Id 0 pass")
must_contain(_cb101_sc, "if (tonumber(def.Id) or 0) == 0 or not MonetizationConfig.SkuLiveFor(player.UserId, productKey) then", "CODEBOT v101: nothing prompts an Id 0 product")
must_contain(_cb101_mc, "and def.Id ~= 0", "CODEBOT v101: world pads skip Id 0 offers")

# ── 4. real purchase paths: prompt with the real Id, grant only on the server, persist, no double grant ──
must_contain(_cb101_sc, "MarketplaceService:PromptGamePassPurchase(player, def.Id)", "CODEBOT v101: Shop prompts the pass's real Id")
must_contain(_cb101_sc, "MarketplaceService:PromptProductPurchase(player, def.Id)", "CODEBOT v101: Shop prompts the product's real Id")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau", "MarketplaceService\"):PromptGamePassPurchase(Players.LocalPlayer, passId)", "CODEBOT v101: Garage prompts the vehicle pass's real Id")
_cb101_ms = "src/ServerScriptService/Server/Services/MonetizationService.luau"
must_contain(_cb101_ms, "MarketplaceService.ProcessReceipt = function(receiptInfo)", "CODEBOT v101: ProcessReceipt wired")
must_contain(_cb101_ms, "MarketplaceService.PromptGamePassPurchaseFinished:Connect(", "CODEBOT v101: PromptGamePassPurchaseFinished wired")
must_contain(_cb101_ms, "if wasPurchased == true and passKey ~= nil then\n\t\t\tconfirmPassPurchase(player, passKey, passId, passName)", "CODEBOT v101: a pass counts only after UserOwnsGamePassAsync confirms (confirmPassPurchase)")
must_contain(_cb101_ms, "return MarketplaceService:UserOwnsGamePassAsync(userId, passId)", "CODEBOT v101: rejoin keeps passes (UserOwnsGamePassAsync on join)")
must_contain(_cb101_ms, "if hasProcessed(profile, receiptId) then", "CODEBOT v101: receipts idempotent (no double grant)")
must_contain(_cb101_ms, "if receiptsInFlight[receiptId] then", "CODEBOT v101: one receipt run per PurchaseId")
must_contain(_cb101_ms, "if not DataService.SaveProfile(player, false) then", "CODEBOT v101: grant saved before PurchaseGranted (persists)")
must_contain(_cb101_ms, "-- Do NOT grant here. Client prompts Marketplace; ProcessReceipt grants.", "CODEBOT v101: the prompt remote never grants")
must_not_contain(_cb101_ms, "IsPlaytestOwner", "CODEBOT v101: MonetizationService has no owner grant")
must_not_contain(_cb101_ms, "470626172", "CODEBOT v101: MonetizationService has no owner UserId")

# ── 5. owner test shortcuts: UserId 470626172 only, never another account ──
_cb101_ac = _cb101_C + "AdminConfig.luau"
must_contain(_cb101_ac, "local PLAYTEST_OWNER_USER_ID = 470626172\n", "CODEBOT v101: the playtest owner is UserId 470626172")
must_contain(_cb101_ac, "\t\treturn uid ~= nil and uid == PLAYTEST_OWNER_USER_ID\n", "CODEBOT v101: IsPlaytestOwner is an exact UserId match")
must_contain(_cb101_ac, "\tUserIds = {\n\t\t470626172,\n\t} :: { number },", "CODEBOT v101: admin list is the owner only")
_cb101_ds = "src/ServerScriptService/Server/Services/DataService.luau"
must_contain(_cb101_ds, "local ADMIN_PLAYTEST_USER_ID = 470626172\nlocal function applyAdminPlaytestCash(userId: number, profile: PlayerProfile): boolean\n\tif userId ~= ADMIN_PLAYTEST_USER_ID then\n\t\treturn false", "CODEBOT v101: owner cash floor only for the owner")
must_contain(_cb101_ds, "local function applyAdminPlaytestUnlocks(userId: number, profile: PlayerProfile): boolean\n\tif not AdminConfig.IsPlaytestOwner(userId) then\n\t\treturn false", "CODEBOT v101: owner vehicle / level unlock only for the owner")
_cb101_vs = "src/ServerScriptService/Server/Services/VehicleService.luau"
must_contain(_cb101_vs, "function VehicleService._IsPlaytestOwner(player: Player): boolean\n\treturn VehicleService._AdminConfig.IsPlaytestOwner(player.UserId) == true", "CODEBOT v101: VehicleService owner test = IsPlaytestOwner")
must_contain(_cb101_vs, "local isOwner = VehicleService._IsPlaytestOwner(player) and MonetizationConfig.LaunchAll ~= true", "CODEBOT v101: premium vehicle spawn without a pass = owner only")
must_contain(_cb101_vs, "if not owns and not isOwner then\n\t\t\treturn false, \"NeedsPass\"", "CODEBOT v101: a non-owner needs the pass (UserOwnsGamePassAsync cache) to spawn a premium vehicle")
must_contain(_cb101_vs, "MC.GarageSlot.OwnerTest == true and MC.LaunchAll ~= true and VehicleService._IsPlaytestOwner(player)", "CODEBOT v101: Extra Garage Slot test = owner only")
must_contain(_cb101_vs, "and MonetizationService.PlayerOwnsGamePass(player, \"ExtraGarageSlot\") == true", "CODEBOT v101: everyone else needs the Extra Garage Slot pass")
must_contain("src/ServerScriptService/Server/Services/PremiumWeaponService.luau", "local ownerTest = AdminConfig.IsPlaytestOwner(player.UserId) and (MonetizationConfig :: any).LaunchAll ~= true", "CODEBOT v101: premium weapons shortcut = owner only")
must_contain("src/ServerScriptService/Server/Services/PremiumWeaponService.luau", "if model == nil or model:GetAttribute(\"OwnerUserId\") ~= player.UserId then", "CODEBOT v101: premium weapons only in his own (paid) vehicle")
# no other hard-coded owner id in the server outside the known owner-only sites
_cb101_ids = []
import pathlib as _cb101_pl
for _p in sorted(_cb101_pl.Path("src/ServerScriptService").rglob("*.luau")):
    _t = _p.read_text(encoding="utf-8")
    if "470626172" in _t:
        _cb101_ids.append(_p.name)
(ok if set(_cb101_ids) <= {"AdminService.luau", "EarlyRemotes.server.luau", "BaseService.luau", "DataService.luau"} else bad)(
    f"CODEBOT v101: the owner UserId appears only in the known owner-only sites {_cb101_ids}")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "-- v63/v64: shaunie6 playtest floor on every buy attempt\n\tif player.UserId == 470626172 then", "CODEBOT v101: BaseService cash floor owner only")

# ── 6. left OFF on purpose ──
must_contain(_cb101_mc, "\tLaunchAll = false,\n", "CODEBOT v101: LaunchAll stays false (redundant: every gate is \"all\"; keeps the owner's UserId-only test shortcuts)")
must_contain(_cb101_C + "VisualAssetConfig.luau", '\tBodyRollout = "owner",\n', "CODEBOT v101: store vehicle bodies stay owner-only (11 hulls have no WE_CHECK2 / licence record)")
must_contain(_cb101_C + "AircraftWeaponConfig.luau", "\tWeaponsLive = false,", "CODEBOT v101: AircraftWeaponConfig.WeaponsLive stays off")
must_contain(_cb101_C + "RebirthConfig.luau", "\tZonesLive = false,", "CODEBOT v101: RebirthConfig.ZonesLive stays off")
must_contain(_cb101_C + "RebirthConfig.luau", "\tWeaponsLive = false,", "CODEBOT v101: RebirthConfig.WeaponsLive stays off")
must_contain(_cb101_C + "OpsConfig.luau", "\tEnabled = false, -- master switch", "CODEBOT v101: OpsConfig.Enabled stays off")
must_contain(_cb101_C + "XPBalanceConfig.luau", "\tBackfill = { Enabled = false,", "CODEBOT v101: XP backfill stays off")
must_not_contain("default.project.json", '"StreamingEnabled": true', "CODEBOT v101: StreamingEnabled stays OFF")
must_contain(_cb101_C + "StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false,", "CODEBOT v101: PreferMesh stays OFF")

# ── 7. balance curve: computed from saved levels, never writes a save, never pays less than the old formula ──
_cb101_bc = read(_cb101_C + "BalanceConfig.luau") or ""
(ok if not _cb101_re.search(r"profile\.\w+\s*=", _cb101_bc) and "SetAsync" not in _cb101_bc and "UpdateAsync" not in _cb101_bc else bad)(
    "CODEBOT v101: BalanceConfig never writes a profile (no save reset)")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "local lvl = math.clamp(math.floor(tonumber(lv) or 0), 0, TycoonMath.MaxLevel(id))\n\t\t\t\tlocal s = BalanceConfig.StructureIncomePerTick(id, lvl)",
             "CODEBOT v101: the curve reads the saved levels as they are")
_cb101_pb = [float(x) for x in _cb101_re.search(r"PaybackMinutes = \{([^}]*)\}", _cb101_bc).group(1).split(",")]
_cb101_ec = read(_cb101_C + "EconomyConfig.luau") or ""
_cb101_tick = float(_cb101_re.search(r"TickSeconds = ([\d.]+)", _cb101_ec).group(1))
_cb101_rb = _cb101_ec[_cb101_ec.index("PerLevelRates = {"):_cb101_ec.index("}", _cb101_ec.index("PerLevelRates = {"))]
_cb101_rates = {k: float(v) for k, v in _cb101_re.findall(r"(\w+) = ([\d.]+)", _cb101_rb)}
_cb101_rows = []  # (id, costs, old income per level)
for _m in _cb101_re.finditer(r"\n\t\t(\w+) = \{\n\t\t\tId = \"\w+\",(.*?)\n\t\t\},", read(_cb101_C + "BaseConfig.luau") or "", _cb101_re.S):
    _cm = _cb101_re.search(r"Costs = costs\(([^)]*)\)", _m.group(2))
    if _cm:
        _c = [float(x) for x in _cm.group(1).split(",")]
        _cb101_rows.append((_m.group(1), _c, [_cb101_rates.get(_m.group(1), 0) * (i + 1) for i in range(len(_c))]))
_cb101_bz = read(_cb101_C + "BusinessConfig.luau") or ""
for _m in _cb101_re.finditer(r"\n\t\t(\w+) = \{\n\t\t\tId = \"\w+\",.*?\n\t\t\tCosts = \{([^}]*)\},.*?\n\t\t\tIncomePerTick = \{([^}]*)\},", _cb101_bz, _cb101_re.S):
    _cb101_rows.append((_m.group(1), [float(x) for x in _m.group(2).split(",")], [float(x) for x in _m.group(3).split(",")]))
_cb101_worse = []
for _id, _c, _old in _cb101_rows:
    for _L in range(1, len(_c) + 1):
        _new = sum(_c[i] / (_cb101_pb[min(i, len(_cb101_pb) - 1)] * 60 / _cb101_tick) for i in range(_L))
        if _new + 1 < _old[_L - 1]:
            _cb101_worse.append((_id, _L, _old[_L - 1], int(_new)))
(ok if len(_cb101_rows) >= 19 and not _cb101_worse else bad)(
    f"CODEBOT v101: balance curve pays every saved structure / business level at least the old income ({len(_cb101_rows)} rows; lower: {_cb101_worse})")

# ── 8. executed (Luau CLI): the real gates for a non-owner account ──
_cb101_luau = _cb101_sh.which("luau")
if _cb101_luau:
    _cb101_r = _cb101_sp.run([_cb101_sys.executable, "tools/v101_gate_test.py"], capture_output=True, text=True, timeout=120)
    _cb101_n = _cb101_r.stdout.count("PASS ")
    (ok if _cb101_r.returncode == 0 and _cb101_n >= 60 else bad)(f"CODEBOT v101: gates executed for a non-owner (Luau): {_cb101_n} PASS, exit {_cb101_r.returncode}")
    _cb101_r2 = _cb101_sp.run([_cb101_sys.executable, "tools/launch_gate_test.py"], capture_output=True, text=True, timeout=120)
    (ok if _cb101_r2.returncode == 0 else bad)(f"CODEBOT v101: claude-bud launch gate test still passes (exit {_cb101_r2.returncode})")
else:
    ok("CODEBOT v101: Luau gate execution skipped (no luau CLI)")
_cb101_spec = _cb101_il.spec_from_file_location("cb101_launch_audit", "tools/launch_audit.py")
_cb101_la = _cb101_il.module_from_spec(_cb101_spec)
_cb101_spec.loader.exec_module(_cb101_la)
_cb101_bad = [r[0] for r in _cb101_la.audit() if not r[6]]
(ok if not _cb101_bad else bad)(f"CODEBOT v101: every sold pass / product has a prompt and a server grant (bad {_cb101_bad})")
