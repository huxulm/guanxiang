import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'rust/api/guanxiang.dart';
import 'theme.dart';

/// 各类天象的名称、图标、强调色（看板、搜索、结果列表共用）。

String kindLabel(AppLocalizations l, EventKind k) => switch (k) {
  EventKind.transit => l.kindTransit,
  EventKind.conjunction => l.kindConjunction,
  EventKind.opposition => l.kindOpposition,
  EventKind.appulse => l.kindAppulse,
  EventKind.solarEclipse => l.kindSolarEclipse,
  EventKind.lunarEclipse => l.kindLunarEclipse,
  EventKind.occultation => l.kindOccultation,
};

IconData kindIcon(EventKind k) => switch (k) {
  EventKind.solarEclipse => Icons.wb_sunny_outlined,
  EventKind.lunarEclipse => Icons.nightlight_outlined,
  EventKind.transit => Icons.trip_origin,
  EventKind.conjunction || EventKind.appulse => Icons.join_inner,
  EventKind.opposition => Icons.sync_alt,
  EventKind.occultation => Icons.brightness_3_outlined,
};

Color kindColor(BuildContext context, EventKind k) {
  final a = AstroAccents.of(context);
  return switch (k) {
    EventKind.solarEclipse || EventKind.lunarEclipse => a.eclipse,
    EventKind.transit => a.transit,
    EventKind.occultation => a.satellite,
    _ => a.conjunction,
  };
}

/// 带浅色底的事件图标（列表行首）。
class KindBadge extends StatelessWidget {
  const KindBadge({super.key, required this.kind, this.size = 36});

  final EventKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = kindColor(context, kind);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(kindIcon(kind), color: c, size: size * 0.55),
    );
  }
}

/// 距今多少天（按本地日历日算）：“今天 / 明天 / 9 天后”；已过去返回 null。
String? countdown(AppLocalizations l, DateTime utc, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final t = utc.toLocal();
  if (t.isBefore(n)) return null;
  // 用小时四舍五入，避开夏令时切换那天只有 23 小时的问题
  final days =
      (DateTime(
                t.year,
                t.month,
                t.day,
              ).difference(DateTime(n.year, n.month, n.day)).inHours /
              24)
          .round();
  return switch (days) {
    0 => l.today,
    1 => l.tomorrow,
    _ => l.inDays(days),
  };
}
