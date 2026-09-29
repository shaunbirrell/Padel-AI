<!-- Q2-START -->
# WHERE I STOPPED — 2026-09-29 (Code Bot shipped v110) — JOB 20 LIVE
**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v110) before new work.** Do not redo JOB 14, JOB 15, BOARDS, Flank, JOB 17, JOB 18, JOB 19, or JOB 20.
Keep v102 Codes / CashBoost, v104 Engagement (all) + Discord invite + exploit guards, v105 BUDSQUAD, v106 GameFeel all + RemoteGate observe, v107 BOARDS, v108 Flank, v109 night/WorldFill2/stands.
Jobs: [x] 12 launch readiness · [x] 13 bring players back · [x] 14 game-feel polish · [x] 15 anti-exploit sweep · [x] BOARDS · [x] army Flank · [x] 17 night lighting · [x] 18 world fill 2 · [x] 19 purchase stands · [x] 20 real base guards · [ ] 21 more plots

- PreferMesh stays OFF. WE_Building* untouched. Never bump WE_Build / publish (Code Bot only).
- Speed Pass display price is 99 R$ (owner repriced in Creator Hub).

## QUEUE 4 (claude-bud, rebased on v110: J20 shipped there)
Jobs: [x] 17 · [x] 18 · [x] 19 · [x] 20 real base guards · [ ] 21 more plots
- J20 SHIPPED (live for all, GuardConfig + Modules/BaseGuards): base guards hold posts, fight intruders
  (players + enemy army) inside the plot within a 60-stud leash, return after 8 s, respawn after 45 s;
  Defenses research Guard Armor / Guard Roster / Tower Guards; owner-credited kills; anti-farm; damage caps.
  Next: JOB 21 more plots (expand to 10 base plots). Phone tests for v110 below in the v110 section.
<!-- Q2-END -->

# v110 — 2026-09-29 ~16:55 Dublin (Code Bot, branch phase-7-polish, WE_Build 110) — JOB 20 REAL BASE GUARDS LIVE FOR ALL

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v110) before JOB 21. Do not redo J14–J20, Flank, BOARDS.**
Merged `origin/claude/desktop-bud` tip `f5387ae` (JOB 20 real base guards) into phase-7-polish (fast-forward from eac6cf9 v109 handoff).

- **JOB 20 Base guards (live for everyone, `GuardConfig` + `Modules/BaseGuards`):** GuardConfig Enabled=true (no owner gate). GateDefenseService 5 Hz loop runs ThinkGuard / ThinkTowers. Intruders (not owner / clan / friends) and enemy army units inside the plot are fought with 60-stud leash, return after 8 s, 45 s respawn, LOS + hit chance, per-target DPS cap, ≤6 shooters/base. Defenses research: Guard Armor / Guard Roster / Tower Guards (paid via ResearchService.Purchase, rebirth-scaled). Kills credit the owner via server creator tag (cash, XP, MOST KILLS, feed "<owner>'s Tower Guard"); max 3 per victim per 10 min; none in private servers; guard/unit kills give smaller rewards.
- Kept: v104 Engagement all + guards; Discord invite; v105 BUDSQUAD; v106 GameFeel all + RemoteGate observe; v107 BOARDS; v108 Flank; v109 night + WorldFill 2 + purchase stands; Speed Pass 99 R$.
- Pins: `tools/checks/codebot_v110.py` + `claude_bud_guards.py` (JOB 20 pins). BuyPathStatic PASS=5943 FAIL=0; rojo ok. PreferMesh OFF. WE_Building* untouched.

**Phone tests (second account / alt):** alt walks into your base → guards turn, chase (never out of plot / past 60 studs), shoot; alt dies → you get the kill (toast, board, feed); you / friend / clan-mate never shot; your own army safe, alt's army shot; alt waits outside 8 s → guards walk back; buy Watchtowers, hire tower guard at corner prompt (owner-only), it shoots alt outside walls (not inside); kill a guard as alt → small reward; new/low-level alt not deleted instantly (damage cap).

**Published:** Open Cloud `versionNumber=PENDING` (commit PENDING). Migrate to Latest Update for real base guards.

# v109 — 2026-09-29 ~16:35 Dublin (Code Bot, branch phase-7-polish, WE_Build 109) — JOBS 17–19 LIVE FOR ALL

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v109) before JOB 20. Do not redo J17/J18/J19, Flank, BOARDS, JOB 14, or JOB 15.**
Merged `origin/claude/desktop-bud` tip `7667291` (JOB 17 night + JOB 18 WorldFill 2 + JOB 19 purchase stands) into phase-7-polish (fast-forward from ad1c5f7 Speed Pass 99 R$).

- **JOB 17 Night (live for everyone, `LightingConfig`):** moonlit night (midnight ambient ~90,95,120, Brightness floor 2.0, blue colour correction), ~50 warm night lights (town roads, plaza, Town Square, base gates/hangars, plaza flag), Neon glow only at night. Low quality halves lights.
- **JOB 18 WorldFill 2 (live for everyone, `WorldFillConfig.Fill2`):** town identities (market/port/garrison), rooftop clutter, themed patch in every empty 300-stud cell, highway power lines, dirt tracks, dune belt. Cap 7,000 Full / 2,600 Low; Tier 2 clutter hidden beyond 180 on low quality.
- **JOB 19 Purchase stands (live for everyone):** Supply Depot row of Robux purchase stands (hex steel plinth, gold trim, hologram, info board with config price, pulsing ring) + Golden Pump stand; prompt-only buying; OWNED green check. Same PromptPremiumPad path.
- Kept: v104 Engagement all + guards; Discord invite; v105 BUDSQUAD; v106 GameFeel all + RemoteGate observe; v107 BOARDS; v108 Flank; Speed Pass 99 R$.
- Pins: `tools/checks/codebot_v109.py` + `claude_bud_night.py` / `claude_bud_worldfill2.py` / `claude_bud_stands.py`. BuyPathStatic PASS=5890 FAIL=0; rojo ok. PreferMesh OFF. WE_Building* untouched.

**Phone tests:** wait for night (~8 min or /time): roads/bases/players readable, streetlights on, windows lit, runway edge glow; Graphics 1–3 fewer lights. Bomber flyover 80+ studs: no big empty squares, dunes on horizon; drive highways/town/plaza (nothing blocks); stands: walk-on does nothing, hold "Buy - R$ …" opens Roblox dialog (cancel); owned = green ✓ OWNED.

**Published:** Open Cloud `versionNumber=107` (commit cd9d421). Migrate to Latest Update for night lights, WorldFill 2, and purchase stands.

# v108 — 2026-09-29 ~15:55 Dublin (Code Bot, branch phase-7-polish, WE_Build 108) — ARMY FLANK FORMATION (place version 106)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v108) before new work. Do not redo Flank, BOARDS, JOB 14, or JOB 15.**
Merged `origin/claude/desktop-bud` tip `66cfdd7` (army Flank formation) into phase-7-polish.

- **Army Flank (live for everyone via Follow2.Tidy):** the tidy wedge put rows behind the owner (at / behind the phone camera), so the camera guard hid them while walking. Formation = "Flank" — a file each side of the owner, last row ~8 studs back, rows on their own side lines. "Wedge" restores the old formation.
- Kept: v104 Engagement all + guards; Discord invite; v105 BUDSQUAD; v106 GameFeel all + RemoteGate observe; v107 BOARDS.
- Pins: `tools/checks/codebot_v108.py` + `claude_bud_army.py` Flank pins. PreferMesh OFF. WE_Building* untouched.

**Published:** Open Cloud `versionNumber=106`. Migrate to Latest Update for army Flank.

# v107 — 2026-09-29 ~15:35 Dublin (Code Bot, branch phase-7-polish, WE_Build 107) — BOARDS LIVE FOR ALL (place version 105)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v107) before new work. Do not redo BOARDS, JOB 14, or JOB 15.**
Merged `origin/claude/desktop-bud` tip `0bd3c79` (Town Centre notice boards) into phase-7-polish, keeping v104
(Engagement live-all + Discord invite + exploit guards), v105 (BUDSQUAD), and v106 (GameFeel all + RemoteGate observe).

- **BOARDS (live for everyone, `LeaderboardConfig`):** 6 Town Centre notice boards on the square's south edge —
  MOST KILLS (all-time / this week), RICHEST, TOP SUPPORTERS (Robux, Settings opt-out), PLAZA CONQUEROR (weekly),
  REBIRTH KINGS, TOP ARMY; weekly #1 crown; night spotlights; gold "You:" line near a board.
  OrderedDataStore per stat (`WE_LB2_`), ISO-week weekly stores, write throttle 90 s (leave respects it too),
  shared 75 s refresh, pcall + back-off + request budget. Validated PvP kills (creator tag, no self/clan, 3/pair/10 min).
  Confirmed-only Robux on Supporters. Admin/playtest accounts stay off the boards (v104).
- **v104 exploit guards kept across the merge:** friends daily cap, comeback once-per-absence, invite friendship +
  new-player checks, admin board exclusion.
