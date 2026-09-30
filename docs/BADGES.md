# WAR EMPIRE — achievement badges (for Code Bot)

claude-bud JOB 34 (2026-09-30). Every achievement in `src/ReplicatedStorage/Shared/Configs/AchievementConfig.luau` has
a `BadgeId`. They are all **0** today (no badge yet). The server awards a badge only when its id is not 0.

## How to add them (Creator Hub)
1. Go to Creator Hub > Creations > WAR EMPIRE > Associated Items > **Badges** > Create a Badge.
2. Use the name and description below. Upload a 512 × 512 icon; it shows as a circle, so keep the art centred.
   - Icons must be original, generic art: no real flags, insignia, brands or real vehicles.
3. Copy the badge's asset id into `BadgeId = <id>` on the same entry in `AchievementConfig.luau`.
4. Check the badges in a live server:
   - A player who already earned the achievement gets the badge on their next join (it is re-synced once per session).
   - The award runs `UserHasBadgeAsync` first, then `AwardBadge`, with pcall and 3 retries.
   - Badges never award in Studio.

Creator Hub shows any Robux cost for creating a badge before you confirm. Paying it is the owner's call.

## The badges

| Config id | Badge name | Description | Suggested icon |
|---|---|---|---|
| `FirstKillNPC` | First Blood | Defeat your first enemy soldier. | Crossed rifles over a red drop |
| `FirstPlayerKill` | Duelist | Defeat another player. | Two helmets facing each other |
| `FirstUpgrade` | First Building | Build your first base building. | A small bunker with a hammer |
| `Cash10k` | War Chest | Earn 10,000 total Cash. | An ammo crate full of coins |
| `PlayerKills10` | Hunter | Defeat 10 players. | A crosshair with "10" |
| `Cash100k` | Six Figures | Earn $100,000 in total. | A stack of green cash bundles |
| `FirstOutpost` | Outpost Taken | Capture an outpost. | A plain green banner on a tower |
| `Level10` | Sergeant | Reach Level 10. | Three gold chevrons |
| `Cash1M` | Millionaire | Earn $1,000,000 in total. | A gold vault door |
| `CommandCenterMax` | High Command | Upgrade the Command Center to max level. | A radar dish on a tall command tower |
| `PlazaCaptured` | Plaza Conqueror | Capture the Central Plaza. | A plain gold banner over a city square |
| `PlayerKills100` | Warlord | Defeat 100 players. | A skull helmet with a laurel |
| `Rebirth1` | Reborn | Rebirth for the first time. | A phoenix rising from a base |
| `Army50` | Grand Army | Command an army of 50 soldiers. | Rows of soldier silhouettes |
| `FirstNuke` | Doomsday | Launch a nuke from your silo. | A mushroom cloud over a missile silo |
| `Cash100M` | War Tycoon | Earn $100,000,000 in total. | A gold crown on a pile of coins |
| `Rebirth5` | Veteran Reborn | Rebirth 5 times. | A bronze phoenix with "5" |
| `Rebirth10` | Legend Reborn | Rebirth 10 times. | A silver phoenix with "10" |
| `Rebirth20` | Eternal Commander | Rebirth 20 times. | A gold phoenix with "20" |
| `Streak7` | Loyal Soldier | Log in 7 days in a row. | A calendar with 7 ticked days |
| `WeeklyCrown` | Number One | Be #1 on a weekly leaderboard. | A gold crown with "#1" |

Owner and admin accounts earn badges like anyone else. They stay off the leaderboards as before, so they can never
earn `WeeklyCrown`.
