import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/licenses.dart';

void main() {
  test('解析许可声明格式', () {
    final blocks = parseNotices(
      '@@ a 1.0, b 2.0\nMIT\n\ntext\n@@ c 3.0\nApache\n',
    );
    expect(blocks.length, 2);
    expect(blocks[0].packages, ['a 1.0', 'b 2.0']);
    expect(blocks[0].text, 'MIT\n\ntext');
    expect(blocks[1].packages, ['c 3.0']);
  });

  test('rust.txt 包含关键依赖，且没有空文本', () {
    final text = File(rustNoticesAsset).readAsStringSync();
    final blocks = parseNotices(text);
    final all = blocks.expand((b) => b.packages).join(' ');
    for (final name in [
      'anise',
      'sofars',
      'sgp4',
      'flutter_rust_bridge',
      'hifitime',
    ]) {
      expect(all, contains('$name '), reason: name);
    }
    expect(blocks.every((b) => b.text.isNotEmpty), isTrue);
    expect(text, contains('MPL-2.0'));
  });

  test('致谢提到 SOFA 和数据来源', () {
    for (final s in [
      'SOFA',
      'DE440',
      'Hipparcos',
      'CelesTrak',
      'OpenStreetMap',
      'USNO',
    ]) {
      expect(acknowledgements, contains(s));
    }
  });
}
