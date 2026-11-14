"""Generate all XPlayer brand artwork (mark, wordmark, lockups, app icons, splash).

Re-runnable from anywhere:  python tool/branding/make_xplayer_brand.py
Requires Pillow only (no numpy).

* Writes the design-system branding set in packages/design_system/assets/branding/
  (deleting any non-xplayer_* file there first).
* Overwrites Android (apps/mobile, apps/tv) and iOS (apps/mobile) icon / splash PNGs in
  place, keeping each existing file's name and pixel size.

Mark: two rounded strokes forming an "X" with a violet->cyan diagonal gradient, a white
rounded play-triangle at the crossing, separated from the arms by a transparent gap.
"""
from __future__ import annotations

import glob
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BRAND_DIR = os.path.join(ROOT, "packages", "design_system", "assets", "branding")
FONT = os.path.join(ROOT, "packages", "design_system", "assets", "fonts", "bebas_neue",
                    "BebasNeue-Regular.ttf")

# Brand gradient (start → end) and icon background. Default theme: black + red.
VIOLET = (0xB3, 0x12, 0x1F)   # deep red (gradient start; name kept for the code below)
CYAN = (0xFF, 0x3B, 0x4A)     # bright red (gradient end)
BG = (0x0D, 0x06, 0x07)       # near-black with a red tint
SILVER = (0xF1, 0xF5, 0xF9)
WHITE = (255, 255, 255)

# ---- Mark geometry, unit coords: mark box = [-0.5, 0.5]^2, centre (0, 0) ----
STROKE_W = 0.25                 # arm thickness
ARM_P = 0.5 - STROKE_W / 2      # arm centre-line end point (|x| = |y| = ARM_P)
TRI_R = 0.15                    # play-triangle circumradius (sharp-corner equivalent)
TRI_ROUND = 0.03                # play-triangle corner radius
GAP = 0.04                      # transparent gap between triangle and arms
TRI_SHIFT = 0.02                # optical shift of the triangle to the right
# Max distance of any opaque pixel from centre, as a fraction of the mark box size.
MARK_RADIUS = ARM_P * math.sqrt(2) + STROKE_W / 2

SS = 4096  # supersampled working size for raster mark

# Size of the mark box as a fraction of the canvas, per use.
FG_FRAC = 0.50       # adaptive-icon foreground: radius ~0.33 canvas (inside 72/108 visible circle)
SPLASH_FRAC = 0.48   # Android 12 splash icon: radius ~0.32 canvas (inside the 2/3 circle mask)
LEGACY_FRAC = 0.66   # square legacy Android launcher
IOS_FRAC = 0.70      # iOS / full icon


# ---------------- geometry helpers ----------------

def rounded_triangle(radius: float, corner: float, shift: float = 0.0, steps: int = 24):
    """Convex polygon (unit coords) of an equilateral triangle pointing right whose
    corners are rounded with `corner` radius; outer edges match a sharp triangle of
    circumradius `radius`."""
    inner = radius - 2 * corner  # vertex->centroid distance of the corner-circle centres
    pts = []
    for a in (0, 120, 240):
        cx = inner * math.cos(math.radians(a)) + shift
        cy = inner * math.sin(math.radians(a))
        # Arc spans +-60 deg around the vertex direction.
        for i in range(steps + 1):
            t = math.radians(a - 60 + 120 * i / steps)
            pts.append((cx + corner * math.cos(t), cy + corner * math.sin(t)))
    return pts


