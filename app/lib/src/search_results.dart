import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'event_detail_page.dart';
import 'rust/api/guanxiang.dart';
import 'time_format.dart';

/// 窄于这个宽度（逻辑像素）时按手机布局：搜索结果单独一页。
const narrowLayoutWidth = 600.0;

bool isNarrow(BuildContext context) =>
    MediaQuery.sizeOf(context).width < narrowLayoutWidth;

/// 一次正在进行或已结束的搜索。搜索页和结果页共用。
class SearchSession extends ChangeNotifier {
  SearchSession({required this.title});

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

/// 结果列表（宽屏嵌在搜索页里，窄屏放在结果页里）。
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
        return ListView.separated(
          itemCount: s.results.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = s.results[i];
            return ListTile(
              title: Text(e.title),
              subtitle: Text('${formatAstroTime(e.utc)} · ${e.summary}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EventDetailPage(event: e)),
              ),
            );
          },
        );
      },
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
