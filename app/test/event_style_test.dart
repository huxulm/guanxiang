import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/l10n/app_localizations.dart';
import 'package:guanxiang/src/event_style.dart';
import 'package:guanxiang/src/time_format.dart';
import 'package:guanxiang/src/tonight_card.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('倒计时按本地日历日算', () {
    final now = DateTime(2026, 11, 7, 23, 30);
    DateTime at(int d, int h) => DateTime(2026, 11, d, h).toUtc();
    expect(
      countdown(zh, at(7, 23).add(const Duration(minutes: 45)), now: now),
      '今天',
    );
    // 只差一小时，但已经是第二天
    expect(
      countdown(zh, at(8, 0).add(const Duration(minutes: 30)), now: now),
      '明天',
    );
    expect(countdown(zh, at(16, 10), now: now), '9 天后');
    expect(countdown(en, at(16, 10), now: now), 'in 9 days');
    expect(countdown(zh, at(7, 22), now: now), isNull);
  });

  test('多久以前', () {
    expect(timeAgo(zh, const Duration(seconds: 20)), '刚刚');
    expect(timeAgo(zh, const Duration(minutes: 42)), '42 分钟前');
    expect(timeAgo(zh, const Duration(minutes: 768)), '12 小时前');
    expect(timeAgo(en, const Duration(hours: 1)), '1 hour ago');
    expect(timeAgo(zh, const Duration(days: 3, hours: 5)), '3 天前');
  });

  test('今晚从本地中午起；凌晨 6 点前算前一晚', () {
    expect(tonightStart(DateTime(2026, 11, 7, 9)), DateTime(2026, 11, 7, 12));
    expect(tonightStart(DateTime(2026, 11, 7, 23)), DateTime(2026, 11, 7, 12));
    expect(tonightStart(DateTime(2026, 11, 7, 3)), DateTime(2026, 11, 6, 12));
    // 跨月
    expect(tonightStart(DateTime(2026, 12, 1, 1)), DateTime(2026, 11, 30, 12));
  });

  test('根数历元只留到分钟', () {
    expect(shortEpoch('2026-11-05T20:28:36.809184'), '2026-11-05 20:28');
    expect(shortEpoch('2026-11-05'), '2026-11-05');
  });
}
