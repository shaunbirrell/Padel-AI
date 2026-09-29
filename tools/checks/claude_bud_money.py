# claude-bud JOB 5 (2026-09-29): monetisation build-out. Every item behind MonetizationConfig flags, owner-only first,
# server-authoritative (ProcessReceipt / UserOwnsGamePassAsync), new Ids 0 until the owner creates them.
# Runs inside tools/BuyPathStatic.py (its globals). Helpers start with _cbm_.
_cbm_mc = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
_cbm_vc = "src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau"
_cbm_vs = "src/ServerScriptService/Server/Services/VehicleService.luau"
_cbm_gc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau"
_cbm_awc = "src/ReplicatedStorage/Shared/Configs/AircraftWeaponConfig.luau"

# ── 5a Robux-only vehicles ──
_cbm_v = read(_cbm_vc) or ""
_cbm_prem = re.findall(r'(\w+) = P\(V\("\w+", "[^"]+", "(\w+)", "Premium", 1, (\d+), (\d+), \d+, (\d+), 0, "\w+", \{[^}]*\}\), "(\w+)", "(\w+)"\),', _cbm_v)
(ok if len(_cbm_prem) == 6 else bad)(f"CLAUDE-BUD 5a: six Robux-only vehicles ({[p[0] for p in _cbm_prem]})")
_cbm_cls = {}
for _vid, _cls, _hp, _spd, _arm, _pk, _base in _cbm_prem:
    _cbm_cls.setdefault(_cls, []).append(_vid)
    _m = re.search(r'\b' + _base + r' = V\(\s*"' + _base + r'",\s*"[^"]+",\s*"\w+",\s*"\w+",\s*\d+,\s*(\d+),\s*(\d+),\s*\d+,\s*(\d+),', _cbm_v)
    _b = [int(x) for x in _m.groups()] if _m else [0, 0, 0]
    _r = [int(_hp) / max(_b[0], 1), int(_spd) / max(_b[1], 1), int(_arm) / max(_b[2], 1)]
    (ok if _m and all(1.0 <= x <= 1.08 for x in _r) and max(_r) > 1.0 else bad)(f"CLAUDE-BUD 5a: {_vid} is only slightly stronger than {_base} (HP/speed/armour x{[round(x, 3) for x in _r]})")
    (ok if re.search(r"\n\t\t" + _pk + r" = \{[^\n]*\n\t\t\tId = \d+,", read(_cbm_mc) or "") else bad)(f"CLAUDE-BUD 5a: {_vid} has its own game pass {_pk}")
    must_contain(_cbm_mc, _pk + " = true", f"CLAUDE-BUD 5a: {_pk} is in RolloutKeys (owner-only first)")
_cbm_best = {"Air": ["InterceptorJet", "StealthHeli"], "Naval": ["Battleship", "TorpedoBoat"], "Ground": ["FortressTank", "ReconBuggy"]}
(ok if sorted(len(v) for v in _cbm_cls.values()) == [2, 2, 2] and set(_cbm_cls) == {"Air", "Naval", "Ground"} else bad)(
    f"CLAUDE-BUD 5a: 2 aircraft, 2 boats, 2 ground ({_cbm_cls})")
