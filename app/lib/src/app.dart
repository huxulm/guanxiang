import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'rust/api/guanxiang.dart';
import 'search_page.dart';

/// 星历文件随应用打包（M7 再换成裁剪版）。三端都从 asset 读成字节交给 Rust，
/// Android 上不需要先释放到磁盘。
const ephemerisAsset = 'assets/de440s.bsp';

class GuanxiangApp extends StatelessWidget {
  const GuanxiangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '观象',
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final watch = Stopwatch()..start();
      final data = await rootBundle.load(ephemerisAsset);
      final engine = await Engine.fromBytes(bytes: data.buffer.asUint8List());
      final ms = watch.elapsedMilliseconds;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SearchPage(engine: engine, loadMs: ms)),
      );
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在加载星历…'),
                  ],
                )
              : Text('星历加载失败：$_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ),
    );
  }
}
