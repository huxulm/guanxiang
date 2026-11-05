import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';

/// 默认关注的卫星：NORAD 编号 → 内部名称（界面上按语言显示，见 [satelliteDisplayName]）。
const defaultSatellites = {25544: 'ISS', 48274: 'Tiangong'};

/// 关注列表中卫星的显示名：默认卫星按语言显示，其他用保存的名称。
String satelliteDisplayName(AppLocalizations l, int id, String stored) =>
    switch (id) {
      25544 => l.issName,
      48274 => l.cssName,
      _ => stored,
    };

/// CelesTrak 根数约每 2 小时更新一次。同一颗卫星 2 小时内只请求一次。
const minFetchInterval = Duration(hours: 2);

/// 请求失败（非 200）后暂停请求的时长。CelesTrak 会封禁反复出错的客户端。
const errorBackoff = Duration(hours: 2);

/// 本应用发出的 HTTP 请求统一使用的 User-Agent（CelesTrak、地图瓦片）。
const appUserAgent =
    'guanxiang/0.1 (+https://gitlab.xao.ac.cn/xulingming/guanxiang)';

Uri celestrakUrl(int noradId) => Uri.https(
  'celestrak.org',
  '/NORAD/elements/gp.php',
  {'CATNR': '$noradId', 'FORMAT': 'JSON'},
);

/// 一颗卫星在本地缓存中的状态。
class CachedOmm {
  CachedOmm({
    required this.noradId,
    this.json,
    this.previousJson,
    this.fetchedAt,
    this.epoch,
  });

  final int noradId;

  /// 当前根数（OMM JSON 数组）；从未下载过为 null
  final String? json;

  /// 上一份根数，用于比较新旧预报
  final String? previousJson;

  /// 上次成功下载的时间（UTC）
  final DateTime? fetchedAt;

  /// 根数历元（OMM 的 EPOCH 字段，UTC）
  final String? epoch;
}

/// 刷新结果的种类。文字由界面按语言生成（[RefreshResult.describe]），
/// 后台任务里没有界面上下文也能用。
enum RefreshStatus {
  /// 之前出错，暂停请求
  blocked,

  /// 2 小时内下载过
  recent,

  /// 网络不通
  network,

  /// CelesTrak 返回非 200
  http,

  /// 返回内容不是这颗卫星的根数
  invalid,

  /// 拿到了新历元的根数
  updated,

  /// 根数没有变化
  unchanged,
}

/// 一次刷新的结果。
class RefreshResult {
  RefreshResult(
    this.noradId,
    this.status, {
    this.minutes = 0,
    this.httpStatus = 0,
    this.epoch = '',
    this.detail,
  });

  final int noradId;
  final RefreshStatus status;
  final int minutes;
  final int httpStatus;
  final String epoch;

  /// network：异常；invalid：返回内容的开头
  final Object? detail;

  bool get updated => status == RefreshStatus.updated;
  bool get error => switch (status) {
    RefreshStatus.blocked ||
    RefreshStatus.network ||
    RefreshStatus.http ||
    RefreshStatus.invalid => true,
    _ => false,
  };

  String describe(AppLocalizations l) => switch (status) {
    RefreshStatus.blocked => l.refreshBlocked,
    RefreshStatus.recent => l.refreshRecent(minutes),
    RefreshStatus.network => l.refreshNetwork(describeError(detail!, l)),
    RefreshStatus.http => l.refreshHttp(httpStatus),
    RefreshStatus.invalid => l.refreshInvalid(noradId, '$detail'),
    RefreshStatus.updated => l.refreshUpdated(epoch),
    RefreshStatus.unchanged => l.refreshUnchanged(epoch),
  };
}

/// 从 OMM JSON 取出编号和历元，不调用 Rust（后台任务里也能用）。
({int noradId, String epoch})? ommSummary(String json) {
  try {
    final list = jsonDecode(json);
    if (list is! List || list.isEmpty) return null;
    final first = list.first;
    if (first is! Map) return null;
    final id = first['NORAD_CAT_ID'];
    final epoch = first['EPOCH'];
    if (id is! int || epoch is! String) return null;
    return (noradId: id, epoch: epoch);
  } on FormatException {
    return null;
  }
}

/// CelesTrak 根数的下载与本地缓存（D5：网络只在 Dart 端）。
///
/// 目录结构：`<应用支持目录>/omm/<编号>.json`（当前）、`<编号>.prev.json`（上一份）、
/// `meta.json`（下载时间、出错暂停时间）。前台和 WorkManager 后台任务共用这份缓存，
/// 频率限制记在 `meta.json` 里，两边都遵守。
class OmmStore {
  OmmStore._(this.dir, {http.Client? client})
    : _client = client ?? http.Client();

  final Directory dir;
  final http.Client _client;

  /// 本次运行中遇到过非 200 响应，不再请求
  static bool _blockedThisSession = false;

