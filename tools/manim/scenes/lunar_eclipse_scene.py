"""月食（全食 / 偏食 / 半影月食）通用双视窗天文科普演示动画。

数据底座：guanxiang-core (JPL DE440s + IAU 2006/2000A + Danjon 大气折射模型)
内置场景类：
  - LunarEclipseScene            : 2025-09-07 北京月全食 (本影食分 1.362)
  - UrumqiNearestPenumbralScene  : 2027-02-20 乌鲁木齐半影月食 (未来最近月食，半影食分 0.927，带食月落)
  - UrumqiNearestPartialScene    : 2028-07-06 乌鲁木齐月偏食 (未来最近本影月食，本影食分 0.389，全程可见)
  - UrumqiNearestTotalScene      : 2028-12-31 乌鲁木齐跨年月全食 (未来最近月全食，本影食分 1.246，仰角 63°)
"""

from __future__ import annotations

import datetime as dt
import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from manim import (
    DOWN,
    LEFT,
    ORIGIN,
    RIGHT,
    UP,
    Circle,
    DashedLine,
    DashedVMobject,
    Dot,
    FadeIn,
    Line,
    Polygon,
    Rectangle,
    RoundedRectangle,
    Scene,
    Text,
    ValueTracker,
    VGroup,
    VMobject,
    always_redraw,
    config,
    linear,
)
from manim.utils.color import ManimColor

MANIM_DIR = Path(__file__).resolve().parent.parent
ROOT = MANIM_DIR.parent.parent
if str(MANIM_DIR) not in sys.path:
    sys.path.insert(0, str(MANIM_DIR))

from common.theme import (  # noqa: E402
    ACCENT_BLUE,
    ACCENT_GOLD,
    ACCENT_RED,
    ACCENT_TEAL,
    BG_DEEP_SPACE,
    FONT_MONO,
    FONT_SANS,
    MOON_BLOOD,
    MOON_BRIGHT,
    OUTLINE_COLOR,
    PENUMBRA_FILL,
    PENUMBRA_STROKE,
    SURFACE_CARD,
    TEXT_MUTED,
    TEXT_PRIMARY,
    UMBRA_FILL,
    UMBRA_STROKE,
)


def utc_to_cst_dt(utc_str: str) -> dt.datetime:
    return dt.datetime.strptime(utc_str, "%Y-%m-%d %H:%M:%S") + dt.timedelta(hours=8)


def utc_to_cst_hm(utc_str: str) -> str:
    return utc_to_cst_dt(utc_str).strftime("%H:%M")


def circle_intersection_region(
    c1: np.ndarray,
    r1: float,
    c2: np.ndarray,
    r2: float,
    *,
    fill_color: str | ManimColor,
    fill_opacity: float,
    stroke_color: str | ManimColor = "#000000",
    stroke_width: float = 0.0,
    n_arc: int = 48,
) -> VMobject:
    """解析计算两圆交集区域（零布尔运算开销，支持部分相交与完全包含）。"""
    dx = float(c2[0] - c1[0])
    dy = float(c2[1] - c1[1])
    d = math.hypot(dx, dy)

    if d >= r1 + r2 - 1e-5:
        mob = Circle(radius=1e-4).move_to(c1)
        mob.set_fill(fill_color, opacity=0.0)
        mob.set_stroke(stroke_color, width=0.0)
        return mob
    if d + r1 <= r2 + 1e-5:
        mob = Circle(radius=r1).move_to(c1)
        mob.set_fill(fill_color, opacity=fill_opacity)
        mob.set_stroke(stroke_color, width=stroke_width)
        return mob
    if d + r2 <= r1 + 1e-5:
        mob = Circle(radius=r2).move_to(c2)
        mob.set_fill(fill_color, opacity=fill_opacity)
        mob.set_stroke(stroke_color, width=stroke_width)
        return mob

    phi = math.atan2(dy, dx)
    cos_a1 = max(-1.0, min(1.0, (d * d + r1 * r1 - r2 * r2) / (2.0 * d * r1)))
    cos_a2 = max(-1.0, min(1.0, (d * d + r2 * r2 - r1 * r1) / (2.0 * d * r2)))
    a1 = math.acos(cos_a1)
    a2 = math.acos(cos_a2)

    t1 = np.linspace(phi - a1, phi + a1, n_arc, endpoint=False)
    t2 = np.linspace(phi + math.pi - a2, phi + math.pi + a2, n_arc, endpoint=False)

    pts1 = np.column_stack(
        [c1[0] + r1 * np.cos(t1), c1[1] + r1 * np.sin(t1), np.zeros_like(t1)]
    )
    pts2 = np.column_stack(
        [c2[0] + r2 * np.cos(t2), c2[1] + r2 * np.sin(t2), np.zeros_like(t2)]
    )
    pts = np.vstack([pts1, pts2])
    poly = Polygon(*pts)
    poly.set_fill(fill_color, opacity=fill_opacity)
    poly.set_stroke(stroke_color, width=stroke_width)
    return poly


