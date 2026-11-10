#!/usr/bin/env python3
"""批量重新渲染日食 compact 模式下的 1080p60 视频与关键帧拼图。"""

import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PYTHON = sys.executable
RENDER_CHECK = ROOT / "tools" / "manim" / "render_check.py"
SCENE_SCRIPT = ROOT / "tools" / "manim" / "scenes" / "solar_eclipse_scene.py"
BRAIN_DIR = Path(r"C:\Users\xulin\.gemini\antigravity\brain\950317cb-1315-4282-b004-13d9c2a23a77")

TASKS = [
    # (scene_name, is_portrait, target_mp4_name, target_png_name)
    (
        "BeijingTotalSolarScene",
        True,
        "BeijingTotalSolarPortrait_1080p.mp4",
        "BeijingTotalSolarPortrait_contact_sheet.png",
    ),
    (
        "ChinaAnnularSolarScene",
        True,
        "ChinaAnnularSolarPortrait_1080p.mp4",
        "ChinaAnnularSolarPortrait_contact_sheet.png",
    ),
    (
        "UrumqiNearestSolarScene",
        True,
        "UrumqiNearestSolarPortrait_1080p.mp4",
        "UrumqiNearestSolarPortrait_contact_sheet.png",
    ),
    (
        "BeijingTotalSolarScene",
        False,
        "BeijingTotalSolarScene.mp4",
        "BeijingTotalSolarScene_contact_sheet.png",
    ),
    (
        "ChinaAnnularSolarScene",
        False,
        "ChinaAnnularSolarScene.mp4",
        "ChinaAnnularSolarScene_contact_sheet.png",
    ),
    (
        "UrumqiNearestSolarScene",
        False,
        "UrumqiNearestSolarScene.mp4",
        "UrumqiNearestSolarScene_contact_sheet.png",
    ),
]


def main() -> None:
    total = len(TASKS)
    print(f"=== 开始批量渲染 {total} 个日食 compact 场景 (1080p60 NVENC GPU) ===")
    start_all = time.perf_counter()

    for idx, (scene, is_portrait, mp4_name, png_name) in enumerate(TASKS, 1):
        mode_str = "9:16 竖屏" if is_portrait else "16:9 横屏"
        print(f"\n[{idx}/{total}] 正在渲染: {scene} ({mode_str})...")
        t0 = time.perf_counter()
        cmd = [
            PYTHON,
            str(RENDER_CHECK),
            str(SCENE_SCRIPT),
            scene,
            "-q",
            "h",
            "--gpu",
        ]
        if is_portrait:
            cmd.append("--portrait")

        subprocess.run(cmd, check=True, cwd=str(ROOT))
        dur = time.perf_counter() - t0
        print(f"[{idx}/{total}] {scene} ({mode_str}) 渲染完成，耗时 {dur:.1f}s")

        # 定位输出文件并同步到 brain artifacts 目录
        media_sub = "1920p60" if is_portrait else "1080p60"
        src_mp4 = (
            ROOT
            / "tools"
            / "manim"
            / "media"
            / "videos"
            / "solar_eclipse_scene"
            / media_sub
            / f"{scene}.mp4"
        )
        src_png = (
            ROOT
            / "tools"
            / "manim"
            / "media"
            / "videos"
            / "solar_eclipse_scene"
            / media_sub
            / f"{scene}_contact_sheet.png"
        )

        if BRAIN_DIR.exists():
            dst_mp4 = BRAIN_DIR / mp4_name
            dst_png = BRAIN_DIR / png_name
            shutil.copy2(src_mp4, dst_mp4)
            shutil.copy2(src_png, dst_png)
            print(f"    -> 已同步至: {dst_mp4.name} & {dst_png.name}")

    total_dur = time.perf_counter() - start_all
    print(f"\n=== 全部 {total} 个日食 compact 场景重渲染完成！总耗时: {total_dur:.1f}s ===")


if __name__ == "__main__":
    main()