- Pins: `tools/checks/codebot_v107.py` + `claude_bud_boards.py`. BuyPathStatic PASS=5702 FAIL=0; rojo ok.
  PreferMesh OFF. WE_Building* untouched.

**Published:** Open Cloud `versionNumber=105`. Migrate to Latest Update for the Town Centre boards.


# v106 — 2026-09-29 15:05 Dublin (Code Bot, branch phase-7-polish, WE_Build 106) — JOB 14 GAME-FEEL LIVE FOR ALL + JOB 15 REMOTEGATE OBSERVE

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v106) before new work. Do not redo JOB 14 or JOB 15.**
Merged `origin/claude/desktop-bud` tip `751a86b` (JOB 14 + JOB 15 after rebase on v103) into phase-7-polish, keeping v104
(JOB 13 live-all + Discord invite + exploit guards) and v105 (BUDSQUAD).

- **JOB 14 GameFeel (live for everyone):** kill feed (2 HUD top-stack lines, PvP + vehicle kills, DisplayNames);
  vehicle damage numbers (attacker + red victim numbers, aggregated); one raid report per attack
  ("YOU WERE RAIDED -$N" / "BASE DEFENDED"); sound pass (volume bands; premium gun/missile, markers, AIRSTRIKE tap,
  event banner no longer silent). `GameFeelConfig.Rollout` = "all" for KillFeed / VehicleNumbers / RaidReport / SoundPass.
- **JOB 15 RemoteGate (observe, safe):** every client→server remote gated (rate ceiling + argument schema + sink on
  push-only). `SecurityConfig.RemoteGate.Rollout` = "observe", Others = "observe" — logs "would reject", never drops/kicks.
  RedeemCode schema kept (`string:40`) for the v102 Codes RemoteFunction. Flip Rollout to "all" after quiet observe logs.
- Kept: v104 Engagement all + invite/friends/comeback/board guards; Discord invite plain text; v105 BUDSQUAD $25k.
- Pins: `tools/checks/claude_bud_q3.py` + `tools/checks/codebot_v106.py` (+ gamefeel_test / remotegate_test / remote_audit / sound_audit).
  BuyPathStatic PASS=5651 FAIL=0; rojo build ok. PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **104** (commit 226aa43).
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v106 appears.

# v105 — 2026-09-29 14:51 Dublin (Code Bot, branch phase-7-polish, WE_Build 105) — BUDSQUAD LIVE

- Added active, non-expiring `BUDSQUAD` redeem code: **Bud Studios Discord**, `$25,000`, once per player via saved `RedeemedCodes`.
- Commit `b7e3e19`; Open Cloud place version **103**. BuyPathStatic `PASS=5595 FAIL=0`; rojo build ok. PreferMesh OFF; `WE_Building*` untouched.

# v104 — 2026-09-29 ~14:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 104) — JOB 13 ENGAGEMENT LIVE FOR ALL

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v104, commit 865a1e3) before JOB 14/15.** JOB 13 is now live for
every player (`EngagementConfig.Rollout` = "all" for Events / Leaderboards / Invite / Friends / Comeback). Do not redo JOB 13,
do not flip any of it back to "owner", and keep the v104 guards below (JOB 15 anti-exploit sweep should build on them).

- **Invite:** pays only when the joiner is a real Roblox friend of the inviter (`IsFriendsWithAsync`; an error pays nothing),
  a brand-new account here (`InviteNewPlayerSeconds` = 15 min since FirstJoinUnix), on a saved profile (`DataService.IsLoaded`);
  `ReferredBy` is saved right away; inviter still capped 5/day (in-server and queued).
- **Friends bonus:** max 3 friends per tick and **$30,000/day** (`FriendsDailyCap`; profile.FriendsDay / FriendsPaid, saved).
- **Leaderboards:** one write per player per 60 s (kept across leave/rejoin), unchanged scores skipped, sorted-store budget
  respected; admin / playtest accounts (50M cash floor) are never written and filtered out of the top 10.
- **Comeback:** once per absence (`profile.ComebackPaidFor`), saved profile only, saved right away.
- Engagement reward reasons (`invite_welcome`, `invite_reward`, `friends_bonus`, `comeback`) are multiplier-exempt, so the caps are exact.
- **Discord:** `SocialConfig.DiscordInvite = "https://discord.gg/tkjA2DFBmZ"`. The Codes panel shows `DiscordInviteText`
  ("Discord: discord.gg/tkjA2DFBmZ") as plain TextLabel text under the Discord line, only when PolicyService
  `AllowedExternalLinkReferences` lists Discord. Never make it clickable; the clickable link belongs in Creator Hub → Social Links.
- Pins: `tools/checks/codebot_v104.py` + `tools/engagement_gate_test.py` (runs the real EngagementService in the Luau CLI,
  52 checks). v103 owner-only pins moved (claude_bud_q3 / codebot_v101 / codebot_v102 / codebot_v103).
  BuyPathStatic PASS=5591 FAIL=0 (with LUAU set), rojo build ok. PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **102** (commit 865a1e3).
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v104 appears.

# v103 — 2026-09-29 ~14:35 Dublin (Code Bot, branch phase-7-polish, WE_Build 103) — JOB 13 ENGAGEMENT (owner-only)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v103) before JOB 14/15.** Code Bot cherry-picked JOB 13 (`36779ce`)
onto v102. Keep Codes / CashBoost; Engagement Double Cash events stack with the timed boost. Do not redo JOB 13.

- **Engagement (owner-only, `EngagementConfig.Rollout` per feature):** weekly events (Plaza War Week / Airdrop Frenzy / Double Cash Weekend)
  with HUD banner + countdown; OrderedDataStore leaderboards (richest / plaza captures / rebirths) on a Town Square board;
  invite ($10k/friend, 5/day; friend gets $2.5k once); friends-in-server $500/min (max 3); comeback after 3+ days $25k.
  Not in LaunchSafe yet — phone-test as owner, then flip Rollout per feature.
- **Cash stack:** v102 `CashBoostMult` + JOB 13 `EngagementService.CashMult` both apply on non-exempt Cash.
- Pins: `tools/checks/claude_bud_q3.py` + `tools/checks/codebot_v103.py`. BuyPathStatic PASS=5554 FAIL=0, rojo build ok. PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **101** (commit 2619db1). BuyPathStatic PASS=5554 FAIL=0.
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v103 appears.


# v102 — 2026-09-29 ~15:00 Dublin (Code Bot, branch phase-7-polish, WE_Build 102) — REDEEM CODES (live for all)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v102).** The rail now has 6 tiles (Shop · Rebirth · Army · Garage ·
Missions · **Codes**); the BuyPathStatic "5 rail tiles" pin was moved to "5 + Codes". Any timed 2x Cash you add must reuse
`profile.CashBoost` / `EconomyService.CashBoostMult` (the one timed boost), not a second system.

- **Codes (live for everyone, no owner gate):** "Codes" rail tile (gift icon) → Codes panel: text box, REDEEM, result line,
  "2x CASH BOOST ACTIVE mm:ss left" while a boost runs, and "Join Bud Studios Discord for free codes!"
  (`SocialConfig.DiscordText`; `SocialConfig.DiscordInvite = ""` is a placeholder and is never shown, so no URL in-game).
  Settings → REDEEM CODE → "ENTER A CODE" opens the same panel.
- **Server:** `CodesService` answers the `RedeemCode` RemoteFunction with Success / AlreadyUsed / Invalid / Expired
  (+ RateLimited / NotReady): 5 tries per player per minute, case and spaces ignored, letters/digits/_ only, the code is marked
  in `profile.RedeemedCodes` before anything is paid, then the profile is saved. Code Cash is multiplier-exempt (reason
  `code`), so BUDSTUDIOS pays exactly $50,000; its 30 min 2x boost multiplies every non-exempt Cash earning (income,
  collection, kills…) and stacks with VIP / 2x Cash like the other multipliers. The minutes are real time from the redeem
  (they keep running while the player is offline); a second boost code adds its minutes on top (max 24 h ahead).
- **CodesConfig moved to the server** (`src/ServerScriptService/Server/Configs/CodesConfig.luau`) so exploiters cannot read the
  list. The pre-launch samples WARFOUNDING / BUILDCONQUER are kept but `Active = false` (players see "expired").
- Pins: `tools/checks/codebot_v102.py` + `tools/codes_gate_test.py` (runs the real CodesService in the Luau CLI, 37 checks).
  PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **100** (commit 4b658d5). BuyPathStatic PASS=5525 FAIL=0 (parse gate on), rojo build ok.
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v102 appears.

## How to add a new code (owner)
1. Open `src/ServerScriptService/Server/Configs/CodesConfig.luau` (the steps are also written at the top of that file).
2. Copy the BUDSTUDIOS block and change the key, e.g.:
   ```lua
   	RAID1000 = {
   		Active = true,
   		Expires = "2026-10-31", -- end of that day UTC; or "2026-10-31T18:00:00Z"; or nil = never
   		DisplayName = "1000 Raids",
   		Rewards = { Cash = 25000, Gold = 5, CashBoostMinutes = 15 }, -- any mix of Cash / Gold / CashBoostMinutes
   	},
   ```
   The key is what players type (any case; spaces ignored; letters, digits and _ only, at most 32 characters).
