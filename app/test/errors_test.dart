import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/errors.dart';

void main() {
  test('Rust 错误只保留第一段', () {
    final e = AnyhowException('结束年份必须晚于起始年份\n\nStack backtrace:\n   0: foo');
    expect(describeError(e), '结束年份必须晚于起始年份');
    final c = AnyhowException('星表中找不到 xyz\n\nCaused by:\n    bar');
    expect(describeError(c), '星表中找不到 xyz');
  });

  test('网络错误', () {
    expect(describeError(const SocketException('x')), contains('网络不可用'));
    expect(describeError(TimeoutException('x')), contains('超时'));
  });

  test('年份范围', () {
    const r = YearRange(1900, 2101);
    expect(r.check(2026, 2056), isNull);
    expect(r.check(1900, 2101), isNull);
    expect(r.check(1850, 1900), contains('1900–2100'));
    expect(r.check(2090, 2120), contains('1900–2100'));
    expect(r.check(2030, 2030), contains('晚于'));
    expect(r.check(null, 2030), isNotNull);
  });
}
