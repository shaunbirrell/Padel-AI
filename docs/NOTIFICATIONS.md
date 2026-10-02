# WAR EMPIRE: experience notifications (claude-bud JOB 29, 2026-09-30)

Roblox experience notifications reach a player who has **opted in**, on their phone or desktop, even when they are not
playing. They are sent from **outside the game** through the Open Cloud *User Notifications* API. The game never sends
one itself: it only asks for the opt-in and saves the state a sender needs.

**No API key lives in the game** (owner rule). The sender runs with its own Open Cloud key, kept in that service's own
secret store.

## 1. What we will and won't notify about

**We will notify about** (at most **one** notification per player per UTC day, only after they opted in):
- **Offline earnings full:** their base has earned the 8 h maximum while they were away.
- **Daily streak:** tomorrow's streak reward is ready, and their streak is still alive (a bigger nudge on day 3 and
  day 7).
- **Base raided:** their ATM was raided shortly before they left, so they can take revenge.

**We will not notify** about:
- sales, Robux offers, game passes, shop items or anything paid;
- other players by name, or any kill, nuke, strike or raid message naming anyone;
- countries or nations of any kind;
- anything at night in the player's likely local time (22:00-08:00);
- anyone who has not played for 30 days, or who ignored 3 notifications in a row;
- more than once a day, or the same template twice in a row.

## 2. Opt-in (in game)

**When we ask.** Only at a calm moment:
- **After the tutorial** (finished or skipped): 25 s later, once the Starter Pack offer's slot has passed, and only
  when the player is on foot and has no panel open (`RetentionConfig.Notifications.TutorialDelaySeconds`).
- **From Settings:** the **NOTIFICATIONS** section has a **Game alerts: TURN ON** button, whenever the player wants.

**The automatic ask is never on join and never every join.** Every rule below is checked on the server
(`RetentionService.GoodMoment`):

| Rule | Where |
|---|---|
| Never in the first 60 s of a session | `NotBeforeSeconds` |
| Never during the new-player onboarding hold (before the Command Center) | `WE_Onboarding` |
| At most once per session | `promptedThisSession` |
| Not again for 7 days after a decline | `profile.NotifOptIn.DeclinedAt`, `DeclineCooldownDays` |
| Never again after an accept | `profile.NotifOptIn.Result = "accepted"` |

