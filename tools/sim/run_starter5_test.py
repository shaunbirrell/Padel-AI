"""claude-bud JOB 66: the 5 R$ starter products, on the REAL MonetizationConfig + RecruitPackService (stand-ins:
run_kit_detail_test.PRELUDE; the services around RecruitPackService are recording fakes).

1. ROWS: StarterRecruit5 (3715888533) + Boost2x10m (3715888566) are 5 R$ (Code Bot: created on the Creator Hub); the pack is one-time with 3 soldiers + starter cash;
   the boost is 10 minutes, repeatable; no damage / health / armour / raid / protection key.
2. CASH: about 2.5 min of his early income, at least 750 and at most 20,000.
3. OWNER-FIRST: SkuLiveFor follows the Starter5 switch (owner yes, others no).
4. OFFER: for the owner the one-time card is the 5 R$ offer at 5 min of play (its own title / lines / product key and
   its own saved flag); never before 5 min, never on hold / in combat; once shown never again. Everyone else keeps the
   Recruit Pack offer at 10 min exactly as before.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_starter5_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Constants": SH / "Constants.luau",
    "Configs/MonetizationConfig": SH / "Configs/MonetizationConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Services/RecruitPackService": SV / "Services/RecruitPackService.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
local prevG = game
game = { GetService = function(_, n)
  if n == "Players" then return { GetPlayers = function() return {} end, PlayerRemoving = { Connect = function() end }, PlayerAdded = { Connect = function() end } } end
  if n == "RunService" then return { IsStudio = function() return false end } end
  return prevG:GetService(n) end }
local MC = require(node("Configs/MonetizationConfig"))
local OWNER, OTHER = 470626172, 9

-- 1. rows
local P, B = MC.DevProducts.StarterRecruit5, MC.DevProducts.Boost2x10m
check(P.RobuxPrice == 5 and B.RobuxPrice == 5 and P.Id == 3715888533 and B.Id == 3715888566, "both 5 R$, the Creator Hub Ids 3715888533 / 3715888566")
local D = MC.Starter5.OfferAfterPlaySeconds
check(D == 300, "the Starter5 pop-up delay is ONE value, 300 s (live; Code Bot v206: back from the 60 s phone test)")
check(P.OneTime == true and P.GrantSoldiers == 3 and P.StarterCash == true and B.OneTime ~= true and B.GrantsCashBoostMinutes == 10, "pack: one-time, 3 soldiers + starter cash; boost: 10 min, repeatable")
local p2w = false
for _, row in ipairs({ P, B }) do for k in pairs(row) do local l = string.lower(k); if string.find(l, "damage") or string.find(l, "health") or string.find(l, "armor") or string.find(l, "armour") or string.find(l, "raid") or string.find(l, "protect") then p2w = true end end end
check(not p2w, "no damage / health / armour / raid / protection key (not pay-to-win)")

-- 2. cash
check(MC.Starter5Cash(300) == 750 and MC.Starter5Cash(1000) == 2500 and MC.Starter5Cash(1e9) == 20000, "starter cash: 2.5 min of income, floor 750, cap 20,000")

-- 3. owner-first
check(MC.SkuLiveFor(OWNER, "StarterRecruit5") and MC.SkuLiveFor(OWNER, "Boost2x10m") and not MC.SkuLiveFor(OTHER, "StarterRecruit5") and not MC.SkuLiveFor(OTHER, "Boost2x10m"), "owner-first: the owner can see / buy them, nobody else")

-- 4. the offer
P.Id = 111 -- as if created (the offer never prompts an Id 0 product)
MC.DevProducts.RecruitPack.Id = 3715776659
local RP = require(node("Services/RecruitPackService"))
local T = 0
RP._clock = function() return T end
RP._delay = function() end
local PUSH = {}
local PROF = { [OWNER] = { Stats = { PlayTimeSeconds = 0 } }, [OTHER] = { Stats = { PlayTimeSeconds = 0 } } }
local remote = { IsA = function() return true end, FireClient = function(_, p, k, d) table.insert(PUSH, { uid = p.UserId, k = k, d = d }) end, OnServerEvent = { Connect = function() end } }
RP.Init({
  DataService = { GetProfile = function(p) return PROF[p.UserId] end, MarkDirty = function() end },
  MonetizationService = { ClaimSoftOfferSlotRefundable = function() return {} end, PassivePerMin = function() return 400 end, OnGranted = function() end },
  RemoteSetup = { Get = function() return remote end },
  RetentionService = { IsOnboarding = function() return false end },
})
local function mkP(uid) local p = { UserId = uid, Name = "P" .. uid, attrs = {} }; p.GetAttribute = function(s, k) return s.attrs[k] end; return p end
local O, X = mkP(OWNER), mkP(OTHER)
PROF[OWNER].Stats.PlayTimeSeconds = D - 10
local ok0 = RP.Step(O)
check(not ok0 and #PUSH == 0, "the owner 10 s before the delay: no card yet")
PROF[OWNER].Stats.PlayTimeSeconds = D + 1
local ok1 = RP.Step(O)
local c = PUSH[#PUSH]
check(ok1 and c and c.d.ProductKey == "StarterRecruit5" and c.d.Title == MC.Starter5.Title and c.d.RobuxPrice == 5 and #c.d.Lines == 3 and string.find(c.d.Lines[2], "1000", 1, true),
  "1 s past the delay: the owner's card is the 5 R$ ONE-TIME OFFER (" .. tostring(c and c.d.Lines[2]) .. ")")
RP.Result(O, "shown")
check(PROF[OWNER].Starter5Offered == true and PROF[OWNER].RecruitPackOffered == nil, "shown: its own saved flag (the Recruit Pack flag untouched)")
T += 100000
PROF[OWNER].Stats.PlayTimeSeconds = 5000
local n = #PUSH
RP.Step(O)
check(#PUSH == n, "once shown, never again")
PROF[OTHER].Stats.PlayTimeSeconds = D + 1
RP.Step(X)
check(#PUSH == n, "another player past the Starter5 delay: no 5 R$ card (owner-first)")
PROF[OTHER].Stats.PlayTimeSeconds = 601
RP.Step(X)
local c2 = PUSH[#PUSH]
check(c2 and c2.uid == OTHER and c2.d.ProductKey == "RecruitPack" and c2.d.Title == nil, "another player at 10:01: the Recruit Pack offer exactly as before")

print(string.format("STARTER5 LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=120)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "STARTER5 LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("STARTER5 TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "STARTER5 TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
