import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/l10n/app_localizations.dart';
import 'package:guanxiang/src/errors.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('Rust 错误只保留第一段', () {
    final e = AnyhowException('结束年份必须晚于起始年份\n\nStack backtrace:\n   0: foo');
    expect(describeError(e, zh), '结束年份必须晚于起始年份');
    final c = AnyhowException('星表中找不到 xyz\n\nCaused by:\n    bar');
    expect(describeError(c, zh), '星表中找不到 xyz');
  });

  test('网络错误按语言', () {
    expect(describeError(const SocketException('x'), zh), contains('网络不可用'));
    expect(
      describeError(const SocketException('x'), en),
      'No network connection',
    );
    expect(describeError(TimeoutException('x'), zh), contains('超时'));
    expect(describeError(TimeoutException('x'), en), contains('timed out'));
  });

  test('年份范围', () {
    const r = YearRange(1900, 2101);
    // 结束年包含在内
    expect(r.check(zh, 2026, 2055), isNull);
    expect(r.check(zh, 1900, 2100), isNull);
    expect(r.check(zh, 2030, 2030), isNull);
    expect(r.check(zh, 1900, 2101), contains('1900–2100'));
    expect(r.check(zh, 1850, 1900), contains('1900–2100'));
    expect(r.check(en, 2090, 2120), contains('1900–2100'));
    expect(r.check(zh, 2030, 2029), contains('早于'));
    expect(r.check(en, 2030, 2029), contains('before'));
    expect(r.check(zh, null, 2030), isNotNull);
  });

  test('中英文 ARB 的键一致', () {
    final zhArb = File('lib/l10n/app_zh.arb').readAsStringSync();
    final enArb = File('lib/l10n/app_en.arb').readAsStringSync();
    // 只比较顶层的消息键（去掉 @ 开头的元数据）
    Set<String> keys(String s) => (jsonDecode(s) as Map<String, dynamic>).keys
        .where((k) => !k.startsWith('@'))
        .toSet();
    expect(keys(enArb), keys(zhArb));
  });
}
