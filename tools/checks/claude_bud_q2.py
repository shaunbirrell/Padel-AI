# claude-bud queue 2 (2026-09-29, jobs 6-11). Runs inside tools/BuyPathStatic.py (its globals). Helpers: _q2_.
_q2_mc = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
_q2_vs = "src/ServerScriptService/Server/Services/VehicleService.luau"
_q2_sc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"

# ── JOB 6 Extra Garage Slot ──
must_contain(_q2_mc, "\t\tExtraGarageSlot = {\n\t\t\tId = 0,\n\t\t\tDisplayName = \"Extra Garage Slot\",\n\t\t\tRobuxPrice = 199,\n\t\t\tDescription =", "CLAUDE-BUD J6: Extra Garage Slot pass, Id 0 until wired")
must_contain(_q2_mc, "ExtraGarageSlot = true", "CLAUDE-BUD J6: owner-only first (RolloutKeys)")
must_contain(_q2_vs, "if not MC.SkuLiveFor(player.UserId, \"ExtraGarageSlot\") then", "CLAUDE-BUD J6: the slot is rollout-gated")
must_contain(_q2_vs, "and MonetizationService.PlayerOwnsGamePass(player, \"ExtraGarageSlot\") == true", "CLAUDE-BUD J6: the slot needs the real pass (server)")
must_contain(_q2_vs, "if cur and cur.Parent and cur:GetAttribute(\"VehicleId\") ~= vehicleId and VehicleService._HasExtraSlot(player) then", "CLAUDE-BUD J6: a different vehicle parks the current one")
must_contain(_q2_vs, "\t\tVehicleService._DestroyParked(player.UserId)\n\t\tVehicleService._Parked[player.UserId] = cur", "CLAUDE-BUD J6: at most one parked vehicle (+1 slot)")
must_contain(_q2_vs, "VehicleService._DestroyParked(player.UserId) -- claude-bud JOB 6", "CLAUDE-BUD J6: the parked vehicle goes when he leaves")
must_contain(_q2_vs, "if prec == nil or not pm or pm:GetAttribute(\"VehicleId\") ~= msg.V or seatedDriver(prec) ~= player then", "CLAUDE-BUD J6: only the seated driver can take the parked vehicle")
must_contain(_q2_sc, 'end, "SOON", "Pass_" .. key, true)', "CLAUDE-BUD J6: gold ROBUX row (SOON while the Id is 0, no prompt)")
must_contain(_q2_sc, 'end, btnLabel, "Pass_" .. key, robuxFeature)', "CLAUDE-BUD J6: gold ROBUX row once live")
must_contain("LATEST-HANDOFF.md", "| Extra Garage Slot | Game pass | 199 | GamePasses.ExtraGarageSlot |", "CLAUDE-BUD J6: on the Creator Hub list")

# ── JOB 7 first five minutes (the tutorial exists: claim, pad, collect, recruit, barracks, outpost, 4x4, Skip, once) ──
_q2_tc = "src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau"
_q2_ts = "src/ServerScriptService/Server/Services/TutorialService.luau"
_q2_fc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/FeatureController.luau"
for _id in ("ClaimBase", "CommandCenter", "Income", "RecruitSoldiers"):
    must_contain(_q2_tc, 'Id = "' + _id + '",', f"CLAUDE-BUD J7: tutorial step {_id}")
must_contain(_q2_tc, "TutorialConfig.FirstMinutes = {\n\tRollout = \"owner\",", "CLAUDE-BUD J7: first-minutes additions owner-only first")
must_contain(_q2_ts, "local skipRemote = RemoteSetup.Get(Constants.RemoteNames.RequestSkipTutorial) :: RemoteEvent", "CLAUDE-BUD J7: skippable")
must_contain(_q2_ts, "if profile.WelcomeShown ~= true and profile.TutorialComplete ~= true then", "CLAUDE-BUD J7: welcome once per profile")
must_contain(_q2_ts, "if profile == nil or (profile :: any).FirstAttackDone == true then", "CLAUDE-BUD J7: first ATTACK hint once per profile (saved)")
must_contain("src/ServerScriptService/Server/Services/SquadOrdersService.luau", "pcall(tut.OnArmyOrder, player, order)", "CLAUDE-BUD J7: the server sees the first ATTACK order")
must_contain(_q2_fc, 'local btn = pg and pg:FindFirstChild("Order_Attack", true)', "CLAUDE-BUD J7: the ATTACK button is outlined")
_q2_t = read(_q2_tc) or ""
(ok if not re.search(r"(?i)\b(click|press [A-Z]\b|key [A-Z]\b)", _q2_t[_q2_t.find("TutorialConfig.FirstMinutes = {"):]) else bad)("CLAUDE-BUD J7: first-minutes copy never says click or names a key (phones)")

