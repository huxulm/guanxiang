import 'dart:io';

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'src/app.dart';
import 'src/celestrak.dart';
import 'src/tasks.dart';
import 'src/licenses.dart';
import 'src/rust/frb_generated.dart';
import 'src/task_service.dart';

/// 后台刷新任务名（Android WorkManager）。
const ommRefreshTask = 'guanxiang.ommRefresh';

/// WorkManager 后台入口，在独立的 isolate 里运行：
/// - 周期任务：刷新根数缓存，再执行到期的后台任务（持续监视）；
/// - 一次性任务：提交任务后立即执行；一次最多 8 分钟（WorkManager 限 10 分钟），没算完就再安排一次。
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      if (task == ommRefreshTask) {
        await (await OmmStore.open()).refreshAll();
      }
      if (task == ommRefreshTask || task == runTasksTask) {
        if (!await _hasActiveTasks()) return true;
        WidgetsFlutterBinding.ensureInitialized();
        await RustLib.init();
        final runner = await buildRunner(await loadEngine());
        if (await runner.runDue()) await scheduleTasks();
      }
      return true;
    } catch (_) {
      // 返回 false 会让 WorkManager 按退避策略重试；网络问题等下一个周期即可
      return true;
    }
  });
}

Future<bool> _hasActiveTasks() async =>
    (await (await TaskStore.open()).load()).any((t) => t.active);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  registerLicenses();
  await Notifications.init();
  if (Platform.isAndroid) {
    // 每 6 小时刷新一次（OmmStore 内部仍遵守 2 小时的频率限制），只在联网时运行
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      ommRefreshTask,
      ommRefreshTask,
      frequency: const Duration(hours: 6),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
  runApp(const GuanxiangApp());
}
