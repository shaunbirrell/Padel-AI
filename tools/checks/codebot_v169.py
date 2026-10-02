# Code Bot Roblox v169 (2026-10-01, owner Shaun: "doesn't want to type /setrebirth"): AdminConfig.OwnerRebirthGrant
# sets UserId 470626172's rebirth count to 10 ONE TIME on his next profile load, through PrestigeService.AdminSetRebirth
# (the /setrebirth path: cash / items kept, derived state refreshed, saved); profile.AdminGrants[Key] stops a re-apply;
# already >= 10: nothing. Owner stays off the boards. PreferMesh / StreamingEnabled OFF; no price changes.
from pathlib import Path
import os
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
        if not cond:
            raise SystemExit(1)


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 212'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 212'),
    (S + "Services/DataService.luau", "WE_Build=212"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 212'),
):
    check(needle in read(rel), "CODEBOT v169: WE_Build=212 " + rel.rsplit("/", 1)[-1])

AC = read(C + "AdminConfig.luau")
PS = read(S + "Services/PrestigeService.luau")
for cond, label in (
    ('OwnerRebirthGrant = { UserId = PLAYTEST_OWNER_USER_ID, Rebirths = 10, Key = "rebirth10-2026-10-01" }' in AC, "AdminConfig.OwnerRebirthGrant 470626172 / 10 / Key"),
    ("local PLAYTEST_OWNER_USER_ID = 470626172" in AC, "the grant UserId is the owner (470626172)"),
    ("function PrestigeService.ApplyOwnerRebirthGrant(" in PS and "local ok = PrestigeService.AdminSetRebirth(player, want)" in PS, "the grant uses the /setrebirth path"),
    ("profile.AdminGrants[g.Key] ~= nil" in PS, "the Key marker stops a re-apply"),
    ("pcall(PrestigeService.ApplyOwnerRebirthGrant, player, profile)" in PS, "applied from the profile-load hook"),
):
    check(cond, "CODEBOT v169: " + label)

env = os.environ.copy()
r = subprocess.run([sys.executable, "tools/sim/run_codebot_v169_test.py"], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=900)
tail = [ln for ln in (r.stdout or "").splitlines() if ln.strip()][-1:] or [((r.stderr or "")[-200:])]
check(r.returncode == 0 and "CODEBOT V169 TESTS: 0 failed" in (r.stdout or ""), "CODEBOT v169: run_codebot_v169_test " + tail[-1])
