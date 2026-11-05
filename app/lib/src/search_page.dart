import 'dart:async';

import 'package:flutter/material.dart';

import 'event_detail_page.dart';
import 'satellite_page.dart';
import 'rust/api/guanxiang.dart';

const _kindLabels = {
  EventKind.transit: '凌日',
  EventKind.conjunction: '合',
  EventKind.opposition: '冲',
  EventKind.appulse: '角距极小',
  EventKind.solarEclipse: '日食',
  EventKind.lunarEclipse: '月食',
  EventKind.occultation: '月掩星',
};

const _occultationTargets = [
  Detail(label: 'all', value: '全部（行星和 550 颗亮星）'),
  Detail(label: 'planets', value: '全部行星'),
  Detail(label: 'stars', value: '全部亮星'),
  Detail(label: '角宿一', value: '角宿一'),
  Detail(label: '心宿二', value: '心宿二'),
  Detail(label: '轩辕十四', value: '轩辕十四'),
  Detail(label: '毕宿五', value: '毕宿五'),
  Detail(label: '昴宿六', value: '昴宿六（昴星团）'),
  Detail(label: 'venus', value: '金星'),
  Detail(label: 'mars', value: '火星'),
  Detail(label: 'jupiter', value: '木星'),
  Detail(label: 'saturn', value: '土星'),
];

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.engine, required this.loadMs});

  final Engine engine;
  final int loadMs;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _bodies = bodyNames(); // label = 英文名，value = 中文名
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
  String _status = '';

  @override
  void initState() {
    super.initState();
    final year = DateTime.now().year;
    _fromCtrl.text = '$year';
    _toCtrl.text = '${year + 30}';
    _status = '星历加载 ${widget.loadMs} ms';
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
    final from = int.tryParse(_fromCtrl.text.trim());
    final to = int.tryParse(_toCtrl.text.trim());
    if (from == null || to == null || to <= from) {
      _snack('年份范围无效');
      return;
    }
    ObserverInput? observer;
    if (_local) {
      final lat = double.tryParse(_latCtrl.text.trim());
      final lon = double.tryParse(_lonCtrl.text.trim());
      final h = double.tryParse(_heightCtrl.text.trim());
      if (lat == null || lon == null || h == null) {
        _snack('测站坐标无效');
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
    );
    final token = CancelToken();
    setState(() {
      _results.clear();
      _progress = 0;
      _status = '搜索中…';
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
              _status =
                  '${u.cancelled ? '已取消，' : ''}共 ${u.count} 个事件，'
                  '用时 ${u.elapsedMs} ms';
          }
        });
      },
      onError: (Object e) {
        _snack('搜索失败：$e');
        setState(() => _status = '搜索失败');
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
    ValueChanged<String> onChanged, {
    List<Detail>? options,
  }) {
    final items = options ?? _bodies;
    return DropdownButtonFormField<String>(
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

  Widget _form() {
    final bodies = switch (_kind) {
      EventKind.occultation => [
        Expanded(
          child: _bodyDropdown(
            '被掩目标',
            _occultationTarget,
            (v) => setState(() => _occultationTarget = v),
            options: _occultationTargets,
          ),
        ),
      ],
      EventKind.solarEclipse || EventKind.lunarEclipse => <Widget>[
        const Expanded(child: Text('日月食按地心计算；打开“只显示本地可见”可得到本地情况')),
      ],
      EventKind.transit => [
        Expanded(
          child: _bodyDropdown(
            '行星',
            _transitPlanet,
            (v) => setState(() => _transitPlanet = v),
            options: const [
              Detail(label: '', value: '水星和金星'),
              Detail(label: 'mercury', value: '水星'),
              Detail(label: 'venus', value: '金星'),
            ],
          ),
        ),
      ],
      _ => [
        Expanded(
          child: _bodyDropdown(
            '天体 A',
            _bodyA,
            (v) => setState(() => _bodyA = v),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _bodyDropdown(
            '天体 B',
            _bodyB,
            (v) => setState(() => _bodyB = v),
          ),
        ),
        if (_kind == EventKind.appulse) ...[
          const SizedBox(width: 12),
          _numberField(_maxSepCtrl, '角距上限°', width: 80),
        ],
      ],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 六种事件，窄屏上自动换行
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final k in EventKind.values)
              ChoiceChip(
                label: Text(_kindLabels[k]!),
                selected: _kind == k,
                onSelected: _running ? null : (_) => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: bodies),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _numberField(_fromCtrl, '起始年'),
            _numberField(_toCtrl, '结束年（不含）'),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('只显示本地可见'),
          subtitle: const Text('目标在地平线上；非凌日事件还要求太阳低于 −6°'),
          value: _local,
          onChanged: _running ? null : (v) => setState(() => _local = v),
        ),
        if (_local)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _numberField(_latCtrl, '纬度°'),
              _numberField(_lonCtrl, '经度°（东正）'),
              _numberField(_heightCtrl, '高度 m'),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _running ? null : _start,
              icon: const Icon(Icons.search),
              label: const Text('搜索'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _running ? () => _token?.cancel() : null,
              child: const Text('取消'),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(_status, overflow: TextOverflow.ellipsis)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('观象 · 天文事件搜索'),
        actions: [
          IconButton(
            icon: const Icon(Icons.satellite_alt),
            tooltip: '卫星凌日、凌月',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SatellitePage(engine: widget.engine),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _form(),
            ),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? Center(child: Text(_running ? '' : '暂无结果'))
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
