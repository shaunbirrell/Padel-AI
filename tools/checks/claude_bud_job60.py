# claude-bud JOB 60 (2026-10-01): the error report. Without the Creator Hub CSV text (message + script + asset id) only the
# code-provable causes are pinned here; the rest is reported as blocked in LATEST-HANDOFF (no symptom patches).
# Executed inside tools/BuyPathStatic.py (ok / bad).
import re as _j60_re
from pathlib import Path as _J60P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j60_src(p):
    q = _J60P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


# 1. AnchorPoint nil (67): the root cause was the TARGETS crosshair reading spec[5] (Code Bot v171). Every non-literal
#    AnchorPoint source must be a defined config field / spec slot.
_bad = []
for _p in _J60P("src").rglob("*.luau"):
    for _i, _l in enumerate(_p.read_text(encoding="utf-8").splitlines(), 1):
        _m = _j60_re.search(r"\.AnchorPoint = ([^\s-]+)(.*)$", _l)
        if _m and not _m.group(1).startswith("Vector2") and " or Vector2" not in _m.group(2):
            _bad.append((str(_p).replace("\\", "/"), _i, _m.group(1)))
_known = {"AM.Anchor", "TC.Fire.Anchor", "TC.Reload.Anchor", "e.Anchor", "spec[4]"}
(ok if all(b[2] in _known for b in _bad) else bad)(
    "CLAUDE-BUD J60: every non-literal AnchorPoint source is a known, defined field (new ones: %s)" % [b for b in _bad if b[2] not in _known])
_H = _j60_src("src/ReplicatedStorage/Shared/Configs/HudConfig.luau")
(ok if ("HudConfig.Ammo = {" in _H and "HudConfig.TouchCombat = {" in _H and _H.count("Anchor = Vector2") >= 3) else bad)(
    "CLAUDE-BUD J60: the combat HUD anchors exist in HudConfig (Ammo / TouchCombat Fire / Reload)")
_RV = _j60_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RivalController.luau")
(ok if "f.AnchorPoint = spec[4]" in _RV else bad)("CLAUDE-BUD J60: the TARGETS crosshair reads its real anchor slot (the v171 root-cause fix stays)")
# 2. animation-track limit (340): the game's own tracks are cached per Animator (WeaponVisuals) or destroyed with their
#    figure (RigAnimator), so they never pile up on one Animator.
_WV = _j60_src("src/StarterPlayer/StarterPlayerScripts/Client/Modules/WeaponVisuals.luau")
_tf = _WV.split("local function trackFor(")[1].split("\nend\n")[0] if "local function trackFor(" in _WV else ""
(ok if ("local cached = if set then set.Tracks[key] else nil" in _tf and "into.Tracks[key] = track" in _tf) else bad)(
    "CLAUDE-BUD J60: WeaponVisuals loads a gun animation once per Animator (cached track, never re-loaded)")
_RA = _j60_src("src/StarterPlayer/StarterPlayerScripts/Client/Modules/RigAnimator.luau")
_st = _RA.split("local function stopTracks(")[1].split("\nend\n")[0] if "local function stopTracks(" in _RA else ""
(ok if ("tr:Destroy()" in _st and "if e.Tracks == nil then" in _RA and _RA.count("loadTracks(") == 3) else bad)(
    "CLAUDE-BUD J60: RigAnimator loads tracks only when a figure has none and destroys them on stop (no stacking)")
_n = sum(len(_j60_re.findall(r"LoadAnimation", p.read_text(encoding="utf-8"))) for p in _J60P("src").rglob("*.luau"))
(ok if _n <= 6 else bad)("CLAUDE-BUD J60: no new LoadAnimation call sites outside the two cached paths (%d mentions)" % _n)
# 3. sanitized-ID moods: the v148 guard stays on (its real-player effect is read from the next error report)
_RC = _j60_src("src/ReplicatedStorage/Shared/Configs/RigConfig.luau")
(ok if ('FallbackId = "rbxassetid://14366558676"' in _RC and "KnownBad = {" in _RC) else bad)("CLAUDE-BUD J60: the avatar mood guard keeps Roblox's default mood fallback + the known-bad list")
