#!/usr/bin/env python3
"""Pipeline helper tools for screenshot compositing.

Subcommands:
  detect  IMG X0 Y0 X1 Y1 [--thresh T] [--inset PX]
      Detect a dark screen quad inside window (X0,Y0)-(X1,Y1).
      Robust trimmed line-fit on the four edges; prints manifest-ready quad
      [[TLx,TLy],[TRx,TRy],[BLx,BLy],[BRx,BRy]] (optionally inset toward center).
  overlay IMG TLx TLy TRx TRy BLx BLy BRx BRy [--out NAME]
      Draw the quad on a zoomed crop around it and save to the scratchpad for
      visual verification. Prints the output path.
  zoom    IMG X0 Y0 X1 Y1 [--scale N] [--out NAME]
      Save a zoomed crop to the scratchpad. Prints the output path.
  crop    IMG X0 Y0 X1 Y1 OUT [--scale N]
      Save a crop (e.g. a generation seed reference) to OUT.
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw

SCRATCH = os.environ.get(
    "SCRATCHPAD",
    "/private/tmp/claude-501/-Users-darioalessandro-Documents-remote-shutter/"
    "cb16b0da-ac53-4863-912d-faad083e6534/scratchpad",
)


def trimmed_fit(pts, vertical, trim=0.15):
    """Least-squares line fit with the worst-residual points trimmed out."""
    if vertical:
        pts = [(y, x) for x, y in pts]
    for _ in range(2):
        n = len(pts)
        mx = sum(p[0] for p in pts) / n
        my = sum(p[1] for p in pts) / n
        den = sum((p[0] - mx) ** 2 for p in pts) or 1e-9
        a = sum((p[0] - mx) * (p[1] - my) for p in pts) / den
        b = my - a * mx
        resid = sorted(pts, key=lambda p: abs(p[1] - (a * p[0] + b)))
        keep = max(4, int(n * (1 - trim)))
        pts = resid[:keep]
    return a, b  # y = a*x + b  (or x = a*y + b when vertical)


def detect(im, x0, y0, x1, y1, thresh):
    px = im.load()
    left, right, top, bot = [], [], [], []
    for y in range(y0, y1, max(2, (y1 - y0) // 60)):
        xs = [x for x in range(x0, x1) if px[x, y] < thresh]
        if len(xs) > 5:
            left.append((min(xs), y))
            right.append((max(xs), y))
    for x in range(x0, x1, max(2, (x1 - x0) // 60)):
        ys = [y for y in range(y0, y1) if px[x, y] < thresh]
        if len(ys) > 5:
            top.append((x, min(ys)))
            bot.append((x, max(ys)))
    la, lb = trimmed_fit(left, True)
    ra, rb = trimmed_fit(right, True)
    ta, tb = trimmed_fit(top, False)
    ba, bb = trimmed_fit(bot, False)

    def ix(va, vb, ha, hb):
        y = (ha * vb + hb) / (1 - ha * va)
        return round(va * y + vb), round(y)

    return [ix(la, lb, ta, tb), ix(ra, rb, ta, tb), ix(la, lb, ba, bb), ix(ra, rb, ba, bb)]


def inset_quad(q, px_in):
    cx = sum(p[0] for p in q) / 4
    cy = sum(p[1] for p in q) / 4
    out = []
    for x, y in q:
        dx, dy = cx - x, cy - y
        d = (dx * dx + dy * dy) ** 0.5 or 1
        out.append((round(x + dx / d * px_in), round(y + dy / d * px_in)))
    return out


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("detect")
    d.add_argument("img")
    d.add_argument("win", nargs=4, type=int)
    d.add_argument("--thresh", type=int, default=55)
    d.add_argument("--inset", type=int, default=0)

    o = sub.add_parser("overlay")
    o.add_argument("img")
    o.add_argument("quad", nargs=8, type=int)
    o.add_argument("--out", default="quad_overlay.png")

    z = sub.add_parser("zoom")
    z.add_argument("img")
    z.add_argument("win", nargs=4, type=int)
    z.add_argument("--scale", type=int, default=2)
    z.add_argument("--out", default="zoom.png")

    c = sub.add_parser("crop")
    c.add_argument("img")
    c.add_argument("win", nargs=4, type=int)
    c.add_argument("out")
    c.add_argument("--scale", type=int, default=1)

    a = p.parse_args()
    if a.cmd == "detect":
        im = Image.open(a.img).convert("L")
        q = detect(im, *a.win, a.thresh)
        if a.inset:
            q = inset_quad(q, a.inset)
        print(f"quad: [[{q[0][0]}, {q[0][1]}], [{q[1][0]}, {q[1][1]}], "
              f"[{q[2][0]}, {q[2][1]}], [{q[3][0]}, {q[3][1]}]]")
    elif a.cmd == "overlay":
        im = Image.open(a.img).convert("RGB")
        q = [(a.quad[i], a.quad[i + 1]) for i in range(0, 8, 2)]
        dr = ImageDraw.Draw(im)
        # TL->TR->BR->BL->TL
        dr.line([q[0], q[1], q[3], q[2], q[0]], fill=(0, 255, 0), width=3)
        for pt in q:
            dr.ellipse([pt[0] - 6, pt[1] - 6, pt[0] + 6, pt[1] + 6], outline=(255, 0, 255), width=3)
        xs = [pt[0] for pt in q]; ys = [pt[1] for pt in q]
        pad = 80
        box = (max(0, min(xs) - pad), max(0, min(ys) - pad),
               min(im.width, max(xs) + pad), min(im.height, max(ys) + pad))
        crop = im.crop(box)
        crop = crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS)
        out = os.path.join(SCRATCH, a.out)
        crop.save(out)
        print(out)
    elif a.cmd == "zoom":
        im = Image.open(a.img).crop(tuple(a.win))
        im = im.resize((im.width * a.scale, im.height * a.scale), Image.LANCZOS)
        out = os.path.join(SCRATCH, a.out)
        im.save(out)
        print(out, im.size, "offset", a.win[0], a.win[1])
    elif a.cmd == "crop":
        im = Image.open(a.img).crop(tuple(a.win))
        if a.scale > 1:
            im = im.resize((im.width * a.scale, im.height * a.scale), Image.LANCZOS)
        im.save(a.out)
        print(a.out, im.size)


if __name__ == "__main__":
    main()
