# Third-party notices

WAR EMPIRE ships only its own code and Roblox-platform content, plus the items below. This file lists every vendored
open-source library and every external Roblox asset id the W2 combat pass (and the W1 audio pass before it) uses,
with its terms. Keep it in the same commit as any change to these items.

Written by W2 CC-3 on 2026-09-24. `docs/ASSET_LICENSES.md` covers the VisualAssetConfig model / mesh ids.

## 1. Vendored libraries (MIT)

All three come from **RbxUtil** by Stephen Leitnick: <https://github.com/Sleitnick/RbxUtil>
Branch `main` @ `31f9120fca021e3dec275b42bc7047d626962082`, fetched 2026-09-24 from `raw.githubusercontent.com`.
Licence: MIT, "Copyright © 2025 Stephen Leitnick". The full licence text sits next to each copy (`LICENSE`).

| Library | Version | Repo path | Our copy | Local changes |
|---|---|---|---|---|
| Trove | 1.8.0 | `modules/trove/init.luau` | `src/ReplicatedStorage/Shared/Vendor/Trove/init.luau` | header comment only |
| Spring | 1.0.0 | `modules/spring/init.luau` | `src/ReplicatedStorage/Shared/Vendor/Spring/init.luau` | header comment only |
| Shake | 1.1.0 | `modules/shake/init.luau` | `src/ReplicatedStorage/Shared/Vendor/Shake/init.luau` | `--!strict` + 5 type annotations (listed in its header); behaviour unchanged |

Use: `Client/Modules/CameraFx.luau` (Spring = recoil, Shake = blast / hit shake). Trove is vendored for the W2 client
modules' clean-up needs (not required by the W2 code today).

## 2. Roblox-owned animations (creator Roblox, User 1)

Played only on the local player's Animator (`HudConfig.CombatFx.Anims`; 0 disables). Only animations owned by Roblox or by
the game owner play in a game, so these are the only kind we use. Source: `docs/ASSET_SHORTLIST.md` §3.4.

| Use | Asset ID | Store name |
|---|---|---|
| Rifle / carbine / SMG / shotgun / long rifle hold | 3972151362 | RifleHold |
| Pistol hold (stand-in) | 507768375 | R15Tool |
| Launcher hold (stand-in) | 3972164452 | NewRifleAim |
| Reload (every gun) | 3972131105 | RifleReload |

## 3. Audio (`src/ReplicatedStorage/Shared/Configs/SoundConfig.luau`)

Sources:
- **[PSE]** Roblox licensed sound library, Pro Sound Effects partner uploads (owner ProSoundEffects, User 7462895450).
- **[APM]** Roblox licensed library, APM Music partner uploads (APMOfficial, User 7462718749).
- **[RBX]** Roblox-owned (the "Light Utility Vehicle" engine sounds).
- **[ENG]** engine files that ship with the Roblox client.

All [PSE] / [APM] audio is free **inside Roblox experiences only**. Do **not** use it in YouTube / TikTok promos: copyright
claims are likely. Nobody has listened to the new combat ids yet; preview each in Studio (Toolbox › Creator Store › Audio ›
paste the id) before a publish.

### 3.1 W2 combat keys (new; played by `Client/Modules/WeaponVisuals.luau`)

