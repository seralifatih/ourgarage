import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/notification_service_provider.dart';

/// Whether notifications can be shown right now: true, false (declined or
/// never asked), or null where the platform can't say.
///
/// Re-read on app resume (see `OurGarageApp`), which is when a change made in
/// iOS Settings comes back into the app, and after any permission request.
final notificationPermissionProvider = FutureProvider<bool?>(
  (ref) => ref.watch(notificationServiceProvider).hasPermission(),
);

/// The "Turn on" action shared by Settings and the reminders banner.
///
/// Asks first: if the user was never asked, this shows the system prompt.
/// iOS only ever shows that prompt once, so after a refusal the request
/// answers false straight away, and the only way left is the Settings app.
Future<void> turnOnNotifications(WidgetRef ref) async {
  final notifications = ref.read(notificationServiceProvider);
  try {
    final granted = await notifications.requestPermissions() ?? false;
    if (!granted) await notifications.openSettings();
  } catch (error, stack) {
    debugPrint('Turning on notifications failed: $error\n$stack');
  } finally {
    ref.invalidate(notificationPermissionProvider);
  }
}

/// Whether the "notifications are off" banner was closed this session.
///
/// Deliberately not persisted: a reminder app with notifications off is
/// worth one quiet line per launch, not a permanent dismissal.
class NotificationBannerDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final notificationBannerDismissedProvider =
    NotifierProvider<NotificationBannerDismissed, bool>(
      NotificationBannerDismissed.new,
    );

/// Shown above a vehicle's reminders while notifications are off.
///
/// Renders nothing while the status is loading, unknown, on, or dismissed.
class NotificationsOffBanner extends ConsumerWidget {
  const NotificationsOffBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(notificationPermissionProvider).asData?.value;
    final dismissed = ref.watch(notificationBannerDismissedProvider);
    if (enabled != false || dismissed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(
                Icons.notifications_off_outlined,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Notifications are off, so these reminders can’t alert '
                  'you.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => turnOnNotifications(ref),
                child: const Text('Turn on'),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close),
                color: scheme.onSecondaryContainer,
                onPressed: () => ref
                    .read(notificationBannerDismissedProvider.notifier)
                    .dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
