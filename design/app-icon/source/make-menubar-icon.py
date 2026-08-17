#!/usr/bin/env python3
"""生成菜单栏回形针模板图（18px / 36px）。

从应用图标的回形针语义提炼的小尺寸重绘：双层嵌套圆角环、38° 斜放。
输出纯黑主体 + 全透明背景的 RGBA PNG，供 MenuBarIcon.imageset 使用。
依赖：Pillow（pip3 install --break-system-packages pillow numpy）
"""
from PIL import Image, ImageDraw

def make_clip(S: int, rot: float = 38, W: float = 40, H: float = 88,
              sw: float = 9, gap: float = 7.5) -> Image.Image:
    """在高分辨率画布 S×S 上画双层圆角环并旋转。参数为 100 单位制。"""
    img = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(img)
    u = S / 100
    Wp, Hp, swp, gp = W * u, H * u, sw * u, gap * u
    x0, y0 = (S - Wp) / 2, (S - Hp) / 2
    # 外环
    d.rounded_rectangle([x0, y0, x0 + Wp, y0 + Hp], radius=Wp / 2,
                        outline=255, width=max(1, int(swp)))
    # 内环
    ix0, iy0 = x0 + swp + gp, y0 + swp + gp
    iW, iH = Wp - 2 * (swp + gp), Hp - 2 * (swp + gp)
    if iW > 2 and iH > 2:
        d.rounded_rectangle([ix0, iy0, ix0 + iW, iy0 + iH],
                            radius=min(Wp / 2, iW / 2), outline=255,
                            width=max(1, int(swp * 0.9)))
    return img.rotate(rot, resample=Image.BICUBIC, expand=False)


def export(master: Image.Image, px: int, box: int, path: str) -> None:
    """按 px 画布、box 主体居中导出纯黑模板 PNG。"""
    t = master.resize((box, box), Image.LANCZOS)
    canvas = Image.new('L', (px, px), 0)
    canvas.paste(t, ((px - box) // 2, (px - box) // 2))
    rgba = Image.merge('RGBA', [Image.new('L', (px, px), 0)] * 3 + [canvas])
    rgba.save(path)


if __name__ == '__main__':
    import pathlib
    here = pathlib.Path(__file__).resolve().parent
    imageset = here.parent.parent.parent / 'NeatPaste/Assets.xcassets/MenuBarIcon.imageset'
    master = make_clip(1152)
    export(master, 18, 17, imageset / 'menubar.png')
    export(master, 36, 34, imageset / 'menubar@2x.png')
    print(f'已生成：{imageset}/menubar.png 与 menubar@2x.png')
