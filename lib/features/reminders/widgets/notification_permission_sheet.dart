import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/notification_service_provider.dart';

/// Explains what notifications are for, then asks the OS for permission.
///
/// The OS prompt is one-shot: a user who declines it can only change their
/// mind by digging through Settings. Explaining first — at the moment they've
/// just asked for reminders, so the answer to "why?" is obvious — is what
/// keeps the grant rate up.
class NotificationPermissionSheet extends ConsumerStatefulWidget {
  const NotificationPermissionSheet({super.key});

  /// Shows the sheet and returns whether notifications ended up allowed.
  ///
  /// Returns false when the user dismisses without deciding.
  static Future<bool> show(BuildContext context) async {
    final granted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const NotificationPermissionSheet(),
    );
    return granted ?? false;
  }

  @override
  ConsumerState<NotificationPermissionSheet> createState() =>
      _NotificationPermissionSheetState();
}

class _NotificationPermissionSheetState
    extends ConsumerState<NotificationPermissionSheet> {
  bool _requesting = false;

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
              Icons.notifications_outlined,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Get reminded before it’s due',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'OurGarage can send you a notification the morning a service '
              'falls due, so it doesn’t quietly slip past. Nothing else — no '
              'marketing, no daily nagging.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _requesting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _requesting ? null : _request,
                  child: const Text('Turn on reminders'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _request() async {
    setState(() => _requesting = true);

    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermissions();

    if (mounted) Navigator.of(context).pop(granted ?? false);
  }
}
