/// 天文时刻格式化与时区转换。
///
/// 计算核心输出的时刻都是 UTC。界面先显示本地时间，再附上 UTC，都精确到秒
/// （卫星凌日凌月往往不到 1 秒，不能省掉秒）。
library;

/// 解析形如 "2026-03-03 11:33:45" 或 "2026-03-03T11:33:45" 的 UTC 字符串。
DateTime? parseUtc(String utcStr) {
  final clean = utcStr.trim().replaceFirst(' ', 'T');
  if (clean.isEmpty) return null;
  final iso = clean.endsWith('Z') ? clean : '${clean}Z';
  return DateTime.tryParse(iso);
}

String _two(int v) => v.toString().padLeft(2, '0');

String _hms(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// 本地时区的简短标签：系统给的缩写够短（如 CST、JST）就用缩写，
/// 否则（Windows 上是“中国标准时间”这样的全称）用 UTC 偏移，如 UTC+8、UTC+5:30。
String zoneLabel(DateTime local) {
  final name = local.timeZoneName;
  if (RegExp(r'^[A-Za-z]{2,5}$').hasMatch(name)) return name;
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final m = off.inMinutes.abs();
  final mm = m % 60;
  return 'UTC$sign${m ~/ 60}${mm == 0 ? '' : ':${_two(mm)}'}';
}

/// 把 UTC 时刻格式化成本地时间，附 UTC 时刻。
///
/// 例如："2026-03-03 19:33:42 CST · 11:33:42 UTC"。本地就是 UTC 时只写一次。
String formatAstroTime(String utcStr, {bool showUtc = true}) {
  final dt = parseUtc(utcStr);
  if (dt == null) return utcStr;
  if (dt.toLocal().timeZoneOffset == Duration.zero) {
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_hms(dt)} UTC';
  }
  final local = dt.toLocal();
  final localStr =
      '${local.year}-${_two(local.month)}-${_two(local.day)} ${_hms(local)} '
      '${zoneLabel(local)}';
  if (!showUtc) return localStr;
  return '$localStr · ${_hms(dt)} UTC';
}
