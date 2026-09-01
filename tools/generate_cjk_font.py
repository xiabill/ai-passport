#!/usr/bin/env python3
"""Generate the small LVGL CJK font subset used by the hardware display.

The generated file is intentionally a subset rather than a full CJK font so
the ESP32 firmware keeps its flash footprint small. Run from the repository:

    python3 tools/generate_cjk_font.py

Pillow is only needed while regenerating the checked-in C source.
"""

from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = "/System/Library/Fonts/STHeiti Medium.ttc"
# Keep this list tied to strings rendered by vibe_ui.c. Sort/dedupe makes the
# cmap stable and keeps the generated diff deterministic.
TEXT = """
连接中 就绪 录音中 处理中 离线
语音 翻译 随便问 豆包 蓝牙 已连接 未连接
电量 音频 音频离线 音频等待 音频正常 录音中 丢包
最近 发送 取消 启动 停止 全选 删除 确认 返回 上 下 等待 空闲
正常模式 省电模式 待机 按键说话 语音助手
"""


def glyph_chars():
    return sorted({c for c in TEXT if "\u4e00" <= c <= "\u9fff"})


def make_font(size: int, name: str, fallback: str):
    font = ImageFont.truetype(FONT_PATH, size, index=1)  # Heiti SC Medium
    width = size
    height = size
    row_bytes = (width + 7) // 8
    bitmaps = bytearray()
    desc = [(0, 0, 0, 0, 0, 0)]

    for char in glyph_chars():
        image = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(image)
        bbox = draw.textbbox((0, 0), char, font=font)
        # Move the glyph's ink to the top of the fixed cell. LVGL places the
        # cell at ofs_y=0, which keeps CJK labels aligned with their fallback
        # Latin font when centered in the compact panels.
        draw.text((0, -bbox[1]), char, font=font, fill=255)
        pixels = image.load()
        start = len(bitmaps)
        for y in range(height):
            for byte in range(row_bytes):
                value = 0
                for bit in range(8):
                    x = byte * 8 + bit
                    if x < width and pixels[x, y] >= 96:
                        value |= 1 << (7 - bit)
                bitmaps.append(value)
        desc.append((start, size * 16, width, height, 0, 0))

    range_start = min(ord(c) for c in glyph_chars())
    unicode_list = [ord(c) - range_start for c in glyph_chars()]
    range_length = max(unicode_list) + 1

    def array_u8(values):
        return ", ".join(str(v) for v in values)

    def array_u16(values):
        return ", ".join(str(v) for v in values)

    bitmap_lines = []
    for i in range(0, len(bitmaps), 16):
        bitmap_lines.append("    " + array_u8(bitmaps[i:i + 16]) + ",")
    desc_lines = []
    for item in desc:
        desc_lines.append("    { .bitmap_index = %d, .adv_w = %d, .box_w = %d, .box_h = %d, .ofs_x = %d, .ofs_y = %d }," % item)

    return f"""\nstatic const uint8_t {name}_glyph_bitmap[] = {{\n""" + "\n".join(bitmap_lines) + f"""\n}};

static const lv_font_fmt_txt_glyph_dsc_t {name}_glyph_dsc[] = {{
""" + "\n".join(desc_lines) + f"""
}};

static const uint16_t {name}_unicode_list[] = {{ {array_u16(unicode_list)} }};
static const lv_font_fmt_txt_cmap_t {name}_cmaps[] = {{
    {{ .range_start = 0x{range_start:X}, .range_length = {range_length},
       .glyph_id_start = 1, .unicode_list = {name}_unicode_list,
       .glyph_id_ofs_list = NULL, .list_length = {len(unicode_list)},
       .type = LV_FONT_FMT_TXT_CMAP_SPARSE_TINY }},
}};

static const lv_font_fmt_txt_dsc_t {name}_dsc = {{
    .glyph_bitmap = {name}_glyph_bitmap,
    .glyph_dsc = {name}_glyph_dsc,
    .cmaps = {name}_cmaps,
    .kern_dsc = NULL,
    .kern_scale = 0,
    .cmap_num = 1,
    .bpp = 1,
    .kern_classes = 0,
    .bitmap_format = LV_FONT_FMT_TXT_PLAIN,
    .stride = 0,
}};

const lv_font_t {name} = {{
    .get_glyph_dsc = lv_font_get_glyph_dsc_fmt_txt,
    .get_glyph_bitmap = lv_font_get_bitmap_fmt_txt,
    .release_glyph = NULL,
    .line_height = {size},
    .base_line = 0,
    .subpx = LV_FONT_SUBPX_NONE,
    .kerning = LV_FONT_KERNING_NONE,
    .static_bitmap = 1,
    .underline_position = 0,
    .underline_thickness = 0,
    .dsc = &{name}_dsc,
    .fallback = {fallback},
    .user_data = NULL,
}};
"""


def main():
    if not Path(FONT_PATH).exists():
        raise SystemExit(f"CJK source font not found: {FONT_PATH}")
    chars = glyph_chars()
    if not chars:
        raise SystemExit("No CJK characters selected")
    output = ROOT / "main" / "ui_font_cjk.c"
    content = """#include \"ui_font.h\"\n#include \"lvgl.h\"\n#include \"font/fmt_txt/lv_font_fmt_txt.h\"\n\n"""
    content += make_font(14, "ui_font_cjk_14", "&lv_font_montserrat_14")
    content += "\n"
    content += make_font(20, "ui_font_cjk_20", "&lv_font_montserrat_20")
    output.write_text(content)
    print(f"generated {output} with {len(chars)} CJK glyphs")


if __name__ == "__main__":
    main()
