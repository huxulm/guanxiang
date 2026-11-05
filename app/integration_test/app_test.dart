// 在设备或模拟器上运行：flutter test integration_test -d <设备>
//
// 验证：星历能从 asset 加载、各类搜索能在设备上跑通且结果正确、取消能让搜索提前结束、
// 许可声明打进了安装包。性能数据请用 profile 模式：
// flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d <设备>
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/app.dart';
import 'package:guanxiang/src/licenses.dart';
import 'package:guanxiang/src/rust/api/guanxiang.dart';
import 'package:guanxiang/src/rust/frb_generated.dart';
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
}
