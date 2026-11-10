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
import os
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


_LAND_RINGS_RAD_CACHE: list[np.ndarray] | None = None


def load_land_rings_rad() -> list[np.ndarray]:
    """加载 app/assets/geo/land_110m.json 陆地多边形（弧度 [lon_rad, lat_rad]），过滤亚像素碎岛与冗余密集点。"""
    global _LAND_RINGS_RAD_CACHE
    if _LAND_RINGS_RAD_CACHE is not None:
        return _LAND_RINGS_RAD_CACHE
    land_path = ROOT / "app" / "assets" / "geo" / "land_110m.json"
    raw = json.loads(land_path.read_text(encoding="utf-8"))
    scale = float(raw["scale"])
    rings: list[np.ndarray] = []
    for r in raw["rings"]:
        deg_arr = np.array(r, dtype=float).reshape(-1, 2) / scale
        if len(deg_arr) >= 3 and np.allclose(deg_arr[0], deg_arr[-1]):
            deg_arr = deg_arr[:-1]
        if len(deg_arr) < 4:
            continue
        x, y = deg_arr[:, 0], deg_arr[:, 1]
        area_sq_deg = 0.5 * abs(float(np.dot(x, np.roll(y, -1)) - np.dot(np.roll(x, -1), y)))
        if area_sq_deg < 1.5:
            continue
        kept = [deg_arr[0]]
        for pt in deg_arr[1:]:
            if math.hypot(float(pt[0] - kept[-1][0]), float(pt[1] - kept[-1][1])) >= 0.9:
                kept.append(pt)
        if len(kept) >= 4:
            rings.append(np.radians(np.array(kept, dtype=float)))
    _LAND_RINGS_RAD_CACHE = rings
    return rings


