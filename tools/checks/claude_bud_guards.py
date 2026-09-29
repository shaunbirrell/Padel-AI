# claude-bud (2026-09-29): guards fight back, bag pickup line of sight, unstick G1/G2 (Empire Bank; CP-9 items 1, 5, 7).
# All three are owner-only first. Runs inside tools/BuyPathStatic.py (its globals). Helpers start with _cbg_.
_cbg_cc = "src/ReplicatedStorage/Shared/Configs/CombatConfig.luau"
_cbg_npc = "src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau"
_cbg_cs = "src/ServerScriptService/Server/Services/CombatService/init.luau"
_cbg_sos = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_cbg_oc = "src/ReplicatedStorage/Shared/Configs/OpsConfig.luau"
_cbg_os = "src/ServerScriptService/Server/Services/OpsService/init.luau"

# flags: owner-only, fail closed
# v101 (Code Bot): retired, superseded in tools/checks/codebot_v101.py: #must_contain(_cbg_cc, "\tGuardsFightBack = {\n\t\tRollout = \"owner\",", "CLAUDE-BUD guards: GuardsFightBack ships owner-only")
# v101 (Code Bot): retired, superseded in tools/checks/codebot_v101.py: #must_contain(_cbg_cc, "\tNpcUnstick = {\n\t\tRollout = \"owner\",", "CLAUDE-BUD guards: NpcUnstick ships owner-only")
must_contain(_cbg_cc, "\t\treturn AdminConfig.IsPlaytestOwner(userId)\n\tend\n\treturn false\nend", "CLAUDE-BUD guards: CombatConfig.LiveFor fails closed")
# v101 (Code Bot): retired, superseded in tools/checks/codebot_v101.py: #must_contain(_cbg_oc, 'PickupLosRollout = "owner",', "CLAUDE-BUD guards: bag LOS ships owner-only")

# 1. fight back: the shooter is passed, remembered only while live for its owner, and fought with LOS + hit chance
must_contain(_cbg_sos, "\t\tsetShooter(unit.Model)\n\tend\n\tlocal ok, dealt = pcall(apply,", "CLAUDE-BUD guards: unitShoot names the shooting unit right before ApplyUnitHit")
must_contain(_cbg_sos, "\tif typeof(setShooter) == \"function\" then\n\t\tsetShooter(nil)\n\tend", "CLAUDE-BUD guards: the shooter is cleared after the hit (never leaks to another hit)")
must_contain(_cbg_cs, "\t\tif CombatConfig.LiveFor(CombatConfig.GuardsFightBack, attacker.UserId) then\n\t\t\trec.UnitFoe = pendingShooter", "CLAUDE-BUD guards: the NPC remembers the unit only while live for its owner")
_cbg_n = read(_cbg_npc) or ""
_cbg_i = _cbg_n.find("local function fightUnit(")
_cbg_f = _cbg_n[_cbg_i:_cbg_n.find("\nend\n", _cbg_i)] if _cbg_i >= 0 else ""
(ok if all(k in _cbg_f for k in ("CombatDamage.LineOfSight(eye, froot.Position", "CombatNPC.HitChance(dist, rec.Def.Range", "C.NpcReactionSeconds", "not CombatConfig.LiveFor(cfg, ownerId)", "rec.Def.AggroRange")) else bad)(
    "CLAUDE-BUD guards: fightUnit needs LOS, hit chance, reaction delay, range and the per-owner flag")
must_contain(_cbg_npc, "\t\t\t\telseif rec.UnitFoe ~= nil then\n\t\t\t\t\tfightUnit(rec, now)", "CLAUDE-BUD guards: a player in range always comes first; the unit only when none is")
must_not_contain(_cbg_npc, "GetDescendants", "CLAUDE-BUD guards: no tree scans in the NPC think")

# 2. bag line of sight on the server
must_contain(_cbg_os, "\tif not bagInSight(player, bag.Part) then\n\t\treturn -- claude-bud (CP-9 E4): no pickup through a wall", "CLAUDE-BUD guards: OnBagPrompt checks line of sight")
must_contain(_cbg_os, "return CombatDamage.LineOfSight(from, to, { char, part }, nil, true)", "CLAUDE-BUD guards: collidable parts block the bag ray")

# 3. unstick: chase goes through chaseTo; off = today's straight MoveTo
must_contain(_cbg_npc, "\tif not CombatConfig.LiveFor(U, userId) then\n\t\trec.Humanoid:MoveTo(goal)\n\t\treturn\n\tend", "CLAUDE-BUD guards: unstick off = the old straight MoveTo")
(ok if _cbg_n.count("chaseTo(rec, troot.Position, now, target.UserId)") == 2 and "rec.Humanoid:MoveTo(troot.Position)" not in _cbg_n else bad)(
    "CLAUDE-BUD guards: both player chases use chaseTo (stuck -> jump + sidestep)")

