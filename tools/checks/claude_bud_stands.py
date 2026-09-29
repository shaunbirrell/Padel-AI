# claude-bud JOB 19 (2026-09-29): purchase stands replace the flat Robux pads (PurchaseStands + MapSetup +
# PlotOilPumpService + PremiumPadService + ShopController + StandFx). Only the prompt buys; the same purchase path; prices
# from MonetizationConfig; OWNED look; no shadows, <= 1 light per stand; the depot row clear of the base layout.
_s_ps = "src/ServerScriptService/Server/Modules/PurchaseStands.luau"
_s_pp = "src/ServerScriptService/Server/Services/PremiumPadService.luau"
_s_ms = "src/ServerScriptService/Server/Modules/MapSetup.luau"
_s_sc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"
_s_mc = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
_s_p = read(_s_ps) or ""
_s_s = read(_s_pp) or ""

# the prompt is the ONLY trigger (no touch / standing buy on a stand)
must_contain(_s_pp, 'if part:GetAttribute("WE_Stand") == true then\n\t\tlocal pp = part:FindFirstChild("WE_BuyPrompt")', "CLAUDE-BUD J19: a stand buys only through its ProximityPrompt")
_i = _s_s.find('if part:GetAttribute("WE_Stand") == true then')
_j = _s_s.find("part.Touched:Connect", _i)
_r = _s_s.find("\t\treturn\n\tend", _i)
(ok if 0 <= _i < _r < _j else bad)("CLAUDE-BUD J19: the stand branch returns before any Touched hook")
must_contain(_s_pp, 'if not part.Parent or part:GetAttribute("WE_Stand") == true then', "CLAUDE-BUD J19: the standing check skips stands")
must_contain(_s_pp, "tryPrompt(player, part, false)", "CLAUDE-BUD J19: the same tryPrompt path")
must_contain(_s_pp, "promptRemote:FireClient(player, {", "CLAUDE-BUD J19: the same PromptPremiumPad -> PromptPurchase / ProcessReceipt path")
must_contain(_s_pp, "if alreadyOwns(player, kind, offerKey, part) then", "CLAUDE-BUD J19: an owned offer never prompts (server)")
must_contain(_s_ps, 'pp.ActionText = "Buy - " .. ROBUX .. " " .. tostring(price)', "CLAUDE-BUD J19: prompt text Buy - R$ X")
must_contain(_s_ps, "pp.HoldDuration = S.HoldSeconds", "CLAUDE-BUD J19: a short hold (no accidental buy)")

# prices from config, never typed
must_contain(_s_ps, "local price = if typeof(def) == \"table\" then tonumber(def.RobuxPrice) or 0 else 0", "CLAUDE-BUD J19: the price comes from MonetizationConfig")
(ok if not re.search(r"R\$ ?\d|ROBUX \.\. \" \d", _s_p) else bad)("CLAUDE-BUD J19: no hard-coded price in the stand")

# the purchase part keeps the old pad contract
for _a in ('top:SetAttribute("PlotId", o.PlotId)', 'top:SetAttribute("OfferKind", o.Kind)', 'top:SetAttribute("OfferKey", o.Key)', 'top:SetAttribute("OwnedIfAny", o.OwnedIfAny)', "CollectionService:AddTag(top, TAG)"):
    must_contain(_s_ps, _a, f"CLAUDE-BUD J19: the stand top keeps the pad contract ({_a[:40]})")

