import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'event_style.dart';
import 'layout.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'satellite_page.dart';
import 'search_results.dart';
import 'settings.dart';
import 'settings_page.dart';

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
  const SearchPage({
    super.key,
    required this.engine,
    required this.settings,
    this.isEmbedded = false,
  });

  final Engine engine;
  final Settings settings;
  final bool isEmbedded;

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _maxSepCtrl = TextEditingController(text: '5');

  EventKind _kind = EventKind.transit;
  String _transitPlanet = '';
  String _occultationTarget = 'all';
  String _bodyA = 'venus';
  String _bodyB = 'sun';
  bool _local = false;

  /// 当前（或上一次）搜索
  SearchSession? _session;

  /// 正在为搜索取得 GPS 定位
  bool _locating = false;

  /// 搜索开始前的状态栏文字，在 build 时按当前语言生成
  late String Function(AppLocalizations) _idleStatus;
  late final YearRange _years;

  @override
  void initState() {
    super.initState();
    final c = widget.engine.coverageYears();
    _years = YearRange(c[0], c[1]);
    final year = DateTime.now().year.clamp(_years.from, _years.toExclusive - 1);
    _fromCtrl.text = '$year';
    _toCtrl.text = '${(year + 29).clamp(year, _years.toExclusive - 1)}';
    _idleStatus = (l) => l.searchIdle;
  }

  @override
  void dispose() {
    _session?.dispose();
    for (final c in [_fromCtrl, _toCtrl, _maxSepCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _running => _locating || (_session?.running ?? false);

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    final from = int.tryParse(_fromCtrl.text.trim());
    final to = int.tryParse(_toCtrl.text.trim());
    // 界面上的结束年包含在内，计算核心要的是不含的上界
    final yearError = _years.check(l, from, to);
    if (yearError != null || from == null || to == null) {
      _snack(yearError ?? l.enterYears);
      return;
    }
    ObserverInput? observer;
    if (_local) {
      setState(() {
        _locating = true;
        _idleStatus = (l) => l.locating;
      });
      PlaceResult r;
      try {
        r = await widget.settings.place();
      } on LocationException catch (e) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _idleStatus = (l) => e.describe(l);
        });
        _snack(e.describe(AppLocalizations.of(context)));
        return;
      }
      if (!mounted) return;
      setState(() => _locating = false);
      if (r.stale) {
        final l = AppLocalizations.of(context);
        _snack(
          l.usingOldFix(
            widget.settings.gpsError?.describe(l) ?? '',
            _hm(widget.settings.gpsTime!),
          ),
        );
      }
      observer = ObserverInput(
        latitudeDeg: r.place.lat,
        longitudeDeg: r.place.lon,
        heightM: r.place.height,
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
      toYear: to + 1,
      maxSeparationDeg: double.tryParse(_maxSepCtrl.text.trim()) ?? 5,
      observer: observer,
      lang: rustLang(context),
    );
    final kind = _kind;
    final session = SearchSession(
      engine: widget.engine,
      settings: widget.settings,
      title: (l) => '${kindLabel(l, kind)} · $from–$to',
    )..addListener(_sessionChanged);
    session.start(
      search(engine: widget.engine, request: request, token: session.token),
    );
    setState(() {
      _session?.dispose();
      _session = session;
    });
    if (isNarrow(context)) _openResults();
  }

  void _openResults() {
    final s = _session;
    if (s == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SearchResultsPage(session: s)));
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
                label: Text(kindLabel(l, k)),
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
            _numberField(_toCtrl, l.endYear),
          ],
        ),
        const SizedBox(height: 8),
        _yearPresets(l),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.localOnly),
          subtitle: Text(l.localOnlyHint),
          value: _local,
          onChanged: _running ? null : (v) => setState(() => _local = v),
        ),
        if (_local)
          LocationSummary(settings: widget.settings, enabled: !_running),
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
              onPressed: (_session?.running ?? false)
                  ? () => _session!.cancel()
                  : null,
              child: Text(l.cancel),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _locating || _session == null
                    ? _idleStatus(l)
                    : _session!.status(l),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _locating
              ? null
              : _session == null
              ? 0
              : (_session!.running ? _session!.progress : 1),
        ),
      ],
    );
  }

  /// 年份快捷选项：未来 10 年、未来 30 年、到星历末年、全部。
  Widget _yearPresets(AppLocalizations l) {
    final now = DateTime.now().year.clamp(_years.from, _years.toExclusive - 1);
    final last = _years.toExclusive - 1;
    void set(int from, int to) => setState(() {
      _fromCtrl.text = '$from';
      _toCtrl.text = '${to.clamp(from, last)}';
    });
    final presets = [
      (l.yearsNext10, now, now + 9),
      (l.yearsNext30, now, now + 29),
      (l.yearsTo2100(last), now, last),
      (l.yearsAll(_years.from, last), _years.from, last),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final (label, from, to) in presets)
          ActionChip(
            label: Text(label),
            onPressed: _running ? null : () => set(from, to),
          ),
      ],
    );
  }

  /// 供外部预设搜索条件（如从看板快捷卡片点击跳转）
  void preset({
    required EventKind kind,
    int? fromYear,
    int? toYear,
    String? bodyA,
    String? bodyB,
  }) {
    setState(() {
      _kind = kind;
      if (fromYear != null) _fromCtrl.text = '$fromYear';
      if (toYear != null) _toCtrl.text = '$toYear';
      if (bodyA != null) _bodyA = bodyA;
      if (bodyB != null) _bodyB = bodyB;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final narrow = isNarrow(context);
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEmbedded
              ? l.navSearch
              : (narrow ? l.appTitle : l.searchTitle),
        ),
        actions: widget.isEmbedded
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.satellite_alt),
                  tooltip: l.satelliteTooltip,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SatellitePage(
                        engine: widget.engine,
                        settings: widget.settings,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: l.settingsTitle,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(settings: widget.settings),
                    ),
                  ),
                ),
              ],
      ),
      body: SafeArea(
        child: narrow
            // 手机：只有表单，结果在单独的页面
            ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _form(l),
                  if (session != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openResults,
                      icon: const Icon(Icons.list),
                      label: Text(l.viewResults(session.results.length)),
                    ),
                  ],
                ],
              )
            : Column(
                children: [
                  ContentInsets(
                    builder: (context, side) => Padding(
                      padding: EdgeInsets.fromLTRB(side, 8, side, 8),
                      child: _form(l),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: EventResultsList(session: session)),
                ],
              ),
      ),
    );
  }
}
