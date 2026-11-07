import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'event_detail_page.dart';
import 'layout.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'theme.dart';
import 'time_format.dart';

/// 首页“观象 · 近期看点”看板。
///
/// 提供今日天象概览、快捷探索入口、精选重磅天象前瞻，
/// 让普通爱好者与资深天文观测者都能一眼获得最核心的天象先机。
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

  /// 切换底部导航 Tab 的回调：0 看板, 1 搜索, 2 卫星, 3 设置
  final ValueChanged<int>? onSelectTab;

  /// 快捷预设搜索条件并切换至搜索页的回调
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
            // -----------------------------------------------------------------
            // 1. 今日时刻与测站状态卡片 (Hero Card)
            // -----------------------------------------------------------------
            _HeroCard(settings: settings, onTap: () => onSelectTab?.call(3)),
            const SizedBox(height: 12),

            // -----------------------------------------------------------------
            // 2. 观测太阳安全提示
            // -----------------------------------------------------------------
            Card(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.65),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sunSafetyNotice(lang: rustLang(context)),
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------------
            // 3. 快捷探索 (Quick Explore)
            // -----------------------------------------------------------------
            Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l.quickExplore,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildQuickExploreGrid(context, l, theme),
            const SizedBox(height: 24),

            // -----------------------------------------------------------------
            // 4. 精选重磅天象前瞻 (Curated Highlights)
            // -----------------------------------------------------------------
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  l.curatedHighlights,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _UpcomingEvents(engine: engine),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickExploreGrid(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
  ) {
    final accents = AstroAccents.of(context);
    final tiles = [
      _quickTile(
        context: context,
        theme: theme,
        icon: Icons.nightlight_outlined,
        iconColor: accents.eclipse,
        title: l.quickEclipses,
        desc: l.quickEclipsesDesc,
        onTap: () {
          onPresetSearch?.call(EventKind.solarEclipse);
          onSelectTab?.call(1);
        },
      ),
      _quickTile(
        context: context,
        theme: theme,
        icon: Icons.brightness_medium,
        iconColor: accents.conjunction,
        title: l.quickConjunctions,
        desc: l.quickConjunctionsDesc,
        onTap: () {
          onPresetSearch?.call(EventKind.conjunction);
          onSelectTab?.call(1);
        },
      ),
      _quickTile(
        context: context,
        theme: theme,
        icon: Icons.wb_sunny_outlined,
        iconColor: accents.transit,
        title: l.quickTransits,
        desc: l.quickTransitsDesc,
        onTap: () {
          onPresetSearch?.call(EventKind.transit);
          onSelectTab?.call(1);
        },
      ),
      _quickTile(
        context: context,
        theme: theme,
        icon: Icons.satellite_alt_outlined,
        iconColor: accents.satellite,
        title: l.quickSpaceStation,
        desc: l.quickSpaceStationDesc,
        onTap: () => onSelectTab?.call(2),
      ),
    ];
    // 宽屏两列，窄屏一列
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 640 ? 2 : 1;
        return Column(
          children: [
            for (var i = 0; i < tiles.length; i += cols) ...[
              if (i > 0) const SizedBox(height: 8),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + cols && j < tiles.length; j++) ...[
                      if (j > i) const SizedBox(width: 8),
                      Expanded(child: tiles[j]),
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

  Widget _quickTile({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: theme.colorScheme.outline,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
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
            Text(
              l.dashboardSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
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
                    padding: const EdgeInsets.symmetric(vertical: 2),
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
///
/// 内容全部来自计算核心（标题、摘要由 Rust 按语言生成），不写死任何日期或数值。
class _UpcomingEvents extends StatefulWidget {
  const _UpcomingEvents({required this.engine});

  final Engine engine;

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
        if (u.kind != UpdateKind.found || e == null) continue;
        final t = parseUtc(e.utc);
        if (t != null && t.isAfter(now)) out.add(e);
      }
      if (!mounted) break;
    }
    out.sort((a, b) => a.ttJd.compareTo(b.ttJd));
    return out.take(_maxItems).toList();
  }

  static Color _iconColor(AstroAccents a, EventKind k) => switch (k) {
    EventKind.solarEclipse || EventKind.lunarEclipse => a.eclipse,
    EventKind.transit => a.transit,
    _ => a.conjunction,
  };

  static IconData _icon(EventKind k) => switch (k) {
    EventKind.solarEclipse => Icons.wb_sunny_outlined,
    EventKind.lunarEclipse => Icons.nightlight_outlined,
    _ => Icons.brightness_medium,
  };

  static String _kindLabel(AppLocalizations l, EventKind k) => switch (k) {
    EventKind.transit => l.kindTransit,
    EventKind.conjunction => l.kindConjunction,
    EventKind.opposition => l.kindOpposition,
    EventKind.appulse => l.kindAppulse,
    EventKind.solarEclipse => l.kindSolarEclipse,
    EventKind.lunarEclipse => l.kindLunarEclipse,
    EventKind.occultation => l.kindOccultation,
  };

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
        const SizedBox(height: 8),
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
            return Column(
              children: [
                for (final e in items)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _icon(e.kind),
                        color: _iconColor(AstroAccents.of(context), e.kind),
                      ),
                      title: Text(e.title),
                      subtitle: Text(
                        '${_kindLabel(l, e.kind)} · '
                        '${formatAstroTime(e.utc, showUtc: false)}\n'
                        '${e.summary}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EventDetailPage(event: e),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
