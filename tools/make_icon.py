"""Draws Folio's icon and launch mark geometrically.

Kept in the repository so the icon can be regenerated or adjusted without any
design tool, and without an AI image generator - which the project forbids.

    python3 tools/make_icon.py <output-dir>

Sizes are then produced with `sips`; see docs/RELEASE.md.


A folio IS a sheet of paper, so the mark is one: a page with a turned corner,
which reads as a document at 48px where anything more detailed turns to mush.
"""
import struct, zlib, math

TEAL       = (0x2F, 0x5D, 0x62)   # the app's seed colour
TEAL_DEEP  = (0x1E, 0x3D, 0x41)
PAPER      = (0xFA, 0xFA, 0xF7)
FOLD       = (0xC9, 0xD8, 0xD9)
INK        = (0x2F, 0x5D, 0x62)

SS = 4  # supersampling factor


def rounded_rect(x0, y0, x1, y1, r):
    def inside(x, y):
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            return False
        for cx, cy in ((x0+r, y0+r), (x1-r, y0+r), (x0+r, y1-r), (x1-r, y1-r)):
            if (x < x0+r or x > x1-r) and (y < y0+r or y > y1-r):
                if abs(x-cx) <= r and abs(y-cy) <= r:
                    return (x-cx)**2 + (y-cy)**2 <= r*r
        return True
    return inside


def polygon(points):
    def inside(x, y):
        hit = False
        n = len(points)
        for i in range(n):
            xi, yi = points[i]
            xj, yj = points[(i-1) % n]
            if (yi > y) != (yj > y):
                if x < (xj-xi) * (y-yi) / (yj-yi) + xi:
                    hit = not hit
        return hit
    return inside


def render(size, with_background=True, inset=0.0, monochrome=False):
    """Foreground inset lets Android's adaptive icon keep its safe zone.

    Android masks an adaptive icon to whatever shape the launcher likes - a
    circle on a Pixel - and only the central 66 of 108 units is guaranteed to
    survive. The mark is inset so its corners are inside that circle rather
    than trimmed off by it.

    `monochrome` draws the themed-icon layer, where only the alpha channel is
    used: the sheet is solid and the fold and rules are holes in it.
    """
    w = h = size * SS
    buf = [[(0, 0, 0, 0)] * w for _ in range(h)]

    S = w  # work in supersampled units
    def u(v):  # 0..1 -> pixels
        return v * S

    # Page geometry, in 0..1 of the canvas, then inset for adaptive icons.
    def sc(v):
        return 0.5 + (v - 0.5) * (1.0 - inset)

    px0, py0, px1, py1 = u(sc(0.255)), u(sc(0.175)), u(sc(0.745)), u(sc(0.825))
    # A SIZE, not a position: scaling it through sc() made the turned corner
    # grow as the mark shrank, until the fold ate half the page.
    cut = u(0.175) * 0.95 * (1.0 - inset)

    page = polygon([
        (px0, py0), (px1 - cut, py0), (px1, py0 + cut), (px1, py1), (px0, py1),
    ])
    fold = polygon([(px1 - cut, py0), (px1, py0 + cut), (px1 - cut, py0 + cut)])

    # Three text rules, suggesting a document without being legible noise.
    rules = []
    for i, (fx, wfrac) in enumerate([(0.42, 0.62), (0.53, 0.62), (0.64, 0.40)]):
        ry = u(sc(fx))
        rh = u(0.028) * (1.0 - inset)
        rx0 = px0 + (px1 - px0) * 0.14
        rx1 = rx0 + (px1 - px0) * wfrac
        rules.append(rounded_rect(rx0, ry, rx1, ry + rh, rh / 2))

    bg = rounded_rect(0, 0, w - 1, h - 1, u(0.22))

    for y in range(h):
        row = buf[y]
        for x in range(w):
            if with_background and bg(x, y):
                # A soft vertical shift keeps it from looking flat.
                t = y / h
                c = tuple(
                    int(TEAL[i] + (TEAL_DEEP[i] - TEAL[i]) * t) for i in range(3)
                )
                row[x] = c + (255,)
            if page(x, y):
                row[x] = (255, 255, 255, 255) if monochrome else PAPER + (255,)
                if any(r(x, y) for r in rules):
                    row[x] = (0, 0, 0, 0) if monochrome else INK + (255,)
            if fold(x, y):
                row[x] = (0, 0, 0, 0) if monochrome else FOLD + (255,)

    # Downsample.
    out = bytearray()
    for y in range(size):
        out.append(0)
        for x in range(size):
            r = g = b = a = 0
            for dy in range(SS):
                for dx in range(SS):
                    pr, pg, pb, pa = buf[y*SS+dy][x*SS+dx]
                    r += pr*pa; g += pg*pa; b += pb*pa; a += pa
            if a:
                out += bytes((r//a, g//a, b//a, a//(SS*SS)))
            else:
                out += b'\x00\x00\x00\x00'
    return bytes(out), size


def write_png(path, raw, size):
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    open(path, 'wb').write(png)


# Android adaptive layers are 108dp square at each density.
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324,
            'xxxhdpi': 432}

# The mark's diagonal has to fit the 66/108 circle the launcher guarantees.
# Anything larger has its corners shaved off on a round-masked launcher.
SAFE_INSET = 0.25


if __name__ == '__main__':
    import sys
    sd = sys.argv[1]
    raw, s = render(512)
    write_png(f'{sd}/folio_icon_512.png', raw, s)
    print('drawn 512')

    for name, px in ADAPTIVE.items():
        raw, s = render(px, with_background=False, inset=SAFE_INSET)
        write_png(f'{sd}/foreground_{name}.png', raw, s)

        raw, s = render(px, with_background=False, inset=SAFE_INSET,
                        monochrome=True)
        write_png(f'{sd}/monochrome_{name}.png', raw, s)
        print(f'drawn adaptive {name} {px}')
