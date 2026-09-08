#!/usr/bin/env python3
"""Render activity.svg — a "commit address map" of the last 52 weeks.

The whole 52-week commit history is flattened into one address space and
wrapped at COLS columns: one square = one commit, read left->right and
top->bottom, oldest first. Within each month the commits are grouped per
product, so every product gets one contiguous "allocation" whose size is
exactly how much it was worked on that month.

Hue = category (fixed slot per category, see CATS), shade = product within
that category. Stepped rules mark month boundaries.

Usage: activity-svg.py <tools.json> <activity-dir> <out.svg>

<activity-dir> holds one file per repo named `<owner>__<name>.json`, each the
raw GitHub `/stats/commit_activity` array (52 weeks, oldest first).

Stdlib only — no build step, no dependencies.
"""

import collections
import datetime
import glob
import html
import json
import math
import os
import sys

# ---------------------------------------------------------------- palette ---
# Categorical hues from a CVD-validated 8-slot palette; the mapping below is
# FIXED so a regeneration never repaints a category. Categories not listed
# fall into "Other" (gray). Validated against this page's card surfaces
# (#fafafa light / #161922 dark): all checks pass except three light-mode
# hues under 3:1, which the in-place labels and the legend relieve.
CATS = [
    ("PostgreSQL",      "#2a78d6", "#3987e5"),  # blue
    ("Terraform",       "#eb6834", "#d95926"),  # orange
    ("AWS",             "#1baf7a", "#199e70"),  # aqua
    ("MySQL",           "#eda100", "#c98500"),  # yellow
    ("Go tool",         "#e87ba4", "#d55181"),  # magenta
    ("Git / GitHub",    "#008300", "#008300"),  # green
    ("macOS / iOS",     "#4a3aa7", "#9085e9"),  # violet
    ("Auth / Security", "#e34948", "#e66767"),  # red
    ("Other",           "#8f8d85", "#8a887f"),  # gray — the catch-all
]
CATIDX = {c[0]: i for i, c in enumerate(CATS)}
NAMED = set(CATIDX) - {"Other"}

# Theme tokens mirror style.css (card surface, not page background).
LIGHT = {"bg": "#fafafa", "ink": "#1a1a1a", "ink2": "#6b7280",
         "ink3": "#9ca3af", "rule": "#e5e7eb"}
DARK = {"bg": "#161922", "ink": "#e6e6e6", "ink2": "#9aa0a6",
        "ink3": "#6f757f", "rule": "#23262d"}
FONT = ('-apple-system, BlinkMacSystemFont, "Helvetica Neue", '
        '"Hiragino Sans", "Noto Sans JP", sans-serif')

COLS = 96      # address-space width, in commits
PITCH = 10     # cell pitch in px
GAP = 1        # surface gap between cells
GX, GY = 108, 104
LABEL_MIN = 9  # shortest run (in cells) that gets an in-place product label


