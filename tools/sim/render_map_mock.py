"""Code Bot MAP-REDESIGN (v129): draws the phone world map from the layout the REAL MapLabelLayout computed
(tools/sim/run_map_layout_test.py --json), the same way MapController builds it: sand terrain + roads + grid, icons,
label pills, vignette, frame + corner brackets, compass, zoom + close buttons and the side card with the legend.
A preview for the owner (Montserrat stands in for Gotham); the geometry is the test's, not hand-placed.
Run: python3 tools/sim/render_map_mock.py layout.json out.png [zoom2_out.png]"""
import json
import re
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
PXV = 1.4  # real px per v at 2x retina (0.70 HUD scale x 2)
FONT = "/usr/share/fonts/truetype/sand-box/google/Montserrat/Montserrat-VariableFont_wght.ttf"


def font(v, weight="Medium"):
    f = ImageFont.truetype(FONT, max(8, int(round(v * PXV * 0.92))))
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def rgb(s):
    return tuple(int(x) for x in s)


cfg = (ROOT / "src/ReplicatedStorage/Shared/Configs/MapConfig.luau").read_text()
COL = {m.group(1): (int(m.group(2)), int(m.group(3)), int(m.group(4))) for m in re.finditer(r"\t\t(\w+) = Color3\.fromRGB\((\d+), (\d+), (\d+)\)", cfg)}
water = (ROOT / "src/ReplicatedStorage/Shared/Configs/WaterConfig.luau").read_text()
ROADS = [(m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))) for m in re.finditer(r'\["Road([XZ])(-?\d+)"\] = \{ Min = (-?\d+), Max = (-?\d+) \}', water)]
GROUP_SHAPE = {"Town": "square", "Military": "bars", "Industry": "dot", "Wilds": "ring", "Site": "cross"}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def icon(d, x, y, s, fill, shape, stroke=(10, 12, 10)):
    r = s / 2 * PXV
    d.ellipse([x - r - 1.5 * PXV, y - r - 1.5 * PXV, x + r + 1.5 * PXV, y + r + 1.5 * PXV], fill=stroke)
    d.ellipse([x - r, y - r, x + r, y + r], fill=fill)
    q = r * 0.42
    w = (255, 255, 255)
    if shape == "square":
        d.rectangle([x - q, y - q, x + q, y + q], fill=w)
    elif shape == "diamond":
        d.polygon([(x, y - q * 1.3), (x + q * 1.3, y), (x, y + q * 1.3), (x - q * 1.3, y)], fill=w)
    elif shape == "bars":
        for yy in (y - q * 0.55, y + q * 0.55):
            d.rectangle([x - q * 1.2, yy - q * 0.34, x + q * 1.2, yy + q * 0.34], fill=w)
    elif shape == "dot":
        d.ellipse([x - q, y - q, x + q, y + q], fill=w)
    elif shape == "ring":
        d.ellipse([x - q * 1.2, y - q * 1.2, x + q * 1.2, y + q * 1.2], outline=w, width=max(2, int(PXV * 2)))
    elif shape == "cross":
        t = q * 0.38
        d.rectangle([x - q * 1.2, y - t, x + q * 1.2, y + t], fill=w)
        d.rectangle([x - t, y - q * 1.2, x + t, y + q * 1.2], fill=w)


