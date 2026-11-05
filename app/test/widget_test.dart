import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/app.dart';

void main() {
  test('星历 asset 是 1900–2100 的裁剪版，且文件存在', () {
    expect(ephemerisAsset, 'assets/de440s_1900_2100.bsp');
    final f = File(ephemerisAsset);
    expect(f.existsSync(), isTrue, reason: '按 app/README.md 生成裁剪星历');
    // 裁剪版约 22 MB；完整 de440s 约 33 MB
    expect(f.lengthSync(), inInclusiveRange(20e6, 24e6));
  });
}
