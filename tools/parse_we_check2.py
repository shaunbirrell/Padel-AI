#!/usr/bin/env python3
"""parse_we_check2.py: turn the owner's WE_CHECK2 log (we_check2.luau output) into JSON. Stdlib only.

Input: plain pasted lines (any prefix before "WE_CHECK2 " is ignored, e.g. timestamps), or the Open Cloud
ListLuauExecutionSessionTaskLogs JSON (FLAT "messages" or STRUCTURED "structuredMessages"); several files are
read in order. Output: JSON on stdout (or -o FILE).

  python3 parse_we_check2.py LOG [LOG...] [-o OUT.json] [--we-check we_check_v75.txt] [--strict] [--summary]

--strict exits 1 when a WE_CHECK2 line is not understood, an id's END count disagrees with its lines, the DONE
line is missing, or a --we-check part count disagrees. --summary prints one line per id to stderr.

Line grammar: "WE_CHECK2 <id> <TYPE> [positional] key=value ..." (id 0 for ENV and DONE). Values: numbers,
comma vectors "x,y,z", bare tokens, or "quoted" text with \" and \\ escapes. Positions (at=) are studs from the
centre of the box of the parts the game's loader keeps (world axes); top= is height above that box's bottom.
  ENV v studio server creator place ver job ids          DONE ids ok fail err lines bytes
  HEAD via parts loader mesh union spm neon seats lights fx scripts hum tools snd dec tex sgui bgui txt img sa att
       cons joints cams prompts desc                    BOX size min max long all kept (or none=1)
  MODEL "container"|"main" path c kids names pp piv pivr bbo bbr bbs ext
  P rank "name" c s at top r lk up m col t in [x=1 loader drops it] [sh] [kw] [ms mesh tex] [sm mesh tex sc]
  SEAT "name" c at top lv ax up pv lvp in               SUB "path" c n ext at [kw]
  HINT "name" c kw [at] in     FX c n on     BRAND c n tex|img|text|kids [face] on     CAM "name" lv ax at
  FAIL err     ERR err     END lines cut ("0" or "KIND:count,...")

Derived fields are hints for the lead, not decisions: facing from part names and seats, the implied
VisualAssetService Yaw (front must end at -Z: -Z=0, +X=90, -X=-90, +Z=180), flat or giant parts, brand
content ids, and for models over the 40-part cap the name groups and a greedy OmitParts suggestion.
"""
import argparse
import json
import math
import re
import sys

PREFIX = "WE_CHECK2 "
CAP = 40
FORMAT_VERSION = 1
POSITIONAL = {  # positional tokens after the type, in order
    "ENV": [], "HEAD": [], "BOX": [], "MODEL": ["label"], "P": ["rank", "name"], "SEAT": ["name"],
    "HINT": ["name"], "SUB": ["path"], "FX": [], "BRAND": [], "CAM": ["name"], "FAIL": [], "ERR": [],
    "END": [], "DONE": [],
}
DETAIL = {"P", "SEAT", "HINT", "SUB", "FX", "BRAND", "CAM"}
LIST_KEYS = {"kw"}
STRING_KEYS = {"via", "c", "m", "col", "lk", "ax", "up", "long", "kept", "sh", "sm", "face", "cut", "creator", "studio",
               "server"}
FRONT_WORDS = ("front", "nose", "cockpit", "canopy", "bow", "head")
REAR_WORDS = ("rear", "back", "tail", "exhaust", "stern")
YAW_FOR_FRONT = {"-Z": 0, "+X": 90, "-X": -90, "+Z": 180}
KEEP_WORDS = ("wheel", "tire", "tyre", "rim", "track", "rotor", "blade", "hull", "body", "chassis", "cab")

TOKEN = re.compile(r'\s*(?:([A-Za-z_][A-Za-z0-9_]*)=("(?:[^"\\]|\\.)*"|\S*)|("(?:[^"\\]|\\.)*")|(\S+))')
NUM = re.compile(r"^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$|^-?inf$|^nan$")
LINE = re.compile(r"WE_CHECK2 (\d+) ([A-Z]+)(?: (.*))?$")


