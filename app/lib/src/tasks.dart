import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'rust/api/guanxiang.dart';
import 'settings.dart' show Place;

/// 后台卫星凌日任务。
///
/// - 长跨度搜索：用当前缓存的根数一次搜完 [SatTask.days] 天，按 7 天一段计算，可以中断后接着算；
///   超过 [SatTask.maxRuntimeMinutes] 的计算时间就停止（状态“到时”）。超过两周的结果只能作大致参考。
/// - 持续监视：到 [SatTask.deadline] 为止，每隔 [watchInterval] 刷新根数、重新搜索接下来 14 天，
///   出现凌日凌月（或范围内可见）时通知。结果始终基于最新根数。
///
/// 两种任务都可以设“找到就停止”。任务保存在应用支持目录的 tasks.json；Android 上由 WorkManager
/// 在后台执行（应用关闭也能运行），其他平台在应用打开时执行。
enum TaskKind { longSearch, watch }

enum TaskStatus { pending, running, done, timeout, cancelled, failed }

/// 长跨度搜索的分段长度（天）。
const chunkDays = 7.0;

/// 持续监视两次搜索之间的间隔。CelesTrak 的根数大约每 2 小时更新，这里不必更频繁。
const watchInterval = Duration(hours: 4);

/// 持续监视每次搜索的跨度（天）：根数只在两周内可靠。
const watchHorizonDays = 14.0;

/// 同一卫星、同一天体、时刻相差不到 2 分钟的两个预报视为同一事件（根数更新后时刻会移动）。
bool sameEvent(SatTransitItem a, SatTransitItem b) =>
    a.noradId == b.noradId &&
    a.body == b.body &&
    (a.ttJd - b.ttJd).abs() * 86400 < 120;

class SatTask {
  SatTask({
    required this.id,
    required this.kind,
    required this.created,
    required this.noradIds,
    required this.place,
    required this.maxSeparationDeg,
    required this.radiusKm,
    required this.stopOnHit,
    this.start,
    this.days = 0,
    this.maxRuntimeMinutes = 10,
    this.deadline,
    this.status = TaskStatus.pending,
    this.searchedDays = 0,
    this.runtimeMs = 0,
    this.lastRun,
    this.finished,
    this.error,
    List<SatTransitItem>? items,
    List<SatTransitItem>? notified,
  }) : items = items ?? [],
       notified = notified ?? [];

  final String id;
  final TaskKind kind;
  final DateTime created;
  final List<int> noradIds;
  final Place place;
  final double maxSeparationDeg;

  /// 范围搜索半径（km），0 表示只看测站
  final double radiusKm;

  /// 出现凌日凌月（或范围内可见）就结束任务
  final bool stopOnHit;

  /// 长跨度搜索：起始时刻（UTC）、天数、最长计算时间
  final DateTime? start;
  final double days;
  final int maxRuntimeMinutes;

  /// 持续监视：截止时刻（UTC）
  final DateTime? deadline;

  TaskStatus status;

  /// 长跨度搜索已完成的天数
  double searchedDays;

  /// 累计计算时间
  int runtimeMs;
  DateTime? lastRun;
  DateTime? finished;
  String? error;

  /// 找到的事件（按时刻排序）
  List<SatTransitItem> items;

  /// 已经通知过的命中事件
  List<SatTransitItem> notified;

  bool get active =>
      status == TaskStatus.pending || status == TaskStatus.running;

  /// 命中：在测站看到凌日凌月，或范围搜索时中心线在半径内经过（到中心线上可以看到）。
  bool isHit(SatTransitItem e) =>
      e.isTransit || (radiusKm > 0 && e.distanceToCenterlineKm <= radiusKm);

  List<SatTransitItem> get hits => items.where(isHit).toList();

