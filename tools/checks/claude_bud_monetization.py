# claude-bud (2026-09-28): the 3 Robux SKUs wired end to end behind MonetizationConfig.Rollout = "owner".
# Speed Pass 1998656357, Keep-Base Rebirth 3714663721, Golden Pumpjacks 3714663783. Helpers start with _cbud_.
_cbud_mc = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
_cbud_ms = "src/ServerScriptService/Server/Services/MonetizationService.luau"
_cbud_pp = "src/ServerScriptService/Server/Services/PlotOilPumpService.luau"
_cbud_ps = "src/ServerScriptService/Server/Services/PrestigeService.luau"
_cbud_sc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"

must_contain(_cbud_mc, '\tRollout = "owner",\n', "CLAUDE-BUD: MonetizationConfig.Rollout is owner-only first")
must_contain(_cbud_mc, "RolloutKeys = { ImpulseSpeed = true, RebirthKeepBase = true, GoldenPumpjack = true, PV_Skylance = true, PV_Stormwing = true, PV_Leviathan = true, PV_Tidebreaker = true, PV_Warlord = true, PV_Razorfang = true, BiggerArmy = true, ExtraGarageSlot = true }", "CLAUDE-BUD: the 3 gated SKU keys")
must_contain(_cbud_mc, "function MonetizationConfig.SkuLiveFor(userId: any, key: string): boolean", "CLAUDE-BUD: SkuLiveFor helper")
must_contain(_cbud_mc, "return AdminConfig.IsPlaytestOwner(userId)", "CLAUDE-BUD: owner mode uses IsPlaytestOwner")
must_contain(_cbud_mc, "\t\t\tId = 1998656357,\n\t\t\tDisplayName = \"Speed Pass\",", "CLAUDE-BUD: Speed Pass Id")
must_contain(_cbud_mc, "\t\tRebirthKeepBase = {\n\t\t\tId = 3714663721,", "CLAUDE-BUD: Keep-Base Rebirth Id")
must_contain(_cbud_mc, "\t\tGoldenPumpjack = {\n\t\t\tId = 3714663783,", "CLAUDE-BUD: Golden Pumpjacks Id")
must_contain(_cbud_mc, "IncomeMult = 1.5,", "CLAUDE-BUD: Golden Pumpjacks income multiplier in config")
must_contain(_cbud_mc, '(MonetizationConfig.Rollout == "all" or not (MonetizationConfig.RolloutKeys :: any)[offer.Key])', "CLAUDE-BUD: world pads skip gated SKUs until Rollout=all")

must_contain(_cbud_ms, "MonetizationConfig.SkuLiveFor(player.UserId, passKey) and ownsCached(player, passKey)", "CLAUDE-BUD: Speed Pass counts only when live for the player")
must_contain(_cbud_ms, "if not MonetizationConfig.SkuLiveFor(player.UserId, productKey :: string) then", "CLAUDE-BUD: dev product intent gated")
must_contain(_cbud_ms, "if not MonetizationConfig.SkuLiveFor(player.UserId, passKey :: string) then", "CLAUDE-BUD: game pass intent gated")
must_contain(_cbud_ms, "if not MonetizationConfig.SkuLiveFor(victim.UserId, passKey) then", "CLAUDE-BUD: death speed offer gated")

must_contain(_cbud_pp, "local goldForOwner = MonetizationConfig.SkuLiveFor(ownerUserId, GOLDEN_KEY)", "CLAUDE-BUD: gold dress gated")
must_contain(_cbud_pp, "if goldLive and goldForOwner and not hasGold then", "CLAUDE-BUD: gold pad gated")
must_contain(_cbud_pp, "local total = cash * (n - golden) + math.floor(cash * goldMult) * golden", "CLAUDE-BUD: golden pumps pay IncomeMult x")
must_contain(_cbud_pp, "math.clamp(tonumber(if typeof(goldDef) == \"table\" then goldDef.IncomeMult else nil) or 1, 1, 3)", "CLAUDE-BUD: income mult clamped 1..3")

must_contain(_cbud_ps, "local function keepBaseLive(player: Player): boolean", "CLAUDE-BUD: keepBaseLive takes the player")
must_contain(_cbud_ps, "MonetizationConfig.SkuLiveFor(player.UserId, PrestigeConfig.KeepBase.ProductKey)", "CLAUDE-BUD: keep-base sale gated (saved token stays usable)")

must_contain(_cbud_sc, "if not MonetizationConfig.SkuLiveFor(Players.LocalPlayer.UserId, key) then", "CLAUDE-BUD: Shop rows gated")
must_contain(_cbud_sc, "or not MonetizationConfig.SkuLiveFor(player.UserId, productKey) then", "CLAUDE-BUD: dev product prompt gated on the client")
must_contain(_cbud_sc, "or not MonetizationConfig.SkuLiveFor(player.UserId, passKey) then", "CLAUDE-BUD: game pass prompt gated on the client")

# Supersedes the retired body pins (K1 F7/F8/F9 copy, M F8, P F7, S prompt, F9 pad): the Ids are live now; the gates hold.
must_contain(_cbud_mc, 'Description = "Gold pumpjacks: +50% pump income",', "CLAUDE-BUD: F9 golden pump Shop copy says the income boost")
must_contain(_cbud_ps, "KeepBaseLive = keepBaseLive(player),", "CLAUDE-BUD: F7 KeepBaseLive pushed per player (SOON for anyone the rollout skips)")
must_contain(_cbud_ps, "return PrestigeConfig.KeepBase.Enabled == true\n\t\tand id ~= nil\n\t\tand id ~= 0\n", "CLAUDE-BUD: F7 KeepBaseLive still needs Enabled and a non-zero Id")
must_contain(_cbud_sc, 'if (tonumber(def.Id) or 0) == 0 or not MonetizationConfig.SkuLiveFor(player.UserId, passKey) then\n\t\ttoast("Coming soon", "Info")\n\t\treturn\n\tend\n\t-- Log intent on server; NEVER treat client confirmation as a grant', "CLAUDE-BUD: promptGamePass stops before any intent or Roblox prompt")
must_contain(_cbud_sc, 'if (tonumber(def.Id) or 0) == 0 or not MonetizationConfig.SkuLiveFor(player.UserId, productKey) then\n\t\ttoast("Coming soon", "Info")', "CLAUDE-BUD: promptDevProduct stops before any intent or Roblox prompt")
# Receipts: idempotent (saved PurchaseId + in-flight lock) and never rollout-gated, so a paid receipt is always granted.
must_contain(_cbud_ms, "if hasProcessed(profile, receiptId) then", "CLAUDE-BUD: a receipt already granted is never granted twice")
must_contain(_cbud_ms, "if receiptsInFlight[receiptId] then", "CLAUDE-BUD: one ProcessReceipt run per PurchaseId at a time")
_cbud_src = read(_cbud_ms) or ""
_cbud_i = _cbud_src.find("local function processReceipt(")
_cbud_j = _cbud_src.find("\nend\n", _cbud_i)
(ok if _cbud_i >= 0 and "SkuLiveFor" not in _cbud_src[_cbud_i:_cbud_j] else bad)("CLAUDE-BUD: processReceipt is not rollout-gated (paid receipts always grant)")
# The world pads never sell a gated SKU, so the cyan pad keeps selling Speed Boost for everyone.
must_contain("src/ServerScriptService/Server/Services/PremiumPadService.luau", "MonetizationConfig.SkuLiveFor(player.UserId, key)", "CLAUDE-BUD: premium pads gated per player")
