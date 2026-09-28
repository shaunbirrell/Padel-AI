# v90 (Code Bot): Claude's floating-faces pins (handoff/wip/06), moved out of the frozen BuyPathStatic.py.
# --- faces lane (owner screenshot d6bccb79, live v83): a hidden army escort left its face Decal floating (Roblox draws
# a Decal whatever its part's LocalTransparencyModifier); a camera swipe or a turning unit swung an escort file through
# the camera between two 4 Hz passes (the camo "blob"); an own squad unit could stand in the camera's face, at the
# wide phone screen's bottom corners too (a landscape phone sees about 113 degrees across: distance misses it).
# Fix: Decals hide with their escort; the camera guard also runs alone at Escort.Camera.GuardHz over a fixed buffer; an
# own unit nearer than the player and drawn taller than Escort.Camera.LeadScreenFrac of the screen (depth along the
# view) hides locally and is always shown again (pick exit, stream-out). Config off values: GuardHz = 0,
# LeadScreenFrac = 0 (both pass these pins).
# Paste as ONE block directly above the final `parse_gate()` call. Headless-verified (NOT Roblox): every check below
# passes on the faces candidate and fails on main e506c9c or on a named mutant (lane dir runs/mut_*.txt).
FC_RA = 'src/StarterPlayer/StarterPlayerScripts/Client/Modules/RigAnimator.luau'
FC_RC = 'src/ReplicatedStorage/Shared/Configs/RigConfig.luau'
must_contain(FC_RA, 'type Escort = { Model: Model, Tracks: Tracks?, State: string, Torso: BasePart?, Parts: { BasePart }, Decals: { Decal }, Hidden: boolean }',
             "faces: an escort keeps its Decals (the kit head's face) next to its parts")
must_contain(FC_RA, '\tfor _, d in ipairs(copy:GetDescendants()) do -- one small body (<= 30 instances), once per build, never per frame\n\t\tif d:IsA("Decal") then -- the kit head\'s face (a Texture is a Decal too)\n\t\t\td.LocalTransparencyModifier = 0\n\t\t\ttable.insert(decals, d)\n',
             "faces: buildEscort collects every Decal of the copy (GetDescendants: the face sits under Head) once, at build (never a per-pass scan)")
must_contain(FC_RA, 'Parts = parts, Decals = decals, Hidden = false }', "faces: the escort record carries its Decals")
_fc_ra = read(FC_RA) or ''
_fc_rc = read(FC_RC) or ''
def _fc_fn(name):
    m = re.search(r'\nlocal function ' + name + r'\(.*?\n(.*?)\nend\n', _fc_ra, re.S)
    return m.group(1) if m else ''
_fc_seh = _fc_fn('setEscortHidden')
_fc_lt = re.findall(r'(\w+)\.LocalTransparencyModifier = if hidden then 1 else 0', _fc_seh)
if re.search(r'for _, p in ipairs\(x\.Parts\) do\s*\n\s*p\.LocalTransparencyModifier = if hidden then 1 else 0', _fc_seh) \
        and re.search(r'for _, d in ipairs\(x\.Decals\) do[^\n]*\n\s*d\.LocalTransparencyModifier = if hidden then 1 else 0', _fc_seh) \
        and sorted(_fc_lt) == ['d', 'p']:
    ok('faces: setEscortHidden hides and shows the Decals together with the parts (no face floats where a hidden head was)')
else:
    bad(f'faces: setEscortHidden must set LocalTransparencyModifier on x.Parts AND x.Decals, nothing else (got {_fc_lt})')
# the camera guard: config, one function over a fixed buffer, run by the 4 Hz pass AND by its own loop
_fc_hz = re.search(r'\n\t\t\tGuardHz = ([0-9.]+),', _fc_rc)
_fc_lead = re.search(r'\n\t\t\tLeadScreenFrac = ([0-9.]+),', _fc_rc)
_fc_feet = re.search(r'\n\t\t\tRootToFeetStuds = ([0-9.]+),', _fc_rc)
if _fc_hz and (float(_fc_hz.group(1)) == 0 or 20 <= float(_fc_hz.group(1)) <= 60):
    ok(f'faces config: Escort.Camera.GuardHz {_fc_hz.group(1)} is 0 (off) or in [20, 60] (a 0.3 s camera swipe or a turning unit outruns a slower guard)')
