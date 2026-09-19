# WAR EMPIRE — Phone publish checklist

Use on a real phone (or Studio Device Emulator → Phone) before shipping.

## Prefs / Studio laptop (8GB)

- [ ] `DevConfig.StudioSkipWorldDressing = true` (keep for PERF)
- [ ] Optional catalog meshes: ForceDress / live only (`VisualAssetService` skips inserts while dressing skipped)
- [ ] Game Settings → Security → **Allow Loading Third Party Assets** if enabling catalog Models
- [ ] Open `dist/WarEmpire.rbxlx` or Rojo sync; **Play** (MapSetup auto-builds)
- [ ] Output shows Ground size/CanCollide after heal; PERF skip note for MapDressing
- [ ] If void/dead-space: **resetmap** or delete `Workspace.WarEmpireSetup` + Play again

## Touch / buttons (all must work)

- [ ] Mobile dock: BASE / Shop / Rebirth / Orders / Army / Settings (≥64px, Activated)
- [ ] GARAGE CTA (bottom-left) opens panel; X closes; OWNED + category/rarity filters
- [ ] Garage BUY → toast / owned; SPAWN → vehicle; DESPAWN works
- [ ] Combat: FIRE hold-to-fire, R reload, ◀/▶ weapon swap; reticle + hit marker
- [ ] Pad **BUY** (gold bottom): stand on own Command Center pad → tap BUY → Success toast + BOUGHT flash
- [ ] Can't afford → button shows **NEED $…** (still tappable; server toast)
- [ ] Base menu (**B** / dock BASE): BUY $ / UP $ with +$/tick; MAX disabled
- [ ] Walk-over auto-buy still works as backup (leave + re-enter pad)
- [ ] Wrong plot pad: no BUY / "Not your base"
- [ ] Seated in vehicle: pad BUY hidden (no drive-by purchase)

## Capture / territory (phone)

- [ ] Enter capture zone → large bar + **STAND IN THE ZONE** + %
- [ ] Contested → orange status; leave zone → bar hides
- [ ] Territory list collapses on phone (tap header to expand)
- [ ] Radar badge only when owning MinimapReveal territory

## Economy / progression smoke

- [ ] Cash ticks (+$/tick on pad billboard)
- [ ] Tutorial SKIP or complete ClaimBase → CommandCenter buy
- [ ] Jeep starter owned after join; Garage SPAWN
- [ ] Soldier recruit (Army) spends cash; training income line
- [ ] Shop prompts only (product IDs still 0 — no real charge)

## Publish

- [ ] Replace MonetizationConfig product IDs (all currently `0`)
- [ ] AdminConfig.UserIds = your UserId
- [ ] DataStore API services on for live persistence
- [ ] SoundIds: replace placeholder menu ambient in AudioController
- [ ] Private server playtest 2+ phones before public

## Ship artifact

Copy built place to phone-test PC path:

`C:\Users\laura\Downloads\WarEmpire-PERF.rbxlx`

Source on agent box (parent CopyFromBox):

`/workspace/war-empire/dist/WarEmpire-PERF.rbxlx`
