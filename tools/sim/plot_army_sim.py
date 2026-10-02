"""v115 (Code Bot Roblox): top-down PNG plots of the army-follow acceptance simulation.
Run: /workspace/army-sim/venv/bin/python tools/sim/plot_army_sim.py [outdir] [scenario ...]
Per plot: his path (black), every slot's marker trace (thin, coloured per soldier), every soldier's trace (dashed),
and snapshots (his position = black star, slots = hollow squares, soldiers = filled dots, rows joined) at a few
times, each snapshot labelled with its time."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_army_sim  # noqa: E402

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

out = Path(sys.argv[1] if len(sys.argv) > 1 else "/workspace/army-sim")
names = sys.argv[2:] or ["circle", "figure8", "u180", "left90"]
out.mkdir(parents=True, exist_ok=True)
txt = run_army_sim.run(trace=names)
if txt is None:
    sys.exit("no luau CLI")
met = run_army_sim.metrics(txt)
data = {}
for line in txt.splitlines():
    if not line.startswith("TRACE,"):
        continue
    p = line.split(",")
    name, t, ox, oz = p[1], float(p[2]), float(p[3]), float(p[4])
    rest = [float(x) for x in p[5:]]
    units = [rest[i:i + 4] for i in range(0, len(rest), 4)]
    data.setdefault(name, []).append((t, ox, oz, units))
cmap = plt.get_cmap("tab20")
for name, rows in data.items():
    fig, ax = plt.subplots(figsize=(10, 10))
    n = len(rows[0][3])
    ax.plot([r[1] for r in rows], [r[2] for r in rows], "k-", lw=2.0, label="player path")
    for k in range(n):
        c = cmap(k % 20)
        ax.plot([r[3][k][2] for r in rows], [r[3][k][3] for r in rows], "-", color=c, lw=0.8, alpha=0.6)
        ax.plot([r[3][k][0] for r in rows], [r[3][k][1] for r in rows], "--", color=c, lw=0.8, alpha=0.9)
    T = rows[-1][0]
    snaps = [T * f for f in (0.15, 0.3, 0.45, 0.6, 0.75, 0.9)]
    if name == "u180":
        snaps = [5.5, 6.3, 6.8, 7.4, 8.2, 10.0, 14.0]
    for st in snaps:
        r = min(rows, key=lambda r: abs(r[0] - st))
        ax.plot(r[1], r[2], "k*", ms=16)
        ax.annotate(f"t={r[0]:.1f}", (r[1], r[2]), textcoords="offset points", xytext=(8, 8), fontsize=9)
        for k in range(n):
            c = cmap(k % 20)
            sx, sz, gx, gz = r[3][k]
            ax.plot(gx, gz, "s", mfc="none", mec=c, ms=9, mew=1.5)
            ax.plot(sx, sz, "o", color=c, ms=6)
            ax.plot([sx, gx], [sz, gz], "-", color=c, lw=0.6)
    ax.set_aspect("equal")
    ax.invert_yaxis()  # north (-Z) up
    m = met.get(name, {})
    ax.set_title(f"{name}: black = player path (stars = snapshots), thin = slot traces, dashed = soldier traces\n"
                 f"squares = slots, dots = soldiers | slotChanges {m.get('slotChanges', 0):.0f}, teleports {m.get('teleports', 0):.0f}, "
                 f"RMS mean {m.get('rmsMean', 0):.2f}, width x{m.get('widthRatio', 0):.2f}, min to player {m.get('minOwner', 0):.1f}, "
                 f"orbit {m.get('orbit', 0):.0f}", fontsize=9)
    ax.set_xlabel("X (studs)")
    ax.set_ylabel("Z (studs, north up)")
    ax.grid(alpha=0.3)
    ax.legend(loc="best", fontsize=8)
    fig.tight_layout()
    fig.savefig(out / f"{name}.png", dpi=110)
    plt.close(fig)
    print("wrote", out / f"{name}.png")