else:
    bad('faces config: Escort.Camera.GuardHz must be 0 (off) or 20..60 (at 4-10 Hz a swiped or swung escort file fills the screen between runs)')
if _fc_lead and (float(_fc_lead.group(1)) == 0 or 0.8 <= float(_fc_lead.group(1)) <= 1.0):
    ok(f'faces config: Escort.Camera.LeadScreenFrac {_fc_lead.group(1)} is 0 (off) or in [0.8, 1.0] (only a soldier drawn about screen-tall hides)')
else:
    bad('faces config: Escort.Camera.LeadScreenFrac must be 0 (off) or 0.8..1.0 (lower hides wing soldiers of a running army; higher leaves the corner blob)')
if _fc_feet and 2 <= float(_fc_feet.group(1)) <= 4 and 'LeadHideStuds' not in _fc_rc:
    ok(f'faces config: Escort.Camera.RootToFeetStuds {_fc_feet.group(1)} (squad root half-height + HipHeight) replaces the old distance key')
else:
    bad('faces config: Escort.Camera.RootToFeetStuds (2..4) must exist and the old LeadHideStuds key must be gone')
_fc_cg = _fc_fn('cameraGuard')
if _fc_cg and 'for i = 1, guardN do' in _fc_cg and 'entries' not in _fc_cg and not re.search(r'GetChildren|GetDescendants|FindFirstChild|Instance\.new|table\.|\{', _fc_cg):
    ok('faces: cameraGuard walks only the guard buffer (no registry walk, no scan, no table per run)')
else:
    bad('faces: cameraGuard must loop `for i = 1, guardN do` over the fixed buffer with no scans, lookups or tables (it runs GuardHz times a second)')
must_contain(FC_RA, '\tlocal leadOn = (tonumber(camCfg.LeadScreenFrac) or 0) > 0 -- off: own units without escorts need no guard runs\n',
             "faces: the near-camera rule's own units join the guard buffer only while LeadScreenFrac > 0")
must_contain(FC_RA, '\t\tif #e.Escorts > 0 or (e.Own and leadOn) then\n\t\t\tgn += 1\n\t\t\tguard[gn] = e\n\t\tend\n\tend\n\tfor i = gn + 1, guardN do\n\t\tguard[i] = nil\n\tend\n\tguardN = gn\n\tcameraGuard(camCf, focus, fovDeg)\n',
             "faces: every pass refills the guard buffer (picked figures with escorts; own units while the near-camera rule is on) and runs the guard (the 30 Hz loop idles when it is empty)")
must_contain(FC_RA, '\tfor i = 1, guardN do\n\t\tif guard[i] == e then\n\t\t\tguard[i] = guard[guardN]\n\t\t\tguard[guardN] = nil\n\t\t\tguardN -= 1\n',
             "faces: a figure that streams out / dies leaves the guard buffer at once (the loop never touches a removed figure)")
must_contain(FC_RA, '\tlocal guardHz = tonumber(camCfg.GuardHz) or 0\n\tif guardHz > 0 then\n\t\ttask.spawn(function() -- the camera guard alone between passes (a camera swipe, a turning unit\'s file)\n\t\t\tlocal gp = 1 / math.clamp(guardHz, 1, 60)\n',
             "faces: the camera guard has its own task.wait loop at GuardHz (no RenderStepped / Heartbeat)")
must_contain(FC_RA, '\t\t\t\ttask.wait(if guardN > 0 then gp else idle) -- nothing to guard: sleep one LOD pass\n',
             "faces: the guard loop sleeps a whole LOD pass while there is nothing to guard")
must_contain(FC_RA, '\t\t\t\t\tcameraGuard(cam.CFrame, if hrp and hrp:IsA("BasePart") then hrp.Position else nil, cam.FieldOfView)\n',
             "faces: the guard loop uses the live camera and the local player's root")
