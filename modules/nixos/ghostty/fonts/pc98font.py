#!/usr/bin/env python3
"""Decoder for Anex86-compatible PC-98 font BMPs (e.g. FREECG98.BMP).

Pure-stdlib so it can be imported both from CPython (the BDF CLI) and from
FontForge's embedded interpreter (the outline-font builder).
"""

from __future__ import annotations

import struct
from pathlib import Path

K_FONT_16X16_CHARS = 8831
K_FONT_8X16_CHARS = 256
ROW_BYTES = 2048 // 8


def read_bmp(path: Path) -> tuple[bytes, int]:
    data = Path(path).read_bytes()
    if data[:2] != b"BM":
        raise ValueError(f"{path}: not a BMP file")
    image_offset = struct.unpack_from("<I", data, 10)[0]
    if struct.unpack_from("<I", data, 14)[0] != 40:
        raise ValueError(f"{path}: expected 40-byte BITMAPINFOHEADER")
    width, height = struct.unpack_from("<ii", data, 18)
    planes, bpp = struct.unpack_from("<HH", data, 26)
    if (width, height, planes, bpp) != (2048, 2048, 1, 1):
        raise ValueError(f"{path}: expected 2048x2048 1bpp bitmap")
    return data, image_offset


def load_fonts(data: bytes, image_offset: int) -> tuple[list[bytes], list[bytes]]:
    font_16x16 = [bytes(32) for _ in range(K_FONT_16X16_CHARS)]
    pos = image_offset

    for row in range(95, -1, -1):
        for y in range(15, -1, -1):
            pos += 2  # skip 16 pixels
            for col in range(96):
                a = data[pos] ^ 0xFF
                b = data[pos + 1] ^ 0xFF
                pos += 2
                point = row + col * 96
                if point < K_FONT_16X16_CHARS:
                    glyph = bytearray(font_16x16[point])
                    glyph[y * 2] = a
                    glyph[y * 2 + 1] = b
                    font_16x16[point] = bytes(glyph)
            pos += (2048 - 96 * 16 - 16) // 8

    font_8x16 = [bytearray(16) for _ in range(K_FONT_8X16_CHARS)]
    pos = image_offset + (2048 - 16) * ROW_BYTES
    for y in range(15, -1, -1):
        for i in range(K_FONT_8X16_CHARS):
            font_8x16[i][y] = data[pos] ^ 0xFF
            pos += 1

    return [bytes(g) for g in font_8x16], font_16x16


def sjis_glyph_index(lead: int, trail: int) -> int | None:
    if 0x81 <= lead <= 0x9F:
        hiblock = lead - 0x81
    elif 0xE0 <= lead <= 0xEE:
        hiblock = lead - 0x81 - 0x40
    else:
        return None

    glyph = hiblock * 192
    if 0x40 <= trail <= 0x7E:
        glyph += trail - 0x3F
    elif 0x80 <= trail <= 0x9D:
        glyph += trail - 0x80 + 64
    elif 0x9E <= trail <= 0xFC:
        glyph += trail - 0x9E + 96
    else:
        return None

    if glyph >= K_FONT_16X16_CHARS:
        return None
    return glyph


def sjis_to_unicode(lead: int, trail: int) -> int | None:
    try:
        return ord(bytes([lead, trail]).decode("shift_jis"))
    except UnicodeDecodeError:
        return None


def build_glyph_list(
    font_8x16: list[bytes], font_16x16: list[bytes]
) -> list[tuple[int, int, int, bytes]]:
    """Return (codepoint, cell_w, cell_h, bitmap) tuples for every glyph."""
    glyphs: list[tuple[int, int, int, bytes]] = []
    for cp in range(K_FONT_8X16_CHARS):
        glyphs.append((cp, 8, 16, font_8x16[cp]))

    seen: set[int] = set(range(K_FONT_8X16_CHARS))
    for lead in range(0x81, 0xF0):
        for trail in range(0x40, 0xFF):
            glyph = sjis_glyph_index(lead, trail)
            if glyph is None:
                continue
            cp = sjis_to_unicode(lead, trail)
            if cp is None or cp in seen:
                continue
            seen.add(cp)
            glyphs.append((cp, 16, 16, font_16x16[glyph]))

    return glyphs


def decode(path: Path) -> list[tuple[int, int, int, bytes]]:
    data, image_offset = read_bmp(path)
    font_8x16, font_16x16 = load_fonts(data, image_offset)
    return build_glyph_list(font_8x16, font_16x16)