def build_surface_eclipse_band_rad(central_line: list[dict]) -> np.ndarray | None:
    """按中心线 (lat_deg, lon_deg, width_km) 构建地表全/环食带多边形（与客户端 world_map.dart 的 pathBand 一致）。"""
    # 过滤掉首尾地平线附近因投影倾角趋近 0° 导致食带宽数值发散的端点
    valid_cl = [
        p
        for p in central_line
        if float(p.get("sun_alt_deg", 10.0)) >= 5.5
        and float(p.get("width_km", 100.0)) <= 650.0
    ]
    if len(valid_cl) > 90:
        step = max(1, len(valid_cl) // 80)
        sampled = valid_cl[::step]
        if sampled[-1] is not valid_cl[-1]:
            sampled.append(valid_cl[-1])
        valid_cl = sampled
    n = len(valid_cl)
    if n < 2:
        return None
    km_per_deg = 111.2
    left_pts: list[tuple[float, float]] = []
    right_pts: list[tuple[float, float]] = []
    for i in range(n):
        a = valid_cl[0 if i == 0 else i - 1]
        b = valid_cl[n - 1 if i == n - 1 else i + 1]
        c = valid_cl[i]
        lat = float(c["lat_deg"])
        lon = float(c["lon_deg"])
        w_km = float(c.get("width_km", 100.0))
        k = math.cos(math.radians(lat))
        dlon = float(b["lon_deg"]) - float(a["lon_deg"])
        dlon -= 360.0 * round(dlon / 360.0)
        dlat = float(b["lat_deg"]) - float(a["lat_deg"])
        east_km = dlon * k * km_per_deg
        north_km = dlat * km_per_deg
        seg_len = math.hypot(east_km, north_km)
        if seg_len <= 1e-6:
            continue
        ux = -north_km / seg_len
        uy = east_km / seg_len
        half_w = 0.5 * max(w_km, 25.0)
        off_lat = uy * half_w / km_per_deg
        off_lon = ux * half_w / (km_per_deg * max(k, 0.05))
        left_pts.append((math.radians(lon + off_lon), math.radians(lat + off_lat)))
        right_pts.append((math.radians(lon - off_lon), math.radians(lat - off_lat)))
    if len(left_pts) < 2:
        return None
    ring = left_pts + list(reversed(right_pts))
    return np.array(ring, dtype=float)


def project_ring_to_orthographic(
    ring_rad: np.ndarray,
    d_rad: float,
    sub_lon_rad: float,
    plane_origin: np.ndarray,
    earth_r_scale: float,
) -> tuple[np.ndarray | None, list[np.ndarray]]:
    """将球面多边形正射投影到向阳半球 (ζ >= 0)，沿地平边缘圆弧闭合被裁切部分。"""
    lons = ring_rad[:, 0]
    lats = ring_rad[:, 1]
    h_ang = lons - sub_lon_rad
    cl = np.cos(lats)
    sl = np.sin(lats)
    cd = math.cos(d_rad)
    sd = math.sin(d_rad)
    xi = cl * np.sin(h_ang)
    eta = sl * cd - cl * sd * np.cos(h_ang)
    zeta = sl * sd + cl * cd * np.cos(h_ang)

    if np.all(zeta <= 0.0):
        return None, []

    if np.all(zeta >= 0.0):
        sx = plane_origin[0] + xi * earth_r_scale
        sy = plane_origin[1] + eta * earth_r_scale
        pts = np.column_stack([sx, sy, np.zeros_like(sx)])
        closed = np.vstack([pts, pts[0:1]])
        return closed, [closed]

    neg_idx = int(np.argmin(zeta))
    xi = np.roll(xi, -neg_idx)
    eta = np.roll(eta, -neg_idx)
    zeta = np.roll(zeta, -neg_idx)
    n_pts = len(zeta)
    vis = zeta >= 0.0
    starts = np.where(vis & ~np.roll(vis, 1))[0]
    ends = np.where(vis & ~np.roll(vis, -1))[0]
    if len(starts) == 0:
        return None, []

    coast_segments: list[np.ndarray] = []
    run_unit_segs: list[np.ndarray] = []
    t_ins: list[float] = []
    t_outs: list[float] = []

    for s_idx, e_idx in zip(starts, ends, strict=True):
        prev_idx = (s_idx - 1) % n_pts
        a_in = float(-zeta[prev_idx] / (zeta[s_idx] - zeta[prev_idx]))
        xi_in = float(xi[prev_idx] + a_in * (xi[s_idx] - xi[prev_idx]))
        eta_in = float(eta[prev_idx] + a_in * (eta[s_idx] - eta[prev_idx]))
        r_in = max(math.hypot(xi_in, eta_in), 1e-6)
        xi_in, eta_in = xi_in / r_in, eta_in / r_in

        nxt_idx = (e_idx + 1) % n_pts
        a_out = float(zeta[e_idx] / (zeta[e_idx] - zeta[nxt_idx]))
        xi_out = float(xi[e_idx] + a_out * (xi[nxt_idx] - xi[e_idx]))
        eta_out = float(eta[e_idx] + a_out * (eta[nxt_idx] - eta[e_idx]))
        r_out = max(math.hypot(xi_out, eta_out), 1e-6)
        xi_out, eta_out = xi_out / r_out, eta_out / r_out

        if s_idx <= e_idx:
            mid_xi = xi[s_idx : e_idx + 1]
            mid_eta = eta[s_idx : e_idx + 1]
        else:
            mid_xi = np.concatenate([xi[s_idx:], xi[: e_idx + 1]])
            mid_eta = np.concatenate([eta[s_idx:], eta[: e_idx + 1]])

        ux = np.concatenate([[xi_in], mid_xi, [xi_out]])
        uy = np.concatenate([[eta_in], mid_eta, [eta_out]])
        unit_seg = np.column_stack([ux, uy])
        run_unit_segs.append(unit_seg)
        t_ins.append(math.atan2(eta_in, xi_in))
        t_outs.append(math.atan2(eta_out, xi_out))

        sx = plane_origin[0] + ux * earth_r_scale
        sy = plane_origin[1] + uy * earth_r_scale
        coast_segments.append(np.column_stack([sx, sy, np.zeros_like(sx)]))

    # 将可见海岸段与地平圆弧段拼接为闭合填充多边形
    fill_unit_parts: list[np.ndarray] = []
    num_runs = len(run_unit_segs)
    for k in range(num_runs):
        fill_unit_parts.append(run_unit_segs[k])
        th0 = t_outs[k]
        th1 = t_ins[(k + 1) % num_runs]
        dth = (th1 - th0 + math.pi) % (2.0 * math.pi) - math.pi
        n_arc = max(2, int(abs(dth) / math.radians(4.0)) + 1)
        ths = np.linspace(th0, th0 + dth, n_arc)[1:-1]
        if len(ths) > 0:
            arc_xy = np.column_stack([np.cos(ths), np.sin(ths)])
            fill_unit_parts.append(arc_xy)

    full_unit = np.vstack(fill_unit_parts)
    fx = plane_origin[0] + full_unit[:, 0] * earth_r_scale
    fy = plane_origin[1] + full_unit[:, 1] * earth_r_scale
    fill_pts = np.column_stack([fx, fy, np.zeros_like(fx)])
    fill_closed = np.vstack([fill_pts, fill_pts[0:1]])
    return fill_closed, coast_segments


def polylines_to_vmobject(
    polylines: list[np.ndarray],
    *,
    fill_color: str | ManimColor = "#000000",
    fill_opacity: float = 0.0,
    stroke_color: str | ManimColor = "#FFFFFF",
    stroke_width: float = 1.0,
    stroke_opacity: float = 1.0,
) -> VMobject:
    """将多条折线或闭合多边形批量打包进单个 VMobject（恒定单节点，消除逐个创建的开销）。"""
    valid = [p for p in polylines if len(p) >= 2]
    if not valid:
        dummy = Circle(radius=1e-4)
        dummy.set_fill(opacity=0.0).set_stroke(width=0.0)
        return dummy
    starts = np.vstack([p[:-1] for p in valid])
    ends = np.vstack([p[1:] for p in valid])
    bezier = np.empty((len(starts) * 4, 3), dtype=float)
    bezier[0::4] = starts
    bezier[1::4] = starts * (2.0 / 3.0) + ends * (1.0 / 3.0)
    bezier[2::4] = starts * (1.0 / 3.0) + ends * (2.0 / 3.0)
    bezier[3::4] = ends
    vmob = VMobject()
    vmob.set_points(bezier)
    vmob.set_fill(fill_color, opacity=fill_opacity)
    vmob.set_stroke(stroke_color, width=stroke_width, opacity=stroke_opacity)
    return vmob


class MonospaceGlyphPool:
    """预渲染等宽 ASCII 字形池，打包为单节点 VMobject 消除逐帧 Pango 读写与子对象树变动。"""

    def __init__(self, font: str = FONT_MONO, font_size: int = 13) -> None:
        self._glyph_pts: dict[str, np.ndarray] = {}
        ref = Text("0", font=font, font_size=font_size, color=TEXT_PRIMARY)
        self.advance_w = float(ref.width) * 1.08
        self.ref_h = float(ref.height)

        charset = "0123456789+-.:%°UTC'"
        for ch in charset:
            g = Text(ch, font=font, font_size=font_size, color=TEXT_PRIMARY)
            g.move_to(ORIGIN)
            pts_list = [
                m.points for m in g.family_members_with_points() if len(m.points) > 0
            ]
            if pts_list:
                self._glyph_pts[ch] = np.vstack(pts_list).copy()

    def render_line(
        self,
        text: str,
        anchor_left: np.ndarray,
        color: str | ManimColor,
        fixed_len: int = 14,
    ) -> VMobject:
        padded = text.ljust(fixed_len)[:fixed_len]
        parts: list[np.ndarray] = []
        for idx, ch in enumerate(padded):
            base_pts = self._glyph_pts.get(ch)
            if ch == " " or base_pts is None:
                continue
            x_pos = float(anchor_left[0]) + (idx + 0.5) * self.advance_w
            y_pos = float(anchor_left[1])
            if ch == ".":
                y_pos -= self.ref_h * 0.30
            elif ch in ("'", "°"):
                y_pos += self.ref_h * 0.26
            parts.append(base_pts + np.array([x_pos, y_pos, 0.0]))
        vmob = VMobject()
        if parts:
            vmob.set_points(np.vstack(parts))
            vmob.set_fill(color, opacity=1.0).set_stroke(width=0.0)
        else:
            dummy = Circle(radius=1e-4).move_to(anchor_left)
            vmob.set_points(np.array(dummy.points))
            vmob.set_fill(opacity=0.0).set_stroke(width=0.0)
        return vmob


class SolarEclipseBaseScene(Scene):
    """自适应日全食、日环食、日偏食与任意观测站点的通用日食演示基类。"""

    eclipse_date: str = "2027-08-02"
    observer_coords: str = "25.687,32.640"
    observer_label: str = "卢克索观测视算 (25.7°N, 32.6°E)"
    city_short: str = "卢克索"
    json_filename: str = "solar_2027_08_02.json"
    aspect_ratio_mode: str = "16:9"

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

        is_portrait = (
            os.environ.get("GUANXIANG_ASPECT") == "9:16"
            or getattr(self, "aspect_ratio_mode", None) == "9:16"
            or (hasattr(config, "pixel_width") and config.pixel_width < config.pixel_height)
        )
        if is_portrait:
            self.camera.frame_width = 8.0
            self.camera.frame_height = 8.0 * (16.0 / 9.0)  # 14.2222

            # 9:16 移动端竖屏布局 (自上而下: Header -> 站心特写/HUD -> 贝塞尔基本面正射投影 -> 时序演化曲线)
            header_w = 7.40
            header_h = 0.94
            header_center = np.array([0.0, 6.45, 0.0])

            # 面板 1：站心日面特写视窗 (天顶向上) + 遥测 HUD (上区)
            top_panel_w = 7.40
            top_panel_h = 3.50
            top_panel_center = np.array([0.0, 4.05, 0.0])
            zoom_sun_center = np.array([-1.90, 3.75, 0.0])
            zoom_fov_radius = 1.15
            zoom_sun_radius = 0.58
            hud_label_x = 0.05
            hud_value_x = 1.35
            hud_row_ys = [4.38, 4.00, 3.62, 3.24, 2.86]
            stage_text_y = 4.88

            # 面板 2：贝塞尔基本面正射投影主视窗 (中区)
            main_panel_w = 7.40
            main_panel_h = 5.50
            main_panel_center = np.array([0.0, -0.65, 0.0])
            plane_origin = np.array([0.0, -0.80, 0.0])
            earth_r_scale = 2.05

            # 面板 3：时序演化曲线 (下区)
            bot_panel_w = 7.40
            bot_panel_h = 3.20
            bot_panel_center = np.array([0.0, -5.20, 0.0])
            chart_left = -2.85
            chart_right = 2.85
            chart_bottom = -6.40
            chart_top = -4.30
        else:
            # 16:9 宽屏科研仪表板布局
            header_w = 13.60
            header_h = 0.72
            header_center = np.array([0.0, 3.48, 0.0])

            # 面板 1：站心日面特写视窗 (右上)
            top_panel_w = 5.65
            top_panel_h = 3.18
            top_panel_center = np.array([3.95, 1.33, 0.0])
            zoom_sun_center = np.array([2.28, 1.00, 0.0])
            zoom_fov_radius = 0.98
            zoom_sun_radius = 0.50
            hud_label_x = 3.52
            hud_value_x = 4.60
            hud_row_ys = [1.56, 1.20, 0.84, 0.48, 0.12]
            stage_text_y = 1.94

            # 面板 2：贝塞尔基本面正射投影主视窗 (左侧大窗)
            main_panel_w = 7.70
            main_panel_h = 6.76
            main_panel_center = np.array([-2.95, -0.42, 0.0])
            plane_origin = np.array([-2.95, -0.58, 0.0])
            earth_r_scale = 2.40

            # 面板 3：时序演化曲线 (右下)
            bot_panel_w = 5.65
            bot_panel_h = 3.36
            bot_panel_center = np.array([3.95, -2.12, 0.0])
            chart_left = 1.72
            chart_right = 6.22
            chart_bottom = -3.34
            chart_top = -1.16

        # =====================================================================
        # 1. 顶部科研遥测标题栏 (Header Bar - 直角边框)
        # =====================================================================
        header_bg = Rectangle(
            width=header_w,
            height=header_h,
            fill_color=SURFACE_CARD,
            fill_opacity=0.96,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.4,
        ).move_to(header_center)

        dur_part = ""
        if central_dur_s is not None and central_dur_s > 0:
            dm = int(central_dur_s) // 60
            ds = int(round(central_dur_s)) % 60
            dur_part = f" · 持续 {dm}m{ds:02d}s"

        if is_portrait:
            title_text = Text(
                f"{cst_date_str} {global_kind_zh} · {self.observer_label}",
                font=FONT_SANS,
                font_size=13.5,
                color=TEXT_PRIMARY,
                weight="BOLD",
            ).move_to(np.array([0.0, header_bg.get_center()[1] + 0.17, 0.0]))

            subtitle_text = Text(
                f"本地{local_kind_zh} · 食分 {local_mag:.3f} · 遮掩 {local_max_obsc * 100:.1f}%{dur_part} · "
                f"沙罗 {saros['series']} ({saros['member']}/{saros['count']})",
                font=FONT_SANS,
                font_size=9.5,
                color=TEXT_MUTED,
            ).move_to(np.array([0.0, header_bg.get_center()[1] - 0.17, 0.0]))
        else:
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
        # 2. 贝塞尔基本面与地影扫掠视图 (向阳半球 · 北上东右)
        # =====================================================================
        left_panel = Rectangle(
            width=main_panel_w,
            height=main_panel_h,
            fill_color=SURFACE_CARD,
            fill_opacity=0.90,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.4,
        ).move_to(main_panel_center)

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
            "贝塞尔基本面正射投影 (向阳半球 · 北上东右)" if not is_portrait else "贝塞尔基本面正射投影 (向阳半球)",
            font=FONT_SANS,
            font_size=13 if not is_portrait else 11.5,
            color=ACCENT_BLUE,
            weight="BOLD",
        )
        left_panel_title.move_to(
            np.array([left_panel.get_left()[0] + 0.20, left_header_y, 0.0]),
            aligned_edge=LEFT,
        )

        # 图例说明（顶栏右对齐）
        band_label_zh = "地表全食带" if l2_earth <= 0 else "地表环食带"
        band_col = ACCENT_RED if l2_earth <= 0 else ACCENT_GOLD
        bessel_legend = VGroup(
            Rectangle(
                width=0.18,
                height=0.09,
                fill_color=band_col,
                fill_opacity=0.65,
                stroke_color=band_col,
                stroke_width=1.0,
            ),
            Text(band_label_zh, font=FONT_SANS, font_size=10 if not is_portrait else 8.5, color=TEXT_MUTED),
            Dot(radius=0.040 if not is_portrait else 0.035, color=ACCENT_GOLD),
            Text(
                f"月影轴 (γ={data['gamma']:+.3f})" if not is_portrait else f"月影 (γ={data['gamma']:+.2f})",
                font=FONT_SANS,
                font_size=10 if not is_portrait else 8.5,
                color=TEXT_MUTED,
            ),
            Dot(radius=0.040 if not is_portrait else 0.035, color=ACCENT_TEAL),
            Text(
                f"{self.city_short}自转轨迹" if not is_portrait else f"{self.city_short}轨迹",
                font=FONT_SANS,
                font_size=10 if not is_portrait else 8.5,
                color=TEXT_MUTED,
            ),
        ).arrange(RIGHT, buff=0.07 if not is_portrait else 0.05)
        bessel_legend.move_to(
            np.array([left_panel.get_right()[0] - 0.20, left_header_y, 0.0]),
            aligned_edge=RIGHT,
        )

        def bessel_to_point(x_er: float, y_er: float) -> np.ndarray:
            return plane_origin + np.array(
                [x_er * earth_r_scale, y_er * earth_r_scale, 0.0]
            )

        land_rings_rad = load_land_rings_rad()
        surface_band_rad = build_surface_eclipse_band_rad(data.get("central_line", []))

        # 地球向阳半球海洋底盘与外缘地平圈
        earth_disk = Circle(
            radius=earth_r_scale,
            fill_color="#0B1524",
            fill_opacity=0.96,
            stroke_color=ACCENT_BLUE,
            stroke_width=1.6,
        ).move_to(plane_origin)

        earth_limb_ring = Circle(
            radius=earth_r_scale,
            fill_opacity=0.0,
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
                plane_origin + LEFT * (earth_r_scale + 0.32)
            ),
            Text("东 E", font=FONT_SANS, font_size=11, color=TEXT_MUTED).move_to(
                plane_origin + RIGHT * (earth_r_scale + 0.32)
            ),
            Text("北 N", font=FONT_SANS, font_size=11, color=TEXT_MUTED).move_to(
                plane_origin + UP * (earth_r_scale + 0.22)
            ),
            Text("南 S", font=FONT_SANS, font_size=11, color=TEXT_MUTED).move_to(
                plane_origin + DOWN * (earth_r_scale + 0.22)
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

        # 月影中心轴轨迹线（严格裁剪在左侧视窗安全区域内）
        shadow_track_pts = []
        for p in bessel_track:
            pt = bessel_to_point(p["x"], p["y"])
            if (
                left_panel.get_left()[0] + 0.28
                <= pt[0]
                <= left_panel.get_right()[0] - 0.28
                and left_panel.get_bottom()[1] + 0.40
                <= pt[1]
                <= left_divider_y - 0.16
            ):
                shadow_track_pts.append(pt)
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
            dir_labels,
            coord_note,
        )

        # =====================================================================
        # 3. 站心日面特写与月影遮掩模拟 (天顶向上) + 遥测 HUD
        # =====================================================================
        right_top_panel = Rectangle(
            width=top_panel_w,
            height=top_panel_h,
            fill_color=SURFACE_CARD,
            fill_opacity=0.90,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.4,
        ).move_to(top_panel_center)

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
            font_size=13 if not is_portrait else 11.5,
            color=ACCENT_GOLD,
            weight="BOLD",
        )
        right_top_title.move_to(
            np.array([right_top_panel.get_left()[0] + 0.20, rt_header_y, 0.0]),
            aligned_edge=LEFT,
        )

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

        hud_static_labels = VGroup()
        for row_y, zh_label in zip(
            hud_row_ys,
            ["北京时间", "世界时", "遮掩面积", f"{self.city_short}仰角", "日月角距"],
            strict=True,
        ):
            lbl = Text(
                zh_label,
                font=FONT_SANS,
                font_size=12 if not is_portrait else 11,
                color=TEXT_MUTED,
            )
            lbl.move_to(np.array([hud_label_x, row_y, 0.0]), aligned_edge=LEFT)
            hud_static_labels.add(lbl)

        glyph_pool = MonospaceGlyphPool(font=FONT_MONO, font_size=12 if not is_portrait else 11)
        stage_text_cache: dict[tuple[str, str], VMobject] = {}

        def get_cached_stage_text(stage_str: str, color_hex: str) -> VMobject:
            key = (stage_str, color_hex)
            if key not in stage_text_cache:
                t_mob = Text(
                    stage_str,
                    font=FONT_SANS,
                    font_size=13 if not is_portrait else 12,
                    color=color_hex,
                    weight="BOLD",
                )
                t_mob.move_to(np.array([hud_label_x, stage_text_y, 0.0]), aligned_edge=LEFT)
                pts_list = [
                    m.points
                    for m in t_mob.family_members_with_points()
                    if len(m.points) > 0
                ]
                single = VMobject()
                single.set_points(np.vstack(pts_list))
                single.set_fill(color_hex, opacity=1.0).set_stroke(width=0.0)
                stage_text_cache[key] = single
            return stage_text_cache[key].copy()

        # =====================================================================
        # 4. 右下视窗：日面遮掩面积与太阳仰角时序曲线
        # =====================================================================
        right_bot_panel = Rectangle(
            width=bot_panel_w,
            height=bot_panel_h,
            fill_color=SURFACE_CARD,
            fill_opacity=0.90,
            stroke_color=OUTLINE_COLOR,
            stroke_width=1.4,
        ).move_to(bot_panel_center)

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
            font_size=12 if is_portrait else 13,
            color=ACCENT_RED,
            weight="BOLD",
        )
        right_bot_title.move_to(
            np.array([right_bot_panel.get_left()[0] + 0.22, rb_header_y, 0.0]),
            aligned_edge=LEFT,
        )

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

            # --- A. 左侧贝塞尔基本面动态大陆轮廓、地表食带、月影与自转测站 ---
            sub_lon_rad = math.radians(sub_lon0_deg - t_cur * (360.0 / 86400.0))
            fill_polys: list[np.ndarray] = []
            for r_rad in land_rings_rad:
                fp, _ = project_ring_to_orthographic(
                    r_rad, d_rad, sub_lon_rad, plane_origin, earth_r_scale
                )
                if fp is not None:
                    fill_polys.append(fp)

            land_fill_vmob = polylines_to_vmobject(
                fill_polys,
                fill_color="#1A2E47",
                fill_opacity=0.90,
                stroke_color="#3E6C9E",
                stroke_width=0.9,
                stroke_opacity=0.85,
            )

            band_polys: list[np.ndarray] = []
            if surface_band_rad is not None:
                bfp, _ = project_ring_to_orthographic(
                    surface_band_rad, d_rad, sub_lon_rad, plane_origin, earth_r_scale
                )
                if bfp is not None:
                    band_polys.append(bfp)
            surface_band_vmob = polylines_to_vmobject(
                band_polys,
                fill_color=band_col,
                fill_opacity=0.42,
                stroke_color=band_col,
                stroke_width=1.1,
                stroke_opacity=0.88,
            )

            shadow_pt = bessel_to_point(bx, by)
            pen_r_plan = l1_earth * earth_r_scale
            umb_r_plan = max(abs(l2_earth) * earth_r_scale, 0.048)

            # 半影与地球圆盘的交集高亮 + 半影外轮廓
            pen_earth_inter = circle_intersection_region(
                plane_origin,
                earth_r_scale,
                shadow_pt,
                pen_r_plan,
                fill_color=PENUMBRA_FILL,
                fill_opacity=0.50,
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
                land_fill_vmob,
                graticule_group.copy(),
                surface_band_vmob,
                earth_limb_ring.copy(),
                pen_earth_inter,
                pen_circle_outline,
                shadow_track_line.copy(),
                g_dot.copy(),
                obs_rot_path.copy(),
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

        dynamic_overlay = build_dynamic_overlay()

        def _update_dynamic_overlay(mob: VGroup) -> None:
            target = build_dynamic_overlay()
            for sm1, sm2 in zip(mob.get_family(), target.get_family(), strict=True):
                if isinstance(sm1, VMobject) and isinstance(sm2, VMobject):
                    sm1.points = np.array(sm2.points)
                    sm1.interpolate_color(sm1, sm2, 1.0)

        dynamic_overlay.add_updater(_update_dynamic_overlay)

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


# =============================================================================
# 9:16 移动端竖屏短视频 HD 模式专有场景定义
# =============================================================================


class SolarEclipsePortraitScene(SolarEclipseScene):
    """2027-08-02 卢克索世纪日全食（9:16 移动端竖屏 HD 模式）。"""

    aspect_ratio_mode = "9:16"


class BeijingTotalSolarPortraitScene(BeijingTotalSolarScene):
    """2035-09-02 北京日全食（9:16 移动端竖屏 HD 模式）。"""

    aspect_ratio_mode = "9:16"


class ChinaAnnularSolarPortraitScene(ChinaAnnularSolarScene):
    """2030-06-01 黑龙江同江日环食（9:16 移动端竖屏 HD 模式）。"""

    aspect_ratio_mode = "9:16"


class UrumqiNearestSolarPortraitScene(UrumqiNearestSolarScene):
    """2030-06-01 乌鲁木齐日偏食（9:16 移动端竖屏 HD 模式）。"""

    aspect_ratio_mode = "9:16"