# an own squad unit in the camera's face: hidden locally, parts AND Decals, restored by every path
must_contain(FC_RA, '\tlocal leadFrac = tonumber(camCfg.LeadScreenFrac) or 0\n\tlocal leadDepth = if leadFrac > 0 then camCfg.FigureStuds / (2 * leadFrac * tanHalf) + camCfg.DepthMarginStuds else -math.huge\n\tlocal feet = camCfg.RootToFeetStuds\n',
             "faces: the own-unit line is a depth along the view where a figure is drawn LeadScreenFrac of the screen tall (off: never)")
must_contain(FC_RA, '\tlocal nearLift = math.min(-feet * look.Y, (camCfg.FigureStuds - feet) * look.Y)\n',
             "faces: the unit's body line (feet RootToFeetStuds below its root up to its head top) comes from config, no body-size number in code")
must_contain(FC_RA, '\t\t\tlocal v = root.Position - camPos\n\t\t\t-- depth along the view sets how large the phone draws it, at the screen\'s wide corners too (distance does not)\n\t\t\tlocal near = v:Dot(look) + nearLift\n\t\t\tlocal d = v.Magnitude\n',
             "faces: an own unit is judged by the depth of its body's nearest point along the view (a wide screen's corner draws a soldier 5-6 studs away screen-tall)")
must_contain(FC_RA, '\t\t\telseif near < leadDepth and d < playerDist then\n\t\t\t\tsetLeadHidden(e, true)\n',
             "faces: an own unit drawn taller than LeadScreenFrac of the screen, nearer than the player, hides on this client")
must_contain(FC_RA, '\t\t\t\tif near >= leadDepth + hyst or d >= playerDist + hyst then\n\t\t\t\t\tsetLeadHidden(e, false)\n',
             "faces: it shows again ShowHysteresisStuds past either line")
must_contain(FC_RA, '\t\tif e.Own and root then\n', "faces: the near-camera rule is for the local player's own units only (never another player's army)")
_fc_rm = _fc_fn('remove')
if 'if e.LeadHidden then\n\t\tsetLeadHidden(e, false)' in _fc_rm and 'LeadsHidden' not in _fc_rm:
    ok('faces: remove() shows a hidden own unit again (parts + face) before it leaves the registry (a streamed-out rig can come back as the same instance)')
else:
    bad('faces: remove() must call setLeadHidden(e, false) for a LeadHidden unit (never only fix the stat: a re-added rig would stay invisible)')
_fc_slh = _fc_fn('setLeadHidden')
if '\tfor _, c in ipairs(e.Rig:GetChildren()) do\n\t\tif c:IsA("BasePart") then\n' in _fc_slh and 'c.LocalTransparencyModifier = if hidden or (c == e.Beret and e.Far) then 1 else 0' in _fc_slh \
        and re.search(r'\n\t\t\tfor _, d in ipairs\(c:GetChildren\(\)\) do\n\t\t\t\tif d:IsA\("Decal"\) then[^\n]*\n\s*d\.LocalTransparencyModifier = if hidden then 1 else 0', _fc_slh):
    ok("faces: setLeadHidden hides the rig's parts and each part's own Decals (the face on Head), keeping the LOD's hidden beret")
else:
    bad("faces: setLeadHidden must walk the rig's parts, set LocalTransparencyModifier on each AND on each part's Decals (c:GetChildren()), and keep a far figure's beret hidden")
must_contain(FC_RA, '\t\te.Beret.LocalTransparencyModifier = if far or e.LeadHidden then 1 else 0\n',
             "faces: the blocks LOD never shows the beret of a unit hidden by the camera guard")
must_contain(FC_RA, '\t\tif e.LeadHidden and not e.Picked then\n\t\t\tsetLeadHidden(e, false) -- out of the guard buffer: shown again\n',
             "faces: a unit that leaves the pick (far, streamed) is shown again (never stays hidden)")
# ── end faces lane