| Key | Asset ID | Source | Store name / note |
|---|---|---|---|
| `Weapon.StarterRifle.Fire` | 9113188870 | PSE | "Assault Rifle 2 (SFX)" 9113188870 |
| `Weapon.AssaultRifle.Fire` | 9113188876 | PSE | "Assault Rifle 4 (SFX)" 9113188876 |
| `Weapon.SMG.Fire` | 9113029219 | PSE | "9 Mm Gun Firing 5 (SFX)" 9113029219 |
| `Weapon.Pistol.Fire` | 9117400889 | PSE | "Pistol Single Shots 8 (SFX)" 9117400889 |
| `Weapon.Shotgun.Fire` | 9112912936 | PSE | "12 Gauge Shotgun 101 (SFX)" 9112912936 (preview: may hold 2 blasts) |
| `Weapon.Sniper.Fire` | 9118173988 | PSE | "Rifle Single Shots 3 (SFX)" 9118173988 |
| `Weapon.RocketLauncher.Fire` | 9118592471 | PSE | "Rocket Flare Out 9 (SFX)" 9118592471 |
| `Weapon.Grenade.Throw` | 9114659833 | PSE | "Grenade Pull Pin 2 (SFX)" 9114659833 |
| `Weapon.Reload.Rifle` | 9113104509 | PSE | "Ammo Magazine 3 (SFX)" 9113104509 |
| `Weapon.Reload.Pistol` | 9113104176 | PSE | "Ammo Magazine 1 (SFX)" 9113104176 |
| `Weapon.Reload.Shotgun` | 9112913564 | PSE | "12 Gauge Shotgun 9 (SFX)" 9112913564 (pump) |
| `Weapon.Reload.Launcher` | 9118594324 | PSE | "Rockets Handle 6 (SFX)" 9118594324 |
| `Weapon.Empty` | 9117396530 | PSE | "Pistol Handling 1 (SFX)" 9117396530 (dry fire) |
| `Weapon.Equip` | 9114702107 | PSE | "Gun Grab Hard 1 (SFX)" 9114702107 |
| `Hit.Confirm` | 9119717529 | PSE | "Switch Click On Or Off Toggle Button 1 (SFX)" 9119717529 |
| `Hit.Headshot` | 9119717529 | PSE | same file as Hit.Confirm, higher |
| `Hit.Kill` | 9126073001 | PSE | "Synth Sparkle Tone High Pitch Bell Tone Ding (SFX)" 9126073001 |
| `Player.Hurt` | 9113524237 | PSE | "Body Impact 2 (SFX)" 9113524237, low |
| `Impact.Ground` | 9118768193 | PSE | "Sand Impacts 5 (SFX)" 9118768193 |
| `Impact.Metal` | 9119915230 | PSE | "Tank Impact 1 (SFX)" 9119915230 |
| `Explosion.Small` | 9114086583 | PSE | "Dirt Explosion 4 (SFX)" 9114086583 (grenade, rocket) |
| `Explosion.Large` | 9114554567 | PSE | "Gas Fire Explosion 3 (SFX)" 9114554567 (vehicle wreck) |

`Hit.Headshot` reuses the `Hit.Confirm` file at a higher pitch. The Weapons Kit guns' own Sounds are never used: the
asset loader strips them (they belong to a user and a group, not Roblox).

### 3.2 Earlier keys (W1 audio pass, unchanged by W2)

| Key | Asset ID | Source | Store name / note |
|---|---|---|---|
| `UI.Click` | engine file `rbxasset://sounds/electronicpingshort.wav` | ENG | electronicpingshort.wav |
| `UI.Notify` | engine file `rbxasset://sounds/switch.wav` | ENG | switch.wav (local toasts with no typed key) |
| `Toast.Success` | 9113849492 | PSE | "Coins Or Keys Jingle 6" 9113849492, pitched up |
| `Toast.Reward` | 9113849492 | PSE | "Coins Or Keys Jingle 6" 9113849492 |
| `Toast.Warn` | engine file `rbxasset://sounds/electronicpingshort.wav` | ENG | electronicpingshort.wav, low |
| `Toast.Error` | engine file `rbxasset://sounds/switch.wav` | ENG | switch.wav, low |
| `Cash.Collect` | 9113849492 | PSE | "Coins Or Keys Jingle 6" 9113849492 |
| `Cash.Purchase` | 9113728042 | PSE | "Cash Register 1" 9113728042 |
| `UI.Denied` | engine file `rbxasset://sounds/electronicpingshort.wav` | ENG | electronicpingshort.wav, lowest (failed buy) |
| `Capture.Start` | engine file `rbxasset://sounds/electronicpingshort.wav` | ENG | electronicpingshort.wav ("radio" cue) |
| `Capture.Secured` | 9113849492 | PSE | "Coins Or Keys Jingle 6" 9113849492 (+income), low |
| `Capture.Lost` | 9119236749 | PSE | "Small Explosion 1" 9119236749 |
| `Level.Up` | 9113849492 | PSE | "Coins Or Keys Jingle 6" 9113849492, high |
| `Alarm.Raid` | 9113073742 | PSE | "Air Raid Siren Old Fashioned 1" 9113073742 (ATM being robbed) |
| `Alarm.Base` | 9113073742 | PSE | same siren ("BASE UNDER ATTACK!" banner; its Reroute rule shows it at most once per 60 s) |
| `Alarm.Missile` | 9113073742 | PSE | same siren; 9 s = RaidConfig.Strike MaxFlightSeconds |
| `Music.Base` | 1844397606 | APM | "Military March" 1844397606 (159 s), base theme |
| `Music.Combat` | 1841116989 | APM | "Military March" 1841116989 (63 s), combat layer |
| `Amb.Wind` | 9114057104 | PSE | "Desert Wind Whistley Light Gusts 1" 9114057104 (37 s) |
| `Amb.Surf` | 9119677135 | PSE | "Surf Ocean Wave Impact 1" 9119677135 |
| `Engine.Ground` | 6417138409 | RBX | LUV "Sedan_Loop_Mid" 6417138409 |
| `Engine.Heavy` | 6417179625 | RBX | LUV "Sedan_Loop_Low" 6417179625 (tracked) |
| `Engine.Jet` | 6417165160 | RBX | LUV "Sedan_Loop_High" 6417165160 (placeholder jet whine) |
| `Engine.Heli` | 9113417759 | PSE | helicopter "Rises For Takeoff 2" 9113417759 (swap for a seamless rotor loop after preview) |
| `Engine.Naval` | 6417179625 | RBX | LUV "Sedan_Loop_Low" 6417179625, pitched down (boat motor) |

