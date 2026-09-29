# claude-bud (2026-09-29): guards fight back, bag pickup line of sight, unstick G1/G2 (Empire Bank; CP-9 items 1, 5, 7).
# All three are owner-only first. Runs inside tools/BuyPathStatic.py (its globals). Helpers start with _cbg_.
_cbg_cc = "src/ReplicatedStorage/Shared/Configs/CombatConfig.luau"
_cbg_npc = "src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau"
_cbg_cs = "src/ServerScriptService/Server/Services/CombatService/init.luau"
_cbg_sos = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_cbg_oc = "src/ReplicatedStorage/Shared/Configs/OpsConfig.luau"
_cbg_os = "src/ServerScriptService/Server/Services/OpsService/init.luau"

# flags: owner-only, fail closed
must_contain(_cbg_cc, "\tGuardsFightBack = {\n\t\tRollout = \"owner\",", "CLAUDE-BUD guards: GuardsFightBack ships owner-only")
must_contain(_cbg_cc, "\tNpcUnstick = {\n\t\tRollout = \"owner\",", "CLAUDE-BUD guards: NpcUnstick ships owner-only")
must_contain(_cbg_cc, "\t\treturn AdminConfig.IsPlaytestOwner(userId)\n\tend\n\treturn false\nend", "CLAUDE-BUD guards: CombatConfig.LiveFor fails closed")
must_contain(_cbg_oc, 'PickupLosRollout = "owner",', "CLAUDE-BUD guards: bag LOS ships owner-only")

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