# ── JOB 8 mobile performance: automatic low tier + streaming readiness audit (flag stays OFF) ──
import os as _q2_os
_q2_qc = "src/ReplicatedStorage/Shared/Configs/QualityConfig.luau"
_q2_qg = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau"
must_contain(_q2_qc, "local QualityConfig = {\n\tRollout = \"owner\",", "CLAUDE-BUD J8: low tier owner-only first")
must_contain(_q2_qg, "local small = math.min(vp.X, vp.Y) <= Q.SmallScreenShortSide", "CLAUDE-BUD J8: small screens go low")
must_contain(_q2_qg, "if small or lowFor >= Q.LowFpsSeconds then", "CLAUDE-BUD J8: sustained low FPS goes low")
must_contain(_q2_qg, "local hide = low and ((e.Tier >= 2 and d > Q.HideTier2BeyondStuds) or d > Q.HideAnyBeyondStuds)", "CLAUDE-BUD J8: far decoration hidden while low")
must_contain(_q2_qg, "\tfor _, d in ipairs(folder:GetDescendants()) do -- once per folder", "CLAUDE-BUD J8: the cluster list is built once per folder (no per-frame scans)")
_q2_g = read(_q2_qg) or ""
_q2_hb = _q2_g[_q2_g.find("RunService.Heartbeat:Connect"):_q2_g.find("end)", _q2_g.find("RunService.Heartbeat:Connect"))]
(ok if _q2_hb and "GetDescendants" not in _q2_hb and "{" not in _q2_hb else bad)("CLAUDE-BUD J8: the per-frame work is one counter (no scans, no allocation)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/ProductionFx.luau", 'LocalPlayer:GetAttribute("WE_LowQuality") == true then', "CLAUDE-BUD J8: cheaper effects while low")
must_not_contain("default.project.json", '"StreamingEnabled": true', "CLAUDE-BUD J8: StreamingEnabled stays OFF")
# streaming audit (regression guard on client code): no dot-indexed map paths, no chained FindFirstChild method calls
_q2_bad = []
for _root in ("src/StarterPlayer", "src/ReplicatedStorage"):
    for _dp, _dn, _fn in _q2_os.walk(_root):
        for _f in _fn:
            if _f.endswith(".luau"):
                _p = _q2_os.path.join(_dp, _f).replace("\\", "/")
                _src = re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), read(_p) or "", flags=re.S)
                for _i, _l in enumerate(_src.split("\n"), 1):
                    _code = _l.split("--")[0]
                    if re.search(r"\b[wW]orkspace\.(?!CurrentCamera|Terrain|Gravity|FallenPartsDestroyHeight|StreamingEnabled|DistributedGameTime)[A-Z]\w*\.[A-Z]", _code):
                        _q2_bad.append(f"{_p}:{_i} map path")
                    if re.search(r":FindFirstChild\([^)]*\)[:.][A-Za-z]", _code):
                        _q2_bad.append(f"{_p}:{_i} chained FindFirstChild")
(ok if not _q2_bad else bad)(f"CLAUDE-BUD J8: streaming audit clean on client code ({_q2_bad[:5]})")

# ── JOB 9 old WIP: finished or removed cleanly ──
_q2_vac = "src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"
_q2_v = read(_q2_vac) or ""
must_not_contain(_q2_vac, "ModelAssetId = 16692908395", "CLAUDE-BUD J9: the real-world PT-boat body is gone")
must_not_contain(_q2_vac, "ModelAssetId = 15838664806", "CLAUDE-BUD J9: the HELD gunboat body is not wired")
for _k in ("PatrolBoat", "FastAttackCraft", "RiverBoat", "CoastCutter", "TorpedoBoat", "Gunboat", "MissileBoat", "MineLayer", "CoastalMonitor"):
    must_contain(_q2_vac, "\t\t" + _k + " = { ModelAssetId = 0, Note = \"claude-bud J9: Part kit.", f"CLAUDE-BUD J9: {_k} back on the Part kit")
(ok if "PendingAssetId = 8546141386" not in _q2_v and "PendingAssetId = 8455894899" not in _q2_v else bad)("CLAUDE-BUD J9: the failed truck picks (unit markings / 53 parts) left the rows")
must_contain(_q2_vac, '\t\tFuelTanker = { ModelAssetId = 0, Note = "claude-bud J9: FINISHED as the Part kit', "CLAUDE-BUD J9: fuel tanker finished as the Part kit")
_q2_ac = read("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau") or ""
(ok if 'March = "owner"' not in _q2_ac and 'March = "TO %s"' not in _q2_ac else bad)("CLAUDE-BUD J9: the never-built lane C (March) is gone")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "\t\tTidy = {\n\t\t\tRollout = \"owner\",", "CLAUDE-BUD J9: ATTACK marching = the finished Tidy rows / ring")
import os as _q2_os2
(ok if not any(_q2_os2.path.exists(_p) for _p in ("handoff/wip/09-vkit-framework_on_e506c9c.patch", "handoff/wip/12-vkit-naval_on_e506c9c.patch", "handoff/wip/04-army-laneA_on_oldFIX+A0.patch")) else bad)("CLAUDE-BUD J9: unfinished WIP patches retired (git history keeps them)")
must_not_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "no underwater physics yet", "CLAUDE-BUD J9: no stub wording on the surface-only sub")

