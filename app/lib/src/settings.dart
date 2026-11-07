import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';

/// 观测位置从哪里来。
enum LocationMode { gps, manual }

/// 应用外观主题模式。
enum AppThemeMode {
  /// 跟随系统深浅色设置（深色时使用深空暗夜）
  system,

  /// 深空暗夜模式（OLED 纯黑与星空冷蓝调）
  deepSpace,

  /// 天文夜间红光模式（专为户外实地观星暗适应设计）
  astroRed,

  /// 明亮浅色模式
  light,
}

/// 一个观测位置：纬度、经度（东正）、高度（米）。
@immutable
class Place {
  const Place(this.lat, this.lon, this.height);

  final double lat;
  final double lon;
  final double height;

  /// 默认的手动位置：北京
  static const beijing = Place(39.9, 116.4, 50);

  bool get isValid =>
      lat.isFinite &&
      lon.isFinite &&
      height.isFinite &&
      lat.abs() <= 90 &&
      lon.abs() <= 180;

  String describe() {
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}°$ns '
        '${lon.abs().toStringAsFixed(4)}°$ew '
        '${height.round()} m';
  }

  Map<String, double> toJson() => {'lat': lat, 'lon': lon, 'height': height};

  static Place? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = (j['lat'] as num?)?.toDouble();
    final lon = (j['lon'] as num?)?.toDouble();
    final h = (j['height'] as num?)?.toDouble();
    if (lat == null || lon == null || h == null) return null;
    final p = Place(lat, lon, h);
    return p.isValid ? p : null;
  }
}

/// 定位失败的原因。
enum LocationError { serviceOff, denied, deniedForever, timeout, unavailable }

class LocationException implements Exception {
  const LocationException(this.error, [this.detail]);

  final LocationError error;
  final String? detail;

  String describe(AppLocalizations l) => switch (error) {
    LocationError.serviceOff => l.locServiceOff,
    LocationError.denied => l.locDenied,
    LocationError.deniedForever => l.locDeniedForever,
    LocationError.timeout => l.locTimeout,
    LocationError.unavailable => l.locUnavailable(detail ?? ''),
  };

  @override
  String toString() => 'LocationException($error, $detail)';
}

/// 取得一次 GPS 定位。测试时可替换。
typedef Locator = Future<Place> Function();

/// 应用设置：观测位置。保存在应用支持目录的 settings.json，只在本机。
class Settings extends ChangeNotifier {
  Settings._(this._file, this._locator);

  /// 测试用：不读写文件。
  Settings.inMemory({Locator? locator})
    : _file = null,
      _locator = locator ?? _gpsLocate;

  final File? _file;
  final Locator _locator;

  LocationMode _mode = LocationMode.gps;
  AppThemeMode _themeMode = AppThemeMode.system;
  bool? _amapConsent;
  Place _manual = Place.beijing;
  Place? _gpsFix;
  DateTime? _gpsTime;
  LocationException? _gpsError;
  Future<Place>? _locating;

  /// GPS 定位在这个时间内有效，超过后搜索时重新定位
  static const fixMaxAge = Duration(minutes: 10);

  LocationMode get mode => _mode;
  AppThemeMode get themeMode => _themeMode;

  /// 是否同意使用高德地图 SDK（隐私合规）。null 表示还没问过。
  bool? get amapConsent => _amapConsent;
  Place get manual => _manual;
  Place? get gpsFix => _gpsFix;

  /// 显示本地信息（今晚、月食详情）用的位置：手动模式用手动位置，GPS 模式用缓存的定位。
  /// 不会触发定位；都没有时为 null。
  Place? get knownPlace => _mode == LocationMode.manual
      ? (_manual.isValid ? _manual : null)
      : _gpsFix;

  /// 上次定位成功的时间（本地时间）
  DateTime? get gpsTime => _gpsTime;

  /// 最近一次定位失败的原因；定位成功后清空
  LocationException? get gpsError => _gpsError;
  bool get locating => _locating != null;

  static Future<Settings> open() async {
    final dir = await getApplicationSupportDirectory();
    return openFile(File('${dir.path}/settings.json'));
  }

  /// 从指定文件读设置（文件不存在时用默认值）。
  static Future<Settings> openFile(File file, {Locator? locator}) async {
    final s = Settings._(file, locator ?? _gpsLocate);
    try {
      if (await s._file!.exists()) {
        s._load(jsonDecode(await s._file.readAsString()));
      }
    } catch (_) {
      // 文件损坏时用默认值，下次保存时覆盖
    }
    return s;
  }