# ------------------------------------------------------- sRGB <-> OKLCH ----
def _s2l(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _l2s(c):
    c = 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055
    return max(0, min(255, round(c * 255)))


def hex2oklch(h):
    r, g, b = (_s2l(int(h[i:i + 2], 16)) for i in (1, 3, 5))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = l ** (1 / 3), m ** (1 / 3), s ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(A, B), math.atan2(B, A)


def oklch2hex(L, C, H):
    A, B = C * math.cos(H), C * math.sin(H)
    l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
    m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
    s = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3
    r = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return "#%02x%02x%02x" % (_l2s(r), _l2s(g), _l2s(b))


def shades(base, n, dark):
    """n distinguishable steps of one hue, kept inside the mode's L band."""
    L, C, _H = hex2oklch(base)
    _, _, H = hex2oklch(base)
    span = 0.10 if n > 1 else 0.0
    lo = max(0.49 if dark else 0.44, L - span / 2)
    hi = min(0.68 if dark else 0.76, lo + span)
    out = []
    for i in range(n):
        t = 0.0 if n == 1 else i / (n - 1)
        out.append(oklch2hex(hi - t * (hi - lo), min(C * (0.80 + 0.35 * (1 - t)), C * 1.05), H))
    return out


def ink_on(fill):
    return "#111111" if hex2oklch(fill)[0] > 0.63 else "#ffffff"


def esc(s):
    return html.escape(str(s if s is not None else ""))


# ------------------------------------------------------------------ data ---
def load(tools_path, act_dir):
    meta = {}
    for t in json.load(open(tools_path)):
        meta[t["url"].replace("https://github.com/", "")] = t

    rows = []
    for f in sorted(glob.glob(os.path.join(act_dir, "*.json"))):
        slug = os.path.basename(f)[:-5].replace("__", "/", 1)
        try:
            weeks = json.load(open(f))
        except json.JSONDecodeError:
            continue
        if not isinstance(weeks, list) or not weeks:
            continue
        total = sum(w.get("total", 0) for w in weeks)
        if total == 0:
            continue
        m = meta.get(slug, {})
        cat = (m.get("categories") or ["Other"])[0]
        rows.append({
            "slug": slug, "name": slug.split("/")[1],
            "cat": cat, "grp": cat if cat in NAMED else "Other",
            "total": total, "weeks": [w.get("total", 0) for w in weeks],
            "wk0": weeks[0]["week"], "nweeks": len(weeks),
        })
    if not rows:
        sys.exit("activity-svg.py: no commit activity found in %s" % act_dir)
    return rows


def assign_colors(rows):
    """Fixed order: category slot, then commits desc, then name."""
    prods = sorted(rows, key=lambda r: (CATIDX[r["grp"]], -r["total"], r["name"]))
    bycat = collections.defaultdict(list)
    for r in prods:
        bycat[r["grp"]].append(r)
    for lab, lh, dh in CATS:
        lst = bycat[lab]
        if not lst:
            continue
        n = len(lst)
        # Interleave so products that end up side by side in the map get
        # shades from opposite ends of the ramp.
        idx = list(range(n))
        half = (n + 1) // 2
        order = [x for pair in zip(idx[:half], idx[half:] + [None]) for x in pair if x is not None]
        sl, sd = shades(lh, n, False), shades(dh, n, True)
        for slot, r in zip(order, lst):
            r["light"], r["dark"] = sl[slot], sd[slot]
    for i, r in enumerate(prods):
        r["pid"] = i
    return prods


def build_address_space(prods):
    """Flatten to a list of pids, month by month. Returns (cells, months)."""
    nweeks = max(r["nweeks"] for r in prods)
    week0 = max(r["wk0"] for r in prods)
    wmonth = []
    for w in range(nweeks):
        d = datetime.datetime.fromtimestamp(week0 + w * 604800, datetime.timezone.utc)
        wmonth.append((d.year, d.month))

    keys = []
    for k in wmonth:
        if not keys or keys[-1] != k:
            keys.append(k)

    cells, months = [], []
    for k in keys:
        months.append((len(cells), datetime.date(k[0], k[1], 1).strftime("%b %Y")))
        ws = [i for i, x in enumerate(wmonth) if x == k]
        for r in prods:
            n = sum(r["weeks"][w] for w in ws if w < len(r["weeks"]))
            if n:
                cells.extend([r["pid"]] * n)
    return cells, months, week0, nweeks


# ------------------------------------------------------------------ draw ---
def render(prods, cells, months, week0, nweeks):
    total = len(cells)
    nrows = math.ceil(total / COLS)
    gw = COLS * PITCH
    W = GX + gw + 34
    leg_y = GY + nrows * PITCH + 46
    H = leg_y + 266
    L0 = GX - 84
    byid = {r["pid"]: r for r in prods}

    # contiguous same-product runs, never crossing a row
    runs = []
    i = 0
    while i < total:
        row, col = divmod(i, COLS)
        pid, j = cells[i], i
        while j < total and cells[j] == pid and j // COLS == row:
            j += 1
        runs.append((row, col, j - i, pid))
        i = j

    out = []
    A = out.append
    A('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" '
      'font-family=\'%s\' role="img" aria-label="commit activity map">' % (W, H, W, H, FONT))

    css = []
    tok = lambda d: ";".join("--%s:%s" % (k, v) for k, v in d.items())
    css.append("svg{%s}" % tok(LIGHT))
    for i, c in enumerate(CATS):
        css.append("svg{--g%d:%s}" % (i, c[1]))
    for r in prods:
        css.append("svg{--c%d:%s;--k%d:%s}" % (r["pid"], r["light"], r["pid"], ink_on(r["light"])))
    dk = [tok(DARK)]
    dk += ["--g%d:%s" % (i, c[2]) for i, c in enumerate(CATS)]
    dk += ["--c%d:%s;--k%d:%s" % (r["pid"], r["dark"], r["pid"], ink_on(r["dark"])) for r in prods]
    dk = "{%s}" % ";".join(dk)
    css.append("@media (prefers-color-scheme:dark){svg%s}" % dk)
    css.append(".t{fill:var(--ink)}.t2{fill:var(--ink2)}.t3{fill:var(--ink3)}")
    css.append(".cell{shape-rendering:crispEdges}")
    A("<style>%s</style>" % "\n".join(css))
    A('<rect width="%d" height="%d" fill="var(--bg)"/>' % (W, H))

    d0 = datetime.datetime.fromtimestamp(week0, datetime.timezone.utc)
    d1 = datetime.datetime.fromtimestamp(week0 + (nweeks - 1) * 604800, datetime.timezone.utc)
    A('<text x="%d" y="32" class="t" font-size="15" font-weight="600">%s commits'
      '<tspan class="t3" font-weight="400">  &#183;  </tspan>%d products'
      '<tspan class="t3" font-weight="400">  &#183;  </tspan>%s &#8211; %s</text>'
      % (L0, "{:,}".format(total), len(prods),
         d0.strftime("%b %d, %Y"), d1.strftime("%b %d, %Y")))
    A('<text x="%d" y="54" class="t2" font-size="12.5">One square = one commit; the address runs '
      'left&#8594;right, top&#8594;bottom in time order. Each month allocates one block per product.</text>'
      % L0)
    A('<text x="%d" y="%d" class="t3" font-size="10.5" letter-spacing="0.08em">ADDRESS = TIME</text>'
      % (L0, GY - 14))

    A('<g class="cell">')
    for row, col, ln, pid in runs:
        x, y = GX + col * PITCH, GY + row * PITCH
        for k in range(ln):
            A('<rect x="%d" y="%d" width="%d" height="%d" rx="1.4" fill="var(--c%d)"/>'
              % (x + k * PITCH, y, PITCH - GAP, PITCH - GAP, pid))
    A("</g>")

    # month separators (stepped, because the address space wraps) + gutter labels
    lasty = -99.0
    for start, lab in months:
        r0, c0 = divmod(start, COLS)
        x = GX + c0 * PITCH - GAP / 2
        yt = GY + r0 * PITCH - GAP / 2
        yb = yt + PITCH
        if start > 0:
            d = "M %s %s H %s V %s H %s" % (GX - 4, yb, x, yt, GX + gw)
            A('<path d="%s" fill="none" stroke="var(--bg)" stroke-width="2.6"/>' % d)
            A('<path d="%s" fill="none" stroke="var(--rule)" stroke-width="1"/>' % d)
        want = GY + r0 * PITCH + 7.5
        ly = max(want, lasty + 13.5)
        lasty = ly
        A('<text x="%s" y="%s" class="t2" font-size="10.5" text-anchor="end" font-weight="600">%s</text>'
          % (GX - 14, ly, esc(lab)))
        if ly - want > 1.5:
            A('<path d="M %s %s H %s V %s H %s" fill="none" stroke="var(--rule)" stroke-width="1"/>'
              % (GX - 11, ly - 3.5, GX - 7.5, want - 3.5, GX - 4))

    # in-place labels on each product's longest run
    best = {}
    for row, col, ln, pid in runs:
        if ln > best.get(pid, (0,))[0]:
            best[pid] = (ln, row, col)
    for pid, (ln, row, col) in best.items():
        if ln < LABEL_MIN:
            continue
        nm = byid[pid]["name"]
        room = ln * PITCH - GAP - 6
        if len(nm) * 5.2 > room:
            nm = nm[:max(3, int(room / 5.2) - 1)] + "…"
        A('<text x="%s" y="%s" font-size="8.6" font-weight="600" fill="var(--k%d)">%s</text>'
          % (GX + col * PITCH + 3, GY + row * PITCH + 7.1, pid, esc(nm)))

    # hover targets: one per run, so the raw .svg has native tooltips too
    A('<g fill="transparent">')
    for row, col, ln, pid in runs:
        r = byid[pid]
        A('<rect x="%s" y="%s" width="%d" height="%d"><title>%s &#8212; %d commit%s here &#183; '
          '%d in 52w &#183; %s</title></rect>'
          % (GX + col * PITCH - GAP / 2, GY + row * PITCH - GAP / 2, ln * PITCH, PITCH,
             esc(r["name"]), ln, "s" if ln > 1 else "", r["total"], esc(r["grp"])))
    A("</g>")

    # legend — categories (hue), then the biggest products (shade)
    cat_tot = collections.Counter()
    for r in prods:
        cat_tot[r["grp"]] += r["total"]
    A('<text x="%d" y="%d" class="t3" font-size="10.5" letter-spacing="0.08em">CATEGORY &#8212; hue</text>'
      % (L0, leg_y - 16))
    active = [(lab, i) for i, (lab, _l, _d) in enumerate(CATS) if cat_tot[lab]]
    cw = (W - L0 - 24) / 5
    for i, (lab, gi) in enumerate(active):
        cx, cy = L0 + (i % 5) * cw, leg_y + (i // 5) * 20
        A('<rect x="%s" y="%s" width="11" height="11" rx="2" fill="var(--g%d)"/>' % (cx, cy - 9, gi))
        A('<text x="%s" y="%s" class="t2" font-size="11.5">%s <tspan class="t3">%s</tspan></text>'
          % (cx + 16, cy, esc(lab), "{:,}".format(cat_tot[lab])))
    leg_y += ((len(active) - 1) // 5) * 20

    A('<text x="%d" y="%d" class="t3" font-size="10.5" letter-spacing="0.08em">'
      'TOP PRODUCTS &#8212; shade within hue</text>' % (L0, leg_y + 30))
    cw2 = (W - L0 - 24) / 4
    for i, r in enumerate(sorted(prods, key=lambda r: -r["total"])[:24]):
        cx, cy = L0 + (i % 4) * cw2, leg_y + 52 + (i // 4) * 19
        A('<rect x="%s" y="%s" width="10" height="10" rx="2" fill="var(--c%d)"/>'
          % (cx, cy - 8.5, r["pid"]))
        nm = r["name"]
        if len(nm) > 30:
            nm = nm[:29] + "…"
        A('<text x="%s" y="%s" class="t2" font-size="11">%s</text>' % (cx + 15, cy, esc(nm)))
        A('<text x="%s" y="%s" class="t3" font-size="11" text-anchor="end">%d</text>'
          % (cx + cw2 - 48, cy, r["total"]))

    A('<text x="%d" y="%d" class="t3" font-size="10.5">Source: GitHub commit_activity '
      '(default branch, last 52 weeks).</text>' % (L0, H - 16))
    A("</svg>")
    return "\n".join(out)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__.strip().splitlines()[-6])
    tools_path, act_dir, out_path = sys.argv[1:]
    rows = load(tools_path, act_dir)
    prods = assign_colors(rows)
    cells, months, week0, nweeks = build_address_space(prods)
    svg = render(prods, cells, months, week0, nweeks)
    with open(out_path, "w") as f:
        f.write(svg + "\n")
    print("activity.svg: %d commits, %d products, %d months"
          % (len(cells), len(prods), len(months)))


if __name__ == "__main__":
    main()
