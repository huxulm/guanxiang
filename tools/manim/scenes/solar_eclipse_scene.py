"""日食（全食 / 环食 / 偏食）通用三视窗天文科普演示动画。

数据底座：guanxiang-core (JPL DE440s + IAU 2006/2000A + 贝塞尔基本面与站心视差精算)
内置场景类：
  - SolarEclipseScene         : 2027-08-02 卢克索世纪日全食 (食分 1.079，全食 6m22s，沙罗 136)
  - BeijingTotalSolarScene    : 2035-09-02 北京日全食 (食分 1.026，全食 1m32s，沙罗 145)
  - ChinaAnnularSolarScene    : 2030-06-01 黑龙江同江日环食 (食分 0.940，环食 4m30s，金环日食)
  - UrumqiNearestSolarScene   : 2030-06-01 乌鲁木齐日偏食 (未来最近可见日食，食分 0.632，仰角 67°)
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
    n_arc: int = 56,
) -> VMobject:
    """解析计算两圆交集区域（零布尔运算开销，支持偏食透镜、全食覆盖与环食内含）。"""
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
        ref = Text("0", font=font, font_size=font_size, color=TEXT_PRIMARY)
        self.advance_w = float(ref.width) * 1.08
        self.ref_h = float(ref.height)

        charset = "0123456789+-.:%°UTC'"
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
                dummy = Circle(radius=1e-4).move_to(np.array([x_pos, y_pos, 0.0]))
                dummy.set_fill(opacity=0.0).set_stroke(width=0.0)
                group.add(dummy)
                continue
            g = proto.copy()
            g.set_color(color)
            if ch == ".":
                y_pos -= self.ref_h * 0.30
            elif ch in ("'", "°"):
                y_pos += self.ref_h * 0.26
            g.move_to(np.array([x_pos, y_pos, 0.0]))
            group.add(g)
        return group


class SolarEclipseBaseScene(Scene):
    """自适应日全食、日环食、日偏食与任意观测站点的通用日食演示基类。"""

    eclipse_date: str = "2027-08-02"
    observer_coords: str = "25.687,32.640"
    observer_label: str = "卢克索观测视算 (25.7°N, 32.6°E)"
    city_short: str = "卢克索"
    json_filename: str = "solar_2027_08_02.json"

    def ensure_scene_data(self) -> dict:
        data_path = MANIM_DIR / "data" / self.json_filename
        need_export = not data_path.exists()
        if not need_export:
            existing = json.loads(data_path.read_text(encoding="utf-8"))
            if "sub_solar_lon_deg" not in existing.get("diagram", {}):
                need_export = True
        if need_export:
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
                    "solar-eclipse",
                    "--date",
                    self.eclipse_date,
                    "--at",
                    self.observer_coords,
                    "--step-s",
                    "30",
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

        global_kind_zh = str(data["kind_zh"])
        saros = data["saros"]
        obs_info = data["observer"]
        obs_lat_deg = float(obs_info["lat_deg"])
        obs_lon_deg = float(obs_info["lon_deg"])
        obs_lat_rad = math.radians(obs_lat_deg)

        diag = data["diagram"]
        l1_earth = float(diag["l1"])
        l2_earth = float(diag["l2"])
        d_deg = float(diag["d_deg"])
        d_rad = math.radians(d_deg)
        sub_lon0_deg = float(diag["sub_solar_lon_deg"])
        bessel_track = diag["track"]

        b_t_arr = np.array([p["t_rel_s"] for p in bessel_track], dtype=float)
        b_x_arr = np.array([p["x"] for p in bessel_track], dtype=float)
        b_y_arr = np.array([p["y"] for p in bessel_track], dtype=float)

        local = data["local"]
        local_kind = str(local["kind"])  # "total" | "annular" | "partial"
        local_kind_zh = str(local["kind_zh"])
        local_mag = float(local["magnitude"])
        local_max_obsc = float(local["obscuration"])
        central_dur_s = local.get("central_duration_s")
        contacts_list = local["contacts"]
        contacts = {c["code"]: c for c in contacts_list}
        disk_frames = local["disk_frames"]

        f_t_arr = np.array([f["t_rel_s"] for f in disk_frames], dtype=float)
        f_x_arr = np.array([f["x_deg"] for f in disk_frames], dtype=float)
        f_y_arr = np.array([f["y_deg"] for f in disk_frames], dtype=float)
        f_sun_r_arr = np.array([f["sun_r_deg"] for f in disk_frames], dtype=float)
        f_moon_r_arr = np.array([f["moon_r_deg"] for f in disk_frames], dtype=float)
        f_obsc_arr = np.array([f["obscuration"] for f in disk_frames], dtype=float)
        f_alt_arr = np.array([f["sun_alt_deg"] for f in disk_frames], dtype=float)
        # 对天顶位置角做連続解缠（unwrap），防止跨 ±180° 线性插值跳变
        f_zen_rad_unwrapped = np.unwrap(
            np.radians([f["zenith_angle_deg"] for f in disk_frames])
        )

        greatest_utc_dt = dt.datetime.strptime(
            data["greatest_utc"], "%Y-%m-%d %H:%M:%S"
        )
        local_max_utc_dt = dt.datetime.strptime(
            local["maximum_utc"], "%Y-%m-%d %H:%M:%S"
        )
        local_max_cst_dt = local_max_utc_dt + dt.timedelta(hours=8)
        cst_date_str = local_max_cst_dt.strftime("%Y-%m-%d")

        c1_t = float(contacts["C1"]["t_rel_s"])
        c4_t = float(contacts["C4"]["t_rel_s"])
        max_t = float(contacts["MAX"]["t_rel_s"])
        c2_t = float(contacts["C2"]["t_rel_s"]) if "C2" in contacts else None
        c3_t = float(contacts["C3"]["t_rel_s"]) if "C3" in contacts else None

        def obs_bessel_xy(t_rel: float) -> tuple[float, float, float]:
            """计算测站在 t_rel 时刻投影在贝塞尔基本面上的坐标 (xi, eta, zeta)，单位：地球半径。"""
            sub_lon = sub_lon0_deg - t_rel * (360.0 / 86400.0)
            h_rad = math.radians(obs_lon_deg - sub_lon)
            xi = math.cos(obs_lat_rad) * math.sin(h_rad)
            eta = math.sin(obs_lat_rad) * math.cos(d_rad) - math.cos(
                obs_lat_rad
            ) * math.sin(d_rad) * math.cos(h_rad)
            zeta = math.sin(obs_lat_rad) * math.sin(d_rad) + math.cos(
                obs_lat_rad
            ) * math.cos(d_rad) * math.cos(h_rad)
            return xi, eta, zeta

        def sky_to_zenith_up(
            x_deg: float, y_deg: float, q_rad: float
        ) -> tuple[float, float]:
            """将真赤道切平面偏移 (x向东, y向北) 旋转至天顶朝上坐标系 (+X向右, +Y向天顶)。"""
            cq = math.cos(q_rad)
            sq = math.sin(q_rad)
            sx = -x_deg * cq + y_deg * sq
            sy = x_deg * sq + y_deg * cq
            return sx, sy

        def interp_state(t_rel: float) -> dict[str, float | str]:
            bx = float(np.interp(t_rel, b_t_arr, b_x_arr))
            by = float(np.interp(t_rel, b_t_arr, b_y_arr))
            x_deg = float(np.interp(t_rel, f_t_arr, f_x_arr))
            y_deg = float(np.interp(t_rel, f_t_arr, f_y_arr))
            sun_r = float(np.interp(t_rel, f_t_arr, f_sun_r_arr))
            moon_r = float(np.interp(t_rel, f_t_arr, f_moon_r_arr))
            obsc = float(np.clip(np.interp(t_rel, f_t_arr, f_obsc_arr), 0.0, 1.0))
            alt_deg = float(np.interp(t_rel, f_t_arr, f_alt_arr))
            q_rad = float(np.interp(t_rel, f_t_arr, f_zen_rad_unwrapped))

            cur_utc = greatest_utc_dt + dt.timedelta(seconds=float(t_rel))
            cur_cst = cur_utc + dt.timedelta(hours=8)

            if t_rel < c1_t:
                stage = "食前 · 月影接近"
            elif t_rel > c4_t:
                stage = "复圆 · 离开月影"
            elif (
                local_kind == "total"
                and c2_t is not None
                and c3_t is not None
            ):
                if t_rel < c2_t:
                    stage = "初亏偏食 (C1-C2)"
                elif t_rel <= c3_t:
                    stage = "全食日冕 (C2-C3)"
                else:
                    stage = "生光复圆 (C3-C4)"
            elif (
                local_kind == "annular"
                and c2_t is not None
                and c3_t is not None
            ):
                if t_rel < c2_t:
                    stage = "初亏偏食 (C1-C2)"
                elif t_rel <= c3_t:
                    stage = "环食金环 (C2-C3)"
                else:
                    stage = "生光复圆 (C3-C4)"
            else:
                if t_rel <= max_t:
                    stage = "初亏至食甚 (C1-MAX)"
                else:
                    stage = "食甚至复圆 (MAX-C4)"

            if alt_deg < 0.0:
                stage = f"{stage} [日面地平线下]"

            return {
                "bx": bx,
                "by": by,
                "x_deg": x_deg,
                "y_deg": y_deg,
                "sun_r": sun_r,
                "moon_r": moon_r,
                "obsc": obsc,
                "alt_deg": alt_deg,
                "q_rad": q_rad,
                "utc_str": cur_utc.strftime("%H:%M:%S UTC"),
                "cst_str": cur_cst.strftime("%m-%d %H:%M:%S"),
                "stage": stage,
            }

        # =====================================================================
        # 1. 顶部科研遥测标题栏 (Header Bar - 直角边框)
        # =====================================================================
        header_bg = Rectangle(
            width=13.60,
            height=0.72,
            fill_color=SURFACE_CARD,
            fill_opacity=0.96,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.4,
        ).move_to(np.array([0.0, 3.48, 0.0]))

        title_text = Text(
            f"{cst_date_str} {global_kind_zh} · {self.observer_label}",
            font=FONT_SANS,
            font_size=17,
            color=TEXT_PRIMARY,
            weight="BOLD",
        )
        title_text.move_to(
            np.array([header_bg.get_left()[0] + 0.24, header_bg.get_center()[1], 0.0]),
            aligned_edge=LEFT,
        )

        dur_part = ""
        if central_dur_s is not None and central_dur_s > 0:
            dm = int(central_dur_s) // 60
            ds = int(round(central_dur_s)) % 60
            dur_part = f" · 持续 {dm}m{ds:02d}s"

        subtitle_text = Text(
            f"本地{local_kind_zh} · 食分 {local_mag:.3f} · 遮掩 {local_max_obsc * 100:.1f}%{dur_part} · "
            f"沙罗 {saros['series']} ({saros['member']}/{saros['count']})",
            font=FONT_SANS,
            font_size=12,
            color=TEXT_MUTED,
        )
        subtitle_text.move_to(
            np.array([header_bg.get_right()[0] - 0.24, header_bg.get_center()[1], 0.0]),
            aligned_edge=RIGHT,
        )

        header_group = VGroup(header_bg, title_text, subtitle_text)

        # =====================================================================
        # 2. 左侧主视窗：贝塞尔基本面与地影扫掠视图 (向阳半球 · 北上东右)
        # =====================================================================
        left_panel_center = np.array([-2.95, -0.42, 0.0])
        left_panel = Rectangle(
            width=7.70,
            height=6.76,
            fill_color=SURFACE_CARD,
            fill_opacity=0.90,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.4,
        ).move_to(left_panel_center)

        left_header_y = left_panel.get_top()[1] - 0.26
        left_divider_y = left_panel.get_top()[1] - 0.52
        left_header_line = Line(
            np.array([left_panel.get_left()[0], left_divider_y, 0.0]),
            np.array([left_panel.get_right()[0], left_divider_y, 0.0]),
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.0,
            stroke_opacity=0.75,
        )

        left_panel_title = Text(
            "贝塞尔基本面正射投影 (向阳半球 · 北上东右)",
            font=FONT_SANS,
            font_size=13,
            color=ACCENT_BLUE,
            weight="BOLD",
        )
        left_panel_title.move_to(
            np.array([left_panel.get_left()[0] + 0.22, left_header_y, 0.0]),
            aligned_edge=LEFT,
        )

        # 图例说明（左上视窗顶栏右对齐）
        bessel_legend = VGroup(
            Dot(radius=0.042, color=ACCENT_GOLD),
            Text(
                f"月影轴 (γ={data['gamma']:+.3f})",
                font=FONT_SANS,
                font_size=10,
                color=TEXT_MUTED,
            ),
            Dot(radius=0.042, color=ACCENT_TEAL),
            Text(
                f"{self.city_short}测站轨迹",
                font=FONT_SANS,
                font_size=10,
                color=TEXT_MUTED,
            ),
        ).arrange(RIGHT, buff=0.08)
        bessel_legend.move_to(
            np.array([left_panel.get_right()[0] - 0.22, left_header_y, 0.0]),
            aligned_edge=RIGHT,
        )

        plane_origin = np.array([-2.95, -0.68, 0.0])
        earth_r_scale = 1.80  # 1 地球赤道半径对应的屏幕单位

        def bessel_to_point(x_er: float, y_er: float) -> np.ndarray:
            return plane_origin + np.array(
                [x_er * earth_r_scale, y_er * earth_r_scale, 0.0]
            )

        # 地球向阳半球圆盘与经纬网格
        earth_disk = Circle(
            radius=earth_r_scale,
            fill_color="#101B2E",
            fill_opacity=0.92,
            stroke_color=ACCENT_BLUE,
            stroke_width=1.8,
        ).move_to(plane_origin)

        graticule_group = VGroup()
        # 纬线圈 (-60°, -30°, 0°赤道, +30°, +60°) 在地球自转中保持静止
        for lat_d in [-60, -30, 0, 30, 60]:
            phi_r = math.radians(lat_d)
            hs = np.linspace(-math.pi, math.pi, 121)
            vis_pts = []
            for h_r in hs:
                zeta = math.sin(phi_r) * math.sin(d_rad) + math.cos(
                    phi_r
                ) * math.cos(d_rad) * math.cos(h_r)
                if zeta >= 0.0:
                    xi = math.cos(phi_r) * math.sin(h_r)
                    eta = math.sin(phi_r) * math.cos(d_rad) - math.cos(
                        phi_r
                    ) * math.sin(d_rad) * math.cos(h_r)
                    vis_pts.append(bessel_to_point(xi, eta))
            if len(vis_pts) >= 3:
                lat_curve = VMobject(
                    stroke_color=ACCENT_BLUE if lat_d == 0 else OUTLINE_COLOR,
                    stroke_width=1.4 if lat_d == 0 else 0.9,
                    stroke_opacity=0.65 if lat_d == 0 else 0.45,
                )
                lat_curve.set_points_as_corners(vis_pts)
                graticule_group.add(lat_curve)

        # 经线圈 (-60°, -30°, 0°中央子午线, +30°, +60°)
        for h_deg in [-60, -30, 0, 30, 60]:
            h_r = math.radians(h_deg)
            phis = np.linspace(-math.pi / 2, math.pi / 2, 91)
            vis_pts = []
            for phi_r in phis:
                zeta = math.sin(phi_r) * math.sin(d_rad) + math.cos(
                    phi_r
                ) * math.cos(d_rad) * math.cos(h_r)
                if zeta >= 0.0:
                    xi = math.cos(phi_r) * math.sin(h_r)
                    eta = math.sin(phi_r) * math.cos(d_rad) - math.cos(
                        phi_r
                    ) * math.sin(d_rad) * math.cos(h_r)
                    vis_pts.append(bessel_to_point(xi, eta))
            if len(vis_pts) >= 3:
                lon_curve = VMobject(
                    stroke_color=OUTLINE_COLOR,
                    stroke_width=0.9,
                    stroke_opacity=0.40,
                )
                lon_curve.set_points_as_corners(vis_pts)
                graticule_group.add(lon_curve)

        # 地球自转轴与可见极点
        pole_sign = 1.0 if d_rad >= 0.0 else -1.0
        pole_pt = bessel_to_point(0.0, pole_sign * math.cos(d_rad))
        pole_axis = Line(
            plane_origin,
            pole_pt,
            stroke_color=ACCENT_BLUE,
            stroke_width=1.2,
            stroke_opacity=0.6,
        )
        pole_dot = Dot(point=pole_pt, radius=0.042, color=ACCENT_BLUE)
        pole_lbl = Text(
            "北极" if pole_sign > 0 else "南极",
            font=FONT_SANS,
            font_size=9,
            color=ACCENT_BLUE,
        ).next_to(pole_pt, RIGHT, buff=0.08)
        graticule_group.add(pole_axis, pole_dot, pole_lbl)

        # 方向标签（从太阳方向看地球：北上、南下、西左、东右）
        dir_labels = VGroup(
            Text("西 W", font=FONT_SANS, font_size=11, color=TEXT_MUTED).move_to(
                plane_origin + LEFT * (earth_r_scale + 0.36)
            ),
            Text("东 E", font=FONT_SANS, font_size=11, color=TEXT_MUTED).move_to(
                plane_origin + RIGHT * (earth_r_scale + 0.36)
            ),
            Text("北 N", font=FONT_SANS, font_size=11, color=TEXT_MUTED).move_to(
                plane_origin + UP * (earth_r_scale + 0.24)
            ),
            Text("南 S", font=FONT_SANS, font_size=11, color=TEXT_MUTED).move_to(
                plane_origin + DOWN * (earth_r_scale + 0.24)
            ),
        )

        # 测站随地球自转在 C1..C4 期间划过的轨迹弧线
        obs_arc_ts = np.linspace(c1_t - 600.0, c4_t + 600.0, 60)
        obs_arc_pts = [
            bessel_to_point(*obs_bessel_xy(float(t))[:2]) for t in obs_arc_ts
        ]
        obs_rot_path = DashedVMobject(
            VMobject(stroke_color=ACCENT_TEAL, stroke_width=1.8).set_points_as_corners(
                obs_arc_pts
            ),
            num_dashes=24,
        )

        # 月影中心轴轨迹线（严格裁剪在基本面视场内）
        shadow_track_pts = [
            bessel_to_point(p["x"], p["y"])
            for p in bessel_track
            if abs(p["x"]) <= 1.65 and abs(p["y"]) <= 1.28
        ]
        shadow_track_line = VMobject(
            stroke_color=ACCENT_GOLD, stroke_width=2.0, stroke_opacity=0.80
        )
        shadow_track_line.set_points_as_corners(shadow_track_pts)

        # 全球食甚点标记
        gx = float(diag["greatest"]["x"])
        gy = float(diag["greatest"]["y"])
        g_pt = bessel_to_point(gx, gy)
        g_dot = Dot(point=g_pt, radius=0.050, color=ACCENT_GOLD)

        # 左下角科研坐标标尺说明
        coord_note = Text(
            f"坐标系: 贝塞尔基本面 (ξ, η) · 单位: 地球赤道半径 R⊕ · 太阳赤纬 d={math.degrees(d_rad):+.2f}°",
            font=FONT_SANS,
            font_size=9,
            color=TEXT_MUTED,
        )
        coord_note.move_to(
            np.array(
                [left_panel.get_left()[0] + 0.22, left_panel.get_bottom()[1] + 0.20, 0.0]
            ),
            aligned_edge=LEFT,
        )

        left_static_group = VGroup(
            left_panel,
            left_header_line,
            left_panel_title,
            bessel_legend,
            earth_disk,
            graticule_group,
            dir_labels,
            obs_rot_path,
            shadow_track_line,
            g_dot,
            coord_note,
        )

        # =====================================================================
        # 3. 右上视窗：站心日面特写与月影遮掩模拟 (天顶向上) + 遥测 HUD
        # =====================================================================
        right_top_center = np.array([3.95, 1.33, 0.0])
        right_top_panel = Rectangle(
            width=5.65,
            height=3.18,
            fill_color=SURFACE_CARD,
            fill_opacity=0.90,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.4,
        ).move_to(right_top_center)

        rt_header_y = right_top_panel.get_top()[1] - 0.24
        rt_divider_y = right_top_panel.get_top()[1] - 0.48
        right_top_header_line = Line(
            np.array([right_top_panel.get_left()[0], rt_divider_y, 0.0]),
            np.array([right_top_panel.get_right()[0], rt_divider_y, 0.0]),
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.0,
            stroke_opacity=0.75,
        )

        right_top_title = Text(
            f"{self.city_short}站心日面遮掩特写 (天顶向上 ↑)",
            font=FONT_SANS,
            font_size=13,
            color=ACCENT_GOLD,
            weight="BOLD",
        )
        right_top_title.move_to(
            np.array([right_top_panel.get_left()[0] + 0.22, rt_header_y, 0.0]),
            aligned_edge=LEFT,
        )

        zoom_sun_center = np.array([2.28, 1.00, 0.0])
        zoom_fov_radius = 0.98
        zoom_sun_radius = 0.50
        mean_sun_r_deg = float(np.mean(f_sun_r_arr))
        zoom_deg_scale = zoom_sun_radius / mean_sun_r_deg

        fov_bg = Circle(
            radius=zoom_fov_radius,
            fill_color="#0D1522",
            fill_opacity=0.95,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.3,
        ).move_to(zoom_sun_center)

        zenith_lbl = Text(
            "↑天顶", font=FONT_SANS, font_size=9, color=TEXT_MUTED
        ).move_to(zoom_sun_center + UP * (zoom_fov_radius - 0.13))

        obs_tag_proto = Text(
            self.city_short,
            font=FONT_SANS,
            font_size=10,
            color=ACCENT_TEAL,
            weight="BOLD",
        )

        hud_label_x = 3.52
        hud_value_x = 4.60
        hud_row_ys = [1.56, 1.20, 0.84, 0.48, 0.12]
        hud_static_labels = VGroup()
        for row_y, zh_label in zip(
            hud_row_ys,
            ["北京时间", "世界时", "遮掩面积", f"{self.city_short}仰角", "日月角距"],
            strict=True,
        ):
            lbl = Text(
                zh_label,
                font=FONT_SANS,
                font_size=12,
                color=TEXT_MUTED,
            )
            lbl.move_to(np.array([hud_label_x, row_y, 0.0]), aligned_edge=LEFT)
            hud_static_labels.add(lbl)

        glyph_pool = MonospaceGlyphPool(font=FONT_MONO, font_size=12)
        stage_text_cache: dict[tuple[str, str], Text] = {}

        def get_cached_stage_text(stage_str: str, color_hex: str) -> VMobject:
            key = (stage_str, color_hex)
            if key not in stage_text_cache:
                t_mob = Text(
                    stage_str,
                    font=FONT_SANS,
                    font_size=13,
                    color=color_hex,
                    weight="BOLD",
                )
                t_mob.move_to(np.array([hud_label_x, 1.94, 0.0]), aligned_edge=LEFT)
                stage_text_cache[key] = t_mob
            return stage_text_cache[key].copy()

        # =====================================================================
        # 4. 右下视窗：日面遮掩面积与太阳仰角时序曲线
        # =====================================================================
        right_bot_center = np.array([3.95, -2.12, 0.0])
        right_bot_panel = Rectangle(
            width=5.65,
            height=3.36,
            fill_color=SURFACE_CARD,
            fill_opacity=0.90,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.4,
        ).move_to(right_bot_center)

        rb_header_y = right_bot_panel.get_top()[1] - 0.24
        rb_divider_y = right_bot_panel.get_top()[1] - 0.48
        right_bot_header_line = Line(
            np.array([right_bot_panel.get_left()[0], rb_divider_y, 0.0]),
            np.array([right_bot_panel.get_right()[0], rb_divider_y, 0.0]),
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.0,
            stroke_opacity=0.75,
        )

        right_bot_title = Text(
            f"日面遮掩率与{self.city_short}太阳仰角演化",
            font=FONT_SANS,
            font_size=13,
            color=ACCENT_RED,
            weight="BOLD",
        )
        right_bot_title.move_to(
            np.array([right_bot_panel.get_left()[0] + 0.22, rb_header_y, 0.0]),
            aligned_edge=LEFT,
        )

        chart_left = 1.72
        chart_right = 6.22
        chart_bottom = -3.34
        chart_top = -1.16
        t_min = float(f_t_arr[0])
        t_max = float(f_t_arr[-1])
        alt_min_bound = (
            min(-5.0, float(np.min(f_alt_arr)) - 2.0)
            if np.min(f_alt_arr) < 0
            else 0.0
        )
        alt_max_bound = max(
            45.0, float(math.ceil(np.max(f_alt_arr) / 10.0) * 10.0 + 5.0)
        )

        def chart_obsc_pt(t_s: float, obsc_frac: float) -> np.ndarray:
            tx = np.clip((t_s - t_min) / (t_max - t_min), 0.0, 1.0)
            oy = np.clip(obsc_frac / 1.08, 0.0, 1.0)
            return np.array(
                [
                    chart_left + tx * (chart_right - chart_left),
                    chart_bottom + oy * (chart_top - chart_bottom),
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

        full_obsc_y = chart_obsc_pt(0.0, 1.0)[1]
        half_obsc_y = chart_obsc_pt(0.0, 0.5)[1]
        full_line = DashedLine(
            np.array([chart_left, full_obsc_y, 0.0]),
            np.array([chart_right, full_obsc_y, 0.0]),
            dash_length=0.06,
            stroke_color=ACCENT_RED,
            stroke_width=1.1,
            stroke_opacity=0.75,
        )
        half_line = DashedLine(
            np.array([chart_left, half_obsc_y, 0.0]),
            np.array([chart_right, half_obsc_y, 0.0]),
            dash_length=0.06,
            stroke_color=ACCENT_BLUE,
            stroke_width=1.0,
            stroke_opacity=0.55,
        )

        top_alt_label = f"{int(round(np.max(f_alt_arr)))}°"
        bot_alt_label = f"{int(round(np.min(f_alt_arr)))}°"
        y_axis_labels = VGroup(
            Text("100%", font=FONT_MONO, font_size=9, color=ACCENT_RED).next_to(
                full_line.get_left(), LEFT, buff=0.08
            ),
            Text("50%", font=FONT_MONO, font_size=9, color=ACCENT_BLUE).next_to(
                half_line.get_left(), LEFT, buff=0.08
            ),
            Text(
                top_alt_label, font=FONT_MONO, font_size=9, color=ACCENT_TEAL
            ).next_to(np.array([chart_right, chart_top - 0.14, 0.0]), RIGHT, buff=0.08),
            Text(
                bot_alt_label, font=FONT_MONO, font_size=9, color=ACCENT_TEAL
            ).next_to(
                np.array([chart_right, chart_bottom + 0.16, 0.0]), RIGHT, buff=0.08
            ),
        )

        contact_colors = {
            "C1": ACCENT_BLUE,
            "C2": ACCENT_RED,
            "MAX": ACCENT_GOLD,
            "C3": ACCENT_RED,
            "C4": ACCENT_BLUE,
        }
        chart_v_ticks = VGroup()
        for c in contacts_list:
            code = c["code"]
            ct = float(c["t_rel_s"])
            cx = chart_obsc_pt(ct, 0.0)[0]
            col = contact_colors.get(code, TEXT_PRIMARY)
            vline = Line(
                np.array([cx, chart_bottom, 0.0]),
                np.array([cx, chart_top, 0.0]),
                stroke_color=col,
                stroke_width=1.0,
                stroke_opacity=0.45,
            )
            # C2/MAX/C3 时刻非常接近（仅差 1~3 分钟），底部标签只标 C1、MAX、C4 避免重叠
            if code in ("C1", "MAX", "C4"):
                clbl = Text(code, font=FONT_MONO, font_size=9, color=col).next_to(
                    np.array([cx, chart_bottom, 0.0]), DOWN, buff=0.08
                )
                chart_v_ticks.add(VGroup(vline, clbl))
            else:
                chart_v_ticks.add(vline)

        obsc_curve_pts = [
            chart_obsc_pt(f["t_rel_s"], f["obscuration"]) for f in disk_frames
        ]
        obsc_curve = VMobject(stroke_color=ACCENT_GOLD, stroke_width=2.2)
        obsc_curve.set_points_as_corners(obsc_curve_pts)

        alt_curve_pts = [
            chart_alt_pt(f["t_rel_s"], f["sun_alt_deg"]) for f in disk_frames
        ]
        alt_curve = VMobject(
            stroke_color=ACCENT_TEAL, stroke_width=1.9, stroke_opacity=0.85
        )
        alt_curve.set_points_as_corners(alt_curve_pts)

        legend_group = VGroup(
            Line(ORIGIN, RIGHT * 0.24, stroke_color=ACCENT_GOLD, stroke_width=2.4),
            Text("遮掩率", font=FONT_SANS, font_size=10, color=TEXT_PRIMARY),
            Line(ORIGIN, RIGHT * 0.24, stroke_color=ACCENT_TEAL, stroke_width=2.0),
            Text(
                f"{self.city_short}仰角",
                font=FONT_SANS,
                font_size=10,
                color=TEXT_PRIMARY,
            ),
        ).arrange(RIGHT, buff=0.08)
        legend_group.move_to(
            np.array([right_bot_panel.get_right()[0] - 0.22, rb_header_y, 0.0]),
            aligned_edge=RIGHT,
        )

        right_static_group = VGroup(
            right_top_panel,
            right_top_header_line,
            right_top_title,
            fov_bg,
            zenith_lbl,
            hud_static_labels,
            right_bot_panel,
            right_bot_header_line,
            right_bot_title,
            chart_box,
            full_line,
            half_line,
            y_axis_labels,
            chart_v_ticks,
            alt_curve,
            obsc_curve,
            legend_group,
        )

        # =====================================================================
        # 5. 时间驱动器 (ValueTracker) 与零 I/O 动态重绘组件
        # =====================================================================
        t_tracker = ValueTracker(t_min)

        def build_dynamic_overlay() -> VGroup:
            t_cur = float(t_tracker.get_value())
            st = interp_state(t_cur)
            bx = float(st["bx"])
            by = float(st["by"])
            x_deg = float(st["x_deg"])
            y_deg = float(st["y_deg"])
            sun_r = float(st["sun_r"])
            moon_r = float(st["moon_r"])
            obsc = float(st["obsc"])
            alt_deg = float(st["alt_deg"])
            q_rad = float(st["q_rad"])

            # --- A. 左侧贝塞尔基本面动态月影与自转测站 ---
            shadow_pt = bessel_to_point(bx, by)
            pen_r_plan = l1_earth * earth_r_scale
            umb_r_plan = max(abs(l2_earth) * earth_r_scale, 0.048)

            # 半影与地球圆盘的交集高亮 + 裁剪在视窗内的半影外轮廓
            pen_earth_inter = circle_intersection_region(
                plane_origin,
                earth_r_scale,
                shadow_pt,
                pen_r_plan,
                fill_color=PENUMBRA_FILL,
                fill_opacity=0.58,
            )
            pen_circle_outline = Circle(
                radius=pen_r_plan,
                fill_opacity=0.0,
                stroke_color=PENUMBRA_STROKE,
                stroke_width=1.4,
                stroke_opacity=0.80,
            ).move_to(shadow_pt)

            umb_spot = Circle(
                radius=umb_r_plan,
                fill_color="#05070B" if l2_earth <= 0 else ACCENT_GOLD,
                fill_opacity=0.95,
                stroke_color=ACCENT_RED if l2_earth <= 0 else ACCENT_GOLD,
                stroke_width=1.8,
            ).move_to(shadow_pt)

            obs_xi, obs_eta, obs_zeta = obs_bessel_xy(t_cur)
            obs_pt = bessel_to_point(obs_xi, obs_eta)
            obs_ring = Circle(
                radius=0.095,
                fill_opacity=0.0,
                stroke_color=ACCENT_TEAL,
                stroke_width=1.8,
                stroke_opacity=0.90 if obs_zeta >= 0 else 0.35,
            ).move_to(obs_pt)
            obs_dot = Dot(
                point=obs_pt,
                radius=0.048,
                color=ACCENT_TEAL if obs_zeta >= 0 else TEXT_MUTED,
            )
            obs_tag = obs_tag_proto.copy().move_to(obs_pt + DOWN * 0.16)
            plan_group = VGroup(
                pen_earth_inter,
                pen_circle_outline,
                umb_spot,
                obs_ring,
                obs_dot,
                obs_tag,
            )

            # --- B. 右上站心日面特写 (天顶向上) ---
            sx_deg, sy_deg = sky_to_zenith_up(x_deg, y_deg, q_rad)
            r_sun_zoom = sun_r * zoom_deg_scale
            r_moon_zoom = moon_r * zoom_deg_scale
            moon_offset = np.array(
                [sx_deg * zoom_deg_scale, sy_deg * zoom_deg_scale, 0.0]
            )
            zoom_moon_center = zoom_sun_center + moon_offset

            is_totality = (
                local_kind == "total"
                and obsc >= 0.998
                and r_moon_zoom >= r_sun_zoom * 0.995
            )
            is_annularity = (
                local_kind == "annular"
                and c2_t is not None
                and c3_t is not None
                and c2_t <= t_cur <= c3_t
            )

            # 日冕光晕层（恒定保留在树中，仅在全食阶段显式提升不透明度）
            corona_alpha = 1.0 if is_totality else 0.0
            corona_outer = Circle(
                radius=r_sun_zoom * 1.52,
                fill_color=MOON_BRIGHT,
                fill_opacity=0.16 * corona_alpha,
                stroke_width=0.0,
            ).move_to(zoom_sun_center)
            corona_mid = Circle(
                radius=r_sun_zoom * 1.26,
                fill_color=MOON_BRIGHT,
                fill_opacity=0.32 * corona_alpha,
                stroke_width=0.0,
            ).move_to(zoom_sun_center)
            corona_inner = Circle(
                radius=r_sun_zoom * 1.06,
                fill_color="#FF6B5B",
                fill_opacity=0.75 * corona_alpha,
                stroke_width=0.0,
            ).move_to(zoom_sun_center)

            # 太阳光球层圆盘
            sun_disk = Circle(
                radius=r_sun_zoom,
                fill_color="#FFBE2E",
                fill_opacity=0.98 if alt_deg >= 0.0 else 0.42,
                stroke_color=ACCENT_GOLD,
                stroke_width=1.8,
            ).move_to(zoom_sun_center)

            # 月球遮挡太阳的暗面交集（偏食月牙、环食黑芯、全食黑盘）
            moon_occ_region = circle_intersection_region(
                zoom_sun_center,
                r_sun_zoom * (1.01 if is_totality else 1.0),
                zoom_moon_center,
                r_moon_zoom,
                fill_color="#070A10",
                fill_opacity=0.98,
                stroke_color=ACCENT_RED if is_totality else "#1E293B",
                stroke_width=1.2 if is_totality else 0.6,
            )

            # 视场内的月球完整外轮廓（在 C1/C4 前后也能看清月盘进出方向）
            moon_limb_clip = circle_intersection_region(
                zoom_sun_center,
                zoom_fov_radius * 0.96,
                zoom_moon_center,
                r_moon_zoom,
                fill_color="#070A10",
                fill_opacity=0.0,
                stroke_color=ACCENT_GOLD if is_annularity else OUTLINE_COLOR,
                stroke_width=1.2,
            )

            zoom_group = VGroup(
                corona_outer,
                corona_mid,
                corona_inner,
                sun_disk,
                moon_occ_region,
                moon_limb_clip,
            )

            # --- C. 遥测文字与等宽数字 ---
            stage_color = (
                ACCENT_RED
                if is_totality
                else (
                    ACCENT_GOLD
                    if (is_annularity or obsc > 0.01)
                    else ACCENT_BLUE
                )
            )
            stage_txt = get_cached_stage_text(str(st["stage"]), stage_color)

            sep_arcmin = float(math.hypot(x_deg, y_deg) * 60.0)
            val_specs = [
                (hud_row_ys[0], str(st["cst_str"]), TEXT_PRIMARY),
                (hud_row_ys[1], str(st["utc_str"]), TEXT_MUTED),
                (
                    hud_row_ys[2],
                    f"{obsc * 100:5.1f}%",
                    ACCENT_RED
                    if is_totality
                    else (ACCENT_GOLD if obsc > 0 else TEXT_PRIMARY),
                ),
                (
                    hud_row_ys[3],
                    f"{alt_deg:5.1f}°",
                    ACCENT_TEAL if alt_deg >= 0 else ACCENT_RED,
                ),
                (hud_row_ys[4], f"{sep_arcmin:5.2f}'", TEXT_MUTED),
            ]
            hud_vals = VGroup(stage_txt)
            for ry, v_str, v_col in val_specs:
                vt = glyph_pool.render_line(
                    v_str, np.array([hud_value_x, ry, 0.0]), v_col
                )
                hud_vals.add(vt)

            # --- D. 右下曲线游标 ---
            cur_obsc_pt = chart_obsc_pt(t_cur, obsc)
            cur_alt_pt = chart_alt_pt(t_cur, alt_deg)
            playhead_line = Line(
                np.array([cur_obsc_pt[0], chart_bottom, 0.0]),
                np.array([cur_obsc_pt[0], chart_top, 0.0]),
                stroke_color=ACCENT_GOLD,
                stroke_width=1.6,
            )
            obsc_dot = Dot(point=cur_obsc_pt, radius=0.055, color=ACCENT_GOLD)
            alt_dot = Dot(point=cur_alt_pt, radius=0.048, color=ACCENT_TEAL)

            return VGroup(
                plan_group,
                zoom_group,
                hud_vals,
                playhead_line,
                obsc_dot,
                alt_dot,
            )

        dynamic_overlay = always_redraw(build_dynamic_overlay)

        # =====================================================================
        # 6. 动画编排 (Timeline Choreography)
        # =====================================================================
        self.add(
            header_group,
            left_static_group,
            right_static_group,
            dynamic_overlay,
        )
        self.wait(0.3)

        if c2_t is not None:
            self.play(
                t_tracker.animate.set_value(c2_t),
                run_time=2.8,
                rate_func=linear,
            )
            self.play(
                t_tracker.animate.set_value(max_t),
                run_time=1.4,
                rate_func=linear,
            )
        else:
            self.play(
                t_tracker.animate.set_value(max_t),
                run_time=4.2,
                rate_func=linear,
            )

        max_cst_hms = local_max_cst_dt.strftime("%H:%M:%S")
        greatest_badge_txt = Text(
            f"本地食甚 {max_cst_hms} · 遮掩 {local_max_obsc * 100:.1f}%",
            font=FONT_SANS,
            font_size=11,
            color=ACCENT_GOLD,
            weight="BOLD",
        )
        greatest_badge = Rectangle(
            width=greatest_badge_txt.width + 0.36,
            height=0.38,
            fill_color=UMBRA_FILL,
            fill_opacity=0.95,
            stroke_color=ACCENT_GOLD,
            stroke_width=1.3,
        )
        greatest_badge.move_to(
            np.array([left_panel.get_right()[0] - 0.22, left_divider_y - 0.16, 0.0]),
            aligned_edge=UP + RIGHT,
        )
        greatest_badge_txt.move_to(greatest_badge.get_center())
        greatest_callout = VGroup(greatest_badge, greatest_badge_txt)

        self.play(FadeIn(greatest_callout, scale=0.92), run_time=0.3)
        self.wait(1.0)

        if c3_t is not None:
            self.play(
                t_tracker.animate.set_value(c3_t),
                run_time=1.8,
                rate_func=linear,
            )
            self.play(
                t_tracker.animate.set_value(t_max),
                run_time=3.6,
                rate_func=linear,
            )
        else:
            self.play(
                t_tracker.animate.set_value(t_max),
                run_time=5.4,
                rate_func=linear,
            )
        self.wait(0.8)


class SolarEclipseScene(SolarEclipseBaseScene):
    """2027-08-02 卢克索世纪日全食（全食 6m22s，食分 1.079，仰角 82°）。"""

    eclipse_date = "2027-08-02"
    observer_coords = "25.687,32.640"
    observer_label = "卢克索观测视算 (25.7°N, 32.6°E)"
    city_short = "卢克索"
    json_filename = "solar_2027_08_02.json"


class BeijingTotalSolarScene(SolarEclipseBaseScene):
    """2035-09-02 北京日全食（本地全食 1m32s，食分 1.026，仰角 32°）。"""

    eclipse_date = "2035-09-02"
    observer_coords = "39.9042,116.4074"
    observer_label = "北京观测视算 (39.9°N, 116.4°E)"
    city_short = "北京"
    json_filename = "beijing_solar_2035_09_02.json"


class ChinaAnnularSolarScene(SolarEclipseBaseScene):
    """2030-06-01 黑龙江同江日环食（金环日食 4m30s，食分 0.940，遮掩 88.4%）。"""

    eclipse_date = "2030-06-01"
    observer_coords = "48.00,132.00"
    observer_label = "黑龙江同江观测视算 (48.0°N, 132.0°E)"
    city_short = "同江"
    json_filename = "tongjiang_solar_2030_06_01.json"


class UrumqiNearestSolarScene(SolarEclipseBaseScene):
    """2030-06-01 乌鲁木齐日偏食（未来最近可见日食，食分 0.632，遮掩 53.2%，仰角 67°）。"""

    eclipse_date = "2030-06-01"
    observer_coords = "43.8256,87.6168"
    observer_label = "乌鲁木齐观测视算 (43.8°N, 87.6°E)"
    city_short = "乌市"
    json_filename = "urumqi_solar_2030_06_01.json"