  static Future<OmmStore> open({
    http.Client? client,
    Directory? baseDir,
  }) async {
    final base = baseDir ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}omm');
    await dir.create(recursive: true);
    return OmmStore._(dir, client: client);
  }

  File _file(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  Future<Map<String, dynamic>> _readMeta() async {
    final f = _file('meta.json');
    if (!await f.exists()) return {};
    try {
      final m = jsonDecode(await f.readAsString());
      return m is Map<String, dynamic> ? m : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeMeta(Map<String, dynamic> meta) async {
    final f = _file('meta.json.tmp');
    await f.writeAsString(jsonEncode(meta), flush: true);
    await f.rename(_file('meta.json').path);
  }

  Future<String?> _readOptional(String name) async {
    final f = _file(name);
    return await f.exists() ? f.readAsString() : null;
  }

  /// 关注列表（编号 → 名称）。
  Future<Map<int, String>> watchList() async {
    final meta = await _readMeta();
    final list = meta['watch'];
    if (list is! Map) return Map.of(defaultSatellites);
    return {
      for (final e in list.entries)
        if (int.tryParse('${e.key}') != null)
          int.parse('${e.key}'): '${e.value}',
    };
  }

  Future<void> setWatchList(Map<int, String> list) async {
    final meta = await _readMeta();
    meta['watch'] = {for (final e in list.entries) '${e.key}': e.value};
    await _writeMeta(meta);
  }

  Future<CachedOmm> cached(int noradId) async {
    final meta = await _readMeta();
    final m = (meta['sats'] as Map?)?['$noradId'] as Map?;
    final json = await _readOptional('$noradId.json');
    return CachedOmm(
      noradId: noradId,
      json: json,
      previousJson: await _readOptional('$noradId.prev.json'),
      fetchedAt: DateTime.tryParse('${m?['fetchedAt']}'),
      epoch: json == null ? null : ommSummary(json)?.epoch,
    );
  }

  /// 刷新一颗卫星的根数。遵守频率限制：2 小时内下载过就不再请求；
  /// 出错后本次运行不再请求，并在 [errorBackoff] 内不再请求（后台任务也遵守）。
  Future<RefreshResult> refresh(int noradId, {DateTime? now}) async {
    now ??= DateTime.now().toUtc();
    final meta = await _readMeta();
    final blockedUntil = DateTime.tryParse('${meta['blockedUntil']}');
    if (_blockedThisSession ||
        (blockedUntil != null && now.isBefore(blockedUntil))) {
      return RefreshResult(noradId, RefreshStatus.blocked);
    }
    final sats =
        (meta['sats'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final last = DateTime.tryParse(
      '${(sats['$noradId'] as Map?)?['fetchedAt']}',
    );
    if (last != null && now.difference(last) < minFetchInterval) {
      return RefreshResult(
        noradId,
        RefreshStatus.recent,
        minutes: now.difference(last).inMinutes,
      );
    }

    http.Response resp;
    try {
      resp = await _client
          .get(celestrakUrl(noradId), headers: {'User-Agent': appUserAgent})
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      // 网络不通不算 CelesTrak 出错，不暂停
      return RefreshResult(noradId, RefreshStatus.network, detail: e);
    }
    if (resp.statusCode != 200) {
      _blockedThisSession = true;
      meta['blockedUntil'] = now.add(errorBackoff).toIso8601String();
      await _writeMeta(meta);
      return RefreshResult(
        noradId,
        RefreshStatus.http,
        httpStatus: resp.statusCode,
      );
    }
    final body = utf8.decode(resp.bodyBytes);
    final summary = ommSummary(body);
    // 记下请求时间：即使内容无效（如编号不存在）也不要立刻重复请求
    sats['$noradId'] = {'fetchedAt': now.toIso8601String()};
    meta['sats'] = sats;
    if (summary == null || summary.noradId != noradId) {
      await _writeMeta(meta);
      final hint = body.length > 80 ? '${body.substring(0, 80)}…' : body;
      return RefreshResult(noradId, RefreshStatus.invalid, detail: hint);
    }
    final current = await _readOptional('$noradId.json');
    final currentEpoch = current == null ? null : ommSummary(current)?.epoch;
    final updated = currentEpoch != summary.epoch;
    if (updated && current != null) {
      await _file('$noradId.prev.json').writeAsString(current, flush: true);
    }
    if (updated) {
      final tmp = _file('$noradId.json.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(_file('$noradId.json').path);
    }
    await _writeMeta(meta);
    return RefreshResult(
      noradId,
      updated ? RefreshStatus.updated : RefreshStatus.unchanged,
      epoch: summary.epoch,
    );
  }

  /// 刷新关注列表中的全部卫星（后台任务也调用这个）。
  Future<List<RefreshResult>> refreshAll() async {
    final out = <RefreshResult>[];
    for (final id in (await watchList()).keys) {
      out.add(await refresh(id));
    }
    return out;
  }

  /// 测试用：清除本次运行的出错标记。
  static void resetSessionBlockForTest() => _blockedThisSession = false;
}