3. To switch a code off early: `Active = false`. Players who already redeemed it keep their reward.
4. Ask Code Bot to ship (or: `python3 tools/BuyPathStatic.py` must end FAIL=0, `rojo build -o dist/WarEmpire-PERF.rbxlx`,
   `tools/publish-opencloud.sh`), then "Migrate to Latest Update". Codes only change with a publish.

**Phone test for Shaun (any account, the second account too):**
- Tap **Codes** on the left rail (on the smallest phones it sits at the top of a 2nd column next to Shop). The panel opens
  centred; the text box, REDEEM and the ✕ are easy to hit; the Discord line shows with no link.
- Type `budstudios` → green "Redeemed! You got $50,000 + 30 min 2x Cash." Cash jumps by exactly $50,000, the panel shows
  "2x CASH BOOST ACTIVE 29:59 left", and income / collections pay double while it runs.
- REDEEM again (try `BudStudios`) → orange "You've already redeemed this code." Leave the game, rejoin → still already used;
  the boost timer keeps counting down.
- Type `hello` → red "That code doesn't exist." Type `WARFOUNDING` → orange "This code has expired."
- Tap REDEEM 6 times fast with junk → "Too many tries. Wait a minute and try again."
- Settings (gear) → REDEEM CODE → ENTER A CODE opens the same panel. Tapping outside the panel closes it.

---


