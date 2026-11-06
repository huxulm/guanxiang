import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'rust/api/guanxiang.dart';
import 'time_format.dart';

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(event.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(formatAstroTime(event.utc), style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
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
