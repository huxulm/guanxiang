import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

import 'errors.dart';
import 'rust/api/guanxiang.dart';
import 'search_page.dart';
import 'settings.dart';
import 'task_service.dart';

/// 随应用打包的星历：de440s 裁剪到 1899-12 至 2101-02（22 MB，原 33 MB）。三端都从 asset
/// 读成字节交给 Rust，Android 上不需要先释放到磁盘。
const ephemerisAsset = 'assets/de440s_1900_2100.bsp';

/// 加载随应用打包的星历（界面和后台任务都用）。
Future<Engine> loadEngine() async {
  final data = await rootBundle.load(ephemerisAsset);
  return Engine.fromBytes(bytes: data.buffer.asUint8List());
}

class GuanxiangApp extends StatelessWidget {
  const GuanxiangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      // 跟随系统语言；既不是中文也不是英文时用英文（列表第一项）
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F3A68)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F3A68),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LoadingPage(),
    );
  }
}

/// 启动时加载星历。
class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final watch = Stopwatch()..start();
      final engine = await loadEngine();
      final ms = watch.elapsedMilliseconds;
      final settings = await Settings.open();
      // 非 Android 平台在应用打开期间执行后台任务
      ForegroundTaskScheduler.instance.start(engine);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              SearchPage(engine: engine, loadMs: ms, settings: settings),
        ),
      );
    } catch (e) {
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l.loadingEphemeris),
                  ],
                )
              : Text(
                  l.ephemerisLoadFailed(describeError(_error!, l)),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
        ),
      ),
    );
  }
}