  /// 0–1 的进度；持续监视按时间算
  double progress(DateTime now) => switch (kind) {
    TaskKind.longSearch => days <= 0 ? 1 : (searchedDays / days).clamp(0, 1),
    TaskKind.watch =>
      deadline == null
          ? 0
          : (now.difference(created).inSeconds /
                    deadline!.difference(created).inSeconds)
                .clamp(0, 1),
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'created': created.toUtc().toIso8601String(),
    'noradIds': noradIds,
    'place': place.toJson(),
    'maxSeparationDeg': maxSeparationDeg,
    'radiusKm': radiusKm,
    'stopOnHit': stopOnHit,
    'start': start?.toUtc().toIso8601String(),
    'days': days,
    'maxRuntimeMinutes': maxRuntimeMinutes,
    'deadline': deadline?.toUtc().toIso8601String(),
    'status': status.name,
    'searchedDays': searchedDays,
    'runtimeMs': runtimeMs,
    'lastRun': lastRun?.toUtc().toIso8601String(),
    'finished': finished?.toUtc().toIso8601String(),
    'error': error,
    'items': [for (final e in items) satItemToJson(e)],
    'notified': [for (final e in notified) satItemToJson(e)],
  };

  static SatTask fromJson(Map<String, dynamic> j) {
    DateTime? t(Object? v) => v is String ? DateTime.tryParse(v) : null;
    double d(Object? v) => (v as num?)?.toDouble() ?? 0;
    return SatTask(
      id: j['id'] as String,
      kind: TaskKind.values.byName(j['kind'] as String),
      created: t(j['created'])!,
      noradIds: [for (final n in j['noradIds'] as List) (n as num).toInt()],
      place: Place.fromJson(j['place']) ?? Place.beijing,
      maxSeparationDeg: d(j['maxSeparationDeg']),
      radiusKm: d(j['radiusKm']),
      stopOnHit: j['stopOnHit'] == true,
      start: t(j['start']),
      days: d(j['days']),
      maxRuntimeMinutes: (j['maxRuntimeMinutes'] as num?)?.toInt() ?? 10,
      deadline: t(j['deadline']),
      status: TaskStatus.values.byName(j['status'] as String),
      searchedDays: d(j['searchedDays']),
      runtimeMs: (j['runtimeMs'] as num?)?.toInt() ?? 0,
      lastRun: t(j['lastRun']),
      finished: t(j['finished']),
      error: j['error'] as String?,
      items: [
        for (final e in (j['items'] as List? ?? []))
          satItemFromJson(e as Map<String, dynamic>),
      ],
      notified: [
        for (final e in (j['notified'] as List? ?? []))
          satItemFromJson(e as Map<String, dynamic>),
      ],
    );
  }
}

Map<String, Object?> satItemToJson(SatTransitItem e) => {
  'noradId': e.noradId,
  'satellite': e.satellite,
  'body': e.body,
  'isTransit': e.isTransit,
  'title': e.title,
  'utc': e.utc,
  'ttJd': e.ttJd,
  'summary': e.summary,
  'details': [
    for (final d in e.details) [d.label, d.value],
  ],
  'distanceToCenterlineKm': e.distanceToCenterlineKm,
  'bandHalfWidthKm': e.bandHalfWidthKm,
  'elementsAgeDays': e.elementsAgeDays,
  'centerline': [
    for (final p in e.centerline) [p.latitudeDeg, p.longitudeDeg],
  ],
  'centerlineNearest': [
    e.centerlineNearest.latitudeDeg,
    e.centerlineNearest.longitudeDeg,
  ],
  'previousShiftS': e.previousShiftS,
  'previousShiftKm': e.previousShiftKm,
  'warning': e.warning,
};

SatTransitItem satItemFromJson(Map<String, dynamic> j) {
  double d(Object? v) => (v as num).toDouble();
  GeoPoint g(Object? v) {
    final l = v as List;
    return GeoPoint(latitudeDeg: d(l[0]), longitudeDeg: d(l[1]));
  }

  return SatTransitItem(
    noradId: (j['noradId'] as num).toInt(),
    satellite: j['satellite'] as String,
    body: j['body'] as String,
    isTransit: j['isTransit'] as bool,
    title: j['title'] as String,
    utc: j['utc'] as String,
    ttJd: d(j['ttJd']),
    summary: j['summary'] as String,
    details: [
      for (final x in j['details'] as List)
        Detail(label: (x as List)[0] as String, value: x[1] as String),
    ],
    distanceToCenterlineKm: d(j['distanceToCenterlineKm']),
    bandHalfWidthKm: d(j['bandHalfWidthKm']),
    elementsAgeDays: d(j['elementsAgeDays']),
    centerline: [for (final p in j['centerline'] as List) g(p)],
    centerlineNearest: g(j['centerlineNearest']),
    previousShiftS: (j['previousShiftS'] as num?)?.toDouble(),
    previousShiftKm: (j['previousShiftKm'] as num?)?.toDouble(),
    warning: j['warning'] as String?,
  );
}

