import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/src/celestrak.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String omm(int id, String epoch) =>
    '[{"OBJECT_NAME":"TEST","NORAD_CAT_ID":$id,"EPOCH":"$epoch","MEAN_MOTION":15.5}]';

void main() {
  late Directory tmp;
  var requests = 0;
  var status = 200;
  var epoch = '2026-11-04T21:15:15.204960';

  final client = MockClient((req) async {
    requests++;
    expect(req.url.host, 'celestrak.org');
    expect(req.url.queryParameters['FORMAT'], 'JSON');
    expect(req.headers['User-Agent'], startsWith('guanxiang/'));
    final id = int.parse(req.url.queryParameters['CATNR']!);
    return http.Response(omm(id, epoch), status);
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('omm_test');
    requests = 0;
    status = 200;
    OmmStore.resetSessionBlockForTest();
  });
  tearDown(() => tmp.delete(recursive: true));

  test('下载、频率限制、保留旧根数', () async {
    final store = await OmmStore.open(client: client, baseDir: tmp);
    final t0 = DateTime.utc(2026, 11, 6, 0);

    final r1 = await store.refresh(25544, now: t0);
    expect(r1.updated, isTrue);
    expect(requests, 1);

    // 2 小时内不再请求
    final r2 = await store.refresh(
      25544,
      now: t0.add(const Duration(minutes: 90)),
    );
    expect(r2.updated, isFalse);
    expect(requests, 1);

    // 2 小时后再请求；历元变了，旧根数保存为 prev
    epoch = '2026-11-05T09:00:00.000000';
    final r3 = await store.refresh(
      25544,
      now: t0.add(const Duration(hours: 3)),
    );
    expect(r3.updated, isTrue);
    expect(requests, 2);
    final c = await store.cached(25544);
    expect(c.epoch, epoch);
    expect(ommSummary(c.previousJson!)!.epoch, '2026-11-04T21:15:15.204960');
  });

  test('非 200 后本次运行和 2 小时内都不再请求', () async {
    final store = await OmmStore.open(client: client, baseDir: tmp);
    final t0 = DateTime.utc(2026, 11, 6, 0);
    status = 403;
    final r = await store.refresh(25544, now: t0);
    expect(r.error, isTrue);
    expect(requests, 1);
    status = 200;
    expect((await store.refresh(48274, now: t0)).error, isTrue);
    expect(requests, 1);

    // 模拟重新启动：本次运行的标记清除，但持久化的暂停时间仍有效
    OmmStore.resetSessionBlockForTest();
    expect(
      (await store.refresh(48274, now: t0.add(const Duration(hours: 1)))).error,
      isTrue,
    );
    expect(requests, 1);
    expect(
      (await store.refresh(
        48274,
        now: t0.add(const Duration(hours: 3)),
      )).updated,
      isTrue,
    );
    expect(requests, 2);
  });

  test('关注列表', () async {
    final store = await OmmStore.open(client: client, baseDir: tmp);
    expect(await store.watchList(), defaultSatellites);
    await store.setWatchList({...defaultSatellites, 20580: 'NORAD 20580'});
    expect((await store.watchList()).keys, containsAll([25544, 48274, 20580]));
  });
}
