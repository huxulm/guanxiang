import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guanxiang/l10n/app_localizations.dart';
import 'package:guanxiang/src/rust/api/guanxiang.dart';
import 'package:guanxiang/src/settings.dart';
import 'package:guanxiang/src/share_poster.dart';

void main() {
  test('观测地取整到 1°', () {
    expect(roundedPlace(39.9042, 116.4074), '40°N 116°E');
    expect(roundedPlace(-33.87, -70.65), '34°S 71°W');
    expect(roundedPlace(0.4, -0.4), '0°N 0°W');
  });

  testWidgets('分享图：打开“显示观测地”才写位置', (tester) async {
    const event = EventItem(
      kind: EventKind.lunarEclipse,
      title: '月全食',
      utc: '2025-09-07 18:11:48',
      ttJd: 2460926.259,
      summary: '本影食分 1.362',
      details: [],
      subtle: false,
    );
    final detail = LunarEclipseDetail(
      diagram: const LunarEclipseDiagram(
        penumbraDeg: 1.25,
        umbraDeg: 0.74,
        moonSemidiameterDeg: 0.25,
        path: [],
        marks: [
          DiagramPoint(
            x: -0.1,
            y: 0.2,
            utc: '2025-09-07 18:11:48',
            label: '食甚',
          ),
        ],
      ),
      phases: const [
        EclipsePhase(
          code: 'Max',
          name: '食甚',
          utc: '2025-09-07 18:11:48',
          sublunar: GeoPoint(latitudeDeg: -6, longitudeDeg: 87),
        ),
      ],
      penumbralMinutes: 326.7,
      partialMinutes: 209.4,
      totalMinutes: 82.1,
      saros: '128（第 41 次，共 71 次）',
      local: LocalLunarView(
        verdict: LunarVisibility.full,
        totalityVisible: true,
        trackAltitudeDeg: Float64List(0),
        moonEvents: const [],
      ),
    );
    Future<void> pump(Place? place) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Center(
          child: SizedBox.fromSize(
            size: posterSize,
            child: EclipsePoster(event: event, detail: detail, place: place),
          ),
        ),
      ),
    );

    await pump(null);
    expect(find.text('月全食'), findsOneWidget);
    expect(find.text('1 小时 22 分'), findsOneWidget);
    expect(find.text('1.362'), findsOneWidget);
    expect(find.textContaining('40°N'), findsNothing);
    expect(find.bySemanticsLabel(posterSiteUrl), findsOneWidget);

    await pump(const Place(39.9042, 116.4074, 44));
    expect(find.text('在 40°N 116°E · 全程可见'), findsOneWidget);
    // 精确坐标不会出现在图上
    expect(find.textContaining('39.9'), findsNothing);
  });
}
