#!/usr/bin/env python3
"""Convert an Anex86-compatible PC-98 font BMP (e.g. FREECG98.BMP) to BDF.

Kept as a utility; the NixOS build now produces a scalable outline TTF via
make-outline-font.py. Decoding lives in pc98font.py (shared source of truth).
"""

from __future__ import annotations

import sys
from pathlib import Path

import pc98font


def write_glyph(out, name: str, encoding: int, cell_w: int, cell_h: int, bitmap: bytes) -> None:
    out.write(f"STARTCHAR {name}\n")
    out.write(f"ENCODING {encoding}\n")
    out.write("SWIDTH 1000 0\n")
    out.write(f"DWIDTH {cell_w} 0\n")
    out.write(f"BBX {cell_w} {cell_h} 0 -2\n")
    out.write("BITMAP\n")

    if cell_w == 8:
        for y in range(16):
            out.write(f"{bitmap[y]:02X}\n")
    else:
        for y in range(16):
            left = bitmap[y * 2]
            right = bitmap[y * 2 + 1]
            out.write(f"{left:02X}{right:02X}\n")

    out.write("ENDCHAR\n")


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <input.bmp> <output.bdf>", file=sys.stderr)
        return 1

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    glyphs = pc98font.decode(src)

    with dst.open("w", encoding="ascii") as out:
        out.write("STARTFONT 2.1\n")
        out.write("FONT -Free CG98-Medium-R-Normal--16-160-75-75-C-80-ISO10646-1\n")
        out.write("SIZE 16 75 75\n")
        out.write("FONTBOUNDINGBOX 16 16 0 -2\n")
        out.write("STARTPROPERTIES 7\n")
        out.write("FAMILY_NAME \"Free CG98\"\n")
        out.write("CHARSET_REGISTRY \"ISO10646\"\n")
        out.write("CHARSET_ENCODING \"1\"\n")
        out.write("PIXEL_SIZE 16\n")
        out.write("POINT_SIZE 160\n")
        out.write("FONT_ASCENT 14\n")
        out.write("FONT_DESCENT 2\n")
        out.write("ENDPROPERTIES\n")

        out.write(f"CHARS {len(glyphs)}\n")
        for cp, cell_w, cell_h, bitmap in glyphs:
            write_glyph(out, f"U{cp:04X}", cp, cell_w, cell_h, bitmap)

        out.write("ENDFONT\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