def render(sc, out):
    side = sc["Side"]
    size = sc["Size"]
    ox, oy = sc["Ox"], sc["Oy"]
    SW, SH = 1206, 557
    top = 60
    CARD = 300
    GAP = 14
    mapX = (SW - (side + GAP + CARD)) / 2
    mapY = top + (SH - top - side) / 2
    W, H = int(SW * PXV), int(SH * PXV)
    # backdrop: a blurred "game" behind the dim
    img = Image.new("RGB", (W, H))
    bd = ImageDraw.Draw(img)
    for yy in range(H):
        t = yy / H
        bd.line([(0, yy), (W, yy)], fill=lerp((120, 160, 190), (196, 170, 120), min(1, t * 1.6)))
    for i in range(14):
        bx = (i * 173) % W
        bd.rectangle([bx, H * 0.45 + (i % 3) * 30, bx + 120, H], fill=(90 + i * 5, 84, 70))
    img = img.filter(ImageFilter.GaussianBlur(18))
    dim = Image.new("RGBA", (W, H), (8, 10, 8, 175))
    img = Image.alpha_composite(img.convert("RGBA"), dim)
    # the map content (zoomed), drawn at content scale then cropped to the viewport
    cs = int(size * PXV)
    content = Image.new("RGBA", (cs, cs))
    cd = ImageDraw.Draw(content)
    for yy in range(cs):
        cd.line([(0, yy), (cs, yy)], fill=lerp(COL["SeaLight"], COL["SeaDark"], yy / cs))
    E = (-2000, 2000)

    def P(x, z):
        return (x - E[0]) / 4000 * cs, (z - E[0]) / 4000 * cs

    lx0, ly0 = P(-1760, -1760)
    lx1, ly1 = P(1760, 1490)
    land = Image.new("RGBA", (cs, cs), (0, 0, 0, 0))
    ld = ImageDraw.Draw(land)
    for yy in range(int(ly0), int(ly1)):
        t = (yy - ly0) / (ly1 - ly0)
        ld.line([(lx0, yy), (lx1, yy)], fill=lerp(COL["SandLight"], COL["SandDark"], t) + (255,))
    mask = Image.new("L", (cs, cs), 0)
    ImageDraw.Draw(mask).rounded_rectangle([lx0, ly0, lx1, ly1], radius=int(0.025 * cs), fill=255)
    content.paste(land, (0, 0), mask)
    # shore line
    cd.rounded_rectangle([lx0, ly0, lx1, ly1], radius=int(0.025 * cs), outline=(236, 220, 176), width=max(1, int(PXV * 1.5)))
    over = Image.new("RGBA", (cs, cs), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    # grid every 500 studs
    for k in range(-1500, 2000, 500):
        gx, _ = P(k, 0)
        _, gy = P(0, k)
        od.line([(gx, 0), (gx, cs)], fill=COL["Grid"] + (40,), width=1)
        od.line([(0, gy), (cs, gy)], fill=COL["Grid"] + (40,), width=1)
    # zones
    for a in sc["Areas"]:
        f = (sc["Size"] / side)
        if a.get("Rect"):
            x0, y0, x1, y1 = [v * PXV for v in a["Rect"]]
            od.rounded_rectangle([x0, y0, x1, y1], radius=int(6 * PXV * f), fill=COL["Zone"] + (70 if a["Kind"] == "town" else 45,), outline=COL["Zone"] + (120,), width=1)
        else:
            x, y, r = a["X"] * PXV, a["Y"] * PXV, a["R"] * PXV
            od.ellipse([x - r, y - r, x + r, y + r], fill=COL["Zone"] + (45,), outline=COL["Zone"] + (110,), width=1)
    content = Image.alpha_composite(content, over)
    cd = ImageDraw.Draw(content)
    rw = max(2, int(0.0055 * cs))
    for axis, at, mn, mx in ROADS:
        if axis == "X":
            a0, b0 = P(at, mn)
            a1, b1 = P(at, mx)
        else:
            a0, b0 = P(mn, at)
            a1, b1 = P(mx, at)
        cd.line([(a0, b0), (a1, b1)], fill=COL["Road"], width=rw)
        cd.line([(a0, b0), (a1, b1)], fill=(150, 124, 88), width=max(1, rw // 4))
    # icons
    groupCol = {"Town": COL["Town"], "Military": COL["Military"], "Industry": COL["Industry"], "Wilds": COL["Wilds"], "Site": COL["Site"]}
    terr = {"A:" + a["Id"]: a["Territory"] for a in sc["Areas"]}
    for ic in sc["Icons"]:
        x, y, s = ic["X"] * PXV, ic["Y"] * PXV, ic["S"]
        g = ic["Group"]
        if g in ("Base", "BaseMine"):
            r = s / 2 * PXV
            cd.rounded_rectangle([x - r - 2, y - r - 2, x + r + 2, y + r + 2], radius=int(4 * PXV), fill=(10, 12, 10))
            cd.rounded_rectangle([x - r, y - r, x + r, y + r], radius=int(3 * PXV), fill=COL["BaseMine"] if g == "BaseMine" else COL["Base"])
            if g == "BaseMine":
                q = r * 0.45
                cd.rectangle([x - q, y - q, x + q, y + q], fill=(255, 255, 255))
        elif g == "Bank":
            icon(cd, x, y, s, COL["Bank"], None)
            cd.text((x, y), "$", font=font(13, "Black"), fill=(40, 30, 0), anchor="mm")
        else:
            icon(cd, x, y, s, groupCol[g], GROUP_SHAPE[g])
            if terr.get(ic["Id"]):
                bx, by, b = x + s * 0.42 * PXV, y - s * 0.42 * PXV, 5 * PXV
                cd.rounded_rectangle([bx - b - 2, by - b - 2, bx + b + 2, by + b + 2], radius=3, fill=(10, 12, 10))
                cd.rounded_rectangle([bx - b, by - b, bx + b, by + b], radius=2, fill=COL["Outpost"])
    # sample live markers: your arrow near your base, a pin, an airdrop, 3 jobs
    def livept(x, z):
        return P(x, z)

    for jx, jz in ((-300, -820), (450, 260), (-1200, 300)):
        x, y = livept(jx, jz)
        icon(cd, x, y, 10, COL["Job"], None)
    x, y = livept(600, -700)
    icon(cd, x, y, 20, COL["Drop"], "dot")
    x, y = livept(-620, -520)
    a = 13 * PXV
    cd.polygon([(x, y - a), (x + a * 0.75, y + a * 0.7), (x, y + a * 0.35), (x - a * 0.75, y + a * 0.7)], fill=(255, 255, 255), outline=(10, 12, 10))
    x, y = livept(-150, -1000)
    a = 14 * PXV
    cd.polygon([(x - a * 0.6, y - a * 1.1), (x + a * 0.6, y - a * 1.1), (x, y)], fill=COL["Pin"], outline=(10, 12, 10))
    # labels
    for lab in sc["Labels"]:
        x0, y0, x1, y1 = [lab[k] * PXV for k in ("X0", "Y0", "X1", "Y1")]
        pill = Image.new("RGBA", (cs, cs), (0, 0, 0, 0))
        pd = ImageDraw.Draw(pill)
        pd.rounded_rectangle([x0, y0, x1, y1], radius=int((y1 - y0) / 2), fill=COL["Pill"] + (170,), outline=(255, 255, 255, 40), width=1)
        content = Image.alpha_composite(content, pill)
        cd = ImageDraw.Draw(content)
        f = font(sc["TextV"] * 0.82, "Bold" if lab["Priority"] <= 1 else "Medium")
        col = COL["Accent"] if lab["Priority"] == 0 else COL["Text"]
        cd.text(((x0 + x1) / 2, (y0 + y1) / 2), lab["Text"], font=f, fill=col, anchor="mm", stroke_width=1, stroke_fill=(0, 0, 0))
    view = content.crop((int(-ox * PXV), int(-oy * PXV), int(-ox * PXV) + int(side * PXV), int(-oy * PXV) + int(side * PXV)))
    vd = ImageDraw.Draw(view)
    vs = view.size[0]
    # vignette
    vig = Image.new("L", (vs, vs), 0)
    vgd = ImageDraw.Draw(vig)
    band = int(vs * 0.12)
    for i in range(band):
        a = int(150 * (1 - i / band) ** 2)
        vgd.rectangle([i, i, vs - 1 - i, vs - 1 - i], outline=a)
    view = Image.composite(Image.new("RGBA", (vs, vs), (0, 0, 0, 255)), view, vig)
    vd = ImageDraw.Draw(view)
    # compass rose (bottom-left)
    cr = 28 * PXV
    cx, cy = 10 * PXV + cr, vs - 10 * PXV - cr
    vd.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(14, 16, 12, 200), outline=COL["Accent"], width=2)
    n = cr * 0.72
    vd.polygon([(cx, cy - n), (cx + n * 0.26, cy), (cx - n * 0.26, cy)], fill=(214, 70, 52))
    vd.polygon([(cx, cy + n), (cx + n * 0.26, cy), (cx - n * 0.26, cy)], fill=(220, 214, 196))
    vd.polygon([(cx - n, cy), (cx, cy - n * 0.2), (cx, cy + n * 0.2)], fill=(120, 116, 100))
    vd.polygon([(cx + n, cy), (cx, cy - n * 0.2), (cx, cy + n * 0.2)], fill=(120, 116, 100))
    vd.text((cx, cy - cr - 1), "N", font=font(14, "Black"), fill=COL["Accent"], anchor="md", stroke_width=2, stroke_fill=(0, 0, 0))
    # zoom button (top-left) and close X (top-right): 44 px taps
    t = sc["Tap"] * PXV
    for bx, lbl in ((6 * PXV, "+" if sc["Zoom"] == 1 else "−"), (vs - 6 * PXV - t, "X")):
        vd.rounded_rectangle([bx + t * 0.12, 6 * PXV + t * 0.12, bx + t * 0.88, 6 * PXV + t * 0.88], radius=int(t * 0.2), fill=(14, 16, 12, 215), outline=COL["Accent"], width=2)
        vd.text((bx + t / 2, 6 * PXV + t / 2), lbl, font=font(24 if lbl != "X" else 18, "Bold"), fill=COL["Text"], anchor="mm")
    if sc["Zoom"] == 2:
        vd.text((6 * PXV + t / 2, 6 * PXV + t * 0.98), "2x", font=font(12, "Bold"), fill=COL["Accent"], anchor="mt", stroke_width=1, stroke_fill=(0, 0, 0))
    # frame + corner brackets
    vd.rectangle([0, 0, vs - 1, vs - 1], outline=COL["Accent"] + (160,), width=2)
    L = int(26 * PXV)
    th = int(3 * PXV)
    for (px_, py_, sx, sy) in ((0, 0, 1, 1), (vs, 0, -1, 1), (0, vs, 1, -1), (vs, vs, -1, -1)):
        vd.rectangle(sorted([px_, px_ + sx * L]) [:1] + [min(py_, py_ + sy * th)] + sorted([px_, px_ + sx * L])[1:] + [max(py_, py_ + sy * th)], fill=COL["Accent"])
        vd.rectangle([min(px_, px_ + sx * th), min(py_, py_ + sy * L), max(px_, px_ + sx * th), max(py_, py_ + sy * L)], fill=COL["Accent"])
    vmask = Image.new("L", (vs, vs), 0)
    ImageDraw.Draw(vmask).rounded_rectangle([0, 0, vs - 1, vs - 1], radius=int(6 * PXV), fill=255)
    img.paste(view, (int(mapX * PXV), int(mapY * PXV)), vmask)
    # the side card
    d = ImageDraw.Draw(img)
    cx0, cy0 = (mapX + side + GAP) * PXV, mapY * PXV
    cx1, cy1 = cx0 + CARD * PXV, cy0 + side * PXV
    card = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle([cx0, cy0, cx1, cy1], radius=int(10 * PXV), fill=COL["Card"] + (235,), outline=COL["Accent"] + (120,), width=2)
    img = Image.alpha_composite(img, card)
    d = ImageDraw.Draw(img)
    pad = 12 * PXV
    y = cy0 + pad
    d.text((cx0 + pad, y), "WORLD MAP", font=font(20, "Black"), fill=COL["Accent"])
    y += 30 * PXV
    d.line([(cx0 + pad, y), (cx1 - pad, y)], fill=COL["Accent"] + (90,), width=1)
    y += 8 * PXV
    d.text((cx0 + pad, y), "Camp Viper", font=font(22, "Bold"), fill=COL["Text"])
    y += 30 * PXV
    for line in ("Enemy camp", "Activity: Clear the camp", "Start it from Missions"):
        d.text((cx0 + pad, y), line, font=font(18, "Medium"), fill=COL["Muted"])
        y += 24 * PXV
    y += 6 * PXV
    bh = sc["Tap"] * PXV
    for bx, bw, lbl in ((cx0 + pad, 96, "GO"), (cx0 + pad + 104 * PXV, 150, "CLEAR PIN")):
        d.rounded_rectangle([bx, y, bx + bw * PXV, y + bh], radius=int(8 * PXV), fill=(58, 62, 44) if lbl != "GO" else (70, 96, 44), outline=COL["Accent"], width=2)
        d.text((bx + bw * PXV / 2, y + bh / 2), lbl, font=font(20, "Black"), fill=COL["Text"], anchor="mm")
    y += bh + 12 * PXV
    d.line([(cx0 + pad, y), (cx1 - pad, y)], fill=COL["Accent"] + (90,), width=1)
    y += 8 * PXV
    legend = [("Town", "Town", "square"), ("Military", "Military", "bars"), ("Industry", "Industry", "dot"), ("Camp", "Wilds", "ring"),
              ("Site", "Site", "cross"), ("Your base", "BaseMine", None), ("Outpost", "Outpost", "badge"), ("Bank", "Bank", "$"),
              ("Crate / job", "Job", None), ("You", "Me", None)]
    colw = (CARD - 24) / 2 * PXV
    for i, (txt, g, shape) in enumerate(legend):
        lx = cx0 + pad + (i % 2) * colw
        ly = y + (i // 2) * 26 * PXV
        ix, iy = lx + 9 * PXV, ly + 11 * PXV
        if g == "BaseMine":
            r = 8 * PXV
            d.rounded_rectangle([ix - r, iy - r, ix + r, iy + r], radius=int(3 * PXV), fill=COL["BaseMine"], outline=(10, 12, 10), width=2)
        elif shape == "badge":
            b = 7 * PXV
            d.rounded_rectangle([ix - b * 0.8, iy - b * 0.8, ix + b * 0.8, iy + b * 0.8], radius=3, fill=COL["Outpost"], outline=(10, 12, 10), width=2)
        elif g == "Bank":
            icon(d, ix, iy, 16, COL["Bank"], None)
            d.text((ix, iy), "$", font=font(11, "Black"), fill=(40, 30, 0), anchor="mm")
        elif g == "Job":
            icon(d, ix, iy, 16, COL["Job"], None)
        elif g == "Me":
            a = 9 * PXV
            d.polygon([(ix, iy - a), (ix + a * 0.75, iy + a * 0.7), (ix, iy + a * 0.35), (ix - a * 0.75, iy + a * 0.7)], fill=(255, 255, 255), outline=(10, 12, 10))
        else:
            icon(d, ix, iy, 16, groupCol[g], shape)
        d.text((lx + 24 * PXV, iy), txt, font=font(17, "Medium"), fill=COL["Text"], anchor="lm")
    d.text((cx0 + pad, cy1 - pad), "Pinch or + to zoom · tap to pin", font=font(15, "Medium"), fill=COL["Muted"], anchor="ld")
    img.convert("RGB").save(out)
    print("wrote", out, img.size)


data = json.loads(Path(sys.argv[1]).read_text())
render([s for s in data if s["Zoom"] == 1][0], sys.argv[2])
if len(sys.argv) > 3:
    render([s for s in data if s["Zoom"] == 2][0], sys.argv[3])
