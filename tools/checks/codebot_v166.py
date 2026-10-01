# Code Bot Roblox v166 (2026-10-01, Shaun 10:31 Dublin: "Turn everything on for everyone please, obviously the speed
# update just when someone pays for the speed boost"). FLIP-ALL-LIVE: every owner-first OwnerFirst flag -> false.
#  * TutorialConfig.Guided, GuardConfig.Posts, ShopOverhaulConfig.TimePacks (still hidden until all five Ids are set:
#    TimePacksReady), StorePropsConfig + cfg40.JOB40, MonetizationConfig.RecruitPackOffer (Id 0 = never offered),
#    RivalConfig, RatePromptConfig, EndgameConfig.Live (every part), ArmyConfig.ArmyBrawl, ArmyOrdersConfig.Live,
#    MonetizationConfig.SpeedV2.
#  * SpeedV2 only changes the multiplier OF the speed SKUs (WalkSpeedMultV2: Speed Pass x1.75, Speed Boost x2.5). The
#    speed itself is applied only through MonetizationService.SpeedMultFor = the highest OWNED speed SKU (1 when none):
#    a player who never paid for speed runs at the default. Pinned below + proved in run_recruit_pack_test (real
#    MonetizationService: x1 / x2.5 / x1.75 / both = x2.5).
#  * RecruitPackTakesStarterSlot: the Recruit Pack replaces the old Starter Pack first offer only once its Id is set
#    (live AND Id ~= 0); while Id 0 the Starter Pack pop-up + Speed Boost fallback run for everyone as before.
# Unchanged: admins off the boards, 10 players, StreamingEnabled / PreferMesh off, no WE_Building*, no fast travel, no
# price / Id change, VisualAssetConfig.BodyRollout stays "owner" (licence records, codebot_v101).
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 208)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 208)'),
    (S + "Services/DataService.luau", "WE_Build=208"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 208)'),
):
    check(needle in read(rel), "CODEBOT v166: WE_Build=208 " + rel.rsplit("/", 1)[-1])

# ── every owner-first flag is false ──
V = "OwnerFirst = false, -- codebot_v166 flip-all-live"
TC = read(C + "TutorialConfig.luau")
GC = read(C + "GuardConfig.luau")
SO = read(C + "ShopOverhaulConfig.luau")
SP = read(C + "StorePropsConfig.luau")
MC = read(C + "MonetizationConfig.luau")
RC = read(C + "RivalConfig.luau")
RP = read(C + "RatePromptConfig.luau")
EG = read(C + "EndgameConfig.luau")
AC = read(C + "ArmyConfig.luau")
AO = read(C + "ArmyOrdersConfig.luau")
for cond, label in (
    ("TutorialConfig.Guided = {\n\tEnabled = true,\n\t" + V in TC, "TutorialConfig.Guided"),
    ("\tPosts = {\n\t\tEnabled = true,\n\t\t" + V in GC, "GuardConfig.Posts (real base guards at every base)"),
    ("\tTimePacks = {\n\t\tEnabled = true,\n\t\t" + V in SO, "ShopOverhaulConfig.TimePacks"),
    ("local StorePropsConfig = {\n\tEnabled = true, -- KILL SWITCH: false = no store props anywhere (the Part builds as before)\n\t" + V in SP, "StorePropsConfig"),
    ("cfg40.JOB40 = { Enabled = true, OwnerFirst = false } -- codebot_v166" in SP, "StorePropsConfig cfg40.JOB40"),
    ("cfg.RecruitPackOffer = {\n\tEnabled = true,\n\t" + V in MC, "MonetizationConfig.RecruitPackOffer"),
    ("cfg.SpeedV2 = {\n\tEnabled = true,\n\t" + V in MC, "MonetizationConfig.SpeedV2"),
    ("local RivalConfig = {\n\tEnabled = true,\n\t" + V in RC, "RivalConfig"),
    ("\tEnabled = true, -- kill switch\n\t" + V in RP, "RatePromptConfig"),
    ("\tLive = {\n\t\tEnabled = true,\n\t\t" + V in EG, "EndgameConfig.Live (every endgame part)"),
    ("ArmyBrawl = {\n\t\tEnabled = true,\n\t\t" + V in AC, "ArmyConfig.ArmyBrawl"),
    ("\tLive = {\n\t\tEnabled = true,\n\t\t" + V in AO, "ArmyOrdersConfig.Live"),
):
    check(cond, "CODEBOT v166: " + label + " Enabled + OwnerFirst=false (everyone)")

