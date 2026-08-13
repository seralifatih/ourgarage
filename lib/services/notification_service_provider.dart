import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'notification_service.dart';

part 'notification_service_provider.g.dart';

/// The app-wide [NotificationService].
///
/// Kept alive for the process lifetime: it owns the tap stream the router
/// listens to, so tearing it down when the last listener drops would silently
/// stop deep links working.
///
/// Tests override this with a service wrapping a fake plugin.
@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) {
  final service = NotificationService(
    FlutterLocalNotificationPlugin(FlutterLocalNotificationsPlugin()),
  );
  ref.onDispose(service.dispose);
  return service;
}
