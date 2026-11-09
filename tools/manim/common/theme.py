"""与观象 App (app/lib/src/theme.dart) 对齐的深空视觉色板与排版配置。"""

import platform

# 深空背景与卡片色板
BG_DEEP_SPACE = "#0B0E14"
SURFACE_CARD = "#131924"
SURFACE_HIGH = "#1B2332"
OUTLINE_COLOR = "#263246"

# 文字与强调色
TEXT_PRIMARY = "#E2E6EE"
TEXT_MUTED = "#8E9CAD"
ACCENT_BLUE = "#569AFF"
ACCENT_GOLD = "#FFAA00"
ACCENT_RED = "#E05A47"
ACCENT_TEAL = "#4DB6AC"

# 月食与地影专用色
PENUMBRA_FILL = "#1A2232"
PENUMBRA_STROKE = "#5C6F8C"
UMBRA_FILL = "#2C0E0A"
UMBRA_STROKE = "#D85A44"
MOON_BRIGHT = "#E5E9F0"
MOON_BLOOD = "#B83B24"

# 中英文字体选择（Windows 优先微软雅黑，Linux 优先 Noto Sans CJK SC）
if platform.system() == "Windows":
    FONT_SANS = "Microsoft YaHei"
    FONT_MONO = "Consolas"
else:
    FONT_SANS = "Noto Sans CJK SC"
    FONT_MONO = "DejaVu Sans Mono"
