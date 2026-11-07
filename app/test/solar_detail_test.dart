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
}