# v101 — 2026-09-29 ~14:30 Dublin (Code Bot, branch phase-7-polish, WE_Build 101) — ROLLOUTS ARE NOW "all"

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v101) BEFORE any new work.** Every owner-only rollout is now
`"all"` (owner: "enable everything for ALL players now"). v101 contains your JOB 12 (`fe22e41`, cherry-picked; on rebase git
drops it as already applied — if LATEST-HANDOFF.md conflicts keep phase-7-polish's). `MonetizationConfig.LaunchAll` stays
**false** on purpose: each gate's own Rollout is "all", and the owner keeps his UserId-only test shortcuts. Do not set any
gate back to "owner"; new features may still ship owner-only first under their own new key.

- **Live for everyone:** all 13 Robux SKUs (Speed Pass, Keep-Base Rebirth, Golden Pumpjacks, 6 premium vehicles + their guns,
  Bigger Army, Extra Garage Slot, Army Refill, Plaza Airstrike), VIP perks, purchase prompts at moments, retention rows + Premium
  daily perk, airdrop, daily auto-claim, plaza bounty, army upgrades, guards fight back, NpcUnstick, bag LOS, first-minutes
  tutorial, QualityGovernor, juice, balance curve + income XP, army Escort / Army / Fix / ThreatStandingFor / Follow2 / Tidy,
  Bridge Layer wading. WorldFill was already world-wide.
- **Still off:** StreamingEnabled, OpsConfig.Enabled, RebirthConfig.ZonesLive / WeaponsLive, AircraftWeaponConfig.WeaponsLive,
  XP backfill, PreferMesh, VisualAssetConfig.BodyRollout (11 hulls need the owner's WE_CHECK2 run).
- **Id 0 hidden:** PV_Bastion / PV_MotorPool (and every Id 0 product) have no Shop row or prompt for anyone.
- Pins: `tools/checks/codebot_v101.py` (+ `tools/v101_gate_test.py`, Luau-executed gates for a non-owner account). Old
  "owner-only first" pins retired with a `# v101 ... superseded` prefix. PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **99** (commit 56a1c5c). BuyPathStatic PASS=5471 FAIL=0 (parse gate on), rojo build ok.
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v101 appears.

---

# v100 — 2026-09-29 ~14:00 Dublin (Code Bot, branch phase-7-polish, WE_Build 100)

**Claude: do not redo / undo queue 2 (JOB 6–11) or PREMIUM.** Code Bot merged `origin/claude/desktop-bud` tip `3cf54f2` (ce0b5cc..3cf54f2; based on v98 `08bcdf4`) onto phase-7-polish (v99 `c32bd9a`) and published. v99 Creator Hub Ids + army/rifle fixes kept.

- **JOB 9** (owner-only cleanup): old WIP finished or removed (real-world PT-boat / failed truck picks out; naval rows back on Part kits; unfinished handoff/wip patches retired; March lane C gone).
- **JOB 10** (owner-only): `BalanceConfig` curve — pads pay back in minutes, income XP does not feed battle pass; first rebirth ~34 min (`tools/progression_sim.py`).
- **JOB 11** (owner-only): juice — purchase burst, rebirth celebration banner, AIRSTRIKE button in HUD top stack (touch-safe sizes).
- **PREMIUM** (owner-only): 6 Robux-only vehicles clearly overpowered (`VehicleConfig.Premium`); server-validated guns + homing missiles (`PremiumWeaponService` / `PremiumWeaponsClient`); mobile FIRE/MISSILE; gold trail + ROBUX badge.
- Pins: `tools/checks/claude_bud_q2.py`, `claude_bud_premium.py`, `codebot_v99.py` (army/rifle/Ids), `codebot_v100.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Creator Hub Ids kept from v99:** PV_Skylance 2001602422 · PV_Stormwing 2001722392 · PV_Leviathan 2001398410 · PV_Tidebreaker 1999263465 · PV_Warlord 2001320428 · PV_Razorfang 2002484380 · BiggerArmy 2001734404 · ExtraGarageSlot 1999359549 · SoldierRefill 3715442523 · PlazaAirstrike 3715442542.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so JOB 9–11 + PREMIUM appear.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Balance:** pads feel worth buying (minutes payback); first rebirth around ~30–40 min; income does not power the battle pass.
- **Juice:** buy a pad → short burst; rebirth → celebration banner in the top stack (not over controls); AIRSTRIKE button in top stack, big enough for a thumb.
- **PREMIUM vehicles:** spawn Warlord / Razorfang next to cash tank / buggy — faster, tougher, snappier. While driving: FIRE + MISSILE bottom-right (not on jump/thumbstick); get out → gone. Hold FIRE hits NPCs/alt vehicles; clan/own vehicles take no damage. Gold lock ~250 studs → MISSILE curves; hard turn can dodge; 5 s cooldown. Skylance/Stormwing air; Leviathan/Tidebreaker water. Second account sees gold trail + ROBUX badge, cannot spawn. Spawn-protect / novice shield ignored damage.
- **Regression:** army gate-hold + rifle re-tap holster still work (v99). Garage gold ROBUX rows + Hub Ids still prompt.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v99 — 2026-09-29 ~13:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 99)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v99) BEFORE you touch any army or weapon code**
(`ArmyFollow.luau`, `SquadOrdersService.luau`, `ArmyConfig.luau` Follow2, `CombatController.luau`, `CameraFx.luau`,
`WeaponVisuals.luau`, `HudConfig.luau` Hotbar). v99 is **not** a merge of your JOB 9–11 (`22032ae..2028147` are still
only on Bud, left for the normal watch). Expect small conflicts in `tools/checks/claude_bud_money.py` and
`claude_bud_q2.py`: v99 changed your "Id 0 until created" pins to the real Ids — keep the v99 Ids.

**Creator Hub Ids now wired (owner created them; `tools/wire-monetization-ids.py`; prices unchanged; RolloutKeys unchanged = owner-only):**
PV_Skylance 2001602422 (899) · PV_Stormwing 2001722392 (999) · PV_Leviathan 2001398410 (1199) · PV_Tidebreaker 1999263465 (299) ·
PV_Warlord 2001320428 (799) · PV_Razorfang 2002484380 (199) · BiggerArmy 2001734404 (249) · ExtraGarageSlot 1999359549 (199) ·
DevProducts SoldierRefill 3715442523 (49) · PlazaAirstrike 3715442542 (79). `docs/LIVE_PLACE.md` table updated.
ProcessReceipt checked (no change needed): unknown Id → NotProcessedYet; ProcessedReceipts makes it idempotent; the grant banks
`SoldierRefills` / `AirstrikeCharges` (1 per receipt), marks processed, saves, then PurchaseGranted.

**Army (Bug 1: blobs / overlaps / snap-backs / stuck, owner-only via Follow2):**
- Two controllers on one Humanoid: the escort fight and ArmyFollow both drove MoveTo; stale follow state after a fight/HOLD/
  death made the stuck timer fire at once → teleport back. Now `ArmyFollow.Release` on every hand-off and a fresh state on re-acquire.
- Two yaw owners: AutoRotate vs NPCFaceGyro. Now AutoRotate off while following, one rate-limited facing (TurnRateDeg 300).
- Shared fallback point around buildings → every unit now gets its own point toward its own slot; paths kept 12 studs / 2 s,
  no walking back to passed waypoints.
- Formation turns rate-limited (no 180° swings); seats kept on deaths (compaction only after 4 s); regroup far = 100 studs for 3 s,
  staged stuck (repath 3 s → side step + jump 6 s → reposition 10 s, behind you, out of view); vehicle speed no longer counts
  as a jump; smooth catch-up speed; collision group `ArmyNPCs` set at spawn for every order.

**Rifle (Bug 2: can't put it away):** there are no Roblox Tools; the tap on the selected hotbar slot now holsters on touch
(`HudConfig.Hotbar.TouchTapHolsters = true`), getting shot no longer re-draws it for 4 s after a holster, death holsters,
recoil is zeroed and the reload track stopped when holstered.

- Pins: `tools/checks/codebot_v99.py`. BuyPathStatic PASS=5322 FAIL=0. PreferMesh stays OFF. WE_Building* untouched.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** so v99 appears.

**Phone tests for Shaun (owner account):** army with 3 and with 15+: walk, sprint, sharp turns, run in circles, round buildings,
into and out of the base, run far away, stand still (no blob, no overlap, no snap-back). Rifle: equip, re-tap to put away,
swap to another slot and back, respawn, die while holding. Buy each pass + both dev products once (refill fills the army;
airstrike charge shows / fires at the plaza); a second account must not see the owner-only items.

---

# v98 — 2026-09-29 ~13:25 Dublin (Code Bot, branch phase-7-polish, WE_Build 98)

**Claude: do not redo / undo JOB 6–8.** Code Bot merged `origin/claude/desktop-bud` tip `e791323` (fc85a35..e791323) onto phase-7-polish and published.

- **JOB 6** (owner-only): Extra Garage Slot pass (+1 parked vehicle, Id 0 TODO) + gold ROBUX Shop rows. Spawn A then B parks A with health kept; sit in parked to drive again.
- **JOB 7** (owner-only): welcome toast on first join + first-ATTACK hint (Army popover outlines ATTACK until first ATTACK) on top of the existing tutorial.
- **JOB 8** (owner-only): QualityGovernor low-quality tier for phones / low FPS (far decoration clusters hide, local shadows off, cheaper FX) + streaming audit (StreamingEnabled stays OFF).
- Pins: `tools/checks/claude_bud_q2.py`, `codebot_v98.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Creator Hub Id still owner TODO** for ExtraGarageSlot and other Id=0 items (paste with `tools/wire-monetization-ids.py`). Do not create products here.
- **Still open on Bud:** JOB 9–11 (old WIP, balance, juice). Claude may still work those — do not take them over.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so JOB 6–8 appear.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Extra Garage Slot:** spawn vehicle A, spawn different vehicle B — A parks with health kept; sit in parked to drive again. Gold ROBUX Shop row; Id still 0 so purchase may be coming-soon / owner auto-grant.
- **First five minutes (new profile or wiped):** welcome toast on first join; after tutorial, Army popover opens with ATTACK outlined until first ATTACK.
- **Quality:** on phone / low FPS, far decoration clusters hide, local shadows off, cheaper FX (owner-only QualityConfig).
- Migrate to Latest Update (or shut down old servers) before testing.

---


# v97 — 2026-09-29 ~09:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 97)

**Claude: do not redo / undo JOB 5b–5e.** Code Bot merged `origin/claude/desktop-bud` tip `7d5837c` (230fe5b..7d5837c) onto phase-7-polish and published.

- **JOB 5b** (owner-only): Bigger Army pass (+10 cap, Id 0 TODO); VIP chat tag `[VIP]` + VIP lounge north of Town (door + $5k/15 min gold pad); Extra Garage Slot stub hidden (not built).
- **JOB 5c** (owner-only): Instant Army Refill + Plaza Airstrike dev products (Ids 0 TODO; never-lethal airstrike).
- **JOB 5d** (owner-only): purchase prompts at the right moments + limited starter window.
- **JOB 5e**: Shop FREE retention rows (daily reward, airdrop track, group reward, unrewarded favorite) + Premium daily bonus; Creator Hub Id table for owner.
- Pins: `tools/checks/claude_bud_money.py`, `claude_bud_monetization.py`, `codebot_v97.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Creator Hub Id table still owner TODO** (paste with `tools/wire-monetization-ids.py`; items stay hidden while Id is 0). Do not create Extra Garage Slot yet.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so JOB 5b–5e appear.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Army (prior fix):** walk into your base with 8+ soldiers. Nobody crosses the gate; two neat blocks outside facing out. ATTACK: rows then ring (no stacking).
- **5a:** Garage shows 6 gold "ROBUX · R$" rows. Tap says "coming soon" until Id pasted; owner can already spawn via auto-grant.
- **5b:** chat shows `[VIP]` if you own VIP. VIP lounge just north of the Town: door lets you through; 2 s on gold pad pays $5,000 (once per 15 min).
- **5c/5d (after Ids exist):** AIRSTRIKE button near plaza; army-refill offer after squad wiped; 2x Cash / cash offer after rebirth; cash-pack offer when a vehicle is too expensive.
- **5e:** Shop Robux tab starts with FREE rows (Daily Reward CLAIM, Airdrop TRACK, Favorite). Roblox Premium: +$2,500 on first join of the day.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v96 — 2026-09-29 ~09:15 Dublin (Code Bot, branch phase-7-polish, WE_Build 96)

**Claude: do not redo / undo these.** Code Bot merged `origin/claude/desktop-bud` tip `a063154` (83a98b9..a063154) onto phase-7-polish and published.

- **Army gate-hold fix** (`ArmyConfig.Follow2.Tidy`, owner-only): after Shaun's v95 phone test — hold BEFORE the gate (no path through, no stuck/far teleport while outside); validated hold grid (raycast + overlap; bad cells skipped outward); per-seat ATTACK march rows / target ring (no stacking). Kill switch `Follow2.Tidy.Rollout = "off"`.
- **JOB 5a Robux-only vehicles** (owner-only via `MonetizationConfig.RolloutKeys`): six Premium clones — Skylance jet, Stormwing heli, Leviathan + Tidebreaker boats, Warlord tank, Razorfang buggy. Pass Ids still **0 / TODO owner** (Garage gold ROBUX rows; owner can spawn via auto-grant). Cash purchase refused (`RobuxOnly`). Free respawn for pass owners.
- Pins: `tools/checks/claude_bud_army.py`, `claude_bud_money.py`, `claude_bud_monetization.py`, `codebot_v96.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Still open on Bud:** JOB 5b+ monetisation (VIP chat tag + VIP area, Bigger Army pass, Extra Garage slot; then 5c/5d/5e + Creator Hub list). Claude tip was fresh at merge — may still be coding.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so the army fix + Robux vehicle Garage rows appear.

**Phone tests for Shaun:**
- Army fix (8+ soldiers, owner): walk into your base — nobody crosses the gate; two neat blocks outside facing out; none inside walls/props. Walk out: rejoin wedge. ATTACK in the open: rows in front; near an enemy: ring (no stacking into 2). Kill switch `ArmyConfig.Follow2.Tidy.Rollout = "off"`.
- Robux vehicles (owner): Garage shows gold **ROBUX** rows for the six Premium vehicles; spawn via owner auto-grant (pass Ids still 0). A second account should not see the rollout. Once Creator Hub Ids are pasted, Shop/Garage prompts work for pass buyers.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v95 — 2026-09-29 ~08:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 95)

**Claude: do not redo / undo these.** Code Bot merged `origin/claude/desktop-bud` tip `3355267` (aaa87f3..3355267) onto phase-7-polish and published.

- **JOB 2 army tidy** (`ArmyConfig.Follow2.Tidy`, owner-only): army holds in neat rows outside the main gate (never enters plot); fixed seats; no column-crossing on turn; 8 s no-teleport run-back after leaving base.
- **JOB 3 WorldFill** (`WorldFillConfig.Enabled`, everyone): connector roads P1/P2/P5/P6→plaza, 2 dock bridges, 6 army positions, 4 plaza posts, terrain rocks under `Workspace.WorldFill` (planned ~388 Full / ~198 Low).
- **JOB 4.1 airdrop** (`SupplyDropConfig.Airdrop`, owner-only): parachute drop every 10 min + marker; claim for cash.
- **JOB 4.2 daily streak** (`DailyRewardConfig.AutoClaim`, owner-only): auto-claim ~8 s after join + next-day toast.
- **JOB 4.3 plaza bounty** (`PlazaBountyConfig`, owner-only): timed $15k for retaking Central Plaza within 3 min.
- **JOB 4.4 Army Upgrades** (`ArmyUpgradeConfig`, owner-only): Barracks world prompt opens Research → Soldiers.
- Pins: `tools/checks/claude_bud_army.py`, `claude_bud_worldfill.py`, `claude_bud_features.py`, `codebot_v95.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Still open on Bud:** JOB 5 monetisation (Claude tip was fresh at merge — may still be coding).
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so WorldFill + owner-only JOB2/4 appear.

**Phone tests for Shaun:**
- Army fix (8+ soldiers): walk into your base; nobody crosses the gate, and they file into two neat blocks outside, facing out,
  none inside walls or props. Walk out: they rejoin the wedge. Press ATTACK in the open: they spread into rows in front of you;
  near an enemy they spread round it (no stacking into 2). (from Claude Bud handoff)
- JOB 4: wait ~1 min for first airdrop (marker + toast; stand by crate 2 s). ~8 s after join: login streak toast. Capture plaza with a second account, retake within 3 min: +$15,000. At Barracks tap "Army Upgrades" → Research Soldiers.
- Map fill: drive side gates P1/P2/P5/P6 — road to plaza; sandbag/watchtower positions; west dock bridge (boats under). Check mid-phone FPS. Server log `WorldFill: quality=full parts=N skipped=M`.
- Army (owner): walk/drive into base with 8+ soldiers — they stop outside gate in two blocks facing out. Walk out: wedge without teleport. Turn in place: no crossing. Kill switch `ArmyConfig.Follow2.Tidy.Rollout = "off"`.

---

# WHERE I STOPPED — 2026-09-29 (Claude on Bud, branch claude/desktop-bud, rebased on v95 phase-7-polish)

**All jobs are done and pushed:** Robux 3 products · runway · guards · JOB 2 army (+ the v95 army fix) · JOB 3 map fill ·
JOB 4 (airdrop, daily streak, plaza bounty, army upgrades) · JOB 5 monetisation (5a–5e). Nothing is half-done.
Every new gameplay item is owner-only (Rollout "owner") behind its own flag; OFF = the old game.

**Gates on this Windows PC:**
- `python` is the Store alias; use `C:/Users/shaun/AppData/Local/Programs/Python/Python312/python.exe` with PYTHONIOENCODING=utf-8
  and a forward-slash path wrapper (4 frozen pins compare POSIX paths).
- luau-compile and luau-lsp are in the session scratchpad.
- Last run: BuyPathStatic PASS=5209 FAIL=0 (parse gate on), rojo build ok, luau-lsp no new errors.
- The headless world sim and the DataService harness are not in the repo, so they were NOT run.

## Owner must create on Creator Hub
Paste each Id with `tools/wire-monetization-ids.py`. Every item stays hidden and prompts nothing while its Id is 0. Then set
`MonetizationConfig.Rollout = "all"` (and the other owner-only Rollouts) when you're happy on your account.

| Name | Type | Suggested R$ | Config key | One line |
|---|---|---|---|---|
| Skylance Interceptor | Game pass | 899 | GamePasses.PV_Skylance | Robux-only interceptor jet, a bit faster/tougher than the best cash jet |
| Stormwing Gunship | Game pass | 999 | GamePasses.PV_Stormwing | Robux-only attack helicopter |
| Leviathan Dreadnought | Game pass | 1199 | GamePasses.PV_Leviathan | Robux-only capital ship |
| Tidebreaker Assault Boat | Game pass | 299 | GamePasses.PV_Tidebreaker | Robux-only fast attack boat |
| Warlord Siege Tank | Game pass | 799 | GamePasses.PV_Warlord | Robux-only heavy tank |
| Razorfang GT Interceptor | Game pass | 199 | GamePasses.PV_Razorfang | Robux-only fast buggy |
| Bigger Army | Game pass | 249 | GamePasses.BiggerArmy | +10 soldiers in your army, forever |
| Instant Army Refill | Developer product | 49 | DevProducts.SoldierRefill | Fill your army to its cap right now |
| Plaza Airstrike | Developer product | 79 | DevProducts.PlazaAirstrike | One airstrike on the Central Plaza (3 s warning, never lethal) |
| Extra Garage Slot | Game pass | 199 | GamePasses.ExtraGarageSlot | +1 vehicle slot: keep a second vehicle out (JOB 6) |

Also: set `MonetizationConfig.Retention.GroupId` to your Roblox group id (0 hides the group-reward row).
All Robux prices live in one table: `MonetizationConfig` (RobuxPrice).
Already live and unchanged: VIP, 2x Cash, Double XP, Auto Collect, Speed Pass, cash packs x4, gold packs, Battle Pass Premium,
Army Expansion, Speed Boost, Golden Pumpjacks, Commander Starter Pack, Keep-Base Rebirth.

**Open dev tasks (not done, on purpose):**
- Extra Garage Slot: needs multi-active vehicles in VehicleService.
- Ground/naval vehicle weapons: they don't exist, so the premium tanks and boats are armour/HP/speed only.
- VIP stays at +25 % cash (not cut to the requested +10 %: live buyers paid for 25 %).
- "Skip build timer" was not added: upgrades are instant.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Army (v95 fix):** walk into your base with 8+ soldiers. Nobody crosses the gate, and there are two neat blocks outside facing out.
  ATTACK: rows in front of you, then a ring round an enemy (no stacking).
- **5a:** the Garage shows 6 gold "ROBUX · R$" rows. Tapping one says "coming soon" until its Id is pasted. You can already spawn
  them (owner auto-grant).
- **5b:** your chat shows the [VIP] tag if you own VIP. The VIP lounge is just north of the Town: its door lets you through, and 2 s
  on the gold pad pays $5,000 (once per 15 min).
- **5c/5d (after the Ids exist):**
  - the AIRSTRIKE button near the plaza;
  - the army-refill offer after your squad is wiped;
  - the 2x Cash / cash offer after a rebirth;
  - the cash-pack offer when a vehicle is too expensive.
- **5e:** the Shop's Robux tab starts with FREE rows (Daily Reward CLAIM, Airdrop TRACK, Favorite). With Roblox Premium you get
  +$2,500 on the first join of the day.
- **Earlier jobs** (runway, guards, map fill, JOB 4): see the sections below and ASSUMPTIONS.md.

---

# v94 — 2026-09-29 ~08:20 Dublin (Code Bot, branch phase-7-polish, WE_Build 94)

**Claude: do not redo guards fight-back / bag LOS / NPC unstick.** Merged `origin/claude/desktop-bud` (18df075) into phase-7-polish and published as WE_Build 94.

- **Guards fight back (owner-only):** `CombatConfig.GuardsFightBack` Rollout owner. A plain NPC shot by a squad unit fights that unit back (LOS, reaction, FireRate, HitChance) while no player is in range. Shooter handed via `CombatService.SetUnitShooter` (frozen squadfair pins untouched).
- **NPC unstick (owner-only):** `CombatConfig.NpcUnstick` — chase with no progress in 1.5 s jumps and sidesteps (bank planters G1/G2).
- **Bag pickup LOS (owner-only):** `OpsConfig.Cargo.PickupLosRollout` — server line of sight on bag pickup (CP-9 E4).
- **Pins:** `tools/checks/claude_bud_guards.py`; WE_Build pins bumped 93→94 (`tools/checks/codebot_v94.py`). PreferMesh stays OFF.
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow, v92 plaza capture, v93 Robux + runway layout-sig.

**Still open for Claude (Bud queue):** JOB 2 army gate/formation, JOB 3 fill the map, JOB 4 features, JOB 5 monetisation.
**Still in `handoff/wip/`:** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

**Phone tests for Shaun:**
- Guards (owner account): take the army to the Empire Bank and ATTACK the guards while you stand more than 90 studs away. Guards shoot your soldiers (tracers, soldiers lose HP). Walk in front of the hall so G1/G2 chase you past the planters: they hop or step around them instead of sticking. A second account should see the old guard behaviour.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v93 — 2026-09-29 ~00:29 Dublin (Code Bot, branch phase-7-polish, WE_Build 93)

**Claude: do not redo Robux products or the runway layout-sig fix.** Merged `origin/claude/desktop-bud` (72c2b12 + d9c2b77) into phase-7-polish and published as WE_Build 93.

- **3 Robux products (owner-only):** Speed Pass game pass 1998656357, Keep-Base Rebirth 3714663721, Golden Pumpjacks 3714663783.
  `MonetizationConfig.Rollout = "owner"` + `RolloutKeys` + `SkuLiveFor`. Shop/prompts/pads gated per player; **ProcessReceipt is never gated**.
  Golden Pumpjacks: gold pumps pay `IncomeMult` 1.5 (+50% Pending cash). World ATM pads skip gated keys until Rollout = "all".
- **Runway layout-sig rebuild:** `MapSetup.LAYOUT_SIG` / `WE_LayoutSig` in MapSetup + Bootstrap rebuilds a saved pre-v90 map so the runway is 190×29 and hangar 68×40 (v90 sizes). Check: `tools/checks/claude_bud_runway.py`. PreferMesh stays OFF.
- **Pins:** `tools/checks/claude_bud_monetization.py` + `tools/checks/claude_bud_runway.py`; WE_Build pins bumped 92→93.
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow, v92 plaza capture.

**Still open for Claude (Bud queue after v94):** JOB 2 army gate/formation, JOB 3 fill the map, JOB 4 features, JOB 5 monetisation.
**Still in `handoff/wip/`:** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

**Phone tests for Shaun (from Claude Bud handoff):**
- Robux (owner account only): Shop shows Speed Pass (5 R$) and Golden Pumpjacks (49 R$); Speed Pass makes you faster and the army keeps up; Rebirth panel shows KEEP BASE R$ 50; Golden Pumpjacks turns pumps gold with ~+50% Pending cash per tick. A second account sees none of these.
- Runway: join a NEW server ("Migrate to Latest Update" first). Runway from west plot wall almost to helipad lane (190 long, 29 wide, dashes all the way). Jet spawns at west end and takes off along the whole strip. Hangar is not inside any building.

---

# WHERE I STOPPED — 2026-09-28 (Claude on Bud, branch claude/desktop-bud)

Queue (owner's order): [x] Robux 3 products · [x] runway · [x] guards (fight back, bag LOS, unstick G1/G2) · [x] new JOB 2 army
gate/formation · [x] JOB 3 fill the map · [x] JOB 4 features (supply drops, daily reward, plaza bounty, army upgrades) · [ ] JOB 5 monetisation (5a Robux vehicles DONE; next 5b passes: VIP chat tag + VIP area, Bigger Army pass, Extra Garage slot; then 5c, 5d, 5e, then the Creator Hub list).

**Done, pushed:**
- (rebased on v95 phase-7-polish) ARMY FIX after the owner's v95 test: the army holds before the gate (no path through it, no teleport),
  validated clean hold grid facing out, ATTACK gives every soldier its own spot (march rows / target ring). Kill switch `Follow2.Tidy.Rollout = "off"`.
- 5a: six Robux-only vehicles (Skylance jet, Stormwing heli, Leviathan + Tidebreaker boats, Warlord tank, Razorfang buggy),
  own passes (Ids 0: TODO owner), about +5 % over the best cash vehicle, owner-only, gold ROBUX rows in the Garage.
- Robux: Speed Pass 1998656357, Keep-Base 3714663721 and Golden Pumpjacks 3714663783, owner-only (`MonetizationConfig.Rollout = "owner"`).
- JOB 4 (each owner-only, own flag): parachute **airdrop** every 10 min with marker (`SupplyDropConfig.Airdrop`); **daily streak**
  auto-claimed on join (`DailyRewardConfig.AutoClaim`); **plaza bounty** $15k for retaking the plaza within 3 min (`PlazaBountyConfig`);
  **Army Upgrades** prompt at your Barracks, which opens the Soldiers research (`ArmyUpgradeConfig`). Check: `tools/checks/claude_bud_features.py`.
- Map fill (everyone, kill switch `WorldFillConfig.Enabled`): **planned parts Full 388 / Low 198** in `Workspace.WorldFill`
  (world total about 2,864 / 1,877 against caps 2,900 / 1,900): 4 connector roads to the plaza, 2 bridges over dock channels,
  6 army positions between the bases, 4 light plaza posts, terrain rocks. Check: `tools/checks/claude_bud_worldfill.py`.
- Army (owner-only, `ArmyConfig.Follow2.Tidy`): the army stops in neat rows outside your main gate facing out and never enters your plot;
  fixed seats in the wedge, no crossing when you turn; after you leave the base they run back into the wedge (no teleport for 8 s).
  Check: `tools/checks/claude_bud_army.py`.
- Guards (owner-only): bank/camp NPCs shoot back at squad units that shot them; chasing NPCs jump and sidestep when stuck (G1/G2 planters);
  Ops bag pickup needs line of sight. Flags: `CombatConfig.GuardsFightBack` / `NpcUnstick`, `OpsConfig.Cargo.PickupLosRollout`. Check: `tools/checks/claude_bud_guards.py`.
- Runway: a saved pre-v90 map is now rebuilt (`WE_LayoutSig` layout hash in MapSetup + Bootstrap). Check: `tools/checks/claude_bud_runway.py`.

**How to run the gates on this Windows PC:**
- `python` is the Store alias; use `C:\Users\shaun\AppData\Local\Programs\Python\Python312\python.exe`.
- BuyPathStatic needs `PYTHONIOENCODING=utf-8`, plus a wrapper that makes paths use forward slashes (4 frozen pins compare POSIX paths).
- luau-compile and luau-lsp are in the session scratchpad (not the repo). The headless world sim and the DataService harness are not in the repo, so they were not run.

**Phone tests for Shaun:**
- JOB 4: wait about 1 min after joining for the first airdrop (marker + toast; the crate falls with a canopy, stand by it 2 s for the cash).
  About 8 s after joining you get a login streak toast. Capture the plaza with a second account, then retake it with yours within 3 min: +$15,000.
  At your Barracks, tap "Army Upgrades": the Research panel opens on Soldiers.
- Map fill: drive out of the side gates (P1/P2/P5/P6). A road now runs to the main east-west road and on to the plaza. Visit the
  sandbag/watchtower positions between bases, and drive over the bridge at the west dock channel; boats pass under it. Check the frame rate
  on a mid phone. The server log line `WorldFill: quality=full parts=N skipped=M` gives the real count.
- Army: walk (then drive) into your base with 8+ soldiers. They stop outside the main gate in two neat blocks (left and right of the road),
  facing out, and none come in. Walk out: they fall in behind you in a wedge without popping or teleporting. Turn round on the spot:
  the wedge follows without soldiers running through each other. Kill switch: `ArmyConfig.Follow2.Tidy.Rollout = "off"`.
- Guards (owner account): take the army to the Empire Bank and ATTACK the guards while you stand more than 90 studs away. The guards now shoot
  your soldiers (tracers, soldiers lose HP). Walk in front of the hall so G1/G2 chase you past the planters: they hop or step around them instead of sticking.
- Robux (owner account only): Shop shows Speed Pass (5 R$) and Golden Pumpjacks (49 R$); Speed Pass makes you faster and the army keeps up;
  the Rebirth panel shows KEEP BASE R$ 50; Golden Pumpjacks turns the pumps gold with about +50% Pending cash per tick. A second account sees none of these.
- Runway: join a NEW server ("Migrate to Latest Update" first). The runway runs from the west plot wall almost to the helipad lane
  (190 long, 29 wide, dashes all the way). A jet spawns at the west end and takes off along the whole strip. The hangar is not inside any building.

---

# v92 — 2026-09-28 ~23:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 92)

**Claude: do not redo / undo these.** Code Bot finished the stalled Claude-watch takeover of WIP lane **02 capture**
(`handoff/wip/02-capture_on_e506c9c.patch` on base e506c9c, 3-way merged onto phase-7-polish after v91).

- **PersistClaims = false** (`EconomyConfig.OutpostIncomeBuff`): saved outpost claims are NOT re-planted on join.
- **ReleaseOnLeave = true** (`TerritoryConfig`): a leaver's zones go Neutral at once (Home Outpost still returns on join once taken, F10).
- **StandingBar** on: CAPTURING / CONTESTED / YOURS bar. YOURS is a 5 s cue on the painted disc (`OnDisc`, `HeldSeconds=5`);
  no YOURS on top of the capture toast (`HeldAfterCapture=false`). CONTESTED follows the counted reach (blocker sees it too).
- Capturer's bar only names a zone he is counted inside this tick (CAP-16). Presence changes push to movers only (CAP-19).
- Contested pulse capped at 10 Hz. Finished Neutral contests reset to Neutral.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so PersistClaims-on v83 servers
  do not re-plant claims during a rolling update (CAP-5 / phone_test step 0).
- Pins: `tools/checks/codebot_v92.py` + the fb4 capture block already in `tools/BuyPathStatic.py`. Assumptions appended
  from `handoff/wip/notes/02-capture/assumptions.md` (CAP-1..CAP-22).
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow path), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow.

**Still in `handoff/wip/` (not this ship):** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

---

# v91 — 2026-09-28 ~23:45 Madrid (Code Bot, branch phase-7-polish, WE_Build 91, place versions 87 + 88)

**Claude: do not redo these.**
- **Helicopters (owner's choice):** every heli key wears the attack heli 11240665977, owner-only like every heli body
  (`Rollout = "Body"`). Each key has its own colour on the body panels only (`HELI_PAINT_PARTS`: BAP 1, Body, Doors,
  Thing for Blades); glass, seats, blades, wheels and engines keep theirs. Built with `heliRef(scale, colour, cabin, note)`.
  - Transport keys get a bigger scale to fit their bigger kit (TransportHeli 0.52, HeavyLiftHeli 0.6, Medevac and LightTransport 0.48;
    the rest 0.45). Seats, after live raycasts on place v87 (the commit after the first v91 publish, place v88):
    - crew at (±4, 5.4, -30): 3.4-4.8 studs under the glass (narrow kits had 2.5 at 6.0);
    - rear pair at (±3.5, 5.0, -21) and the middle seat at (0, 5.0, -25), inside the cabin with hull on both sides.
      The old z -13 rear pair stuck out of the tail.
  - The main Blades spin through the v90 rotor lookup.
  - `BODY_LIGHT_HELI` / `BODY_TRANSPORT_HELI` are kept, unused (a one-line revert).
  - AttackHelicopter keeps its own navy (27,42,53). StealthHeli keeps near-black (20,22,26), a whole-body recolour as in v88.
  - Colours: GunshipHeli gunmetal 74,80,88 · EscortHeli slate blue 78,98,124 · NightAttackHeli dark olive 58,62,40 ·
    LightScoutHeli olive drab 100,108,68 · UtilityHeli khaki 150,138,100 · RescueHeli desert sand 190,168,122 ·
    MedevacHeli light grey 160,164,168 · TransportHeli forest green 54,78,56 · LightTransportHeli sage 118,134,112 ·
    HeavyLiftHeli earth brown 116,92,66. VTOLTransport keeps its own tilt-rotor body.
- **Army FOLLOW overhaul, live for EVERYONE** (`ArmyConfig.Follow2.Rollout = "all"`; set it to `"off"` to go back to the old follow).
  New `Server/Modules/ArmyFollow.luau`; SquadOrdersService hands it FOLLOW movement (`_AFOn`) and keeps the lifecycle
  and shooting. The v85 FollowPace and v90 Fix follow/recover are bypassed while it is on.
  - **What was wrong:** soldiers collided with each other (every HumanoidRootPart collides, all in Default). At a run they
    shoved, tripped (FallingDown/Ragdoll) and got flung. A unit flung under the map lost its root to
    FallenPartsDestroyHeight; for everyone but the owner that unit then stayed in the squad as an invisible ghost forever.
    SyncArmy only culls dead or parentless models, and the v90 re-form was owner-only. That was the "despawn".
    On top of that: no per-unit spacing, catch-up capped at 28 (or the v85 multipliers), and regroup was owner-only and slow.
  - **Now:**
    - wedge slots behind him, turned by his move direction;
    - separation steering, and CollisionGroup `WE_Squad` never collides with itself;
    - trip/ragdoll states off;
    - straight MoveTo while the slot is in sight, pathfinding only when blocked (1.5 s per unit, 8 per server per second,
      path kept while its end is within 8 studs of the slot);
    - catch-up speed = max(his WalkSpeed incl. Speed Pass/Boost, his measured speed) x 1.35 plus 0.6 per stud behind,
      capped at max(owner x 1.8, 34);
    - regroup teleport (one PivotTo to a ground-checked clear spot behind him, never a delete) when: 70 studs from its slot
      for 1 s, stuck 3 s, under the map, or right after he teleports/respawns;
    - a unit that lost its root is re-formed for everyone;
    - every removal, death, root loss and regroup is logged `[ArmyFollow] ...` (rate-limited).
  - **Own base:** while he is inside his own plot square (4 studs in; out again 2 studs past the edge), his units wait spread
    out 12-16 studs outside his main gate, beside the gate lane and never in it. They re-form behind him when he comes out.
  - **Checks:** the Open Cloud session has no physics (GetRealPhysicsFPS 0) and no built map, so the check was a
    kinematic stand-in (units walk to their WalkToPoint at their WalkSpeed). Owner sprinting at 26 for 20 s, turn, stop,
    diagonal, base, exit: 0 units lost, formation within 25 studs while running, 0 units inside the plot during the base
    phase, re-formed after the exit. Real physics and the wait line on the real map need the phone test.
- Pins: `tools/checks/codebot_v91.py`. It retires 3 frozen army-fix pins and 1 v90 pin (the cull/trim now log first, and the
  ArmyFollow branch runs before recoverUnit).

---

# v90 — 2026-09-28 ~22:30 Madrid (Code Bot, branch phase-7-polish, WE_Build 90, place version 86)

**Claude: do not redo these. Shipped from `handoff/wip/` plus the owner's answers to the questions below.**
- **01 army despawn fix**: merged onto HEAD behind the new `ArmyConfig.Rollout.Fix = "owner"`. Only shaunie6's squads use the fix
  (Follow / Recover / Gate-open blocks via `SquadOrdersService._FixLive`, `reformRootless(uid)`, and the GateDefense gate-open
  `LiveFor("Fix")`). For him it replaces v85 FollowPace (`_PaceBegin` returns false); everyone else keeps v85 / 4d26673.
  NOT done: Claude's r1 re-measure (GATECAMP, UNDER, hall with guards down, T3), because it needs the stand-in/phone. Go-live for everyone: `Rollout.Fix = "all"`.
- **05 harbour** (the dock boat and building as a Part kit): live for everyone, kill switch `DockKitConfig.Enabled = false`. Visual only, 0 new assets.
- **06 floating faces**: live for everyone (client-only visual). Switches: `Escort.Camera.GuardHz = 0` / `LeadScreenFrac = 0`.
- **08 air fix-2** (rotor `Under` scope, chase-zoom span, rotor joint not counted as a pin): live. No current ref uses `Under` yet.
- **Owner answers:**
  - **Jets:** StrikeJet, CASJet and StealthStrike (plus the StealthStrikeJet ref) now wear jet 14589101870 with the pilot inside,
    using the FighterJet layout. They stay owner-only (`Rollout = "Body"`), like the v88 bodies they replace. The v88 tables
    `BODY_STRIKE_JET` / `BODY_STEALTH_STRIKE` are kept, unused, so reverting is one line.
  - **Jet colours:** each jet has its own colour on its grey panels only (`BodyColorParts = JET_PAINT_PARTS`). The black trim
    and the glass canopy keep the approved look.
    Palette (RGB):
    - FighterJet: air-superiority grey (118,126,136)
    - InterceptorJet: navy blue-grey (64,82,108)
    - TrainerJet: desert sand (184,162,118)
    - LightFighter: olive drab (96,104,66)
    - StrikeJet: dark green (62,82,60)
    - CASJet: earth brown (126,100,72)
    - StealthStrike (and the StealthStrikeJet alias ref): charcoal (46,48,54)
    The colours on the four original jets show for everyone. The three new jet keys are owner-only.
  - **Runway:** 170 x 24 → 190 x 29. It can't be longer: the plot edge is at X -160 and the HeliApron at X 34.
  - **Hangar:** 58 x 34 → 68 x 40 (+17 %). The site moves to Z -125 and the shell scales by Width/58.
  - **Bridge Layer:** wades through water like the Amphibious APC (0.4 x speed). Server-authoritative,
    owner-only (`VehicleConfig.Drive.WaterRule.AmphibiousRollout = { BridgeLayer = "owner" }`).
- **Left in `handoff/wip/`** (the README rows give the status): 02 capture, 03 lane B, 04 lane A, 07, 09-12 VKIT. Lane C was not started.
- **Pins:** `tools/checks/codebot_v90.py`, plus Claude's lane pins moved to `codebot_v90_airfix2.py`, `codebot_v90_harbor.py` and `codebot_v90_faces.py`.

---

# WHERE I STOPPED — 2026-09-28 ~19:40 UTC (branch claude/war-empire-phase-7-toqwff)

**What I was doing:** shipping the army despawn fix (fix round r1), plus review rounds for the capture, harbor and faces fixes, and building the Part-made vehicle bodies (VKIT). The owner asked me to stop, so all workflows are stopped and nothing is scheduled.

**Finished and pushed (live-ready):**
- `af4c7d4`: ground vehicles can't drive on water.
- `4d26673`: army escorts shoot back at the bank, with tracers (owner-only rollout).
- `4e07fc2`: the owner's jet on the four jet keys, pilot inside, Ride on the Trainer.

**Left (all saved as patches in `handoff/wip/`; not built, not live; the table in `handoff/wip/README.md` gives each base and status):**
1. ~~Army despawn fix (`01`)~~: **shipped in v90, owner-only (`Rollout.Fix`)**. Still open: the r1 re-measure on a device/stand-in.
2. Plaza capture fix (`02`), then army lane B checkpoints (`03`, rebase after 02). **Still open** (not shipped in v90).
3. Army lane A, guard and follow (`04`): finish tests and rebase onto the shipped `01`. **Still open.** Lane C (ATTACK marches to checkpoints) is not started.
4. ~~Harbor boat and dock (`05`), faces (`06`) and air fix-2 (`08`)~~: **shipped in v90** (their review rounds were done by Code Bot while merging).
5. VKIT vehicle bodies (`09`–`12`): ground fix-2 and naval deliverables are half-done. ground2 records (`07`) wait on VKIT ground. **Still open.**
6. Water Lows: land spot behind walls, rider teleport prefetch, hover above 160 studs, shallow reverse. **Still open.**
7. Owner questions (**answered by the owner 2026-09-28; all done in v90 except the helicopter**):
   - Should the Strike, CAS and Stealth jets get his jet? **Yes**: they now use 14589101870 with the pilot inside (v90, owner-only like v88).
   - Is the jet's look OK? **Yes, approved**: kept.
   - Should each jet get its own colour? **Yes**: one military colour per jet key (v90; palette in the v90 note).
   - Should the runway and hangar be bigger? **Yes, slightly (15-25 %)**: runway 190 x 29, hangar 68 x 40 (v90).
   - Should the Bridge Layer be amphibious? **Yes, it should cross water**: it wades, owner-only, server-authoritative (v90).
   - New helicopter model (the uploader made every part, 35 parts or fewer)? **Yes, wanted. The owner is handling the search himself: do NOT search.** Wire it once he sends the id.

**Files:** `handoff/wip/*.patch` (12 lanes, plus 03b/04b base patches), `handoff/wip/README.md` and `handoff/wip/notes/` (phone tests, owner texts, assumptions and the army design spec).
**Owner phone test right now:** nothing new. `src/` is unchanged since 4e07fc2.

---

# LATEST HANDOFF — Code Bot Roblox replacement (20 Sep 2026 ~00:00 Madrid)

> **v89 (28 Sep 2026, Code Bot): the wc7 capital ships + airlifter are WIRED — owner-only, same system. Claude: do not redo.**
> Destroyer 6860896505 (Stud Class, 0.2) and Cruiser 6860896505 (0.22), both Yaw 180 (bow = the pointed +Z end with the
> full-depth stem; the rounded overhanging -Z end is the stern: wc7's Yaw 0 note was flipped after the side-profile
> raycasts), MissileCruiser 104820847233642 (18, BodyMaxScale 18, bow -Z), Battleship 12442299148 (2.0, bow -Z); all
> dark naval grey (58,62,68), captain inside the bridge, kit TurretF/BarrelF/TurretA moved onto the body turrets
> (BodyMounts). CargoPlane/AWACSPlane/TankerPlane now 10649792198 (4-engine airlifter, 2.1, Yaw -90, dark grey;
> replaces 17033079003). The v88 capital-ship NoFamilyFallback exclusion is gone (own bodies now). StrikeJet stays
> 3553891209. Every air / naval vehicle with a definition now wears a body for the owner. Pins: tools/checks/codebot_v89.py.

> **v88 (28 Sep 2026, Code Bot): the wc6 winners are WIRED too — owner-only, same system. Claude: do not redo this.**
> VTOLTransport 80886282228822 (both proprotors spin), AttackHelicopter/GunshipHeli/EscortHeli/NightAttackHeli
> 11240665977 (main rotor spins), StealthHeli = 11240665977 recoloured near-black (NOT 11839207737: a real Little
> Bird look-alike), StrikeJet/CASJet 3553891209 (gear omitted, texture cleared, dark), StealthStrike/StealthStrikeJet
> 7976374439, CargoPlane/AWACSPlane/TankerPlane 17033079003 at BodyScale 30, dark grey (replaces 2475398012),
> LandingCraft/AssaultLanding 12235335847 (anchor + chain omitted), HospitalShip/SupplyShip 2625253037, HoverTransport
> 3626114334. New ref fields: BodyMaxScale (cap 4..40), BodyAnchorX (carrier + amphib: the body also shifts across so
> the captain sits in the island). Still on the kit (search ongoing): Destroyer, Cruiser, MissileCruiser, Battleship —
> now NoFamilyFallback so they never inherit the LandingCraft barge. Pins: tools/checks/codebot_v88.py.

> **v87 (28 Sep 2026, Code Bot): air + naval store bodies are WIRED — owner-only. Claude: do not redo this.**
> 29 vehicles wear the owner's picks through the 4e07fc2 body system (VisualAssetConfig `BODY_*` tables + `bodyRef`,
> VisualAssetService fit, AirBodyRig), gated by `VisualAssetConfig.BodyRollout = "owner"` + per-ref `Rollout = "Body"`
> (only vehicles spawned by shaunie6 / 470626172 wear them; everyone else keeps the Part kit, no load):
> light helis 3130894523 (LightScoutHeli, UtilityHeli, RescueHeli, MedevacHeli; kit rotor spins on the mast),
> transport helis 109615982233602 (TransportHeli, LightTransportHeli, HeavyLiftHeli), bombers 14669079591
> (StrikeBomber, HeavyBomber, StrategicBomber; Bay mount under the centre), transports 2475398012 (CargoPlane,
> AWACSPlane, TankerPlane), patrol 16692908395 (PatrolBoat, FastAttackCraft, RiverBoat, CoastCutter, TorpedoBoat),
> gunboat 15838664806 at 0.027 (Gunboat, MissileBoat, MineLayer, CoastalMonitor; per-ref BodyMinScale), frigate
> 473576954 (Corvette, Frigate, CarrierEscort), carrier 7941124517 (FleetCarrier; BodyDeck plates), amphib 5545544418
> (AmphibAssault), sub 116924692473761 (SubSurfaceRunner, AttackSub; propeller spins). New ref fields: Rollout,
> BodyMinScale, BodyWaterline, BodyColor/BodyMaterial/BodyClearTexture, BodyDeck, BodyKitNoCollide, KitRotor.
> Kept on the kit (owner decision): Destroyer, Cruiser, MissileCruiser, Battleship (16675798409 rejected: real class),
> VTOLTransport (NoFamilyFallback), attack/gunship/escort/night/stealth helis, strike/CAS/stealth jets, landing craft,
> hospital/supply ships, hover transport. Pins: tools/checks/codebot_v87.py. To open to everyone later: BodyRollout = "all".


Shaun created you because the previous Code Bot Roblox chat **wedged** (messages failed to send). You replace it. Code/GitHub/laptop Studio are intact.

## Read first
1. `/workspace/war-empire/HANDOFF-TO-NEW-CODE-BOT.md` — MASTER SYSTEM INSTRUCTION + WAR EMPIRE brief
2. `/workspace/war-empire/MASTER_BUILD_SPEC.md`
3. `/workspace/war-empire/ASSUMPTIONS.md`
4. This file

Save operating rules to agent memory (profile): build don’t tutor; COMPLETED/FILES/TESTING/NEXT; local iteration; push to https://github.com/shaunbirrell/war-empire; ask only when architecture-breaking.

## Repo / branch
- Remote: https://github.com/shaunbirrell/war-empire
- Working branch: **`phase-7-polish`** (latest commit at handoff: **`b009165`** — BUY bootstrap fix)
- Earlier PRs: #1 phase-3-combat, #2 phase-5-territory, #3 phase-7-polish (may need refresh)
- Local: `/workspace/war-empire`
- Place builds: `dist/WarEmpire.rbxlx`, `dist/WarEmpire-PERF.rbxlx`
- Shaun’s laptop: `C:\Users\laura\Downloads\WarEmpire-PERF.rbxlx` (machineId `be2ced83-f720-49b1-a3c0-1100e04ffc10` — Lara’s Windows laptop used for Studio)

## What the previous bot was doing (transcript summary)

### Product progress
Phases 1–7+ heavily expanded beyond MVP:
- Foundation, tycoon, combat, vehicles, territory, missions, monetization, tutorial, battle pass, clans, seasons, soldiers, bank raids, spinner, upgrade pads, desert map restyle, bank guards AI, mobile HUD, perf cuts, void/fall safety, world prompts / BUY pads

### Critical live bug (LAST FOCUS — claimed fixed, needs Shaun confirm)
**Command Center BUY broken in Studio Play:**
1. `CombatService/init.luau` required `VisualAssetService` via wrong path (`script.Parent.Parent` → Server), crashing Bootstrap
2. Crash happened **before** remotes finished → client error `RemoteEvent missing: SpinnerStateUpdate`
3. HUDController died → WorldPromptController never inited → no BUY button

**Fix shipped in `b009165`:**
- Correct require → `script.Parent.VisualAssetService`
- `RemoteSetup.Init()` early + idempotent
- UIController `safeInit` pcall so WorldPrompt always runs
- Rebuilt rbxlx; copied to laptop Downloads as `WarEmpire-PERF.rbxlx`

**Shaun was asked to:** Stop Play → open new Downloads file → Play → stand on Command Center → expect gold BUY + walk-buy; cash $5000 → $3500. **He has not confirmed yet** (chat wedged).

### Other open work from previous todos
- Verify BUY + all dock/buttons end-to-end
- Playtest on laptop Studio until solid
- Studio/Creator assets for soldiers/guards/buildings/vehicles (in progress / cancelled stick approach)
- Overnight polish / MVP completion pass

### Git commit tip
Do **not** write `git config`. Use env:
```
export GIT_AUTHOR_NAME="Code Bot Roblox"
export GIT_AUTHOR_EMAIL="codebot@war-empire.local"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
```

### Shaun prefs
- Speed: keep chaining, local executors over Cloud Agents
- Copy rbxlx to his laptop Downloads when shipping playtest builds
- Roblox username seen in logs: `shaunie6`
- Spanish Windows path (`El sistema no puede encontrar…`) — laptop is Spanish locale

## Immediate job
1. Message Shaun: you’re the new Code Bot, online, you have the handoff.
2. Confirm `git log -1` on `phase-7-polish` is `b009165` or newer; pull if needed.
3. Ask if BUY works on the latest `WarEmpire-PERF.rbxlx`; if not, diagnose from Studio Output and fix.
4. Continue polish: buttons, playtest, assets — COMPLETED/FILES/TESTING/NEXT format.

Chief of Staff may ping you; Shaun’s chat is primary.
