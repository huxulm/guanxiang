import 'dart:io';

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'src/app.dart';
import 'src/celestrak.dart';
import 'src/rust/frb_generated.dart';

/// 后台刷新任务名（Android WorkManager）。
const ommRefreshTask = 'guanxiang.ommRefresh';

/// WorkManager 后台入口：在独立的 isolate 里运行，只刷新根数缓存，不需要 Rust。
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != ommRefreshTask) return true;
    try {
      final store = await OmmStore.open();
      await store.refreshAll();
      return true;
    } catch (_) {
      // 返回 false 会让 WorkManager 按退避策略重试；网络问题等下一个周期即可
      return true;
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
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
