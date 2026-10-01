"""claude-bud JOB 40 part D: the "Enjoying WAR EMPIRE?" reminder, with the REAL RatePromptService on a fake clock
(stand-ins: run_kit_detail_test.PRELUDE) and the real ProfileSchema.Migrate for the save round trip.

1. PLAYTIME: nothing before 900 s of total play; it shows at 900 s (FeaturePush "RatePrompt" { Trigger = "playtime" }).
2. TRIGGER: a rebirth / big achievement shows it early (after TriggerDelaySeconds), once.
3. GAP: not again within 3 days (a new session 1 day later: nothing; 3 days later: yes).
4. COMBAT: a hit 5 s ago -> it waits; 20 s quiet -> it shows.
5. NEVER: "Don't show again" -> after a save + Migrate + a fresh session, never again (even 30 days later).
6. SESSION: at most once per session; the tutorial / onboarding hold blocks it; not live (OwnerFirst) -> nothing.
7. ANSWERS: only later | never | favorite | timeout, only while a show is out; telemetry = rate_prompt_shown /
   rate_prompt_answer only; no economy / inventory / XP call anywhere (the stand-ins record any).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_rate_prompt_test.py   (exit 1 on any failure)"""
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
    "Types": SH / "Types.luau",
    "Configs/RatePromptConfig": SH / "Configs/RatePromptConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/AnalyticsConfig": SH / "Configs/AnalyticsConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/SoldierConfig": SH / "Configs/SoldierConfig.luau",
    "Configs/VehicleConfig": SH / "Configs/VehicleConfig.luau",
    "Configs/WeaponConfig": SH / "Configs/WeaponConfig.luau",
    "Configs/SeasonConfig": SH / "Configs/SeasonConfig.luau",
    "Configs/NationConfig": SH / "Configs/NationConfig.luau",
    "Modules/ProfileSchema": SV / "Modules/ProfileSchema.luau",
    "Services/RatePromptService": SV / "Services/RatePromptService.luau",
}

