import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'celestrak.dart';
import 'errors.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'sat_transit_page.dart';
import 'search_results.dart' show isNarrow;
import 'settings.dart';
import 'settings_page.dart';
import 'task_pages.dart';

/// 卫星凌日、凌月搜索页。
class SatellitePage extends StatefulWidget {
  const SatellitePage({
    super.key,
    required this.engine,
    required this.settings,
    this.store,
  });

  final Engine engine;
  final Settings settings;

  /// 测试时可注入；默认打开应用支持目录下的缓存
  final OmmStore? store;

  @override
  State<SatellitePage> createState() => _SatellitePageState();
}

class _SatellitePageState extends State<SatellitePage> {
  final _daysCtrl = TextEditingController(text: '7');
  final _maxSepCtrl = TextEditingController(text: '1');
  final _addCtrl = TextEditingController();

  OmmStore? _store;
  Map<int, String> _watch = {};
  final Map<int, CachedOmm> _cache = {};
  final List<SatTransitItem> _results = [];
  bool _busy = false;
  (double, double) _searchedAt = (0, 0);

  /// 至少完成过一次搜索（手机上显示“查看结果”按钮）
  bool _searched = false;

  /// 搜索起始时间（本地时间）；null 表示从现在开始
  DateTime? _start;

  /// 状态文字，在 build 时按当前语言生成
  String Function(AppLocalizations) _status = (_) => '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in [_daysCtrl, _maxSepCtrl, _addCtrl]) {
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
      _setStatus((l) => l.cacheOpenFailed(describeError(e, l)));
    }
  }

  Future<void> _reloadCache() async {
    for (final id in _watch.keys) {
      _cache[id] = await _store!.cached(id);
    }
    if (mounted) setState(() {});
  }

  void _setStatus(String Function(AppLocalizations) s) {
    if (mounted) setState(() => _status = s);
  }

  String _name(AppLocalizations l, int id) =>
      satelliteDisplayName(l, id, _watch[id] ?? 'NORAD $id');

  Future<void> _refresh() async {
    final store = _store;
    if (store == null || _busy) return;
    setState(() => _busy = true);
    final results = <RefreshResult>[];
    for (final id in _watch.keys) {
      results.add(await store.refresh(id));
    }
    await _reloadCache();
    setState(() => _busy = false);
    _setStatus(
      (l) => results
          .map((r) => '${_name(l, r.noradId)}：${r.describe(l)}')
          .join('\n'),
    );
  }

  Future<void> _addSatellite() async {
    final id = int.tryParse(_addCtrl.text.trim());
    if (id == null || id <= 0) {
      _snack(AppLocalizations.of(context).enterNorad);
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
    final l = AppLocalizations.of(context);
    final lang = rustLang(context);
    final days = double.tryParse(_daysCtrl.text.trim());
    final maxSep = double.tryParse(_maxSepCtrl.text.trim());
    if (days == null || maxSep == null || days <= 0) {
      _snack(l.invalidInput);
      return;
    }
    final withData = _cache.values.where((c) => c.json != null).toList();
    if (withData.isEmpty) {
      _snack(l.noElementsYet);
      return;
    }
    setState(() {
      _busy = true;
      _results.clear();
      _status = (l) => l.locating;
    });
    PlaceResult r;
    try {
      r = await widget.settings.place();
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setStatus((l) => e.describe(l));
      return;
    }
    if (!mounted) return;
    final stale = r.stale
        ? (AppLocalizations l) => l.usingOldFix(
            widget.settings.gpsError?.describe(l) ?? '',
            _hm(widget.settings.gpsTime!),
          )
        : null;
    final (lat, lon, h) = (r.place.lat, r.place.lon, r.place.height);
    _searchedAt = (lat, lon);
    setState(() => _status = (l) => l.computing);
    final watch = Stopwatch()..start();
    final startUtc = (_start ?? DateTime.now()).toUtc().toIso8601String();
    final errors = <String Function(AppLocalizations)>[];
    for (final c in withData) {
      try {
        final found = await satelliteTransits(
          engine: widget.engine,
          ommJson: c.json!,
          previousOmmJson: c.previousJson,
          latitudeDeg: lat,
          longitudeDeg: lon,
          heightM: h,
          startUtc: startUtc,
          days: days,
          maxSeparationDeg: maxSep,
          radiusKm: 0,
          lang: lang,
        );
        _results.addAll(found);
      } catch (e) {
        errors.add((l) => '${_name(l, c.noradId)}：${describeError(e, l)}');
      }
    }
    _results.sort((a, b) => a.ttJd.compareTo(b.ttJd));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _searched = true;
      final count = _results.length;
      final transits = _results.where((e) => e.isTransit).length;
      final ms = watch.elapsedMilliseconds;
      _status = (l) => [
        l.satSummary(count, transits, ms),
        ?stale?.call(l),
        for (final e in errors) e(l),
      ].join('\n');
    });
    if (isNarrow(context)) _openResults();
  }

  void _openSubmit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubmitTaskPage(
          settings: widget.settings,
          noradIds: [
            for (final e in _cache.entries)
              if (e.value.json != null) e.key,
          ],
          maxSeparationDeg: double.tryParse(_maxSepCtrl.text.trim()) ?? 1,
          start: _start,
        ),
      ),
    );
  }

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _openResults() {
    final items = List.of(_results);
    final at = _searchedAt;
    final status = _status;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          final l = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(title: Text(l.resultsTitle)),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      status(l),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Divider(height: 1),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(l.noResults)),
                    ),
                  for (final e in items) _resultTile(context, e, at),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _resultTile(
    BuildContext context,
    SatTransitItem e,
    (double, double) at,
  ) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        e.body == 'sun' ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
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
            observerLat: at.$1,
            observerLon: at.$2,
            settings: widget.settings,
          ),
        ),
      ),
    );
  }

  /// 选择起始日期和时间（本地时间）。
  Future<void> _pickStart() async {
    final now = DateTime.now();
    final initial = _start ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      // 根数只在历元前后约两周内可靠，这里只限制在合理范围内，龄期过大时结果里会提醒
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _startLabel(AppLocalizations l) {
    final s = _start;
    if (s == null) return l.startNow;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${s.year}-${two(s.month)}-${two(s.day)} ${two(s.hour)}:${two(s.minute)}';
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

  String _cacheLine(AppLocalizations l, int id) {
    final c = _cache[id];
    if (c == null || c.json == null) return l.noElements;
    final age = c.fetchedAt == null
        ? ''
        : l.downloadedAgo(
            DateTime.now().toUtc().difference(c.fetchedAt!).inMinutes,
          );
    return l.cacheEpoch(c.epoch ?? '?') +
        age +
        (c.previousJson != null ? l.hasPrevious : '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final status = _status(l);
    final narrow = isNarrow(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.satTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l.tasksTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TaskListPage(settings: widget.settings),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  sunSafetyNotice(lang: rustLang(context)),
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
                title: Text('${_name(l, id)} ($id)'),
                subtitle: Text(_cacheLine(l, id)),
                trailing: defaultSatellites.containsKey(id)
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : () => _remove(id),
                      ),
              ),
            Row(
              children: [
                _numberField(_addCtrl, l.noradNumber, width: 120),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l.addSatellite,
                  onPressed: _busy ? null : _addSatellite,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(l.refreshElements),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LocationSummary(settings: widget.settings, enabled: !_busy),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _numberField(_daysCtrl, l.days, width: 64),
                _numberField(_maxSepCtrl, l.maxSeparation, width: 80),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(l.startTime),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickStart,
                  icon: const Icon(Icons.event),
                  label: Text(_startLabel(l)),
                ),
                if (_start != null)
                  IconButton(
                    icon: const Icon(Icons.restart_alt),
                    tooltip: l.resetToNow,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _start = null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search),
                  label: Text(l.search),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openSubmit,
                  icon: const Icon(Icons.schedule_send),
                  label: Text(l.newTask),
                ),
                const SizedBox(width: 12),
                if (_busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(status, style: theme.textTheme.bodySmall),
            ],
            const Divider(),
            if (narrow)
              _searched && !_busy
                  ? OutlinedButton.icon(
                      onPressed: _openResults,
                      icon: const Icon(Icons.list),
                      label: Text(l.viewResults(_results.length)),
                    )
                  : const SizedBox.shrink()
            else ...[
              if (_results.isEmpty && !_busy) Center(child: Text(l.noResults)),
              for (final e in _results) _resultTile(context, e, _searchedAt),
            ],
          ],
        ),
      ),
    );
  }
}