def strip(a, b, w):
    """Rectangle (convex polygon) of the segment a-b with thickness w (no caps)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy / L * w / 2, dx / L * w / 2
    return [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny),
            (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]


def clip_convex(subject, clip):
    """Sutherland-Hodgman: subject polygon clipped by convex clip polygon."""
    def inside(p, a, b, sign):
        return sign * ((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])) >= 0

    def inter(p, q, a, b):
        x1, y1, x2, y2 = p[0], p[1], q[0], q[1]
        x3, y3, x4, y4 = a[0], a[1], b[0], b[1]
        den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
        return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))

    # orientation of clip polygon
    area = sum(clip[i][0] * clip[(i + 1) % len(clip)][1] - clip[(i + 1) % len(clip)][0] * clip[i][1]
               for i in range(len(clip)))
    sign = 1 if area > 0 else -1
    out = subject
    for i in range(len(clip)):
        a, b = clip[i], clip[(i + 1) % len(clip)]
        inp, out = out, []
        if not inp:
            break
        s = inp[-1]
        for e in inp:
            if inside(e, a, b, sign):
                if not inside(s, a, b, sign):
                    out.append(inter(s, e, a, b))
                out.append(e)
            elif inside(s, a, b, sign):
                out.append(inter(s, e, a, b))
            s = e
    return out


ARMS = [((-ARM_P, -ARM_P), (ARM_P, ARM_P)), ((ARM_P, -ARM_P), (-ARM_P, ARM_P))]
TRI_POLY = rounded_triangle(TRI_R, TRI_ROUND, TRI_SHIFT)
CUT_POLY = rounded_triangle(TRI_R + 2 * GAP, TRI_ROUND + GAP, TRI_SHIFT)
# Notification silhouette hole (slightly tighter than CUT so the X stays bold when tiny).
HOLE_POLY = rounded_triangle(TRI_R + GAP, TRI_ROUND + GAP / 2, TRI_SHIFT)


def _px(pts, s):
    return [((x + 0.5) * s, (y + 0.5) * s) for x, y in pts]


# ---------------- raster mark ----------------

def gradient(size: int) -> Image.Image:
    """Diagonal violet (top-left) -> cyan (bottom-right) gradient, RGB, size x size."""
    big = int(size * 1.5) + 2
    g = Image.linear_gradient("L").resize((big, big), Image.BICUBIC)  # black top -> white bottom
    g = g.rotate(45, resample=Image.BICUBIC)  # black top-left -> white bottom-right
    off = (big - size) // 2
    g = g.crop((off, off, off + size, off + size))
    return Image.composite(Image.new("RGB", (size, size), CYAN),
                           Image.new("RGB", (size, size), VIOLET), g)


def _capsule(d, a, b, w, s, fill=255):
    (ax, ay), (bx, by) = _px([a, b], s)
    r = w * s / 2
    d.line([(ax, ay), (bx, by)], fill=fill, width=int(round(w * s)))
    for x, y in ((ax, ay), (bx, by)):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def _poly_mask(pts, s):
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).polygon(_px(pts, s), fill=255)
    return m


_CACHE: dict = {}


def mark_layers():
    """(colour mark RGBA, white-silhouette alpha L) at SS x SS."""
    if "mark" not in _CACHE:
        xm = Image.new("L", (SS, SS), 0)
        d = ImageDraw.Draw(xm)
        for a, b in ARMS:
            _capsule(d, a, b, STROKE_W, SS)
        arms = ImageChops.subtract(xm, _poly_mask(CUT_POLY, SS))
        mark = gradient(SS).convert("RGBA")
        mark.putalpha(arms)
        tri = _poly_mask(TRI_POLY, SS)
        mark = Image.composite(Image.new("RGBA", (SS, SS), WHITE + (255,)), mark, tri)
        sil = ImageChops.subtract(xm, _poly_mask(HOLE_POLY, SS))
        _CACHE["mark"] = (mark, sil)
    return _CACHE["mark"]


def mark_at(px: int) -> Image.Image:
    return mark_layers()[0].resize((px, px), Image.LANCZOS)


def place(canvas: Image.Image, img: Image.Image) -> Image.Image:
    canvas.alpha_composite(img, ((canvas.width - img.width) // 2, (canvas.height - img.height) // 2))
    return canvas


def icon(w: int, h: int, frac: float, bg=None) -> Image.Image:
    """Mark box centred at `frac` of the shorter side, on bg colour (or transparent)."""
    c = Image.new("RGBA", (w, h), (bg + (255,)) if bg else (0, 0, 0, 0))
    return place(c, mark_at(max(1, round(min(w, h) * frac))))


def notification_badge(s: int) -> Image.Image:
    big = s * 4
    c = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(c).ellipse([0, 0, big - 1, big - 1], fill=(0, 0, 0, 255))
    place(c, mark_at(round(big * 0.62)))  # opaque radius ~0.41 < 0.5 circle
    return c.resize((s, s), Image.LANCZOS)


def status_icon(s: int) -> Image.Image:
    pad = max(1, round(s * 0.04))
    big = (s - 2 * pad) * 4
    a = mark_layers()[1].resize((big, big), Image.LANCZOS).resize((s - 2 * pad, s - 2 * pad), Image.LANCZOS)
    alpha = Image.new("L", (s, s), 0)
    alpha.paste(a, (pad, pad))
    c = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    c.putalpha(alpha)
    return c


# ---------------- wordmark / lockup ----------------

def wordmark(cap_px: int = 600) -> Image.Image:
    font = ImageFont.truetype(FONT, cap_px)
    full = font.getbbox("XPlayer")
    W, H = full[2] - full[0] + 80, full[3] - full[1] + 80
    ox, oy = 40 - full[0], 40 - full[1]
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((ox + font.getlength("X"), oy), "Player", font=font,
                             fill=SILVER + (255,))
    xm = Image.new("L", (W, H), 0)
    ImageDraw.Draw(xm).text((ox, oy), "X", font=font, fill=255)
    x0, y0, x1, y1 = xm.getbbox()
    gs = max(x1 - x0, y1 - y0)
    gfull = Image.new("RGB", (W, H), VIOLET)
    gfull.paste(gradient(gs), (x0 + (x1 - x0 - gs) // 2, y0 + (y1 - y0 - gs) // 2))
    layer = gfull.convert("RGBA")
    layer.putalpha(xm)
    img.alpha_composite(layer)
    return img.crop(img.getbbox())


def pad_to(img: Image.Image, w: int, h: int, pad_frac=0.04) -> Image.Image:
    k = min(w * (1 - 2 * pad_frac) / img.width, h * (1 - 2 * pad_frac) / img.height)
    r = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    return place(Image.new("RGBA", (w, h), (0, 0, 0, 0)), r)


def lockup(rtl: bool = False) -> Image.Image:
    wm = wordmark(600)
    mh = round(wm.height * 1.3)
    m = mark_at(mh)
    gap = round(mh * 0.2)
    W, H = mh + gap + wm.width, mh
    c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    wy = (H - wm.height) // 2
    if rtl:
        c.alpha_composite(wm, (0, wy))
        c.alpha_composite(m, (wm.width + gap, 0))
    else:
        c.alpha_composite(m, (0, 0))
        c.alpha_composite(wm, (mh + gap, wy))
    return c


def tv_banner(w: int, h: int) -> Image.Image:
    c = Image.new("RGBA", (w * 4, h * 4), BG + (255,))
    lk = lockup()
    k = min(c.width * 0.76 / lk.width, c.height * 0.5 / lk.height)
    place(c, lk.resize((round(lk.width * k), round(lk.height * k)), Image.LANCZOS))
    return c.resize((w, h), Image.LANCZOS)


# ---------------- SVG ----------------

def _f(v: float) -> str:
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def _d(pts, s=1024) -> str:
    p = _px(pts, s)
    return "M" + " L".join(f"{_f(x)} {_f(y)}" for x, y in p) + " Z"


def _capsule_d(a, b, w, s=1024) -> str:
    (ax, ay), (bx, by) = _px([a, b], s)
    r = w * s / 2
    dx, dy = bx - ax, by - ay
    L = math.hypot(dx, dy)
    nx, ny = -dy / L * r, dx / L * r
    return (f"M{_f(ax + nx)} {_f(ay + ny)} L{_f(bx + nx)} {_f(by + ny)} "
            f"A{_f(r)} {_f(r)} 0 0 0 {_f(bx - nx)} {_f(by - ny)} "
            f"L{_f(ax - nx)} {_f(ay - ny)} A{_f(r)} {_f(r)} 0 0 0 {_f(ax + nx)} {_f(ay + ny)} Z")


def write_svg(path: str):
    # Each arm is a capsule with the (cut-triangle intersect arm strip) region as an
    # even-odd hole: the hole lies fully inside the capsule, so no mask/clip is needed.
    paths = []
    for a, b in ARMS:
        hole = clip_convex(CUT_POLY, strip(a, b, STROKE_W))
        paths.append(f'  <path fill="url(#xp)" fill-rule="evenodd" d="{_capsule_d(a, b, STROKE_W)} {_d(hole)}"/>')
    svg = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
        '  <defs>\n'
        '    <linearGradient id="xp" x1="0" y1="0" x2="1024" y2="1024" gradientUnits="userSpaceOnUse">\n'
        '      <stop offset="0" stop-color="#B3121F"/>\n'
        '      <stop offset="1" stop-color="#FF3B4A"/>\n'
        '    </linearGradient>\n'
        '  </defs>\n'
        + "\n".join(paths) + "\n"
        f'  <path fill="#FFFFFF" d="{_d(TRI_POLY)}"/>\n'
        '</svg>\n'
    )
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(svg)
    WRITTEN.append(os.path.relpath(path, ROOT))


# ---------------- writers ----------------

WRITTEN: list[str] = []
DELETED: list[str] = []


def save(img: Image.Image, path: str, rgb: bool = False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if rgb:
        base = Image.new("RGBA", img.size, BG + (255,))
        base.alpha_composite(img.convert("RGBA"))
        img = base.convert("RGB")
    img.save(path, optimize=True)
    WRITTEN.append(os.path.relpath(path, ROOT))


def brand_set():
    os.makedirs(BRAND_DIR, exist_ok=True)
    for f in sorted(os.listdir(BRAND_DIR)):
        fp = os.path.join(BRAND_DIR, f)
        if os.path.isfile(fp) and not f.startswith("xplayer_"):
            os.remove(fp)
            DELETED.append(os.path.relpath(fp, ROOT))
    save(mark_at(1024), os.path.join(BRAND_DIR, "xplayer_mark.png"))
    write_svg(os.path.join(BRAND_DIR, "xplayer_mark.svg"))
    save(pad_to(wordmark(), 1600, 400), os.path.join(BRAND_DIR, "xplayer_wordmark.png"))
    save(pad_to(lockup(False), 2000, 500), os.path.join(BRAND_DIR, "xplayer_lockup.png"))
    save(pad_to(lockup(True), 2000, 500), os.path.join(BRAND_DIR, "xplayer_lockup_rtl.png"))
    save(icon(1024, 1024, IOS_FRAC, BG), os.path.join(BRAND_DIR, "xplayer_launcher.png"), rgb=True)
    save(icon(1024, 1024, FG_FRAC), os.path.join(BRAND_DIR, "xplayer_launcher_fg.png"))
    save(icon(1152, 1152, 0.45), os.path.join(BRAND_DIR, "xplayer_splash.png"))


def android(app: str):
    res = os.path.join(ROOT, "apps", app, "android", "app", "src", "main", "res")
    for p in sorted(glob.glob(os.path.join(res, "**", "*.png"), recursive=True)):
        name = os.path.basename(p)
        with Image.open(p) as im:
            w, h = im.size
            mode = im.mode
        if name == "ic_launcher.png":
            save(icon(w, h, LEGACY_FRAC, BG), p, rgb=(mode == "RGB"))
        elif name == "ic_launcher_foreground.png":
            save(icon(w, h, FG_FRAC), p)
        elif name == "android12splash.png":
            save(icon(w, h, SPLASH_FRAC), p)
        elif name == "ic_stat_notification.png":
            save(status_icon(w), p)
        elif name == "ic_notification_app.png":
            save(notification_badge(w), p)
        elif name == "background.png":
            save(Image.new("RGB", (w, h), BG), p)
        elif name == "tv_banner.png":
            save(tv_banner(w, h), p)
        else:
            print("UNHANDLED (left as-is):", os.path.relpath(p, ROOT), (w, h))


def ios():
    xc = os.path.join(ROOT, "apps", "mobile", "ios", "Runner", "Assets.xcassets")
    for p in sorted(glob.glob(os.path.join(xc, "AppIcon.appiconset", "Icon-App-*.png"))):
        with Image.open(p) as im:
            w, h = im.size
        save(icon(w, h, IOS_FRAC, BG), p, rgb=True)  # iOS rejects alpha
    for p in sorted(glob.glob(os.path.join(xc, "LaunchImage.imageset", "LaunchImage*.png"))):
        with Image.open(p) as im:
            w, h = im.size
        # Existing placeholders are 1x1; a mark is meaningless there, keep transparent.
        save(icon(w, h, 0.6) if min(w, h) >= 16 else Image.new("RGBA", (w, h), (0, 0, 0, 0)), p)
    for p in glob.glob(os.path.join(xc, "LaunchBackground.imageset", "background.png")):
        with Image.open(p) as im:
            w, h = im.size
        save(Image.new("RGB", (w, h), BG), p)


if __name__ == "__main__":
    brand_set()
    android("mobile")
    android("tv")
    ios()
    print(f"mark radius / box = {MARK_RADIUS:.3f}")
    print("deleted:", len(DELETED))
    for d in DELETED:
        print("  -", d)
    print("written:", len(WRITTEN))
    for w in WRITTEN:
        print("  +", w)
