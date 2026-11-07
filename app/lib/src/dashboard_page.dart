import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'event_detail_page.dart';
import 'event_style.dart';
import 'layout.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'theme.dart';
import 'time_format.dart';
import 'tonight_card.dart';

/// 首页看板：当前时间和观测地、观测太阳的安全提示、近期天象（本机计算）、快捷入口。
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.engine,
    required this.settings,
    this.onSelectTab,
    this.onPresetSearch,
  });

  final Engine engine;
  final Settings settings;

  /// 切换导航页的回调：0 看板, 1 搜索, 2 卫星, 3 设置
  final ValueChanged<int>? onSelectTab;

  /// 预设搜索条件并切到搜索页的回调
  final void Function(EventKind kind, {int? fromYear, int? toYear})?
  onPresetSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.dashboardTitle)),
      body: SafeArea(
        child: ContentListView(
          top: 8,
          bottom: 24,
          children: [
            _HeroCard(settings: settings, onTap: () => onSelectTab?.call(3)),
            const SizedBox(height: 12),
            TonightCard(
              engine: engine,
              settings: settings,
              onSetLocation: () => onSelectTab?.call(3),
            ),
            const SizedBox(height: 12),
            _SafetyCard(text: sunSafetyNotice(lang: rustLang(context))),
            const SizedBox(height: 20),
            _SectionTitle(
              icon: Icons.auto_awesome,
              color: theme.colorScheme.tertiary,
              text: l.curatedHighlights,
            ),
            const SizedBox(height: 6),
            _UpcomingEvents(engine: engine, settings: settings),
            const SizedBox(height: 24),
            _SectionTitle(
              icon: Icons.grid_view_rounded,
              color: theme.colorScheme.primary,
              text: l.quickExplore,
            ),
            const SizedBox(height: 10),
            _quickExplore(context, l),
          ],
        ),
      ),
    );
  }

  Widget _quickExplore(BuildContext context, AppLocalizations l) {
    final a = AstroAccents.of(context);
    void search(EventKind k) {
      onPresetSearch?.call(k);
      onSelectTab?.call(1);
    }

    final tiles = [
      _QuickTile(
        icon: Icons.nightlight_outlined,
        color: a.eclipse,
        title: l.quickEclipses,
        desc: l.quickEclipsesDesc,
        onTap: () => search(EventKind.solarEclipse),
      ),
      _QuickTile(
        icon: Icons.join_inner,
        color: a.conjunction,
        title: l.quickConjunctions,
        desc: l.quickConjunctionsDesc,
        onTap: () => search(EventKind.conjunction),
      ),
      _QuickTile(
        icon: Icons.trip_origin,
        color: a.transit,
        title: l.quickTransits,
        desc: l.quickTransitsDesc,
        onTap: () => search(EventKind.transit),
      ),
      _QuickTile(
        icon: Icons.satellite_alt_outlined,
        color: a.satellite,
        title: l.quickSpaceStation,
        desc: l.quickSpaceStationDesc,
        onTap: () => onSelectTab?.call(2),
      ),
    ];
    // 手机两列，宽屏四列
    return _Grid(columns: (w) => w >= 720 ? 4 : 2, children: tiles);
  }
}