  void _load(Object? j) {
    if (j is! Map) return;
    _mode = j['mode'] == 'manual' ? LocationMode.manual : LocationMode.gps;
    _themeMode = switch (j['themeMode']) {
      'deepSpace' => AppThemeMode.deepSpace,
      'astroRed' => AppThemeMode.astroRed,
      'light' => AppThemeMode.light,
      _ => AppThemeMode.system,
    };
    final consent = j['amapConsent'];
    _amapConsent = consent is bool ? consent : null;
    _manual = Place.fromJson(j['manual']) ?? Place.beijing;
    _gpsFix = Place.fromJson(j['gpsFix']);
    _gpsTime = DateTime.tryParse(j['gpsTime'] as String? ?? '')?.toLocal();
    if (_gpsTime == null) _gpsFix = null;
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    final j = {
      'mode': _mode.name,
      'themeMode': _themeMode.name,
      'amapConsent': ?_amapConsent,
      'manual': _manual.toJson(),
      if (_gpsFix != null && _gpsTime != null) ...{
        'gpsFix': _gpsFix!.toJson(),
        'gpsTime': _gpsTime!.toUtc().toIso8601String(),
      },
    };
    try {
      await f.writeAsString(jsonEncode(j));
    } catch (_) {
      // 写不进去只影响下次启动，不打断使用
    }
  }

  Future<void> setThemeMode(AppThemeMode m) async {
    if (_themeMode == m) return;
    _themeMode = m;
    notifyListeners();
    await _save();
  }

  Future<void> setAmapConsent(bool agree) async {
    if (agree == _amapConsent) return;
    _amapConsent = agree;
    notifyListeners();
    await _save();
  }

  Future<void> setMode(LocationMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    await _save();
  }

  Future<void> setManual(Place p) async {
    if (!p.isValid) return;
    _manual = p;
    notifyListeners();
    await _save();
  }

  /// 立即定位一次。同一时间只发起一个请求。
  Future<Place> locate() {
    final pending = _locating;
    if (pending != null) return pending;
    final f = _locate();
    _locating = f;
    notifyListeners();
    return f;
  }

  Future<Place> _locate() async {
    // 先让出一次，保证 _locating 在 finally 清空之前已经赋值
    await Future<void>.delayed(Duration.zero);
    try {
      final p = await _locator();
      _gpsFix = p;
      // 定位结果同时作为手动位置的默认值：之后切到手动时从这里开始改
      _manual = p;
      _gpsTime = DateTime.now();
      _gpsError = null;
      await _save();
      return p;
    } on LocationException catch (e) {
      _gpsError = e;
      rethrow;
    } catch (e) {
      _gpsError = LocationException(LocationError.unavailable, e.toString());
      throw _gpsError!;
    } finally {
      _locating = null;
      notifyListeners();
    }
  }

  /// 搜索时用的位置。手动模式直接返回；GPS 模式下定位不超过 10 分钟就沿用，否则重新定位，
  /// 定位失败时退回上次的定位（[PlaceResult.stale] 为 true），从未定位成功则抛出
  /// [LocationException]。
  Future<PlaceResult> place() => placeWithMaxAge(fixMaxAge);

  /// 同 [place]，可指定定位的有效期（测试用）。
  @visibleForTesting
  Future<PlaceResult> placeWithMaxAge(Duration maxAge) async {
    if (_mode == LocationMode.manual) return PlaceResult(_manual);
    final fix = _gpsFix;
    final t = _gpsTime;
    if (fix != null && t != null && DateTime.now().difference(t) < maxAge) {
      return PlaceResult(fix);
    }
    try {
      return PlaceResult(await locate());
    } on LocationException {
      if (fix != null) return PlaceResult(fix, stale: true);
      rethrow;
    }
  }
}

class PlaceResult {
  const PlaceResult(this.place, {this.stale = false});

  final Place place;

  /// GPS 定位失败，用的是上次的定位
  final bool stale;
}

Future<Place> _gpsLocate() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationException(LocationError.serviceOff);
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.deniedForever) {
    throw const LocationException(LocationError.deniedForever);
  }
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.unableToDetermine) {
    throw const LocationException(LocationError.denied);
  }
  Position pos;
  try {
    pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 30),
      ),
    );
  } on TimeoutException {
    Position? last;
    try {
      last = await Geolocator.getLastKnownPosition();
    } catch (_) {
      // 部分平台不支持
    }
    if (last == null) throw const LocationException(LocationError.timeout);
    pos = last;
  }
  // 没有高度（altitudeAccuracy 为 0 且高度为 0）时按海平面算；对天文事件影响很小
  return Place(pos.latitude, pos.longitude, pos.altitude);
}