left = []
for p in sorted((ROOT / C).glob("*.luau")):
    for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("--", 1)[0]
        # claude-bud JOB 48: a NEW owner-first block (CLAUDE.md "Flags": new gameplay ships owner-first) is tagged
        # NEW-OWNER-FIRST on its line; v166's flip of every block that existed then is still pinned above
        if re.search(r"\bOwnerFirst\s*=\s*true\s*(,|\}|$)", code) and "NEW-OWNER-FIRST" not in line:  # a table field, not docblock prose
            left.append(f"{p.name}:{i}")
check(not left, f"CODEBOT v166: no OwnerFirst = true assignment left in Shared/Configs {left}")

# the LiveFor helpers really turn on for a non-owner once OwnerFirst ~= true
RET = read(C + "RetentionConfig.luau")
check("if block.OwnerFirst ~= true then\n\t\treturn true\n\tend" in RET, "CODEBOT v166: RetentionConfig.Live: OwnerFirst ~= true -> everyone")
for cond, label in (
    ("Live(TutorialConfig.Guided, userId)" in TC, "Guided"),
    ("Live((GuardConfig :: any).Posts, ownerUserId)" in GC, "Posts"),
    ("RetentionConfig.Live(ShopOverhaulConfig.TimePacks, userId)" in SO, "TimePacks"),
    ("Live(cfg.RecruitPackOffer, userId)" in MC, "RecruitPack"),
    ("Live(RivalConfig, userId)" in RC, "Rival"),
    ("Live(RatePromptConfig, userId)" in RP, "RatePrompt"),
    ("return RetentionConfig.Live(EndgameConfig.Live, userId)" in EG, "Endgame"),
    ("RetentionConfig.Live(ArmyOrdersConfig.Live, userId)" in AO and "return L.Enabled == true and L.OwnerFirst ~= true" in AO, "ArmyOrders (+ LiveForAll)"),
    ("RC.Live(b, userId) == true" in read(S + "Modules/ArmyBrawl.luau"), "ArmyBrawl"),
    ("if StorePropsConfig.OwnerFirst ~= true then\n\t\treturn true" in SP and "if b.OwnerFirst ~= true then\n\t\treturn true" in SP, "StoreProps + JOB40"),
):
    check(cond, "CODEBOT v166: " + label + " LiveFor goes through the OwnerFirst rule")
check("ShopOverhaulConfig.TimePacksLiveFor(userId) and ShopOverhaulConfig.TimePacksReady()" in SO,
      "CODEBOT v166: the time packs stay hidden until all five Ids are set (TimePacksShown = live AND Ready)")
LB = read(C + "LeaderboardConfig.luau")
check("LeaderboardConfig.ArmyKillsBoardLive = true" in LB, "CODEBOT v166: ARMY KILLS board live (its own switch)")

# ── SpeedV2: applies only to players who own / paid for a speed SKU ──
MS = read(S + "Services/MonetizationService.luau")
check("if userId ~= nil and typeof(def.WalkSpeedMultV2) == \"number\" and cfg.SpeedV2LiveFor(userId) then\n\t\treturn def.WalkSpeedMultV2" in MC,
      "CODEBOT v166: SpeedV2 only swaps a speed SKU's own multiplier (WalkSpeedMultV2)")
check("WalkSpeedMultV2 = 1.75," in MC and "WalkSpeedMultV2 = 2.5," in MC and MC.count("WalkSpeedMultV2 =") == 2,
      "CODEBOT v166: only the Speed Pass (x1.75) and the Speed Boost (x2.5) carry a V2 multiplier")
sm = re.search(r"function MonetizationService\.SpeedMultFor\(player: Player\): number\n(.*?)\nend\n", MS, re.S)
smb = sm.group(1) if sm else ""
check("local best = 1" in smb and "MonetizationConfig.SkuLiveFor(player.UserId, passKey) and ownsCached(player, passKey)" in smb
      and "if m > best and ownsSkuCached(player, productKey) then" in smb and smb.count("best = m") == 2,
      "CODEBOT v166: SpeedMultFor = the highest OWNED speed SKU (game pass owned / product entitlement), 1 when none")