must_contain(_cbm_vc, "\tx.Premium = { PassKey = passKey }\n\tx.LookId = lookId", "CLAUDE-BUD 5a: premium defs carry their pass and base look")
must_contain(_cbm_vs, 'return false, "RobuxOnly" -- claude-bud JOB 5a', "CLAUDE-BUD 5a: never sold for cash")
_cbm_s = read(_cbm_vs) or ""
_cbm_i = _cbm_s.find("function VehicleService.Purchase(")
(ok if _cbm_i >= 0 and _cbm_s.find('"RobuxOnly"', _cbm_i) < _cbm_s.find("EconomyService.SpendCash", _cbm_i) else bad)("CLAUDE-BUD 5a: the Robux-only refusal comes before any cash spend / grant")
must_contain(_cbm_vs, "and MonetizationService.PlayerOwnsGamePass(player, passKey) == true", "CLAUDE-BUD 5a: spawn needs the pass (server check every spawn)")
must_contain(_cbm_vs, "if not isOwner and not MonetizationConfig.SkuLiveFor(player.UserId, passKey) then", "CLAUDE-BUD 5a: spawn gated by the rollout")
must_contain(_cbm_vs, "if not premiumFree and VehicleService._VehicleHealth.RepairLeft(player.UserId, vehicleId) > 0 then", "CLAUDE-BUD 5a: pass owners respawn free (no repair wait)")
must_contain("src/ServerScriptService/Server/Services/VisualAssetService.luau", "\t\tif vdef and typeof(vdef.LookId) == \"string\" then\n\t\t\tvehicleId = vdef.LookId", "CLAUDE-BUD 5a: premium clones wear their base's body")
must_contain(_cbm_awc, 'PremiumSkylance = "Fighter"', "CLAUDE-BUD 5a: the premium jet is armed like its base")
must_contain(_cbm_awc, 'PremiumStormwing = "AttackHeli"', "CLAUDE-BUD 5a: the premium heli is armed like its base")
must_contain(_cbm_gc, 'return { Kind = "Robux", Text = "R$ " .. tostring(robux), Enabled = true }', "CLAUDE-BUD 5a: Garage shows the Robux price")
must_contain(_cbm_gc, 'meta.Text = string.format("ROBUX · R$ %d · %s · Spd %d", pr, rowTip(def), def.Speed)', "CLAUDE-BUD 5a: Garage ROBUX badge")
must_contain(_cbm_gc, "if catOk and rarOk and ownedOk and premiumListed(def) then", "CLAUDE-BUD 5a: premium rows only where the rollout is live")
must_contain(_cbm_gc, ":PromptGamePassPurchase(Players.LocalPlayer, passId)", "CLAUDE-BUD 5a: the Garage prompts the pass (grant is the server's)")

# ── 5b game passes: 2x Cash / VIP / Auto Collect are live already; + Bigger Army, VIP perks, Extra Garage (stub) ──
_cbm_ss = "src/ServerScriptService/Server/Services/SoldierService.luau"
_cbm_ms = "src/ServerScriptService/Server/Services/MonetizationService.luau"
_cbm_vl = "src/ServerScriptService/Server/Modules/VIPLounge.luau"
_cbm_fc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/FeatureController.luau"
for _k in ("DoubleCash", "VIP", "AutoCollect"):
    (ok if re.search(r"\n\t\t" + _k + r" = \{\n\t\t\tId = [1-9]\d+,", read(_cbm_mc) or "") else bad)(f"CLAUDE-BUD 5b: {_k} game pass is live")
must_contain(_cbm_mc, "\t\tBiggerArmy = {\n\t\t\tId = 0,", "CLAUDE-BUD 5b: Bigger Army pass (Id 0 until the owner creates it)")
must_contain(_cbm_mc, "\t\tExtraGarageSlot = {\n\t\t\tId = 0,\n\t\t\tDisplayName = \"Extra Garage Slot\",\n\t\t\tRobuxPrice = 199,\n\t\t\tHideFromShop = true,", "CLAUDE-BUD 5b: Extra Garage Slot stays hidden until it is built")
must_contain(_cbm_mc, "BiggerArmy = true, ExtraGarageSlot = true, SoldierRefill", "CLAUDE-BUD 5b: new passes owner-only first (RolloutKeys)")
must_contain(_cbm_mc, "\tVIPPerks = {\n\t\tRollout = \"owner\",", "CLAUDE-BUD 5b: VIP perks owner-only first")
must_contain(_cbm_ss, "\tlocal passBonus = biggerArmyBonus(profile)", "CLAUDE-BUD 5b: Bigger Army adds army capacity")
must_contain(_cbm_ms, "if MonetizationConfig.SkuLiveFor(player.UserId, \"BiggerArmy\") and ownsCached(player, \"BiggerArmy\") then", "CLAUDE-BUD 5b: Bigger Army mirrored only from real ownership (UserOwnsGamePassAsync cache)")
must_contain(_cbm_ms, "local vip = MonetizationConfig.VIPPerksLiveFor(player.UserId) and ownsCached(player, \"VIP\")", "CLAUDE-BUD 5b: VIP tag only for a real VIP")
must_contain(_cbm_ms, "return MonetizationConfig.VIPPerksLiveFor(pl.UserId) and ownsCached(pl, \"VIP\")", "CLAUDE-BUD 5b: lounge payout re-checks VIP on the server")
must_contain(_cbm_vl, "if hold[uid] >= P.LoungeHoldSeconds and (last == nil or now - last >= P.LoungeCooldownSeconds) then", "CLAUDE-BUD 5b: lounge bonus once per cooldown")
must_not_contain(_cbm_vl, "OnServerEvent", "CLAUDE-BUD 5b: lounge has no client -> server path")
must_contain(_cbm_fc, "TextChatService.OnIncomingMessage = function(message: TextChatMessage)", "CLAUDE-BUD 5b: VIP chat tag")
must_contain(_cbm_fc, "door.CanCollide = not vip", "CLAUDE-BUD 5b: VIP door opens on the VIP's own client only")

