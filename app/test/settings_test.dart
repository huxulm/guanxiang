import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/l10n/app_localizations.dart';
import 'package:guanxiang/src/settings.dart';

void main() {
  test('手动模式直接返回手动位置', () async {
    final s = Settings.inMemory(locator: () async => throw StateError('不应定位'));
    await s.setMode(LocationMode.manual);
    await s.setManual(const Place(31.2, 121.5, 10));
    final r = await s.place();
    expect(r.place.lat, 31.2);
    expect(r.stale, isFalse);
  });

  test('无效的手动位置不保存', () async {
    final s = Settings.inMemory();
    await s.setManual(const Place(95, 0, 0));
    expect(s.manual.lat, Place.beijing.lat);
  });

  test('GPS：10 分钟内沿用定位，同时只发一次请求', () async {
    var calls = 0;
    final s = Settings.inMemory(
      locator: () async {
        calls++;
        return const Place(25.0, 102.7, 1900);
      },
    );
    final both = await Future.wait([s.place(), s.place()]);
    expect(both.map((r) => r.place.lat), [25.0, 25.0]);
    expect(calls, 1);
    await s.place();
    expect(calls, 1);
    expect(s.gpsTime, isNotNull);
    expect(s.locating, isFalse);
  });

  test('GPS 失败：没有旧定位时报错，有旧定位时沿用并标记', () async {
    var fail = true;
    final s = Settings.inMemory(
      locator: () async {
        if (fail) throw const LocationException(LocationError.denied);
        return const Place(1, 2, 3);
      },
    );
    await expectLater(s.place(), throwsA(isA<LocationException>()));
    expect(s.gpsError?.error, LocationError.denied);

    fail = false;
    await s.locate();
    expect(s.gpsError, isNull);

    fail = true;
    // 让定位过期
    await Future<void>.delayed(Duration.zero);
    final r = await s.placeWithMaxAge(Duration.zero);
    expect(r.stale, isTrue);
    expect(r.place.lat, 1);
    expect(s.gpsError?.error, LocationError.denied);
  });

  test('定位错误有中英文说明', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final en = lookupAppLocalizations(const Locale('en'));
    for (final e in LocationError.values) {
      final x = LocationException(e, 'x');
      expect(x.describe(zh), isNotEmpty);
      expect(x.describe(en), isNotEmpty);
    }
    expect(
      const Place(39.9, -116.4, 50).describe(),
      '39.9000°N 116.4000°W 50 m',
    );
  });
}
