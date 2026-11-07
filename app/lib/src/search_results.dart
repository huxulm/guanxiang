import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'event_detail_page.dart';
import 'event_style.dart';
import 'layout.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'time_format.dart';

/// 窄于这个宽度（逻辑像素）时按手机布局：搜索结果单独一页。
const narrowLayoutWidth = 600.0;

bool isNarrow(BuildContext context) =>
    MediaQuery.sizeOf(context).width < narrowLayoutWidth;

/// 一次正在进行或已结束的搜索。搜索页和结果页共用。
class SearchSession extends ChangeNotifier {
  SearchSession({required this.title, this.engine, this.settings});

  /// 打开详情页时用来画日月食示意图
  final Engine? engine;

  /// 打开月食详情时用其中的观测地
  final Settings? settings;

  /// 结果页标题，在 build 时按当前语言生成
  final String Function(AppLocalizations) title;

  final List<EventItem> results = [];
  double progress = 0;
  bool running = true;
  String Function(AppLocalizations) status = (l) => l.searching;

  final CancelToken _token = CancelToken();
  StreamSubscription<SearchUpdate>? _sub;
  bool _disposed = false;

  void start(Stream<SearchUpdate> updates) {
    _sub = updates.listen(
      (u) {
        switch (u.kind) {
          case UpdateKind.progress:
            progress = u.fraction;
          case UpdateKind.found:
            results.add(u.item!);
          case UpdateKind.finished:
            final (count, ms) = (u.count, u.elapsedMs.toInt());
            status = u.cancelled
                ? (l) => l.searchCancelled(count, ms)
                : (l) => l.searchFinished(count, ms);
        }
        _notify();
      },
      onError: (Object e) {
        status = (l) => l.searchFailed(describeError(e, l));
        _finish();
      },
      onDone: _finish,
    );
  }

  CancelToken get token => _token;

  void cancel() {
    if (running) _token.cancel();
  }

  void _finish() {
    running = false;
    _sub = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

/// 结果列表（宽屏嵌在搜索页里，窄屏放在结果页里）：按年份分组，每行有类型图标。
class EventResultsList extends StatelessWidget {
  const EventResultsList({super.key, required this.session});

  final SearchSession? session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = session;
    if (s == null) return Center(child: Text(l.noResults));
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.results.isEmpty) {
          return Center(child: Text(s.running ? '' : l.noResults));
        }
        // 行：int 是年份标题，EventItem 是事件
        final rows = <Object>[];
        int? year;
        for (final e in s.results) {
          final y = parseUtc(e.utc)?.toLocal().year;
          if (y != null && y != year) rows.add(y);
          year = y ?? year;
          rows.add(e);
        }
        return ContentInsets(
          min: 0,
          builder: (context, side) => ListView.builder(
            padding: EdgeInsets.fromLTRB(side, 0, side, 16),
            itemCount: rows.length,
            itemBuilder: (context, i) => switch (rows[i]) {
              final int y => _YearHeader(year: y),
              final EventItem e => EventResultTile(
                event: e,
                engine: s.engine,
                settings: s.settings,
              ),
              _ => const SizedBox.shrink(),
            },
          ),
        );
      },
    );
  }
}

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        '$year',
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 结果列表的一行：类型图标、标题，下面两行是时间和摘要。
class EventResultTile extends StatelessWidget {
  const EventResultTile({
    super.key,
    required this.event,
    this.engine,
    this.settings,
  });

  final EventItem event;
  final Engine? engine;
  final Settings? settings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final e = event;
    // 手机上只写本地时间（UTC 在详情页），宽屏两个都写
    final time = formatAstroTime(e.utc, showUtc: !isNarrow(context));
    final summary = e.subtle ? '${e.summary} · ${l.subtleHint}' : e.summary;
    return ListTile(
      leading: KindBadge(kind: e.kind),
      title: Text(e.title),
      subtitle: Text('$time\n$summary'),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              EventDetailPage(event: e, engine: engine, settings: settings),
        ),
      ),
    );
  }
}

/// 手机上的结果页：状态、进度、取消，下面是结果列表。返回不会取消搜索。
class SearchResultsPage extends StatelessWidget {
  const SearchResultsPage({super.key, required this.session});

  final SearchSession session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(session.title(l))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(child: Text(session.status(l))),
                    if (session.running)
                      TextButton(
                        onPressed: session.cancel,
                        child: Text(l.cancel),
                      ),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: session.running ? session.progress : 1,
              ),
              Expanded(child: EventResultsList(session: session)),
            ],
          ),
        ),
      ),
    );
  }
}
