"""Draws the Sindur app icon (docs/DESIGN.md 7.16): a crimson play-bolt (a
play triangle cut by a lightning notch) with a near-black keyline and a small
rose / milk highlight on its upper edge.

Outputs (1024 px):
  app_icon.png             full-bleed iOS / legacy icon: #0B0B0D -> #4A0F24 diagonal, no alpha
  app_icon_foreground.png  adaptive foreground: the glyph + keyline on transparent
  app_icon_monochrome.png  themed-icon silhouette: the glyph only, white on transparent

Usage: python -I draw_icon.py <out_dir> [preview_dir]
"""
import math
import os
import sys

from PIL import Image, ImageDraw

VOLT = (0xCC, 0x32, 0x4C, 255)  # crimson fill (the name is the glyph layer's)
INK = (0x0B, 0x0B, 0x0D, 255)
ROSE = (0xFF, 0x6E, 0x86, 255)
MILK = (0xFF, 0xF3, 0xE6, 255)
FIELD_TOP = (0x0B, 0x0B, 0x0D)
FIELD_DEEP = (0x4A, 0x0F, 0x24)

SS = 4  # supersampling
SIZE = 1024

# Glyph geometry in a 1000-unit box (centred later). A play triangle whose
# centroid sits on the centre, with rounded corners.
TRI = [(318.0, 205.0), (318.0, 795.0), (829.0, 500.0)]
CORNER = 70.0
# The lightning notch: a zig-zag band from above the top edge to below the
# bottom edge, splitting the triangle in two.
BOLT = [(668.0, 250.0), (520.0, 512.0), (612.0, 512.0), (452.0, 790.0)]
BOLT_HALF = 44.0


def incenter(tri):
    (ax, ay), (bx, by), (cx, cy) = tri
    a = math.dist((bx, by), (cx, cy))
    b = math.dist((ax, ay), (cx, cy))
    c = math.dist((ax, ay), (bx, by))
    p = a + b + c
    ix = (a * ax + b * bx + c * cx) / p
    iy = (a * ay + b * by + c * cy) / p
    s = p / 2
    area = math.sqrt(s * (s - a) * (s - b) * (s - c))
    return (ix, iy), area / s


def scale_about(points, centre, k):
    cx, cy = centre
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in points]


def band_polygon(poly, half):
    """Outline of a constant-width band along [poly] with mitred joins."""
    def offset_line(p, q, d):
        dx, dy = q[0] - p[0], q[1] - p[1]
        n = math.hypot(dx, dy)
        nx, ny = -dy / n * d, dx / n * d
        return (p[0] + nx, p[1] + ny), (q[0] + nx, q[1] + ny)

    def intersect(l1, l2):
        (x1, y1), (x2, y2) = l1
        (x3, y3), (x4, y4) = l2
        den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(den) < 1e-9:
            return l1[1]
        px = ((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4)) / den
        py = ((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4)) / den
        return px, py

    def side(d):
        lines = [offset_line(poly[i], poly[i + 1], d) for i in range(len(poly) - 1)]
        pts = [lines[0][0]]
        for i in range(len(lines) - 1):
            pts.append(intersect(lines[i], lines[i + 1]))
        pts.append(lines[-1][1])
        return pts

    return side(half) + list(reversed(side(-half)))


def rounded_triangle(draw, tri, radius, grow, fill, transform):
    """Fills [tri] grown outwards by [grow] with corners of [radius] + [grow]."""
    centre, rho = incenter(tri)
    inner = scale_about(tri, centre, (rho - radius) / rho)
    pts = [transform(p) for p in inner]
    r = transform.scale * (radius + grow)
    draw.polygon(pts, fill=fill)
    draw.line(pts + [pts[0]], fill=fill, width=int(round(2 * r)), joint='curve')
    for x, y in pts:
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


class Transform:
    def __init__(self, box, size):
        # Maps the 1000-unit glyph box onto [box] px of a [size] px canvas.
        self.scale = box / 1000.0
        self.offset = (size - box) / 2.0

    def __call__(self, p):
        return (self.offset + p[0] * self.scale, self.offset + p[1] * self.scale)


def glyph_layers(size, box, keyline):
    """(keyline mask, glyph mask) at [size] px, glyph box [box] px, keyline px."""
    t = Transform(box, size)
    k_units = keyline / t.scale

    ink = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(ink)
    rounded_triangle(d, TRI, CORNER, k_units, 255, t)
    d.polygon([t(p) for p in band_polygon(BOLT, BOLT_HALF - k_units)], fill=0)

    volt = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(volt)
    rounded_triangle(d, TRI, CORNER, 0, 255, t)
    d.polygon([t(p) for p in band_polygon(BOLT, BOLT_HALF)], fill=0)
    return ink, volt


