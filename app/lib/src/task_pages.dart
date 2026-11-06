import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'rust/api/guanxiang.dart';
import 'sat_transit_page.dart';
import 'settings.dart';
import 'settings_page.dart' show LocationSummary;
import 'task_service.dart';
import 'tasks.dart';

String _localDateTime(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String statusText(AppLocalizations l, SatTask t) => switch (t.status) {
  TaskStatus.pending => l.statusPending,
  TaskStatus.running => l.statusRunning,
  TaskStatus.done => l.statusDone,
  TaskStatus.timeout => l.statusTimeout,
  TaskStatus.cancelled => l.statusCancelled,
  TaskStatus.failed => l.statusFailed(t.error ?? ''),
};

/// 提交后台任务。
class SubmitTaskPage extends StatefulWidget {
  const SubmitTaskPage({
    super.key,
    required this.settings,
    required this.noradIds,
    required this.maxSeparationDeg,
    this.start,
  });

  final Settings settings;

  /// 有缓存根数的卫星
  final List<int> noradIds;
  final double maxSeparationDeg;

  /// 长跨度搜索的起始时刻（本地时间）；null 为现在
  final DateTime? start;

  @override
  State<SubmitTaskPage> createState() => _SubmitTaskPageState();
}

class _SubmitTaskPageState extends State<SubmitTaskPage> {
  TaskKind _kind = TaskKind.watch;
  late final _maxSepCtrl = TextEditingController(
    text: '${widget.maxSeparationDeg}',
  );
  final _radiusCtrl = TextEditingController(text: '50');
  final _daysCtrl = TextEditingController(text: '60');
  final _runtimeCtrl = TextEditingController(text: '10');
  final _watchDaysCtrl = TextEditingController(text: '14');
  bool _stopOnHit = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _maxSepCtrl,
      _radiusCtrl,
      _daysCtrl,
      _runtimeCtrl,
      _watchDaysCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    double? n(TextEditingController c) => double.tryParse(c.text.trim());
    final maxSep = n(_maxSepCtrl);
    final radius = n(_radiusCtrl);
    final days = n(_daysCtrl);
    final runtime = n(_runtimeCtrl);
    final watchDays = n(_watchDaysCtrl);
    final ok =
        maxSep != null &&
        maxSep > 0 &&
        maxSep <= 10 &&
        radius != null &&
        radius >= 0 &&
        radius <= 500 &&
        (_kind == TaskKind.watch
            ? watchDays != null && watchDays > 0 && watchDays <= 90
            : days != null &&
                  days > 0 &&
                  days <= 120 &&
                  runtime != null &&
                  runtime >= 1 &&
                  runtime <= 120);
    if (!ok) {
      _snack(l.invalidInput);
      return;
    }
    if (widget.noradIds.isEmpty) {
      _snack(l.noCachedElements);
      return;
    }
    setState(() => _busy = true);
    try {
      final PlaceResult place;
      try {
        place = await widget.settings.place();
      } on LocationException catch (e) {
        if (mounted) _snack(e.describe(l));
        return;
      }
      final now = DateTime.now().toUtc();
      final task = SatTask(
        id: newTaskId(),
        kind: _kind,
        created: now,
        noradIds: widget.noradIds,
        place: place.place,
        maxSeparationDeg: maxSep,
        radiusKm: radius,
        stopOnHit: _stopOnHit,
        start: (widget.start ?? DateTime.now()).toUtc(),
        days: days ?? 0,
        maxRuntimeMinutes: (runtime ?? 10).round(),
        deadline: _kind == TaskKind.watch
            ? now.add(Duration(minutes: (watchDays! * 1440).round()))
            : null,
      );
      await (await TaskStore.open()).add(task);
      final allowed = await Notifications.requestPermission();
      await scheduleTasks();
      if (!mounted) return;
      _snack(allowed ? l.taskSubmitted : l.notificationDenied);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TaskListPage(settings: widget.settings),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {double width = 140}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: c,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final long = _kind == TaskKind.longSearch;
    return Scaffold(
      appBar: AppBar(title: Text(l.newTask)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TaskKind>(
              segments: [
                ButtonSegment(
                  value: TaskKind.watch,
                  icon: const Icon(Icons.radar),
                  label: Text(l.taskKindWatch),
                ),
                ButtonSegment(
                  value: TaskKind.longSearch,
                  icon: const Icon(Icons.manage_search),
                  label: Text(l.taskKindLong),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _busy
                  ? null
                  : (v) => setState(() => _kind = v.single),
            ),
            const SizedBox(height: 8),
            Text(
              long ? l.taskLongHint : l.taskWatchHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            LocationSummary(settings: widget.settings, enabled: !_busy),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (long) ...[
                  _field(_daysCtrl, l.searchDaysLabel),
                  _field(_runtimeCtrl, l.maxRuntimeLabel),
                ] else
                  _field(_watchDaysCtrl, l.watchDaysLabel),
                _field(_maxSepCtrl, l.maxSeparation),
                _field(_radiusCtrl, l.radiusLabel),
              ],
            ),
            const SizedBox(height: 4),
            Text(l.radiusHint, style: theme.textTheme.bodySmall),
            if (long && widget.start != null) ...[
              const SizedBox(height: 8),
              Text('${l.startTime}: ${_localDateTime(widget.start!)}'),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.stopOnHitLabel),
              value: _stopOnHit,
              onChanged: _busy ? null : (v) => setState(() => _stopOnHit = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(l.submit),
            ),
          ],
        ),
      ),
    );
  }
}