## 4. Engine textures (particles)

`WeaponVisuals` uses these files, which ship in every Roblox client (checked in client 0.740, `docs/ASSET_SHORTLIST.md` §3.6):
`rbxasset://textures/particles/sparkles_main.dds` (muzzle flash), `…/smoke_main.dds` (dust, smoke), `…/fire_sparks_main.dds`
(metal sparks), `…/fire_main.dds` (explosions). Tracers are plain Beams (no texture).

## 5. Roblox Weapons Kit models (future; NOT loaded today)

Creator Roblox (User 1), Endorsed, free. Terms: the **Roblox Limited Use License** (use inside Roblox experiences only; no
redistribution outside Roblox). These ids are **not loaded while `WeaponConfig.<Id>.VisualAssetId = 0`** (every weapon today);
the Part-kit guns in `WeaponVisuals` are used instead. Setting an id makes the server's `WeaponAssetLoader` load it once, strip
every script and Sound, and share a template; no code change is needed.

| WeaponConfig id | Asset ID | Store name | Tool / child |
|---|---|---|---|
| StarterRifle, AssaultRifle | 4842207161 | Auto Rifle | `AR2` / `AR3` > Model `AR` (owner decision: look-alike call) |
| Pistol | 4842197274 | Pistol | `Pistol3` > Model `Pistol` |
| SMG | 4842212980 | Submachine Gun | `SMG2` > Model `SMG` |
| Shotgun | 4842215723 | Shotgun | `Shotgun2` > Model `Shotgun` |
| Sniper | 4842218829 | Sniper Rifle | `Sniper2` > Model `Sniper` |
| RocketLauncher | 4842186817 | Rocket Launcher | `Rocket Launcher` > Model `RocketLauncher` (owner decision) |
| Grenade projectile mesh | 232379763 (texture 232379808) | MESH_ArmyGuy_Grenade | `WeaponConfig.Grenade.Projectile.MeshId` (0 today) |
| Rocket projectile mesh | 94690081 (texture 94689966) | MESH_BattleGameRocketLauncherAmmo | `WeaponConfig.RocketLauncher.Projectile.MeshId` (0 today) |

The kit's scripts (WeaponsSystem) are never used; the game re-implements the behaviours in its own code.

<!-- Lane A1: append to THIRD_PARTY_NOTICES.md as the next section (after "## 5. Roblox Weapons Kit models"). -->

## 6. Nation flag images (MIT, flag-icons)

The nation flags (`assets/flags/atlas_<group>.png`, 7 images of 1024 x 512, and the optional per-flag PNGs) are rendered by
`tools/gen_nation_flags.py` from **flag-icons** by Panayiotis Lipiridis: <https://github.com/lipis/flag-icons>.

| Item | Value |
|---|---|
| Version | 7.5.0 (npm `flag-icons`, <https://registry.npmjs.org/flag-icons/-/flag-icons-7.5.0.tgz>) |
| Integrity | `sha512-kd+MNXviFIg5hijH766tt+3x76ele1AXlo4zDdCxIvqWZhKt4T83bOtxUOOMlTx/EcFdUMH5yvQgYlFh1EqqFg==` (checked on every run) |
| Upstream fix after 7.5.0 | `flags/4x3/pa.svg` from commit `086f7e97d657358203916dbe84f61c2bccaa81eb` ("Fix white border in Panama flag (#1440)"), sha256 `5e034a8ad127c43b19f52c648fe808160ab4ddb117afa4204772af96566d31bc` |
| Licence | MIT, "Copyright (c) 2013 Panayiotis Lipiridis". Full text: `assets/flags/LICENSE-flag-icons.txt` |
| Local changes | 4x3 SVGs rasterised (cairosvg, 4x supersampled), downscaled to 104 x 78, packed into atlases with an edge-extended gutter; anti-aliasing seams made opaque. The flag designs are not altered. |
| Pins | `assets/flags/atlas_manifest.json` (per-SVG sha256, per-atlas sha256, cell table); `python3 tools/gen_nation_flags.py --verify` |

Use: the player's own nation flag on their base (NationFlag, lane B) and the nation picker (NationController, lane C).
Uploaded to Roblox by the game owner as ordinary images (ids in `src/ReplicatedStorage/Shared/Configs/NationFlagIds.luau`).
The MIT licence allows this use; keep `LICENSE-flag-icons.txt` next to the images.
