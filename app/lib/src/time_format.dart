/// 天文时刻格式化与时区转换工具。
///
/// 观象核心输出的时刻均为 UTC。为了提供商用级体验，界面默认优先以本地时区展示，
/// 同时保留 UTC 辅助标注，让用户一目了然。
library;

/// 解析形如 "2026-03-03 11:33:45" 或 "2026-03-03T11:33:45" 的 UTC 字符串。
DateTime? parseUtc(String utcStr) {
  final clean = utcStr.trim().replaceFirst(' ', 'T');
  if (clean.isEmpty) return null;
  final iso = clean.endsWith('Z') ? clean : '${clean}Z';
  return DateTime.tryParse(iso);
}

/// 格式化天文事件时刻为本地时区时间（附带本地时区名称与 UTC 时间对比）。
///
/// 例如："2026-03-03 19:33 CST (11:33 UTC)"
String formatAstroTime(String utcStr, {bool showUtc = true}) {
  final dt = parseUtc(utcStr);
  if (dt == null) return utcStr;
  final local = dt.toLocal();

  String two(int v) => v.toString().padLeft(2, '0');
  final localStr =
      '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  final tz = local.timeZoneName;

  if (!showUtc) return '$localStr $tz';
  final utcTimeOnly = '${two(dt.hour)}:${two(dt.minute)}';
  return '$localStr $tz · $utcTimeOnly UTC';
}

/// 获取相对于现在的天数差，若在今天则返回 0，明天返回 1，昨天返回 -1。
int daysFromNow(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(dt.year, dt.month, dt.day);
  return target.difference(today).inDays;
}