def highlight(volt, size, box):
    """A thin rose rim on the glyph's upper-left edges, upper half only."""
    from PIL import ImageChops
    d = int(box * 0.012)
    shifted = ImageChops.offset(volt, d, d)
    rim = ImageChops.subtract(volt, shifted)
    fade = Image.linear_gradient('L').resize((size, size))  # 0 top -> 255 bottom
    fade = fade.point(lambda v: 255 if v < 100 else max(0, 255 - (v - 110) * 6))
    return ImageChops.multiply(rim, fade)


def glint(size, box):
    """A small milk dot near the glyph's top-left corner."""
    t = Transform(box, size)
    m = Image.new('L', (size, size), 0)
    x, y = t((352.0, 300.0))
    r = 16.0 * t.scale
    ImageDraw.Draw(m).ellipse([x - r, y - r, x + r, y + r], fill=255)
    return m


def render(box_px, keyline_px, background):
    size = SIZE * SS
    ink, volt = glyph_layers(size, box_px * SS, keyline_px * SS)
    if background == 'field':
        # Diagonal #0B0B0D (top left) -> #4A0F24 (bottom right).
        v = Image.linear_gradient('L').resize((size, size))
        h = v.transpose(Image.Transpose.ROTATE_90)
        grad = Image.blend(v, h, 0.5)
        top = Image.new('RGBA', (size, size), FIELD_TOP + (255,))
        deep = Image.new('RGBA', (size, size), FIELD_DEEP + (255,))
        img = Image.composite(deep, top, grad)
    else:
        img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if background != 'mono':
        img.paste(Image.new('RGBA', (size, size), INK), (0, 0), ink)
        img.paste(Image.new('RGBA', (size, size), VOLT), (0, 0), volt)
        img.paste(Image.new('RGBA', (size, size), ROSE), (0, 0), highlight(volt, size, box_px * SS))
        img.paste(Image.new('RGBA', (size, size), MILK), (0, 0), glint(size, box_px * SS))
    else:
        img.paste(Image.new('RGBA', (size, size), (255, 255, 255, 255)), (0, 0), volt)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    if background == 'field':
        img = img.convert('RGB')
    return img


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    # Full-bleed icon: 2 dp of a 108 dp icon is ~19 px at 1024.
    render(880, 19, 'field').save(os.path.join(out, 'app_icon.png'), optimize=True)
    # Adaptive foreground: the PNG fills the inner 68 % of the 108 dp canvas
    # (16 % inset), so 1024 px = ~73 dp and 2 dp = ~28 px. The glyph (about
    # 46 % of the icon tall) stays inside the 66 dp safe circle.
    render(1180, 28, 'clear').save(os.path.join(out, 'app_icon_foreground.png'), optimize=True)
    render(1180, 28, 'mono').save(os.path.join(out, 'app_icon_monochrome.png'), optimize=True)

    if len(sys.argv) > 2:
        prev = sys.argv[2]
        os.makedirs(prev, exist_ok=True)
        fg = Image.open(os.path.join(out, 'app_icon_foreground.png'))
        # How a launcher shows the adaptive icon: #0B0B0D field, 16 % inset,
        # circle mask; and small sizes.
        canvas = Image.new('RGBA', (1080, 1080), FIELD_TOP + (255,))
        inner = fg.resize((734, 734), Image.LANCZOS)
        canvas.paste(inner, (173, 173), inner)
        mask = Image.new('L', (1080, 1080), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, 1079, 1079], fill=255)
        circle = Image.new('RGBA', (1080, 1080), (255, 255, 255, 0))
        circle.paste(canvas, (0, 0), mask)
        sheet = Image.new('RGBA', (1500, 560), (247, 242, 232, 255))
        sheet.paste(circle.resize((400, 400), Image.LANCZOS), (20, 20), circle.resize((400, 400), Image.LANCZOS))
        full = Image.open(os.path.join(out, 'app_icon.png')).convert('RGBA')
        sheet.paste(full.resize((400, 400), Image.LANCZOS), (440, 20))
        for i, s in enumerate([144, 96, 48]):
            small = circle.resize((s, s), Image.LANCZOS)
            sheet.paste(small, (880 + i * 170, 20), small)
        mono = Image.open(os.path.join(out, 'app_icon_monochrome.png'))
        mono_bg = Image.new('RGBA', (400, 400), (60, 60, 60, 255))
        m = mono.resize((272, 272), Image.LANCZOS)
        mono_bg.paste(m, (64, 64), m)
        sheet.paste(mono_bg.resize((200, 200)), (880, 200))
        sheet.save(os.path.join(prev, 'icon_sheet.png'))


main()
