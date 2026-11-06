import 'dart:math' as math;

/// WGS-84 → GCJ-02（国测局坐标）。
///
/// 高德等国内地图的底图使用 GCJ-02，直接画 WGS-84 坐标在国内会偏 300–700 米。境外两者相同，
/// 不做变换。算法是公开的标准近似公式（克拉索夫斯基椭球），与高德 SDK 的转换结果相差在米级。
(double, double) wgs84ToGcj02(double lat, double lon) {
  if (outOfChina(lat, lon)) return (lat, lon);
  const a = 6378245.0;
  const ee = 0.00669342162296594323;
  var dLat = _transformLat(lon - 105.0, lat - 35.0);
  var dLon = _transformLon(lon - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  dLon = (dLon * 180.0) / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return (lat + dLat, lon + dLon);
}

/// 粗略判断是否在中国境外（GCJ-02 只在境内偏移）。用经纬度矩形，边境附近可能不准。
bool outOfChina(double lat, double lon) =>
    lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;

double _transformLat(double x, double y) {
  var ret =
      -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  ret +=
      (20.0 * math.sin(6.0 * x * math.pi) +
          20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (160.0 * math.sin(y / 12.0 * math.pi) +
          320 * math.sin(y * math.pi / 30.0)) *
      2.0 /
      3.0;
  return ret;
}

double _transformLon(double x, double y) {
  var ret =
      300.0 +
      x +
      2.0 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs());
  ret +=
      (20.0 * math.sin(6.0 * x * math.pi) +
          20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (150.0 * math.sin(x / 12.0 * math.pi) +
          300.0 * math.sin(x / 30.0 * math.pi)) *
      2.0 /
      3.0;
  return ret;
}
