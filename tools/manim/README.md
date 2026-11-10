# Manim 天文事件动画工作台 (`tools/manim/`)

本目录提供基于 **Rust 天文引擎 (`guanxiang-core`) + Manim Community** 的高精天文科普动画渲染与 AI 视觉自检闭环。

## 架构概览

1. **计算底座与数据导出 (`guanxiang-cli scene`)**：
   - 所有天体历表（DE440s）、真赤道坐标系（IAU 2006/2000A）、日月食接触时刻、贝塞尔根数、站心地平高度角均在 Rust 层完成计算，导出为结构化 JSON 时序文件（`tools/manim/data/*.json`）。
   - `crates/guanxiang-core` 保持纯 Rust 零外部编译依赖，Python / Manim 仅读取 JSON 进行声明式矢量动画编排。
2. **闭环渲染与视觉审查 (`tools/manim/render_check.py`)**：
   - 调用 `manim render` 渲染指定场景，并通过 `ffmpeg` + `Pillow` 自动抽取 6 个代表性时刻拼合成一张带时间戳角标的 `3×2` 网格审查图（`*_contact_sheet.png`），供智能体直接读取审查布局、文字防遮挡与色彩对比度。

## 目录结构

| 路径 | 说明 |
|---|---|
| `common/theme.py` | 与 Flutter 客户端 [`theme.dart`](../../app/lib/src/theme.dart) 对齐的深空色板与中英文字体配置 |
| `scenes/lunar_eclipse_scene.py` | 通用月食演示场景库（支持月全食、月偏食、半影月食，内置北京 2025 与乌鲁木齐 3 场最近月食） |
| `scenes/solar_eclipse_scene.py` | 通用日食演示场景库（贝塞尔基本面正射地球盘 + 天顶向上站心日面特写 + 时序曲线，支持日全食、日环食、日偏食） |
| `render_check.py` | 一键渲染 + 关键帧九宫/六宫格拼图（Contact Sheet）生成脚本 |
| `data/` | `guanxiang-cli scene` 导出的时序 JSON（已加入 `.gitignore`） |
| `media/` | Manim 输出视频与关键帧拼图（已加入 `.gitignore`） |

## 环境准备

需要本机已安装 Python 3.12+ 与 `ffmpeg`：

```powershell
# 在仓库根目录下创建独立虚拟环境并安装依赖
py -3.13 -m venv tools/manim/.venv
.\tools\manim\.venv\Scripts\pip.exe install manim Pillow
```

## 常用命令

### 1. 从 Rust 引擎导出场景时序数据

```powershell
# 月食切平面轨迹与食分时序（以 2025-09-07 北京月全食为例）
cargo run -q -p guanxiang-cli -- scene lunar-eclipse `
  --date 2025-09-07 --at 39.9,116.4 --step-s 60 `
  --out tools/manim/data/lunar_2025_09_07.json

# 日食站心相切圆与食分时序（以 2027-08-02 卢克索日全食为例）
cargo run -q -p guanxiang-cli -- scene solar-eclipse `
  --date 2027-08-02 --at 25.687,32.640 --step-s 60 `
  --out tools/manim/data/solar_2027_08_02.json

# 双天体视位置轨迹与角距演化（如金星合木星、行星顺逆行）
cargo run -q -p guanxiang-cli -- scene ephem-track `
  --body1 venus --body2 jupiter `
  --from 2025-08-01 --to 2025-08-25 --step-h 6 `
  --out tools/manim/data/venus_jupiter_2025.json
```

### 2. 运行闭环渲染并生成自检拼图

```powershell
# 快速迭代预览（-q l 480p15 或 -q m 720p30，加 --gpu 启用 NVENC/QSV/AMF 硬件视频编码与并发加速）
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/lunar_eclipse_scene.py LunarEclipseScene -q m --gpu

# 渲染乌鲁木齐未来最近月食场景（半影月食 / 月偏食 / 跨年月全食）
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/lunar_eclipse_scene.py UrumqiNearestPenumbralScene -q m --gpu
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/lunar_eclipse_scene.py UrumqiNearestPartialScene -q m --gpu
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/lunar_eclipse_scene.py UrumqiNearestTotalScene -q m --gpu

# 渲染日食演示场景（卢克索世纪日全食 / 北京日全食 / 同江日环食 / 乌鲁木齐日偏食）
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py SolarEclipseScene -q m --gpu
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py BeijingTotalSolarScene -q m --gpu
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py ChinaAnnularSolarScene -q m --gpu
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py UrumqiNearestSolarScene -q m --gpu

# 正式成片输出（-q h 1080p60 或 -q k 2160p60）
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py SolarEclipseScene -q h --gpu

# 9:16 移动端竖屏短视频 HD 模式（--portrait 或 --aspect 9:16，输出 1080×1920 60fps）
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py SolarEclipseScene -q h --portrait --gpu
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py BeijingTotalSolarScene -q h --portrait --gpu
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py ChinaAnnularSolarScene -q h --portrait --gpu
.\tools\manim\.venv\Scripts\python.exe tools/manim/render_check.py `
  tools/manim/scenes/solar_eclipse_scene.py UrumqiNearestSolarScene -q h --portrait --gpu

```

渲染完成后，终端会输出：
- `VIDEO_PATH`: 渲染生成的 `.mp4` 路径（位于 `tools/manim/media/videos/<脚本名>/<清晰度>/<场景名>.mp4`）
- `CONTACT_SHEET`: 6 帧关键时刻拼图路径（位于同目录下的 `<场景名>_contact_sheet.png`）
