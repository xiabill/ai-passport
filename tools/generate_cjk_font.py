#!/usr/bin/env python3
"""Generate the CJK font subset used by the hardware UI.

The LVGL Source Han Sans SC font shipped by LVGL is intentionally limited to
the most common CJK characters. That is useful for demos, but it does not
guarantee coverage for this project's UI copy. This generator scans the
firmware sources, renders every CJK character that can appear there, and
checks the generated cmap before returning.

Run from the repository:

    python3 tools/generate_cjk_font.py
    python3 tools/generate_cjk_font.py --check

Pillow is only needed while regenerating the checked-in C source.
"""

from pathlib import Path
import re
import sys

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = Path("/System/Library/Fonts/STHeiti Medium.ttc")
OUTPUT = ROOT / "main" / "ui_font_cjk.c"
CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
GLYPH_RE = re.compile(r'/\* U\+([0-9A-F]+) "([^"].*?)" \*/')


def glyph_chars():
    """Return all CJK characters in firmware source, excluding this output."""
    chars = set()
    for path in sorted((ROOT / "main").glob("*.c")):
        if path.name == OUTPUT.name:
            continue
        chars.update(CJK_RE.findall(path.read_text(encoding="utf-8")))
    return sorted(chars)


def make_font(size: int, name: str, fallback: str, chars: list[str],
              line_height: int, base_line: int, glyph_ofs_y: int) -> str:
    font = ImageFont.truetype(str(FONT_PATH), size, index=1)
    width = size
    height = size
    row_bytes = (width * 4 + 7) // 8
    bitmaps = bytearray()
    desc = [(0, 0, 0, 0, 0, 0)]

    for char in chars:
        image = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(image)
        bbox = draw.textbbox((0, 0), char, font=font)
        # Keep every CJK glyph in the same fixed cell. The source font's
        # antialiasing is quantized to LVGL's 4bpp grayscale format.
        draw.text((-bbox[0], -bbox[1]), char, font=font, fill=255)
        pixels = image.load()
        start = len(bitmaps)
        for y in range(height):
            for x in range(0, width, 2):
                left = round(pixels[x, y] * 15 / 255)
                right = round(pixels[x + 1, y] * 15 / 255)
                bitmaps.append((left << 4) | right)
        # Match the fallback font's line metrics. LVGL uses the label font's
        # line_height/base_line for every glyph, including fallback glyphs;
        # keeping CJK at 14/0 while Latin uses 16/3 makes mixed labels jump.
        desc.append((start, size * 16, width, height, 0, glyph_ofs_y))

    range_start = min(ord(c) for c in chars)
    unicode_list = [ord(c) - range_start for c in chars]
    range_length = max(unicode_list) + 1

    def array_u8(values):
        return ", ".join(str(v) for v in values)

    def array_u16(values):
        return ", ".join(str(v) for v in values)

    bitmap_lines = []
    for i in range(0, len(bitmaps), 16):
        bitmap_lines.append("    " + array_u8(bitmaps[i:i + 16]) + ",")
    desc_lines = [
        "    { .bitmap_index = 0, .adv_w = 0, .box_w = 0, .box_h = 0,"
        " .ofs_x = 0, .ofs_y = 0 },"
    ]
    for char, item in zip(chars, desc[1:]):
        desc_lines.append(
            f'    /* U+{ord(char):04X} "{char}" */\n'
            "    { .bitmap_index = %d, .adv_w = %d, .box_w = %d,"
            " .box_h = %d, .ofs_x = %d, .ofs_y = %d }," % item
        )

    return (
        f"static const uint8_t {name}_glyph_bitmap[] = {{\n"
        + "\n".join(bitmap_lines)
        + f"\n}};\n\n"
        + f"static const lv_font_fmt_txt_glyph_dsc_t {name}_glyph_dsc[] = {{\n"
        + "\n".join(desc_lines)
        + f"\n}};\n\n"
        + f"static const uint16_t {name}_unicode_list[] = {{ {array_u16(unicode_list)} }};\n"
        + f"static const lv_font_fmt_txt_cmap_t {name}_cmaps[] = {{\n"
        + f"    {{ .range_start = 0x{range_start:X}, .range_length = {range_length},\n"
        + f"       .glyph_id_start = 1, .unicode_list = {name}_unicode_list,\n"
        + f"       .glyph_id_ofs_list = NULL, .list_length = {len(unicode_list)},\n"
        + "       .type = LV_FONT_FMT_TXT_CMAP_SPARSE_TINY },\n"
        + "};\n\n"
        + f"static const lv_font_fmt_txt_dsc_t {name}_dsc = {{\n"
        + f"    .glyph_bitmap = {name}_glyph_bitmap,\n"
        + f"    .glyph_dsc = {name}_glyph_dsc,\n"
        + f"    .cmaps = {name}_cmaps,\n"
        + "    .kern_dsc = NULL,\n"
        + "    .kern_scale = 0,\n"
        + "    .cmap_num = 1,\n"
        + "    .bpp = 4,\n"
        + "    .kern_classes = 0,\n"
        + "    .bitmap_format = LV_FONT_FMT_TXT_PLAIN,\n"
        + "    // Glyph rows are byte-aligned 4bpp data. A non-zero stride makes\n"
        + "    // LVGL restart grayscale decoding at every row.\n"
        + f"    .stride = {row_bytes},\n"
        + "};\n\n"
        + f"const lv_font_t {name} = {{\n"
        + "    .get_glyph_dsc = lv_font_get_glyph_dsc_fmt_txt,\n"
        + "    .get_glyph_bitmap = lv_font_get_bitmap_fmt_txt,\n"
        + "    .release_glyph = NULL,\n"
        + f"    .line_height = {line_height},\n"
        + f"    .base_line = {base_line},\n"
        + "    .subpx = LV_FONT_SUBPX_NONE,\n"
        + "    .kerning = LV_FONT_KERNING_NONE,\n"
        + "    .static_bitmap = 1,\n"
        + "    .underline_position = 0,\n"
        + "    .underline_thickness = 0,\n"
        + f"    .dsc = &{name}_dsc,\n"
        + f"    .fallback = {fallback},\n"
        + "    .user_data = NULL,\n"
        + "};\n"
    )


