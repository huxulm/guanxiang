import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'eclipse_diagram.dart';
import 'event_style.dart';
import 'layout.dart';
import 'lunar_eclipse_detail.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'share_poster.dart';
import 'solar_eclipse_detail.dart';
import 'time_format.dart';

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({
    super.key,
    required this.event,
    this.engine,
    this.settings,
  });

  final EventItem event;

  /// 有星历时，日月食详情显示示意图；月食另有时间轴、本地可见情况等
  final Engine? engine;

  /// 月食详情用其中的观测地
  final Settings? settings;

  /// 复制用的纯文本：标题、时间、摘要和全部参数。
  String _plainText() {
    final utcLine = formatUtcLine(event.utc);
    return [
      event.title,
      formatAstroTime(event.utc, showUtc: false),
      ?utcLine,
      event.summary,
      '',
      for (final d in event.details) '${d.label}: ${d.value}',
    ].join('\n');
  }

  /// 从底部拉出全部参数（日月食页用：页面上已有更好读的卡片，原始参数收起来）。
  void _showParameters(BuildContext context) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // 宽屏上不铺满整个窗口
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, controller) {
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.allParameters,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _CopyButton(text: _plainText()),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    _ParameterRows(details: event.details),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        l.detailFooter(event.ttJd.toStringAsFixed(6)),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final utcLine = formatUtcLine(event.utc);
    final t = parseUtc(event.utc);
    final left = t == null ? null : countdown(l, t);
    final lunar = engine != null && event.kind == EventKind.lunarEclipse;
    final solar = engine != null && event.kind == EventKind.solarEclipse;
    // 日月食页上，原始参数收进底部抽屉；其他事件的参数表就是主体内容，照旧直接显示
    final sheet = (lunar || solar) && event.details.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(event.title),
        actions: [
          if (lunar || solar)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l.shareImage,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EclipseSharePage(
                    engine: engine!,
                    event: event,
                    settings: settings,
                  ),
                ),
              ),
            ),
          if (sheet)
            IconButton(
              icon: const Icon(Icons.table_rows_outlined),
              tooltip: l.allParameters,
              onPressed: () => _showParameters(context),
            ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: l.copyDetails,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _plainText()));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.copied)));
            },
          ),
        ],
      ),
      body: ContentListView(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KindBadge(kind: event.kind, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 本地时间一行，UTC 另起一行（手机上放在一行会断开）
                    Text(
                      formatAstroTime(event.utc, showUtc: false),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (utcLine != null)
                      Text(
                        utcLine,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (left != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          left,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(event.summary, style: theme.textTheme.bodyLarge),
          if (event.subtle)
            Text(
              l.subtleHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (sheet)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.table_rows_outlined, size: 18),
                  label: Text(l.allParametersCount(event.details.length)),
                  onPressed: () => _showParameters(context),
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (lunar) ...[
            LunarEclipseSections(
              engine: engine!,
              event: event,
              settings: settings,
            ),
            const SizedBox(height: 16),
          ],
          if (solar) ...[
            SolarEclipseSections(
              engine: engine!,
              event: event,
              settings: settings,
            ),
            const SizedBox(height: 16),
          ],
          if (!sheet) Card(child: _ParameterRows(details: event.details)),
          if (!lunar &&
              !solar &&
              engine != null &&
              EclipseDiagramCard.supports(event.kind)) ...[
            const SizedBox(height: 16),
            EclipseDiagramCard(engine: engine!, event: event),
          ],
          const SizedBox(height: 16),
          Text(
            l.detailFooter(event.ttJd.toStringAsFixed(6)),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 参数表：每行左边是名称、右边是值。
class _ParameterRows extends StatelessWidget {
  const _ParameterRows({required this.details});

  final List<Detail> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (i, d) in details.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 16),
          ListTile(
            dense: true,
            title: Text(d.label),
            trailing: Text(d.value, style: theme.textTheme.bodyLarge),
          ),
        ],
      ],
    );
  }
}

/// 抽屉里的复制按钮：抽屉挡住了页面底部的提示条，复制后图标变成对勾 2 秒。
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IconButton(
      icon: Icon(_done ? Icons.check : Icons.copy_all_outlined),
      tooltip: _done ? l.copied : l.copyDetails,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        if (!mounted) return;
        setState(() => _done = true);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _done = false);
      },
    );
  }
}
