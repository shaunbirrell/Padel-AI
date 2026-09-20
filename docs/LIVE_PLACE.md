# WAR EMPIRE — Live place (created 2026-09-20)

- **Experience name (fix):** still showing *Untitled Experience* in Studio — rename to **WAR EMPIRE** in Creator Hub / Game Settings.
- **Place ID:** `97112936860418`
- **Universe ID:** `10767159222`
- **Play URL:** https://www.roblox.com/games/97112936860418
- **Live Published:** Open Cloud **versionNumber=28** (2026-09-20 Europe/Madrid) — cash HUD `+` → Shop; jeep drive fix remains from v27
- **Privacy:** Private (owner + friends / shared access only until set Public)
- **Devices:** Computer, Phone, Tablet enabled at create

## After rename / for mobile

1. Creator Dashboard → experience → rename to WAR EMPIRE.
2. Enable **API Services** (DataStores) under Security / Configure.
3. On phone: open the Play URL while logged into the same Roblox account (`shaunie6`), or set Private → Friends if others join.

## Open Cloud republish

```bash
export ROBLOX_OPEN_CLOUD_API_KEY=...
export ROBLOX_UNIVERSE_ID=10767159222
export ROBLOX_PLACE_ID=97112936860418
./tools/publish-opencloud.sh
```