class MonospaceGlyphPool:
    """预渲染等宽 ASCII 字形池，消除 always_redraw 逐帧调用 Pango/SVG 磁盘读写的 CPU 开销。"""

    def __init__(self, font: str = FONT_MONO, font_size: int = 13) -> None:
        self._glyphs: dict[str, VMobject] = {}
        # 以数字 '0' 的包围盒宽度与基线中心作为等宽网格基准
        ref = Text("0", font=font, font_size=font_size, color=TEXT_PRIMARY)
        self.advance_w = float(ref.width) * 1.08
        self.ref_h = float(ref.height)

        charset = "0123456789+-.:degUTC"
        for ch in charset:
            g = Text(ch, font=font, font_size=font_size, color=TEXT_PRIMARY)
            g.move_to(ORIGIN)
            self._glyphs[ch] = g

    def render_line(
        self,
        text: str,
        anchor_left: np.ndarray,
        color: str | ManimColor,
        fixed_len: int = 14,
    ) -> VGroup:
        group = VGroup()
        padded = text.ljust(fixed_len)[:fixed_len]
        for idx, ch in enumerate(padded):
            x_pos = float(anchor_left[0]) + (idx + 0.5) * self.advance_w
            y_pos = float(anchor_left[1])
            proto = self._glyphs.get(ch)
            if ch == " " or proto is None:
                # 占位点以保持每帧带点子对象数量恒定，确保 Manim 动画家族列表不发生突变
                dummy = Circle(radius=1e-4).move_to(np.array([x_pos, y_pos, 0.0]))
                dummy.set_fill(opacity=0.0).set_stroke(width=0.0)
                group.add(dummy)
                continue
            g = proto.copy()
            g.set_color(color)
            if ch == ".":
                y_pos -= self.ref_h * 0.30
            g.move_to(np.array([x_pos, y_pos, 0.0]))
            group.add(g)
        return group


