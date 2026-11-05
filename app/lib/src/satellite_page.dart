import 'package:flutter/material.dart';

import 'celestrak.dart';
import 'errors.dart';
import 'rust/api/guanxiang.dart';
import 'sat_transit_page.dart';

/// 卫星凌日、凌月搜索页。
class SatellitePage extends StatefulWidget {
  const SatellitePage({super.key, required this.engine, this.store});

  final Engine engine;

  /// 测试时可注入；默认打开应用支持目录下的缓存
  final OmmStore? store;

  @override
  State<SatellitePage> createState() => _SatellitePageState();
}

class _SatellitePageState extends State<SatellitePage> {
  final _latCtrl = TextEditingController(text: '39.9');
  final _lonCtrl = TextEditingController(text: '116.4');
  final _heightCtrl = TextEditingController(text: '50');
  final _daysCtrl = TextEditingController(text: '7');
  final _maxSepCtrl = TextEditingController(text: '1');
  final _addCtrl = TextEditingController();

  OmmStore? _store;
  Map<int, String> _watch = {};
  final Map<int, CachedOmm> _cache = {};
  final List<SatTransitItem> _results = [];
  bool _busy = false;
  (double, double) _searchedAt = (0, 0);
  String _status = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in [
      _latCtrl,
      _lonCtrl,
      _heightCtrl,
      _daysCtrl,
      _maxSepCtrl,
      _addCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final store = widget.store ?? await OmmStore.open();
      _store = store;
      _watch = await store.watchList();
      await _reloadCache();
    } catch (e) {
      _setStatus('打开根数缓存失败：${describeError(e)}');
    }
  }

  Future<void> _reloadCache() async {
    for (final id in _watch.keys) {
      _cache[id] = await _store!.cached(id);
    }
    if (mounted) setState(() {});
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _refresh() async {
    final store = _store;
    if (store == null || _busy) return;
    setState(() => _busy = true);
    final lines = <String>[];
    for (final id in _watch.keys) {
      final r = await store.refresh(id);
      lines.add('${_watch[id]}：${r.message}');
    }
    await _reloadCache();
    setState(() => _busy = false);
    _setStatus(lines.join('\n'));
  }

  Future<void> _addSatellite() async {
    final id = int.tryParse(_addCtrl.text.trim());
    if (id == null || id <= 0) {
      _snack('请输入 NORAD 编号');
      return;
    }
    _watch[id] = 'NORAD $id';
    await _store?.setWatchList(_watch);
    _addCtrl.clear();
    await _reloadCache();
  }

  Future<void> _remove(int id) async {
    _watch.remove(id);
    _cache.remove(id);
    await _store?.setWatchList(_watch);
    setState(() {});
  }

  Future<void> _search() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    final h = double.tryParse(_heightCtrl.text.trim());
    final days = double.tryParse(_daysCtrl.text.trim());
    final maxSep = double.tryParse(_maxSepCtrl.text.trim());
    if (lat == null ||
        lon == null ||
        h == null ||
        days == null ||
        maxSep == null) {
      _snack('输入无效');
      return;
    }
    final withData = _cache.values.where((c) => c.json != null).toList();
    if (withData.isEmpty) {
      _snack('还没有根数，请先刷新');
      return;
    }
    _searchedAt = (lat, lon);
    setState(() {
      _busy = true;
      _results.clear();
      _status = '计算中…';
    });
    final watch = Stopwatch()..start();
    final now = DateTime.now().toUtc().toIso8601String();
    final errors = <String>[];
    for (final c in withData) {
      try {
        final found = await satelliteTransits(
          engine: widget.engine,
          ommJson: c.json!,
          previousOmmJson: c.previousJson,
          latitudeDeg: lat,
          longitudeDeg: lon,
          heightM: h,
          startUtc: now,
          days: days,
          maxSeparationDeg: maxSep,
        );
        _results.addAll(found);
      } catch (e) {
        errors.add('${_watch[c.noradId]}：${describeError(e)}');
      }
    }
    _results.sort((a, b) => a.ttJd.compareTo(b.ttJd));
    setState(() {
      _busy = false;
      _status = [
        '共 ${_results.length} 次接近（${_results.where((e) => e.isTransit).length} 次凌日凌月），'
            '用时 ${watch.elapsedMilliseconds} ms',
        ...errors,
      ].join('\n');
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _numberField(
    TextEditingController c,
    String label, {
    double width = 96,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        enabled: !_busy,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  String _cacheLine(int id) {
    final c = _cache[id];
    if (c == null || c.json == null) return '无根数';
    final age = c.fetchedAt == null
        ? ''
        : '，${DateTime.now().toUtc().difference(c.fetchedAt!).inMinutes} 分钟前下载';
    return '历元 ${c.epoch ?? '?'} UTC$age${c.previousJson != null ? '，有旧根数可比较' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('卫星凌日、凌月')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  sunSafetyNotice(),
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final id in _watch.keys)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.satellite_alt),
                title: Text('${_watch[id]}（$id）'),
                subtitle: Text(_cacheLine(id)),
                trailing: defaultSatellites.containsKey(id)
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : () => _remove(id),
                      ),
              ),
            Row(
              children: [
                _numberField(_addCtrl, 'NORAD 编号', width: 120),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '添加卫星',
                  onPressed: _busy ? null : _addSatellite,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新根数'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _numberField(_latCtrl, '纬度°'),
                _numberField(_lonCtrl, '经度°（东正）'),
                _numberField(_heightCtrl, '高度 m'),
                _numberField(_daysCtrl, '天数', width: 64),
                _numberField(_maxSepCtrl, '角距上限°', width: 80),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search),
                  label: const Text('从现在起搜索'),
                ),
                const SizedBox(width: 12),
                if (_busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_status, style: theme.textTheme.bodySmall),
            ],
            const Divider(),
            if (_results.isEmpty && !_busy) const Center(child: Text('暂无结果')),
            for (final e in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  e.body == 'sun'
                      ? Icons.wb_sunny_outlined
                      : Icons.nightlight_outlined,
                  color: e.isTransit ? theme.colorScheme.primary : null,
                ),
                title: Text(e.title),
                subtitle: Text('${e.utc} UTC · ${e.summary}'),
                trailing: e.warning != null
                    ? Icon(Icons.warning_amber, color: theme.colorScheme.error)
                    : const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SatTransitPage(
                      item: e,
                      observerLat: _searchedAt.$1,
                      observerLon: _searchedAt.$2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
