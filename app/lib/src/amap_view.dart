import 'package:amap_map/amap_map.dart' as amap;
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart' as amapb;

import 'amap_support.dart';
import 'gcj02.dart';

/// 卫星凌日地图（高德）：地面中心线、测站和测站到中心线最近点的连线。
///
/// 输入是 WGS-84 坐标，在这里换成高德底图使用的 GCJ-02。
class AmapTransitMap extends StatelessWidget {
  const AmapTransitMap({
    super.key,
    required this.observer,
    required this.nearest,
    required this.centerline,
    required this.lineColor,
    required this.observerLineColor,
    required this.english,
  });

  final (double, double) observer;
  final (double, double) nearest;
  final List<(double, double)> centerline;
  final Color lineColor;
  final Color observerLineColor;
  final bool english;

  amapb.LatLng _gcj((double, double) p) {
    final (lat, lon) = wgs84ToGcj02(p.$1, p.$2);
    return amapb.LatLng(lat, lon);
  }

  @override
  Widget build(BuildContext context) {
    ensureAmapInitialized(context);
    final obs = _gcj(observer);
    final near = _gcj(nearest);
    final line = [for (final p in centerline) _gcj(p)];
    final all = [obs, near, ...line];
    var (s, w, n, e) = (90.0, 180.0, -90.0, -180.0);
    for (final p in all) {
      s = p.latitude < s ? p.latitude : s;
      n = p.latitude > n ? p.latitude : n;
      w = p.longitude < w ? p.longitude : w;
      e = p.longitude > e ? p.longitude : e;
    }
    final bounds = amapb.LatLngBounds(
      southwest: amapb.LatLng(s, w),
      northeast: amapb.LatLng(n, e),
    );
    return amap.AMapWidget(
      initialCameraPosition: amap.CameraPosition(
        target: amapb.LatLng((s + n) / 2, (w + e) / 2),
        zoom: 10,
      ),
      mapLanguage: english
          ? amap.MapLanguage.english
          : amap.MapLanguage.chinese,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scaleEnabled: true,
      onMapCreated: (c) =>
          c.moveCamera(amap.CameraUpdate.newLatLngBounds(bounds, 48)),
      polylines: {
        amap.Polyline(points: line, color: lineColor, width: 10),
        amap.Polyline(
          points: [obs, near],
          color: observerLineColor,
          width: 5,
          dashLineType: amap.DashLineType.square,
        ),
      },
      markers: {amap.Marker(position: obs)},
    );
  }
}
