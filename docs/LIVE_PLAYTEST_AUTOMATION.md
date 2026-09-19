# WAR EMPIRE — Live playtest automation notes

Linux agents cannot run Roblox Studio. Use these Studio-side harnesses after opening
`dist/WarEmpire-PERF.rbxlx` (or Rojo sync) + **Play Solo**.

## Harnesses (command bar)

| Tool | When | What |
|------|------|------|
| `tools/SmokeTest.luau` | After Bootstrap | Remotes + configs + services present; no Give* remotes |
| `tools/BuyPathStatic.py` | Box CLI (`python3`) | Source wiring: BUY path, BankGuard MoveTo, HUD Visible/Activated, PERF flag |
| `tools/BuyPathVerify.luau` | Play Solo client | BUY/Army/Garage remotes, **all product Ids=0**, pad tags, GUIs, PERF flag, StudioSmokeLog |

Paste entire file → Command Bar → Enter. Read Output for `PASS` / `FAIL` / `WAIT`.

## Manual live loop (phone / Studio Device Emulator)

1. **PERF** — Output shows MapDressing SKIPPED (`StudioSkipWorldDressing`). Keep it.
2. **BUY** — Stand on own Command Center pad → gold **BUY** → `[WorldPrompt] BUY` + `[BaseService] Remote BUY result Ok=true` + Success toast.
3. **Army** — Dock **ARMY** / key **A** → status hydrates (not “No army data”) → **RECRUIT x1** → Success toast + count up. **FILL CAP** with 0 free → Warn toast.
4. **Garage** — **G** or **E** on vehicle pad → OWNED Jeep → **SPAWN** → `[VehicleController] SPAWN request` + `[VehicleService] Remote SPAWN result Ok=true` + Deployed toast + DriverSeat. **DESPAWN** clears.
5. **Shop stubs** — Dock Shop → buttons labeled **STUB**; tap → Warn “not configured (placeholder ID)”; **no** Marketplace charge.
6. **Touch** — All dock / panel actions use **Activated** (not MouseButton1Click-only). Combat FIRE may use MouseButton1Down/Up for hold-to-fire (intentional).
7. **Rebirth** — Dock **REBIRTH** → phone panel full-width **CONFIRM REBIRTH (+10% CASH)** + stacked BP claim buttons.
8. **FallSafety** — walk off map / under floor → teleport home + “Rescued from fall” toast (Y < 0); SafetyCatch underfloor remains.

## Auto smoke (Studio Play Solo)

Server module `StudioBuySmoke` (Bootstrap, `RunService:IsStudio()` only) waits ~4s after profile/plot,
teleports home, calls `BaseService.PurchaseUpgrade("CommandCenter")`, then:

1. **Loud server prints** — `========== [SMOKE] BUY OK … ==========` (+ `warn` on FAIL)
2. **`ServerStorage.SmokeResult.LastBuy` / `.Log`** — StringValue mirror
3. **`StudioSmokeLog` RemoteEvent → FireAllClients** — client module `StudioSmokeClient` echoes the same lines in **client** Output (Play Solo filter often hides server-only prints)

```
[SMOKE] BUY START cash=...
[SMOKE] BUY OK newCash=... level=...
```
or `[SMOKE] BUY FAIL ...`.

After CC OK, a second smoke (~+2s) buys **Barracks** the same way (`START`/`OK`/`FAIL`).

HttpService / `%TEMP%` file writes from Studio Luau are unreliable — do not depend on them.

## Expected Output markers

```
[WAR EMPIRE] PERF: MapDressing SKIPPED in Studio (StudioSkipWorldDressing)...
[VisualAssetService] Catalog inserts SKIPPED (StudioSkipWorldDressing / disabled). Part kits only.
[SMOKE] StudioBuySmoke armed ...
========== [SMOKE] BUY OK ... ==========
[SMOKE] ★★★ BUY PATH OK ★★★
========== CLIENT [SMOKE] BUY OK ... ==========
[BaseService] Remote BUY result ... Ok=true
[VehicleService] Remote SPAWN result ... Ok=true
[BuyPathVerify] PASS Monetization stubs clear — N product Ids all 0
[BuyPathVerify] PASS DevConfig.StudioSkipWorldDressing=true
[BuyPathVerify] PASS StudioSmokeLog remote present
```

## Ship artifact / CopyFromBox

| Box path | Suggested CopyFromBox destination |
|----------|-----------------------------------|
| `/workspace/war-empire/dist/WarEmpire-PERF.rbxlx` | `C:\Users\laura\Downloads\WarEmpire-PERF.rbxlx` |
| `/workspace/war-empire/dist/WarEmpire.rbxlx` | `C:\Users\laura\Downloads\WarEmpire.rbxlx` |

Parent: run CopyFromBox on those two paths after rebuild. Prefer **PERF** on 8GB Studio.
