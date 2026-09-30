# Code Bot Roblox v155 (2026-10-01): JOB 40E base-owner name tags live for everyone.
# Only BaseMarkerConfig.Live.OwnerFirst changes to false; all other requested OwnerFirst rails stay true.
from pathlib import Path
import re

ROOT = Path.cwd()

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")

def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)

def block(text, key):
    m = re.search(r"(?m)^\s*" + re.escape(key) + r"\s*=\s*\{", text)
    if not m:
        return ""
    depth = 0
    for i in range(m.end() - 1, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[m.end():i]
    return ""

S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"

# All four runtime build pins: BaseService, DataService attribute + load log, EarlyRemotes.
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 157)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 157)'),
    (S + "Services/DataService.luau", "WE_Build=157"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 157)'),
):
    check(needle in read(rel), "CODEBOT v155: WE_Build=157 " + rel.rsplit("/", 1)[-1])

bmc = read(C + "BaseMarkerConfig.luau")
check(re.search(r"Live\s*=\s*\{[^}]*OwnerFirst\s*=\s*false\s*,", bmc, re.S) is not None,
      "CODEBOT v155: BaseMarker OwnerFirst=false for everyone")

endgame = read(C + "EndgameConfig.luau")
check("OwnerFirst = true," in block(endgame, "Live"), "CODEBOT v155: Endgame OwnerFirst stays true")
army = read(C + "ArmyOrdersConfig.luau")
check("OwnerFirst = true," in block(army, "Live"), "CODEBOT v155: ArmyOrders OwnerFirst stays true")
guard = read(C + "GuardConfig.luau")
check("OwnerFirst = true," in block(guard, "Posts"), "CODEBOT v155: GuardConfig.Posts OwnerFirst stays true")
mon = read(C + "MonetizationConfig.luau")
check("OwnerFirst = true," in block(mon, "cfg.SpeedV2"), "CODEBOT v155: SpeedV2 OwnerFirst stays true")
store = read(C + "StorePropsConfig.luau")
check(re.search(r"local StorePropsConfig\s*=\s*\{[^}]*OwnerFirst\s*=\s*true\s*,", store, re.S) is not None,
      "CODEBOT v155: StorePropsConfig OwnerFirst stays true")

# Do not silently alter the other named owner-first rails in this build.
for rel, needle, label in (
    (C + "EndgameConfig.luau", "OwnerFirst = true", "Endgame"),
    (C + "ArmyOrdersConfig.luau", "OwnerFirst = true", "ArmyOrders"),
    (C + "GuardConfig.luau", "OwnerFirst = true", "GuardConfig.Posts"),
    (C + "MonetizationConfig.luau", "OwnerFirst = true", "SpeedV2"),
    (C + "StorePropsConfig.luau", "OwnerFirst = true", "StorePropsConfig"),
):
    check(needle in read(rel), "CODEBOT v155: " + label + " rail unchanged")
