# Code Bot Roblox v205 (2026-10-01/02): owner "switch the 2x event notification ON for everyone now".
# EventConfig.ChipPublic = true (DISPLAY ONLY): the DOUBLE WEEKEND chip shows for EVERYONE before the start as a
# countdown to it ("2x WEEKEND · in 21h 6m"; tap = details "starts in ..."). The 2x itself is untouched: StartUnix /
# EndUnix / multipliers / reasons / OwnerFirst / ActiveFor / DoubleEvent byte-identical to the previous ship.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes.
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V205_PREV", "b82cee1")  # the previous ship's code tip
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def code(src):
    src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
    return "\n".join(l.split("--", 1)[0] for l in src.splitlines())


for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 214'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 214'),
    (S + "Services/DataService.luau", "WE_Build=214"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 214'),
):
    check(needle in read(rel), "CODEBOT v205: WE_Build=214 " + rel.rsplit("/", 1)[-1])

EC = read(C + "EventConfig.luau")
check("\tChipPublic = true,\n" in EC, "CODEBOT v205: EventConfig.ChipPublic = true (chip for everyone before the start)")
check("StartUnix = 1790971200" in EC and "EndUnix = 1791144000" in EC, "CODEBOT v205: event window unchanged")
check("XPMult = 2," in EC and "CashMult = 2," in EC and "KillMult = 2," in EC, "CODEBOT v205: multipliers unchanged")
check("OwnerFirst = true, -- NEW-OWNER-FIRST (Code Bot v185)" in EC, "CODEBOT v205: OwnerFirst (owner preview of the real 2x) unchanged")
DE = read(S + "Modules/DoubleEvent.luau")
check("ChipPublic" not in DE, "CODEBOT v205: DoubleEvent (server rewards) never reads ChipPublic")
for rel in (S + "Services/EconomyService.luau", S + "Services/XPService.luau", S + "Services/RetentionService.luau"):
    if (ROOT / rel).exists():
        check("ChipPublic" not in read(rel), "CODEBOT v205: no ChipPublic in " + rel.rsplit("/", 1)[-1])

prev_ec = shipped(C + "EventConfig.luau", PREV)
if prev_ec is not None:
    strip = lambda t: re.sub(r"\t-- Code Bot v\w+ \(owner 2026-10-01: \"switch the 2x event.*?\tChipPublic = true,\n", "", t, flags=re.S)
    check(strip(EC) == prev_ec, "CODEBOT v205: EventConfig identical to %s outside the ChipPublic block" % PREV)
    check(shipped(S + "Modules/DoubleEvent.luau", PREV) == DE, "CODEBOT v205: DoubleEvent byte-identical to %s" % PREV)

UI = code(read(CL + "Controllers/DoubleWeekendController.luau"))
check("local live = EventConfig.ActiveFor(player.UserId, t, previewOn())" in UI, "CODEBOT v205: live still = ActiveFor (the real 2x)")
check("local soon = not live and EventConfig.ChipPublic == true and t < EventConfig.StartUnix" in UI
      and "local show = (live or soon) and pop == nil" in UI, "CODEBOT v205: chip shows live OR (ChipPublic and before the start)")
check('else EventConfig.ChipText .. " · in " .. EventConfig.FormatLeft(EventConfig.StartUnix - t)' in UI,
      "CODEBOT v205: before the start (not live) the chip counts down to the START, never claims 2x is on")
check('then EventConfig.ChipText .. " · " .. EventConfig.FormatLeft(EventConfig.EndUnix - t)' in UI, "CODEBOT v205: live text unchanged")
check('if EventConfig.ActiveFor(player.UserId, t, previewOn()) then "  (OWNER PREVIEW)" else ""' in UI,
      "CODEBOT v205: OWNER PREVIEW tag only for the owner preview")

# sim: the real EventConfig under luau, the controller's chip expression, owner / player, before / during / after
if os.path.exists(LUAU):
    ecsrc = read(C + "EventConfig.luau").replace("--!strict", "")
    lua = "local EventConfig = (function()\n" + ecsrc + "\nend)()\n" + r'''
local function chip(uid, t, prev)
  if t >= EventConfig.EndUnix then return "hidden" end
  local live = EventConfig.ActiveFor(uid, t, prev)
  local soon = not live and EventConfig.ChipPublic == true and t < EventConfig.StartUnix
  if not (live or soon) then return "hidden" end
  if live then return EventConfig.ChipText .. " · " .. EventConfig.FormatLeft(EventConfig.EndUnix - t) end
  return EventConfig.ChipText .. " · in " .. EventConfig.FormatLeft(EventConfig.StartUnix - t)
end
local S, E = EventConfig.StartUnix, EventConfig.EndUnix
local now = S - (20 * 3600 + 6 * 60)
print("A", chip(1, now, true))
print("B", chip(470626172, now, true))
print("C", chip(1, S + 3600, true))
print("D", chip(1, E, true))
print("E", chip(1, S - 3 * 86400, false))
print("F", tostring(EventConfig.ActiveFor(1, now, true)))
'''
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(lua)
    r = subprocess.run([LUAU, f.name], capture_output=True, text=True)
    os.unlink(f.name)
    out = dict(l.split("\t", 1) for l in r.stdout.splitlines() if "\t" in l)
    check(out.get("A") == "2x WEEKEND · in 20h 6m", "CODEBOT v205 sim: a player before the start sees '%s'" % out.get("A"))
    check(out.get("B") == "2x WEEKEND · 2d 20h", "CODEBOT v205 sim: the owner (preview) still sees '%s'" % out.get("B"))
    check(out.get("C") == "2x WEEKEND · 1d 23h", "CODEBOT v205 sim: in the window a player sees the live countdown '%s'" % out.get("C"))
    check(out.get("D") == "hidden", "CODEBOT v205 sim: nothing after EndUnix")
    check(out.get("E") == "2x WEEKEND · in 3d 0h", "CODEBOT v205 sim: ChipPublic shows before the start ('%s')" % out.get("E"))
    check(out.get("F") == "false", "CODEBOT v205 sim: the 2x is still NOT active for a player before the start")

# never regress the platform pins
check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v205: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v205: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v205: StreamingEnabled stays OFF")