# ── 5c dev products: 4 cash tiers live already; + Instant Army Refill, Plaza Airstrike (no build timers exist) ──
_cbm_pa = "src/ServerScriptService/Server/Modules/PlazaAirstrike.luau"
_cbm_mcs = read(_cbm_mc) or ""
_cbm_cash = [int(x) for x in re.findall(r"Cash(?:Small|Medium|Large|Mega) = \{ Id = (\d+),", _cbm_mcs)]
(ok if len(_cbm_cash) == 4 and all(i > 0 for i in _cbm_cash) else bad)(f"CLAUDE-BUD 5c: 4 cash pack tiers live ({len(_cbm_cash)})")
must_contain(_cbm_mc, "\t\tSoldierRefill = {\n\t\t\tId = 0,", "CLAUDE-BUD 5c: army refill product (Id 0 until created)")
must_contain(_cbm_mc, "\t\tPlazaAirstrike = {\n\t\t\tId = 0,", "CLAUDE-BUD 5c: plaza airstrike product (Id 0 until created)")
must_contain(_cbm_mc, "SoldierRefill = true, PlazaAirstrike = true }", "CLAUDE-BUD 5c: owner-only first (RolloutKeys)")
must_contain(_cbm_mc, "\t\tGrantSoldierRefills = {\n\t\t\tField = \"SoldierRefills\",", "CLAUDE-BUD 5c: refill banked in ProcessReceipt (whitelisted counter, saved before PurchaseGranted)")
must_contain(_cbm_mc, "\t\tGrantAirstrikes = {\n\t\t\tField = \"AirstrikeCharges\",", "CLAUDE-BUD 5c: airstrike banked in ProcessReceipt")
must_contain(_cbm_ss, "function SoldierService.ConsumeRefills(player: Player)", "CLAUDE-BUD 5c: refill spent on the server")
must_contain(_cbm_ms, "pcall(SoldierService.ConsumeRefills, player) -- claude-bud JOB 5c: a refill banked before a crash", "CLAUDE-BUD 5c: a banked refill is spent on join (never lost)")
must_contain(_cbm_pa, "local dmg = math.min(T.Damage, math.max(0, hum.Health - T.MinHealthLeft))", "CLAUDE-BUD 5c: airstrike never lethal")
must_contain(_cbm_pa, "if p ~= player then", "CLAUDE-BUD 5c: airstrike never hits its caller")
must_contain(_cbm_pa, "if now < serverReadyAt then", "CLAUDE-BUD 5c: one airstrike per server per cooldown")
must_contain(_cbm_pa, "if profile == nil or (tonumber(profile.AirstrikeCharges) or 0) < 1 then", "CLAUDE-BUD 5c: needs a paid charge (server)")
must_contain(_cbm_pa, "if not MonetizationConfig.SkuLiveFor(player.UserId, \"PlazaAirstrike\") then", "CLAUDE-BUD 5c: airstrike rollout-gated")
must_contain(_cbm_pa, "deps.RateLimitService.Allow(player, \"plaza_airstrike\", 1, 2)", "CLAUDE-BUD 5c: airstrike remote rate-limited")
_cbm_t = re.search(r"PlazaAirstrikeTuning = \{(.*?)\n\t\},", _cbm_mcs, re.S)
_cbm_tv = dict((k, float(v)) for k, v in re.findall(r"(\w+) = ([\d.]+)", _cbm_t.group(1))) if _cbm_t else {}
(ok if _cbm_tv.get("Damage", 999) <= 50 and _cbm_tv.get("WarnSeconds", 0) >= 2 and _cbm_tv.get("ServerCooldownSeconds", 0) >= 60 and _cbm_tv.get("MinHealthLeft", 0) >= 1 else bad)(
    f"CLAUDE-BUD 5c: airstrike balanced (<= 50 dmg, >= 2 s warning, >= 60 s server cooldown, non-lethal) {_cbm_tv}")