/// 任务历史：定时重读任务文件，后台进度会自动刷新。
class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key, required this.settings});

  final Settings settings;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  TaskStore? _store;
  List<SatTask> _tasks = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final store = _store ??= await TaskStore.open();
    final tasks = await store.load();
    tasks.sort((a, b) => b.created.compareTo(a.created));
    if (mounted) setState(() => _tasks = tasks);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = DateTime.now().toUtc();
    return Scaffold(
      appBar: AppBar(title: Text(l.tasksTitle)),
      body: SafeArea(
        child: _tasks.isEmpty
            ? Center(child: Text(l.noTasks))
            : ListView.separated(
                itemCount: _tasks.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = _tasks[i];
                  return ListTile(
                    leading: Icon(
                      t.kind == TaskKind.watch
                          ? Icons.radar
                          : Icons.manage_search,
                    ),
                    title: Text(taskName(l, t)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${statusText(l, t)} · '
                          '${l.taskDoneBody(t.hits.length, t.items.length)}',
                        ),
                        if (t.active) ...[
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: t.progress(now)),
                        ],
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'cancel') await _store!.cancel(t.id);
                        if (v == 'delete') await _store!.delete(t.id);
                        await _reload();
                      },
                      itemBuilder: (_) => [
                        if (t.active)
                          PopupMenuItem(
                            value: 'cancel',
                            child: Text(l.cancelTask),
                          ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l.deleteTask),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TaskReportPage(
                          taskId: t.id,
                          settings: widget.settings,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// 任务报告：参数、状态和找到的事件（命中在前）。
class TaskReportPage extends StatefulWidget {
  const TaskReportPage({
    super.key,
    required this.taskId,
    required this.settings,
  });

  final String taskId;
  final Settings settings;

  @override
  State<TaskReportPage> createState() => _TaskReportPageState();
}

class _TaskReportPageState extends State<TaskReportPage> {
  SatTask? _task;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final t = (await (await TaskStore.open()).load())
        .where((x) => x.id == widget.taskId)
        .firstOrNull;
    if (mounted) setState(() => _task = t);
    if (t != null && !t.active) _timer?.cancel();
  }

  Widget _tile(BuildContext context, SatTask t, SatTransitItem e) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hit = t.isHit(e);
    final tag = e.isTransit
        ? l.hitAtSite
        : hit
        ? l.hitNearby(e.distanceToCenterlineKm.toStringAsFixed(0))
        : null;
    final old = e.elementsAgeDays.abs() > 14;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        e.body == 'sun' ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
        color: hit ? theme.colorScheme.primary : null,
      ),
      title: Text(e.title),
      subtitle: Text(
        [
          localTimeText(e.utc),
          ?tag,
          e.summary,
          if (old) l.beyondTwoWeeks,
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SatTransitPage(
            item: e,
            observerLat: t.place.lat,
            observerLon: t.place.lon,
            settings: widget.settings,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = _task;
    if (t == null) {
      return Scaffold(appBar: AppBar(title: Text(l.reportTitle)));
    }
    final hits = t.hits;
    final others = t.items.where((e) => !t.isHit(e)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(taskName(l, t))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(statusText(l, t), style: theme.textTheme.titleMedium),
            if (t.active) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: t.progress(DateTime.now().toUtc()),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              [
                l.reportCreated(_localDateTime(t.created)),
                t.place.describe(),
                t.noradIds.join(', '),
                l.reportParams(
                  t.maxSeparationDeg.toString(),
                  t.radiusKm.toStringAsFixed(0),
                ),
                if (t.kind == TaskKind.longSearch)
                  l.reportSearched(
                    t.searchedDays.toStringAsFixed(0),
                    t.days.toStringAsFixed(0),
                    (t.runtimeMs / 1000).toStringAsFixed(1),
                  ),
                if (t.lastRun != null)
                  l.reportLastRun(_localDateTime(t.lastRun!)),
              ].join('\n'),
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            Text(
              '${l.reportHits} (${hits.length})',
              style: theme.textTheme.titleSmall,
            ),
            if (hits.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.noResults),
              ),
            for (final e in hits) _tile(context, t, e),
            if (others.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '${l.reportOthers} (${others.length})',
                style: theme.textTheme.titleSmall,
              ),
              for (final e in others) _tile(context, t, e),
            ],
          ],
        ),
      ),
    );
  }
}
