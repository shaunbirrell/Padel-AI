# claude-bud (2026-09-29): army tidy follow (ArmyConfig.Follow2.Tidy, owner-only first). Owner: "the army still walks into
# the base and the soldiers bunch up and walk over each other". Runs inside tools/BuyPathStatic.py. Helpers: _cba_.
_cba_ac = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
_cba_af = "src/ServerScriptService/Server/Modules/ArmyFollow.luau"
_cba_a = read(_cba_af) or ""

must_contain(_cba_ac, '\t\tEnabled = true,\n\t\tRollout = "all",', "CLAUDE-BUD army: the Follow2 kill switch (Enabled / Rollout) is kept")
must_contain(_cba_ac, '\t\tTidy = {\n\t\t\tRollout = "owner",', "CLAUDE-BUD army: Tidy ships owner-only")
must_contain(_cba_af, 'return r == "all" or (r == "owner" and AdminConfig.IsPlaytestOwner(player.UserId) == true)', "CLAUDE-BUD army: tidyLive fails closed")

# (a) hold outside the gate, never cross the plot edge
must_contain(_cba_af, 'inside = if st._afInBase then edge <= half + tnum("HoldReleaseStuds", 10) else edge <= half + tnum("HoldApproachStuds", 6)', "CLAUDE-BUD army: the hold starts before he reaches his edge (from outside)")
must_contain(_cba_af, "local unitOutside = ownPlot ~= nil and not inPlot(ownPlot, pos, 0)", "CLAUDE-BUD army: units outside his plot are kept out")
(ok if _cba_a.count("keepOut(") >= 4 else bad)("CLAUDE-BUD army: slot goal, path waypoint and trail fallback all pass keepOut")
must_contain(_cba_af, "local z = half + tnum(\"WaitOut\", 14) + row * tnum(\"RowSpacing\", 4)", "CLAUDE-BUD army: wait rows are outside the front edge")
must_contain(_cba_af, "local x = side * (gateHalf + tnum(\"WaitGap\", 5) + col * tnum(\"ColSpacing\", 4))", "CLAUDE-BUD army: wait rows leave the gate lane clear")
must_contain(_cba_af, "unit.Model:PivotTo(CFrame.lookAt(unit.Root.Position, unit.Root.Position + out)) -- turn on the spot only", "CLAUDE-BUD army: soldiers face out at the gate")

# (b) fixed seats, no crossing, rows wider than the separation radius
must_contain(_cba_af, "-- claude-bud: fixed seats for life; a dead / gone unit frees its seat, nobody else moves up", "CLAUDE-BUD army: fixed formation seats")
must_contain(_cba_af, "if st._afFlip and st._afFlip[row] == true then\n\t\t\tside = -side", "CLAUDE-BUD army: row pairs keep their world sides when he turns")
_cba_m = re.search(r"\t\tTidy = \{(.*?)\n\t\t\},", read(_cba_ac) or "", re.S)
_cba_t = dict((k, float(v)) for k, v in re.findall(r"(\w+) = (-?[\d.]+)", _cba_m.group(1))) if _cba_m else {}
_cba_sep = re.search(r"SeparationStuds = ([\d.]+)", read(_cba_ac) or "")
_cba_sep = float(_cba_sep.group(1)) if _cba_sep else 99
(ok if _cba_t and min((_cba_t["RowBack"] ** 2 + _cba_t["RowSide"] ** 2) ** 0.5, _cba_t["ColSpacing"], _cba_t["RowSpacing"]) > _cba_sep else bad)(
    f"CLAUDE-BUD army: tidy wedge rows and wait rows are wider than SeparationStuds {_cba_sep} ({_cba_t})")
(ok if _cba_t and _cba_t.get("WaitOut", 0) > _cba_t.get("PlotPadStuds", 99) and _cba_t.get("HoldReleaseStuds", 0) > _cba_t.get("HoldApproachStuds", 99) else bad)(
    "CLAUDE-BUD army: wait rows lie beyond the keep-out pad; release hysteresis > approach")

# (c) walk back, no teleport
must_contain(_cba_af, 'local walkBack = st._afTidy and not st._afInBase and now - (st._afLeftBaseAt or -math.huge) < tnum("LeaveGraceSeconds", 8)', "CLAUDE-BUD army: no far / stuck teleport right after he leaves")
must_contain(_cba_af, "if not seatedFast and not walkBack then", "CLAUDE-BUD army: the grace skips only far / stuck / owner-jump (void rescue still runs)")
