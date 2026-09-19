# CopyFromBox — ship artifacts for laptop Studio

Parent agent / Shaun: copy these **from the box** after overnight rebuilds.

| Priority | Box path | Suggested Windows destination |
|----------|----------|-------------------------------|
| **PERF (8GB)** | `/workspace/war-empire/dist/WarEmpire-PERF.rbxlx` | `C:\Users\laura\Downloads\WarEmpire-PERF.rbxlx` |
| Full twin | `/workspace/war-empire/dist/WarEmpire.rbxlx` | `C:\Users\laura\Downloads\WarEmpire.rbxlx` |

Open **PERF** in Studio → Play Solo. Expect:

- `[WAR EMPIRE] PERF: MapDressing SKIPPED…`
- `[VisualAssetService] Catalog inserts SKIPPED… Part kits only.`
- `========== [SMOKE] BUY OK … ==========` (~4s after plot) on **server and client** Output
- Dock: BASE / SHOP / REBIRTH / ORDERS / ARMY / GARAGE / SETTINGS (Activated)

`DevConfig.StudioSkipWorldDressing = true` — do not flip for laptop playtests.
