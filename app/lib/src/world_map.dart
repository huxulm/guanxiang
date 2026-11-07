import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 随应用打包的陆地轮廓（Natural Earth 1:110m，公有领域），由 tools/geo/gen_land.py 生成。
const landAsset = 'assets/geo/land_110m.json';

/// 陆地轮廓：每个多边形是 [经度, 纬度, 经度, 纬度, …]（度）。只加载一次。
class LandOutline {
  LandOutline._(this.rings);

  final List<Float64List> rings;

  static Future<LandOutline>? _loading;

  static Future<LandOutline> load() => _loading ??= _load();

  static Future<LandOutline> _load() async {
    final j = jsonDecode(await rootBundle.loadString(landAsset)) as Map;
    final scale = (j['scale'] as num).toDouble();
    return LandOutline._([
      for (final r in j['rings'] as List)
        Float64List.fromList([for (final v in r as List) (v as num) / scale]),
    ]);
  }
}

/// 等距圆柱投影：经度 `centerLon` 放在正中，北在上；画布宽高比 2:1。
class MapProjection {
  MapProjection(this.size, this.centerLon);

  final Size size;
  final double centerLon;

  /// 每度多少像素
  double get k => size.width / 360;

  /// 不折回的横坐标：经度连续变化时坐标也连续，画的时候再按 ±360° 平移重画
  double rawX(double lon) => (lon - centerLon + 180) * k;

  double y(double lat) => (90 - lat) * k;

  /// 折回到画布内的位置
  Offset at(double lat, double lon) {
    final x = (lon - centerLon + 180) % 360;
    return Offset(x * k, y(lat));
  }

  /// 在三个平移位置（−360°、0、+360°）各画一次，跨过地图左右边缘的图形就完整了。
  void drawWrapped(Canvas canvas, void Function(Canvas canvas) draw) {
    for (final dx in [-360 * k, 0.0, 360 * k]) {
      canvas.save();
      canvas.translate(dx, 0);
      draw(canvas);
      canvas.restore();
    }
  }

  /// 一串 (纬度, 经度) 连成折线：相邻两点经度相差超过 180° 时按另一侧连（不折回）。
  Path polyline(Iterable<(double, double)> points) {
    final path = Path();
    double? prev;
    var lonAcc = 0.0;
    for (final (lat, lon) in points) {
      if (prev == null) {
        lonAcc = lon;
        path.moveTo(rawX(lonAcc), y(lat));
      } else {
        var d = lon - prev;
        d -= 360 * (d / 360).round();
        lonAcc += d;
        path.lineTo(rawX(lonAcc), y(lat));
      }
      prev = lon;
    }
    return path;
  }
}

/// 世界地图：海洋底色、陆地、经纬网。[fill] 画在陆地之上、海岸线之下（填色区域），
/// [marks] 画在最上面（曲线、点、标签）。
class WorldMap extends StatelessWidget {
  const WorldMap({super.key, required this.centerLon, this.fill, this.marks});

