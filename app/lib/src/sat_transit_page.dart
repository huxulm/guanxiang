import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_localizations.dart';
import 'amap_support.dart';
import 'amap_view.dart';
import 'celestrak.dart' show appUserAgent;
import 'rust/api/guanxiang.dart';
import 'settings.dart';

/// 地图瓦片地址。OSM 瓦片政策建议不要把地址写死在多处，需要时在这里换成自建或商业瓦片。
const tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// 按 OSM 瓦片政策：使用本应用自己的 User-Agent；每块瓦片至少缓存 7 天（缓存上限 200 MB）。
final _tileProvider = NetworkTileProvider(
  headers: {'User-Agent': appUserAgent},
  cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
    overrideFreshAge: const Duration(days: 7),
    maxCacheSize: 200000000,
  ),
);

/// 一次卫星接近的详情：地面中心线地图 + 数据。
///
/// 底图：arm64 Android 上用户同意隐私说明后用高德地图，其他情况用 OpenStreetMap 瓦片。
/// 两者都需要联网；离线时地图空白，数据照常显示。
class SatTransitPage extends StatefulWidget {
  const SatTransitPage({
    super.key,
    required this.item,
    required this.observerLat,
    required this.observerLon,
    required this.settings,
  });

  final SatTransitItem item;
  final double observerLat;
  final double observerLon;
  final Settings settings;

  @override
  State<SatTransitPage> createState() => _SatTransitPageState();
}

class _SatTransitPageState extends State<SatTransitPage> {
  SatTransitItem get item => widget.item;
  double get observerLat => widget.observerLat;
  double get observerLon => widget.observerLon;

  @override
  void initState() {
    super.initState();
    // 第一次打开地图时询问是否使用高德地图
    if (amapSupported && widget.settings.amapConsent == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await askAmapConsent(context, widget.settings);
        if (mounted) setState(() {});
      });
    }
  }

  /// 经度换成与测站相差不超过 180° 的值，跨 180° 经线时折线不会绕地球一圈。
  double _unwrap(double lon) =>
      observerLon + ((lon - observerLon + 540) % 360 - 180);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final observer = LatLng(observerLat, observerLon);
    final line = [
      for (final p in item.centerline)
        LatLng(p.latitudeDeg, _unwrap(p.longitudeDeg)),
    ];
    final nearest = LatLng(
      item.centerlineNearest.latitudeDeg,
      _unwrap(item.centerlineNearest.longitudeDeg),
    );
    final points = [observer, nearest, ...line];
    final bounds = LatLngBounds.fromPoints(points);
    final lineColor = item.isTransit ? Colors.red : Colors.orange;

    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: ListView(
        children: [
          SizedBox(
            height: 320,
            child: useAmap(widget.settings)
                ? AmapTransitMap(
                    observer: (observerLat, observerLon),
                    nearest: (
                      item.centerlineNearest.latitudeDeg,
                      _unwrap(item.centerlineNearest.longitudeDeg),
                    ),
                    centerline: [
                      for (final p in item.centerline)
                        (p.latitudeDeg, _unwrap(p.longitudeDeg)),
                    ],
                    lineColor: lineColor,
                    observerLineColor: theme.colorScheme.primary,
                    english:
                        Localizations.localeOf(context).languageCode != 'zh',
                  )
                : FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(32),
                        maxZoom: 13,
                      ),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: tileUrlTemplate,
                        tileProvider: _tileProvider,
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: line,
                            color: lineColor,
                            strokeWidth: 4,
                          ),
                          Polyline(
                            points: [observer, nearest],
                            color: theme.colorScheme.primary,
                            strokeWidth: 2,
                            pattern: StrokePattern.dashed(
                              segments: const [6, 6],
                            ),
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: observer,
                            width: 32,
                            height: 32,
                            child: Icon(
                              Icons.person_pin_circle,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      RichAttributionWidget(
                        attributions: [TextSourceAttribution(l.osmAttribution)],
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${item.utc} UTC', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(item.summary, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  (item.body == 'sun'
                      ? l.centerlineHintSun
                      : l.centerlineHintMoon)(
                    item.bandHalfWidthKm.toStringAsFixed(2),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                if (item.warning != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: theme.colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber),
                      title: Text(item.warning!),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      for (final d in item.details)
                        ListTile(
                          dense: true,
                          title: Text(d.label),
                          subtitle: d.value.length > 30 ? Text(d.value) : null,
                          trailing: d.value.length > 30
                              ? null
                              : Text(d.value, style: theme.textTheme.bodyLarge),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
