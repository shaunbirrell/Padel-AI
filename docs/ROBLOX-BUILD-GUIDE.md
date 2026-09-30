# WAR EMPIRE: Roblox build guide (environment, props, vehicles, guards, UI)

Owner: Shaun. Written by Code Bot, 2026-09-30, from official Roblox Learn video transcripts and
create.roblox.com/docs text (see [Sources](#12-sources)). It is a **working guide for coders** (Code Bot, Claude):
follow it for every build job, then run the [detail checklist](#11-pre-ship-detail-checklist-every-build-job)
before you push. It changes no gameplay code.

**Project rules still come first** (CLAUDE.md): `PreferMesh` stays OFF for structure kits. Never touch `WE_Building*`
attributes. No real-world or franchise copies (no named real tanks, jets, ships, insignia, brands or other games'
assets). No fast travel. Phone first. Budgets in CLAUDE.md §1 are hard caps. Gameplay ships owner-first behind a flag,
and OFF must equal the old behaviour.

What this means for building: WAR EMPIRE's world is mostly **anchored Parts built by Luau builders**
(`WorldKits.Builders.*`, `StructureKitBuilder`, `HollowBuildingBuilder`, `Interiors/`, `RebirthZoneBuilder`,
`TrainingYardBuilder`), switched by `WorldDetailConfig`. Owner-approved Creator Store props (`StorePropsConfig`) are
the only meshes. So most of this guide is about getting "real object" detail **out of Parts**, and keeping it cheap.

---

## 1. The build order (greybox → play → detail → light → optimise)

From the Roblox Learn greybox, 3-lane map and environment polish videos, and the Environmental Art curriculum:

1. **Greybox the silhouette first.** Primitive Parts only (blocks, wedges, cylinders). Get the big shape, height,
   footprint and the gameplay-critical props (cover, doors, stairs, roads) right. No trims, no clutter.
   - A cottage in the video was one block plus two wedges. Our equivalent: a barracks is a long block, a
     pitched or flat roof slab and the door void. Nothing else yet.
2. **Playtest the greybox at phone scale.** Walk it, drive a tank through it, fight in it. Check the camera fits
   through doors and under ceilings (see §4). Fix scale and flow now, while it is cheap.
3. **Detail in layers** (§2): base/plinth → body → trims → openings → roof → clutter → ground contact → storytelling.
4. **Light it** (§5). Lighting changes how every colour reads, so final colour tweaks happen after lighting.
5. **Optimise** (§6): shadows, collisions, queries, transparency, part count, logged budgets.
6. **Detail checklist** (§11), then commit.

"Always put gameplay first and visuals second. Don't move on to final detailing until it plays well in greybox."
(3-lane FPS map design video.)

---

## 2. Making buildings, props and vehicles read as real objects

Players read an object in three passes: **silhouette** (from far), **big breakups** (from mid range), **surface
detail** (up close). Spend parts in that order. A box with 30 tiny stickers still reads as a box.

### 2.1 Silhouette rules
- **Break the top line.** Every building needs something above the roof line: parapet, roof overhang, AC unit,
  vent stack, water tank, antenna, radio mast, sandbag nest, flag pole. A flat box top is the #1 "low detail" tell.
- **Break the footprint.** Add a step-out: porch, lean-to, stair block, loading dock, side annex. The greybox
  video's cottage got its "real" read from a smaller copy stuck on the back.
- **Ground it.** Nothing floats and nothing is sliced by the ground: plinth or kerb at the base (0.5 to 1 stud
  tall, 0.5 stud wider than the wall), sandbags or crates against walls, a darker grime band at the bottom.
- **Vary heights in a group.** In a plaza row, no two neighbouring buildings share the same height and roof type.
- **Angles, not only 90°.** "When you only have 90° angles, tactical options are reduced and the map isn't as
  atmospheric." Use a chamfered corner, an angled wall, a wedge ramp, a staggered barrier chicane.

### 2.2 Layered parts (the "kit of layers")
Build every structure from these layers, in this order. Each layer is a few parts, not dozens.

| Layer | What it is | WAR EMPIRE example |
|---|---|---|
| Plinth | slab 0.5–1 stud tall, 0.5 wider than the walls, darker concrete | barracks, command centre, checkpoint booth |
| Body | the walls; 2 tones: main + slightly darker lower band | plaza shop walls |
| Trims | thin strips (0.2–0.4 stud proud) at the base, floor lines, top edge | a parapet cap on every flat roof |
| Openings | a void or recessed panel **plus** a frame (4 thin parts) **plus** a sill/lintel | booth windows with mullions, door frame and handle |
| Roof | overhang 0.5–1.5 studs past the walls, fascia strip, roof clutter | booth roof, hangar roof ribs |
| Clutter | 3–6 props that explain the building | AC unit, vent, pipes, sign board, light fixture |
| Ground contact | things that touch the floor next to it | sandbags, crates, jerry can, kerb, tyre marks |
| Story | one or two "something happened here" details | a knocked-over crate, a repair ladder, a patched wall |

**Trim is the cheapest detail you can buy.** The 3-lane map polish video added top and bottom trim to every wall and
it "already looks great". A 1-part trim strip changes a wall more than 10 bolts.

### 2.3 Bevels and edges with Parts
Hard 90° box edges read as "Roblox block". Soften the edges that the camera sees most:
- **Chamfer corners** with a thin rotated block or a `CornerWedgePart`/`WedgePart` at vertical corners of big
  buildings and on tank hull edges (front glacis, rear deck).
- **Rounded edges** with a half-buried cylinder along a top edge (sandbag tops, pipe runs, turret ring).
- **Inset panels:** a slightly smaller, slightly darker block 0.1–0.2 stud behind the face reads as a recessed
  door or panel (the same trick as the obelisk engraving in the environment polish video).
- **Keep bevels a fixed size when you scale.** From the Procedural Models interview (the "27-slice" idea): corners
  and edges keep their size while the middle stretches. In our builders, compute trims, bevels and frames from
  **fixed stud sizes**, not as a percentage of the building. A 40-stud-long wall gets the same 0.3-stud trim as a
  10-stud one, just longer. Never scale a whole detailed model up or down to fit.
- **Unions (solid modelling) are a last resort.** Docs: union UVs are box-mapped (textures stretch), results over
  20,000 triangles are simplified, and each union is its own geometry (no instancing). If you must union (a curved
  seamless floor, an arch), set `SmoothingAngle` 30–70, `CollisionFidelity = Box` or `Hull` unless it needs
  precise collision, and count it in the budget. Prefer overlapping parts.

### 2.4 Material and colour variation
- **Never one flat colour per object.** Every object gets at least 2 tones of its material, usually 3:
  base, a darker tone (lower band, frames, shadows), a lighter tone (trims, edge highlights). Keep them close
  (about 5–15 % brightness apart). Big jumps look like toys.
- **Randomise repeats a little.** The environment polish video recoloured 25 % of trees lighter and 25 % darker so
  a forest stopped looking copy-pasted. Do the same for sandbags, crates, barrels, rocks and tents:
  seeded random ±5 % brightness per instance, and a random 0/90/180/270° yaw where it doesn't matter.
  Use a **seed from the site id** so every server builds the same result.
- **Materials match the object.** Concrete for bunkers and plinths, `Metal`/`DiamondPlate`/`CorrodedMetal` for
  vehicles, gates and hangars, `WoodPlanks` for crates, `Fabric` for sandbags, tents and flags, `Glass` for windows
  (see §6 for transparency), `Asphalt`/`Pavement` for roads, `Brick`/`Cobblestone` for plaza fronts.
- **Built-in materials first.** Docs: built-in materials use far less memory than custom textures. Custom looks
  come from `MaterialVariant` (works on Parts, no mesh needed) only for surfaces that matter; any texture used must
  follow the asset origin rules (uploaded by the owner or Roblox) and be listed in `docs/ASSET_LICENSES.md`.
- **Colour codes help players.** The 3-lane video colour-coded each side of the map so players know where they
  are. Use one consistent accent per zone (plaza, depot, port, each base owner's accent) on trims, doors and signs.
- **Desert palette discipline.** Our world is warm and dusty. Keep big surfaces desaturated (sand, concrete, olive,
  rust), and save saturated colour for things players act on: red/white boom arms, warning signs, the objective,
  the purchase stands.

### 2.5 PBR (SurfaceAppearance) and why we rarely use it
- `SurfaceAppearance` (colour, normal, roughness, metalness, emissive maps) only works on **MeshParts**. With
  `PreferMesh` OFF our structures are Parts, so SurfaceAppearance is **only** for owner-approved Creator Store
  props that already ship with it. Don't convert kits to meshes to get PBR.
- The Part equivalent is a `MaterialVariant` in `MaterialService` (colour + normal + roughness + metalness maps,
  `StudsPerTile`, `Pattern`). Use at most a handful for the whole game, reused everywhere. Each new texture set costs
  memory on phones.
- Docs rule worth keeping: base material values on the real surface (rusty metal is rough, wet paint is shiny),
  not on one lighting setup. Check under day, dusk and night presets.

### 2.6 Decals, textures and signs
- Use `Decal`/`Texture` for stencils, warning stripes, grime, bullet marks, signs and flags. Flags in the world are
  **always** Textures/Decals, never SurfaceGuis (CLAUDE.md), and only original fictional emblems or the player's own
  cosmetic nation flag.
- Docs: decals, textures and particles **don't batch well** and add draw calls. Budget: 0–2 decals on a small prop,
  up to ~6 on a hero building. Reuse the same image ids so they instance.
- Text signs ("CHECKPOINT", "STOP") use the existing SurfaceGui budget (`MaxDistance` ≤ 80) and GothamBlack, short
  words. Never real brands.

### 2.7 Scale references (Roblox studs; 1 stud ≈ 0.28 m)
A default character is about 5 studs tall. Things read "real" when they sit at human scale, but doors and rooms
must be **larger than real** so the third-person camera fits (greybox video: "we often must make these things
abnormally large to accommodate a third-person camera").

| Thing | Size (studs) |
|---|---|
| Walk-in door | at least 6 wide × 9 tall (7 × 10 on phone-heavy paths); frame 0.4–0.6 thick |
| Vehicle door (hangar, depot) | tank width + 4 on each side, height + 4 |
| Interior ceiling | at least 12, prefer 14–16 |
| Room | at least 16 × 16 floor for anything the camera enters |
| Corridor | at least 8 wide |
| Stair | rise ≤ 1 per step, tread ≥ 1.5; or a wedge ramp with rails |
| Railing / parapet | 3–3.5 tall |
| Window sill | 3 above floor; window 3–4 tall |
| Crate | 2–3 cube; ammo box 1.5 × 0.8 × 0.8; jerry can 1 × 1.6 × 0.5 |
| Sandbag | about 2 × 0.8 × 1, laid in courses of 2–3 |
| Jersey barrier | about 8 long × 3 tall, sloped profile |
| Street lamp | 12–14 tall |
| Guard tower | platform 12–16 up, railing, roof, ladder |

Put one scale reference near every hero object (a crate beside a tank, a door on a hangar, a guard at a gate). It is
how the eye judges size.

### 2.8 Modular kits
From the Environmental Art curriculum ("Design modular kits") and the 3-lane polish video:
- A kit is a small set of pieces that snap together into many buildings. In our code a "kit" is a **builder
  function** that takes a size and emits pieces (wall segment, corner, door bay, window bay, roof edge, trim run).
- **Consistent pivots and grid.** Every piece has its pivot at the same place (lower front corner) and sizes that
  are multiples of the smallest piece (the curriculum uses 5 × 5 as the base and 15 × 5 as the largest). Pick a
  WAR EMPIRE grid (4 studs for walls, 1 stud for trims) and stick to it so pieces never clash when rotated.
- **Name the sub-pieces** (`Wall`, `UpperTrim`, `LowerTrim`, `DoorFrame`) so a later job can change one layer's
  colour, collision or shadow setting without rebuilding the building.
- **Reuse beats variety.** Five shapes rearranged, recoloured and rotated look richer than twenty unique ones, and
  they are cheaper (§6). "The human brain is excellent at recognizing patterns": break patterns with rotation,
  small colour shifts and a different prop at the end of each row, not with new shapes.
- **Covering pieces hide bad joins.** Where two kit pieces don't meet cleanly, put a support column or pilaster over
  the seam (3-lane polish video). Fix z-fighting (two faces in the same plane) by offsetting one by 0.05 stud or
  removing it.

### 2.9 WAR EMPIRE examples

**Base buildings (barracks, command centre, depot, armory).** Plinth + two-tone walls + trim at the floor line and
parapet + recessed door with frame and step + 2–4 framed windows + roof clutter (vent, AC, antenna) + sandbags or
crates at one corner + one base-accent stripe. The walk-in shells go through `HollowBuildingBuilder`/`Interiors`.
Respect the base part cap (2,700 at L5).

**Plaza buildings** (`PlazaBuildingsConfig`). A shop front is the most-seen facade in the game. Ground floor:
bigger openings, awning or canopy, sign board, one light. Upper floors: repeated window bays with sills. Vary the
roof line across the row. Keep the arch/plaza landmark visible down every approach (a vista point, §4).

**Road checkpoint** (JOB 37). The job file already lists the right layers: plinth, framed windows with mullions,
door with frame and handle, roof overhang with fascia and AC unit, interior desk silhouette, one warm light
(shadows off), a proper boom gate (cabinet, hinge, counterweight, 5–6 red/white bands, rest post), 2-course
sandbag Ls, a braced tower with searchlight, a staggered jersey-barrier chicane, razor-wire posts and rails,
floodlights, a fictional-emblem flag, short signs, stacked crates and ammo boxes. At most ~110 parts. That is the
standard every POI should reach.

**Tanks and vehicles.** All original designs.
- Silhouette: low wide hull with a sloped front, turret offset slightly back, a long barrel with a muzzle end
  (a slightly wider short cylinder), a mantlet block where the barrel meets the turret.
- Layers: tracks as a dark block with 5–7 road-wheel cylinders showing, side skirts, fenders; turret hatches,
  stowage boxes on the turret sides and rear, tow hooks, a jerry can, headlight housings, an antenna (thin
  cylinder), exhaust grille on the rear deck.
- Colour: one body tone + a darker tone on lower hull and skirts, near-black tracks and wheels, metal materials.
  Faction markings are fictional emblems only.
- Physics: only the hull (and maybe the turret) collides; all decor parts `CanCollide = false`, `Massless = true`,
  `CastShadow = false` if under ~4 studs, welded to the chassis. No real tank names or recognisable real designs.

**Guards and soldiers.** Rigs from `RigBuilder` with the client `RigAnimator` (idle, walk, aim, shoot, hit,
death; never T-pose). Readable gear silhouette: helmet, vest, pack, weapon. A consistent fictional faction colour so
players tell enemy from friendly at a glance. Behaviour patterns are in §7.

---

## 3. Interiors you can walk into

- **Openings sized for the camera** (§2.7). Test the doorway with the camera behind the character on a phone.
  If the camera clips through a wall or snaps in, the door is too small or the room too tight.
- **Floor and ceiling differ from the walls.** The environment polish video built a temple in-Studio (no meshes)
  and made it read by giving the floor and ceiling different materials from the walls. Do the same: tile or
  concrete floor, a darker ceiling, walls with a lower band.
- **Indoor lighting is ambient, not sun.** Docs: an area counts as "indoor" when most of the sky above it is covered.
  Indoors is lit by `Lighting.Ambient` and local lights. Add **one** light per room (a `PointLight` or `SurfaceLight`
  on an invisible or fixture part, `Shadows = false`, limited `Range`), warm for living spaces, cool white for
  hangars and ops rooms. Count it in the per-base light cap (40).
- **Furnish for silhouette, not count.** A desk, a chair, a map table, a locker row, a rack of crates is enough.
  Put 1–2 story details (a chair knocked over, papers on the floor, a repair in progress with a ladder and exposed
  wiring) so the room "explains itself" (3-lane polish video).
- **Keep interiors off the collision and query path where you can:** small furniture `CanCollide = false`,
  `CanQuery = false`, `CanTouch = false`. Walls and cover stay collidable and queryable (bullets must hit them).
- **Stream as one unit.** A walk-in building is a `Model` with `ModelStreamingMode = Atomic` so the roof doesn't
  arrive after the walls (client-server video: "imagine a house streaming in incrementally"). Don't use
  `Persistent` for looks (docs: persistent is only for the rare parts a client script must always have).
- **Glass**: one pane, `Transparency` 0.3–0.5, never two panes in line of sight of each other (overdraw, §6).

---

## 4. Level design for bases, plaza, roads and POIs

From the greybox and 3-lane map videos:
- **Vista points and landmarks.** Every approach should show one clear goal: the plaza tower, a base's command
  centre, a checkpoint's searchlight tower. A landmark is a one-off shape nobody else has; don't reuse it.
- **Guide with light and colour, not arrows.** Warm lights and saturated accents pull the eye; fire and red mark
  danger. The one active objective marker is the only `AlwaysOnTop` label (CLAUDE.md).
- **Flow and trip length.** Paths shouldn't be a slog. Any core-loop trip over 30 s on foot needs sprint, vehicle
  or recall (CLAUDE.md). No fast travel.
- **Sight lines and cover.** Open fights go to whoever clicks first. Break long sight lines at fight spots with
  cover (sandbag Ls, pillars, barriers, parked trucks) so players can push, retreat and flank. The checkpoint's
  staggered barriers do this on a road.
- **Loops.** Give every fight area at least two ways in, so attackers can flank and defenders can reposition
  (applies to base breaches in JOB 38).
- **Props never block movement.** "A piece of cover one or two studs too long and blocking a natural path could be
  hugely detrimental." Walk every route after placing props, and drive a tank through every road gate.
- **Foreground vs background detail.** Foreground (what players touch) gets the full layer treatment. Background
  (outside the playable area: distant ridges, buildings beyond the fence) gets big cheap shapes plus atmosphere haze
  to sell scale. Blend where the player can get close.
- **Contain the playable area** with believable edges (cliffs, fences, dunes), not invisible walls in open ground.
- **Symmetry for PvP fairness.** When two sides fight over a spot, the time to reach it should be about equal.

---

## 5. Lighting and atmosphere presets

WAR EMPIRE already has the plumbing: `WorldAtmosphere` + `WorldConfig.Atmosphere.Presets` ("V2", "Classic") +
`LightingConfig` (day cycle, colour correction), and `NightLights`. **Change looks through those configs, never with
new ad-hoc `Lighting` writes** from other services. Remember Roblox hides `Fog` while an `Atmosphere` exists.

How each Lighting property behaves (Lighting docs + the lighting/terrain video):
- `EnvironmentDiffuseScale` / `EnvironmentSpecularScale`: how much ambient and reflected light comes from the sky.
  Near 1 = more natural. When they are high, keep `Ambient`/`OutdoorAmbient` darker or the scene washes out.
- `OutdoorAmbient` tints everything under open sky; `Ambient` tints indoors. Set `Ambient` a little brighter than
  you think so interiors aren't black.
- `Brightness` is direct sun strength (low = cold, high = hot day). `ExposureCompensation` slightly negative
  (about -0.1) adds contrast in shadows.
- `ColorShift_Top` warms sun-facing surfaces; `ColorShift_Bottom` (a darker copy) tints the shaded side.
- Move the sun with `GeographicLatitude` plus a small `ClockTime` change, so the sun sits where you want it
  (behind a landmark, over the dunes) while it is still "day" for the lighting settings.
- `LightingStyle = Realistic` is the most advanced look; `Soft` is the flat retro look. `PrioritizeLightingQuality`
  chooses whether shadows or view distance degrade first on low quality.

Starting points (tune on a phone at Graphics Quality 3, then put the numbers in the preset config):

| Preset | Sun / time | Colour | Atmosphere | Post |
|---|---|---|---|---|
| **Desert day** (default play) | high sun, Brightness ~3 | OutdoorAmbient warm grey-sand, ColorShift_Top pale warm | Density ~0.3, Offset ~0.2, warm dusty Color/Decay (no blue below the horizon, as V2 does), Haze 1–2, low Glare | Bloom ~0.3–0.5, ColorCorrection Saturation ~+0.05, SunRays low |
| **Golden hour** (events, menus) | sun low over the dunes via Latitude | ColorShift_Top orange-yellow, Bottom a darker copy, OutdoorAmbient pink-orange | Density ~0.3, pinkish Color/Decay, Haze ~2 | Bloom ~0.5, small warm tint, SunRays intensity ~0.05 / spread ~0.04 |
| **Night ops** | ClockTime night | Ambient and OutdoorAmbient dark blue-grey but readable | lower Haze, cooler Decay | NightLights on (few, shadows off), no Blur |

The golden-hour row follows the Roblox Learn lighting/terrain video recipe (Diffuse/Specular 1, sun ~4, exposure
-0.1, fog far away, pink atmosphere, bloom 0.5, low sun rays), adapted to a combat game. **Don't use `BlurEffect`
in gameplay** (the video uses blur for a cozy map; in a shooter it hurts target reading). Dynamic `Clouds` must be a
child of `Workspace.Terrain`, not Lighting; keep Cover moderate and Density low if the skybox already has clouds.

Local lights: few, `Shadows = false`, capped `Range`/`Brightness`, no neon floods, no constantly moving big lights
(the performance video shows moving lights cost CPU). A searchlight sweep runs on the client only and stops when far
away (JOB 37 pattern). Every light counts against the 730 total / 40 per base cap.

Particles (smoke, dust, sand): one texture reused with different settings (the polish video made smoke, mist and
blowing sand from the same particle). Keep `Rate` low, `Lifetime` short, and cap per site. Docs: changing
ParticleEmitter properties at runtime is expensive; set them once.

---

## 6. Keeping performance good while adding detail

Budgets are in CLAUDE.md §1 and are hard caps. A detail pass that breaks the budget is not done.

**Draw calls and instancing** (performance video + Improve performance doc):
- Draw calls matter more than triangles. A pro budget quoted in the video: about 500 draw calls and 500k triangles
  per view, tested on an old phone. See them with Shift+F2 (Render Stats).
- The engine batches identical meshes with identical textures/materials into one draw call. For us: reuse the same
  **store prop asset ids** (never import the same model twice under two ids), the same decal image ids, the same
  `MaterialVariant`s. Spend the saved draw calls on hero objects.
- Decals, textures and particles don't batch well. Count them.

**Per-part settings (Environmental Art curriculum, "Set physics and rendering parameters"):**

| Property | Rule |
|---|---|
| `Anchored` | true for everything static. Only doors, vehicles and deliberate physics props are unanchored. |
| `CanCollide` | false for decor players never stand on or hide behind (trims above head height, clutter, foliage, antennas, vehicle decor). |
| `CanTouch` | false unless a `Touched` handler needs it (touch state is checked every frame). |
| `CanQuery` | false for pure decor. **Keep true on anything bullets, raycasts or line-of-sight checks must hit** (walls, cover, sandbags, barriers), or shots and NPC LOS go through them. |
| `CastShadow` | false on small parts (under ~4 studs in every axis), distant parts, moving decor, interior clutter. Keep on big shapes near the player. |
| `CollisionFidelity` (meshes/unions) | `Box` for walls and blocks, `Hull` for trims people might jump near, `Default`/precise only where the shape matters (a doorway you walk through). |
| `RenderFidelity` (meshes) | `Automatic` or `Performance` for foliage and clutter; `Precise` only when needed. |
| `Transparency` | 0 or 1. Partial only for glass, and never several transparent layers overlapping in view (overdraw). |
| `DoubleSided` (meshes) | only for thin planar foliage. |

**Streaming** (the game runs under StreamingEnabled):
- Never assume a workspace part exists on the client; never `WaitForChild` without a timeout (CLAUDE.md).
- `StreamingMinRadius` must be well below `StreamingTargetRadius` ("when everything's a priority, nothing is").
- Buildings and kits are Models with `ModelStreamingMode = Atomic`. `Persistent` only when a client script truly
  needs the part, never for visuals. Distant humanoids stream out automatically, which helps with guard counts.
- For big world models, `LevelOfDetail = SLIM` (lightweight distant meshes) or `StreamingMesh` (impostor, only
  worth it with a target radius of about 1,000+ studs) keep a far silhouette instead of popping. Trial this on one
  model first and measure before rolling it out.

**Scripts, physics, lights:**
- No per-frame scans or raycasts. Event-driven first; if a loop, throttle it (UI ≤ 10 Hz). `RenderStepped`/
  `PreRender` only for camera and tight visuals.
- Fewer unanchored parts; the number of simulated parts is the most common physics cost. Consider adaptive
  physics stepping.
- Moving lights and many shadow-casting lights are expensive. Disable lights by room or distance where you can.
- Use `debug.profilebegin/profileend` tags around new systems and check them in the MicroProfiler.
- Don't micro-optimise early; follow the budgets and measure on a mid-range phone.

**Detail without the cost, in practice:**
- Merge what reads the same: one long trim part instead of ten short ones; one sandbag course block with a
  cylinder top instead of twenty bags where the player never gets close.
- Detail density follows attention: the gate, the door and the first 30 studs of an approach get the most parts.
- Log the count like JOB 31/37 (`[WorldDetail] <Kit> extra=N`) and keep it inside `WorldDetailConfig.MaxExtraParts`.
- The phone LOW tier QualityGovernor hides small decor; tag or size decor so it is eligible.

---

## 7. Server-authoritative combat and movement

WAR EMPIRE's rule (CLAUDE.md §2): **the server decides**; clients request. Docs and videos give the patterns:

**Combat hits (Client-server boundary doc, "Weapon targeting"):** the client sends *where it fired from and what it
thinks it hit*, never "damage player X". The server checks:
1. the shot origin is near the shooter's character on the server (with latency tolerance);
2. the reported hit position is close to where that part really is on the server;
3. no **static** geometry blocks the line between them (raycast against world geometry only, so latency doesn't
   reject fair shots);
4. fire rate (last shot time), ammo count, not reloading/sprinting, target alive, target is an enemy (teams,
   raid rules, NPC groups).
Plus: validate types and ranges of every remote argument (reject NaN and inf), and **rate-limit** every
client-triggered action on the server (token bucket), including ProximityPrompts and Touched. Never rely on a
client-side limit alone. The server never trusts a target id (CLAUDE.md).

**Effects vs state (client-server video):** clients do the pretty part (tracers, muzzle flash, debris, ragdoll
bits, random ejection), sent over `UnreliableRemoteEvent`; the server keeps state (health, loot, rewards,
ownership). In the video's destructible crate, the client plays debris, tells the server, and the server decides
loot and replicates the break. Different clients seeing slightly different debris is fine.

**NPC guards (guard NPC state machine video):** build guards as a small state machine, not one big script:
- States: `Idle` (at post) → `Patrol` (waypoints, tagged with CollectionService) → `Alert/Attack` (target in
  AggroRange with line of sight) → `Return` (leash exceeded or no target). Each state has `onEnter`, `onStay`,
  `onExit`; transitions are small test functions (`isPlayerNearby`, `isIdleTimerDone`, `isBeyondLeash`).
- A shared context table (the "blackboard") holds target, home, current waypoint, timers.
- Tick on the server from one Heartbeat loop for all guards, throttled (not one loop per guard). Stay on the
  existing `CombatService.SpawnNPC` / CombatNPC path (target pick, LOS, hit-chance rolls, damage caps).
- Guards only wake for players the feature flag is live for (owner-first), and group-respawn only when a player
  is near and never on top of one (JOB 37).

**Movement:** character and vehicle speed are server truth. Nothing but `MonetizationService` writes WalkSpeed
(codebot_v126). No teleports/`PivotTo` in marches, no fast travel. Vehicles keep physics owned or validated so a
client can't report impossible positions.

**Roblox Server Authority (beta), for the future:** `Workspace.AuthorityMode = Server` makes the server own all
character movement with client prediction and rollback, so speed and fly hacks stop working. It also turns on and
requires `StreamingEnabled`, `NextGenerationReplication`, `PlayerScriptsUseInputActionSystem`,
`SignalBehavior = Deferred` and `UseFixedSimulation`. Core logic then runs in a ModuleScript loaded on both client and
server, inside `RunService:BindToSimulation`. Only physics properties and **attributes on predicted instances** roll
back (max 64 attributes, 50-char names/strings); plain Lua variables are not synced. Effects must be able to "undo"
a mispredicted event. This is a big engine switch (deferred signals alone can break old code), so it is **not** a
build-job change: only an owner-approved spike on its own branch, behind a flag, with the whole test suite.

**Top-down / command camera (top-down camera video), if we build one for army orders:** `CameraType = Scriptable`,
one bound RenderStep update, a clean `disable()` that unbinds, restores the default camera and disconnects
everything, Input Action System bindings for touch, mouse, keyboard and gamepad, and on-screen buttons for touch
rotate. It is a view only; the orders it issues still go through server-validated remotes.

---

## 8. UI polish rules

From the UI/UX design doc and the UI styling video, plus our phone rules (CLAUDE.md §1):
- **Hierarchy of information:** show what the player needs *right now* first (health, ammo, current objective,
  cash). Contextual buttons swap by situation (on foot vs driving vs flying vs in a menu) instead of showing all.
- **Attention tools in moderation:** colour (bright for key actions, muted for the rest), size, space (padding),
  proximity (group related things), movement (small animation only for the one thing you want noticed).
- **Visual language and conventions:** one button style per role (primary, secondary, danger), X to close, grey =
  unavailable, lock icon = not unlocked yet, green = health. Headers bigger and bolder than body; legibility first.
- **Consistency through tokens:** colours, fonts, corner radius and stroke come from one shared theme/token table,
  never hand-typed per screen (the styling video's point: "every time I use this token it refers to the same
  colour"). Roblox's StyleSheet/tokens system is in beta; follow whatever theme config the HUD already uses.
- **No overlaps, clean layout:**
  - Use `UIListLayout`/`UIGridLayout` + `UIPadding` + `AnchorPoint` + scale sizes, not stacked absolute offsets.
  - `AutomaticSize` or `UITextSizeConstraint` so text never spills out of its box; `TextWrapped` for long strings.
  - A clear `ZIndex`/`DisplayOrder` plan: HUD < panels < modal < toast. Only one modal at a time.
  - Respect reserved zones: thumbstick area (left 40 % × lower ⅔), 16 px around jump, top-bar pills.
  - Tap targets ≥ 44 real px (≥ 64 in code under UIScale 0.70), text ≥ 14 real px (≥ 20 in code).
  - No screen-covering pop-ups in combat or driving; one message at a time.
  - Never name a key or say "click" to a phone player.
- **Verify with the HUD harness** at phone, owner, desktop, 800×360 and 1180×820 viewports, with panels full of
  data, before calling UI done.

---

## 9. Workflow for AI coders (from the owner's key video)

"How to start coding with AI on Roblox (MCP)" is about the tool setup, and its lessons apply to how we work:
- **Git is the safety net.** Commit small, known-good steps so any bad change can be reverted with one command.
  Never lose other workers' uncommitted changes (no stash/reset/discard of files that aren't yours).
- **Scripts live in files and sync to Studio** (Rojo here). Server logic in ServerScriptService, shared modules in
  ReplicatedStorage, client scripts under StarterPlayerScripts.
- **Use the Studio MCP connection to check your work:** read the game tree, list what a builder produced, start a
  playtest and read the output, instead of assuming.
- From the companion "make a game using AI" interview: plan first, split the job into testable chunks, stop at each
  chunk and test, and let the owner change direction between chunks. The AI still needs game-design thinking (for
  example health bars that show at range so hits read).

---

## 10. Build job recipe (copy into your plan)

1. Read the job file, `WorldDetailConfig`, the builder you are changing and its current part count.
2. Greybox pass: silhouette, footprint, heights, openings, cover. Playtest at 844×390 on foot and in a tank.
3. Detail pass by layer (§2.2), fixed-size trims and bevels (§2.3), 2–3 tones per material, seeded variation.
4. Interiors (§3) if enterable. Lights (§5) within caps, shadows off.
5. Performance pass (§6 table) on every new part; log `extra=N`; stay under the caps.
6. Combat/NPC changes follow §7; UI follows §8.
7. Run the detail checklist (§11), the CLAUDE.md §3 checks, and list what the owner must test on his phone.

---

## 11. Pre-ship detail checklist (every build job)

Tick every line in your DONE reply or say why it doesn't apply.

**Read as real**
- [ ] Greybox was playtested before detailing (on foot and by vehicle where relevant).
- [ ] Silhouette: top line broken (roof clutter, parapet, overhang, mast) and footprint broken (annex, porch, steps).
- [ ] Every object sits on a plinth, kerb or ground contact; nothing floats, nothing clips through the ground.
- [ ] Trims on wall bases, floor lines and roof edges; openings have frames, sills or lintels.
- [ ] Visible hard corners chamfered or softened; bevel/trim sizes are fixed studs, not scaled.
- [ ] 2–3 tones per material; repeated props vary (seeded ±5 % colour, rotation); no flat single-colour objects.
- [ ] Materials match the object; saturated colour only on things players act on.
- [ ] A scale reference next to hero objects; doors/rooms sized for the camera (§2.7).
- [ ] 1–2 storytelling details per site.
- [ ] No z-fighting, no gaps at joins (covering pieces over seams).

**Rules**
- [ ] `PreferMesh` untouched (OFF); no `WE_Building*` attribute touched; no `Store_*` names; clear of
      `Workspace.WorldFill.StoreProps`.
- [ ] Nothing real-world or franchise: no real vehicle/weapon names or designs, insignia, brands, other games' assets.
- [ ] Flags are Textures/Decals with fictional emblems (or the player's own cosmetic nation flag).
- [ ] No fast travel, no teleport/PivotTo in marches.
- [ ] Behind the job's config flag; OFF builds the old version exactly.

**Interiors, lighting, level**
- [ ] Enterable rooms: door ≥ 6 × 9, ceiling ≥ 12, camera tested inside on a phone.
- [ ] Floor and ceiling materials differ from walls; one light per room, `Shadows = false`.
- [ ] Walk-in buildings are Atomic Models; nothing Persistent for looks.
- [ ] Lighting changes go through `WorldConfig.Atmosphere` / `LightingConfig`; checked in day, dusk and night.
- [ ] Routes walked after props were placed; no prop blocks a path or a vehicle gate; cover breaks long sight lines.

**Performance**
- [ ] Part count logged (`[WorldDetail] <Kit> extra=N`) and inside `MaxExtraParts` and the CLAUDE.md caps.
- [ ] All static parts anchored; small/far parts `CastShadow = false`; decor `CanCollide`/`CanTouch`/`CanQuery` off.
- [ ] Cover, walls and barriers keep `CanQuery = true` (bullets and NPC line of sight hit them).
- [ ] Transparency is 0 or 1 except single glass panes; no stacked transparent layers.
- [ ] Lights, neon and SurfaceGuis inside caps; decals reuse image ids; particles capped.
- [ ] No per-frame scans, no `WaitForChild` without timeout, loops throttled.
- [ ] Checked at Graphics Quality 3 / mid-range Android for frame drops at the new site.

**Combat and UI (if touched)**
- [ ] Server validates origin, hit position, static LOS, fire rate, ammo, team, alive; rate-limited; no target ids
      trusted; NaN rejected.
- [ ] Effects on the client via `UnreliableRemoteEvent`; state and rewards on the server.
- [ ] NPCs use a state machine with leash, LOS and hit chance; one throttled server loop.
- [ ] UI: no overlaps at all 5 viewports (harness run), tap targets ≥ 44 real px, text ≥ 14 real px, reserved zones
      clear, tokens/theme colours used, one modal at a time.

---

## 12. Sources

Text actually retrieved on 2026-09-30. Videos: transcripts only (YouTube captions via `yt-dlp`, or
`youtube-transcript-api` where yt-dlp was rate-limited). Nothing here comes from watching the videos.
Docs: the official `Roblox/creator-docs` repository, which is the source of create.roblox.com/docs.

### Videos (Roblox Learn channel)

1. **How to start coding with AI on Roblox (MCP)**, the owner's key video. https://youtu.be/v8r1d80DxOY
   (title, description and full transcript). Setup video: install an editor (Cursor/VS Code), Studio and Git; use
   Git as a safety net to revert bad AI changes; Script Sync ties files to Studio (Rojo for file workflows); Studio's
   MCP server lets the agent read the game tree, create objects and run playtests to verify its own work; commit the
   known-good baseline. Description links the WaveSurvival starter and the companion interview.
2. **How to make a game using AI on Roblox**. https://youtu.be/XsY8xhluuZM. Plan first, break work into
   testable chunks, stop and test at each, iterate by conversation; AI isn't magic, you still do game design; code
   quality needs review as the project grows.
3. **How to start using Server Authority on Roblox** (jetpack). https://youtu.be/-DJy_CfK2Vk.
   `Workspace.AuthorityMode = Server` (auto-enables streaming and next-gen replication) makes character motion
   secure; shared module run on client and server; logic in `RunService:BindToSimulation`; input actions under the
   player replicate to the server; only attributes on predicted instances and physics roll back; the client gets
   instant feedback and the server gives the real result (coins can't be hacked).
4. **How Server Authority works on Roblox**. https://youtu.be/hb14MxhZiOU. Clients send only inputs; server
   simulates; client-side prediction hides latency; other players are always slightly in the past; lerp smoothing
   hides corrections; removes speed/fly/jump hacks and allows shared physics objects.
5. **How client-server architecture works on Roblox**. https://youtu.be/ougjxNrDvQo. The server owns
   everything; clients see a subset (streaming); tag parts and use CollectionService instead of scripts in models;
   event-driven code; remote events; client does debris/visuals, server does state and loot; mark models Atomic
   under streaming; server authority for competitive games; gates: server sets an attribute, client tweens.
6. **How to make guard NPCs using a state machine**. https://youtu.be/nlVpAZEkxgo. Context blackboard,
   states with enter/stay/exit, transitions with test functions, Heartbeat tick; walker → patroller (random
   waypoints + idle) → defender (attack when a player is near).
7. **How to make a top down camera system (MOBAs, RTS)**. https://youtu.be/qx7T7EDPqPA. Scriptable camera
   bound to render step, clean disable, Input Action System bindings for all devices, touch buttons,
   click-to-move and free-pan variants.
8. **How to graybox on Roblox**. https://youtu.be/T--CNfkfBBQ. Organise folders first; primitives for props
   and terrain; focus on silhouette; vista points and landmarks; colour and light for guidance; doors and ceilings
   oversized for the camera; short, interesting paths; environmental storytelling.
9. **How to customize lighting and edit terrain on Roblox**. https://youtu.be/XgkmKxyRuWE. Light before
   detailing; Diffuse/Specular scale, Ambient vs OutdoorAmbient, Latitude + ClockTime to place the sun, Brightness,
   ExposureCompensation, ColorShift; Atmosphere; Clouds under Terrain; Bloom/ColorCorrection/SunRays; terrain
   voxels are 4 studs; terrain is never flat; blend material transitions.
10. **How to polish your environment on Roblox**. https://youtu.be/4kasDMSDvcQ. Greybox → finished props
    (bevels, inset engravings); random colour variation (25 %/25 %) on repeats; hide terrain seams; foreground vs
    background detailing; not everything needs a mesh (in-Studio temple with distinct floor/ceiling materials);
    SurfaceLight for warm interiors; one particle reused for smoke, mist, sand.
11. **How to design a 3-lane FPS map on Roblox**. https://youtu.be/fGaiAvh7Q-4. Equal travel times, sight
    lines broken by cover, verticality, non-90° angles, loops for flanking, props must never block paths, gameplay
    before visuals.
12. **How to polish a 3-lane FPS map on Roblox**. https://youtu.be/-Q9mg1hyqMY. Materials first, colour-code
    sides, fix z-fighting and gaps, trim at top and bottom of walls, covering pieces for bad corners, alternate wall
    textures, modular doors/windows, lighting with accent variation, break pattern recognition, non-functional doors,
    storytelling props, fake exterior city to sell scale, reduce visual noise for young players.
13. **How to optimize performance on Roblox**. https://youtu.be/VDO_amtWfDw. Draw calls and batching (reuse
    the same mesh), ~500 draw calls / 500k triangles budget, streaming radii, humanoids stream out, sparing
    persistence, CPU culprits: per-frame scripts, unanchored physics, shadows and moving lights; profiler tags.
14. **Manage level of detail settings on Roblox**. https://youtu.be/Wwj8EkMWFhI. RenderFidelity; streaming LOD
    options: disabled, impostor StreamingMesh (≥ 1,000-stud radius), SLIM meshes; Persistent only for gameplay.
15. **How to style your UI on Roblox**. https://youtu.be/_k1ea0OIKaU. Style sheets, rules per class and state,
    tokens for shared colours, themes, tags for variants.
16. **How to not hate editing your 3D models on Roblox** (re-import). https://youtu.be/uElRpN1ZQ-4. Re-import
    updates a mesh in place and keeps colours, welds and hinges (only relevant to owner-approved meshes).
17. **How Procedural Models work on Roblox**. https://youtu.be/gu1iPJmyMgA. Code-generated geometry from a
    box; "27-slice" keeps corners and bevels fixed-size when resized; no runtime cost beyond the output geometry;
    pieces are the key to quality.

### Docs (create.roblox.com/docs, read from the Roblox/creator-docs repo)
- Environmental art curriculum: https://create.roblox.com/docs/tutorials/curriculums/environmental-art
  (greybox-your-environment, develop-polished-assets: trim sheets and modular kits, assemble-an-asset-library:
  physics and render parameters, construct-your-world, optimize-your-experience: cull duplicates, geometry,
  layered transparency).
- Materials and MaterialVariant: https://create.roblox.com/docs/parts/materials
- PBR textures (SurfaceAppearance): https://create.roblox.com/docs/art/modeling/surface-appearance
- Solid modelling: https://create.roblox.com/docs/parts/solid-modeling
- Textures and decals: https://create.roblox.com/docs/parts/textures-decals
- Lighting properties: https://create.roblox.com/docs/environment/lighting
- Improve performance: https://create.roblox.com/docs/performance-optimization/improve
- Design for performance: https://create.roblox.com/docs/performance-optimization/design
- Instance streaming: https://create.roblox.com/docs/workspace/streaming
- Server authority: https://create.roblox.com/docs/projects/server-authority and
  https://create.roblox.com/docs/projects/server-authority/techniques
- Security, client-server boundary: https://create.roblox.com/docs/scripting/security/client-server-boundary
- UI/UX design: https://create.roblox.com/docs/production/game-design/ui-ux-design
