// 在设备或模拟器上运行：flutter test integration_test -d <设备>
//
// 验证三件事：星历能从 asset 加载、Rust 搜索能在设备上跑通（2004–2013 年金星凌日恰好 2 次）、
// 取消能让搜索提前结束。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/app.dart';
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
      ),
      token: CancelToken(),
    ).toList();
    final found = updates.where((u) => u.kind == UpdateKind.found).map((u) => u.item!).toList();
    expect(found.map((e) => e.utc.substring(0, 10)), ['2004-06-08', '2012-06-06']);
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
      ),
      token: CancelToken(),
    ).toList();
    final done = updates.last;
    expect(done.count, greaterThan(1300));
    // ignore: avoid_print
    print('月木合 100 年：${done.count} 个，用时 ${done.elapsedMs} ms');
  });

  test('日月食 2024–2026：日食 6 次、月食 6 次；2035 年北京日全食', () async {
    Future<List<EventItem>> run(EventKind kind, int from, int to, {ObserverInput? at}) async {
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
        ),
        token: CancelToken(),
      ).toList();
      return updates.where((u) => u.kind == UpdateKind.found).map((u) => u.item!).toList();
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
      ),
      token: token,
    )) {
      updates.add(u);
      if (u.kind == UpdateKind.progress && ++progressCount == 3) token.cancel();
    }
    expect(updates.last.cancelled, isTrue);
    expect(progressCount, lessThan(100));
  });
}
