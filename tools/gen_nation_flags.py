#!/usr/bin/env python3
"""Render the nation-flag atlases (assets/flags/atlas_<group>.png) from the MIT-licensed lipis/flag-icons SVGs.

Usage:
    python3 tools/gen_nation_flags.py [--out assets/flags] [--per-flag [DIR]] [--contact-sheet PNG [--ids IE,JP,...]]
                                      [--tarball PATH] [--cache DIR] [--renderer auto|cairosvg|rsvg-convert|inkscape]
    python3 tools/gen_nation_flags.py --check    # re-render in memory, exit 1 if any committed atlas differs
                                                 # (byte-exact only with the renderer named in atlas_manifest.json)
    python3 tools/gen_nation_flags.py --verify   # no rendering, no network: manifest matches NationConfig, files match manifest

Needs Pillow plus one SVG renderer: the cairosvg module (pip install cairosvg), or rsvg-convert / inkscape on PATH.

What it does (nations spec, lane A0):
  * Reads the roster and the atlas layout from src/ReplicatedStorage/Shared/Configs/NationConfig.luau (Id, AtlasGroup,
    AtlasCell per nation; NationConfig.Atlas for sizes). NationConfig is the only source of truth: this tool never
    invents a cell.
  * Source art: flag-icons FLAG_ICONS_VERSION from the npm registry tarball, checked against its pinned sha512
    (FLAG_ICONS_INTEGRITY), plus the pinned upstream fixes in OVERRIDES (each checked against its sha256). The tarball
    is cached (--cache); --tarball uses a local copy (same integrity check). Nothing unpinned is ever rendered.
  * Each flag: the 4x3 SVG rendered at SUPERSAMPLE x the flag size, then downscaled (premultiplied alpha, Lanczos) to
    FlagW x FlagH, pasted in its cell with an edge-extended gutter (the flag's edge pixels repeated outward).
  * Writes atlas_<group>.png (one per NationConfig.Atlas.Groups entry), atlas_manifest.json (source pins, layout,
    per-atlas sha256 and cell table) and LICENSE-flag-icons.txt (version + the MIT licence text) into --out.
  * --per-flag writes PerFlagW x PerFlagH PNGs per nation (fallback path; default DIR = <out>/per-flag).
  * Checks: every atlas <= 1024 x 1024 px (Roblox downscales larger images) and <= MAX_ATLAS_BYTES; every flag fully
    opaque except NationConfig Cutout flags (Nepal); cells unique inside each atlas and inside the grid; no SVG pulls
    an external image.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "src" / "ReplicatedStorage" / "Shared" / "Configs" / "NationConfig.luau"
DEFAULT_OUT = ROOT / "assets" / "flags"

FLAG_ICONS_VERSION = "7.5.0"
FLAG_ICONS_TARBALL = f"https://registry.npmjs.org/flag-icons/-/flag-icons-{FLAG_ICONS_VERSION}.tgz"
# npm dist.integrity of flag-icons@7.5.0 (registry.npmjs.org/flag-icons, published 2025-05-29)
FLAG_ICONS_INTEGRITY = "sha512-kd+MNXviFIg5hijH766tt+3x76ele1AXlo4zDdCxIvqWZhKt4T83bOtxUOOMlTx/EcFdUMH5yvQgYlFh1EqqFg=="
FLAG_ICONS_REPO = "https://github.com/lipis/flag-icons"
# Upstream fixes made after the 7.5.0 release, pinned to a commit + sha256 (same project, same MIT licence).
OVERRIDE_COMMIT = "086f7e97d657358203916dbe84f61c2bccaa81eb"  # 2026-04-07 "Fix white border in Panama flag (#1440)"
OVERRIDES = {
    "pa": {
        "why": "7.5.0 draws a thin white border on the top and left edges; the official flag has none",
        "sha256": "5e034a8ad127c43b19f52c648fe808160ab4ddb117afa4204772af96566d31bc",
        "urls": [
            f"https://raw.githubusercontent.com/lipis/flag-icons/{OVERRIDE_COMMIT}/flags/4x3/pa.svg",
            f"https://cdn.jsdelivr.net/gh/lipis/flag-icons@{OVERRIDE_COMMIT}/flags/4x3/pa.svg",
        ],
    },
}

SUPERSAMPLE = 4
MAX_ATLAS_PX = 1024
MAX_ATLAS_BYTES = 1_000_000  # our own budget per atlas (Roblox's upload limit is far higher)
MANIFEST = "atlas_manifest.json"
LICENSE_FILE = "LICENSE-flag-icons.txt"


def fail(msg: str) -> None:
    print(f"ERROR {msg}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------------------------------------------------
# NationConfig parsing (the same file the game reads)
# ---------------------------------------------------------------------------------------------------------------------
NATION_ROW = re.compile(r'^\t\t\{ Id = "([^"]+)",(.*)\},\s*$', re.M)


def parse_config(path: Path) -> tuple[dict, list[dict]]:
    text = path.read_text(encoding="utf-8")
    m = re.search(r"\n\tAtlas = \{\n(.*?)\n\t\},\n", text, re.S)
    if not m:
        fail(f"NationConfig.Atlas block not found in {path}")
    block = m.group(1)
    layout: dict = {}
    for key in ("Width", "Height", "Columns", "Rows", "CellW", "CellH", "FlagW", "FlagH", "PerFlagW", "PerFlagH"):
        km = re.search(rf"^\t\t{key} = (\d+),", block, re.M)
        if not km:
            fail(f"NationConfig.Atlas.{key} not found")
        layout[key] = int(km.group(1))
    gm = re.search(r"^\t\tGroups = \{([^}]*)\}", block, re.M)
    if not gm:
        fail("NationConfig.Atlas.Groups not found")
    layout["Groups"] = re.findall(r'"(\w+)"', gm.group(1))
    nations = []
    for row in NATION_ROW.finditer(text):
        body = row.group(2)
        g = re.search(r'\bAtlasGroup = "(\w+)"', body)
        c = re.search(r"\bAtlasCell = (\d+)", body)
        if not g or not c:
            fail(f"nation {row.group(1)}: AtlasGroup / AtlasCell missing")
        nations.append({
            "Id": row.group(1),
            "AtlasGroup": g.group(1),
            "AtlasCell": int(c.group(1)),
            "Cutout": re.search(r"\bCutout = true\b", body) is not None,
        })
    if not nations:
        fail(f"no nation rows parsed from {path}")
    return layout, nations


def check_layout(layout: dict, nations: list[dict]) -> list[str]:
    errs = []
    L = layout
    if L["Columns"] * L["CellW"] > L["Width"] or L["Rows"] * L["CellH"] > L["Height"]:
        errs.append("cell grid does not fit the atlas")
    if L["Width"] > MAX_ATLAS_PX or L["Height"] > MAX_ATLAS_PX:
        errs.append(f"atlas larger than {MAX_ATLAS_PX} px")
    if L["FlagW"] > L["CellW"] or L["FlagH"] > L["CellH"]:
        errs.append("flag larger than its cell")
    if L["FlagW"] * 3 != L["FlagH"] * 4:
        errs.append("flag is not 4:3")
    seen_ids: set[str] = set()
    seen_cells: set[tuple[str, int]] = set()
    for n in nations:
        if n["Id"] in seen_ids:
            errs.append(f"duplicate id {n['Id']}")
        seen_ids.add(n["Id"])
        if n["AtlasGroup"] not in L["Groups"]:
            errs.append(f"{n['Id']}: unknown AtlasGroup {n['AtlasGroup']}")
        if not 0 <= n["AtlasCell"] < L["Columns"] * L["Rows"]:
            errs.append(f"{n['Id']}: AtlasCell {n['AtlasCell']} outside the {L['Columns']}x{L['Rows']} grid")
        key = (n["AtlasGroup"], n["AtlasCell"])
        if key in seen_cells:
            errs.append(f"{n['Id']}: cell {key} used twice")
        seen_cells.add(key)
    return errs


def cell_rect(layout: dict, cell: int) -> tuple[int, int, int, int]:
    """Flag pixels (x, y, w, h) of a cell; the same maths as NationTexture.CellRect."""
    col, row = cell % layout["Columns"], cell // layout["Columns"]
    gx = (layout["CellW"] - layout["FlagW"]) // 2
    gy = (layout["CellH"] - layout["FlagH"]) // 2
    return col * layout["CellW"] + gx, row * layout["CellH"] + gy, layout["FlagW"], layout["FlagH"]


# ---------------------------------------------------------------------------------------------------------------------
# Pinned source
# ---------------------------------------------------------------------------------------------------------------------
def sri_sha512(data: bytes) -> str:
    return "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode()


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "war-empire-gen-nation-flags"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def load_tarball(tarball: str | None, cache: Path) -> bytes:
    if tarball:
        data = Path(tarball).read_bytes()
        src = tarball
    else:
        cached = cache / f"flag-icons-{FLAG_ICONS_VERSION}.tgz"
        if cached.is_file():
            data = cached.read_bytes()
            src = str(cached)
        else:
            data = fetch(FLAG_ICONS_TARBALL)
            src = FLAG_ICONS_TARBALL
            if sri_sha512(data) == FLAG_ICONS_INTEGRITY:
                cache.mkdir(parents=True, exist_ok=True)
                cached.write_bytes(data)
    if sri_sha512(data) != FLAG_ICONS_INTEGRITY:
        fail(f"{src}: integrity mismatch (expected flag-icons {FLAG_ICONS_VERSION} {FLAG_ICONS_INTEGRITY})")
    return data


def load_override(name: str, cache: Path) -> bytes:
    o = OVERRIDES[name]
    cached = cache / f"override-{OVERRIDE_COMMIT[:7]}-{name}.svg"
    if cached.is_file() and hashlib.sha256(cached.read_bytes()).hexdigest() == o["sha256"]:
        return cached.read_bytes()
    last = None
    for url in o["urls"]:
        try:
            data = fetch(url)
        except OSError as err:  # try the next mirror
            last = err
            continue
        if hashlib.sha256(data).hexdigest() != o["sha256"]:
            last = ValueError(f"{url}: sha256 mismatch")
            continue
        cache.mkdir(parents=True, exist_ok=True)
        cached.write_bytes(data)
        return data
    fail(f"override {name}.svg could not be fetched: {last}")
    raise AssertionError


def load_sources(nations: list[dict], tarball: str | None, cache: Path) -> tuple[dict[str, bytes], str, str]:
    data = load_tarball(tarball, cache)
    svgs: dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
        pkg = json.loads(tf.extractfile("package/package.json").read())  # type: ignore[union-attr]
        if pkg.get("version") != FLAG_ICONS_VERSION or pkg.get("license") != "MIT":
            fail(f"tarball is flag-icons {pkg.get('version')} ({pkg.get('license')}), expected {FLAG_ICONS_VERSION} (MIT)")
        licence = tf.extractfile("package/LICENSE").read().decode("utf-8")  # type: ignore[union-attr]
        for n in nations:
            name = n["Id"].lower()
            if name in OVERRIDES:
                continue
            member = f"package/flags/4x3/{name}.svg"
            try:
                svgs[n["Id"]] = tf.extractfile(member).read()  # type: ignore[union-attr]
            except KeyError:
                fail(f"{n['Id']}: {member} is not in flag-icons {FLAG_ICONS_VERSION}")
    for n in nations:
        name = n["Id"].lower()
        if name in OVERRIDES:
            svgs[n["Id"]] = load_override(name, cache)
    for nid, svg in svgs.items():
        if b"<image" in svg or b"xlink:href=\"http" in svg or b"href=\"http" in svg:
            fail(f"{nid}: SVG references an external image")
    return svgs, licence, sri_sha512(data)


# ---------------------------------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------------------------------
def pick_renderer(name: str):
    def cairo(svg: bytes, w: int, h: int) -> bytes:
        import cairosvg  # type: ignore

        return cairosvg.svg2png(bytestring=svg, output_width=w, output_height=h)

    def cli(cmd_for):
        def run(svg: bytes, w: int, h: int) -> bytes:
            with tempfile.TemporaryDirectory() as td:
                src = Path(td) / "f.svg"
                dst = Path(td) / "f.png"
                src.write_bytes(svg)
                subprocess.run(cmd_for(src, dst, w, h), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                return dst.read_bytes()
        return run

    rsvg = cli(lambda s, d, w, h: ["rsvg-convert", "-w", str(w), "-h", str(h), "-o", str(d), str(s)])
    inkscape = cli(lambda s, d, w, h: ["inkscape", str(s), "--export-type=png", f"--export-filename={d}", "-w", str(w), "-h", str(h)])
    if name in ("auto", "cairosvg"):
        try:
            import cairosvg  # type: ignore  # noqa: F401

            import importlib.metadata as md

            return cairo, f"cairosvg {md.version('cairosvg')}"
        except ImportError:
            if name == "cairosvg":
                fail("cairosvg is not installed (pip install cairosvg)")
    if name in ("auto", "rsvg-convert") and shutil.which("rsvg-convert"):
        return rsvg, "rsvg-convert"
    if name in ("auto", "inkscape") and shutil.which("inkscape"):
        return inkscape, "inkscape"
    fail("no SVG renderer: pip install cairosvg, or install rsvg-convert (librsvg) or inkscape")
    raise AssertionError


def render_flag(render, svg: bytes, w: int, h: int):
    from PIL import Image

    big = Image.open(io.BytesIO(render(svg, w * SUPERSAMPLE, h * SUPERSAMPLE))).convert("RGBA")
    if big.size != (w * SUPERSAMPLE, h * SUPERSAMPLE):
        big = big.resize((w * SUPERSAMPLE, h * SUPERSAMPLE), Image.LANCZOS)
    small = big.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")
    return small


def bleed_rgb(flag):
    """Fill the RGB of fully transparent pixels from the nearest covered colour (alpha unchanged), so filtering and
    mipmaps never pull a dark fringe in."""
    from PIL import Image, ImageFilter

    alpha = flag.getchannel("A")
    out = flag.copy()
    hole = alpha.point(lambda a: 255 if a == 0 else 0)
    premult = flag.convert("RGBa")
    for radius in (1, 2, 4, 8, 16, 32, 64, 128):
        if hole.getbbox() is None:
            break
        blurred = premult.filter(ImageFilter.BoxBlur(radius)).convert("RGBA")
        reached = blurred.getchannel("A").point(lambda a: 255 if a > 0 else 0)
        take = Image.composite(reached, Image.new("L", hole.size, 0), hole)  # holes the blur reached this round
        rgb = Image.composite(blurred.convert("RGB"), out.convert("RGB"), take)
        out = Image.merge("RGBA", (*rgb.split(), alpha))
        hole = Image.composite(Image.new("L", hole.size, 0), hole, take)
    return out


def finish_flag(flag, nid: str, cutout: bool):
    """Rectangular flags end fully opaque. Adjacent SVG shapes leave anti-aliasing seams of partial coverage (alpha
    188-254 at stripe borders at 104x78) and a few SVGs stop a fraction of a pixel short of the edge (Bahamas,
    Papua New Guinea); straight RGB there is already the coverage-weighted colour, so only the alpha changes and a
    Texture never shows the part through a seam. More than 1% nearly-empty pixels means a non-rectangular flag:
    the build fails until it is marked Cutout in NationConfig. Cutout flags (Nepal) keep their alpha."""
    out = bleed_rgb(flag)
    if cutout:
        return out
    hist = flag.getchannel("A").histogram()
    empty = sum(hist[:16]) / (flag.width * flag.height)
    if empty > 0.01:
        fail(f"{nid}: {empty:.1%} of the flag is transparent; mark it Cutout in NationConfig or fix the SVG")
    out.putalpha(255)
    return out


def cell_tile(flag, layout: dict):
    """The flag centred in a CellW x CellH tile, its edge pixels repeated into the gutter (no neighbour bleed)."""
    from PIL import Image

    cw, ch, fw, fh = layout["CellW"], layout["CellH"], layout["FlagW"], layout["FlagH"]
    gx, gy = (cw - fw) // 2, (ch - fh) // 2
    tile = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    tile.paste(flag, (gx, gy))
    if gx > 0:
        tile.paste(flag.crop((0, 0, 1, fh)).resize((gx, fh), Image.NEAREST), (0, gy))
    if cw - gx - fw > 0:
        tile.paste(flag.crop((fw - 1, 0, fw, fh)).resize((cw - gx - fw, fh), Image.NEAREST), (gx + fw, gy))
    if gy > 0:
        tile.paste(tile.crop((0, gy, cw, gy + 1)).resize((cw, gy), Image.NEAREST), (0, 0))
    if ch - gy - fh > 0:
        tile.paste(tile.crop((0, gy + fh - 1, cw, gy + fh)).resize((cw, ch - gy - fh), Image.NEAREST), (0, gy + fh))
    return tile


def png_bytes(im) -> bytes:
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def build(layout: dict, nations: list[dict], svgs: dict[str, bytes], render) -> tuple[dict[str, bytes], dict, dict]:
    from PIL import Image

    atlases = {g: Image.new("RGBA", (layout["Width"], layout["Height"]), (0, 0, 0, 0)) for g in layout["Groups"]}
    flags = {}
    problems = []
    for n in nations:
        flag = finish_flag(render_flag(render, svgs[n["Id"]], layout["FlagW"], layout["FlagH"]), n["Id"], n["Cutout"])
        if not n["Cutout"] and flag.getchannel("A").getextrema() != (255, 255):
            problems.append(f"{n['Id']}: flag is not fully opaque")
        elif n["Cutout"] and flag.getchannel("A").getextrema()[0] == 255:
            problems.append(f"{n['Id']}: marked Cutout but has no transparent pixels")
        flags[n["Id"]] = flag
        col, row = n["AtlasCell"] % layout["Columns"], n["AtlasCell"] // layout["Columns"]
        atlases[n["AtlasGroup"]].paste(cell_tile(flag, layout), (col * layout["CellW"], row * layout["CellH"]))
    if problems:
        fail("; ".join(problems))
    out = {g: png_bytes(im) for g, im in atlases.items()}
    cells: dict[str, dict] = {g: {} for g in layout["Groups"]}
    for n in nations:
        cells[n["AtlasGroup"]][n["Id"]] = [n["AtlasCell"], *cell_rect(layout, n["AtlasCell"])]
    return out, cells, flags


def manifest_for(layout, nations, out, cells, svgs, integrity, renderer_name) -> dict:
    return {
        "generator": "tools/gen_nation_flags.py",
        "source": {
            "package": "flag-icons",
            "version": FLAG_ICONS_VERSION,
            "repo": FLAG_ICONS_REPO,
            "tarball": FLAG_ICONS_TARBALL,
            "integrity": integrity,
            "licence": "MIT",
            "overrides": {k: {"commit": OVERRIDE_COMMIT, "sha256": v["sha256"], "why": v["why"]} for k, v in OVERRIDES.items()},
            "svg_sha256": {n["Id"]: hashlib.sha256(svgs[n["Id"]]).hexdigest() for n in nations},
        },
        "renderer": renderer_name,
        "supersample": SUPERSAMPLE,
        "layout": {k: layout[k] for k in ("Width", "Height", "Columns", "Rows", "CellW", "CellH", "FlagW", "FlagH", "Groups")},
        "atlases": {
            g: {
                "file": f"atlas_{g}.png",
                "width": layout["Width"],
                "height": layout["Height"],
                "bytes": len(out[g]),
                "sha256": hashlib.sha256(out[g]).hexdigest(),
                "count": len(cells[g]),
                "cells": dict(sorted(cells[g].items())),  # id: [cell, x, y, w, h]
            }
            for g in layout["Groups"]
        },
    }


def licence_text(licence: str, integrity: str) -> str:
    over = "\n".join(
        f"  flags/4x3/{k}.svg from commit {OVERRIDE_COMMIT} (sha256 {v['sha256']}): {v['why']}" for k, v in OVERRIDES.items()
    )
    return (
        "Nation flag images in this folder (atlas_*.png, per-flag/*.png) are rendered from flag-icons.\n\n"
        f"Project:  flag-icons by Panayiotis Lipiridis, {FLAG_ICONS_REPO}\n"
        f"Version:  {FLAG_ICONS_VERSION} (npm), {FLAG_ICONS_TARBALL}\n"
        f"Integrity: {integrity}\n"
        f"Upstream fixes applied after that release (same repository, same licence):\n{over}\n"
        "Changes:  the 4x3 SVGs are rasterised to PNG, downscaled and packed into atlases with an edge-extended gutter\n"
        "          by tools/gen_nation_flags.py. The flag designs are not altered.\n"
        "Licence:  MIT (full text below, copied from the package's LICENSE file).\n\n"
        "-------------------------------------------------------------------------------\n"
        f"{licence.strip()}\n"
    )


# ---------------------------------------------------------------------------------------------------------------------
# Contact sheet (spot-check: crops the written atlases with the manifest rects)
# ---------------------------------------------------------------------------------------------------------------------
def contact_sheet(out_dir: Path, manifest: dict, ids: list[str], dest: Path) -> None:
    from PIL import Image, ImageDraw

    where = {nid: (g, v) for g, a in manifest["atlases"].items() for nid, v in a["cells"].items()}
    scale = 2
    fw, fh = manifest["layout"]["FlagW"] * scale, manifest["layout"]["FlagH"] * scale
    cols = 4
    rows = (len(ids) + cols - 1) // cols
    pad = 12
    sheet = Image.new("RGB", (cols * (fw + pad) + pad, rows * (fh + pad + 22) + pad), (48, 52, 58))
    draw = ImageDraw.Draw(sheet)
    cache: dict[str, object] = {}
    for i, nid in enumerate(ids):
        if nid not in where:
            fail(f"contact sheet: unknown id {nid}")
        g, (cell, x, y, w, h) = where[nid]
        if g not in cache:
            cache[g] = Image.open(out_dir / f"atlas_{g}.png").convert("RGBA")
        crop = cache[g].crop((x, y, x + w, y + h)).resize((fw, fh), Image.NEAREST)  # type: ignore[attr-defined]
        bg = Image.new("RGBA", crop.size, (48, 52, 58, 255))
        bg.alpha_composite(crop)
        cx, cy = pad + (i % cols) * (fw + pad), pad + (i // cols) * (fh + pad + 22)
        sheet.paste(bg.convert("RGB"), (cx, cy))
        draw.text((cx, cy + fh + 4), f"{nid}  {g}#{cell}  ({x},{y})", fill=(235, 235, 235))
    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dest)
    print(f"contact sheet {dest} ({len(ids)} flags)")


# ---------------------------------------------------------------------------------------------------------------------
def verify(out_dir: Path, layout: dict, nations: list[dict]) -> int:
    """No rendering: the committed manifest matches NationConfig, and every atlas file matches the manifest."""
    errs = check_layout(layout, nations)
    mpath = out_dir / MANIFEST
    if not mpath.is_file():
        errs.append(f"missing {mpath}")
    else:
        man = json.loads(mpath.read_text(encoding="utf-8"))
        want = {g: {} for g in layout["Groups"]}
        for n in nations:
            want[n["AtlasGroup"]][n["Id"]] = [n["AtlasCell"], *cell_rect(layout, n["AtlasCell"])]
        for k in ("Width", "Height", "Columns", "Rows", "CellW", "CellH", "FlagW", "FlagH", "Groups"):
            if man["layout"].get(k) != layout[k]:
                errs.append(f"manifest layout {k} {man['layout'].get(k)} != NationConfig {layout[k]} (re-run the generator)")
        if man["source"].get("version") != FLAG_ICONS_VERSION:
            errs.append(f"manifest source version {man['source'].get('version')} != pinned {FLAG_ICONS_VERSION}")
        for g in layout["Groups"]:
            a = man["atlases"].get(g)
            if a is None:
                errs.append(f"manifest has no atlas {g}")
                continue
            if a["cells"] != dict(sorted(want[g].items())):
                errs.append(f"atlas_{g}: cells differ from NationConfig (re-run the generator and re-upload atlas_{g}.png)")
            f = out_dir / a["file"]
            if not f.is_file():
                errs.append(f"missing {f}")
            elif hashlib.sha256(f.read_bytes()).hexdigest() != a["sha256"]:
                errs.append(f"{f.name}: sha256 differs from the manifest")
    if not (out_dir / LICENSE_FILE).is_file():
        errs.append(f"missing {out_dir / LICENSE_FILE}")
    for e in errs:
        print(f"FAIL {e}", file=sys.stderr)
    print(f"verify: {'FAIL' if errs else 'ok'} ({len(nations)} nations, {len(layout['Groups'])} atlases)")
    return 1 if errs else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Render the nation-flag atlases from pinned flag-icons SVGs")
    ap.add_argument("--config", default=str(CONFIG))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--per-flag", nargs="?", const="", default=None, metavar="DIR", help="also write one PNG per nation")
    ap.add_argument("--contact-sheet", default=None, metavar="PNG")
    ap.add_argument("--ids", default="IE,JP,BR,US,GB,NP,CH,VA,QA,ZA,KE,TW,PS", help="contact-sheet ids (comma separated)")
    ap.add_argument("--tarball", default=None, help=f"local flag-icons-{FLAG_ICONS_VERSION}.tgz (integrity-checked)")
    ap.add_argument("--cache", default=os.environ.get("WE_FLAG_CACHE", str(Path.home() / ".cache" / "war-empire-flags")))
    ap.add_argument("--renderer", default="auto", choices=["auto", "cairosvg", "rsvg-convert", "inkscape"])
    ap.add_argument("--check", action="store_true", help="re-render in memory; exit 1 if a committed atlas differs")
    ap.add_argument("--verify", action="store_true", help="no rendering: manifest vs NationConfig vs files")
    args = ap.parse_args(argv)

    out_dir = Path(args.out)
    layout, nations = parse_config(Path(args.config))
    if args.verify:
        return verify(out_dir, layout, nations)
    errs = check_layout(layout, nations)
    if errs:
        fail("; ".join(errs))

    try:
        import PIL  # noqa: F401
    except ImportError:
        fail("Pillow is not installed (pip install pillow)")
    render, renderer_name = pick_renderer(args.renderer)
    svgs, licence, integrity = load_sources(nations, args.tarball, Path(args.cache))
    out, cells, flags = build(layout, nations, svgs, render)
    man = manifest_for(layout, nations, out, cells, svgs, integrity, renderer_name)

    for g in layout["Groups"]:
        if len(out[g]) > MAX_ATLAS_BYTES:
            fail(f"atlas_{g}.png is {len(out[g])} bytes (> {MAX_ATLAS_BYTES})")

    if args.check:
        bad = 0
        for g in layout["Groups"]:
            f = out_dir / f"atlas_{g}.png"
            if not f.is_file() or f.read_bytes() != out[g]:
                print(f"FAIL {f} differs from a fresh render", file=sys.stderr)
                bad += 1
        print(f"check: {'FAIL' if bad else 'ok'} ({len(layout['Groups'])} atlases, renderer {renderer_name})")
        return 1 if bad else 0

    out_dir.mkdir(parents=True, exist_ok=True)
    for g in layout["Groups"]:
        (out_dir / f"atlas_{g}.png").write_bytes(out[g])
        print(f"atlas_{g}.png  {layout['Width']}x{layout['Height']}  {len(cells[g]):>2} flags  {len(out[g]) // 1024} KB")
    (out_dir / MANIFEST).write_text(json.dumps(man, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    (out_dir / LICENSE_FILE).write_text(licence_text(licence, integrity), encoding="utf-8")
    print(f"{len(nations)} flags, flag-icons {FLAG_ICONS_VERSION} ({integrity[:19]}...), renderer {renderer_name} -> {out_dir}")

    if args.per_flag is not None:
        pdir = Path(args.per_flag) if args.per_flag else out_dir / "per-flag"
        pdir.mkdir(parents=True, exist_ok=True)
        for n in nations:
            im = finish_flag(render_flag(render, svgs[n["Id"]], layout["PerFlagW"], layout["PerFlagH"]), n["Id"], n["Cutout"])
            (pdir / f"{n['Id']}.png").write_bytes(png_bytes(im))
        print(f"per-flag: {len(nations)} PNGs ({layout['PerFlagW']}x{layout['PerFlagH']}) -> {pdir}")

    if args.contact_sheet:
        contact_sheet(out_dir, man, [s.strip() for s in args.ids.split(",") if s.strip()], Path(args.contact_sheet))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
