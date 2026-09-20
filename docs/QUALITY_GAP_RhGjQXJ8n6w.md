# Quality gap — competitor playthrough RhGjQXJ8n6w

**Source:** https://youtu.be/RhGjQXJ8n6w (~28:03, 720p60)  
**Captured:** 2026-09-20 Europe/Madrid  
**Status:** Full-file watch failed (size); 8min clip re-watching + stills at 1/5/10/20m analyzed. Mid/late clips encoding.

## What this game actually is
Military-flavored **classic dropper/conveyor tycoon** (not pure Military Tycoon clone):
- Blue conveyors + droppers + floating `$N` ore values
- Green neon floor buy pads (`Dropper $150`, `Walls 2.5K`, `Barrack $1.2K`, `Paths $500`, `Ceiling $3K`)
- End-of-line **Collect** pad + oil derrick income spectacle
- Floor **white chevron arrows** guiding next pad
- Weapon hotbar (Glock-17 → AK-47) + Shop / Rebirth / Orders / Setting sidebar
- Desert canyon + red rock mesas + palms/cacti backdrop

## Stills (actionable)

### ~1m — early loop
- Conveyor with live `$10` / `$75` floating values (income readable without opening UI)
- Single clear green pad + floor arrows
- Compact left icon rail (Shop/Rebirth/Orders/Setting) — no overlapping panels
- Cash pill bottom-left with `+` Robux upsell

### ~5m — build feedback
- Instant **"Purchase SUCCESSFUL!"** toast (green, readable)
- Walls/Ceiling pads show next prices in world
- Chevron path still points at unpaid pads
- Base silhouette grows as gray concrete room (still blocky — but **layout density** beats empty grass)

### ~10m — military theming
- **Pistol Squad / Rifle Squad** stalls with tarp roofs, crate stacks, lantern, crouching camo NPC with rifle
- Player in full camo + helmet (reads “soldier game”)
- Asphalt strip + yellow chevrons; palms/cacti/mesas fill horizon (no void)

### ~20m — mid base
- Parallel machine rows inside unfinished shell
- Oil derrick pumping beside base
- Collect circle + stacked toasts (Collected / need money / success)
- Barrack pad still guiding expansion

## Gaps vs WAR EMPIRE (ship these)

| # | Competitor pattern | WE gap | P0 fix |
|---|-------------------|--------|--------|
| 1 | Floor chevron arrows to next pad | Tutorial beam only / messy | Paint permanent `>>>>` on plot floor toward next unlock |
| 2 | Live floating `$` on producers | Training income invisible | Billboard `+$/tick` on TrainingYard + dropper-style feedback |
| 3 | Dense desert props (mesas, palms, cacti, asphalt) | Flat sand / void risk | MapDressing: canyon walls, road, flora density |
| 4 | Squad stalls with crates + NPC posing | Empty Part kits | Structure kits = mesh stalls + R15 camo soldiers |
| 5 | Instant green success toast | Yellow/low-contrast spam | High-contrast toast; debounce can’t-afford |
| 6 | Collect pad as ritual | Neon pillar OK but weak | ATM screen digits + Collect circle like peer |
| 7 | Oil derrick spectacle | Oil POIs far / weak VFX | Near-base oil/extractor visual or pump anim |
| 8 | Weapon hotbar early identity | Combat soft | Early Glock-class tool or Army UI hotbar cue |
| 9 | Left icon rail only | Overlapping BUY + tutorial | One panel rule already — keep DisplayOrder discipline |
| 10 | Every buy changes silhouette | Kits thin | Mesh buildings on buy (Design Bot IDs) |

## Design Bot brief (from this video)
Reject: neon green Part cars, R6 blocky SWAT, empty grass plots.  
Require: desert warzone dressing, camo R15 squads at stalls, crate/tarp props, military vehicle mesh with real wheels, ATM-like collector face.

## Next
- Finish clip watch (0–8, then 8–16 / 16–24)
- Fold into `DESIGN_COMPETITIVE_DEEP_DIVE.md` + live ship checklist


## Full 0–8min clip watch (2026-09-20)

Confirmed: stylized low-poly desert with sculpted terrain (not flat baseplate); Part-kit buildings OK within that aesthetic; blocky troops but formation/salute/pathfind; no vehicle drive in first 8m; no text tutorial — green pads + Free Dropper; premium colored pads (yellow speed, red auto/2x); walkie Orders UI; outpost capture → +10% Income.

### Extra P0s from watch
1. Manual early click-dropper ($10) to kill AFK boredom
2. Capture outpost → permanent income buff
3. Squad Orders (Follow/Attack/Hold/Retreat) walkie UI
4. Sculpted dunes + rock border enclosure (not void edge)


## Mid clip 8–16min watch (2026-09-20)

Loop: income → weapons/troops → Orders walkie → capture towns for +% → raid enemy bases.
- Pumpjacks outside walls as cash spectacle
- Heavy gate + fences + ceiling enclose compound
- PvP skirmishes at named zones; frontal gate assaults
- Frustration Robux (2x Money, Fast Speed, Golden Pumpjack) one click after loss
- Helicopters in air drive need for ceiling

### Gaps vs WE (post v23)
| Gap | WE status | Next |
|-----|-----------|------|
| Contested +10% zones | v22 shipped | polish zone names/flags |
| Orders walkie | v20 shipped | OK |
| Gate guards / HMG | v23 shipped | OK |
| **Siegeable gates** (damage/breach) | v24 shipped | OK — GateBarrier HP + breach/rebuild |
| **Oil pumpjacks outside walls** | oil POIs far | P0 — near-plot pump income pads |
| Frustration shop UX after death | stubs | P1 — Speed boost + 2x prompt on death |
| Base ceiling vs air | missing | P1 |


## Late frames ~17–21m (2026-09-20; full 16–24 watch failed then clipped)

- Rooftop/platform with yellow rail — elevated base floors / ceiling buy path
- Leaderboard shows Money + Rebirths columns
- Missions icon in sidebar (WE may lack dedicated Missions dock)
- Barriers $4K floor pads expand perimeter outward
- Squad stalls with tarp + crates still mid-game identity
- Multiple Purchase SUCCESSFUL stacked (debounce already in WE)

### Remaining vs WE v24
| Gap | Action |
|-----|--------|
| Base ceiling / roof | Shipping v25 |
| Missions dock | P1 backlog |
| Rebirth column on leaderboard | P1 |
| Barriers outward expansion spectacle | Walls exist — ensure L2+ visible fence grow |


## Late clip ~16–20min watch (2026-09-20)

Rebirth loop: base completion % → 100% → pay fee ($250k analog) → wipe base, keep Rebirth count + retained army → capture for +% income that survives rebirth.
Vertical expansion: stairs + concrete ceiling + roof barracks + helipad on roof.
Monetization: Mega Pack cash for Robux mid-grind (frictionless).
Missions: cash sink to unlock unique units/vehicles.
Orders + contested caps already in WE.

### Backlog after WE v24/v25 ceiling
| Priority | Feature | WE status |
|----------|---------|-----------|
| P0 | Rebirth at % base complete + fee UI | Prestige exists @ L40 — tighten to completion % + clear fee toast |
| P0 | Hard-currency cash packs | Monetization stubs — need live DevProduct IDs |
| P1 | Vertical roof barracks / helipad on ceiling | Ceiling shipping; add roof pad slots |
| P1 | Missions cash-sink UI | MissionConfig may exist — dock entry |
| P1 | Income buff survives rebirth | Verify OutpostIncomeStacks persist through prestige |
