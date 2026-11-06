import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/gcj02.dart';

/// 两点间的近似距离（米）
double _meters((double, double) a, (double, double) b) {
  const r = 6371000.0;
  final dLat = (b.$1 - a.$1) * math.pi / 180;
  final dLon = (b.$2 - a.$2) * math.pi / 180 * math.cos(a.$1 * math.pi / 180);
  return r * math.sqrt(dLat * dLat + dLon * dLon);
}

void main() {
  test('境外不变', () {
    expect(wgs84ToGcj02(37.422, -122.084), (37.422, -122.084));
    expect(wgs84ToGcj02(51.5, -0.12), (51.5, -0.12));
  });

  test('天安门：与公开的对照值相差不到 1 米', () {
    // 常用对照：WGS-84 (39.908692, 116.397477) ≈ GCJ-02 (39.910093, 116.403718)
    final g = wgs84ToGcj02(39.908692, 116.397477);
    expect(_meters(g, (39.910093, 116.403718)), lessThan(1.0));
  });

  test('国内各地偏移在 100–800 米之间', () {
    for (final p in [
      (25.04, 102.7),
      (31.23, 121.47),
      (43.83, 87.62),
      (22.3, 114.17),
      (45.75, 126.65),
    ]) {
      final d = _meters(p, wgs84ToGcj02(p.$1, p.$2));
      expect(d, inInclusiveRange(100, 800), reason: '$p');
    }
  });
}