/// 任务列表，保存在一个 JSON 文件里。后台 isolate 和界面可能同时读写，所以每次修改都重新读文件、
/// 只改一个任务再写回（先写临时文件再改名）。
class TaskStore {
  TaskStore(this.file);

  final File file;

  static Future<TaskStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return TaskStore(File('${dir.path}/tasks.json'));
  }

  Future<List<SatTask>> load() async {
    try {
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List;
      return [
        for (final j in list) SatTask.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<SatTask> tasks) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final t in tasks) t.toJson()]));
    await tmp.rename(file.path);
  }

  Future<void> add(SatTask t) async {
    final all = await load();
    all.add(t);
    await _write(all);
  }

  Future<void> delete(String id) async {
    final all = await load()
      ..removeWhere((t) => t.id == id);
    await _write(all);
  }

  Future<void> cancel(String id) => update(id, (t) {
    if (t.active) {
      t.status = TaskStatus.cancelled;
      t.finished = DateTime.now().toUtc();
    }
  });

  /// 修改一个任务。任务已被删除时返回 null；已被取消时不再修改，返回文件里的版本。
  Future<SatTask?> update(String id, void Function(SatTask) change) async {
    final all = await load();
    final i = all.indexWhere((t) => t.id == id);
    if (i < 0) return null;
    final t = all[i];
    if (t.status == TaskStatus.cancelled) return t;
    change(t);
    await _write(all);
    return t;
  }
}

/// 按卫星搜索一段时间（单次不超过 14 天）。
typedef SatSearch = Future<List<SatTransitItem>> Function({
  required int noradId,
  required Place place,
  required DateTime startUtc,
  required double days,
  required double maxSeparationDeg,
  required double radiusKm,
});

/// 发通知（标题、正文、任务 ID）。
typedef Notify = Future<void> Function(
  String title,
  String body,
  String taskId,
);

/// 通知文字。由调用方按语言生成，执行器不依赖界面。
abstract class TaskTexts {
  String hitTitle(SatTask t, SatTransitItem e);
  String hitBody(SatTask t, SatTransitItem e);
  String finishedTitle(SatTask t);
  String finishedBody(SatTask t);
}

