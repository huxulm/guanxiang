import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/rust/api/guanxiang.dart';
import 'package:guanxiang/src/settings.dart';
import 'package:guanxiang/src/tasks.dart';

/// 造一个事件：start 之后 [dayOffset] 天
SatTransitItem item(
  DateTime t, {
  int norad = 25544,
  bool transit = false,
  double distanceKm = 100,
}) => SatTransitItem(
  noradId: norad,
  satellite: 'ISS',
  body: 'sun',
  isTransit: transit,
  title: 'ISS',
  utc: t.toIso8601String(),
  ttJd: t.millisecondsSinceEpoch / 86400000 + 2440587.5,
  summary: '',
  details: const [],
  distanceToCenterlineKm: distanceKm,
  bandHalfWidthKm: 3,
  elementsAgeDays: 1,
  centerline: const [GeoPoint(latitudeDeg: 0, longitudeDeg: 0)],
  centerlineNearest: const GeoPoint(latitudeDeg: 0, longitudeDeg: 0),
);

class Texts implements TaskTexts {
  @override
  String hitTitle(SatTask t, SatTransitItem e) => 'hit';
  @override
  String hitBody(SatTask t, SatTransitItem e) => e.utc;
  @override
  String finishedTitle(SatTask t) => 'done';
  @override
  String finishedBody(SatTask t) => t.status.name;
}

void main() {
  late Directory dir;
  late TaskStore store;
  final t0 = DateTime.utc(2026, 11, 10);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('guanxiang_tasks');
    store = TaskStore(File('${dir.path}/tasks.json'));
  });
  tearDown(() => dir.delete(recursive: true));

  SatTask longTask({
    bool stopOnHit = false,
    double days = 30,
    int maxMin = 10,
  }) => SatTask(
    id: 'L',
    kind: TaskKind.longSearch,
    created: t0,
    noradIds: [25544, 48274],
    place: Place.beijing,
    maxSeparationDeg: 1,
    radiusKm: 50,
    stopOnHit: stopOnHit,
    start: t0,
    days: days,
    maxRuntimeMinutes: maxMin,
  );

  test('长跨度搜索：按 7 天分段算完，结果保存，结束时只发一条汇总通知', () async {
    await store.add(longTask());
    final calls = <(int, DateTime, double)>[];
    final notes = <String>[];
    final runner = TaskRunner(
      store: store,
      texts: Texts(),
      notify: (title, body, id) async => notes.add(title),
      search:
          ({
            required noradId,
            required place,
            required startUtc,
            required days,
            required maxSeparationDeg,
            required radiusKm,
          }) async {
            calls.add((noradId, startUtc, days));
            // 第 2 段里有一个范围内可见（40 km < 50 km）的事件
            if (noradId == 25544 &&
                startUtc == t0.add(const Duration(days: 7))) {
              return [
                item(startUtc.add(const Duration(days: 1)), distanceKm: 40),
              ];
            }
            return [
              item(startUtc.add(const Duration(hours: 5)), norad: noradId),
            ];
          },
    );
    expect(await runner.runDue(), isFalse);
    final t = (await store.load()).single;
    expect(t.status, TaskStatus.done);
    expect(t.searchedDays, closeTo(30, 1e-9));
    // 30 天 = 7+7+7+7+2，两颗卫星
    expect(calls.length, 10);
    expect(calls.last.$3, closeTo(2, 1e-9));
    expect(t.hits.length, 1);
    expect(notes, ['done']);
    // 再跑一次不会重复
    await runner.runDue();
    expect(notes.length, 1);
  });

  test('长跨度搜索：找到就停、计算时间到期、预算用完可续算', () async {
    await store.add(longTask(stopOnHit: true));
    final runner = TaskRunner(
      store: store,
      texts: Texts(),
      search: ({
        required noradId,
        required place,
        required startUtc,
        required days,
        required maxSeparationDeg,
        required radiusKm,
      }) async => [item(startUtc, transit: startUtc.isAfter(t0))],
    );
    await runner.runDue();
    var t = (await store.load()).single;
    expect(t.status, TaskStatus.done);
    expect(t.searchedDays, closeTo(14, 1e-9), reason: '第 2 段出现凌日就停');

    // 计算时间上限 0 分钟：一开始就到时
    await store.delete('L');
    await store.add(longTask(maxMin: 0));
    await runner.runDue();
    t = (await store.load()).single;
    expect(t.status, TaskStatus.timeout);

    // 预算为 0：一段都不算，返回“还有没算完的”
    await store.delete('L');
    await store.add(longTask());
    expect(await runner.runDue(budget: Duration.zero), isTrue);
    expect((await store.load()).single.searchedDays, 0);
  });

  test('持续监视：间隔内不重复搜索，未来部分用新预报替换，到期结束', () async {
    var now = t0;
    await store.add(
      SatTask(
        id: 'W',
        kind: TaskKind.watch,
        created: t0,
        noradIds: [25544],
        place: Place.beijing,
        maxSeparationDeg: 1,
        radiusKm: 0,
        stopOnHit: false,
        deadline: t0.add(const Duration(days: 3)),
      ),
    );
    var searches = 0;
    var refreshes = 0;
    var shift = Duration.zero;
    final notes = <String>[];
    final runner = TaskRunner(
      store: store,
      texts: Texts(),
      now: () => now,
      refresh: (_) async => refreshes++,
      notify: (title, body, id) async => notes.add(title),
      search:
          ({
            required noradId,
            required place,
            required startUtc,
            required days,
            required maxSeparationDeg,
            required radiusKm,
          }) async {
            searches++;
            expect(days, watchHorizonDays);
            // 固定的一次凌日，根数更新后时刻移动几十秒
            return [
              item(t0.add(const Duration(days: 2)).add(shift), transit: true),
            ];
          },
    );
    await runner.runDue();
    expect((searches, refreshes), (1, 1));
    expect(notes, ['hit']);
    now = t0.add(const Duration(hours: 1));
    await runner.runDue();
    expect(searches, 1, reason: '4 小时内不重搜');
    now = t0.add(const Duration(hours: 5));
    shift = const Duration(seconds: 40);
    await runner.runDue();
    final t = (await store.load()).single;
    expect(searches, 2);
    expect(t.items.length, 1, reason: '同一事件被新预报替换');
    expect(notes, ['hit'], reason: '同一事件不重复通知');
    now = t0.add(const Duration(days: 3));
    await runner.runDue();
    expect((await store.load()).single.status, TaskStatus.done);
    expect(notes.last, 'done');
  });

  test('取消后不再执行，JSON 往返不丢字段', () async {
    await store.add(longTask());
    await store.cancel('L');
    var calls = 0;
    final runner = TaskRunner(
      store: store,
      texts: Texts(),
      search:
          ({
            required noradId,
            required place,
            required startUtc,
            required days,
            required maxSeparationDeg,
            required radiusKm,
          }) async {
            calls++;
            return [];
          },
    );
    await runner.runDue();
    expect(calls, 0);
    expect((await store.load()).single.status, TaskStatus.cancelled);

    final e = item(t0, transit: true);
    final back = satItemFromJson(satItemToJson(e));
    expect(jsonEncode(satItemToJson(back)), jsonEncode(satItemToJson(e)));
    expect(back.isTransit, isTrue);
  });
}