# ── claude-bud JOB 20 (2026-09-29): base guards as real defenders (GuardConfig + Modules/BaseGuards) ──
import os as _g20_os
import subprocess as _g20_sp
import tempfile as _g20_tf

_g20_bg = "src/ServerScriptService/Server/Modules/BaseGuards.luau"
_g20_gd = "src/ServerScriptService/Server/Services/GateDefenseService.luau"
_g20_cfg = "src/ReplicatedStorage/Shared/Configs/GuardConfig.luau"
_g20_c = read(_g20_cfg) or ""
must_contain(_g20_cfg, "\tEnabled = true,", "CLAUDE-BUD J20: live for all")
must_not_contain(_g20_cfg, "IsPlaytestOwner", "CLAUDE-BUD J20: no owner gate")
# reward crediting: the OWNER gets the kill through the server's creator tag, only on the killing hit
must_contain(_g20_bg, "local killing = t.Humanoid.Health - amt <= 0", "CLAUDE-BUD J20: credit decided on the killing hit")
must_contain(_g20_bg, "pcall(cd.TagCreator, t.Humanoid, owner, false) -- CombatService credits the owner (cash, XP, board, feed)", "CLAUDE-BUD J20: a guard kill = the owner's player kill (cash, XP, MOST KILLS, feed)")
must_contain(_g20_bg, 't.Humanoid:SetAttribute("WE_LastWeapon", sourceId)', "CLAUDE-BUD J20: the kill names the guard (feed: <owner>'s Tower Guard)")
must_contain("src/ServerScriptService/Server/Services/GameFeelService.luau", "feed(killer, victim.DisplayName, victim, \"\", killer.DisplayName .. \"'s \" .. guard) -- a base / tower guard kill", "CLAUDE-BUD J20: kill feed line <owner>'s Tower Guard")
# anti-farm + private servers
must_contain(_g20_bg, "GuardConfig.AllowPair(pairLog, owner.UserId, victim.UserId, now)", "CLAUDE-BUD J20: same victim at most PairMax per window")
must_contain(_g20_bg, "not (C.Rewards.NoCreditInPrivateServers and isPrivateServer())", "CLAUDE-BUD J20: no guard-kill credit in private servers (own alts)")
must_contain(_g20_bg, "if GuardConfig.AllowPair(pairLog, attacker.UserId, ownerUserId, os.clock()) then", "CLAUDE-BUD J20: enemy-guard kill reward pair-limited")
must_contain(_g20_bg, 'reward(attacker, C.Rewards.GuardKillCash, C.Rewards.GuardKillXP, "guard_kill")', "CLAUDE-BUD J20: killing a guard = the smaller reward (never RegisterPlayerKill / MOST KILLS)")
# owner / friend / clan / own army safety
must_contain(_g20_bg, "return p.UserId == ownerUserId or H.IsAlly(ownerUserId, p) or areFriends(ownerUserId, p.UserId)", "CLAUDE-BUD J20: never the owner, his clan or his friends")
must_contain(_g20_bg, "if unitOwner == ownerUserId or areFriends(ownerUserId, unitOwner) then", "CLAUDE-BUD J20: never his own (or a friend's) army")
must_contain(_g20_bg, "if not friendlyPlayer(def.OwnerUserId, p, H) and not H.InSpawnGrace(p) then", "CLAUDE-BUD J20: spawn grace respected")
# leash, plot, return, LOS, hit chance, caps
must_contain(_g20_bg, "if flat.Magnitude > C.LeashStuds then", "CLAUDE-BUD J20: leash from the post")
must_contain(_g20_bg, "return H.ClampInside(def, goal)", "CLAUDE-BUD J20: never out of the plot")
must_contain(_g20_bg, "if tnow - (g._bgLastIntruder or -math.huge) >= C.ReturnAfterSeconds", "CLAUDE-BUD J20: back to the post after the quiet time")
must_contain(_g20_bg, "local sees = H.HasLos(pos, t.Root.Position, ignore)", "CLAUDE-BUD J20: line of sight before a shot")
must_contain(_g20_bg, "if rng:NextNumber() <= hitChance(bestD, range) then", "CLAUDE-BUD J20: hit chance")
must_contain(_g20_bg, "local amt = GuardConfig.CapDamage(win.Taken, amount, t.Player ~= nil and lowTarget(t.Player :: Player))", "CLAUDE-BUD J20: damage per target per second capped (lower for new / low-level players)")
must_contain(_g20_bg, "if st.N >= C.MaxShootersPerBase then", "CLAUDE-BUD J20: at most MaxShootersPerBase firing per base")
_ms = re.search(r"MaxShootersPerBase = (\d+)", _g20_c)
(ok if _ms and int(_ms.group(1)) <= 6 else bad)(f"CLAUDE-BUD J20: <= 6 shooters per base ({_ms.group(1) if _ms else '?'})")
for _k, _v in (("RespawnSeconds", 45), ("LeashStuds", 60), ("ReturnAfterSeconds", 8)):
    _m = re.search(r"\b" + _k + r" = (\d+)", _g20_c)
    (ok if _m and int(_m.group(1)) == _v else bad)(f"CLAUDE-BUD J20: {_k} = {_v}")