EXTRA = r'''
NOW, UNIX = 1000, 1700000000
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function(s) NOW += (s or 0) end }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
local function mkPlayer(uid, name) return { UserId = uid, Name = name, Parent = true, CharacterAdded = signal() } end
OWNER = mkPlayer(470626172, "shaunie6")
OTHER = mkPlayer(1234, "rookie99")
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
LOG = { push = {}, analytics = {}, economy = 0, dirty = 0 }
PROFILES = {}
ONBOARDING = false
PACK_BUSY, PACK_DUE = false, false
local remote = { IsA = function(_, c) return c == "RemoteEvent" end, OnServerEvent = signal(),
  FireClient = function(_, p, kind, data) table.insert(LOG.push, { p = p, kind = kind, data = data }) end }
local function boom() LOG.economy += 1 end
DEPS = {
  RemoteSetup = { Get = function() return remote end },
  DataService = { GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() LOG.dirty += 1 end },
  EconomyService = { AddCash = boom, AddGold = boom, SpendCash = boom },
  XPService = { AddXP = boom },
  AnalyticsService = { Log = function(ev, uid, props) table.insert(LOG.analytics, { ev = ev, props = props }) end },
  RetentionService = { IsOnboarding = function() return ONBOARDING end },
  -- claude-bud JOB 41 D: the Recruit Pack card state (out / just closed, or still due first)
  RecruitPackService = { CardBlocks = function() return PACK_BUSY end, Pending = function() return PACK_DUE end },
}
function fresh()
  CACHE["Services/RatePromptService"] = nil
  local S = require(node("Services/RatePromptService"))
  S._clock = function() return NOW end
  S._unix = function() return UNIX end
  S.Init(DEPS)
  return S
end
function shows() local n = 0; for _, e in ipairs(LOG.push) do if e.kind == "RatePrompt" then n += 1 end end; return n end
-- play `secs` seconds in 5 s ticks (the real tick size)
function play(S, p, secs) local shown = false; local t = 0; while t < secs do NOW += 5; UNIX += 5; t += 5; if S.Step(p) then shown = true end end; return shown end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local PS = require(node("Modules/ProfileSchema"))
local Cfg = require(node("Configs/RatePromptConfig"))
local function deep(t) if type(t) ~= "table" then return t end local c = {} for k, v in pairs(t) do c[k] = deep(v) end return c end

PROFILES[OWNER.UserId] = { TutorialComplete = true }
local S = fresh()
-- 1. playtime
check(not play(S, OWNER, 890) and shows() == 0, "nothing before 900 s of play (890 s)")
check(play(S, OWNER, 15) and shows() == 1 and LOG.push[1].data.Trigger == "playtime", "shows at 900 s: FeaturePush RatePrompt { Trigger = playtime }")
local rec = PROFILES[OWNER.UserId].RatePrompt
check(rec.Shows == 1 and rec.LastShownUnix > 0 and rec.PlaySeconds >= 900, "saved at once: Shows 1, LastShownUnix, PlaySeconds")
check(not play(S, OWNER, 3000) and shows() == 1, "at most once per session")
check(S.Answer(OWNER, "later") and not S.Answer(OWNER, "later"), "one answer per show (a second is ignored)")

-- 3. gap: a new session 1 day later, then 3 days later
UNIX += 86400
S = fresh(); LOG.push = {}
check(not play(S, OWNER, 1200) and shows() == 0, "a new session 1 day later: nothing (3-day gap)")
UNIX += 2 * 86400
S = fresh(); LOG.push = {}
check(play(S, OWNER, 70) and shows() == 1, "3 days after the last show: it shows again (play time already past 900)")
S.Answer(OWNER, "timeout")

-- 4. combat quiet
UNIX += 3 * 86400
S = fresh(); LOG.push = {}
play(S, OWNER, 55)
S._Session(OWNER).LastHurt = NOW -- a hit now
check(not play(S, OWNER, 5) and shows() == 0, "a hit 5 s ago: it waits")
check(play(S, OWNER, 20) and shows() == 1, "20 s quiet: it shows")

-- 5. never, across a save + Migrate + a new session
check(S.Answer(OWNER, "never") and PROFILES[OWNER.UserId].RatePrompt.Never == true, "Don't show again -> Never = true")
PROFILES[OWNER.UserId] = PS.Migrate(deep(PROFILES[OWNER.UserId]))
check(PROFILES[OWNER.UserId].RatePrompt.Never == true and PROFILES[OWNER.UserId].RatePrompt.Shows == 3, "Never / Shows survive a save + ProfileSchema.Migrate")
UNIX += 30 * 86400
S = fresh(); LOG.push = {}
S.Trigger(OWNER, "rebirth")
check(not play(S, OWNER, 2000) and shows() == 0, "after 'never': nothing, even 30 days later and after a rebirth")
local bad = PS.Migrate({ RatePrompt = { LastShownUnix = -4, Shows = "x", Never = "yes", PlaySeconds = 0 / 0 } })
check(bad.RatePrompt.LastShownUnix == 0 and bad.RatePrompt.Shows == 0 and bad.RatePrompt.Never == false, "Migrate repairs a bad record")
check(PS.Migrate({}).RatePrompt == nil, "a profile without the record: nil (the defaults)")

-- 2. trigger: a fresh player (little play) after a rebirth / big achievement
PROFILES[OWNER.UserId] = { TutorialComplete = true }
S = fresh(); LOG.push = {}
play(S, OWNER, 65)
S.Trigger(OWNER, "achievement")
check(not play(S, OWNER, 5) and shows() == 0, "the trigger waits its TriggerDelaySeconds (" .. Cfg.TriggerDelaySeconds .. " s)")
check(play(S, OWNER, 10) and shows() == 1 and LOG.push[#LOG.push].data.Trigger == "achievement", "a big achievement shows it early (65 s of play)")
S.Trigger(OWNER, "rebirth")
check(not play(S, OWNER, 60) and shows() == 1, "a second trigger in the same session: nothing (once per session)")

-- 6. tutorial / onboarding / not live / session start
PROFILES[OWNER.UserId] = { TutorialComplete = false, RatePrompt = { PlaySeconds = 5000 } }
S = fresh(); LOG.push = {}
check(not play(S, OWNER, 120) and shows() == 0, "tutorial not done: nothing")
PROFILES[OWNER.UserId].TutorialComplete = true; ONBOARDING = true
check(not play(S, OWNER, 30) and shows() == 0, "the onboarding hold: nothing")
ONBOARDING = false
S = fresh(); LOG.push = {}
check(not play(S, OWNER, 55) and shows() == 0, "never in the first minute of a session")
PROFILES[OTHER.UserId] = { TutorialComplete = true, RatePrompt = { PlaySeconds = 5000 } }
check(not play(S, OTHER, 200) and shows() == 0, "OwnerFirst: not live for another player -> nothing")
check(S.Decide({ Live = true, Loaded = true, TutorialDone = true, SessionSeconds = 100, PlaySeconds = 900, SinceHurt = 25 }) == true, "Decide: all rules pass -> show")

-- 7. answers / telemetry / no economy
local S7 = fresh()
check(not S7.Answer(OWNER, "later"), "an answer with no show out: ignored")
S7._Session(OWNER).Awaiting = true
check(not S7.Answer(OWNER, "liked") and not S7.Answer(OWNER, 5), "only later | never | favorite | timeout")
check(S7.Answer(OWNER, "favorite"), "favorite accepted (nothing given)")
local evs = {}
for _, e in ipairs(LOG.analytics) do evs[e.ev] = true end
local onlyTwo = true
for ev in pairs(evs) do if ev ~= "RATE_PROMPT_SHOWN" and ev ~= "RATE_PROMPT_ANSWER" then onlyTwo = false end end
check(evs.RATE_PROMPT_SHOWN and evs.RATE_PROMPT_ANSWER and onlyTwo, "telemetry: rate_prompt_shown / rate_prompt_answer only")
check(LOG.economy == 0, "no economy / XP call from the service (0 calls)")
local words = string.lower(Cfg.Text.Title .. " " .. Cfg.Text.Body .. " " .. Cfg.Text.Favorite .. " " .. Cfg.Text.Later .. " " .. Cfg.Text.Never)
local rewardy = false
for _, w in ipairs({ "reward", "free", "cash", "gold", "gift", "bonus", "prize", "win", "earn", "claim", "unlock" }) do if string.find(words, w, 1, true) then rewardy = true end end
check(not rewardy, "the card text has no reward words")

-- ── 8. JOB 41 part D: the big-win triggers ──
local function newcomer() PROFILES[OWNER.UserId] = { TutorialComplete = true }; local S8 = fresh(); LOG.push = {}; play(S8, OWNER, 65); return S8 end
local S8 = newcomer()
S8.Trigger(OWNER, "FirstCapture")
check(play(S8, OWNER, 10) and shows() == 1 and LOG.push[#LOG.push].data.Trigger == "FirstCapture", "FirstCapture shows it early (65 s of play)")
check(PROFILES[OWNER.UserId].RatePrompt.Triggered.FirstCapture == true, "FirstCapture is spent for good (RatePrompt.Triggered)")
S8.Trigger(OWNER, "RaidWin")
check(not play(S8, OWNER, 60) and shows() == 1, "never both in one session (RaidWin after FirstCapture: nothing)")
-- a later session 3+ days on: FirstCapture again does nothing (one-time), RaidWin shows once
UNIX += 4 * 86400
S8 = fresh(); LOG.push = {}; play(S8, OWNER, 65)
S8.Trigger(OWNER, "FirstCapture")
check(not play(S8, OWNER, 30) and shows() == 0, "FirstCapture again on the same profile: nothing (one time per profile)")
S8 = fresh(); LOG.push = {}; play(S8, OWNER, 65)
S8.Trigger(OWNER, "RaidWin")
check(play(S8, OWNER, 10) and shows() == 1 and LOG.push[#LOG.push].data.Trigger == "RaidWin", "RaidWin shows it early once")
-- the 3-day gap and Never still win
S8 = fresh(); LOG.push = {}; play(S8, OWNER, 65)
local p8 = PROFILES[OWNER.UserId]
p8.RatePrompt.Triggered = {}
S8.Trigger(OWNER, "FirstCapture")
check(not play(S8, OWNER, 30) and shows() == 0, "the 3-day gap still wins over a big-win trigger")
UNIX += 4 * 86400
p8.RatePrompt.Never = true
S8 = fresh(); LOG.push = {}; play(S8, OWNER, 65)
S8.Trigger(OWNER, "FirstCapture")
check(not play(S8, OWNER, 30) and shows() == 0, "Never still wins over a big-win trigger")
-- it waits for the Recruit Pack card
S8 = newcomer()
PACK_BUSY = true
S8.Trigger(OWNER, "FirstCapture")
check(not play(S8, OWNER, 40) and shows() == 0, "the Recruit Pack card is out / closed < 20 s ago: the rate card waits")
PACK_BUSY = false
check(play(S8, OWNER, 10) and shows() == 1, "... and shows once that card is gone")
S8 = newcomer()
PACK_DUE = true
S8.Trigger(OWNER, "FirstCapture")
check(not play(S8, OWNER, 60) and shows() == 0, "the Recruit Pack is still due from the same capture: it goes first")
check(play(S8, OWNER, 180) and shows() == 1, "... the rate card waits at most WaitForPackMaxSeconds, then may show")
PACK_DUE = false
check(LOG.economy == 0, "still no economy / XP call (the JOB 40 no-reward rule)")
local saved = PS.Migrate(deep(PROFILES[OWNER.UserId]))
check(saved.RatePrompt.Triggered ~= nil and saved.RatePrompt.Triggered.FirstCapture == true, "Triggered survives a save + Migrate")

print(string.format("RATE PROMPT TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

chunks = [PRELUDE, EXTRA]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
out = r.stdout.strip()
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("RATE PROMPT TEST")) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2500:])
    sys.exit(1)
