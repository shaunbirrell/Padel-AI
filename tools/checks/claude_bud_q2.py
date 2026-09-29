# claude-bud queue 2 (2026-09-29, jobs 6-11). Runs inside tools/BuyPathStatic.py (its globals). Helpers: _q2_.
_q2_mc = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
_q2_vs = "src/ServerScriptService/Server/Services/VehicleService.luau"
_q2_sc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"

# ── JOB 6 Extra Garage Slot ──
must_contain(_q2_mc, "\t\tExtraGarageSlot = {\n\t\t\tId = 1999359549,\n\t\t\tDisplayName = \"Extra Garage Slot\",\n\t\t\tRobuxPrice = 199,\n\t\t\tDescription =", "CLAUDE-BUD J6: Extra Garage Slot pass, v99: Creator Hub Id wired")
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
