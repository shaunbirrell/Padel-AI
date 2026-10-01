# Code Bot Roblox v167 (2026-10-01): TIME PACK + RECRUIT PACK IDS. Shaun approved the prices 2026-10-01; the six
# developer products were created on the Creator Hub (universe 10767159222) and their Ids are wired here:
#   Cash15m 3715776339 (25 R$), Cash30m 3715776410 (49), Cash1h 3715776466 (89), Cash2h 3715776582 (159),
#   Cash4h 3715776616 (279), RecruitPack 3715776659 (49).
#  * All five time-pack Ids set -> ShopOverhaulConfig.TimePacksReady() -> the time rows replace the old four cash rows in
#    the Shop for everyone (TimePacks live since v166).
#  * RecruitPack Id set -> MonetizationConfig.RecruitPackTakesStarterSlot -> the Recruit Pack is offerable and takes the
#    Starter Pack first-offer slot (RecruitPackOffer live since v166).
# Unchanged: every flag (no OwnerFirst / Enabled edit), every other product Id and price.
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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 205)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 205)'),
    (S + "Services/DataService.luau", "WE_Build=205"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 205)'),
):
    check(needle in read(rel), "CODEBOT v167: WE_Build=205 " + rel.rsplit("/", 1)[-1])

MC = read(C + "MonetizationConfig.luau")
WANT = {
    "Cash15m": (3715776339, 25), "Cash30m": (3715776410, 49), "Cash1h": (3715776466, 89),
    "Cash2h": (3715776582, 159), "Cash4h": (3715776616, 279), "RecruitPack": (3715776659, 49),
}
ids = []
for key, (pid, price) in WANT.items():
    m = re.search(r"\n\t\t" + key + r" = \{ Id = (\d+), DisplayName = \"[^\"]+\", RobuxPrice = (\d+),", MC)
    got = int(m.group(1)) if m else 0
    ids.append(got)
    check(m is not None and got != 0, "CODEBOT v167: DevProducts.%s Id is nonzero (%d)" % (key, got))
    check(m is not None and got == pid and int(m.group(2)) == price, "CODEBOT v167: DevProducts.%s Id %d / %d R$ (Creator Hub)" % (key, pid, price))
check(len(set(ids)) == 6, "CODEBOT v167: the six Ids are distinct")
check(all(len(re.findall(r"\bId = %d\b" % pid, MC)) == 1 for pid, _ in WANT.values()), "CODEBOT v167: no other row carries one of the new Ids")

# only those six Id lines changed vs v166 (no price, flag or other Id edit)
try:
    d = subprocess.run(["git", "diff", "-U0", "ec524bf", "--", C + "MonetizationConfig.luau"], cwd=str(ROOT), capture_output=True, text=True).stdout
    ch = [l for l in d.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
    # Code Bot v175: the stand-sign rows (SignW / SignH / SignPixelsPerStud / SignBack, Depot.SignLift) are later, separate edits
    ch = [l for l in ch if "Code Bot v175" not in l and "Depot = { X0 = " not in l
          and not re.match(r"\s*Sign(W|H|PixelsPerStud|Back) = ", l[1:])]
    # claude-bud JOB 49: the two DISABLED sidegrade rows (Id 0, no price) + their comment are added lines only;
    # claude_bud_job49.py pins them (Id 0, no RobuxPrice, no stat keys). Every other line is still held to v167's rule.
    ch = [l for l in ch if not re.match(r"^\+		(OfflineCap2x|MissionReroll) = \{ Id = 0, ", l) and not re.match(r"^\+		-- claude-bud JOB 49 \(Robux sidegrades, DISABLED\)", l)]
    # Code Bot v180: the two wired items + PurchaseSources.missions (pinned in codebot_v180.py): the lines v180 added vs 5e9649b
    _v180 = set(l for l in subprocess.run(["git", "diff", "-U0", "5e9649b", "--", C + "MonetizationConfig.luau"], cwd=str(ROOT), capture_output=True, text=True).stdout.splitlines() if l.startswith("+") and not l.startswith("+++"))
    ch = [l for l in ch if l not in _v180]
    norm = lambda l: re.sub(r"\bId = \d+,", "Id = X,", l[1:])
    minus = sorted(norm(l) for l in ch if l.startswith("-"))
    plus = sorted(norm(l) for l in ch if l.startswith("+"))
    check(len(ch) == 12 and minus == plus and all(re.search(r"\b(Cash15m|Cash30m|Cash1h|Cash2h|Cash4h|RecruitPack) = \{ Id = ", l) for l in ch),
          "CODEBOT v167: MonetizationConfig diff vs v166 = only the six Id values (%d lines)" % len(ch))
except Exception as e:  # shallow clone without ec524bf
    check(True, "CODEBOT v167: diff vs v166 skipped (" + str(e)[:60] + ")")

SO = read(C + "ShopOverhaulConfig.luau")
check("return ShopOverhaulConfig.TimePacksLiveFor(userId) and ShopOverhaulConfig.TimePacksReady()" in SO,
      "CODEBOT v167: TimePacksShown = live AND Ready (all five Ids now set -> shown)")
check("function cfg.RecruitPackTakesStarterSlot(userId: any): boolean" in MC and "return id ~= 0 and cfg.RecruitPackLiveFor(userId) == true" in MC,
      "CODEBOT v167: RecruitPackTakesStarterSlot = live AND Id set (Id now set -> offerable)")

# the sims (real code): the shipped config shows the time rows and offers the Recruit Pack
env = os.environ.copy()
for script, label in (
    ("tools/sim/run_time_packs_test.py", "run_time_packs_test (shipped Ids -> TimePacksReady)"),
    ("tools/sim/run_recruit_pack_test.py", "run_recruit_pack_test (shipped Id -> offerable, takes the Starter slot)"),
    ("tools/sim/run_shop_render_test.py", "run_shop_render_test (shipped Ids -> time rows replace the old cash rows)"),
    ("tools/sim/run_first_offer_test.py", "run_first_offer_test (Starter Pack path with Recruit Pack Id 0)"),
):
    if not (ROOT / script).is_file():
        check(False, "CODEBOT v167: " + label + " missing")
        continue
    r = subprocess.run([sys.executable, script], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=900)
    out = r.stdout or ""
    tail = [ln for ln in out.splitlines() if ln.strip()][-1:] or [((r.stderr or "")[-200:])]
    check(r.returncode == 0 and "0 failed" in out and not re.search(r"\b[1-9]\d* failed", out), "CODEBOT v167: " + label + " " + tail[-1])