class LunarEclipseBaseScene(Scene):
    """自适应全食、偏食、半影月食与任意观测站点的通用月食演示基类。"""

    eclipse_date: str = "2025-09-07"
    observer_coords: str = "39.9,116.4"
    observer_label: str = "北京观测视算 (39.9°N, 116.4°E)"
    city_short: str = "北京"
    json_filename: str = "lunar_2025_09_07.json"

    def ensure_scene_data(self) -> dict:
        data_path = MANIM_DIR / "data" / self.json_filename
        if not data_path.exists():
            data_path.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [
                    "cargo",
                    "run",
                    "-q",
                    "-p",
                    "guanxiang-cli",
                    "--",
                    "scene",
                    "lunar-eclipse",
                    "--date",
                    self.eclipse_date,
                    "--at",
                    self.observer_coords,
                    "--step-s",
                    "60",
                    "--out",
                    str(data_path),
                ],
                check=True,
                cwd=str(ROOT),
            )
        return json.loads(data_path.read_text(encoding="utf-8"))

    def construct(self) -> None:
        config.background_color = BG_DEEP_SPACE
        data = self.ensure_scene_data()

        radii = data["radii_deg"]
        r_pen_deg = float(radii["penumbra"])
        r_umb_deg = float(radii["umbra"])
        r_moon_deg = float(radii["moon"])
        gamma = float(data["gamma"])
        kind = str(data["kind"])  # "total" | "partial" | "penumbral"
        kind_zh = str(data["kind_zh"])

        contacts_list = data["contacts"]
        contacts = {c["code"]: c for c in contacts_list}
        path_pts = data["path"]

        t_arr = np.array([p["t_rel_s"] for p in path_pts], dtype=float)
        x_arr = np.array([p["x_deg"] for p in path_pts], dtype=float)
        y_arr = np.array([p["y_deg"] for p in path_pts], dtype=float)
        u_mag_arr = np.array([p["umbral_mag"] for p in path_pts], dtype=float)
        p_mag_arr = np.array([p["penumbral_mag"] for p in path_pts], dtype=float)
        alt_arr = np.array([p["altitude_deg"] for p in path_pts], dtype=float)

        greatest_utc_dt = dt.datetime.strptime(
            data["greatest_utc"], "%Y-%m-%d %H:%M:%S"
        )
        greatest_cst_dt = greatest_utc_dt + dt.timedelta(hours=8)
        cst_date_str = greatest_cst_dt.strftime("%Y-%m-%d")

        def interp_state(t_rel: float) -> dict[str, float | str]:
            x_deg = float(np.interp(t_rel, t_arr, x_arr))
            y_deg = float(np.interp(t_rel, t_arr, y_arr))
            u_mag = float(np.interp(t_rel, t_arr, u_mag_arr))
            p_mag = float(np.interp(t_rel, t_arr, p_mag_arr))
            alt_deg = float(np.interp(t_rel, t_arr, alt_arr))
            cur_utc = greatest_utc_dt + dt.timedelta(seconds=float(t_rel))
            cur_cst = cur_utc + dt.timedelta(hours=8)

            p1_t = contacts["P1"]["t_rel_s"]
            p4_t = contacts["P4"]["t_rel_s"]
            u1_t = contacts["U1"]["t_rel_s"] if "U1" in contacts else None
            u2_t = contacts["U2"]["t_rel_s"] if "U2" in contacts else None
            u3_t = contacts["U3"]["t_rel_s"] if "U3" in contacts else None
            u4_t = contacts["U4"]["t_rel_s"] if "U4" in contacts else None

            if t_rel < p1_t:
                stage = "食前 · 接近半影"
            elif t_rel > p4_t:
                stage = "食终 · 离开地影"
            elif (
                kind == "total"
                and u1_t is not None
                and u2_t is not None
                and u3_t is not None
                and u4_t is not None
            ):
                if t_rel < u1_t:
                    stage = "半影食始 (P1-U1)"
                elif t_rel < u2_t:
                    stage = "初亏偏食 (U1-U2)"
                elif t_rel <= u3_t:
                    stage = "全食红月亮 (U2-U3)"
                elif t_rel <= u4_t:
                    stage = "生光复圆 (U3-U4)"
                else:
                    stage = "半影食终 (U4-P4)"
            elif kind == "partial" and u1_t is not None and u4_t is not None:
                if t_rel < u1_t:
                    stage = "半影食始 (P1-U1)"
                elif t_rel <= 0.0:
                    stage = "初亏至食甚 (U1-G)"
                elif t_rel <= u4_t:
                    stage = "食甚至复圆 (G-U4)"
                else:
                    stage = "半影食终 (U4-P4)"
            else:
                if t_rel <= 0.0:
                    stage = "半影食始至食甚 (P1-G)"
                else:
                    stage = "食甚至半影食终 (G-P4)"

            if alt_deg < 0.0:
                stage = f"{stage} [已月落]"

            return {
                "x_deg": x_deg,
                "y_deg": y_deg,
                "u_mag": u_mag,
                "p_mag": p_mag,
                "alt_deg": alt_deg,
                "utc_str": cur_utc.strftime("%H:%M:%S UTC"),
                "cst_str": cur_cst.strftime("%m-%d %H:%M:%S"),
                "stage": stage,
            }

        # =====================================================================
        # 1. 顶部标题栏 (Header Bar)
        # =====================================================================
        header_bg = RoundedRectangle(
            width=13.6,
            height=0.76,
            corner_radius=0.12,
            fill_color=SURFACE_CARD,
            fill_opacity=0.95,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.5,
        ).move_to(np.array([0.0, 3.46, 0.0]))

        title_text = Text(
            f"{cst_date_str} {kind_zh} · {self.observer_label}",
            font=FONT_SANS,
            font_size=20,
            color=TEXT_PRIMARY,
            weight="BOLD",
        ).move_to(header_bg.get_left() + RIGHT * 0.28, aligned_edge=LEFT)

        saros = data["saros"]
        if kind == "penumbral":
            mag_summary = f"半影食分 {data['penumbral_magnitude']:.3f}"
        else:
            mag_summary = f"本影食分 {data['umbral_magnitude']:.3f}"

        subtitle_text = Text(
            f"{mag_summary}  ·  "
            f"沙罗序列 {saros['series']} ({saros['member']}/{saros['count']})  ·  "
            "DE440s 星历",
            font=FONT_SANS,
            font_size=14,
            color=TEXT_MUTED,
        ).move_to(header_bg.get_right() + LEFT * 0.28, aligned_edge=RIGHT)

        header_group = VGroup(header_bg, title_text, subtitle_text)

        # =====================================================================
        # 2. 左侧主视窗：地影切平面天球视图 (Earth Shadow Tangent Plane)
        # =====================================================================
        left_panel_center = np.array([-2.95, -0.44, 0.0])
        left_panel = RoundedRectangle(
            width=7.70,
            height=6.72,
            corner_radius=0.14,
            fill_color=SURFACE_CARD,
            fill_opacity=0.88,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.5,
        ).move_to(left_panel_center)

        left_panel_title = Text(
            "地影切平面轨迹视图 (北上 · 东左)",
            font=FONT_SANS,
            font_size=15,
            color=ACCENT_BLUE,
            weight="BOLD",
        ).move_to(left_panel.get_top() + DOWN * 0.28 + LEFT * 2.15)

        shadow_origin = np.array([-2.85, -0.55, 0.0])
        deg_scale = 1.50

        def sky_to_point(x_deg: float, y_deg: float) -> np.ndarray:
            return shadow_origin + np.array(
                [-x_deg * deg_scale, y_deg * deg_scale, 0.0]
            )

        axis_h = DashedLine(
            shadow_origin + LEFT * 3.35,
            shadow_origin + RIGHT * 3.15,
            dash_length=0.08,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.2,
        )
        axis_v = DashedLine(
            shadow_origin + DOWN * 2.65,
            shadow_origin + UP * 2.65,
            dash_length=0.08,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.2,
        )
        dir_labels = VGroup(
            Text("东 E", font=FONT_SANS, font_size=12, color=TEXT_MUTED).next_to(
                axis_h.get_left(), UP, buff=0.06
            ),
            Text("西 W", font=FONT_SANS, font_size=12, color=TEXT_MUTED).next_to(
                axis_h.get_right(), UP, buff=0.06
            ),
            Text("北 N", font=FONT_SANS, font_size=12, color=TEXT_MUTED).next_to(
                axis_v.get_top(), RIGHT, buff=0.08
            ),
            Text("南 S", font=FONT_SANS, font_size=12, color=TEXT_MUTED).next_to(
                axis_v.get_bottom(), RIGHT, buff=0.08
            ),
        )

        penumbra_circle = Circle(
            radius=r_pen_deg * deg_scale,
            fill_color=PENUMBRA_FILL,
            fill_opacity=0.55,
            stroke_width=0.0,
        ).move_to(shadow_origin)
        penumbra_border = DashedVMobject(
            Circle(
                radius=r_pen_deg * deg_scale,
                stroke_color=PENUMBRA_STROKE,
                stroke_width=1.8,
            ).move_to(shadow_origin),
            num_dashes=48,
        )
        pen_tag_dir = DOWN if gamma > 0.15 else UP
        penumbra_tag = Text(
            f"地球半影 (R={r_pen_deg:.2f}°)",
            font=FONT_SANS,
            font_size=11,
            color=PENUMBRA_STROKE,
        ).move_to(
            shadow_origin + pen_tag_dir * (r_pen_deg * deg_scale + 0.18) + LEFT * 1.15
        )

        umbra_circle = Circle(
            radius=r_umb_deg * deg_scale,
            fill_color=UMBRA_FILL,
            fill_opacity=0.88,
            stroke_color=UMBRA_STROKE,
            stroke_width=2.2,
        ).move_to(shadow_origin)
        umb_tag_dir = DOWN if gamma > 0.0 else UP
        umbra_tag = Text(
            f"地球本影 (R={r_umb_deg:.2f}°)",
            font=FONT_SANS,
            font_size=11,
            color=UMBRA_STROKE,
        ).move_to(shadow_origin + umb_tag_dir * (r_umb_deg * deg_scale - 0.24))

        track_points = [sky_to_point(p["x_deg"], p["y_deg"]) for p in path_pts[::3]]
        moon_track_line = VMobject(
            stroke_color=ACCENT_BLUE, stroke_width=2.0, stroke_opacity=0.65
        )
        moon_track_line.set_points_smoothly(track_points)

        out_v = UP if gamma >= 0.0 else DOWN
        in_v = DOWN if gamma >= 0.0 else UP
        label_offsets = {
            "P1": out_v * 0.38 + RIGHT * 0.10,
            "U1": out_v * 0.38 + RIGHT * 0.05,
            "U2": out_v * 0.42 + RIGHT * 0.04,
            "G": in_v * 0.38,
            "U3": out_v * 0.42 + LEFT * 0.06,
            "U4": in_v * 0.38 + LEFT * 0.05,
            "P4": out_v * 0.38 + LEFT * 0.10,
        }
        contact_colors = {
            "P1": TEXT_MUTED,
            "U1": ACCENT_BLUE,
            "U2": ACCENT_RED,
            "G": ACCENT_GOLD,
            "U3": ACCENT_RED,
            "U4": ACCENT_BLUE,
            "P4": TEXT_MUTED,
        }

        contact_markers = VGroup()
        for c in contacts_list:
            code = c["code"]
            pt = sky_to_point(c["x_deg"], c["y_deg"])
            col = contact_colors.get(code, TEXT_PRIMARY)
            dot = Dot(point=pt, radius=0.055 if code == "G" else 0.042, color=col)
            cst_hm = utc_to_cst_hm(c["utc"])
            short_zh = c["label_zh"].replace("半影", "")
            lbl = VGroup(
                Text(
                    f"{short_zh}({code})",
                    font=FONT_SANS,
                    font_size=10,
                    color=col,
                    weight="BOLD",
                ),
                Text(cst_hm, font=FONT_MONO, font_size=9, color=TEXT_PRIMARY),
            ).arrange(DOWN, buff=0.03)
            offset_vec = label_offsets.get(code, UP * 0.36)
            lbl.move_to(pt + offset_vec)
            tick = Line(
                pt,
                lbl.get_center()
                + (UP * 0.12 if offset_vec[1] < 0 else DOWN * 0.12),
                stroke_color=col,
                stroke_width=1.0,
                stroke_opacity=0.6,
            )
            marker_item = VGroup(tick, dot, lbl)
            contact_markers.add(marker_item)

        left_static_group = VGroup(
            left_panel,
            left_panel_title,
            penumbra_circle,
            penumbra_border,
            umbra_circle,
            axis_h,
            axis_v,
            dir_labels,
            penumbra_tag,
            umbra_tag,
            moon_track_line,
        )

        # =====================================================================
        # 3. 右上视窗：月面特写与本影/半影掩食模拟 + 静态中文遥测标签栏
        # =====================================================================
        right_top_center = np.array([3.95, 1.32, 0.0])
        right_top_panel = RoundedRectangle(
            width=5.65,
            height=3.15,
            corner_radius=0.14,
            fill_color=SURFACE_CARD,
            fill_opacity=0.88,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.5,
        ).move_to(right_top_center)

        right_top_title = Text(
            "月面特写与本影/半影掩食模拟",
            font=FONT_SANS,
            font_size=15,
            color=ACCENT_RED,
            weight="BOLD",
        ).move_to(right_top_panel.get_top() + DOWN * 0.26 + LEFT * 1.35)

        zoom_moon_center = np.array([2.35, 1.16, 0.0])
        zoom_moon_radius = 0.90
        zoom_scale = zoom_moon_radius / r_moon_deg

        hud_label_x = 3.55
        hud_value_x = 4.62
        hud_row_ys = [1.62, 1.24, 0.86, 0.48, 0.10]
        mag_label_zh = "半影食分" if kind == "penumbral" else "本影食分"
        hud_static_labels = VGroup()
        for row_y, zh_label in zip(
            hud_row_ys,
            ["北京时间", "世界时", mag_label_zh, f"{self.city_short}仰角", "影心角距"],
            strict=True,
        ):
            lbl = Text(
                zh_label,
                font=FONT_SANS,
                font_size=13,
                color=TEXT_MUTED,
            )
            lbl.move_to(np.array([hud_label_x, row_y, 0.0]), aligned_edge=LEFT)
            hud_static_labels.add(lbl)

        # 预构建等宽数字字形池与阶段标题缓存（零磁盘 I/O）
        glyph_pool = MonospaceGlyphPool(font=FONT_MONO, font_size=13)
        stage_text_cache: dict[tuple[str, str], Text] = {}

        def get_cached_stage_text(stage_str: str, color_hex: str) -> VMobject:
            key = (stage_str, color_hex)
            if key not in stage_text_cache:
                t_mob = Text(
                    stage_str,
                    font=FONT_SANS,
                    font_size=14,
                    color=color_hex,
                    weight="BOLD",
                )
                t_mob.move_to(np.array([hud_label_x, 2.02, 0.0]), aligned_edge=LEFT)
                stage_text_cache[key] = t_mob
            return stage_text_cache[key].copy()

        # =====================================================================
        # 4. 右下视窗：食分与观测地平高度角时序曲线
        # =====================================================================
        right_bot_center = np.array([3.95, -2.12, 0.0])
        right_bot_panel = RoundedRectangle(
            width=5.65,
            height=3.35,
            corner_radius=0.14,
            fill_color=SURFACE_CARD,
            fill_opacity=0.88,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.5,
        ).move_to(right_bot_center)

        right_bot_title = Text(
            f"食分与{self.city_short}地平高度角演化",
            font=FONT_SANS,
            font_size=15,
            color=ACCENT_GOLD,
            weight="BOLD",
        ).move_to(right_bot_panel.get_top() + DOWN * 0.26 + LEFT * 1.45)

        chart_left = 1.68
        chart_right = 6.32
        chart_bottom = -3.32
        chart_top = -1.08
        t_min = float(max(t_arr[0], contacts["P1"]["t_rel_s"] - 900.0))
        t_max = float(min(t_arr[-1], contacts["P4"]["t_rel_s"] + 900.0))
        mag_min, mag_max = -1.55, 1.55
        alt_min_bound = (
            min(-5.0, float(np.min(alt_arr)) - 2.0) if np.min(alt_arr) < 0 else 0.0
        )
        alt_max_bound = max(
            45.0, float(math.ceil(np.max(alt_arr) / 10.0) * 10.0 + 5.0)
        )

        def chart_mag_pt(t_s: float, mag: float) -> np.ndarray:
            tx = np.clip((t_s - t_min) / (t_max - t_min), 0.0, 1.0)
            my = np.clip((mag - mag_min) / (mag_max - mag_min), 0.0, 1.0)
            return np.array(
                [
                    chart_left + tx * (chart_right - chart_left),
                    chart_bottom + my * (chart_top - chart_bottom),
                    0.0,
                ]
            )

        def chart_alt_pt(t_s: float, alt_deg: float) -> np.ndarray:
            tx = np.clip((t_s - t_min) / (t_max - t_min), 0.0, 1.0)
            ay = np.clip(
                (alt_deg - alt_min_bound) / (alt_max_bound - alt_min_bound), 0.0, 1.0
            )
            return np.array(
                [
                    chart_left + tx * (chart_right - chart_left),
                    chart_bottom + ay * (chart_top - chart_bottom),
                    0.0,
                ]
            )

        chart_box = Rectangle(
            width=chart_right - chart_left,
            height=chart_top - chart_bottom,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.2,
            fill_color=BG_DEEP_SPACE,
            fill_opacity=0.55,
        ).move_to(
            np.array(
                [
                    0.5 * (chart_left + chart_right),
                    0.5 * (chart_bottom + chart_top),
                    0.0,
                ]
            )
        )

        zero_mag_y = chart_mag_pt(0.0, 0.0)[1]
        unit_mag_y = chart_mag_pt(0.0, 1.0)[1]
        zero_line = DashedLine(
            np.array([chart_left, zero_mag_y, 0.0]),
            np.array([chart_right, zero_mag_y, 0.0]),
            dash_length=0.06,
            stroke_color=ACCENT_BLUE,
            stroke_width=1.1,
            stroke_opacity=0.7,
        )
        unit_line = DashedLine(
            np.array([chart_left, unit_mag_y, 0.0]),
            np.array([chart_right, unit_mag_y, 0.0]),
            dash_length=0.06,
            stroke_color=ACCENT_RED,
            stroke_width=1.1,
            stroke_opacity=0.8,
        )
        top_alt_label = f"{int(round(np.max(alt_arr)))}°"
        bot_alt_label = f"{int(round(np.min(alt_arr)))}°"
        y_axis_labels = VGroup(
            Text("1.0 全食", font=FONT_SANS, font_size=9, color=ACCENT_RED).next_to(
                unit_line.get_left(), LEFT, buff=0.06
            ),
            Text("0.0 本影", font=FONT_SANS, font_size=9, color=ACCENT_BLUE).next_to(
                zero_line.get_left(), LEFT, buff=0.06
            ),
            Text(
                top_alt_label, font=FONT_MONO, font_size=9, color=ACCENT_TEAL
            ).move_to(np.array([chart_right + 0.20, chart_top - 0.15, 0.0])),
            Text(
                bot_alt_label, font=FONT_MONO, font_size=9, color=ACCENT_TEAL
            ).move_to(np.array([chart_right + 0.20, chart_bottom + 0.25, 0.0])),
        )

        chart_v_ticks = VGroup()
        for c in contacts_list:
            code = c["code"]
            ct = c["t_rel_s"]
            cx = chart_mag_pt(ct, 0.0)[0]
            col = contact_colors.get(code, TEXT_PRIMARY)
            vline = Line(
                np.array([cx, chart_bottom, 0.0]),
                np.array([cx, chart_top, 0.0]),
                stroke_color=col,
                stroke_width=1.0,
                stroke_opacity=0.45,
            )
            clbl = Text(code, font=FONT_MONO, font_size=9, color=col).move_to(
                np.array([cx, chart_bottom - 0.16, 0.0])
            )
            chart_v_ticks.add(VGroup(vline, clbl))

        mag_curve_pts = [
            chart_mag_pt(
                p["t_rel_s"],
                p["penumbral_mag"] if kind == "penumbral" else p["umbral_mag"],
            )
            for p in path_pts
            if t_min <= p["t_rel_s"] <= t_max
        ]
        mag_curve = VMobject(stroke_color=ACCENT_RED, stroke_width=2.4)
        mag_curve.set_points_smoothly(mag_curve_pts)

        alt_curve_pts = [
            chart_alt_pt(p["t_rel_s"], p["altitude_deg"])
            for p in path_pts
            if t_min <= p["t_rel_s"] <= t_max
        ]
        alt_curve = VMobject(
            stroke_color=ACCENT_TEAL, stroke_width=2.0, stroke_opacity=0.85
        )
        alt_curve.set_points_smoothly(alt_curve_pts)

        legend_group = VGroup(
            Line(ORIGIN, RIGHT * 0.28, stroke_color=ACCENT_RED, stroke_width=2.6),
            Text(mag_label_zh, font=FONT_SANS, font_size=10, color=TEXT_PRIMARY),
            Line(ORIGIN, RIGHT * 0.28, stroke_color=ACCENT_TEAL, stroke_width=2.2),
            Text(
                f"{self.city_short}仰角",
                font=FONT_SANS,
                font_size=10,
                color=TEXT_PRIMARY,
            ),
        ).arrange(RIGHT, buff=0.10)
        legend_group.move_to(right_bot_panel.get_top() + DOWN * 0.26 + RIGHT * 1.55)

        right_static_group = VGroup(
            right_top_panel,
            right_top_title,
            hud_static_labels,
            right_bot_panel,
            right_bot_title,
            chart_box,
            zero_line,
            unit_line,
            y_axis_labels,
            chart_v_ticks,
            alt_curve,
            mag_curve,
            legend_group,
        )

        # =====================================================================
        # 5. 时间驱动器 (ValueTracker) 与零 I/O 动态重绘组件
        # =====================================================================
        t_tracker = ValueTracker(t_min)

        def build_dynamic_overlay() -> VGroup:
            t_cur = float(t_tracker.get_value())
            st = interp_state(t_cur)
            x_deg = float(st["x_deg"])
            y_deg = float(st["y_deg"])
            u_mag = float(st["u_mag"])
            p_mag = float(st["p_mag"])
            alt_deg = float(st["alt_deg"])
            disp_mag = p_mag if kind == "penumbral" else u_mag

            moon_pt = sky_to_point(x_deg, y_deg)
            moon_r_plan = r_moon_deg * deg_scale
            plan_moon_disk = Circle(
                radius=moon_r_plan,
                fill_color=MOON_BRIGHT,
                fill_opacity=0.95 if alt_deg >= 0.0 else 0.40,
                stroke_color=TEXT_PRIMARY,
                stroke_width=1.4,
            ).move_to(moon_pt)

            plan_group = VGroup(plan_moon_disk)
            sep_deg = float(np.hypot(x_deg, y_deg))
            umb_clip = circle_intersection_region(
                moon_pt,
                moon_r_plan,
                shadow_origin,
                r_umb_deg * deg_scale,
                fill_color=MOON_BLOOD,
                fill_opacity=0.92 if alt_deg >= 0.0 else 0.45,
            )
            plan_group.add(umb_clip)

            plan_moon_ring = Circle(
                radius=moon_r_plan,
                fill_opacity=0.0,
                stroke_color=ACCENT_GOLD if u_mag >= 1.0 else TEXT_PRIMARY,
                stroke_width=1.8 if u_mag >= 1.0 else 1.2,
            ).move_to(moon_pt)
            plan_group.add(plan_moon_ring)

            zoom_disk = Circle(
                radius=zoom_moon_radius,
                fill_color=MOON_BRIGHT,
                fill_opacity=0.96 if alt_deg >= 0.0 else 0.45,
                stroke_width=0.0,
            ).move_to(zoom_moon_center)

            zoom_group = VGroup(zoom_disk)
            shadow_rel_vec = np.array([x_deg * zoom_scale, -y_deg * zoom_scale, 0.0])
            zoom_shadow_center = zoom_moon_center + shadow_rel_vec

            pen_inter = circle_intersection_region(
                zoom_moon_center,
                zoom_moon_radius,
                zoom_shadow_center,
                r_pen_deg * zoom_scale,
                fill_color="#141C2B",
                fill_opacity=0.52 if kind == "penumbral" else 0.40,
            )
            zoom_group.add(pen_inter)

            umb_inter = circle_intersection_region(
                zoom_moon_center,
                zoom_moon_radius,
                zoom_shadow_center,
                r_umb_deg * zoom_scale,
                fill_color=MOON_BLOOD,
                fill_opacity=0.88 if alt_deg >= 0.0 else 0.48,
                stroke_color=UMBRA_STROKE,
                stroke_width=1.2,
            )
            zoom_group.add(umb_inter)

            zoom_outline = Circle(
                radius=zoom_moon_radius,
                fill_opacity=0.0,
                stroke_color=ACCENT_RED
                if u_mag >= 1.0
                else (ACCENT_GOLD if u_mag > 0.0 else OUTLINE_COLOR),
                stroke_width=2.2,
            ).move_to(zoom_moon_center)
            zoom_group.add(zoom_outline)

            stage_color = (
                ACCENT_RED
                if u_mag >= 1.0
                else (ACCENT_GOLD if u_mag >= 0.0 else ACCENT_BLUE)
            )
            stage_txt = get_cached_stage_text(str(st["stage"]), stage_color)

            val_specs = [
                (hud_row_ys[0], str(st["cst_str"]), TEXT_PRIMARY),
                (hud_row_ys[1], str(st["utc_str"]), TEXT_MUTED),
                (
                    hud_row_ys[2],
                    f"{disp_mag:+.3f}",
                    ACCENT_RED if disp_mag > 0 else TEXT_PRIMARY,
                ),
                (
                    hud_row_ys[3],
                    f"{alt_deg:.1f} deg",
                    ACCENT_TEAL if alt_deg >= 0 else ACCENT_RED,
                ),
                (hud_row_ys[4], f"{sep_deg:.3f} deg", TEXT_MUTED),
            ]
            hud_vals = VGroup(stage_txt)
            for ry, v_str, v_col in val_specs:
                vt = glyph_pool.render_line(
                    v_str, np.array([hud_value_x, ry, 0.0]), v_col
                )
                hud_vals.add(vt)

            cur_mag_pt = chart_mag_pt(t_cur, disp_mag)
            cur_alt_pt = chart_alt_pt(t_cur, alt_deg)
            playhead_line = Line(
                np.array([cur_mag_pt[0], chart_bottom, 0.0]),
                np.array([cur_mag_pt[0], chart_top, 0.0]),
                stroke_color=ACCENT_GOLD,
                stroke_width=1.6,
            )
            mag_dot = Dot(point=cur_mag_pt, radius=0.055, color=ACCENT_RED)
            alt_dot = Dot(point=cur_alt_pt, radius=0.048, color=ACCENT_TEAL)

            return VGroup(
                plan_group,
                zoom_group,
                hud_vals,
                playhead_line,
                mag_dot,
                alt_dot,
            )

        dynamic_overlay = always_redraw(build_dynamic_overlay)

        # =====================================================================
        # 6. 动画编排 (Timeline Choreography) —— 按固定图层顺序添加，无需 z_index
        # =====================================================================
        self.add(
            header_group,
            left_static_group,
            right_static_group,
            dynamic_overlay,
            contact_markers,
        )
        self.wait(0.4)

        if "U2" in contacts:
            u2_t = float(contacts["U2"]["t_rel_s"])
            self.play(
                t_tracker.animate.set_value(u2_t),
                run_time=3.2,
                rate_func=linear,
            )
            self.play(
                t_tracker.animate.set_value(0.0),
                run_time=2.2,
                rate_func=linear,
            )
        else:
            self.play(
                t_tracker.animate.set_value(0.0),
                run_time=5.4,
                rate_func=linear,
            )

        greatest_cst_hms = greatest_cst_dt.strftime("%H:%M:%S")
        greatest_badge = RoundedRectangle(
            width=2.75,
            height=0.42,
            corner_radius=0.08,
            fill_color=UMBRA_FILL,
            fill_opacity=0.95,
            stroke_color=ACCENT_GOLD,
            stroke_width=1.6,
        ).move_to(left_panel.get_top() + DOWN * 0.28 + RIGHT * 2.20)
        badge_mag_val = (
            data["penumbral_magnitude"]
            if kind == "penumbral"
            else data["umbral_magnitude"]
        )
        greatest_badge_txt = Text(
            f"★ 食甚 {greatest_cst_hms} CST (食分 {badge_mag_val:.3f})",
            font=FONT_SANS,
            font_size=11,
            color=ACCENT_GOLD,
            weight="BOLD",
        ).move_to(greatest_badge.get_center())
        greatest_callout = VGroup(greatest_badge, greatest_badge_txt)

        self.play(FadeIn(greatest_callout, scale=0.92), run_time=0.4)
        self.wait(0.8)

        self.play(
            t_tracker.animate.set_value(t_max),
            run_time=4.2,
            rate_func=linear,
        )
        self.wait(0.8)


