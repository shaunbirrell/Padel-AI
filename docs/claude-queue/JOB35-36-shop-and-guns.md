You are a WAR EMPIRE coder on branch claude/desktop-bud (this repo). Shaun approved everything below.

ORDER RULE (strict): start only AFTER JOBS 30-34 are finished and pushed. Do JOB 35, then JOB 36. One job at a time: finish, test, push claude/desktop-bud, then start the next. If blocked, write it in LATEST-HANDOFF and stop. Never skip.

GIT/RULES: git fetch; rebase claude/desktop-bud on the latest origin/phase-7-polish (v126 or newer). Push only claude/desktop-bud. Never bump WE_Build, publish, or push phase-7-polish/main. Never touch WE_Building*. PreferMesh OFF. Admins stay off leaderboards. No admin/owner combat immunity. Every new pass/product is Id = 0: hidden, the stand shows SOON, never prompted, until Shaun pastes the Id. Ship owner-first behind boolean flags (OwnerFirst = true + an Enabled kill switch; codebot_v101 bans "owner" strings). Prices live in MonetizationConfig only. Phone first (44 px taps). Paid speed stays clean: nothing but MonetizationService writes WalkSpeed (codebot_v126). Checks: tools/checks/claude_bud_jobNN.py + LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py = 0 FAIL, rojo build ok.

== JOB 35: PREMIUM GUNS ARMORY ==
1. GamePasses (Id 0): PG_Sovereign 99, PG_Quake 249, PG_Longshot 299, PG_Havoc 349, PG_Thunderhead 399, PG_Tempest 499, PG_ArmoryPass 1299 (all six; BundlePassKeys, hidden if all six are owned). Each has WeaponIds. Owning one sets profile.Weapons[id] = true (join check + OnPassOwned, like PV_*). Cash purchase refuses Premium guns; equip refuses unowned ones.
2. WeaponConfig (Premium = true, CostCash 0). Models are all owned by the place owner and load live (checked):
- Sovereign gold pistol: 720567240 (one MeshPart). Dmg 30, 2-shot burst, mag 12.
- Quake grenade launcher: 4842201032 (Roblox kit Tool). 6-round drum, lobbed Projectile splash 11.
- Longshot sniper: 14498314181 (Model of 6 MeshParts, incl. Scope). Dmg 110, headshot x1.5, range 600, REAL SCOPE.
- Havoc rotary: 590594953 (Model: gunmodel + separate barrel model to spin). 0.6 s spin-up, 20 rps, dmg 9, mag 150.
- Thunderhead rocket launcher: 12458308179 (Model: launcher + rocket MeshParts). 2-rocket salvo, 170 dmg, splash 12.
- Tempest railgun: 4842190633 (Roblox kit Tool). 0.8 s charge, 140 dmg, pierces 3.
Three of the models have no Tool: extend WeaponAssetLoader to accept a plain Model or MeshPart (add an invisible Handle + a grip offset per weapon). Scripts stay stripped; keep the Part-kit fallback.
3. New optional WeaponDef fields (nil = unchanged for every existing gun), all server-authoritative: Burst{Count,Gap}, SpinUp, ChargeSeconds, Pierce, HeadshotMult. Keep the PvP rule + PlayerMaxDps.
4. Scope (client only): hold RMB/L2 or tap a phone SCOPE button. FOV 70 -> 20 -> 12, black vignette + reticle overlay, sensitivity x FOV/70, sway while moving, recoil x0.5. Exits on reload/death/seat/switch.
5. Armory in every base, next to the Supply Depot, built from Parts: 7 glass cases (glass 0.6 transparency, gold trim, 1 light, no shadows), each holding the gun template slowly spinning on the client. Reuse PurchaseStands: prompt "Buy · R$ X"; once owned the glass fades and it becomes Equip. Show at most the 3 nearest boards. Shop WEAPONS tab gets gold rows too.

== JOB 36: SHOP OVERHAUL ==
1. Order: FREE rows -> War Chest -> 2x Cash (BEST VALUE) -> VIP -> Auto Collect -> Starter Pack -> BP Premium -> Bigger Army -> Super Soldiers -> Double HP -> Speed Boost -> Armory guns -> premium vehicles -> cash packs -> consumables. Mark passes PERMANENT.
2. Cash packs scale: grant = max(floor, minutes x the player's current passive $/min), computed in ProcessReceipt without yielding. S 49 = max($10k, 5 min), M 149 = max($50k, 20 min), L 399 = max($200k, 60 min), Mega 799 = max($2M, 180 min). Rows and offers show the live amount. Keep the Ids.
3. Duplicates: Speed Pass HideFromShop; the Speed stand + death offer sell the Speed Boost; owners keep x1.4. Army Expansion HideFromShop; the ArmyWiped offer sells Bigger Army; owners keep +10 (it still stacks).
4. VIP = premium pass, RobuxPrice 349: +50% cash (was 25%), daily VIP supply crate (~10 min of income, the VipSupplyAt field), lounge, [VIP] tag, gold name. All current VIP owners get it.
5. New passes (Id 0): WarChest 799 (counts as owning 2x Cash + Auto Collect + VIP + Bigger Army; hidden if all four are owned), SuperSoldiers 349 (+25% army damage and soldier HP), DoubleHP 199 (player MaxHealth x2).
6. docs/SHOP.md: every item with key, name, price, Id (0 = pending), what it grants, and where it is sold.

HANDOFF: update LATEST-HANDOFF with flags, the Ids Shaun must paste, and 5 phone tests per job.
