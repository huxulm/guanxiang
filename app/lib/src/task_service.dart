import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart'
    show ExistingWorkPolicy, Workmanager;

import '../l10n/app_localizations.dart';
import 'celestrak.dart';
import 'rust/api/guanxiang.dart';
import 'tasks.dart';

/// 一次性任务的名字（Android WorkManager）：提交任务后马上安排，算不完会再安排一次。
const runTasksTask = 'guanxiang.runTasks';

/// 后台没有 BuildContext，按系统语言选文字：中文系统用中文，其他用英文。
Locale systemLocale() => PlatformDispatcher.instance.locale.languageCode == 'zh'
    ? const Locale('zh')
    : const Locale('en');

Lang langOf(Locale l) => l.languageCode == 'zh' ? Lang.zh : Lang.en;

/// 把 Rust 输出的 UTC 时刻（"2026-11-07 06:52:01"）换成本地时间文字。
String localTimeText(String utc) {
  final t = DateTime.tryParse('${utc.trim().replaceFirst(' ', 'T')}Z');
  if (t == null) return '$utc UTC';
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

String taskName(AppLocalizations l, SatTask t) => switch (t.kind) {
  TaskKind.longSearch => l.taskLongName(t.days.round()),
  TaskKind.watch => l.taskWatchName(
    t.deadline == null
        ? ''
        : localTimeText(_utcText(t.deadline!)).substring(5, 16),
  ),
};

String _utcText(DateTime t) =>
    t.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ');

class L10nTaskTexts implements TaskTexts {
  L10nTaskTexts(this.l);

  final AppLocalizations l;

  @override
  String hitTitle(SatTask t, SatTransitItem e) => e.isTransit
      ? l.taskHitTitle(e.satellite)
      : l.taskNearbyTitle(
          e.satellite,
          e.distanceToCenterlineKm.toStringAsFixed(0),
        );

  @override
  String hitBody(SatTask t, SatTransitItem e) =>
      '${localTimeText(e.utc)} · ${e.summary}';

  @override
  String finishedTitle(SatTask t) => switch (t.status) {
    TaskStatus.timeout => l.taskTimeoutTitle(taskName(l, t)),
    _ => l.taskDoneTitle(taskName(l, t)),
  };

  @override
  String finishedBody(SatTask t) =>
      l.taskDoneBody(t.hits.length, t.items.length);
}

/// 通知。Android 13+ 需要用户授权，提交任务时请求。
class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_notify'),
          windows: WindowsInitializationSettings(
            appName: '观象',
            appUserModelId: 'Guanxiang.Guanxiang',
            guid: '5d0f2a1e-7c4b-4e8a-9b3f-2a6c8d1e4f70',
          ),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        ),
      );
      _ready = true;
    } catch (_) {
      // 通知不可用时任务照常运行，结果在任务历史里看
    }
  }

  /// 请求通知权限（Android 13+）。其他平台直接返回 true。
  static Future<bool> requestPermission() async {
    await init();
    if (!Platform.isAndroid) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static Future<void> show(String title, String body, String taskId) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: taskId.hashCode & 0x7fffffff ^ body.hashCode & 0xffff,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'tasks',
            'Background tasks',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_notify',
          ),
        ),
        payload: taskId,
      );
    } catch (_) {}
  }
}

/// 用缓存的根数搜索。没有缓存的卫星跳过。
SatSearch makeSearch(Engine engine, OmmStore omm, Lang lang) =>
    ({
      required noradId,
      required place,
      required startUtc,
      required days,
      required maxSeparationDeg,
      required radiusKm,
    }) async {
      final c = await omm.cached(noradId);
      if (c.json == null) return [];
      return satelliteTransits(
        engine: engine,
        ommJson: c.json!,
        previousOmmJson: c.previousJson,
        latitudeDeg: place.lat,
        longitudeDeg: place.lon,
        heightM: place.height,
        startUtc: startUtc.toUtc().toIso8601String(),
        days: days,
        maxSeparationDeg: maxSeparationDeg,
        radiusKm: radiusKm,
        lang: lang,
      );
    };

Future<TaskRunner> buildRunner(Engine engine, {Locale? locale}) async {
  final loc = locale ?? systemLocale();
  final omm = await OmmStore.open();
  return TaskRunner(
    store: await TaskStore.open(),
    search: makeSearch(engine, omm, langOf(loc)),
    texts: L10nTaskTexts(lookupAppLocalizations(loc)),
    refresh: (ids) async {
      for (final id in ids) {
        await omm.refresh(id);
      }
    },
    notify: Notifications.show,
  );
}

/// 安排执行任务：Android 交给 WorkManager（应用关闭也能运行）；其他平台在本进程里执行。
Future<void> scheduleTasks() async {
  if (Platform.isAndroid) {
    await Workmanager().registerOneOffTask(
      runTasksTask,
      runTasksTask,
      existingWorkPolicy: ExistingWorkPolicy.append,
    );
  } else {
    ForegroundTaskScheduler.instance.kick();
  }
}

/// 非 Android 平台：应用打开期间每 10 分钟检查一次任务，提交任务时立即执行。
class ForegroundTaskScheduler {
  ForegroundTaskScheduler._();

  static final instance = ForegroundTaskScheduler._();

  Engine? _engine;
  Timer? _timer;
  bool _running = false;
  bool _again = false;

  void start(Engine engine) {
    if (Platform.isAndroid || _engine != null) return;
    _engine = engine;
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => kick());
    kick();
  }

  Future<void> kick() async {
    final engine = _engine;
    if (engine == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final runner = await buildRunner(engine);
        // 前台不限时：长跨度搜索一直算到完成或到达任务自己的计算时间上限
        while (await runner.runDue(budget: const Duration(minutes: 30))) {}
      } while (_again);
    } finally {
      _running = false;
    }
  }

  void stop() => _timer?.cancel();
}