def generated_chars():
    if not OUTPUT.exists():
        return set()
    return {match.group(2) for match in GLYPH_RE.finditer(OUTPUT.read_text(encoding="utf-8"))}


def check_coverage(chars):
    missing = sorted(set(chars) - generated_chars())
    if missing:
        raise SystemExit("CJK font coverage missing: " + " ".join(missing))
    print(f"CJK font coverage: PASS ({len(chars)} source glyphs present)")


def main():
    chars = glyph_chars()
    if not chars:
        raise SystemExit("No CJK characters found in main sources")
    if "--check" in sys.argv[1:]:
        check_coverage(chars)
        return
    if not FONT_PATH.exists():
        raise SystemExit(f"CJK source font not found: {FONT_PATH}")

    content = (
        '#include "ui_font.h"\n'
        '#include "lvgl.h"\n'
        '#include "font/fmt_txt/lv_font_fmt_txt.h"\n\n'
    )
    # These match Montserrat 14's 16px line / 3px baseline. The -1 glyph
    # offset places the 14px CJK cell on that same visual baseline.
    content += make_font(14, "ui_font_cjk_14", "&lv_font_montserrat_14", chars,
                         line_height=16, base_line=3, glyph_ofs_y=-1)
    content += "\n"
    # The 16px title font is baseline-compatible with Montserrat 16.
    content += make_font(16, "ui_font_cjk_16", "&lv_font_montserrat_16", chars,
                         line_height=18, base_line=3, glyph_ofs_y=-1)
    OUTPUT.write_text(content, encoding="utf-8")
    check_coverage(chars)
    print(f"generated {OUTPUT} with {len(chars)} CJK glyphs")


if __name__ == "__main__":
    main()
