import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/lunar_eclipse_detail.dart';
import 'package:guanxiang/src/rust/api/guanxiang.dart';
import 'package:guanxiang/src/world_map.dart';

void main() {
  test('地心高度角', () {
    expect(geocentricAltitude(0, 0, 0, 0), closeTo(90, 1e-9));
    expect(geocentricAltitude(0, 90, 0, 0), closeTo(0, 1e-9));
    expect(geocentricAltitude(0, 180, 0, 0), closeTo(-90, 1e-9));
    expect(geocentricAltitude(40, 0, 10, 0), closeTo(60, 1e-9));
  });

  test('地平圈上每一点的高度都是 0', () {
    for (final (lat, lon) in [(-6.0, 87.0), (23.4, -170.0), (0.0, 0.0)]) {
      final pts = horizonCircle(lat, lon);
      expect(pts, hasLength(181));
      for (final (a, b) in pts) {
        expect(geocentricAltitude(a, b, lat, lon), closeTo(0, 1e-9));
      }
    }
  });

  test('投影：中心经度在正中，跨 180° 的折线不折回', () {
    final p = MapProjection(const Size(360, 180), 150);
    expect(p.at(0, 150), const Offset(180, 90));
    expect(p.at(90, 150).dy, 0);
    // 中心 150°E 时，170°W（= 190°E）在中线以东 40°
    expect(p.at(0, -170).dx, closeTo(220, 1e-9));
    final b = p.polyline([(0.0, 170.0), (0.0, -170.0)]).getBounds();
    expect(b.width, closeTo(20, 1e-9)); // 170°E 到 170°W 只隔 20°
  });

  test('月食可见区域分区', () {
    EclipsePhase ph(String code, double lat, double lon) => EclipsePhase(
      code: code,
      name: code,
      utc: '2025-09-07 18:00:00',
      sublunar: GeoPoint(latitudeDeg: lat, longitudeDeg: lon),
    );
    // 月下点从 0° 向西移到 30°W
    final (rows, cols, zones) = lunarVisibilityGrid([
      ph('U1', 0, 0),
      ph('Max', 0, -15),
      ph('U4', 0, -30),
    ]);
    expect((rows, cols), (90, 180));
    LunarZone at(double lat, double lon) =>
        zones[((90 - lat) / 2).floor() * cols + ((lon + 180) / 2).floor()];
    expect(at(1, -15), LunarZone.full);
    expect(at(1, 179), LunarZone.hidden);
    expect(at(1, 81), LunarZone.sets); // 初亏时在地平线上，复圆时已落下
    expect(at(1, -101), LunarZone.rises); // 初亏时还没升起
  });

  test('陆地数据：坐标在范围内、多边形足够', () {
    final j =
        jsonDecode(File('assets/geo/land_110m.json').readAsStringSync()) as Map;
    final scale = j['scale'] as int;
    final rings = j['rings'] as List;
    expect(rings.length, greaterThan(100));
    for (final r in rings) {
      final v = (r as List).cast<int>();
      expect(v.length.isEven, isTrue);
      for (var i = 0; i < v.length; i += 2) {
        expect(v[i].abs(), lessThanOrEqualTo(180 * scale));
        expect(v[i + 1].abs(), lessThanOrEqualTo(90 * scale));
      }
    }
  });
}
