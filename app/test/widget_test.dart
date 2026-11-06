import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/app.dart';
import 'package:guanxiang/src/theme.dart';
import 'package:guanxiang/src/time_format.dart';

void main() {
  test('星历 asset 是 1900–2100 的裁剪版，且文件存在', () {
    expect(ephemerisAsset, 'assets/de440s_1900_2100.bsp');
    final f = File(ephemerisAsset);
    expect(f.existsSync(), isTrue, reason: '按 app/README.md 生成裁剪星历');
    // 裁剪版约 22 MB；完整 de440s 约 33 MB
    expect(f.lengthSync(), inInclusiveRange(20e6, 24e6));
  });

  test('天文时刻格式化与本地时区转换', () {
    final dt = parseUtc('2026-03-03 11:33:45');
    expect(dt, isNotNull);
    expect(dt!.isUtc, isTrue);
    expect(dt.year, 2026);
    expect(dt.month, 3);
    expect(dt.day, 3);
    expect(dt.hour, 11);
    expect(dt.minute, 33);

    final formatted = formatAstroTime('2026-03-03 11:33:45');
    expect(formatted, contains('UTC'));
    expect(formatted, contains('11:33:45'), reason: '要精确到秒');

    final local = DateTime.utc(2026, 3, 3, 11, 33, 45).toLocal();
    expect(
      zoneLabel(local),
      matches(RegExp(r'^([A-Za-z]{2,5}|UTC[+-]\d+(:\d\d)?)$')),
    );
  });

  test('深空与红光夜间设计系统主题配置', () {
    final dark = AstroTheme.deepSpaceTheme;
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0B0E14));
    expect(dark.colorScheme.primary, const Color(0xFF569AFF));

    final red = AstroTheme.astroRedTheme;
    expect(red.brightness, Brightness.dark);
    expect(red.scaffoldBackgroundColor, const Color(0xFF0A0202));
    expect(red.colorScheme.primary, const Color(0xFFFF3B30));

    final light = AstroTheme.lightTheme;
    expect(light.brightness, Brightness.light);
  });
}
