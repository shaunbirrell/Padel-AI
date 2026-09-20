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
