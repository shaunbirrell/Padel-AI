# Code Bot Roblox v125 (2026-09-30): ship Claude JOB 29 retention (FastStart, offline earnings,
# tomorrow's streak reward, notification opt-in). OwnerFirst retained. WE_Build 125.
from pathlib import Path as _P125

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P125(path).read_text(encoding="utf-8") if _P125(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)


def _cb125(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


_S125 = "src/ServerScriptService/Server/"
for _f in (_S125 + "Services/DataService.luau", _S125 + "Services/BaseService.luau", _S125 + "EarlyRemotes.server.luau"):
    must_contain(_f, 'SetAttribute("WE_Build", 125)', "CODEBOT v125: WE_Build=125 " + _f.rsplit("/", 1)[-1])
must_contain(_S125 + "Services/DataService.luau", "WE_Build=125", "CODEBOT v125: DataService profile-loaded log says WE_Build=125")

# JOB 29 retention still OwnerFirst; PreferMesh stays OFF; WE_Building* untouched (pin presence only)
_rc = _P125("src/ReplicatedStorage/Shared/Configs/RetentionConfig.luau").read_text(encoding="utf-8")
_cb125("OwnerFirst = true" in _rc and "function RetentionConfig.Live(" in _rc, "CODEBOT v125: RetentionConfig OwnerFirst=true + Live()")
_cb125(_P125("tools/checks/claude_bud_job29.py").is_file(), "CODEBOT v125: claude_bud_job29.py present")
