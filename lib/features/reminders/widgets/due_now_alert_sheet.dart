import 'package:flutter/material.dart';

import '../odometer_nudge_service.dart';

/// What the user chose to do about a rule that just came due.
enum DueNowAction { logIt, remindLater }

/// Surfaces rules that a fresh odometer reading just made due.
///
/// Shown right after saving, while the reading is seconds old — the one moment
/// a distance-based "due now" is trustworthy enough to interrupt someone with.
class DueNowAlertSheet extends StatelessWidget {
  const DueNowAlertSheet({required this.due, super.key});

  final List<DueAfterUpdate> due;

  /// Shows the sheet, resolving to the chosen action and the rule it applies
  /// to, or null if dismissed.
  static Future<(DueNowAction, DueAfterUpdate)?> show(
    BuildContext context,
    List<DueAfterUpdate> due,
  ) {
    return showModalBottomSheet<(DueNowAction, DueAfterUpdate)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DueNowAlertSheet(due: due),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.build_outlined,
              size: 32,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              due.length == 1 ? 'Something’s due' : 'A few things are due',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in due) ...[
              _DueRow(
                item: item,
                onLogIt: () =>
                    Navigator.of(context).pop((DueNowAction.logIt, item)),
              ),
              if (item != due.last) const Divider(height: 24),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop((DueNowAction.remindLater, due.first)),
                child: const Text('Remind me later'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.item, required this.onLogIt});

  final DueAfterUpdate item;
  final VoidCallback onLogIt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(child: Text(item.message, style: theme.textTheme.bodyLarge)),
        const SizedBox(width: 12),
        FilledButton(onPressed: onLogIt, child: const Text('Log it now')),
      ],
    );
  }
}
