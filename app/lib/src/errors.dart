import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

/// 把异常整理成给用户看的一句话。
///
/// Rust 端的 `anyhow::Error` 到了 Dart 是 [AnyhowException]，消息里可能带原因链和调用栈，
/// 这里只保留第一段（core 的错误信息本身就是中文短句）。
String describeError(Object e) {
  return switch (e) {
    AnyhowException(:final message) => _firstParagraph(message),
    PanicException(:final message) => '内部错误：${_firstParagraph(message)}',
    SocketException() => '网络不可用，请检查网络连接',
    TimeoutException() => '请求超时，请稍后再试',
    HttpException(:final message) => '网络请求失败：$message',
    FormatException(:final message) => '数据格式错误：$message',
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
  String? check(int? start, int? endExclusive) {
    if (start == null || endExclusive == null) return '请输入起止年份';
    if (endExclusive <= start) return '结束年份必须晚于起始年份';
    if (start < from || endExclusive > toExclusive) {
      return '内置星历只覆盖 $from–${toExclusive - 1} 年，请在这个范围内搜索';
    }
    return null;
  }
}
