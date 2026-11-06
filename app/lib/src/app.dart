import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

import 'errors.dart';
import 'main_scaffold.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'task_service.dart';
import 'theme.dart';

/// 随应用打包的星历：de440s 裁剪到 1899-12 至 2101-02（22 MB，原 33 MB）。三端都从 asset
/// 读成字节交给 Rust，Android 上不需要先释放到磁盘。
const ephemerisAsset = 'assets/de440s_1900_2100.bsp';

/// 加载随应用打包的星历（界面和后台任务都用）。
Future<Engine> loadEngine() async {
  final data = await rootBundle.load(ephemerisAsset);
  return Engine.fromBytes(bytes: data.buffer.asUint8List());
}

class GuanxiangApp extends StatelessWidget {
  const GuanxiangApp({super.key, this.settings});

  final Settings? settings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    if (s != null) {
      return ListenableBuilder(
        listenable: s,
        builder: (context, _) => _buildApp(context, s.themeMode),
      );
    }
    return _buildApp(context, AppThemeMode.system);
  }

  Widget _buildApp(BuildContext context, AppThemeMode mode) {
    ThemeMode themeMode;
    ThemeData theme;
    ThemeData darkTheme;

    switch (mode) {
      case AppThemeMode.deepSpace:
        themeMode = ThemeMode.dark;
        theme = AstroTheme.deepSpaceTheme;
        darkTheme = AstroTheme.deepSpaceTheme;
      case AppThemeMode.astroRed:
        themeMode = ThemeMode.dark;
        theme = AstroTheme.astroRedTheme;
        darkTheme = AstroTheme.astroRedTheme;
      case AppThemeMode.light:
        themeMode = ThemeMode.light;
        theme = AstroTheme.lightTheme;
        darkTheme = AstroTheme.deepSpaceTheme;
      case AppThemeMode.system:
        themeMode = ThemeMode.system;
        theme = AstroTheme.lightTheme;
        darkTheme = AstroTheme.deepSpaceTheme;
    }

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      // 跟随系统语言；既不是中文也不是英文时用英文（列表第一项）
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: LoadingPage(settings: settings),
    );
  }
}

/// 启动时加载星历。
class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key, this.settings});

  final Settings? settings;

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
      final settings = widget.settings ?? await Settings.open();
      // 非 Android 平台在应用打开期间执行后台任务
      ForegroundTaskScheduler.instance.start(engine);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainScaffold(
            engine: engine,
            loadMs: ms,
            settings: settings,
          ),
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
