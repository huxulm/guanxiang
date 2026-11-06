"""由官网图标（website/public/favicon.svg）的几何生成应用图标。

用法（需要 Pillow）：python tools/icons/gen_icons.py
改图标时先改 favicon.svg，再同步修改下面的 SHAPES，重新运行本脚本。

生成：
- Windows：app/windows/runner/resources/app_icon.ico（16–256 px）
- Android：mipmap-*/ic_launcher.png（旧版启动器，带圆角底）
           mipmap-*/ic_launcher_foreground.png + mipmap-anydpi-v26/ic_launcher.xml（自适应图标）
- Linux：app/linux/packaging/icons/hicolor/<尺寸>/apps/dev.huxulm.guanxiang.png 和 scalable 的 svg
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
APP_ID = "dev.huxulm.guanxiang"

# 与 favicon.svg 一致，单位是 64×64 的 viewBox
BACKGROUND = "#1f3a68"
CORNER = 14
SHAPES = [
    # (cx, cy, r, 颜色)
    (32, 32, 13, "#fcd34d"),  # 太阳
    (38, 29, 4.5, BACKGROUND),  # 日面上的黑点（凌日的行星或卫星）
    (14, 16, 1.6, "#ffffff"),
    (50, 13, 1.2, "#ffffff"),
    (52, 50, 1.6, "#ffffff"),
    (12, 48, 1.2, "#ffffff"),
]

SUPERSAMPLE = 8


def render(size: int, *, with_background: bool, content: float = 64, offset: float = 0) -> Image.Image:
    """画 size×size 的图标。content/offset 以 size 为 108 时的 dp 计（自适应图标用），默认铺满。"""
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    full = 64 if content == 64 else 108
    k = s / full
    if with_background:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=CORNER * k, fill=BACKGROUND)
    unit = (content / 64) * k
    for cx, cy, r, color in SHAPES:
        x, y = offset * k + cx * unit, offset * k + cy * unit
        d.ellipse([x - r * unit, y - r * unit, x + r * unit, y + r * unit], fill=color)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    # Windows
    ico = APP / "windows/runner/resources/app_icon.ico"
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    big = render(256, with_background=True)
    big.save(ico, sizes=[(n, n) for n in sizes], append_images=[render(n, with_background=True) for n in sizes])
    print("wrote", ico.relative_to(ROOT))

    # Android
    res = APP / "android/app/src/main/res"
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, scale in densities.items():
        d = res / f"mipmap-{name}"
        d.mkdir(exist_ok=True)
        render(round(48 * scale), with_background=True).save(d / "ic_launcher.png")
        # 自适应图标前景：108 dp 画布，内容缩放到中间 76 dp（安全区直径 66 dp；四角星点离中心最远约 32.3 dp，仍在圆内）
        render(round(108 * scale), with_background=False, content=76, offset=16).save(d / "ic_launcher_foreground.png")
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- 由 tools/icons/gen_icons.py 生成 -->\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    (res / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print("wrote Android mipmaps")

    # Linux：freedesktop hicolor 主题，图标名与应用 ID 相同（.deb 里装到 /usr/share/icons/hicolor）
    hicolor = APP / "linux/packaging/icons/hicolor"
    for n in [16, 24, 32, 48, 64, 128, 256, 512]:
        d = hicolor / f"{n}x{n}/apps"
        d.mkdir(parents=True, exist_ok=True)
        render(n, with_background=True).save(d / f"{APP_ID}.png")
    scalable = hicolor / "scalable/apps"
    scalable.mkdir(parents=True, exist_ok=True)
    (scalable / f"{APP_ID}.svg").write_bytes((ROOT / "website/public/favicon.svg").read_bytes())
    print("wrote Linux hicolor icons")


if __name__ == "__main__":
    main()
