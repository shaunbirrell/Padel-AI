# Benchmark: Military Tycoon–inspired loop (WAR EMPIRE reimplementation)

**Purpose:** Document publicly observable mechanics from Roblox *Military Tycoon* (place id **7180042682**, InfinityInteractive) so WAR EMPIRE can reimplement **similar systems under original naming** — not copy meshes, trademarks, Discord assets, or Infinity Tower branding.

**Legal / product stance:** Inspiration only. No MT asset reuse. Currencies map to WAR EMPIRE Cash / Gold (not “Diamonds”). Prestige maps MT-style rebirth. All names are WAR EMPIRE originals (Training Yard, Coastal Oil, Capture Stipend, Daily Ops, Nation Color, Codes).

---

## Public sources (themes / loop)

| Source | What it documents |
|--------|-------------------|
| [Roblox Wiki — Military Tycoon](https://roblox.fandom.com/wiki/InfinityInteractive/Military_Tycoon) | Island map; build base; cash from workers; capture fortresses + **2 oil rigs** for stipends; desert POIs / fortresses; vehicles & arsenal progression |
| [Military Tycoon Wiki — Oil Rigs](https://military-tycoon.fandom.com/wiki/Oil_Rigs) | Two coastal oil capture points; stronger guards than fortresses; stipend comparable to fortress; flag stand-in-zone capture |
| [Military Tycoon Wiki — Rebirths](https://military-tycoon.fandom.com/wiki/Rebirths) | Rebirth resets base purchases; permanent cash mult (+0.1 per rebirth, cap ×5 at 40) |
| [Deltia's Gaming — How to play](https://deltiasgaming.com/roblox-how-to-play-military-tycoon/) | Early loop: buy **workers** that shoot training targets for AFK cash; capture flags ASAP for passive income; rebirth often |
| [Pro Game Guides — Rebirth / oil tips](https://progameguides.com/roblox/how-to-rebirth-fast-in-roblox-military-tycoon/) | Codes for cash; oil rig stealth vs AA/navy guards; fortress stipend farming |

Place id reference: Roblox experience **7180042682** (Military Tycoon).

---

## Observed core loop (summary)

1. **Base workers → income** — Purchase soldiers/workers at the base. They “train” (shoot targets) and generate **cash over time**. More workers = higher cash/sec. Early game priority.
2. **Capture fortresses / outposts** — Stand in a flag zone (~30s public guides) after clearing NPC guards. Owned points pay a **periodic stipend** (wiki: ~every 1.5 minutes; fortress cash in the low tens of thousands in older wiki notes).
3. **Oil rigs (×2)** — Harder coastal platforms; stronger guards; stipend at least fortress-tier; useful early mid-game cash.
4. **Vehicles (100+ catalog theme)** — Large ground / air / naval unlock tree gated by base progress / rebirth. WAR EMPIRE keeps its own vehicle catalog (no MT models/names).
5. **Raid / PvP / contest** — Capture contested points; fight players who hold fortresses/oil.
6. **Codes** — Redeem promo codes for cash (and premium currency). Once per code per account.
7. **Daily ops / missions** — Rotating short objectives (kills, captures, recruit) with gold/cash rewards.
8. **Diamonds → Gold** — Secondary currency for cosmetics / skips / premium tracks. WAR EMPIRE uses **Gold**.
9. **Rebirth → Prestige** — Reset base progression for a permanent cash multiplier and unlocks. WAR EMPIRE `PrestigeService` already covers this theme.
10. **Desert / island map POIs** — Fortresses, oil coasts, ridges, docks. WAR EMPIRE expanded desert-style ground (~4800) with territories + **Coastal Oil Alpha/Bravo** + **Fort Ironclad / Fort Sandhold**.
11. **Loot crates / supply drops** — Periodic world crates; stand nearby to claim cash. WAR EMPIRE `SupplyDropService` (not paid RNG boxes).
12. **Bank / high-value raid** — Contested building with guards; loot cash on a cooldown. WAR EMPIRE `Empire Bank` stub (`BankRaidService`).
13. **Free spinner / timed reward** — Claim cash/gold every few hours from HUD/Settings. WAR EMPIRE `SpinnerService` (distinct from policy-pending paid loot boxes).
14. **Group join / shout rewards** — Skipped (no Roblox Group API / no fake Discord).

---

## WAR EMPIRE mapping (this branch)

| MT theme | WAR EMPIRE system |
|----------|-------------------|
| Workers shooting targets | `SoldierService` training tick + MapSetup **TrainingYard** targets per plot |
| Fortress / flag stipend | `CaptureStipendService` + `TerritoryConfig.StipendCash` |
| Oil rigs ×2 | `CoastalOilAlpha` / `CoastalOilBravo` POIs (harder guards, higher stipend) |
| Codes | `CodesService` + Settings redeem (`WARFOUNDING`, `BUILDCONQUER`) |
| Daily objectives | Mission / Daily Ops (`CaptureTerritory`, `KillNPC`, `RecruitSoldiers`) |
| Nation / country color | `NationColorService` → captured flag tint |
| Diamonds | Gold |
| Rebirth (+0.1 cash / rebirth theme) | Prestige / Rebirth — **+10%/prestige** + `RebirthUnlocks` track |
| 100+ vehicles | `VehicleConfig` ~49 Ground/Air/Naval kits + KitFamily ladder toward 100; Garage cat/rarity filters (no MT IPs) |
| Loot crates / supply drops | `SupplyDropService` — periodic crates; stand to claim Cash |
| Bank / raid building | `Empire Bank` + `BankRaidService` (vault hold + cooldown + BankGuard) |
| Free spinner | `SpinnerService` — HUD/Settings claim every 4h (Cash/Gold table) |
| Named fortresses | `FortIronclad` / `FortSandhold` (walls + FortGuard + higher stipend) |
| Naval / harbor | `Dock` structure + coastal water + `WE_NavalSpawn` + PatrolBoat→Destroyer |
| Group / Discord shout | **Skipped** — no Group API; no fake Discord |

---

## Explicit non-goals

- Do **not** copy MT meshes, UI art, Discord assets, Infinity Tower, or trademarked names.
- Do **not** scrape private Discord for codes or assets.
- Do **not** implement fake Discord / Group join shout rewards.
- Product IDs remain `0` until Creator Dashboard setup.
- Paid random loot boxes remain `LootBoxConfig.PolicyPending` (Supply Drops + Spinner are free timed/world rewards only).

