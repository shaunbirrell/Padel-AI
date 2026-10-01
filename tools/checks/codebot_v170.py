# Code Bot Roblox v170 (2026-10-01): wire the next 5 free Roblox badges (Creator Hub universe 10767159222,
# verified enabled via badges.roblox.com). codebot_v134 wired the first 5; this ship wires batch 2.
#  * Cash100k = Six Figures 3066564903295841, FirstOutpost = Outpost Taken 3933837527405364,
#    Level10 = Sergeant 2735659013414286, Cash1M = Millionaire 3464730701383868,
#    CommandCenterMax = High Command 2700577206257761. The other 11 stay BadgeId 0 (daily free routine).
#  * Award / backfill path unchanged (AchievementService). PreferMesh OFF; FastTravelEnabled = false.
from pathlib import Path

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


def block(src, key):
    i = src.find("\t\t" + key + " = {")
    j = src.find("\n\t\t},", i)
    return src[i:j] if i >= 0 and j > i else ""


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 173)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 173)'),
    (S + "Services/DataService.luau", "WE_Build=173"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 173)'),
):
    check(needle in read(rel), "CODEBOT v170: WE_Build=173 " + rel.rsplit("/", 1)[-1])

AC = read(C + "AchievementConfig.luau")
IDS = {
    "Cash100k": 3066564903295841,
    "FirstOutpost": 3933837527405364,
    "Level10": 2735659013414286,
    "Cash1M": 3464730701383868,
    "CommandCenterMax": 2700577206257761,
}
for k, v in IDS.items():
    b = block(AC, k)
    check(b != "" and ("BadgeId = %d," % v) in b, "CODEBOT v170: %s BadgeId = %d" % (k, v))
zeros = AC.count("BadgeId = 0,")
check(zeros == 11, "CODEBOT v170: 11 achievements keep BadgeId 0 (daily routine): %d" % zeros)

# original v134 five must still be present
ORIG = {
    "FirstKillNPC": 772051421546625,
    "FirstPlayerKill": 2489884143486750,
    "FirstUpgrade": 583497417329015,
    "Cash10k": 1847488248714137,
    "PlayerKills10": 2976613716370877,
}
for k, v in ORIG.items():
    b = block(AC, k)
    check(b != "" and ("BadgeId = %d," % v) in b, "CODEBOT v170: v134 %s BadgeId still %d" % (k, v))

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v170: PreferMesh stays OFF")
check("FastTravelEnabled = false" in read(C + "MapConfig.luau"), "CODEBOT v170: FastTravelEnabled = false")
