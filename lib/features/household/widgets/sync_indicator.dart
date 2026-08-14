import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sync/sync_providers.dart';
import '../../../data/sync/sync_service.dart';

/// A small, quiet sync indicator.
///
/// Deliberately understated and never interactive. Sync is not something the
/// user asked for or should have to think about; the only reason to surface it
/// at all is so that "my partner can't see this yet" has a visible
/// explanation. It occupies no space when there is nothing to say.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(syncStatusProvider).asData?.value ?? SyncStatus.idle;
    final theme = Theme.of(context);

    // Idle is the overwhelmingly common state, and a permanent green tick is
    // just noise once the novelty wears off.
    if (status == SyncStatus.idle) return const SizedBox.shrink();

    final (icon, label) = switch (status) {
      SyncStatus.syncing => (Icons.sync, 'Syncing'),
      SyncStatus.pendingOffline => (Icons.cloud_off_outlined, 'Offline'),
      SyncStatus.idle => (Icons.check, ''),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