# ── 5d placement: HUD Shop tile + ATM gamepass pads exist; + moment prompts and a real limited starter window ──
_cbm_sc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"
_cbm_ps = "src/ServerScriptService/Server/Services/PrestigeService.luau"
_cbm_so = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
must_contain("src/ReplicatedStorage/Shared/Configs/HudConfig.luau", "DockShop", "CLAUDE-BUD 5d: the HUD has a Shop tile")
must_contain(_cbm_mc, "\tPremiumPads = {", "CLAUDE-BUD 5d: gamepass pads at each base (PremiumPads)")
must_contain(_cbm_mc, "\tPlacement = {\n\t\tRollout = \"owner\",", "CLAUDE-BUD 5d: moment prompts owner-only first")
must_contain(_cbm_ms, "if key == nil or not MonetizationService.ClaimSoftOfferSlot(player) then", "CLAUDE-BUD 5d: every moment prompt spends the soft-offer budget (not spammy)")
must_contain(_cbm_ms, "if dc and (tonumber(dc.Id) or 0) ~= 0 and not ownsCached(player, \"DoubleCash\") then", "CLAUDE-BUD 5d: never offers a pass already owned")
must_contain(_cbm_ps, "pcall(MonetizationService.OfferMoment, player, \"rebirth\")", "CLAUDE-BUD 5d: prompt after a rebirth")
must_contain(_cbm_so, "pcall(ms.OfferMoment, owner, \"army\")", "CLAUDE-BUD 5d: prompt when the army is wiped")
must_contain(_cbm_gc, "place.CantAffordVehicle == true and MonetizationConfig.PlacementLiveFor(lp.UserId)", "CLAUDE-BUD 5d: prompt when a vehicle is unaffordable")
must_contain(_cbm_ms, "\t\tif os.time() >= (limitedEnds :: number) then\n\t\t\treturn nil -- the limited window is over", "CLAUDE-BUD 5d: the starter pack is really limited (never a fake timer)")
must_contain(_cbm_sc, 'displayName ..= string.format(" · Limited: %dh left", math.max(1, math.floor(left / 3600)))', "CLAUDE-BUD 5d: the starter toast shows the time left")
must_contain(_cbm_sc, "function ShopController.PromptDevProduct(productKey: string, source: string?)", "CLAUDE-BUD 5d: offers reuse the Shop's guarded prompt")
must_not_contain(_cbm_fc, "PromptProductPurchase", "CLAUDE-BUD 5d: FeatureController never prompts Marketplace directly")

# ── 5e retention: free Shop rows (daily, airdrop), group reward (server IsInGroupAsync), Premium daily bonus ──
must_contain(_cbm_mc, "\tRetention = {\n\t\tRollout = \"owner\",\n\t\tGroupId = 0,", "CLAUDE-BUD 5e: retention owner-only first; group id TODO (0 = hidden)")
must_contain(_cbm_sc, "task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestClaimDailyReward)", "CLAUDE-BUD 5e: daily reward in the Shop (server claim)")
must_contain(_cbm_sc, 'addRow("FREE · Airdrop"', "CLAUDE-BUD 5e: airdrop in the Shop")
must_contain(_cbm_ms, "return player:IsInGroupAsync(R.GroupId)", "CLAUDE-BUD 5e: group reward checked on the server")
must_contain(_cbm_ms, "if profile == nil or profile.GroupRewardClaimed == true then", "CLAUDE-BUD 5e: group reward once")
must_contain(_cbm_ms, "if player.MembershipType ~= Enum.MembershipType.Premium then", "CLAUDE-BUD 5e: Premium perk checks membership on the server")
must_contain(_cbm_ms, "if tonumber(profile.PremiumBonusDay) == today then", "CLAUDE-BUD 5e: Premium bonus once per UTC day")
must_contain(_cbm_sc, 'addRow("Favorite WAR EMPIRE", "Find us again fast (no reward)"', "CLAUDE-BUD 5e: favorite prompt carries no reward (Roblox rules)")
_cbm_scs = read(_cbm_sc) or ""
_cbm_k = _cbm_scs.find('addRow("Favorite WAR EMPIRE"')
(ok if _cbm_k >= 0 and "AddCash" not in _cbm_scs[_cbm_k:_cbm_k + 600] and "Reward" not in _cbm_scs[_cbm_k + 60:_cbm_k + 600] else bad)("CLAUDE-BUD 5e: nothing rewards a favorite / like")