class LunarEclipseScene(LunarEclipseBaseScene):
    """2025-09-07 北京月全食（本影食分 1.362，沙罗 128）。"""

    eclipse_date = "2025-09-07"
    observer_coords = "39.9,116.4"
    observer_label = "北京观测视算 (39.9°N, 116.4°E)"
    city_short = "北京"
    json_filename = "lunar_2025_09_07.json"


class UrumqiNearestPenumbralScene(LunarEclipseBaseScene):
    """2027-02-20 乌鲁木齐半影月食（未来最近广义月食，半影食分 0.927，带食月落）。"""

    eclipse_date = "2027-02-20"
    observer_coords = "43.8256,87.6168"
    observer_label = "乌鲁木齐观测视算 (43.8°N, 87.6°E)"
    city_short = "乌市"
    json_filename = "urumqi_lunar_2027_02_20.json"


class UrumqiNearestPartialScene(LunarEclipseBaseScene):
    """2028-07-06 乌鲁木齐月偏食（未来最近本影月食，本影食分 0.389，全程可见）。"""

    eclipse_date = "2028-07-06"
    observer_coords = "43.8256,87.6168"
    observer_label = "乌鲁木齐观测视算 (43.8°N, 87.6°E)"
    city_short = "乌市"
    json_filename = "urumqi_lunar_2028_07_06.json"


class UrumqiNearestTotalScene(LunarEclipseBaseScene):
    """2028-12-31 乌鲁木齐跨年月全食（未来最近月全食，本影食分 1.246，食甚仰角 63°）。"""

    eclipse_date = "2028-12-31"
    observer_coords = "43.8256,87.6168"
    observer_label = "乌鲁木齐观测视算 (43.8°N, 87.6°E)"
    city_short = "乌市"
    json_filename = "urumqi_lunar_2028_12_31.json"
