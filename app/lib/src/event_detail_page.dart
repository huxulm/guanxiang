import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'layout.dart';
import 'rust/api/guanxiang.dart';
import 'time_format.dart';

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final utcLine = formatUtcLine(event.utc);
    return Scaffold(
      appBar: AppBar(title: Text(event.title)),
      body: ContentListView(
        children: [
          // 本地时间一行，UTC 另起一行（手机上放在一行会断开）
          Text(
            formatAstroTime(event.utc, showUtc: false),
            style: theme.textTheme.headlineSmall,
          ),
          if (utcLine != null)
            Text(
              utcLine,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Text(event.summary, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final d in event.details)
                  ListTile(
                    dense: true,
                    title: Text(d.label),
                    trailing: Text(d.value, style: theme.textTheme.bodyLarge),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)
                .detailFooter(event.ttJd.toStringAsFixed(6)),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
