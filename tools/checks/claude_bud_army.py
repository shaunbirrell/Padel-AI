# claude-bud (2026-09-29): army tidy follow (ArmyConfig.Follow2.Tidy, owner-only first). Owner: "the army still walks into
# the base and the soldiers bunch up and walk over each other". Runs inside tools/BuyPathStatic.py. Helpers: _cba_.
_cba_ac = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
_cba_af = "src/ServerScriptService/Server/Modules/ArmyFollow.luau"
_cba_a = read(_cba_af) or ""

must_contain(_cba_ac, '\t\tEnabled = true,\n\t\tRollout = "all",', "CLAUDE-BUD army: the Follow2 kill switch (Enabled / Rollout) is kept")
# v101 (Code Bot): retired, superseded in tools/checks/codebot_v101.py: #must_contain(_cba_ac, '\t\tTidy = {\n\t\t\tRollout = "owner",', "CLAUDE-BUD army: Tidy ships owner-only")
must_contain(_cba_af, 'return r == "all" or (r == "owner" and AdminConfig.IsPlaytestOwner(player.UserId) == true)', "CLAUDE-BUD army: tidyLive fails closed")

# (a) hold outside the gate, never cross the plot edge
must_contain(_cba_af, 'inside = if st._afInBase then edge <= half + tnum("HoldReleaseStuds", 10) else edge <= half + tnum("HoldApproachStuds", 6)', "CLAUDE-BUD army: the hold starts before he reaches his edge (from outside)")
must_contain(_cba_af, "local unitOutside = ownPlot ~= nil and not inPlot(ownPlot, pos, 0)", "CLAUDE-BUD army: units outside his plot are kept out")
(ok if _cba_a.count("keepOut(") >= 4 else bad)("CLAUDE-BUD army: slot goal, path waypoint and trail fallback all pass keepOut")
must_contain(_cba_af, "local z = half + tnum(\"WaitOut\", 14) + row * tnum(\"RowSpacing\", 4)", "CLAUDE-BUD army: wait rows are outside the front edge")
must_contain(_cba_af, "local x = side * (gateHalf + tnum(\"WaitGap\", 5) + col * tnum(\"ColSpacing\", 4))", "CLAUDE-BUD army: wait rows leave the gate lane clear")
must_contain(_cba_af, "unit.Model:PivotTo(CFrame.lookAt(unit.Root.Position, unit.Root.Position + out)) -- turn on the spot only", "CLAUDE-BUD army: soldiers face out at the gate")

# (b) fixed seats, no crossing, rows wider than the separation radius
must_contain(_cba_af, "--[[ claude-bud (Tidy): fixed seats for life, UNIQUE per squad", "CLAUDE-BUD army: fixed formation seats")
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
must_contain(_cba_af, "if not seatedFast and not walkBack and not holdOut then", "CLAUDE-BUD army: the grace skips only far / stuck / owner-jump (void rescue still runs)")

# ── v95 owner phone test fix (2026-09-29): hold before the gate, clean validated grid, ATTACK spots per seat ──
import math as _cba_math
_cba_so = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_cba_so_s = read(_cba_so) or ""
# unique seats: one assigner, duplicates / missing re-issued the lowest free number
must_contain(_cba_af, "\t\tif typeof(s) == \"number\" and s >= 1 and taken[s] == nil then\n\t\t\ttaken[s] = u\n\t\telse\n\t\t\tu._afSeat = nil", "CLAUDE-BUD army fix: a duplicated seat is dropped (unique slots)")
must_contain(_cba_af, "\t\t\twhile taken[s] ~= nil do\n\t\t\t\ts += 1\n\t\t\tend", "CLAUDE-BUD army fix: re-issued seats take the lowest FREE number")
must_contain(_cba_af, "\t\tassignSeats(st, order)\n\t\tfor _, u in ipairs(order) do\n\t\t\tu._afRank = u._afSeat", "CLAUDE-BUD army fix: FOLLOW / hold rank = the unique seat")
# hold: validated cells, straight, no path, no teleport while outside
must_contain(_cba_af, "local parts = Workspace:GetPartBoundsInBox(box, Vector3.new(3, 4.6, 3), overlapParams)", "CLAUDE-BUD army fix: each hold cell overlap-checked (walls / props)")
must_contain(_cba_af, "if hit == nil or hit.Material == Enum.Material.Water or math.abs(hit.Position.Y - refY) > 2.5 then", "CLAUDE-BUD army fix: each hold cell ground-raycast (no water / roof)")
must_contain(_cba_af, "local holdOut = st._afTidy and st._afInBase and st._afPlot ~= nil and not inPlot(st._afPlot, pos, 0)", "CLAUDE-BUD army fix: units outside go straight to their cell while he is in")
must_contain(_cba_af, "if not seatedFast and not walkBack and not holdOut then", "CLAUDE-BUD army fix: no stuck / far teleport correction while holding outside")
_cba_i = _cba_a.find("\tif holdOut and st._afPlot then")
_cba_blk = _cba_a[_cba_i:_cba_a.find("\t-- movement: straight while it sees the slot", _cba_i)] if _cba_i >= 0 else ""
(ok if _cba_blk and "requestPath" not in _cba_blk and "regroup(" not in _cba_blk and "moveTo(unit, via, now)" in _cba_blk else bad)(
    "CLAUDE-BUD army fix: the hold walk has no pathfinding and no teleport")
