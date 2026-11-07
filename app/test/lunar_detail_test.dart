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
}