/// 等高的网格：每行 [columns] 个，最后一行不足时留空位。
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int Function(double width) columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = columns(box.maxWidth);
      return Column(
        children: [
          for (var i = 0; i < children.length; i += cols) ...[
            if (i > 0) const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + cols; j++) ...[
                    if (j > i) const SizedBox(width: 8),
                    Expanded(
                      child: j < children.length
                          ? children[j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer.withValues(alpha: 0.65),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: cs.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 快捷入口：图标在上，标题和一两行说明在下。
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 当前时间和观测地。时间每 20 秒刷新一次（页面一直保留在 IndexedStack 里）。
class _HeroCard extends StatefulWidget {
  const _HeroCard({required this.settings, required this.onTap});

  final Settings settings;
  final VoidCallback onTap;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final now = _now;
    final utc = now.toUtc();
    final localTimeStr =
        '${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)} ${zoneLabel(now)}';
    final utcTimeStr = '${_two(utc.hour)}:${_two(utc.minute)} UTC';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  localTimeStr,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    utcTimeStr,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: widget.settings,
              builder: (context, _) {
                final s = widget.settings;
                final String desc;
                if (s.mode == LocationMode.manual) {
                  desc = '${l.locationManual} · ${s.manual.describe()}';
                } else {
                  final fix = s.gpsFix;
                  desc = fix == null
                      ? '${l.locationGps} · ${l.gpsLocateOnSearch}'
                      : '${l.locationGps} · ${fix.describe()}';
                }
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${l.currentLocation} · $desc',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 近期天象：用本机星历算接下来一年多的日月食和亮行星相合，按时间排序取前几条。
/// 肉眼几乎看不出的（半影月食）不列。
///
/// 内容全部来自计算核心（标题、摘要由 Rust 按语言生成），不写死任何日期或数值。
class _UpcomingEvents extends StatefulWidget {
  const _UpcomingEvents({required this.engine, required this.settings});

  final Engine engine;
  final Settings settings;

  @override
  State<_UpcomingEvents> createState() => _UpcomingEventsState();
}

class _UpcomingEventsState extends State<_UpcomingEvents> {
  /// 亮行星两两组合（不含水星：离太阳太近，不好看）
  static const _pairs = [
    ('venus', 'mars'),
    ('venus', 'jupiter'),
    ('venus', 'saturn'),
    ('mars', 'jupiter'),
    ('mars', 'saturn'),
    ('jupiter', 'saturn'),
  ];
  static const _maxPairDeg = 3.0;
  static const _maxItems = 6;

  Lang? _lang;
  Future<List<EventItem>>? _future;
  CancelToken? _token;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = rustLang(context);
    if (lang != _lang) {
      _lang = lang;
      _token?.cancel();
      final token = CancelToken();
      _token = token;
      _future = _load(lang, token);
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<List<EventItem>> _load(Lang lang, CancelToken token) async {
    final now = DateTime.now().toUtc();
    final years = widget.engine.coverageYears();
    // 年份区间 [from, to)：今年和明年，保证至少覆盖未来 12 个月
    final from = now.year;
    final to = min(now.year + 2, years[1]);
    if (from >= to) return [];
    final requests = [
      for (final k in [EventKind.solarEclipse, EventKind.lunarEclipse])
        SearchRequest(
          kind: k,
          bodyA: '',
          bodyB: '',
          fromYear: from,
          toYear: to,
          maxSeparationDeg: 0,
          lang: lang,
        ),
      for (final (a, b) in _pairs)
        SearchRequest(
          kind: EventKind.appulse,
          bodyA: a,
          bodyB: b,
          fromYear: from,
          toYear: to,
          maxSeparationDeg: _maxPairDeg,
          lang: lang,
        ),
    ];
    final out = <EventItem>[];
    // 逐个搜索，不和用户手动发起的搜索抢 CPU
    for (final r in requests) {
      await for (final u in search(
        engine: widget.engine,
        request: r,
        token: token,
      )) {
        final e = u.item;
        if (u.kind != UpdateKind.found || e == null || e.subtle) continue;
        final t = parseUtc(e.utc);
        if (t != null && t.isAfter(now)) out.add(e);
      }
      if (!mounted) break;
    }
    out.sort((a, b) => a.ttJd.compareTo(b.ttJd));
    return out.take(_maxItems).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.upcomingHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<EventItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(
                describeError(snap.error!, l),
                style: TextStyle(color: theme.colorScheme.error),
              );
            }
            if (!snap.hasData) {
              return Row(
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(l.upcomingLoading),
                ],
              );
            }
            final items = snap.data!;
            if (items.isEmpty) return Text(l.upcomingNone);
            return _Grid(
              columns: (w) => w >= 720 ? 2 : 1,
              children: [
                for (final e in items)
                  UpcomingEventCard(
                    event: e,
                    engine: widget.engine,
                    settings: widget.settings,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 近期天象的一条：类型图标、标题、本地时间、摘要，右侧是倒计时。
class UpcomingEventCard extends StatelessWidget {
  const UpcomingEventCard({
    super.key,
    required this.event,
    this.engine,
    this.settings,
  });

  final EventItem event;

  /// 打开详情页时用来画日月食示意图
  final Engine? engine;

  /// 打开月食详情时用其中的观测地
  final Settings? settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final t = parseUtc(event.utc);
    final left = t == null ? null : countdown(l, t);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailPage(
              event: event,
              engine: engine,
              settings: settings,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KindBadge(kind: event.kind),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatAstroTime(event.utc, showUtc: false),
                      style: muted,
                    ),
                    Text(event.summary, style: muted),
                  ],
                ),
              ),
              if (left != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    left,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
