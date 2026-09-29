# claude-bud JOB 25 (2026-09-29): "<Name>'s Empire" base signs + the flag work that exists (nations spec). Static pins.
import re as _j25_re
from pathlib import Path as _J25P

if "ok" not in globals():
    _j25_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j25_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J25P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j25(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J25: " + msg)


def _j25_code(path):
    return "\n".join(l.split("--", 1)[0] for l in (read(path) or "").splitlines())


_BSC = read("src/ReplicatedStorage/Shared/Configs/BaseSignConfig.luau") or ""
_BSS = _j25_code("src/ServerScriptService/Server/Services/BaseSignService.luau")
_NC = read("src/ReplicatedStorage/Shared/Configs/NationConfig.luau") or ""
_j25("\tEnabled = true," in _BSC and "\tCustomEmpireNames = false," in _BSC, "base signs on (kill switch Enabled); no player-typed empire names")
_j25('Instance.new("BillboardGui")' in _BSS and "UDim2.fromOffset(C.SizePx.X, C.SizePx.Y)" in _BSS and "gui.AlwaysOnTop = false" in _BSS,
    "one server-built BillboardGui per plot, fixed pixel size, never on top of the HUD")
_j25("SurfaceGui" not in _BSS, "the flag is never a GUI (CLAUDE.md: flags in the world are Textures)")
_j25("nf.DressPart, s.Plate, view" in _BSS and "function NationFlag.DressPart(" in _j25_code("src/ServerScriptService/Server/Modules/NationFlag.luau"),
    "the sign's flag plate is dressed by NationFlag (Textures, the owner's own pick)")
_j25("rbxthumb://type=AvatarHeadShot" in _BSS and "owner.DisplayName" in _BSS and "UnclaimedTitle" in _BSS, "headshot + DisplayName's Empire; empty plots say UNCLAIMED")
_j25("shownKey[plotId] == key" in _BSS and "UpdateSeconds" in _BSS and "RenderStepped" not in _BSS and "Heartbeat" not in _BSS, "updates only on change, no per-frame work")
# nation rules kept (CLAUDE.md): the IP suggestion is never auto-applied, no outpost flags, no country on the boards
_j25("\tSuggestPreselect = false," in _NC and "\tOutpostFlags = false," in _NC, "IP suggestion never preselected; outposts keep banner colours")
_eng = _j25_code("src/ServerScriptService/Server/Services/EngagementService.luau")
_j25("NationId" not in _eng and "WE_NationId" not in _eng, "no nation on the leaderboards")
_feat = _j25_re.search(r"Featured = \{([^}]*)\}", _NC, _j25_re.S)
_ids = set(_j25_re.findall(r'Id = "([A-Z\-]+)"', _NC))
_fl = _j25_re.findall(r'"([A-Z\-]+)"', _feat.group(1)) if _feat else []
_j25(len(_fl) >= 55 and all(i in _ids for i in _fl), f"the ~60 most common first ({len(_fl)}), every one on the roster")