class TaskRunner {
  TaskRunner({
    required this.store,
    required this.search,
    required this.texts,
    this.refresh,
    this.notify,
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime.now().toUtc());

  final TaskStore store;
  final SatSearch search;
  final TaskTexts texts;

  /// 刷新这些卫星的根数（遵守 CelesTrak 的频率限制）；持续监视每次搜索前调用
  final Future<void> Function(List<int> noradIds)? refresh;
  final Notify? notify;
  final DateTime Function() now;

  /// 执行所有到期的任务，最多用 [budget] 的时间。返回是否还有没算完的长跨度搜索（需要再安排一次）。
  Future<bool> runDue({Duration budget = const Duration(minutes: 8)}) async {
    final watch = Stopwatch()..start();
    var unfinished = false;
    for (final t in await store.load()) {
      if (!t.active) continue;
      try {
        switch (t.kind) {
          case TaskKind.longSearch:
            final left = await _runLong(t.id, budget - watch.elapsed);
            unfinished |= left;
          case TaskKind.watch:
            await _runWatch(t.id);
        }
      } catch (e) {
        await store.update(t.id, (x) {
          x.status = TaskStatus.failed;
          x.error = e.toString();
          x.finished = now();
        });
      }
      if (watch.elapsed >= budget) {
        unfinished = true;
        break;
      }
    }
    return unfinished;
  }

  Future<void> _notifyHits(SatTask t) async {
    final fresh = [
      for (final e in t.hits)
        if (!t.notified.any((n) => sameEvent(n, e))) e,
    ];
    if (fresh.isEmpty) return;
    await store.update(t.id, (x) => x.notified.addAll(fresh));
    for (final e in fresh) {
      await notify?.call(texts.hitTitle(t, e), texts.hitBody(t, e), t.id);
    }
  }

  Future<void> _finish(String id, TaskStatus status) async {
    final t = await store.update(id, (x) {
      x.status = status;
      x.finished = now();
    });
    if (t != null && t.status == status) {
      await notify?.call(texts.finishedTitle(t), texts.finishedBody(t), t.id);
    }
  }

  /// 长跨度搜索：一段一段算，每段写回文件。返回是否还没算完。
  Future<bool> _runLong(String id, Duration budget) async {
    final watch = Stopwatch()..start();
    while (true) {
      final all = await store.load();
      final t = all.where((x) => x.id == id).firstOrNull;
      if (t == null || !t.active) return false;
      if (t.searchedDays >= t.days - 1e-9) {
        await _finish(id, TaskStatus.done);
        return false;
      }
      if (t.runtimeMs >= t.maxRuntimeMinutes * 60000) {
        await _finish(id, TaskStatus.timeout);
        return false;
      }
      if (watch.elapsed >= budget) return true;

      final span = math.min(chunkDays, t.days - t.searchedDays);
      final from = t.start!.add(
        Duration(milliseconds: (t.searchedDays * 86400000).round()),
      );
      final sw = Stopwatch()..start();
      final found = <SatTransitItem>[];
      for (final id in t.noradIds) {
        found.addAll(
          await search(
            noradId: id,
            place: t.place,
            startUtc: from,
            days: span,
            maxSeparationDeg: t.maxSeparationDeg,
            radiusKm: t.radiusKm,
          ),
        );
      }
      final updated = await store.update(id, (x) {
        x.status = TaskStatus.running;
        x.items = [...x.items, ...found]
          ..sort((a, b) => a.ttJd.compareTo(b.ttJd));
        x.searchedDays += span;
        x.runtimeMs += sw.elapsedMilliseconds;
        x.lastRun = now();
      });
      if (updated == null || !updated.active) return false;
      // 长跨度搜索一次能找到几十个结果，不逐个通知，只在结束时发一条汇总
      if (updated.stopOnHit && updated.hits.isNotEmpty) {
        await _finish(id, TaskStatus.done);
        return false;
      }
    }
  }

  /// 持续监视：到期就结束；距上次搜索超过 [watchInterval] 就刷新根数并重搜接下来 14 天。
  Future<void> _runWatch(String id) async {
    final t = (await store.load()).where((x) => x.id == id).firstOrNull;
    if (t == null || !t.active) return;
    final n = now();
    if (t.deadline != null && !n.isBefore(t.deadline!)) {
      await _finish(id, TaskStatus.done);
      return;
    }
    if (t.lastRun != null && n.difference(t.lastRun!) < watchInterval) return;

    await refresh?.call(t.noradIds);
    final sw = Stopwatch()..start();
    final found = <SatTransitItem>[];
    for (final norad in t.noradIds) {
      found.addAll(
        await search(
          noradId: norad,
          place: t.place,
          startUtc: n,
          days: watchHorizonDays,
          maxSeparationDeg: t.maxSeparationDeg,
          radiusKm: t.radiusKm,
        ),
      );
    }
    // 已经过去的事件保留为历史；未来的部分换成最新根数的预报
    final nowJd = n.millisecondsSinceEpoch / 86400000 + 2440587.5;
    final updated = await store.update(id, (x) {
      x.status = TaskStatus.running;
      x.items = [...x.items.where((e) => e.ttJd < nowJd), ...found]
        ..sort((a, b) => a.ttJd.compareTo(b.ttJd));
      x.runtimeMs += sw.elapsedMilliseconds;
      x.lastRun = n;
    });
    if (updated == null || !updated.active) return;
    await _notifyHits(updated);
    if (updated.stopOnHit && updated.hits.isNotEmpty) {
      await _finish(id, TaskStatus.done);
    }
  }
}

/// 新任务的 ID：时间戳加随机数。
String newTaskId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${math.Random().nextInt(1 << 20).toRadixString(36)}';