def unquote(s):
    body = s[1:-1]
    return re.sub(r"\\(.)", lambda m: m.group(1), body)


def num(s):
    if s in ("inf", "-inf", "nan"):
        return float(s)
    f = float(s)
    return int(f) if f.is_integer() and "." not in s and "e" not in s.lower() else f


def value(key, raw):
    if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
        return unquote(raw)
    if key in LIST_KEYS:
        return [w for w in raw.split(",") if w]
    if key in STRING_KEYS:
        return raw
    parts = raw.split(",")
    if raw and all(NUM.match(p) for p in parts):
        return [num(p) for p in parts] if len(parts) > 1 else num(parts[0])
    return raw


def tokenize(rest):
    kv, pos, pos_order = {}, [], []
    i = 0
    while i < len(rest):
        m = TOKEN.match(rest, i)
        if not m or m.end() == i:
            break
        i = m.end()
        if m.group(1):
            kv[m.group(1)] = value(m.group(1), m.group(2))
            pos_order.append(m.group(1))
        elif m.group(3):
            pos.append(unquote(m.group(3)))
        elif m.group(4):
            t = m.group(4)
            pos.append(num(t) if NUM.match(t) else t)
    return kv, pos


def collect_lines(text):
    """Every WE_CHECK2 line in text: plain lines, or strings inside Open Cloud log JSON."""
    out = []
    stripped = text.strip()
    if stripped[:1] in "{[":
        try:
            data = json.loads(stripped)
        except ValueError:
            data = None
        if data is not None:
            def walk(x):
                if isinstance(x, dict):
                    for v in x.values():
                        walk(v)
                elif isinstance(x, list):
                    for v in x:
                        walk(v)
                elif isinstance(x, str) and PREFIX in x:
                    out.extend(x.splitlines())
            walk(data)
            return [l for l in out if PREFIX in l]
    return [l for l in text.splitlines() if PREFIX in l]


