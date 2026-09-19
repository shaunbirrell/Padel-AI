# WAR EMPIRE — Live playtest automation notes

Linux agents cannot run Roblox Studio. Use these Studio-side harnesses after opening
`dist/WarEmpire-PERF.rbxlx` (or Rojo sync) + **Play Solo**.

## Harnesses (command bar)

| Tool | When | What |
|------|------|------|
| `tools/SmokeTest.luau` | After Bootstrap | Remotes + configs + services present; no Give* remotes |
| `tools/BuyPathVerify.luau` | Play Solo client | BUY/Army/Garage remotes, **all product Ids=0**, pad tags, GUIs, PERF flag |

Paste entire file → Command Bar → Enter. Read Output for `PASS` / `FAIL` / `WAIT`.

## Manual live loop (phone / Studio Device Emulator)

1. **PERF** — Output shows MapDressing SKIPPED (`StudioSkipWorldDressing`). Keep it.
2. **BUY** — Stand on own Command Center pad → gold **BUY** → `[WorldPrompt] BUY` + `[BaseService] Remote BUY result Ok=true` + Success toast.
3. **Army** — Dock **ARMY** / key **A** → status hydrates (not “No army data”) → **RECRUIT x1** → Success toast + count up. **FILL CAP** with 0 free → Warn toast.
4. **Garage** — **G** or **E** on vehicle pad → OWNED Jeep → **SPAWN** → `[VehicleController] SPAWN request` + `[VehicleService] Remote SPAWN result Ok=true` + Deployed toast + DriverSeat. **DESPAWN** clears.
5. **Shop stubs** — Dock Shop → buttons labeled **STUB**; tap → Warn “not configured (placeholder ID)”; **no** Marketplace charge.
6. **Touch** — All dock / panel actions use **Activated** (not MouseButton1Click-only). Combat FIRE may use MouseButton1Down/Up for hold-to-fire (intentional).

## Expected Output markers

```
[WAR EMPIRE] PERF: MapDressing SKIPPED in Studio (StudioSkipWorldDressing)...
[BaseService] Remote BUY result ... Ok=true
[VehicleService] Remote SPAWN result ... Ok=true
[VehicleService] SPAWN ok ... @ WE_VehicleSpawn|BasePlot|...
[BuyPathVerify] PASS Monetization stubs clear — N product Ids all 0
[BuyPathVerify] PASS DevConfig.StudioSkipWorldDressing=true
```

## Ship artifact

- Box: `/workspace/war-empire/dist/WarEmpire-PERF.rbxlx` (+ `WarEmpire.rbxlx` twin)
- Parent CopyFromBox → `C:\Users\laura\Downloads\WarEmpire-PERF.rbxlx`
