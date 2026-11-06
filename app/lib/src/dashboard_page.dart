import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';

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

  /// 切换底部导航 Tab 的回调：0 看板, 1 搜索, 2 空间站, 3 设置
  final ValueChanged<int>? onSelectTab;

  /// 快捷预设搜索条件并切换至搜索页的回调
  final void Function(EventKind kind, {int? fromYear, int? toYear})?
  onPresetSearch;

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final utc = now.toUtc();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.dashboardTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: l.navSettings,
            onPressed: () => onSelectTab?.call(3),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // -----------------------------------------------------------------
            // 1. 今日时刻与测站状态卡片 (Hero Card)
            // -----------------------------------------------------------------
            _buildHeroStatusCard(context, now, utc, l, theme),
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
                  Icons.explore,
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
                  color: theme.colorScheme.secondary,
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
            _buildCuratedHighlights(context, l, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStatusCard(
    BuildContext context,
    DateTime now,
    DateTime utc,
    AppLocalizations l,
    ThemeData theme,
  ) {
    final localTimeStr =
        '${now.year}-${_two(now.month)}-${_two(now.day)} ${_two(now.hour)}:${_two(now.minute)}';
    final utcTimeStr = '${_two(utc.hour)}:${_two(utc.minute)} UTC';
    final tz = now.timeZoneName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$localTimeStr $tz',
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
                      fontFamily: 'monospace',
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
              listenable: settings,
              builder: (context, _) {
                final isGps = settings.mode == LocationMode.gps;
                final fix = settings.gpsFix;
                final manual = settings.manual;
                final desc = isGps
                    ? (fix == null
                          ? l.gpsNoFix
                          : 'GPS · ${fix.lat.toStringAsFixed(2)}°N, ${fix.lon.toStringAsFixed(2)}°E')
                    : '手动 · ${manual.lat.toStringAsFixed(2)}°N, ${manual.lon.toStringAsFixed(2)}°E';

                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelectTab?.call(3),
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
                            '${l.currentLocation}：$desc',
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

  Widget _buildQuickExploreGrid(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return Column(
      children: [
        _quickTile(
          context: context,
          theme: theme,
          icon: Icons.nightlight_outlined,
          iconColor: const Color(0xFFFFAA00),
          title: l.quickEclipses,
          desc: l.quickEclipsesDesc,
          onTap: () {
            onPresetSearch?.call(EventKind.solarEclipse);
            onSelectTab?.call(1);
          },
        ),
        const SizedBox(height: 8),
        _quickTile(
          context: context,
          theme: theme,
          icon: Icons.brightness_medium,
          iconColor: const Color(0xFF569AFF),
          title: l.quickConjunctions,
          desc: l.quickConjunctionsDesc,
          onTap: () {
            onPresetSearch?.call(EventKind.conjunction);
            onSelectTab?.call(1);
          },
        ),
        const SizedBox(height: 8),
        _quickTile(
          context: context,
          theme: theme,
          icon: Icons.wb_sunny_outlined,
          iconColor: const Color(0xFFFF7043),
          title: l.quickTransits,
          desc: l.quickTransitsDesc,
          onTap: () {
            onPresetSearch?.call(EventKind.transit);
            onSelectTab?.call(1);
          },
        ),
        const SizedBox(height: 8),
        _quickTile(
          context: context,
          theme: theme,
          icon: Icons.satellite_alt_outlined,
          iconColor: const Color(0xFF26A69A),
          title: l.quickSpaceStation,
          desc: l.quickSpaceStationDesc,
          onTap: () => onSelectTab?.call(2),
        ),
      ],
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

  Widget _buildCuratedHighlights(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return Column(
      children: [
        _milestoneCard(
          theme: theme,
          title: l.curatedLunar2026,
          dateBadge: '2026-03-03',
          tag: l.curatedNoticeTag,
          tagColor: theme.colorScheme.primary,
          detail: '月全食 · 中国大部可见红月亮盛景 · 食分 1.156',
          onTap: () {
            onPresetSearch?.call(
              EventKind.lunarEclipse,
              fromYear: 2026,
              toYear: 2027,
            );
            onSelectTab?.call(1);
          },
        ),
        const SizedBox(height: 8),
        _milestoneCard(
          theme: theme,
          title: l.curatedSolar2026,
          dateBadge: '2026-08-12',
          tag: l.curatedRareTag,
          tagColor: theme.colorScheme.secondary,
          detail: '日全食 · 格陵兰、冰岛西部及西班牙全食带 · 历时 2分18秒',
          onTap: () {
            onPresetSearch?.call(
              EventKind.solarEclipse,
              fromYear: 2026,
              toYear: 2027,
            );
            onSelectTab?.call(1);
          },
        ),
        const SizedBox(height: 8),
        _milestoneCard(
          theme: theme,
          title: l.curatedConjunction2026,
          dateBadge: '2026-06-09',
          tag: l.curatedNoticeTag,
          tagColor: theme.colorScheme.primary,
          detail: '金星合木星 · 傍晚西方天空极近相合 · 最小角距仅 0.2°',
          onTap: () {
            onPresetSearch?.call(
              EventKind.conjunction,
              fromYear: 2026,
              toYear: 2027,
            );
            onSelectTab?.call(1);
          },
        ),
        const SizedBox(height: 8),
        _milestoneCard(
          theme: theme,
          title: l.curatedSolar2027,
          dateBadge: '2027-08-02',
          tag: l.curatedRareTag,
          tagColor: theme.colorScheme.secondary,
          detail: '世纪日全食 · 埃及卢克索长达 6分23秒 壮丽全食',
          onTap: () {
            onPresetSearch?.call(
              EventKind.solarEclipse,
              fromYear: 2027,
              toYear: 2028,
            );
            onSelectTab?.call(1);
          },
        ),
      ],
    );
  }

  Widget _milestoneCard({
    required ThemeData theme,
    required String title,
    required String dateBadge,
    required String tag,
    required Color tagColor,
    required String detail,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 11,
                        color: tagColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateBadge,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 13,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
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