must_contain(_cba_af, "local sep = if st._afTidy and st._afInBase then 0 else num(\"SeparationStuds\", 3.5)", "CLAUDE-BUD army fix: hold cells are exact (no separation push)")
# hold grid geometry from the config: every nominal cell outside the gate plane (front edge + pad), clear of the gate
# lane, unique, >= 3 studs apart
_cba_half = 160.0
_cba_gate = 14.0 / 2
_cba_cells = set()
for _side in (-1, 1):
    for _row in range(0, 12):
        for _col in range(int(_cba_t.get("PerRow", 4))):
            _cba_cells.add((_side * (_cba_gate + _cba_t.get("WaitGap", 5) + _col * _cba_t.get("ColSpacing", 4)), _cba_half + _cba_t.get("WaitOut", 14) + _row * _cba_t.get("RowSpacing", 4)))
_cba_min = min((_cba_math.hypot(a[0] - b[0], a[1] - b[1]) for a in _cba_cells for b in _cba_cells if a < b), default=0)
(ok if all(z >= _cba_half + _cba_t.get("PlotPadStuds", 2) + 4 and abs(x) > _cba_gate for x, z in _cba_cells) and _cba_min >= 3 else bad)(
    f"CLAUDE-BUD army fix: hold cells all outside the gate plane (>= edge + pad + 4), off the gate lane, unique, >= 3 apart (min {_cba_min})")
# ATTACK: per-seat spots, never a shared point; simulated for squads of 1..60
must_contain(_cba_so, "unit.Humanoid:MoveTo(af.AttackPoint(st, unit, playerRoot.Position, playerRoot.CFrame.LookVector, \"march\"))", "CLAUDE-BUD army fix: ATTACK with no target uses per-seat march spots")
must_contain(_cba_so, "local ringAt = afA.AttackPoint(st, unit, center, center - (if playerRoot then playerRoot.Position else from), \"ring\")", "CLAUDE-BUD army fix: ATTACK chase uses a per-seat ring round the target")
_cba_j = _cba_so_s.find("\tlocal afA = attackTidy(player)")
_cba_blk2 = _cba_so_s[_cba_j:_cba_so_s.find("\tif unit.AimRoot ~= nil then", _cba_j)] if _cba_j >= 0 else ""
(ok if _cba_blk2 and "MoveTo(nroot.Position)" not in _cba_blk2 and "MoveTo(aimAt)" not in _cba_blk2 else bad)("CLAUDE-BUD army fix: the tidy ATTACK path never sends units to the shared target Vector3")
def _cba_attack(n, mode):
    pts = []
    for k in range(1, n + 1):
        if mode == "ring":
            r = max(_cba_t.get("AttackRingMin", 8), n * _cba_t.get("AttackRingSpacing", 3.5) / (2 * _cba_math.pi))
            a = (k - 1) * 2 * _cba_math.pi / n
            pts.append((r * _cba_math.sin(a), -r * _cba_math.cos(a)))
        else:
            per = int(_cba_t.get("MarchPerRow", 5)); sp = _cba_t.get("MarchSpacing", 3.5)
            row, col = (k - 1) // per, (k - 1) % per
            inrow = min(per, n - row * per)
            pts.append(((col - (inrow - 1) * 0.5) * sp, _cba_t.get("MarchAhead", 10) + row * sp))
    return pts
_cba_worst = 99.0
for _n in range(2, 61):
    for _mode in ("march", "ring"):
        _p = _cba_attack(_n, _mode)
        _d = min(_cba_math.hypot(a[0] - b[0], a[1] - b[1]) for i, a in enumerate(_p) for b in _p[i + 1:])
        _cba_worst = min(_cba_worst, _d)
(ok if _cba_worst >= 3 else bad)(f"CLAUDE-BUD army fix: ATTACK spots unique and >= 3 studs apart for squads of 2..60 (min {_cba_worst:.2f})")
must_contain(_cba_so, "\tif af and af.TidyLive and af.AttackPoint and af.TidyLive(player) then", "CLAUDE-BUD army fix: ATTACK formation behind the Tidy kill switch")

# ── claude-bud (owner: "the army is still glitchy and despawns when walking"): Flank formation in front of the camera ──
_cba_fl = {k: float(v) for k, v in re.findall(r"\t\t\t(Flank\w+) = (-?[\d.]+),", read(_cba_ac) or "")}
must_contain(_cba_ac, '\t\t\tFormation = "Flank",', "CLAUDE-BUD army: Flank formation on (\"Wedge\" = the old one)")
must_contain(_cba_af, 'back = tnum("FlankFront", -1) + (row - 1) * tnum("FlankRowBack", 3)', "CLAUDE-BUD army: flank rows")
if len(_cba_fl) == 4:
    _rows = 4  # OrdersConfig.MaxFieldUnits 5 + ResearchConfig SquadExpansion 3 = 8 units = 4 rows
    _last_back = _cba_fl["FlankFront"] + (_rows - 1) * _cba_fl["FlankRowBack"]
    _nb = (_cba_fl["FlankRowBack"] ** 2 + _cba_fl["FlankRowSide"] ** 2) ** 0.5
    (ok if _last_back <= 10 else bad)(f"CLAUDE-BUD army: the last flank row is {_last_back} studs back (<= 10: in front of a ~12-15 stud phone camera)")
    (ok if _nb > _cba_sep and 2 * _cba_fl["FlankSide"] > _cba_sep else bad)(f"CLAUDE-BUD army: flank neighbours {_nb:.2f} studs apart, files {2 * _cba_fl['FlankSide']} apart (> SeparationStuds {_cba_sep})")
    (ok if _cba_fl["FlankRowSide"] >= 2 else bad)("CLAUDE-BUD army: each flank row on its own side line (escort files never land on a soldier)")
else:
    bad(f"CLAUDE-BUD army: flank numbers missing {_cba_fl}")
