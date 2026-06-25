#!/usr/bin/env -S fontforge -lang=py -script
"""Build a scalable outline TTF from the PC-98 bitmap font.

Each source pixel is emitted as a square contour, then overlaps are merged.
The result is a true vector font, so Ghostty's ctrl +/- font resizing scales
it crisply at any size -- unlike an embedded-bitmap strike, which only renders
at its single native pixel size.

usage: fontforge -lang=py -script make-outline-font.py <input.bmp> <output.ttf>
"""

import sys
from pathlib import Path

import fontforge

import pc98font

PX = 64                          # font units per source pixel
CELL_H = 16                      # source cell height in pixels
DESCENT_PX = 2                   # pixels below the baseline (BDF yoff = -2)
ASCENT_PX = CELL_H - DESCENT_PX  # 14
EM_REFERENCE_CP = 0xE000         # PUA glyph filling the full em (shader metrics)


def row_bits(cell_w: int, bitmap: bytes, r: int) -> list[int]:
    if cell_w == 8:
        value = bitmap[r]
        width = 8
    else:
        value = (bitmap[r * 2] << 8) | bitmap[r * 2 + 1]
        width = 16
    return [(value >> (width - 1 - c)) & 1 for c in range(width)]


def build_glyph(glyph, cell_w: int, cell_h: int, bitmap: bytes) -> None:
    pen = glyph.glyphPen()
    for r in range(cell_h):
        bits = row_bits(cell_w, bitmap, r)
        # Font-space top/bottom edge of source row r (row 0 is the top row).
        y_top = (ASCENT_PX - r) * PX
        y_bot = y_top - PX
        for c, on in enumerate(bits):
            if not on:
                continue
            x_left = c * PX
            x_right = x_left + PX
            pen.moveTo((x_left, y_bot))
            pen.lineTo((x_left, y_top))
            pen.lineTo((x_right, y_top))
            pen.lineTo((x_right, y_bot))
            pen.closePath()
    pen = None  # flush the pen into the glyph
    glyph.removeOverlap()
    glyph.correctDirection()
    glyph.round()
    # The pen resets the advance width, so set it last.
    glyph.width = cell_w * PX


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <input.bmp> <output.ttf>", file=sys.stderr)
        return 1

    src = Path(sys.argv[1])
    out = sys.argv[2]
    glyphs = pc98font.decode(src)

    font = fontforge.font()
    font.encoding = "UnicodeFull"
    font.ascent = ASCENT_PX * PX    # 896
    font.descent = DESCENT_PX * PX  # 128  (em = 1024)
    font.familyname = "Free CG98"
    font.fontname = "FreeCG98"
    font.fullname = "Free CG98"
    font.weight = "Medium"
    font.version = "local"
    # Mark as a monospaced Latin-text font for shaping/detection.
    font.os2_panose = (2, 0, 5, 9, 0, 0, 0, 0, 0, 0)

    # Pin the vertical line metrics to the exact em (ascent + descent), with zero
    # line gap, so the host's cell height == 16 native font-pixel rows. FontForge
    # would otherwise auto-pad these tables (adding a line gap), which makes the
    # terminal cell taller than the glyph and leaves an un-scanlined band between
    # rows. Ghostty reads hhea first, then OS/2 sTypo*, then usWin*, so we set all
    # three consistently and enable USE_TYPO_METRICS for other renderers.
    ascent_units = ASCENT_PX * PX     # 896
    descent_units = DESCENT_PX * PX   # 128 (magnitude; below the baseline)
    font.os2_use_typo_metrics = 1
    for attr in (
        "hhea_ascent_add",
        "hhea_descent_add",
        "os2_typoascent_add",
        "os2_typodescent_add",
        "os2_winascent_add",
        "os2_windescent_add",
    ):
        setattr(font, attr, 0)
    font.hhea_ascent = ascent_units
    font.hhea_descent = -descent_units
    font.hhea_linegap = 0
    font.os2_typoascent = ascent_units
    font.os2_typodescent = -descent_units
    font.os2_typolinegap = 0
    font.os2_winascent = ascent_units
    font.os2_windescent = descent_units

    for cp, cell_w, cell_h, bitmap in glyphs:
        glyph = font.createChar(cp)
        build_glyph(glyph, cell_w, cell_h, bitmap)

    # Private-use reference glyph (U+E000): a fully-filled 8x16 cell spanning the
    # whole em (top of ascent to bottom of descent). The Ghostty cell-size patch
    # rasterizes this to learn the exact on-screen size and placement of one
    # cell's font-pixel grid, which the CRT shader uses to align scanlines.
    block = font.createChar(EM_REFERENCE_CP)
    build_glyph(block, 8, CELL_H, b"\xff" * CELL_H)

    font.generate(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
