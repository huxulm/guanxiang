import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/l10n/app_localizations.dart';
import 'package:guanxiang/src/lunar_eclipse_detail.dart';
import 'package:guanxiang/src/rust/api/guanxiang.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('持续时间按分钟四舍五入', () {
    expect(formatDuration(zh, 82.1), '1 小时 22 分');
    expect(formatDuration(en, 209.4), '3 h 29 min');
    expect(formatDuration(zh, 47.6), '48 分钟');
    expect(formatDuration(en, 59.6), '1 h 0 min');
  });

  test('16 方位', () {
    expect(zh.compassPoints.split(' '), hasLength(16));
    expect(en.compassPoints.split(' '), hasLength(16));
    expect(compassPoint(zh, 0), '北 0°');
    expect(compassPoint(zh, 132), '东南 132°');
    expect(compassPoint(en, 359.7), 'N 0°');
    expect(compassPoint(en, 11.2), 'N 11°');
    expect(compassPoint(en, 11.3), 'NNE 11°');
    expect(compassPoint(en, 247.5), 'WSW 248°');
  });

  test('天色按太阳高度分档', () {
    expect(skyText(zh, 10), '白天');
    expect(skyText(zh, -0.5), '白天');
    expect(skyText(zh, -6), '晨昏');
    expect(skyText(zh, -18.5), '夜间');
  });

  test('本地时刻跨日时带日期', () {
    final ref = DateTime(2025, 9, 7, 23, 50);
    expect(localClock(DateTime(2025, 9, 7, 23, 59, 5), ref), '23:59:05');
    expect(
      localClock(DateTime(2025, 9, 8, 0, 3, 9), ref, seconds: false),
      '9/8 00:03',
    );
  });

  test('每种可见情况都有文字', () {
    for (final v in LunarVisibility.values) {
      expect(visibilityText(zh, v), isNotEmpty);
      expect(visibilityText(en, v), isNotEmpty);
    }
  });

  const diagram = LunarEclipseDiagram(
    penumbraDeg: 1.2,
    umbraDeg: 0.7,
    moonSemidiameterDeg: 0.25,
    path: [
      DiagramPoint(x: -1, y: 0.5, utc: '2025-09-07 16:00:00', label: ''),
      DiagramPoint(x: 0, y: 0, utc: '2025-09-07 16:10:00', label: ''),
      DiagramPoint(x: 1, y: -0.5, utc: '2025-09-07 16:20:00', label: ''),
    ],
    marks: [],
  );

  test('轨迹按时刻插值，两端截断', () {
    final s = TrackSampler(diagram, [-10, 0, 20]);
    DateTime at(int m, [int sec = 0]) => DateTime.utc(2025, 9, 7, 16, m, sec);
    expect(s.start, at(0));
    expect(s.end, at(20));
    expect(s.positionAt(at(5)), const Offset(-0.5, 0.25));
    expect(s.positionAt(at(15)), const Offset(0.5, -0.25));
    expect(s.positionAt(DateTime.utc(2025, 9, 7, 15)), const Offset(-1, 0.5));
    expect(s.positionAt(DateTime.utc(2025, 9, 7, 17)), const Offset(1, -0.5));
    expect(s.altitudeAt(at(5)), -5);
    expect(s.altitudeAt(at(12, 30)), 5);
    expect(TrackSampler(diagram, null).altitudeAt(at(5)), isNull);
    // 高度数组和轨迹长度不一致时不插值
    expect(TrackSampler(diagram, [1, 2]).altitudeAt(at(5)), isNull);
  });

  test('此刻所处阶段，边界算在阶段内', () {
    EclipsePhase ph(String code, String utc) => EclipsePhase(
      code: code,
      name: code,
      utc: utc,
      sublunar: const GeoPoint(latitudeDeg: 0, longitudeDeg: 0),
    );
    final phases = [
      ph('P1', '2025-09-07 15:28:00'),
      ph('U1', '2025-09-07 16:27:00'),
      ph('U2', '2025-09-07 17:30:00'),
      ph('Max', '2025-09-07 18:11:00'),
      ph('U3', '2025-09-07 18:52:00'),
      ph('U4', '2025-09-07 19:56:00'),
      ph('P4', '2025-09-07 20:55:00'),
    ];
    String at(int h, int m) =>
        lunarStateText(zh, phases, DateTime.utc(2025, 9, 7, h, m));
    expect(at(15, 0), '月食还没开始');
    expect(at(15, 28), '半影食中');
    expect(at(16, 27), '偏食中');
    expect(at(17, 30), '全食中');
    expect(at(18, 52), '全食中');
    expect(at(19, 0), '偏食中');
    expect(at(20, 0), '半影食中');
    expect(at(21, 0), '月食已结束');
    // 半影月食只有 P1、P4
    final penumbral = [phases.first, phases[3], phases.last];
    expect(
      lunarStateText(en, penumbral, DateTime.utc(2025, 9, 7, 18)),
      'Penumbral phase',
    );
  });
}