**How the client asks** (`Client/Modules/NotifOptIn`, the one code path for both entry points):
1. It calls `ExperienceNotificationService:CanPromptOptInAsync()`, then `:PromptOptIn()`.
2. It waits for `OptInPromptClosed`.
3. It calls `CanPromptOptInAsync()` again:
   - `false` = **accepted** (or Roblox's own limit applied);
   - `true` = **declined**;
   - an error or no prompt = **unavailable**.
4. It reports on `RequestNotifOptInResult` (result, source).

**Analytics.** Custom event `NotificationOptIn`, field 1 = `accepted` | `declined` | `unavailable`. The Settings
button adds `_settings`.

**Kill switch.** `RetentionConfig.Notifications.Enabled = false`. `OwnerFirst = true` keeps the ask and the Settings
row to the owner (UserId 470626172) and Studio test players; Code Bot sets it to `false` to launch.

## 3. Creator Hub steps (the owner / Code Bot)

1. Go to **Creator Hub → Creations → WAR EMPIRE → Engage → Notifications** and create a **String** for each template
   in section 5. Paste the text exactly, with its `{parameters}`. Roblox reviews each one before it can be used.
2. Copy each approved string's **Id** into the sender's settings (not into the game).
3. Go to **Creator Hub → Open Cloud → API Keys** and create a key for the sender:
   - access to this experience's **user notifications**, write;
   - an IP allowlist for the sender's host;
   - an expiry.
4. Keep the key only in the sender's secret store. Never put it in this repo or in any game script.
5. Give the sender read access to the DataStore **`WE_NotifyState_v1`**. Grant this with a second, read-only key (the
   Open Cloud DataStore API, `universe-datastores.objects:read` and `list`), plus write access for its own
   `LastSentDay`.
6. Test first with the owner's account only (the owner opts in through **Settings → Game alerts: TURN ON**), then
   switch `OwnerFirst` off.

Check the exact menu names, API paths and scopes against the current Roblox docs before building: Roblox renames
these from time to time.

## 4. The state a sender reads

DataStore **`WE_NotifyState_v1`**, key **`u_<UserId>`**, written **once per leave**, and only for a player whose
`NotifOptIn.Result` is `accepted`. Nobody else gets a record, which keeps DataStore writes low. The write uses
`UpdateAsync` and keeps the sender's own `LastSentDay`.

| Field | Type | Meaning |
|---|---|---|
| `UserId` | number | the player |
| `LastSeen` | os.time() | when they left (the profile's `LastSeenUnix` is also stamped on every save) |
| `OfflineCapFullAt` | os.time() | when offline earnings reach the 8 h cap (`LastSeen + CapSeconds`); 0 = off or no income |
| `OfflineCapCash` | number | what a full 8 h pays at their income when they left |
| `LastRaidedAt` | os.time() | the last time their ATM was raided (`MoneyCollectorService`); 0 = never |
| `StreakDay` | 0-7 | the last login-streak day claimed |
| `NextStreakDay` | 1-7 | the day the next claim gives |
| `LastClaimDay` | yyyymmdd (UTC) | the day of the last streak claim |
| `LastSentDay` | yyyymmdd (UTC) | **written by the sender** after it sends; the game keeps it |

## 5. Templates

Every template body is under 90 characters and device-neutral ("come back", never "tap" or "click"). None names a
player, a nation, a real place or a brand.

| # | String name / text | Parameters | Fires when (the sender's rule) |
|---|---|---|---|
| 1 | **empire_earned**: "Your empire earned {cash} while you were away. Come back and collect it!" | `cash` = `OfflineCapCash` as $ | `now >= OfflineCapFullAt` and the player has not rejoined since `LastSeen` |
| 2 | **streak_ready**: "Day {day} reward is ready. Keep your streak going!" | `day` = `NextStreakDay` | a new UTC day since `LastClaimDay`, and `LastClaimDay` was yesterday (the streak is alive) |
| 3 | **streak_big**: "Day {day} is a BIG reward. Don't miss it!" | `day` = 3 or 7 | like 2, but only when `NextStreakDay` is 3 or 7 (it replaces 2 that day) |
| 4 | **base_raided**: "Your base was raided! Come back and take revenge." | none | `LastRaidedAt` is within 30 min before `LastSeen` (raided, then left); sent 2-6 h after `LastSeen`. A base is empty while its owner is offline, so raids only happen during a session. |

**Launch data.** The launch data is `{"source":"notif","t":"<template>"}`. The game trusts nothing in it; it only
counts in analytics.

## 6. Sender rules

- **Max 1 notification per player per UTC day.** Skip anyone whose `LastSentDay` is today; write
  `LastSentDay = today` after sending.
- **Priority when several are due:** empire_earned, then streak_big / streak_ready, then base_raided.
- **Quiet hours:** 22:00-08:00. The sender has no location, so it uses the hour the player was last seen as a proxy.
- **Stop:** after 3 unanswered sends in a row, or when `LastSeen` is older than 30 days.
- **Scan:** every 15 minutes (`ListKeysAsync`, or an index the sender keeps).
- **Open Cloud:** `POST https://apis.roblox.com/cloud/v2/users/{userId}/notifications`, with the key from step 3.

## 7. What still needs the owner

1. Create the 4 strings in Creator Hub (section 3), and wait for Roblox to approve them.
2. Build and host the sender (it is not part of this repo), with its own Open Cloud key.
3. Test the opt-in on a real phone. Studio cannot show the Roblox prompt; it reports `unavailable` there.
