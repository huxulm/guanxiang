import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/l10n/app_localizations.dart';
import 'package:guanxiang/src/eclipse_timeline.dart';
import 'package:guanxiang/src/rust/api/guanxiang.dart';
import 'package:guanxiang/src/solar_eclipse_detail.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('全食时长写到秒', () {
    expect(formatSeconds(zh, 381.4), '6 分 21 秒');
    expect(formatSeconds(en, 58.6), '0 min 59 s');
  });

  test('方位名称', () {
    expect(compassName(zh, 191), '南');
    expect(compassName(en, 225), 'SW');
  });

  test('每种情况都有文字', () {
    for (final v in SolarVisibility.values) {
      expect(solarVisibilityText(zh, v), isNotEmpty);
      expect(solarVisibilityText(en, v), isNotEmpty);
    }
    for (final k in LocalEclipseKind.values) {
      expect(solarKindText(zh, k), isNotEmpty);
    }
  });

  test('地平线下的时段：线性插值找零点', () {
    DateTime at(int m) => DateTime.utc(2027, 8, 2, 16, m);
    // 先在地平线下，16:15 升起，16:45 落下
    final below = belowHorizonIntervals(
      [at(0), at(10), at(20), at(30), at(40), at(50)],
      [-3, -1, 1, 3, 1, -1],
    );
    expect(below, [(at(0), at(15)), (at(45), at(50))]);
    expect(belowHorizonIntervals([at(0), at(10)], [5, 6]), isEmpty);
  });
  SolarDiskPoint pt(double s, double x, double z) => SolarDiskPoint(
    seconds: s,
    xArcmin: x,
    yArcmin: 0,
    sunRadiusArcmin: 15.8,
    moonRadiusArcmin: 16.6,
    obscuration: s / 100,
    sunAltitudeDeg: 50,
    zenithAngleDeg: z,
  );
  SolarPhase ph(String code, String utc) => SolarPhase(
    code: code,
    name: code,
    utc: utc,
    sun: const SunPoint(altitudeDeg: 50, azimuthDeg: 180),
  );
  final view = LocalSolarView(
    verdict: SolarVisibility.full,
    kind: LocalEclipseKind.total,
    magnitude: 1.03,
    obscuration: 1,
    phases: [
      ph('C1', '2027-08-02 08:40:00'),
      ph('C2', '2027-08-02 10:02:00'),
      ph('Max', '2027-08-02 10:05:00'),
      ph('C3', '2027-08-02 10:08:00'),
      ph('C4', '2027-08-02 11:26:00'),
    ],
    trackStartUtc: '2027-08-02 08:30:00.000',
    track: [pt(0, -30, 170), pt(60, -20, -170), pt(100, 0, -160)],
  );

  test('太阳面轨迹插值：天顶位置角跨 ±180° 按近的一侧', () {
    final s = SolarTrackSampler(view);
    expect(s.start, DateTime.utc(2027, 8, 2, 8, 30));
    expect(s.end, DateTime.utc(2027, 8, 2, 8, 31, 40));
    final p = s.at(DateTime.utc(2027, 8, 2, 8, 30, 30));
    expect(p.xArcmin, closeTo(-25, 1e-9));
    expect(p.obscuration, closeTo(0.3, 1e-9));
    expect(p.zenithAngleDeg, closeTo(180, 1e-9));
    expect(s.at(DateTime.utc(2027, 8, 2, 9)).xArcmin, 0);
  });

  test('日食阶段', () {
    String at(int h, int m) =>
        solarStateText(zh, view, DateTime.utc(2027, 8, 2, h, m));
    expect(at(8, 0), '日食还没开始');
    expect(at(9, 0), '偏食中');
    expect(at(10, 5), '全食中');
    expect(at(12, 0), '日食已结束');
  });
}
