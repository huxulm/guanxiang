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

  test('月食图固定 4:5', () {
    expect(posterSize.aspectRatio, closeTo(0.8, 1e-9));
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
  testWidgets('日食分享图：打开观测地、英文长文案时高度撑开，不溢出', (tester) async {
    const event = EventItem(
      kind: EventKind.solarEclipse,
      title: 'Annular solar eclipse',
      utc: '2030-06-01 06:28:00',
      ttJd: 2462653.77,
      summary: 'Magnitude 0.944',
      details: [],
      subtle: false,
    );
    // 一条从西到东的中心线，栅格里有一块偏食区
    final grid = Float32List(90 * 180);
    for (var r = 30; r < 45; r++) {
      for (var c = 80; c < 120; c++) {
        grid[r * 180 + c] = 0.5;
      }
    }
    SolarDiskPoint pt(double s, double x) => SolarDiskPoint(
      seconds: s,
      xArcmin: x,
      yArcmin: 0,
      sunRadiusArcmin: 15.8,
      moonRadiusArcmin: 15.0,
      obscuration: 0.9,
      sunAltitudeDeg: 5,
      zenithAngleDeg: 0,
    );
    final detail = SolarEclipseDetail(
      diagram: const SolarEclipseDiagram(
        track: [],
        greatest: DiagramPoint(
          x: 0,
          y: 0.5,
          utc: '2030-06-01 06:28:00',
          label: 'Max',
        ),
        penumbraRadius: 0.55,
        umbraRadius: 0.02,
        axisDeclinationDeg: 22,
      ),
      saros: '128 (34 of 73)',
      centralLine: const [
        GeoPoint(latitudeDeg: 30, longitudeDeg: 0),
        GeoPoint(latitudeDeg: 45, longitudeDeg: 60),
        GeoPoint(latitudeDeg: 50, longitudeDeg: 120),
      ],
      pathWidthKm: Float64List.fromList([250, 250, 250]),
      greatestPoint: const GeoPoint(latitudeDeg: 45, longitudeDeg: 60),
      gridStepDeg: 2,
      gridRows: 90,
      gridCols: 180,
      grid: grid,
      local: LocalSolarView(
        verdict: SolarVisibility.sets,
        kind: LocalEclipseKind.annular,
        magnitude: 0.944,
        obscuration: 0.89,
        phases: const [
          SolarPhase(
            code: 'Max',
            name: 'Maximum',
            utc: '2030-06-01 06:28:00',
            sun: SunPoint(altitudeDeg: 5, azimuthDeg: 300),
          ),
        ],
        centralSeconds: 303,
        trackStartUtc: '2030-06-01 06:00:00.000',
        track: [pt(0, -20), pt(3600, 20)],
      ),
    );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: posterSize.width,
            height: posterHeightFor(detail),
            child: EclipsePoster(
              event: event,
              detail: detail,
              place: const Place(45.75, 126.65, 150),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('From 46°N 127°E'), findsOneWidget);
    expect(find.textContaining('ISO 12312-2'), findsOneWidget);
    expect(find.text('Annular phase'), findsOneWidget);
    expect(find.bySemanticsLabel(posterSiteUrl), findsOneWidget);
    // 高度按内容撑开，比固定的月食图高
    final h = tester.getSize(find.byType(EclipsePoster)).height;
    expect(h, greaterThan(posterSize.height));
  });
}
