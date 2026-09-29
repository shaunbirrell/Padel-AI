# claude-bud PREMIUM (2026-09-29): the 6 Robux-only vehicles are clearly overpowered (owner), and their weapons are
# server-validated. Runs inside tools/BuyPathStatic.py (its globals). Helpers start with _cbp_.
_cbp_vc = "src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau"
_cbp_ws = "src/ServerScriptService/Server/Services/PremiumWeaponService.luau"
_cbp_cl = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/PremiumWeaponsClient.luau"
_cbp_v = read(_cbp_vc) or ""
_cbp_w = read(_cbp_ws) or ""

# every vehicle row: key, category, rarity, hp, speed, armor, cost, kit
_cbp_rows = re.findall(
    r'(\w+) = (?:P\()?V\(\s*"\w+",\s*"[^"]+",\s*"(\w+)",\s*"(\w+)",\s*\d+,\s*(\d+),\s*(\d+),\s*\d+,\s*(\d+),\s*(\d+),\s*"(\w+)"', _cbp_v)
_cbp_best = {}
_cbp_kit = {}
for _k, _cat, _rar, _hp, _spd, _arm, _cost, _kit in _cbp_rows:
    _cbp_kit[_k] = _kit
    if _rar != "Premium" and int(_cost) > 0:
        _b = _cbp_best.setdefault(_kit, [0, 0, 0])
        _cbp_best[_kit] = [max(_b[0], int(_hp)), max(_b[1], int(_spd)), max(_b[2], int(_arm))]
_cbp_stats = re.findall(r"\t\t(Premium\w+) = \{ SpeedMult = ([\d.]+), HPMult = ([\d.]+), ArmorMult = ([\d.]+), AccelMult = ([\d.]+), TurnMult = ([\d.]+), Gun = \"(\w+)\" \}", _cbp_v)
(ok if len(_cbp_stats) == 6 else bad)(f"CLAUDE-BUD PREMIUM: VehicleConfig.Premium.Stats has the 6 Robux-only vehicles ({[s[0] for s in _cbp_stats]})")
for _id, _sm, _hm, _am, _acc, _tm, _gun in _cbp_stats:
    _kit = _cbp_kit.get(_id)
    _best = _cbp_best.get(_kit)
    _sm, _hm, _am, _acc, _tm = float(_sm), float(_hm), float(_am), float(_acc), float(_tm)
    (ok if _best and 1.35 <= _sm <= 1.5 and _hm >= 2 and _am >= 2 and _acc > 1 and _tm > 1 else bad)(
        f"CLAUDE-BUD PREMIUM: {_id} beats the best cash {_kit} (speed x{_sm} of {(_best or [0,0,0])[1]}, HP x{_hm} of {(_best or [0,0,0])[0]}, armour x{_am}, accel x{_acc}, turn x{_tm})")
    must_contain(_cbp_vc, "\t\t" + _gun + " = { Damage = ", f"CLAUDE-BUD PREMIUM: {_id}'s gun {_gun} is defined")
must_contain(_cbp_vc, "\t\t\td.Speed = math.floor(b.Speed * s.SpeedMult + 0.5)\n\t\t\td.Health = math.floor(b.Health * s.HPMult + 0.5)", "CLAUDE-BUD PREMIUM: the rows take their stats from the table (one source)")
_cbp_m = re.search(r"\tMissile = \{(.*?)\n\t\},", _cbp_v, re.S)
_cbp_mv = dict((k, float(v)) for k, v in re.findall(r"(\w+) = ([\d.]+)", _cbp_m.group(1))) if _cbp_m else {}
(ok if 200 <= _cbp_mv.get("LockRange", 0) <= 300 and 0 < _cbp_mv.get("TurnRateDeg", 0) < 360 and _cbp_mv.get("Cooldown", 99) <= 8 else bad)(
    f"CLAUDE-BUD PREMIUM: homing missile ~250 studs, turn-rate limited (dodgeable), short cooldown {_cbp_mv}")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "\t\ta.WE_BaseMaxSpeed = def.Speed\n\t\ta.WE_MaxSpeed = def.Speed * b", "CLAUDE-BUD PREMIUM: premium speed unclamped")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "a.WE_Accel = (tonumber(a.WE_Accel) or 20) * (tonumber(prem.AccelMult) or 1)", "CLAUDE-BUD PREMIUM: snappier acceleration")

