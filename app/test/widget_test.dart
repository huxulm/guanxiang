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

    // 红光模式保护暗适应：所有颜色都必须以红色分量为主（绿、蓝不超过红的 40%），
    // 包括 Material 组件会用到的容器色和各类天象的强调色
    final red = AstroTheme.astroRedTheme;
    expect(red.brightness, Brightness.dark);
    final cs = red.colorScheme;
    final accents = red.extension<AstroAccents>()!;
    final colors = <String, Color>{
      'background': red.scaffoldBackgroundColor,
      'primary': cs.primary,
      'primaryContainer': cs.primaryContainer,
      'onPrimaryContainer': cs.onPrimaryContainer,
      'secondary': cs.secondary,
      'secondaryContainer': cs.secondaryContainer,
      'onSecondaryContainer': cs.onSecondaryContainer,
      'tertiary': cs.tertiary,
      'error': cs.error,
      'errorContainer': cs.errorContainer,
      'onErrorContainer': cs.onErrorContainer,
      'surface': cs.surface,
      'surfaceContainer': cs.surfaceContainer,
      'surfaceContainerHigh': cs.surfaceContainerHigh,
      'onSurface': cs.onSurface,
      'onSurfaceVariant': cs.onSurfaceVariant,
      'outline': cs.outline,
      'eclipse': accents.eclipse,
      'conjunction': accents.conjunction,
      'transit': accents.transit,
      'satellite': accents.satellite,
    };
    colors.forEach((name, c) {
      expect(c.g, lessThanOrEqualTo(c.r * 0.4), reason: name);
      expect(c.b, lessThanOrEqualTo(c.r * 0.4), reason: name);
    });

    final light = AstroTheme.lightTheme;
    expect(light.brightness, Brightness.light);
  });
}
