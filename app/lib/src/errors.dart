import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

import '../l10n/app_localizations.dart';

/// 把异常整理成给用户看的一句话。
///
/// Rust 端的 `anyhow::Error` 到了 Dart 是 [AnyhowException]，消息里可能带原因链和调用栈，
/// 这里只保留第一段（桥接层已按语言输出；core 内部错误目前只有中文）。
String describeError(Object e, AppLocalizations l) {
  return switch (e) {
    AnyhowException(:final message) => _firstParagraph(message),
    PanicException(:final message) => l.errInternal(_firstParagraph(message)),
    SocketException() => l.errNetwork,
    TimeoutException() => l.errTimeout,
    HttpException(:final message) => l.errHttp(message),
    FormatException(:final message) => l.errFormat(message),
    _ => '$e',
  };
}

String _firstParagraph(String s) {
  var t = s.trim();
  for (final marker in [
    '\n\nCaused by',
    '\n\nStack backtrace',
    '\nStack backtrace',
  ]) {
    final i = t.indexOf(marker);
    if (i >= 0) t = t.substring(0, i);
  }
  return t.trim();
}

/// 星历覆盖的可搜索年份 `[from, toExclusive)`，以及检查用户输入的年份范围。
class YearRange {
  const YearRange(this.from, this.toExclusive);

  final int from;
  final int toExclusive;

  /// 返回 null 表示有效，否则是错误提示。
  String? check(AppLocalizations l, int? start, int? endExclusive) {
    if (start == null || endExclusive == null) return l.enterYears;
    if (endExclusive <= start) return l.endAfterStart;
    if (start < from || endExclusive > toExclusive) {
      return l.yearsOutOfRange(from, toExclusive - 1);
    }
    return null;
  }
}
