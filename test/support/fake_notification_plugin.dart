import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ourgarage/services/notification_service.dart';
import 'package:ourgarage/services/notification_service_provider.dart';
import 'package:timezone/timezone.dart' as tz;

/// A [NotificationPlugin] that records nothing and touches no platform.
///
/// Any test that pumps the whole app needs this: `OurGarageApp` initialises
/// notifications on startup, and the real plugin resolves a platform
/// implementation from `defaultTargetPlatform`, which under the test runner is
/// neither Android nor iOS — so it throws before reaching a method channel.
class FakeNotificationPlugin implements NotificationPlugin {
  final scheduledIds = <int>[];
  final cancelledIds = <int>[];

  /// When each id was scheduled for, so tests can assert on timing.
  final scheduledDates = <int, tz.TZDateTime>{};

  int cancelAllCount = 0;

  @override
  Future<bool?> initialize(
    InitializationSettings settings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async => true;

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
  }) async {
    scheduledIds.add(id);
    scheduledDates[id] = scheduledDate;
  }

  @override
  Future<void> cancel(int id) async => cancelledIds.add(id);

  @override
  Future<void> cancelAll() async => cancelAllCount++;

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() {
    return Future.value([
      for (final id in scheduledIds)
        PendingNotificationRequest(id, null, null, null),
    ]);
  }

  @override
  Future<bool?> requestPermissions() async => true;

  @override
  Future<bool?> areNotificationsEnabled() async => true;
}

/// Overrides [notificationServiceProvider] with a platform-free service.
///
/// The timezone is pinned so tests never depend on the machine's zone.
Override fakeNotificationServiceOverride([FakeNotificationPlugin? plugin]) {
  return notificationServiceProvider.overrideWith(
    (ref) => NotificationService(
      plugin ?? FakeNotificationPlugin(),
      localTimeZoneName: 'UTC',
    ),
  );
}
