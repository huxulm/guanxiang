import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'dashboard_page.dart';
import 'rust/api/guanxiang.dart';
import 'satellite_page.dart';
import 'search_page.dart';
import 'search_results.dart' show isNarrow;
import 'settings.dart';
import 'settings_page.dart';

/// 观象主导航脚手架。
///
/// 包含四个核心功能模块：
/// 0. 看板（今日天象、快捷探索、精选重磅事件）
/// 1. 搜索（全量合冲、凌日、日月食、月掩星离线计算）
/// 2. 卫星（卫星凌日凌月、中心线地图、后台任务）
/// 3. 设置（观测位置配置、外观主题切换、关于与许可）
///
/// 窄屏（手机）采用底部 [NavigationBar]；宽屏（平板/桌面）采用侧边 [NavigationRail]。
/// 使用 [IndexedStack] 保留每个页面的状态与计算进度，切换 Tab 不会丢弃任何状态。
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key, required this.engine, required this.settings});

  final Engine engine;
  final Settings settings;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final _searchKey = GlobalKey<SearchPageState>();

  void _selectTab(int index) {
    if (index >= 0 && index < 4 && index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  void _presetSearch(EventKind kind, {int? fromYear, int? toYear}) {
    _searchKey.currentState?.preset(
      kind: kind,
      fromYear: fromYear,
      toYear: toYear,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final narrow = isNarrow(context);

    final pages = [
      DashboardPage(
        engine: widget.engine,
        settings: widget.settings,
        onSelectTab: _selectTab,
        onPresetSearch: _presetSearch,
      ),
      SearchPage(
        key: _searchKey,
        engine: widget.engine,
        settings: widget.settings,
        isEmbedded: true,
      ),
      SatellitePage(engine: widget.engine, settings: widget.settings),
      SettingsPage(settings: widget.settings),
    ];

    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.explore_outlined),
        selectedIcon: const Icon(Icons.explore),
        label: l.navDashboard,
      ),
      NavigationDestination(
        icon: const Icon(Icons.search_outlined),
        selectedIcon: const Icon(Icons.search),
        label: l.navSearch,
      ),
      NavigationDestination(
        icon: const Icon(Icons.satellite_alt_outlined),
        selectedIcon: const Icon(Icons.satellite_alt),
        label: l.navSatellite,
      ),
      NavigationDestination(
        icon: const Icon(Icons.tune_outlined),
        selectedIcon: const Icon(Icons.tune),
        label: l.navSettings,
      ),
    ];

    if (narrow) {
      return Scaffold(
        body: IndexedStack(index: _currentIndex, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _selectTab,
          destinations: destinations,
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: _selectTab,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l.appTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.explore_outlined),
                selectedIcon: const Icon(Icons.explore),
                label: Text(l.navDashboard),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.search_outlined),
                selectedIcon: const Icon(Icons.search),
                label: Text(l.navSearch),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.satellite_alt_outlined),
                selectedIcon: const Icon(Icons.satellite_alt),
                label: Text(l.navSatellite),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.tune_outlined),
                selectedIcon: const Icon(Icons.tune),
                label: Text(l.navSettings),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: pages),
          ),
        ],
      ),
    );
  }
}