# ── JOB 10 balance and progression (BalanceConfig; tools/progression_sim.py) ──
import importlib.util as _q2_il
_q2_bc = "src/ReplicatedStorage/Shared/Configs/BalanceConfig.luau"
must_contain(_q2_bc, "local BalanceConfig = {\n\tRollout = \"owner\",", "CLAUDE-BUD J10: the new curve is owner-only first")
_q2_spec = _q2_il.spec_from_file_location("q2_progression_sim", "tools/progression_sim.py")
_q2_ps = _q2_il.module_from_spec(_q2_spec)
_q2_spec.loader.exec_module(_q2_ps)
_q2_b = _q2_ps.balance()
_q2_r = _q2_ps.simulate(20, 90, "balance")
_q2_lo, _q2_hi = _q2_b.get("FirstRebirthMinutes") or (25, 40)
(ok if _q2_r["RebirthMin"] is not None and _q2_lo <= _q2_r["RebirthMin"] <= _q2_hi else bad)(
    f"CLAUDE-BUD J10: sim first rebirth {_q2_r['RebirthMin']} min is inside {_q2_lo}-{_q2_hi} min")
(ok if _q2_r["WorstPaybackMin"] <= max(_q2_b.get("Payback") or [0]) + 0.05 and not _q2_r["DeadPurchases"] else bad)(
    f"CLAUDE-BUD J10: no dead pads (worst payback {_q2_r['WorstPaybackMin']} min <= {max(_q2_b.get('Payback') or [0])})")
_q2_old = _q2_ps.simulate(20, 90, "old")
(ok if _q2_old["RebirthMin"] is None else bad)(f"CLAUDE-BUD J10: the old curve really had no first rebirth in 90 min (sim {_q2_old['RebirthMin']})")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "\tif player and BalanceConfig.LiveFor(player.UserId) and typeof(profile.BaseUpgrades) == \"table\" then", "CLAUDE-BUD J10: the server pays the curve only where it is live")
must_contain("src/ServerScriptService/Server/Services/XPService.luau", '\t\tand reasonKey ~= "income" -- claude-bud JOB 10', "CLAUDE-BUD J10: income XP never feeds the battle pass")
must_contain("src/ReplicatedStorage/Shared/Util/TycoonMath.luau", "if (BalanceConfig :: any).ClientCurve == true then", "CLAUDE-BUD J10: the owner's labels match what he is paid")
must_not_contain("src/ReplicatedStorage/Shared/Util/TycoonMath.luau", "game:GetService", "CLAUDE-BUD J10: TycoonMath stays pure")

# ── JOB 11 juice (purchase burst, rebirth celebration) + mobile HUD placement of the new touch UI ──
_q2_jc = "src/ReplicatedStorage/Shared/Configs/JuiceConfig.luau"
_q2_j = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/Juice.luau"
must_contain(_q2_jc, "local JuiceConfig = {\n\tRollout = \"owner\",", "CLAUDE-BUD J11: juice owner-only first")
must_contain(_q2_j, "if typeof(payload) == \"table\" and payload.Ok == true then\n\t\t\tburst(J)", "CLAUDE-BUD J11: a burst on every successful purchase")
must_contain(_q2_j, "if not lowFx() then\n\t\tlocal att = Instance.new(\"Attachment\")", "CLAUDE-BUD J11: no particles on low FX / the low tier")
must_contain(_q2_j, "pcall((HudLayout :: any).RegisterTopStack, \"Rebirth\", banner, 15)", "CLAUDE-BUD J11: the rebirth banner sits in the HUD top stack (never over the controls)")
must_contain("src/ServerScriptService/Server/Services/PrestigeService.luau", "(ev :: RemoteEvent):FireClient(player, \"Rebirth\", {", "CLAUDE-BUD J11: the server cues the celebration after a saved rebirth")
must_contain(_q2_fc, "pcall((HudLayout :: any).RegisterTopStack, \"Airstrike\", btn, 35)", "CLAUDE-BUD J11: the AIRSTRIKE button is in the managed top stack (no overlap on phones)")
must_contain(_q2_fc, "pcall((HudLayout :: any).AssertTouchTarget, btn, \"Airstrike\")", "CLAUDE-BUD J11: the AIRSTRIKE button is checked as a touch target")
_q2_jj = read(_q2_j) or ""
(ok if "Enum.Material.Neon" not in _q2_jj and "PointLight" not in _q2_jj else bad)("CLAUDE-BUD J11: no Neon, no lights in the effects")
_q2_sizes = [int(x) for x in re.findall(r"TextSize = (\d+)", _q2_jj + (read(_q2_fc) or ""))]
(ok if _q2_sizes and min(_q2_sizes) >= 20 else bad)(f"CLAUDE-BUD J11: new HUD text >= 20 code px (14 real at phone scale) {sorted(set(_q2_sizes))}")
_q2_h = [int(x) for x in re.findall(r"UDim2\.fromOffset\(\d+, (\d+)\)", read(_q2_fc) or "")]
(ok if _q2_h and min(_q2_h) >= 64 else bad)(f"CLAUDE-BUD J11: new touch buttons >= 64 code px tall (44 real) {_q2_h}")
