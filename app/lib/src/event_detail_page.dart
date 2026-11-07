import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'event_style.dart';
import 'layout.dart';
import 'rust/api/guanxiang.dart';
import 'time_format.dart';

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.event});

  final EventItem event;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final utcLine = formatUtcLine(event.utc);
    final t = parseUtc(event.utc);
    final left = t == null ? null : countdown(l, t);
    return Scaffold(
      appBar: AppBar(
        title: Text(event.title),
        actions: [
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
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final (i, d) in event.details.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  ListTile(
                    dense: true,
                    title: Text(d.label),
                    trailing: Text(d.value, style: theme.textTheme.bodyLarge),
                  ),
                ],
              ],
            ),
          ),
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
