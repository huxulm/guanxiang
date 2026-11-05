import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'event_detail_page.dart';
import 'licenses.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'satellite_page.dart';

String _kindLabel(AppLocalizations l, EventKind k) => switch (k) {
  EventKind.transit => l.kindTransit,
  EventKind.conjunction => l.kindConjunction,
  EventKind.opposition => l.kindOpposition,
  EventKind.appulse => l.kindAppulse,
  EventKind.solarEclipse => l.kindSolarEclipse,
  EventKind.lunarEclipse => l.kindLunarEclipse,
  EventKind.occultation => l.kindOccultation,
};

/// 月掩星目标。label 传给 Rust（恒星用 core 星表的中文名查找），value 是显示名。
List<Detail> _occultationTargets(
  AppLocalizations l,
  Map<String, String> body,
) => [
  Detail(label: 'all', value: l.occAll),
  Detail(label: 'planets', value: l.occPlanets),
  Detail(label: 'stars', value: l.occStars),
  Detail(label: '角宿一', value: l.starSpica),
  Detail(label: '心宿二', value: l.starAntares),
  Detail(label: '轩辕十四', value: l.starRegulus),
  Detail(label: '毕宿五', value: l.starAldebaran),
  Detail(label: '昴宿六', value: l.starAlcyone),
  for (final p in ['venus', 'mars', 'jupiter', 'saturn'])
    Detail(label: p, value: body[p] ?? p),
];

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.engine, required this.loadMs});

  final Engine engine;
  final int loadMs;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _maxSepCtrl = TextEditingController(text: '5');
  final _latCtrl = TextEditingController(text: '39.9');
  final _lonCtrl = TextEditingController(text: '116.4');
  final _heightCtrl = TextEditingController(text: '50');

  EventKind _kind = EventKind.transit;
  String _transitPlanet = '';
  String _occultationTarget = 'all';
  String _bodyA = 'venus';
  String _bodyB = 'sun';
  bool _local = false;

  final List<EventItem> _results = [];
  StreamSubscription<SearchUpdate>? _sub;
  CancelToken? _token;
  double _progress = 0;

  /// 状态栏文字，在 build 时按当前语言生成
  late String Function(AppLocalizations) _status;
  late final YearRange _years;

  @override
  void initState() {
    super.initState();
    final c = widget.engine.coverageYears();
    _years = YearRange(c[0], c[1]);
    final year = DateTime.now().year.clamp(_years.from, _years.toExclusive - 1);
    _fromCtrl.text = '$year';
    _toCtrl.text = '${(year + 30).clamp(year + 1, _years.toExclusive)}';
    _status = (l) => l.ephemerisLoaded(widget.loadMs);
  }

  @override
  void dispose() {
    _token?.cancel();
    _sub?.cancel();
    for (final c in [
      _fromCtrl,
      _toCtrl,
      _maxSepCtrl,
      _latCtrl,
      _lonCtrl,
      _heightCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _running => _sub != null;

  void _start() {
    final l = AppLocalizations.of(context);
    final from = int.tryParse(_fromCtrl.text.trim());
    final to = int.tryParse(_toCtrl.text.trim());
    final yearError = _years.check(l, from, to);
    if (yearError != null || from == null || to == null) {
      _snack(yearError ?? l.enterYears);
      return;
    }
    ObserverInput? observer;
    if (_local) {
      final lat = double.tryParse(_latCtrl.text.trim());
      final lon = double.tryParse(_lonCtrl.text.trim());
      final h = double.tryParse(_heightCtrl.text.trim());
      if (lat == null || lon == null || h == null) {
        _snack(l.invalidObserver);
        return;
      }
      observer = ObserverInput(
        latitudeDeg: lat,
        longitudeDeg: lon,
        heightM: h,
        minAltitudeDeg: 0,
        maxSunAltitudeDeg: -6,
      );
    }
    final isTransit = _kind == EventKind.transit;
    final request = SearchRequest(
      kind: _kind,
      bodyA: isTransit
          ? _transitPlanet
          : (_kind == EventKind.occultation ? _occultationTarget : _bodyA),
      bodyB: isTransit ? '' : _bodyB,
      fromYear: from,
      toYear: to,
      maxSeparationDeg: double.tryParse(_maxSepCtrl.text.trim()) ?? 5,
      observer: observer,
      lang: rustLang(context),
    );
    final token = CancelToken();
    setState(() {
      _results.clear();
      _progress = 0;
      _status = (l) => l.searching;
      _token = token;
    });
    _sub = search(engine: widget.engine, request: request, token: token).listen(
      (u) {
        setState(() {
          switch (u.kind) {
            case UpdateKind.progress:
              _progress = u.fraction;
            case UpdateKind.found:
              _results.add(u.item!);
            case UpdateKind.finished:
              final (count, ms) = (u.count, u.elapsedMs.toInt());
              _status = u.cancelled
                  ? (l) => l.searchCancelled(count, ms)
                  : (l) => l.searchFinished(count, ms);
          }
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        final l = AppLocalizations.of(context);
        _snack(l.searchFailed(describeError(e, l)));
        setState(() => _status = (l) => l.searchFailedShort);
        _finish();
      },
      onDone: _finish,
    );
  }

  void _finish() {
    if (!mounted) return;
    setState(() {
      _sub = null;
      _token = null;
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  DropdownButtonFormField<String> _bodyDropdown(
    String label,
    String value,
    ValueChanged<String> onChanged,
    List<Detail> items,
  ) {
    return DropdownButtonFormField<String>(
      // 语言切换后选项文字变了，用 key 让下拉框重建
      key: ValueKey('$label/${items.map((d) => d.value).join()}'),
      initialValue: value,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final b in items)
          DropdownMenuItem(value: b.label, child: Text(b.value)),
      ],
      onChanged: _running ? null : (v) => onChanged(v!),
    );
  }

  Widget _numberField(
    TextEditingController c,
    String label, {
    double width = 96,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        enabled: !_running,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  Widget _form(AppLocalizations l) {
    final bodies = bodyNames(lang: rustLang(context));
    final bodyMap = {for (final b in bodies) b.label: b.value};
    final row = switch (_kind) {
      EventKind.occultation => [
        Expanded(
          child: _bodyDropdown(
            l.occultedTarget,
            _occultationTarget,
            (v) => setState(() => _occultationTarget = v),
            _occultationTargets(l, bodyMap),
          ),
        ),
      ],
      EventKind.solarEclipse ||
      EventKind.lunarEclipse => <Widget>[Expanded(child: Text(l.eclipseHint))],
      EventKind.transit => [
        Expanded(
          child: _bodyDropdown(
            l.planet,
            _transitPlanet,
            (v) => setState(() => _transitPlanet = v),
            [
              Detail(label: '', value: l.mercuryAndVenus),
              Detail(label: 'mercury', value: bodyMap['mercury'] ?? 'mercury'),
              Detail(label: 'venus', value: bodyMap['venus'] ?? 'venus'),
            ],
          ),
        ),
      ],
      _ => [
        Expanded(
          child: _bodyDropdown(
            l.bodyA,
            _bodyA,
            (v) => setState(() => _bodyA = v),
            bodies,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _bodyDropdown(
            l.bodyB,
            _bodyB,
            (v) => setState(() => _bodyB = v),
            bodies,
          ),
        ),
        if (_kind == EventKind.appulse) ...[
          const SizedBox(width: 12),
          _numberField(_maxSepCtrl, l.maxSeparation, width: 80),
        ],
      ],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 七种事件，窄屏上自动换行
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final k in EventKind.values)
              ChoiceChip(
                label: Text(_kindLabel(l, k)),
                selected: _kind == k,
                onSelected: _running ? null : (_) => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: row),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _numberField(_fromCtrl, l.startYear),
            _numberField(_toCtrl, l.endYear, width: 110),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.localOnly),
          subtitle: Text(l.localOnlyHint),
          value: _local,
          onChanged: _running ? null : (v) => setState(() => _local = v),
        ),
        if (_local)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _numberField(_latCtrl, l.latitude),
              _numberField(_lonCtrl, l.longitude, width: 120),
              _numberField(_heightCtrl, l.height),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _running ? null : _start,
              icon: const Icon(Icons.search),
              label: Text(l.search),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _running ? () => _token?.cancel() : null,
              child: Text(l.cancel),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(_status(l), overflow: TextOverflow.ellipsis)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _running ? _progress : (_results.isEmpty ? 0 : 1),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.searchTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.satellite_alt),
            tooltip: l.satelliteTooltip,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SatellitePage(engine: widget.engine),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l.aboutTooltip,
            onPressed: () => showAbout(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _form(l),
            ),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? Center(child: Text(_running ? '' : l.noResults))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = _results[i];
                        return ListTile(
                          title: Text(e.title),
                          subtitle: Text('${e.utc} UTC · ${e.summary}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventDetailPage(event: e),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
