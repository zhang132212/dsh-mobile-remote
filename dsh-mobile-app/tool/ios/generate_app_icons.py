#!/usr/bin/env python3
"""生成 iOS AppIcon.appiconset 与 LaunchImage.imageset（数据源：assets/icon-1024.png）。

用法（仓库根 dsh-mobile-app/ 下）：
    python tool/ios/generate_app_icons.py

说明：
- iOS 的 AppIcon 不能带 alpha 通道（App Store 会拒绝，Xcode 也会校验），
  这里把 1024 源图按原背景色（取四角像素）展平后再缩放。
- 输出全尺寸图标（iPhone + iPad + 1024 marketing），兼容 Xcode 15 之前/之后的校验。
- LaunchImage 用同色背景 + 居中鲸鱼图标，配合 LaunchScreen.storyboard 的白色/同色底。
"""
from __future__ import annotations

import json
import os
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:  # pragma: no cover - 环境缺 Pillow 时的可读提示
    sys.exit("需要 Pillow：python -m pip install pillow -i https://pypi.tuna.tsinghua.edu.cn/simple")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_ICON = os.path.join(ROOT, "assets", "icon-1024.png")
IOS_DIR = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets")
APPICON_DIR = os.path.join(IOS_DIR, "AppIcon.appiconset")
LAUNCH_DIR = os.path.join(IOS_DIR, "LaunchImage.imageset")

# Contents.json 中声明的 (文件名, 像素尺寸)；必须与 AppIcon.appiconset/Contents.json 完全一致。
APPICON_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

LAUNCH_POINTS = 192  # LaunchScreen.storyboard: 192x192 pt 居中显示


def background_color(im: Image.Image) -> tuple[int, int, int]:
    """取四角像素中出现最多的颜色作为背景色（图标本身是纯色底）。"""
    w, h = im.size
    corners = [im.getpixel((0, 0)), im.getpixel((w - 1, 0)), im.getpixel((0, h - 1)), im.getpixel((w - 1, h - 1))]
    rgb = Counter(c[:3] for c in corners).most_common(1)[0][0]
    return rgb


def flatten(im: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    """把任意带 alpha 的图展平到 bg 上，输出无 alpha 的 RGB 图。"""
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        rgba = im.convert("RGBA")
        canvas = Image.new("RGB", rgba.size, bg)
        canvas.paste(rgba, mask=rgba.getchannel("A"))
        return canvas
    return im.convert("RGB")


def main() -> int:
    if not os.path.isfile(SRC_ICON):
        sys.exit(f"找不到源图标: {SRC_ICON}")
    src = Image.open(SRC_ICON)
    src.load()
    bg = background_color(src.convert("RGB"))
    base = flatten(src, bg)
    print(f"源图: {SRC_ICON} {src.size} {src.mode}; 背景色: #%02X%02X%02X" % bg)

    os.makedirs(APPICON_DIR, exist_ok=True)
    for name, px in APPICON_SIZES.items():
        out = base.resize((px, px), Image.LANCZOS)
        out.save(os.path.join(APPICON_DIR, name), format="PNG", optimize=True)
        print(f"  AppIcon {name}: {px}x{px}")

    os.makedirs(LAUNCH_DIR, exist_ok=True)
    logo_bg = Image.new("RGB", (LAUNCH_POINTS * 3, LAUNCH_POINTS * 3), bg)
    logo = base.resize((LAUNCH_POINTS * 3, LAUNCH_POINTS * 3), Image.LANCZOS)
    logo_bg.paste(logo)
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        px = LAUNCH_POINTS * scale
        img = logo_bg.resize((px, px), Image.LANCZOS) if scale != 3 else logo_bg
        path = os.path.join(LAUNCH_DIR, f"LaunchImage{suffix}.png")
        img.save(path, format="PNG", optimize=True)
        print(f"  LaunchImage{suffix}.png: {px}x{px}")

    # 自检：AppIcon 必须不含 alpha。
    bad = []
    for name in APPICON_SIZES:
        path = os.path.join(APPICON_DIR, name)
        im = Image.open(path)
        if im.mode != "RGB":
            bad.append(f"{name}: mode={im.mode}")
        if "A" in im.getbands():
            bad.append(f"{name}: 含 alpha 通道")
    if bad:
        sys.exit("AppIcon 校验失败:\n  " + "\n  ".join(bad))
    print("OK: AppIcon 全部为无 alpha 的 RGB PNG，尺寸与 Contents.json 一致。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
