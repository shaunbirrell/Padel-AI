# Publish WAR EMPIRE for mobile (Studio)

Studio on the laptop already opens `C:\Users\laura\Downloads\WarEmpire-PERF.rbxlx`.

1. In that Studio window: **File → Publish to Roblox** (or **Publish to Roblox As…** for a new experience).
2. Create **WAR EMPIRE** (or overwrite your existing place).
3. Creator Dashboard → experience → **Configure** → enable **Enable Studio Access to API Services** (DataStores).
4. Optional: set experience to **Private** / friends-only for playtest.
5. On phone Roblox app: open the experience from your Profile → Creations / Shared, or the place URL `https://www.roblox.com/games/<PlaceId>`.

Open Cloud alternative (agent can run once secrets exist):

```bash
export ROBLOX_OPEN_CLOUD_API_KEY=...
export ROBLOX_UNIVERSE_ID=...
export ROBLOX_PLACE_ID=...
./tools/publish-opencloud.sh
```

Product IDs stay 0 (no real charges). Add your UserId to `AdminConfig.UserIds` before relying on admin commands.
