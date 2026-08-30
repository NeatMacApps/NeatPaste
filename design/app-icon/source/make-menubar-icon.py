#!/usr/bin/env python3
"""生成 NeatPaste 菜单栏双键帽模板图（18px / 36px）。

菜单栏图标从应用图标的双键帽关系重绘：前层保留 ⌘，后层在交叠区域的上半段断开，
只从右侧和下侧露出轮廓。输出纯黑主体与全透明背景的 RGBA PNG，供 MenuBarIcon.imageset 使用。
依赖：Pillow（pip3 install --break-system-packages pillow）
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


BASE_SIZE = 18
MASTER_SIZE = 1152
BLACK = 255


def _px(value: float, unit: float) -> int:
    return round(value * unit)


def _rounded_rectangle(
    draw: ImageDraw.ImageDraw,
    box: tuple[float, float, float, float],
    radius: float,
    unit: float,
    fill: int,
) -> None:
    draw.rounded_rectangle(
        tuple(_px(value, unit) for value in box),
        radius=_px(radius, unit),
        fill=fill,
    )


def _draw_command_glyph(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    unit: float,
) -> None:
    """绘制源图中的四环 ⌘，在 18px 下保持连续实心核心。"""
    center_x, center_y = center
    stroke = max(1, _px(1.45, unit))
    radius = 1.65
    loop_centers = (
        (center_x - 1.65, center_y - 1.65),
        (center_x + 1.65, center_y - 1.65),
        (center_x - 1.65, center_y + 1.65),
        (center_x + 1.65, center_y + 1.65),
    )

    draw.line(
        [(_px(center_x - 1.65, unit), _px(center_y, unit)),
         (_px(center_x + 1.65, unit), _px(center_y, unit))],
        fill=BLACK,
        width=stroke,
    )
    draw.line(
        [(_px(center_x, unit), _px(center_y - 1.65, unit)),
         (_px(center_x, unit), _px(center_y + 1.65, unit))],
        fill=BLACK,
        width=stroke,
    )

    for loop_x, loop_y in loop_centers:
        draw.ellipse(
            (
                _px(loop_x - radius, unit),
                _px(loop_y - radius, unit),
                _px(loop_x + radius, unit),
                _px(loop_y + radius, unit),
            ),
            outline=BLACK,
            width=stroke,
        )


def _draw_c_glyph(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    width: float,
    height: float,
    unit: float,
) -> None:
    """用单一弧线保留后层 C 标记，开口朝右。"""
    center_x, center_y = center
    radius_x = width / 2
    radius_y = height / 2
    points = []
    for index in range(49):
        angle = math.radians(-60 - index * 5)
        points.append(
            (_px(center_x + radius_x * math.cos(angle), unit),
             _px(center_y + radius_y * math.sin(angle), unit))
        )
    stroke = max(1, _px(1.20, unit))
    draw.line(points, fill=BLACK, width=stroke, joint="curve")
    cap_radius = stroke / 2
    for point_x, point_y in (points[0], points[-1]):
        draw.ellipse(
            (round(point_x - cap_radius), round(point_y - cap_radius),
             round(point_x + cap_radius), round(point_y + cap_radius)),
            fill=BLACK,
        )


def _rotated_key_layer(
    size: int,
    center: tuple[float, float],
    width: float,
    height: float,
    radius: float,
    angle: float,
    face_inset: float | None,
    face_offset: tuple[float, float],
    marker: str | None,
) -> Image.Image:
    """在高分辨率画布绘制一个键帽，并绕自身中心旋转。"""
    unit = size / BASE_SIZE
    layer = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(layer)
    center_x, center_y = center
    outer = (
        center_x - width / 2,
        center_y - height / 2,
        center_x + width / 2,
        center_y + height / 2,
    )
    _rounded_rectangle(draw, outer, radius, unit, BLACK)

    if face_inset is not None:
        inner = (
            center_x - width / 2 + face_inset + face_offset[0],
            center_y - height / 2 + face_inset + face_offset[1],
            center_x + width / 2 - face_inset + face_offset[0],
            center_y + height / 2 - face_inset + face_offset[1],
        )
        _rounded_rectangle(draw, inner, max(0.1, radius - face_inset * 0.7), unit, 0)

        if marker == "C":
            _draw_c_glyph(draw, (center_x + 0.55, center_y + 0.65), 3.65, 4.65, unit)
        elif marker == "command":
            _draw_command_glyph(draw, (center_x, center_y - 0.55), unit)
            _rounded_rectangle(
                draw,
                (center_x - 4.35 / 2, center_y + 4.35 - 1.28 / 2,
                 center_x + 4.35 / 2, center_y + 4.35 + 1.28 / 2),
                0.64,
                unit,
                BLACK,
            )

    return layer.rotate(
        angle,
        resample=Image.Resampling.BICUBIC,
        center=(_px(center_x, unit), _px(center_y, unit)),
        expand=False,
    )


def make_clip(size: int = MASTER_SIZE) -> Image.Image:
    """按母版的前后遮挡关系重绘模板图。"""
    rear_center = (11.65, 11.25)
    rear = _rotated_key_layer(
        size,
        rear_center,
        width=10.25,
        height=10.15,
        radius=2.05,
        angle=-6.0,
        face_inset=1.08,
        face_offset=(0, -0.12),
        marker="C",
    )

    front_center = (6.85, 6.15)
    front_silhouette = _rotated_key_layer(
        size,
        front_center,
        width=12.65,
        height=12.05,
        radius=2.35,
        angle=-6.0,
        face_inset=None,
        face_offset=(0, 0),
        marker=None,
    )
    # 前层完整遮住后层，避免后层线条从前层透明内页穿出。
    rear = ImageChops.subtract(rear, front_silhouette)

    front = _rotated_key_layer(
        size,
        front_center,
        width=12.65,
        height=12.05,
        radius=2.35,
        angle=-6.0,
        face_inset=1.12,
        face_offset=(0, -0.40),
        marker="command",
    )
    return ImageChops.lighter(rear, front)


def export(master: Image.Image, pixel_size: int, path: Path) -> None:
    """把模板图缩放到目标尺寸并输出 RGBA PNG。"""
    alpha = master.resize((pixel_size, pixel_size), Image.Resampling.LANCZOS)
    transparent_rgb = Image.new("L", (pixel_size, pixel_size), 0)
    rgba = Image.merge("RGBA", (transparent_rgb, transparent_rgb, transparent_rgb, alpha))
    rgba.save(path)


if __name__ == "__main__":
    here = Path(__file__).resolve().parent
    imageset = here.parent.parent.parent / "NeatPaste/Assets.xcassets/MenuBarIcon.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    master = make_clip()
    export(master, 18, imageset / "menubar.png")
    export(master, 36, imageset / "menubar@2x.png")
    print(f"已生成：{imageset}/menubar.png 与 menubar@2x.png")
