#!/usr/bin/env python3
"""Manim 闭环渲染与关键帧网格审查图（Contact Sheet）生成工具。

用法：
  # 默认 CPU 渲染
  python tools/manim/render_check.py tools/manim/scenes/lunar_eclipse_scene.py LunarEclipseScene -q m

  # 开启 GPU 硬件编码与并发流水线加速 (NVIDIA NVENC + CUDA 抽帧)
  python tools/manim/render_check.py tools/manim/scenes/lunar_eclipse_scene.py UrumqiNearestPartialScene -q m --gpu

  # 开启 OpenGL GPU 着色器光栅化渲染器 (实验性)
  python tools/manim/render_check.py tools/manim/scenes/lunar_eclipse_scene.py UrumqiNearestPartialScene -q m --gpu --renderer opengl
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent.parent
MANIM_DIR = ROOT / "tools" / "manim"
VENV_PYTHON = (
    MANIM_DIR / ".venv" / "Scripts" / "python.exe"
    if os.name == "nt"
    else MANIM_DIR / ".venv" / "bin" / "python"
)
MEDIA_DIR = MANIM_DIR / "media"


def detect_gpu_encoder(python_exe: str) -> str | None:
    """探测当前环境 PyAV 可用的硬件 H.264 编码器（优先 h264_nvenc / h264_qsv / h264_amf）。"""
    probe_code = (
        "import av\n"
        "for enc in ('h264_nvenc', 'h264_qsv', 'h264_amf'):\n"
        "    try:\n"
        "        av.CodecContext.create(enc, 'w')\n"
        "        print(enc)\n"
        "        break\n"
        "    except Exception:\n"
        "        pass\n"
    )
    try:
        out = subprocess.check_output(
            [python_exe, "-c", probe_code],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return out.splitlines()[-1] if out else None
    except Exception:
        return None


def get_video_duration(video_path: Path) -> float:
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(video_path),
    ]
    out = subprocess.check_output(cmd, text=True).strip()
    return float(out)


def build_contact_sheet(
    video_path: Path,
    out_png: Path,
    cols: int = 3,
    rows: int = 2,
    use_gpu: bool = False,
) -> Path:
    duration = get_video_duration(video_path)
    total = cols * rows
    # 取 8% 到 96% 之间的代表性时刻，覆盖开场、初亏、食甚、复圆与定格画面
    fractions = [0.08 + (0.88 * i / max(1, total - 1)) for i in range(total)]
    tmp_dir = out_png.parent / "_frames_tmp"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    frames: list[tuple[float, Image.Image]] = []
    for idx, frac in enumerate(fractions):
        ts = duration * frac
        frame_file = tmp_dir / f"frame_{idx:02d}.png"
        ffmpeg_cmd = ["ffmpeg", "-y"]
        if use_gpu:
            ffmpeg_cmd.extend(["-hwaccel", "auto"])
        ffmpeg_cmd.extend(
            [
                "-ss",
                f"{ts:.3f}",
                "-i",
                str(video_path),
                "-frames:v",
                "1",
                "-q:v",
                "2",
                str(frame_file),
            ]
        )
        subprocess.run(
            ffmpeg_cmd,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        img = Image.open(frame_file).convert("RGB")
        frames.append((ts, img))

    # 根据首帧长宽比自适应单帧缩略图比例（横屏 16:9 或 竖屏 9:16）
    first_w, first_h = frames[0][1].size
    if first_h > first_w:  # 9:16 竖屏模式
        tile_w, tile_h = 270, 480
    else:  # 16:9 横屏模式
        tile_w, tile_h = 640, 360
    bar_h = 28
    pad = 10
    sheet_w = cols * tile_w + (cols + 1) * pad
    sheet_h = rows * (tile_h + bar_h) + (rows + 1) * pad
    sheet = Image.new("RGB", (sheet_w, sheet_h), (15, 20, 30))
    draw = ImageDraw.Draw(sheet)

    try:
        font = ImageFont.truetype("consola.ttf", 16)
    except OSError:
        font = ImageFont.load_default()

    for idx, (ts, img) in enumerate(frames):
        r, c = divmod(idx, cols)
        x0 = pad + c * (tile_w + pad)
        y0 = pad + r * (tile_h + bar_h + pad)
        # 顶部信息条（不遮挡 16:9 画面内容）
        draw.rectangle(
            [x0, y0, x0 + tile_w - 1, y0 + bar_h],
            fill=(24, 32, 48),
            outline=(56, 76, 108),
            width=1,
        )
        label = (
            f"Frame #{idx + 1}   t = {ts:.2f}s / {duration:.1f}s   "
            f"({int(round(fractions[idx] * 100))}%)"
        )
        draw.text((x0 + 10, y0 + 6), label, fill=(226, 230, 238), font=font)

        thumb = img.resize((tile_w, tile_h), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (x0, y0 + bar_h))
        draw.rectangle(
            [x0, y0 + bar_h, x0 + tile_w - 1, y0 + bar_h + tile_h - 1],
            outline=(56, 76, 108),
            width=1,
        )

    sheet.save(out_png)
    for f in tmp_dir.glob("*.png"):
        f.unlink(missing_ok=True)
    tmp_dir.rmdir()
    return out_png


def main() -> None:
    parser = argparse.ArgumentParser(
        description="渲染 Manim 场景并生成 AI 视觉自检拼图（支持可选 GPU 加速）"
    )
    parser.add_argument("script", type=Path, help="Manim 场景脚本路径")
    parser.add_argument("scene", type=str, help="Scene 类名")
    parser.add_argument(
        "-q",
        "--quality",
        choices=["l", "m", "h", "k"],
        default="m",
        help="渲染清晰度：l(480p15), m(720p30), h(1080p60), k(2160p60)",
    )
    parser.add_argument(
        "--aspect",
        choices=["16:9", "9:16"],
        default="16:9",
        help="视频宽高比模式：16:9 (默认横屏大屏模式) 或 9:16 (移动端竖屏短视频 HD 模式)",
    )
    parser.add_argument(
        "--portrait",
        action="store_true",
        help="快捷开关：等同于 --aspect 9:16 (移动端竖屏短视频 HD 模式)",
    )
    parser.add_argument(
        "--gpu",
        action="store_true",
        help="开启 GPU 硬件视频编码 (h264_nvenc/qsv/amf) 与多编码器并发加速",
    )
    parser.add_argument(
        "--renderer",
        choices=["cairo", "opengl"],
        default="cairo",
        help="选择光栅化渲染后端：cairo (默认 CPU 矢量高兼容) 或 opengl (ModernGL GPU 着色器)",
    )
    parser.add_argument(
        "--disable-caching",
        action="store_true",
        help="禁用 Manim 分段动画缓存，强制完整重渲染",
    )
    args = parser.parse_args()

    is_portrait = args.portrait or args.aspect == "9:16" or "Portrait" in args.scene

    python_exe = str(VENV_PYTHON) if VENV_PYTHON.exists() else sys.executable
    script_path = args.script.resolve()

    cmd = [
        python_exe,
        "-m",
        "manim",
        "render",
    ]
    if not is_portrait:
        cmd.append(f"-q{args.quality}")
    else:
        portrait_res_fps = {
            "l": ("480,854", "15"),
            "m": ("720,1280", "30"),
            "h": ("1080,1920", "60"),
            "k": ("2160,3840", "60"),
        }
        res_str, fps_str = portrait_res_fps[args.quality]
        cmd.extend(["-r", res_str, "--fps", fps_str])

    cmd.extend(
        [
            "--renderer",
            args.renderer,
            "--media_dir",
            str(MEDIA_DIR),
        ]
    )
    if args.renderer == "opengl":
        cmd.append("--write_to_movie")
    if args.disable_caching:
        cmd.append("--disable_caching")

    if args.gpu:
        hw_enc = detect_gpu_encoder(python_exe)
        if hw_enc:
            print(f"[GPU] 启用硬件视频编码器: {hw_enc} (并发编码队列=4)")
            cmd.extend(
                [
                    "--video-codec",
                    hw_enc,
                    "--max-inflight-encoders",
                    "4",
                ]
            )
        else:
            print("[GPU] 未探测到可用 NVENC/QSV/AMF 硬件编码器，仅开启多编码器并发")
            cmd.extend(["--max-inflight-encoders", "4"])

    cmd.extend([str(script_path), args.scene])

    env = os.environ.copy()
    env["PYTHONPATH"] = str(MANIM_DIR) + os.pathsep + env.get("PYTHONPATH", "")
    if is_portrait:
        env["GUANXIANG_ASPECT"] = "9:16"
    print("running:", " ".join(cmd))
    t0 = time.perf_counter()
    subprocess.run(cmd, check=True, cwd=str(ROOT), env=env)
    elapsed = time.perf_counter() - t0

    qual_dir = {
        "l": "480p15",
        "m": "720p30",
        "h": "1080p60",
        "k": "2160p60",
    }[args.quality]
    portrait_qual_dir = {
        "l": "854p15",
        "m": "1280p30",
        "h": "1920p60",
        "k": "3840p60",
    }[args.quality]

    candidate_paths = [
        MEDIA_DIR / "videos" / script_path.stem / portrait_qual_dir / f"{args.scene}.mp4"
        if is_portrait
        else None,
        MEDIA_DIR / "videos" / script_path.stem / qual_dir / f"{args.scene}.mp4",
    ]
    video_path = next((p for p in candidate_paths if p and p.exists()), None)
    if not video_path:
        # 兜底：搜索最近修改的对应视频
        found = sorted(
            (MEDIA_DIR / "videos" / script_path.stem).glob(f"**/{args.scene}.mp4"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        if found:
            video_path = found[0]
        else:
            raise FileNotFoundError(f"找不到输出视频：{args.scene}.mp4")

    sheet_path = video_path.with_name(f"{args.scene}_contact_sheet.png")
    build_contact_sheet(video_path, sheet_path, use_gpu=args.gpu)
    print(f"RENDER_TIME_S={elapsed:.2f}")
    print(f"VIDEO_PATH={video_path}")
    print(f"CONTACT_SHEET={sheet_path}")


if __name__ == "__main__":
    main()
