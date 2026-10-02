#!/usr/bin/env python3
"""claude-bud JOB 14 (2026-09-29): sound pass audit.

  1. Every sound key the code plays by name (AudioController.Play("X"), GameFeelConfig.Sounds, Juice / FX literals)
     exists in SoundConfig.Sounds  -> a missing key is a silent action: FAIL.
  2. Every SoundConfig.Sounds entry has a Bus with a band in SoundConfig.Mix.Bands and a Volume inside it
     -> outside = listed (AudioController clamps it into the band while Mix.BandsLive), not a failure.
Usage: python tools/sound_audit.py   (exit 1 on a missing key or a bus without a band)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SC = (ROOT / "src/ReplicatedStorage/Shared/Configs/SoundConfig.luau").read_text(encoding="utf-8")
GF = (ROOT / "src/ReplicatedStorage/Shared/Configs/GameFeelConfig.luau").read_text(encoding="utf-8")


def sounds():
    out = {}
    for m in re.finditer(r'\[\"([\w.]+)\"\] = \{([^\n]*)\}', SC):
        body = m.group(2)
        vol = re.search(r"\bVolume = ([\d.]+)", body)
        bus = re.search(r'\bBus = "(\w+)"', body)
        out[m.group(1)] = (float(vol.group(1)) if vol else None, bus.group(1) if bus else "World")
    return out


def bands():
    i = SC.index("Bands = {")
    j = SC.index("} :: { [string]: { number } }", i)
    return {m.group(1): (float(m.group(2)), float(m.group(3))) for m in re.finditer(r"(\w+) = \{ ([\d.]+), ([\d.]+) \}", SC[i:j])}


def referenced():
    refs = {}
    for p in (ROOT / "src").rglob("*.luau"):
        t = p.read_text(encoding="utf-8")
        for m in re.finditer(r'(?:AudioController|Audio|A)\.Play,? ?\(?\s*"([A-Z][\w]*\.[\w.]+)"', t):
            refs.setdefault(m.group(1), str(p.relative_to(ROOT)))
        for m in re.finditer(r'pcall\(\(?(?:Audio|A)(?: :: any)?\)?\.Play, "([A-Z][\w]*\.[\w.]+)"', t):
            refs.setdefault(m.group(1), str(p.relative_to(ROOT)))
    i = GF.index("Sounds = {")
    j = GF.index("\n\t},", i)
    for m in re.finditer(r'= "([A-Z][\w]*\.[\w.]+)"', GF[i:j]):
        refs.setdefault(m.group(1), "GameFeelConfig.Sounds")
    return refs


def audit():
    s, b, refs = sounds(), bands(), referenced()
    missing = sorted(k for k in refs if k not in s)
    nobus = sorted(k for k, (_, bus) in s.items() if bus not in b)
    outside = []
    for k, (vol, bus) in sorted(s.items()):
        if vol is not None and bus in b and not (b[bus][0] <= vol <= b[bus][1]):
            outside.append((k, bus, vol, b[bus]))
    return s, b, refs, missing, nobus, outside


if __name__ == "__main__":
    s, b, refs, missing, nobus, outside = audit()
    print("[sound_audit] %d sounds, %d referenced keys, bands %s" % (len(s), len(refs), b))
    for k in missing:
        print("  MISSING key %s (played by %s)" % (k, refs[k]))
    for k in nobus:
        print("  NO BAND for bus of %s" % k)
    for k, bus, vol, band in outside:
        print("  clamped: %s (%s) volume %.2f -> band %s" % (k, bus, vol, band))
    ok = not missing and not nobus
    print("[sound_audit] %s" % ("OK" if ok else "FAIL"))
    sys.exit(0 if ok else 1)