  final double centerLon;
  final void Function(Canvas canvas, MapProjection p)? fill;
  final void Function(Canvas canvas, MapProjection p)? marks;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<LandOutline>(
      future: LandOutline.load(),
      builder: (context, snap) => AspectRatio(
        aspectRatio: 2,
        child: CustomPaint(
          painter: _WorldMapPainter(
            land: snap.data,
            centerLon: centerLon,
            ocean: Color.alphaBlend(
              cs.primary.withValues(alpha: dark ? 0.08 : 0.06),
              cs.surface,
            ),
            landFill: Color.alphaBlend(
              cs.onSurface.withValues(alpha: dark ? 0.16 : 0.10),
              cs.surface,
            ),
            coast: cs.onSurfaceVariant.withValues(alpha: 0.7),
            grid: cs.outline.withValues(alpha: 0.6),
            fill: fill,
            marks: marks,
          ),
        ),
      ),
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  _WorldMapPainter({
    required this.land,
    required this.centerLon,
    required this.ocean,
    required this.landFill,
    required this.coast,
    required this.grid,
    this.fill,
    this.marks,
  });

  final LandOutline? land;
  final double centerLon;
  final Color ocean;
  final Color landFill;
  final Color coast;
  final Color grid;
  final void Function(Canvas canvas, MapProjection p)? fill;
  final void Function(Canvas canvas, MapProjection p)? marks;

  @override
  void paint(Canvas canvas, Size size) {
    final p = MapProjection(size, centerLon);
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = ocean);

    final landPath = Path();
    for (final r in land?.rings ?? const <Float64List>[]) {
      for (var i = 0; i < r.length; i += 2) {
        final o = Offset(p.rawX(r[i]), p.y(r[i + 1]));
        i == 0 ? landPath.moveTo(o.dx, o.dy) : landPath.lineTo(o.dx, o.dy);
      }
      landPath.close();
    }
    p.drawWrapped(
      canvas,
      (c) => c.drawPath(landPath, Paint()..color = landFill),
    );

    fill?.call(canvas, p);

    p.drawWrapped(
      canvas,
      (c) => c.drawPath(
        landPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = coast,
      ),
    );

    // 经纬网：每 30°
    final g = Paint()
      ..strokeWidth = 0.5
      ..color = grid;
    for (var lat = -60; lat <= 60; lat += 30) {
      canvas.drawLine(
        Offset(0, p.y(lat.toDouble())),
        Offset(size.width, p.y(lat.toDouble())),
        g,
      );
    }
    for (var lon = -180; lon < 180; lon += 30) {
      final x = p.at(0, lon.toDouble()).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), g);
    }

    marks?.call(canvas, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WorldMapPainter old) =>
      old.land != land ||
      old.centerLon != centerLon ||
      old.fill != fill ||
      old.marks != marks ||
      old.ocean != ocean;
}

/// 天体正好在地平线上的地方（地心计算）：与地下点相距 90° 的大圆，按 (纬度, 经度) 返回。
List<(double, double)> horizonCircle(
  double subLatDeg,
  double subLonDeg, {
  int steps = 180,
}) {
  final phi = subLatDeg * math.pi / 180;
  final lam = subLonDeg * math.pi / 180;
  // s 为地下点单位向量，u、v 与 s 正交
  final s = [
    math.cos(phi) * math.cos(lam),
    math.cos(phi) * math.sin(lam),
    math.sin(phi),
  ];
  // u：沿 s 所在经线指向北（φ+90°）
  final u = [
    -math.sin(phi) * math.cos(lam),
    -math.sin(phi) * math.sin(lam),
    math.cos(phi),
  ];
  final v = [
    s[1] * u[2] - s[2] * u[1],
    s[2] * u[0] - s[0] * u[2],
    s[0] * u[1] - s[1] * u[0],
  ];
  return [
    for (var i = 0; i <= steps; i++)
      () {
        final t = 2 * math.pi * i / steps;
        final (c, sn) = (math.cos(t), math.sin(t));
        final x = c * u[0] + sn * v[0];
        final yv = c * u[1] + sn * v[1];
        final z = c * u[2] + sn * v[2];
        return (
          math.asin(z.clamp(-1.0, 1.0)) * 180 / math.pi,
          math.atan2(yv, x) * 180 / math.pi,
        );
      }(),
  ];
}

/// 地心高度角（度）：观测点 (lat, lon) 看地下点在 (subLat, subLon) 的天体。
double geocentricAltitude(
  double lat,
  double lon,
  double subLat,
  double subLon,
) {
  const r = math.pi / 180;
  final s =
      math.sin(lat * r) * math.sin(subLat * r) +
      math.cos(lat * r) * math.cos(subLat * r) * math.cos((lon - subLon) * r);
  return math.asin(s.clamp(-1.0, 1.0)) / r;
}
