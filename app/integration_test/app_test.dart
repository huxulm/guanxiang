// 在设备或模拟器上运行：flutter test integration_test -d <设备>
//
// 验证：星历能从 asset 加载、各类搜索能在设备上跑通且结果正确、取消能让搜索提前结束、
// 许可声明打进了安装包。性能数据请用 profile 模式：
// flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d <设备>
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/l10n/app_localizations.dart';
import 'package:guanxiang/src/app.dart';
import 'package:guanxiang/src/dashboard_page.dart';
import 'package:guanxiang/src/eclipse_diagram.dart';
import 'package:guanxiang/src/event_detail_page.dart';
import 'package:guanxiang/src/lunar_eclipse_detail.dart';
import 'package:guanxiang/src/licenses.dart';
import 'package:guanxiang/src/rust/api/guanxiang.dart';
import 'package:guanxiang/src/rust/frb_generated.dart';
import 'package:guanxiang/src/settings.dart';
import 'package:guanxiang/src/tonight_card.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Engine engine;

  setUpAll(() async {
    await RustLib.init();
    final data = await rootBundle.load(ephemerisAsset);
    final watch = Stopwatch()..start();
    engine = await Engine.fromBytes(bytes: data.buffer.asUint8List());
    // ignore: avoid_print
    print('星历加载 ${watch.elapsedMilliseconds} ms');
  });

  test('金星凌日 2004–2013 恰好两次', () async {
    final updates = await search(
      engine: engine,
      request: const SearchRequest(
        kind: EventKind.transit,
        bodyA: 'venus',
        bodyB: '',
        fromYear: 2004,
        toYear: 2013,
        maxSeparationDeg: 0,
        lang: Lang.zh,
      ),
      token: CancelToken(),
    ).toList();
    final found = updates
        .where((u) => u.kind == UpdateKind.found)
        .map((u) => u.item!)
        .toList();
    expect(found.map((e) => e.utc.substring(0, 10)), [
      '2004-06-08',
      '2012-06-06',
    ]);
    final done = updates.last;
    expect(done.kind, UpdateKind.finished);
    expect(done.cancelled, isFalse);
    // ignore: avoid_print
    print('金星凌日搜索 9 年用时 ${done.elapsedMs} ms');
  });

  test('100 年月木合（性能参考）', () async {
    final updates = await search(
      engine: engine,
      request: const SearchRequest(
        kind: EventKind.conjunction,
        bodyA: 'moon',
        bodyB: 'jupiter',
        fromYear: 2000,
        toYear: 2100,
        maxSeparationDeg: 0,
        lang: Lang.zh,
      ),
      token: CancelToken(),
    ).toList();
    final done = updates.last;
    expect(done.count, greaterThan(1300));
    // ignore: avoid_print
    print('月木合 100 年：${done.count} 个，用时 ${done.elapsedMs} ms');
  });

  test('日月食 2024–2026：日食 6 次、月食 6 次；2035 年北京日全食', () async {
    Future<List<EventItem>> run(
      EventKind kind,
      int from,
      int to, {
      ObserverInput? at,
    }) async {
      final updates = await search(
        engine: engine,
        request: SearchRequest(
          kind: kind,
          bodyA: '',
          bodyB: '',
          fromYear: from,
          toYear: to,
          maxSeparationDeg: 0,
          observer: at,
          lang: Lang.zh,
        ),
        token: CancelToken(),
      ).toList();
      return updates
          .where((u) => u.kind == UpdateKind.found)
          .map((u) => u.item!)
          .toList();
    }

    expect((await run(EventKind.solarEclipse, 2024, 2027)).length, 6);
    expect((await run(EventKind.lunarEclipse, 2024, 2027)).length, 6);
    final beijing = await run(
      EventKind.solarEclipse,
      2035,
      2036,
      at: const ObserverInput(
        latitudeDeg: 39.9,
        longitudeDeg: 116.4,
        heightM: 50,
        minAltitudeDeg: 0,
        maxSunAltitudeDeg: -6,
      ),
    );
    expect(beijing.single.summary, startsWith('本地全食'));
  });

  test('月掩星：2026 年心宿二地心候选 13 次', () async {
    final updates = await search(
      engine: engine,
      request: const SearchRequest(
        kind: EventKind.occultation,
        bodyA: '心宿二',
        bodyB: '',
        fromYear: 2026,
        toYear: 2027,
        maxSeparationDeg: 0,
        lang: Lang.zh,
      ),
      token: CancelToken(),
    ).toList();
    expect(updates.where((u) => u.kind == UpdateKind.found).length, 13);
  });

  test('取消后提前结束', () async {
    final token = CancelToken();
    var progressCount = 0;
    final updates = <SearchUpdate>[];
    await for (final u in search(
      engine: engine,
      request: const SearchRequest(
        kind: EventKind.conjunction,
        bodyA: 'moon',
        bodyB: 'saturn',
        fromYear: 2000,
        toYear: 2100,
        maxSeparationDeg: 0,
        lang: Lang.zh,
      ),
      token: token,
    )) {
      updates.add(u);
      if (u.kind == UpdateKind.progress && ++progressCount == 3) token.cancel();
    }
    expect(updates.last.cancelled, isTrue);
    expect(progressCount, lessThan(100));
  });

  // 与 crates/guanxiang-core/tests/satellites.rs 用同一份根数和 Skyfield 对照数据
  test('卫星：天宫过北京的太阳接近与 Skyfield 一致', () async {
    const omm =
        r'[{"OBJECT_NAME":"ISS (ZARYA)","OBJECT_ID":"1998-067A","EPOCH":"2026-11-04T21:15:15.204960","MEAN_MOTION":15.49180468,"ECCENTRICITY":0.00072122,"INCLINATION":51.6327,"RA_OF_ASC_NODE":323.8448,"ARG_OF_PERICENTER":348.649,"MEAN_ANOMALY":11.4335,"EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"U","NORAD_CAT_ID":25544,"ELEMENT_SET_NO":999,"REV_AT_EPOCH":59356,"BSTAR":0.00010456704,"MEAN_MOTION_DOT":5.352e-5,"MEAN_MOTION_DDOT":0},{"OBJECT_NAME":"CSS (TIANHE)","OBJECT_ID":"2021-035A","EPOCH":"2026-11-04T21:46:39.576864","MEAN_MOTION":15.61399302,"ECCENTRICITY":0.00044949,"INCLINATION":41.4685,"RA_OF_ASC_NODE":186.988,"ARG_OF_PERICENTER":260.0378,"MEAN_ANOMALY":99.9954,"EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"U","NORAD_CAT_ID":48274,"ELEMENT_SET_NO":999,"REV_AT_EPOCH":31514,"BSTAR":0.00023141307,"MEAN_MOTION_DOT":0.00020029,"MEAN_MOTION_DDOT":0}]';
    final sats = parseOmm(json: omm);
    expect(sats.map((s) => s.noradId), [25544, 48274]);
    final css = omm.substring(
      omm.indexOf('{"OBJECT_NAME":"CSS'),
      omm.length - 1,
    );
    final found = await satelliteTransits(
      engine: engine,
      ommJson: '[$css]',
      latitudeDeg: 39.9042,
      longitudeDeg: 116.4074,
      heightM: 50,
      startUtc: '',
      days: 7,
      maxSeparationDeg: 10,
      radiusKm: 0,
      lang: Lang.zh,
    );
    final sun = found.where((e) => e.body == 'sun').toList();
    const expected = [
      2461350.6980705536,
      2461353.6404368957,
      2461354.5988757834,
      2461354.8662447315,
      2461355.5574492658,
      2461355.8251210563,
    ];
    expect(sun.length, expected.length);
    for (var i = 0; i < expected.length; i++) {
      expect((sun[i].ttJd - expected[i]).abs() * 86400, lessThan(0.05));
    }
    expect(sun.first.centerline.length, greaterThan(20));
    expect(sun.first.details.any((d) => d.label == '安全提示'), isTrue);
  });

  test('许可声明已打包（含 Rust 依赖和致谢）', () async {
    registerLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();
    expect(packages, contains('观象：算法与数据来源'));
    expect(packages.any((p) => p.startsWith('anise ')), isTrue);
    expect(packages.any((p) => p.startsWith('sofars ')), isTrue);
  });

  test('英文输出：金星凌日标题、天体名、安全提示', () async {
    final updates = await search(
      engine: engine,
      request: const SearchRequest(
        kind: EventKind.transit,
        bodyA: 'venus',
        bodyB: '',
        fromYear: 2012,
        toYear: 2013,
        maxSeparationDeg: 0,
        lang: Lang.en,
      ),
      token: CancelToken(),
    ).toList();
    final item = updates.firstWhere((u) => u.kind == UpdateKind.found).item!;
    expect(item.title, 'Transit of Venus');
    expect(item.details.map((d) => d.label), contains('Greatest transit'));
    expect(
      bodyNames(lang: Lang.en).map((d) => d.value),
      containsAll(['Moon', 'Jupiter']),
    );
    expect(sunSafetyNotice(lang: Lang.en), contains('solar filter'));
  });

  testWidgets('看板：近期天象由本机星历算出，不报错', (tester) async {
    final dir = await Directory.systemTemp.createTemp('guanxiang_dash');
    final settings = await Settings.openFile(File('${dir.path}/settings.json'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DashboardPage(engine: engine, settings: settings),
      ),
    );
    // 列表是懒构建的：一边往下滚一边等，直到出现结果卡片（或“没有找到”/错误）
    final scrollable = find.byType(Scrollable).first;
    final tiles = find.byType(UpcomingEventCard);
    final none = find.text('没有找到');
    for (var i = 0; i < 300; i++) {
      if (tiles.evaluate().isNotEmpty || none.evaluate().isNotEmpty) break;
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(none, findsNothing);
    expect(tiles, findsWidgets);
    await tester.drag(scrollable, const Offset(0, -3000));
    await tester.pumpAndSettle();
    for (final t in tiles.evaluate()) {
      final e = (t.widget as UpcomingEventCard).event;
      // 半影月食肉眼几乎看不出，不该出现在看板上
      expect(e.subtle, isFalse);
      // ignore: avoid_print
      print('近期天象：${e.title} | ${e.utc} | ${e.summary}');
    }
    await tester.pumpWidget(const SizedBox());
    await dir.delete(recursive: true);
  });

  testWidgets('看板：今晚的日月出没和月相（手动观测地）', (tester) async {
    final dir = await Directory.systemTemp.createTemp('guanxiang_tonight');
    final settings = await Settings.openFile(File('${dir.path}/settings.json'));
    await settings.setMode(LocationMode.manual);
    await settings.setManual(Place.beijing);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: TonightCard(engine: engine, settings: settings),
        ),
      ),
    );
    final moon = find.byType(MoonPhaseIcon);
    for (var i = 0; i < 200 && moon.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(moon, findsOneWidget);
    // 北京每晚都有日落、天黑、天亮、日出：四个时刻都不是“—”
    final times = find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d\d:\d\d$').hasMatch(w.data ?? ''),
    );
    expect(times.evaluate().length, greaterThanOrEqualTo(4));
    // ignore: avoid_print
    print(
      '今晚：${times.evaluate().map((e) => (e.widget as Text).data).join(' ')}',
    );
    await tester.pumpWidget(const SizedBox());
    await dir.delete(recursive: true);
  });

  testWidgets('详情页：日月食示意图能画出来', (tester) async {
    for (final kind in [EventKind.lunarEclipse, EventKind.solarEclipse]) {
      final updates = await search(
        engine: engine,
        request: SearchRequest(
          kind: kind,
          bodyA: '',
          bodyB: '',
          fromYear: 2027,
          toYear: 2028,
          maxSeparationDeg: 0,
          lang: Lang.zh,
        ),
        token: CancelToken(),
      ).toList();
      final event = updates.firstWhere((u) => u.kind == UpdateKind.found).item!;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: EclipseDiagramCard(engine: engine, event: event),
            ),
          ),
        ),
      );
      final title = find.text('示意图');
      for (var i = 0; i < 200 && title.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(title, findsOneWidget, reason: '${event.title} 的示意图没有出来');
      // ignore: avoid_print
      print('示意图：${event.title} ${event.utc}');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('月食详情：时间轴、本地可见情况、滑块和地图', (tester) async {
    final updates = await search(
      engine: engine,
      request: const SearchRequest(
        kind: EventKind.lunarEclipse,
        bodyA: '',
        bodyB: '',
        fromYear: 2025,
        toYear: 2026,
        maxSeparationDeg: 0,
        lang: Lang.zh,
      ),
      token: CancelToken(),
    ).toList();
    final event = updates
        .where((u) => u.kind == UpdateKind.found)
        .map((u) => u.item!)
        .firstWhere((e) => e.utc.startsWith('2025-09-07'));
    final settings = Settings.inMemory();
    await settings.setMode(LocationMode.manual);
    await settings.setManual(const Place(39.9042, 116.4074, 44));

    // 窗口拉高，整页一次排下（列表不会把下面的卡片省略掉）
    tester.view.physicalSize = const Size(900, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: EventDetailPage(event: event, engine: engine, settings: settings),
      ),
    );
    final verdict = find.text('全程可见');
    for (var i = 0; i < 200 && verdict.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(verdict, findsWidgets, reason: '北京应全程可见');
    expect(find.text('全食 1 小时 22 分'), findsOneWidget);
    expect(find.textContaining('沙罗序列 128'), findsWidgets);
    expect(find.byType(PhaseTimeline), findsOneWidget);
    expect(find.text('全球可见区域'), findsOneWidget);

    // 默认停在食甚（全食中）；点 P1 后是半影食，点 U2 回到全食
    expect(find.text('全食中'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'P1'));
    await tester.pump();
    expect(find.text('半影食中'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'U2'));
    await tester.pump();
    expect(find.text('全食中'), findsOneWidget);

    expect(find.byTooltip('分享图片'), findsOneWidget);

    // 原始参数收在底部抽屉里：页面上没有参数表，点按钮后才出现
    expect(find.text('γ（影轴离地心）'), findsNothing);
    await tester.tap(find.textContaining('全部参数（'));
    await tester.pumpAndSettle();
    expect(find.text('γ（影轴离地心）'), findsOneWidget);
    expect(find.text('沙罗序列'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('日食详情：本地全食、太阳面模拟和地图', (tester) async {
    final updates = await search(
      engine: engine,
      request: const SearchRequest(
        kind: EventKind.solarEclipse,
        bodyA: '',
        bodyB: '',
        fromYear: 2027,
        toYear: 2028,
        maxSeparationDeg: 0,
        lang: Lang.zh,
      ),
      token: CancelToken(),
    ).toList();
    final event = updates
        .where((u) => u.kind == UpdateKind.found)
        .map((u) => u.item!)
        .firstWhere((e) => e.utc.startsWith('2027-08-02'));
    final settings = Settings.inMemory();
    await settings.setMode(LocationMode.manual);
    await settings.setManual(const Place(25.6872, 32.6396, 80)); // 卢克索

    tester.view.physicalSize = const Size(900, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: EventDetailPage(event: event, engine: engine, settings: settings),
      ),
    );
    final verdict = find.text('全程可见');
    for (var i = 0; i < 300 && verdict.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(verdict, findsOneWidget, reason: '卢克索应全程可见');
    expect(find.textContaining('全食 6 分'), findsOneWidget);
    expect(find.textContaining('沙罗序列 136'), findsWidgets);
    expect(find.textContaining('ISO 12312-2'), findsWidgets);
    expect(find.text('全球食况'), findsOneWidget);

    // 默认停在本地食甚（全食）；点 C1 后是偏食开始，食面积 0
    expect(find.text('全食中'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'C1'));
    await tester.pump();
    expect(find.text('偏食中'), findsOneWidget);
    expect(find.text('食面积 0.0%'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'C2'));
    await tester.pump();
    expect(find.text('全食中'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