# hooks + tower guards (bought through the existing research purchase path, rebirth-scaled)
must_contain(_g20_gd, "bgMod.ThinkGuard(def, g, stats, tnow, (GateDefenseService :: any)._H)", "CLAUDE-BUD J20: the guard think hook (5 Hz loop)")
must_contain(_g20_gd, "local okTw, errTw = pcall(bgMod.ThinkTowers, def, tnow, (GateDefenseService :: any)._H)", "CLAUDE-BUD J20: tower guards in the 5 Hz loop")
must_contain(_g20_bg, 'local ok, err = deps.ResearchService.Purchase(player, "TowerGuards")', "CLAUDE-BUD J20: a tower guard is paid through ResearchService.Purchase (the pinned research_ spend)")
must_contain("src/ServerScriptService/Server/Services/ResearchService.luau", "local rebirthScale = tonumber((def :: any).RebirthScale)", "CLAUDE-BUD J20: the tower guard price scales with rebirths")
must_contain(_g20_bg, 'if def == nil or def.OwnerUserId ~= player.UserId or typeof(i) ~= "number" or i ~= hiredCount(player.UserId) + 1 then', "CLAUDE-BUD J20: only the owner hires, one tower at a time")
must_contain(_g20_bg, "for _, t in ipairs(hostiles(def, H, false, pos, C.Tower.Range)) do", "CLAUDE-BUD J20: tower guards shoot only OUTSIDE the walls, within range")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/FeatureController.luau", 'pp.Enabled = pp:GetAttribute("OwnerUserId") == me', "CLAUDE-BUD J20: the hire prompt shows for the owner only")
# the pure helpers, executed
_g20_luau = _g20_os.environ.get("LUAU")
if not _g20_luau and _g20_os.environ.get("LUAU_COMPILE"):
    for _n in ("luau.exe", "luau"):
        _p = _g20_os.path.join(_g20_os.path.dirname(_g20_os.environ["LUAU_COMPILE"]), _n)
        if _g20_os.path.exists(_p):
            _g20_luau = _p
if _g20_luau:
    _src = _g20_c.replace("Color3.fromRGB(240, 190, 50)", "nil")
    _code = "local G = (function()\n" + _src + "\nend)()\n" + r'''
local fails = 0
local function check(ok, label) print((ok and "PASS " or "FAIL ") .. label); if not ok then fails += 1 end end
local log = {}
local n = 0
for i = 1, 5 do if G.AllowPair(log, 1, 2, i) then n += 1 end end
check(n == 3, "same victim 3 times per window (" .. n .. ")")
check(G.AllowPair(log, 1, 2, 1 + G.Rewards.PairWindowSeconds) == true, "the window slides")
check(G.AllowPair(log, 7, 7, 0) == false, "never self")
check(G.CapDamage(0, 50, false) == G.DpsCap.PerTarget, "damage per second capped")
check(G.CapDamage(G.DpsCap.PerTarget, 10, false) == 0, "nothing past the cap")
check(G.CapDamage(0, 50, true) == G.DpsCap.LowTarget, "lower cap for low-level / new players")
check(G.TowerCost(0) == G.Tower.BaseCost and G.TowerCost(2) == math.floor(G.Tower.BaseCost * (1 + 2 * G.Tower.PerRebirth)) and G.TowerCost(1000) == G.Tower.MaxCost, "tower price scales with rebirths, capped")
print(fails == 0 and "ALL PASS" or ("FAILS " .. fails))
'''
    with _g20_tf.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as _f:
        _f.write(_code)
        _tmp = _f.name
    _r = _g20_sp.run([_g20_luau, _tmp], capture_output=True, text=True, timeout=60)
    _g20_os.unlink(_tmp)
    _out = (_r.stdout + _r.stderr).strip()
    (ok if "ALL PASS" in _out else bad)("CLAUDE-BUD J20: GuardConfig executed (anti-farm, damage caps, tower price) " + ("ALL PASS" if "ALL PASS" in _out else _out.replace("\n", " | ")[-300:]))
_rc = read("src/ReplicatedStorage/Shared/Configs/ResearchConfig.luau") or ""
_bc = re.search(r"BaseCost = (\d+)", _g20_c)
_pr = re.search(r"PerRebirth = ([\d.]+)", _g20_c)
(ok if _bc and "Costs = { " + ", ".join([_bc.group(1)] * 4) + " }, -- = GuardConfig.Tower.BaseCost" in _rc and _pr and f"RebirthScale = {_pr.group(1)}, -- = GuardConfig.Tower.PerRebirth" in _rc else bad)("CLAUDE-BUD J20: research Tower Guards price = GuardConfig (base + rebirth scale)")
