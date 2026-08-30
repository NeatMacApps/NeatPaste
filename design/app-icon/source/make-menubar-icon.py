#!/usr/bin/env python3
"""生成 NeatPaste 菜单栏双键帽模板图（18px / 36px）。

菜单栏图标从应用图标的双键帽关系重绘：前层保留 ⌘，后层在交叠区域的上半段断开，
只从右侧和下侧露出轮廓。输出纯黑主体与全透明背景的 RGBA PNG，供 MenuBarIcon.imageset 使用。
依赖：Pillow（pip3 install --break-system-packages pillow）
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


def _scaled_box(values: tuple[float, float, float, float], unit: float) -> tuple[int, int, int, int]:
    """把 36 单位画布中的矩形换算为高分辨率像素。"""
    x0, y0, x1, y1 = values
    return (
        round(x0 * unit),
        round(y0 * unit),
        round(x1 * unit),
        round(y1 * unit),
    )


def _draw_command_glyph(draw: ImageDraw.ImageDraw, unit: float) -> None:
    """绘制适合菜单栏小尺寸的四环 ⌘ 符号。"""
    stroke = max(1, round(1.65 * unit))
    centers = ((9.35, 11.45), (18.05, 11.45), (9.35, 18.55), (18.05, 18.55))

    draw.line(
        [(round(9.35 * unit), round(15 * unit)), (round(18.05 * unit), round(15 * unit))],
        fill=255,
        width=stroke,
    )
    draw.line(
        [(round(13.7 * unit), round(11.45 * unit)), (round(13.7 * unit), round(18.55 * unit))],
        fill=255,
        width=stroke,
    )

    radius = 2.2 * unit
    for center_x, center_y in centers:
        draw.ellipse(
            (
                round(center_x * unit - radius),
                round(center_y * unit - radius),
                round(center_x * unit + radius),
                round(center_y * unit + radius),
            ),
            outline=255,
            width=stroke,
        )


def make_clip(size: int) -> Image.Image:
    """在高分辨率画布上重绘双键帽菜单栏模板图。"""
    image = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(image)
    unit = size / 36

    # 后层只保留右侧与下侧轮廓，交叠区域的上半段不画线。
    rear_points = (
        (30.3, 12.0),
        (31.5, 12.2),
        (32.6, 13.1),
        (33.1, 14.5),
        (33.2, 16.2),
        (33.2, 27.3),
        (33.1, 28.7),
        (32.4, 30.0),
        (31.0, 31.0),
        (29.0, 31.5),
        (18.2, 31.5),
    )
    draw.line(
        [(round(x * unit), round(y * unit)) for x, y in rear_points],
        fill=255,
        width=max(1, round(2 * unit)),
        joint="curve",
    )

    # 前层键帽是黑色外环，内页保持透明。
    outer = _scaled_box((2.75, 3.0, 26.25, 27.8), unit)
    inner = _scaled_box((5.10, 5.45, 23.90, 25.05), unit)
    draw.rounded_rectangle(outer, radius=round(4.7 * unit), fill=255)
    draw.rounded_rectangle(inner, radius=round(3.15 * unit), fill=0)
    _draw_command_glyph(draw, unit)

    # 高分辨率旋转后缩小，边缘只通过 alpha 抗锯齿，不引入灰色像素。
    return image.rotate(-8, resample=Image.BICUBIC, expand=False)


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
    export(make_clip(1152), 18, imageset / "menubar.png")
    export(make_clip(1152), 36, imageset / "menubar@2x.png")
    print(f"已生成：{imageset}/menubar.png 与 menubar@2x.png")
