#!/usr/bin/env python3
"""Generate NeatPaste app icon and menu-bar template images."""

from __future__ import annotations

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "NeatPaste", "Assets.xcassets", "AppIcon.appiconset")
MENUSET = os.path.join(ROOT, "NeatPaste", "Assets.xcassets", "MenuBarIcon.imageset")
DESIGN = os.path.join(ROOT, "design", "app-icon")

BG = (21, 32, 43, 255)  # 克制深色
CLIP = (46, 230, 255, 255)  # 亮青强调
WHITE = (255, 255, 255, 255)
INNER = (232, 244, 248, 255)


def write_png(path: str, width: int, height: int, rgba: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgba[y * width * 4 : (y + 1) * width * 4] for y in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)


def blend(dst: list[int], x: int, y: int, w: int, color: tuple[int, int, int, int], alpha: float = 1.0) -> None:
    if x < 0 or y < 0 or x >= w:
        return
    i = (y * w + x) * 4
    if i < 0 or i + 3 >= len(dst):
        return
    a = color[3] / 255.0 * alpha
    if a <= 0:
        return
    ia = 1.0 - a
    dst[i] = int(dst[i] * ia + color[0] * a)
    dst[i + 1] = int(dst[i + 1] * ia + color[1] * a)
    dst[i + 2] = int(dst[i + 2] * ia + color[2] * a)
    dst[i + 3] = 255 if color[3] == 255 and alpha >= 1 else max(dst[i + 3], int(color[3] * alpha))


def fill_round_rect(
    pixels: list[int],
    size: int,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    radius: float,
    color: tuple[int, int, int, int],
) -> None:
    for y in range(max(0, int(math.floor(y0))), min(size, int(math.ceil(y1)) + 1)):
        for x in range(max(0, int(math.floor(x0))), min(size, int(math.ceil(x1)) + 1)):
            px = x + 0.5
            py = y + 0.5
            cx = min(max(px, x0 + radius), x1 - radius)
            cy = min(max(py, y0 + radius), y1 - radius)
            dx = px - cx
            dy = py - cy
            if dx * dx + dy * dy <= radius * radius:
                blend(pixels, x, y, size, color)


def fill_rect(
    pixels: list[int],
    size: int,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    color: tuple[int, int, int, int],
) -> None:
    for y in range(max(0, y0), min(size, y1 + 1)):
        for x in range(max(0, x0), min(size, x1 + 1)):
            blend(pixels, x, y, size, color)


def draw_clipboard(size: int, *, opaque: bool) -> bytes:
    pixels = [0] * (size * size * 4)
    if opaque:
        fill_rect(pixels, size, 0, 0, size - 1, size - 1, BG)

    s = size / 1024.0
    body_x0, body_y0, body_x1, body_y1 = 278 * s, 230 * s, 746 * s, 870 * s
    fill_round_rect(pixels, size, body_x0, body_y0, body_x1, body_y1, 72 * s, WHITE)

    inner_x0, inner_y0, inner_x1, inner_y1 = 330 * s, 360 * s, 694 * s, 810 * s
    fill_round_rect(pixels, size, inner_x0, inner_y0, inner_x1, inner_y1, 36 * s, INNER)

    for index, y in enumerate((430, 520, 610, 700)):
        line_y0 = int((y - 8) * s)
        line_y1 = int((y + 8) * s)
        inset = 40 * s if index < 3 else 120 * s
        fill_round_rect(
            pixels,
            size,
            inner_x0 + inset,
            line_y0,
            inner_x1 - inset,
            line_y1,
            8 * s,
            (46, 230, 255, 220) if opaque else (0, 0, 0, 220),
        )

    clip_x0, clip_y0, clip_x1, clip_y1 = 390 * s, 150 * s, 634 * s, 340 * s
    clip_color = CLIP if opaque else (0, 0, 0, 255)
    fill_round_rect(pixels, size, clip_x0, clip_y0, clip_x1, clip_y1, 48 * s, clip_color)
    hole_color = BG if opaque else (0, 0, 0, 0)
    if opaque:
        fill_round_rect(pixels, size, 430 * s, 195 * s, 594 * s, 255 * s, 24 * s, hole_color)
    else:
        # 模板图挖空：把中间写成全透明
        for y in range(int(195 * s), int(255 * s)):
            for x in range(int(430 * s), int(594 * s)):
                i = (y * size + x) * 4
                if 0 <= i < len(pixels) - 3:
                    pixels[i : i + 4] = [0, 0, 0, 0]

    if opaque:
        for i in range(0, len(pixels), 4):
            pixels[i + 3] = 255
    return bytes(pixels)


def scale_nearest(src: bytes, src_size: int, dst_size: int) -> bytes:
    out = bytearray(dst_size * dst_size * 4)
    for y in range(dst_size):
        sy = min(src_size - 1, int(y * src_size / dst_size))
        for x in range(dst_size):
            sx = min(src_size - 1, int(x * src_size / dst_size))
            si = (sy * src_size + sx) * 4
            di = (y * dst_size + x) * 4
            out[di : di + 4] = src[si : si + 4]
    return bytes(out)


def main() -> None:
    master = draw_clipboard(1024, opaque=True)
    os.makedirs(DESIGN, exist_ok=True)
    write_png(os.path.join(DESIGN, "AppIcon-1024.png"), 1024, 1024, master)

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in sizes.items():
        pixels = master if size == 1024 else scale_nearest(master, 1024, size)
        write_png(os.path.join(ICONSET, name), size, size, pixels)

    template = draw_clipboard(256, opaque=False)
    write_png(os.path.join(MENUSET, "clipboard@2x.png"), 256, 256, template)
    small = scale_nearest(template, 256, 18)
    # 菜单栏模板图按 18pt 输出；先从 256 收到 18 会糊，改为单独绘制 18/36。
    template36 = draw_clipboard(36, opaque=False)
    template18 = draw_clipboard(18, opaque=False)
    write_png(os.path.join(MENUSET, "clipboard.png"), 18, 18, template18)
    write_png(os.path.join(MENUSET, "clipboard@2x.png"), 36, 36, template36)
    print("已生成应用图标与菜单栏模板图")


if __name__ == "__main__":
    main()