check("if mult <= 1 then\n\t\treturn -- nothing owned: WalkSpeed stays what the game set" in MS
      and "if MonetizationService.SpeedMultFor(player) <= 1 then\n\t\treturn -- nothing owned: WalkSpeed stays the game default" in MS,
      "CODEBOT v166: no speed SKU owned -> WalkSpeed is never written (default speed)")
check("cfg.MaxWalkSpeedMult = 2.5" in MC and "local MAX_WALK_SPEED_MULT = tonumber((MonetizationConfig :: any).MaxWalkSpeedMult) or 2.0" in MS,
      "CODEBOT v166: the 2.5 sanity cap (40 studs/s)")
for k, i, pr in (("ImpulseSpeed", 1998656357, 99), ("SpeedBoost", 3713839342, 99)):
    check(re.search(r"\b%s = \{\n\t+Id = %d,\n\t+DisplayName = \"[^\"]+\",\n\t+RobuxPrice = %d," % (k, i, pr), MC) is not None,
          f"CODEBOT v166: {k} Id {i} / {pr} R$ unchanged")

# ── Recruit Pack: takes the Starter Pack slot only once its Id is set ──
check("function cfg.RecruitPackTakesStarterSlot(userId: any): boolean" in MC and "return id ~= 0 and cfg.RecruitPackLiveFor(userId) == true" in MC,
      "CODEBOT v166: RecruitPackTakesStarterSlot = live AND Id set")
check(MS.count("RecruitPackTakesStarterSlot(player.UserId) then") == 2 and "RecruitPackLiveFor(player.UserId) then" not in MS,
      "CODEBOT v166: TrySoftOfferStarterBundle + ScheduleFirstOffer use RecruitPackTakesStarterSlot (Id 0 -> Starter Pack as before)")

# ── rules that stay ──
check("MaxPlayersPerServer = 10," in read(C + "GameConfig.luau"), "CODEBOT v166: servers stay at 10 players")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v166: StreamingEnabled stays off")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v166: PreferMesh stays off")
check("FastTravelEnabled = false," in read(C + "MapConfig.luau"), "CODEBOT v166: no fast travel")
check('\tBodyRollout = "owner",\n' in read(C + "VisualAssetConfig.luau"), "CODEBOT v166: store vehicle bodies stay owner-only (no licence records; not an OwnerFirst flag)")
ES = read(S + "Services/EngagementService.luau")
check("local function isBoardExcluded(uid: number): boolean" in ES and "AC.IsPlaytestOwner(uid)" in ES and "if isBoardExcluded(player.UserId) then" in ES,
      "CODEBOT v166: admin / owner accounts stay off every leaderboard")
check("RobuxPrice = 49," in MC and 'RecruitPack = { Id = ' in MC, "CODEBOT v166: Recruit Pack 49 R$ unchanged (Id set by the Creator Hub worker only)")

# ── the sims (real code) ──
env = os.environ.copy()
for script, label in (
    ("tools/sim/run_speed_test.py", "run_speed_test"),
    ("tools/sim/run_recruit_pack_test.py", "run_recruit_pack_test (SpeedMultFor ownership + Starter slot)"),
    ("tools/sim/run_first_offer_test.py", "run_first_offer_test"),
    ("tools/sim/run_time_packs_test.py", "run_time_packs_test"),
    ("tools/sim/run_army_brawl_test.py", "run_army_brawl_test"),
    ("tools/sim/run_first_minutes_test.py", "run_first_minutes_test"),
    ("tools/sim/run_rival_targets_test.py", "run_rival_targets_test"),
    ("tools/sim/run_rate_prompt_test.py", "run_rate_prompt_test"),
    ("tools/sim/run_endgame_test.py", "run_endgame_test"),
    ("tools/sim/run_blackmarket_public_test.py", "run_blackmarket_public_test"),
    ("tools/sim/run_base_guards_test.py", "run_base_guards_test"),
    ("tools/sim/run_codebot_v163_test.py", "run_codebot_v163_test"),
):
    if not (ROOT / script).is_file():
        check(False, "CODEBOT v166: " + label + " missing")
        continue
    r = subprocess.run([sys.executable, script], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=900)
    out = r.stdout or ""
    tail = [ln for ln in out.splitlines() if ln.strip()][-1:] or [((r.stderr or "")[-200:])]
    check(r.returncode == 0 and "0 failed" in out and not re.search(r"\b[1-9]\d* failed", out), "CODEBOT v166: " + label + " " + tail[-1])
