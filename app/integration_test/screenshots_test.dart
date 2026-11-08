// 界面截图：浅色、深空、红光三套主题 × 窄屏、宽屏，供改界面时核对效果。
//
// 只在给了 SHOT_DIR 时运行，否则整个文件跳过。CI 和日常集成测试只跑 app_test.dart，不会启动这个文件。
// 推荐在 Windows 桌面上跑，最快：
//
//   cd app
//   flutter test integration_test/screenshots_test.dart -d windows \
//     --dart-define=SHOT_DIR=%CD%\build\screenshots
//
// 可选参数（都用 --dart-define 传）：
//   SHOT_FILTER=solar        只截名字里含这个字符串的图（页面、主题、尺寸都算在名字里，如 lunar-red）
//   SHOT_LOCALE=en           英文界面（默认中文）
//
// 输出：<SHOT_DIR>/<页面>-<主题>-<尺寸>-<序号>.png。长页面按一屏一张往下滚动截取，
// 每次运行前请清空输出目录，免得混进上次多出来的序号。
// 要截新页面，在 `_pages` 里加一项即可。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/l10n/app_localizations.dart';
import 'package:guanxiang/src/app.dart';
import 'package:guanxiang/src/event_detail_page.dart';
import 'package:guanxiang/src/rust/api/guanxiang.dart';
import 'package:guanxiang/src/rust/frb_generated.dart';
import 'package:guanxiang/src/settings.dart';
import 'package:guanxiang/src/share_poster.dart';
import 'package:guanxiang/src/theme.dart';
import 'package:integration_test/integration_test.dart';

const shotDir = String.fromEnvironment('SHOT_DIR');
const shotFilter = String.fromEnvironment('SHOT_FILTER');
const shotLocale = String.fromEnvironment('SHOT_LOCALE', defaultValue: 'zh');

const _beijing = Place(39.9, 116.4, 50);
const _luxor = Place(25.69, 32.64, 80);

/// 三套主题：名字用在文件名里
final _themes = <String, ThemeData>{
  'light': AstroTheme.lightTheme,
  'dark': AstroTheme.deepSpaceTheme,
  'red': AstroTheme.astroRedTheme,
};

/// 逻辑尺寸：窄屏是常见手机，宽屏是桌面窗口（宽度 ≥ 600 时搜索结果与列表同屏）
const _sizes = <String, Size>{
  'narrow': Size(412, 915),
  'wide': Size(1280, 860),
};

/// 一个要截的页面：名字、观测地、页面本身（需要事件的在 build 里自己查）
class _Page {
  const _Page(this.name, this.place, this.build, {this.scroll = true});
  final String name;
  final Place place;
  final Future<Widget> Function(Engine engine, Settings settings) build;

  /// 是否往下滚动，一屏一张截完整页
  final bool scroll;
}

Future<EventItem> _findEvent(Engine engine, EventKind kind, String day) async {
  final year = int.parse(day.substring(0, 4));
  final updates = await search(
    engine: engine,
    request: SearchRequest(
      kind: kind,
      bodyA: '',
      bodyB: '',
      fromYear: year,
      toYear: year + 1,
      maxSeparationDeg: 0,
      lang: shotLocale == 'en' ? Lang.en : Lang.zh,
    ),
    token: CancelToken(),
  ).toList();
  return updates
      .where((u) => u.kind == UpdateKind.found)
      .map((u) => u.item!)
      .firstWhere((e) => e.utc.startsWith(day));
}

final _pages = <_Page>[
  // 启动页加载星历后进入首页（今晚、近期天象）
  _Page('dashboard', _beijing, (e, s) async => LoadingPage(settings: s)),
  _Page('lunar', _beijing, (e, s) async {
    final ev = await _findEvent(e, EventKind.lunarEclipse, '2025-09-07');
    return EventDetailPage(event: ev, engine: e, settings: s);
  }),
  _Page('solar', _luxor, (e, s) async {
    final ev = await _findEvent(e, EventKind.solarEclipse, '2027-08-02');
    return EventDetailPage(event: ev, engine: e, settings: s);
  }),
  _Page('share', _luxor, scroll: false, (e, s) async {
    final ev = await _findEvent(e, EventKind.solarEclipse, '2027-08-02');
    return EclipseSharePage(engine: e, event: ev, settings: s);
  }),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Engine engine;

  setUpAll(() async {
    if (shotDir.isEmpty) return;
    await RustLib.init();
    final data = await rootBundle.load(ephemerisAsset);
    engine = await Engine.fromBytes(bytes: data.buffer.asUint8List());
    Directory(shotDir).createSync(recursive: true);
  });

  testWidgets('界面截图', skip: shotDir.isEmpty, (tester) async {
    final boundary = GlobalKey();
    var count = 0;
    for (final page in _pages) {
      for (final MapEntry(key: themeName, value: theme) in _themes.entries) {
        for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
          final base = '${page.name}-$themeName-$sizeName';
          if (shotFilter.isNotEmpty && !base.contains(shotFilter)) continue;

          final settings = Settings.inMemory();
          await settings.setMode(LocationMode.manual);
          await settings.setManual(page.place);
          tester.view.devicePixelRatio = 2;
          tester.view.physicalSize = size * 2;

          final home = await tester.runAsync(
            () => page.build(engine, settings),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                locale: Locale(shotLocale),
                supportedLocales: const [Locale('en'), Locale('zh')],
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: home,
              ),
            ),
          );
          await _settle(tester);

          // 一屏一张往下滚：每次滚约 85% 屏高，留一点重叠方便对照上下文。
          // 列表是懒加载的，可滚动高度边滚边变，所以每次都重新读当前位置和最大值。
          final scroll = page.scroll ? _mainScroll(tester) : null;
          for (var i = 1; i <= 20; i++) {
            await _save(tester, boundary, '$base-$i');
            count++;
            final pos = scroll?.position;
            if (pos == null) break;
            final before = pos.pixels;
            pos.jumpTo(
              (before + size.height * 0.85).clamp(0, pos.maxScrollExtent),
            );
            await _settle(tester, rounds: 5);
            // 到底了（位置不再变化）就停
            if (pos.pixels <= before + 1) break;
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    // ignore: avoid_print
    print('截图 $count 张 → $shotDir');
  });
}

/// 等异步计算（Rust 端的详情、地图数据）完成：真实地等待，同时推进帧。
/// 页面上没有转圈的进度条后再多等几帧。
Future<void> _settle(WidgetTester tester, {int rounds = 40}) async {
  var idle = 0;
  for (var i = 0; i < rounds && idle < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final busy = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    idle = busy ? 0 : idle + 1;
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// 页面主体的竖向滚动区域：可滚动距离最大的那个
ScrollableState? _mainScroll(WidgetTester tester) {
  ScrollableState? best;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) {
      continue;
    }
    if (best == null ||
        s.position.maxScrollExtent > best.position.maxScrollExtent) {
      best = s;
    }
  }
  return best;
}

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