def rot_yxz(deg):
    """Roblox Orientation (X, Y, Z degrees, applied Y then X then Z) -> 3x3 rows."""
    x, y, z = (math.radians(d) for d in deg)
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mm(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mm(mm(ry, rx), rz)


def world_ext(size, deg):
    r = rot_yxz(deg)
    return [sum(abs(r[i][j]) * size[j] for j in range(3)) for i in range(3)]


def vec(x):
    return x if isinstance(x, list) and len(x) == 3 and all(isinstance(v, (int, float)) for v in x) else None


def dominant(v):
    """Horizontal axis a vector points along most: +X/-X/+Z/-Z (None when tiny)."""
    if v is None or (abs(v[0]) < 1e-6 and abs(v[2]) < 1e-6):
        return None
    if abs(v[0]) >= abs(v[2]):
        return "+X" if v[0] > 0 else "-X"
    return "+Z" if v[2] > 0 else "-Z"


def mean(vs):
    return [sum(v[i] for v in vs) / len(vs) for i in range(3)] if vs else None


def new_model(mid):
    return {"id": mid, "status": None, "head": None, "box": None, "models": [], "parts": [], "seats": [], "hints": [],
            "subs": [], "fx": [], "brand": [], "cams": [], "fail": None, "err": [], "end": None, "line_count": 0,
            "problems": []}


def parse(lines):
    doc = {"format": FORMAT_VERSION, "env": None, "done": None, "order": [], "models": {}, "counts": {}, "unparsed": [],
           "problems": []}
    for raw in lines:
        at = raw.find(PREFIX)
        line = raw[at:].rstrip("\r\n")
        m = LINE.match(line.rstrip())
        if not m or m.group(2) not in POSITIONAL:
            doc["unparsed"].append(line)
            continue
        mid, kind, rest = m.group(1), m.group(2), m.group(3) or ""
        kv, pos = tokenize(rest)
        rec = dict(zip(POSITIONAL[kind], pos))
        if len(pos) > len(POSITIONAL[kind]):
            rec["extra"] = pos[len(POSITIONAL[kind]):]
        rec.update(kv)
        doc["counts"][kind] = doc["counts"].get(kind, 0) + 1
        if mid == "0":
            if kind == "ENV":
                doc["env"] = rec
            elif kind == "DONE":
                doc["done"] = rec
            else:
                doc["unparsed"].append(line)
            continue
        md = doc["models"].get(mid)
        if md is None:
            md = new_model(mid)
            doc["models"][mid] = md
            doc["order"].append(mid)
        if kind != "END":
            md["line_count"] += 1
        if kind == "HEAD":
            md["head"], md["status"] = rec, "OK"
        elif kind == "BOX":
            md["box"] = rec
        elif kind == "MODEL":
            md["models"].append(rec)
        elif kind == "P":
            md["parts"].append(rec)
        elif kind == "SEAT":
            md["seats"].append(rec)
        elif kind == "HINT":
            md["hints"].append(rec)
        elif kind == "SUB":
            md["subs"].append(rec)
        elif kind == "FX":
            md["fx"].append(rec)
        elif kind == "BRAND":
            md["brand"].append(rec)
        elif kind == "CAM":
            md["cams"].append(rec)
        elif kind == "FAIL":
            md["fail"], md["status"] = rec, "FAIL"
        elif kind == "ERR":
            md["err"].append(rec)
            md["status"] = "ERR" if md["status"] != "OK" else "OK+ERR"
        elif kind == "END":
            md["end"] = rec
    for mid in doc["order"]:
        derive(doc["models"][mid])
    check_doc(doc)
    return doc


def derive(md):
    d = {}
    box = md["box"] or {}
    size = vec(box.get("size"))
    longest = max(size) if size else 0.0
    head = md["head"] or {}
    if head:
        d["stripped_parts"] = head.get("parts", 0) - head.get("loader", 0)
        d["over_cap"] = head.get("loader", 0) > CAP
    for p in md["parts"]:
        s, r, a = vec(p.get("s")), vec(p.get("r")), vec(p.get("at"))
        if s:
            p["vol"] = round(s[0] * s[1] * s[2], 3)
            p["maxd"] = max(s)
        if s and r:
            we = world_ext(s, r)
            p["wext"] = [round(v, 2) for v in we]
            if a:
                p["lo"] = [round(a[i] - we[i] / 2, 2) for i in range(3)]
                p["hi"] = [round(a[i] + we[i] / 2, 2) for i in range(3)]
    parts = md["parts"]
    d["biggest"] = [{"name": p.get("name"), "c": p.get("c"), "s": p.get("s"), "at": p.get("at")} for p in parts[:5]]
    d["giant_parts"] = [{"name": p.get("name"), "c": p.get("c"), "s": p.get("s"), "ms": p.get("ms"), "at": p.get("at"),
                         "t": p.get("t")} for p in parts if p.get("maxd", 0) >= 200]
    flat = []
    for p in parts:
        s = vec(p.get("s"))
        if s and max(s) >= 50 and min(s) <= 0.05 * max(s):
            flat.append({"name": p.get("name"), "c": p.get("c"), "s": s, "t": p.get("t")})
    d["flat_parts"] = flat
    # keyword parts and hint objects (where things named front / tail / light... sit)
    kwp = {}
    for p in parts + md["hints"] + md["subs"]:
        for w in p.get("kw") or []:
            kwp.setdefault(w, []).append({"name": p.get("name", p.get("path")), "c": p.get("c"), "at": p.get("at")})
    d["keyword_parts"] = kwp
    fronts = [vec(x["at"]) for w in FRONT_WORDS for x in kwp.get(w, []) if vec(x["at"])]
    rears = [vec(x["at"]) for w in REAR_WORDS for x in kwp.get(w, []) if vec(x["at"])]
    face = None
    if fronts and rears:
        mf, mr = mean(fronts), mean(rears)
        face = dominant([mf[0] - mr[0], 0, mf[2] - mr[2]])
    elif fronts:
        face = dominant(mean(fronts))
    elif rears:
        mr = mean(rears)
        face = dominant([-mr[0], 0, -mr[2]])
    d["front_by_names"] = {"front": face, "yaw": YAW_FOR_FRONT.get(face), "front_parts": len(fronts), "rear_parts": len(rears)}
    vseats = [s for s in md["seats"] if s.get("c") == "VehicleSeat"] or md["seats"]
    seat_face = dominant(vec(vseats[0].get("lv"))) if vseats else None
    d["front_by_seat"] = {"front": seat_face, "yaw": YAW_FOR_FRONT.get(seat_face),
                          "seat": vseats[0].get("name") if vseats else None}
    if size:
        d["seat_vs_top"] = [{"name": s.get("name"), "top_gap": round(s["top"] - size[1], 2)} for s in md["seats"]
                            if isinstance(s.get("top"), (int, float))]
    # brand check: every texture / image id and gui text in the model
    tex, texts = [], []
    for p in parts:
        for k in ("tex",):
            v = p.get(k)
            if v not in (None, "-", ""):
                tex.append({"id": v, "from": "part:" + str(p.get("name"))})
    for b in md["brand"]:
        for k in ("tex", "img"):
            v = b.get(k)
            if v not in (None, "-", ""):
                tex.append({"id": v, "from": b.get("c") + ":" + str(b.get("on"))})
        if "text" in b:
            texts.append({"text": b["text"], "c": b.get("c"), "on": b.get("on")})
    seen, uniq = set(), []
    for t in tex:
        if str(t["id"]) not in seen:
            seen.add(str(t["id"]))
            uniq.append(t)
    d["brand_content"] = {"textures": uniq, "texts": texts, "decals": head.get("dec"), "textures_n": head.get("tex"),
                          "guis": (head.get("sgui") or 0) + (head.get("bgui") or 0)}
    cut = (md["end"] or {}).get("cut", "0")
    d["cut"] = cut
    d["complete"] = bool(md["end"]) and cut == "0" and md["status"] in ("OK", "FAIL")
    if head.get("loader", 0) > CAP:
        d["trim"] = trim(md, longest, cut)
    md["derived"] = d


def trim(md, longest, cut):
    """Name groups and a greedy OmitParts hint (same rule as wc2/trim's WE_TRIM SUGGEST)."""
    kept = [p for p in md["parts"] if p.get("x") != 1]
    part_names = {p.get("name") for p in md["parts"]}
    groups = {}
    for p in kept:
        g = groups.setdefault(p.get("name"), {"name": p.get("name"), "n": 0, "maxd": 0.0, "classes": set(), "in": p.get("in")})
        g["n"] += 1
        g["maxd"] = max(g["maxd"], p.get("maxd", 0.0))
        g["classes"].add(p.get("c"))
    order = sorted(groups.values(), key=lambda g: (-g["n"], g["maxd"]))
    for g in order:
        g["share"] = round(100 * g["maxd"] / longest) if longest else None
        g["classes"] = sorted(g["classes"])
    loader = (md["head"] or {}).get("loader", len(kept))

    def removed(omit):
        n = 0
        for p in kept:
            segs = [s for s in str(p.get("in") or "").split("/") if s]
            if p.get("name") in omit or any(s in omit and s in part_names for s in segs):
                n += 1
        return n
    cands = [g for g in order if longest and g["maxd"] < 0.25 * longest
             and not any(w in str(g["name"]).lower() for w in KEEP_WORDS)]
    cands.sort(key=lambda g: g["maxd"])
    omit, after, biggest = [], loader, 0.0
    for g in cands:
        if after <= CAP:
            break
        omit.append(g["name"])
        biggest = max(biggest, g["maxd"])
        after = loader - removed(set(omit))
    subs_fit = [{"path": s.get("path"), "n": s.get("n"), "ext": s.get("ext")} for s in md["subs"]
                if isinstance(s.get("n"), int) and s["n"] <= CAP]
    return {"loader": loader, "must_drop": max(0, loader - CAP), "groups": order[:40],
            "suggest": {"omit": omit, "parts_after": after, "fits": after <= CAP, "biggest_dropped": round(biggest, 2),
                        "partial": cut != "0"},
            "subs_that_fit": subs_fit}


def check_doc(doc):
    probs = doc["problems"]
    if doc["env"] is None:
        probs.append("no ENV line")
    elif doc["env"].get("v") != FORMAT_VERSION:
        probs.append("script format v=%s, parser v=%d" % (doc["env"].get("v"), FORMAT_VERSION))
    if doc["done"] is None:
        probs.append("no DONE line: the log is cut or the run stopped")
    for l in doc["unparsed"]:
        probs.append("not understood: " + l[:120])
    for mid in doc["order"]:
        md = doc["models"][mid]
        if md["end"] is None:
            md["problems"].append("no END line")
        elif md["end"].get("lines") != md["line_count"]:
            md["problems"].append("END says %s lines, log has %d" % (md["end"].get("lines"), md["line_count"]))
        if md["status"] is None:
            md["problems"].append("no HEAD or FAIL line")
        if md["err"]:
            md["problems"].append("script error: " + str(md["err"][0].get("err"))[:160])
        head = md["head"] or {}
        if head and len(md["parts"]) > head.get("parts", 0):
            md["problems"].append("more P lines than parts=")
        for p in md["problems"]:
            probs.append(mid + ": " + p)
    done = doc["done"] or {}
    if done and doc["env"] and done.get("ids") != doc["env"].get("ids"):
        probs.append("DONE ids=%s but ENV ids=%s" % (done.get("ids"), doc["env"].get("ids")))
    if done and len(doc["order"]) != done.get("ids"):
        probs.append("DONE ids=%s but the log has %d ids" % (done.get("ids"), len(doc["order"])))


def we_check_parts(path):
    parts = {}
    for l in open(path, encoding="utf-8", errors="replace"):
        m = re.search(r"WE_CHECK OK (\d+) .*?\bparts=(\d+)", l)
        if m:
            parts[m.group(1)] = int(m.group(2))
    return parts


def main(argv=None):
    ap = argparse.ArgumentParser(description="Parse WE_CHECK2 lines into JSON")
    ap.add_argument("logs", nargs="*", help="log files (default: stdin)")
    ap.add_argument("-o", "--out", help="write JSON here instead of stdout")
    ap.add_argument("--we-check", help="first-check log (WE_CHECK OK lines) to compare part counts with")
    ap.add_argument("--strict", action="store_true", help="exit 1 on any problem")
    ap.add_argument("--summary", action="store_true", help="one line per id on stderr")
    a = ap.parse_args(argv)
    lines = []
    if a.logs:
        for f in a.logs:
            lines.extend(collect_lines(open(f, encoding="utf-8", errors="replace").read()))
    else:
        lines.extend(collect_lines(sys.stdin.read()))
    doc = parse(lines)
    if a.we_check:
        ref = we_check_parts(a.we_check)
        cmp = {}
        for mid in doc["order"]:
            head = doc["models"][mid]["head"] or {}
            if mid in ref and head:
                same = ref[mid] == head.get("parts")
                cmp[mid] = {"we_check": ref[mid], "we_check2": head.get("parts"), "same": same}
                if not same:
                    doc["problems"].append("%s: parts=%s now, WE_CHECK said %d" % (mid, head.get("parts"), ref[mid]))
        doc["we_check_compare"] = cmp

    def default(o):
        if isinstance(o, set):
            return sorted(o)
        raise TypeError(type(o))
    text = json.dumps(doc, indent=1, ensure_ascii=False, default=default)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    else:
        print(text)
    if a.summary:
        for mid in doc["order"]:
            md = doc["models"][mid]
            h, d = md["head"] or {}, md["derived"]
            t = d.get("trim")
            sys.stderr.write("%s %s parts=%s loader=%s size=%s front(names)=%s front(seat)=%s giant=%d cut=%s%s\n" % (
                mid, md["status"], h.get("parts"), h.get("loader"), (md["box"] or {}).get("size"),
                d["front_by_names"]["front"], d["front_by_seat"]["front"], len(d["giant_parts"]), d["cut"],
                (" trim_after=%s" % t["suggest"]["parts_after"]) if t else ""))
        sys.stderr.write("problems: %d, unparsed: %d, lines: %d\n" % (len(doc["problems"]), len(doc["unparsed"]),
                                                                       sum(doc["counts"].values())))
    return 1 if a.strict and doc["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