# look + budgets
(ok if _s_p.count('part("Plinth"') == 1 and "for k = 0, 2 do" in _s_p else bad)("CLAUDE-BUD J19: hexagonal plinth (3 boxes at 0 / 60 / 120)")
must_contain(_s_ps, 'part("GoldTrim"', "CLAUDE-BUD J19: gold trim ring")
must_contain(_s_ps, 'local ring = part("FloorRing"', "CLAUDE-BUD J19: the Neon floor ring")
must_contain(_s_ps, 'local holo = part("Hologram"', "CLAUDE-BUD J19: the hologram")
must_contain(_s_ps, 'label(chip, "Price", ROBUX', "CLAUDE-BUD J19: gold price chip with the Robux icon")
(ok if _s_p.count('Instance.new("PointLight")') == 1 and "light.Shadows = false" in _s_p else bad)("CLAUDE-BUD J19: one light per stand, Shadows off")
must_contain(_s_ps, "p.CastShadow = false", "CLAUDE-BUD J19: no shadows")
_lm = re.search(r"LabelMaxDistance = (\d+), -- CLAUDE.md world labels", read(_s_mc) or "")
(ok if _lm and int(_lm.group(1)) <= 40 else bad)(f"CLAUDE-BUD J19: stand labels MaxDistance <= 40 ({_lm.group(1) if _lm else '?'})")
must_not_contain(_s_ps, "AlwaysOnTop = true", "CLAUDE-BUD J19: no AlwaysOnTop")

# OWNED look (client)
must_contain(_s_sc, 'price.Text = "✓ OWNED"', "CLAUDE-BUD J19: OWNED check badge")
must_contain(_s_sc, "pp.Enabled = not owned", "CLAUDE-BUD J19: an owned stand shows no prompt")
must_contain(_s_sc, "p.Color = if owned then green else base", "CLAUDE-BUD J19: OWNED green tint")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/StandFx.luau", "if low() then", "CLAUDE-BUD J19: no motion in low quality")

# the Supply Depot row: clear of structures, kiosks, roads, the spawn and the ATM (plot-local)
_mc = read(_s_mc) or ""
_d = re.search(r"Depot = \{ X0 = (-?\d+), Step = (\d+), Z = (\d+), SignZ = (\d+)", _mc)
_bl = read("src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau") or ""
if _d:
    _x0, _st, _z, _sz = (float(v) for v in _d.groups())
    _n = 4  # 3 ATM slots (+1 spare)
    _row = [(_x0 + k * _st, _z) for k in range(_n)]
    _stand_r = 3.2 + 1.5 + 2  # plinth + ring + a walking gap
    _sites = [(float(x), float(z)) for x, z in re.findall(r"Site = \{ X = (-?\d+), Z = (-?\d+) \}", _bl)]
    _kiosks = [(float(x), float(z)) for x, z in re.findall(r"Kiosk = \{ X = (-?\d+), Z = (-?\d+) \}", _bl)]
    _hits = []
    for (sx, sz) in _row:
        for (x, z) in _sites:
            if abs(sx - x) < 16 + _stand_r and abs(sz - z) < 16 + _stand_r:
                _hits.append(("site", x, z))
        for (x, z) in _kiosks:
            if ((sx - x) ** 2 + (sz - z) ** 2) ** 0.5 < 6 + _stand_r:
                _hits.append(("kiosk", x, z))
        if abs(sx) < 7 + _stand_r:
            _hits.append(("main road", 0, sz))
        if ((sx - 0) ** 2 + (sz - 136) ** 2) ** 0.5 < 12 + _stand_r:
            _hits.append(("spawn", 0, 136))
        if ((sx - (-14)) ** 2 + (sz - 126) ** 2) ** 0.5 < 10 + _stand_r:
            _hits.append(("ATM", -14, 126))
    (ok if not _hits and _sz < 158 and _z + _stand_r < _sz else bad)(f"CLAUDE-BUD J19: Supply Depot row {_row} clear of the layout / spawn / ATM, sign inside the front wall {_hits}")
else:
    bad("CLAUDE-BUD J19: Depot config missing")
must_contain(_s_ms, "pcall((Stands :: any).Sign, folder, F * CFrame.new(mid, 0.3, D.SignZ) * CFrame.Angles(0, math.pi, 0), D.Sign)", "CLAUDE-BUD J19: one Supply Depot sign")
must_contain(_s_mc, "\t\tStands = true,", "CLAUDE-BUD J19: stands live for all (false = the old pads)")