# weapons: server-validated (seat, ownership, pass, rate, cone, range / LOS, friendly fire, damage through CombatService)
for _need, _label in (
    ('if seat == nil or seat.Name ~= "DriverSeat" or hum == nil or hum.Health <= 0 then', "only the driver fires"),
    ('if model == nil or model:GetAttribute("OwnerUserId") ~= player.UserId then', "only his own vehicle"),
    ("if not (MonetizationConfig.SkuLiveFor(player.UserId, tostring(prem.PassKey)) or AdminConfig.IsPlaytestOwner(player.UserId)) then", "rollout / pass gate (owner-only first)"),
    ('if rl and not rl.Allow(player, "premium_weapon", P.MaxRequestHz, P.MaxRequestHz) then', "remote rate limit"),
    ("if t - (lastFire[model] or -math.huge) < 0.9 / math.max(0.1, gun.FireRate) then", "gun fire rate"),
    ("if t - (lastMissile[model] or -math.huge) < M.Cooldown then", "missile cooldown"),
    ("dir = clampCone(seat.CFrame.LookVector, dir :: Vector3, gun.ConeDeg)", "aim clamped to the gun's cone"),
    ("local r = Workspace:Raycast(origin, (dir :: Vector3) * gun.Range, rayParams)", "server raycast from the muzzle (range + line of sight)"),
    ("if cs == nil or cs.ApplyHit == nil or friendly(player, inst) then", "friendly fire off (self, own vehicles, clan allies)"),
    ("pcall(cs.ApplyHit, player, inst, amount, {", "damage through CombatService.ApplyHit (PvP / shields / protection)"),
    ("local target = pickTarget(player, model, origin, dir :: Vector3)", "the server picks the missile lock"),
    ("if Workspace:Raycast(origin, d, rayParams) ~= nil then", "missile lock needs line of sight"),
    ("m.Dir = clampCone(m.Dir, want.Unit, math.deg(maxTurn)) -- the turn-rate limit: dodgeable", "missile turn-rate limit"),
):
    must_contain(_cbp_ws, _need, f"CLAUDE-BUD PREMIUM: {_label}")
_cbp_h = re.search(r"OnServerEvent:Connect\(function\(([^)]*)\)", _cbp_w)
(ok if _cbp_h and _cbp_h.group(1).replace(" ", "") == "player:Player,action:any,aim:any" else bad)(
    f"CLAUDE-BUD PREMIUM: the client sends only an action and an aim (never a target or a damage) ({_cbp_h.group(1) if _cbp_h else None})")
must_not_contain(_cbp_cl, "Damage =", "CLAUDE-BUD PREMIUM: the client never states damage")
must_contain(_cbp_cl, 'if model and model:GetAttribute("WE_PremiumGun") ~= nil and model:GetAttribute("OwnerUserId") == lp.UserId then', "CLAUDE-BUD PREMIUM: buttons only while driving his own premium vehicle")
must_contain(_cbp_cl, 'ContextActionService:UnbindAction("WE_PremiumFire")', "CLAUDE-BUD PREMIUM: clean reset on exit")
must_contain(_cbp_cl, "local ok, out = pcall(AW.Layout, 2, vp,", "CLAUDE-BUD PREMIUM: buttons placed clear of jump / EXIT / thumbstick (AirWeaponsClient.Layout)")
must_contain(_cbp_cl, 'local fireB = button(gui, if keys then "FIRE\\nLMB" else "FIRE"', "CLAUDE-BUD PREMIUM: key hints only for keyboard / gamepad")
must_contain(_cbp_ws, 'trail.Name = "WE_PremiumTrail"', "CLAUDE-BUD PREMIUM: gold trail on every premium vehicle")
must_contain(_cbp_ws, 'Name = "WE_PremiumBadge",', "CLAUDE-BUD PREMIUM: ROBUX badge for everyone")
must_contain("src/ReplicatedStorage/Shared/Configs/AircraftWeaponConfig.luau", "\t\tPremiumSkylance = true,\n\t\tPremiumStormwing = true,", "CLAUDE-BUD PREMIUM: premium aircraft use the premium weapons (not the aircraft kit weapons)")
must_contain(_cbp_ws, "rayParams.RespectCanCollide = true", "CLAUDE-BUD PREMIUM: decor never blocks a shot")
must_not_contain(_cbp_ws, "Enum.Material.Neon", "CLAUDE-BUD PREMIUM: no Neon")
