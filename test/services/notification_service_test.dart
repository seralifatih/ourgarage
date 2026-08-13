import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/core/constants.dart';
import 'package:ourgarage/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// One scheduled notification, as the fake plugin saw it.
class _Scheduled {
  _Scheduled({
    required this.id,
    required this.scheduledDate,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final tz.TZDateTime scheduledDate;
  final String? title;
  final String? body;
  final String? payload;
}

class _FakePlugin implements NotificationPlugin {
  final scheduled = <_Scheduled>[];
  final cancelled = <int>[];
  int cancelAllCount = 0;
  int initializeCount = 0;
  int requestPermissionsCount = 0;

  /// Records call order, so "cancelAll happened first" is assertable.
  final callOrder = <String>[];

  InitializationSettings? lastSettings;
  DidReceiveNotificationResponseCallback? responseCallback;
  NotificationAppLaunchDetails? launchDetails;
  bool? permissionResult = true;

  @override
  Future<bool?> initialize(
    InitializationSettings settings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    initializeCount++;
    callOrder.add('initialize');
    lastSettings = settings;
    responseCallback = onDidReceiveNotificationResponse;
    return true;
  }

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
    callOrder.add('zonedSchedule');
    scheduled.add(
      _Scheduled(
        id: id,
        scheduledDate: scheduledDate,
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    callOrder.add('cancel');
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    callOrder.add('cancelAll');
    cancelAllCount++;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    return launchDetails;
  }

  @override
  Future<bool?> requestPermissions() async {
    requestPermissionsCount++;
    callOrder.add('requestPermissions');
    return permissionResult;
  }

  @override
  Future<bool?> areNotificationsEnabled() async => permissionResult;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() {
    return Future.value([
      for (final s in scheduled)
        PendingNotificationRequest(s.id, s.title, s.body, s.payload),
    ]);
  }
}

void main() {
  late _FakePlugin plugin;
  late NotificationService service;

  /// Pinned so expected instants stay readable and the test doesn't depend on
  /// where it runs.
  const zone = 'UTC';

  setUp(() async {
    plugin = _FakePlugin();
    service = NotificationService(plugin, localTimeZoneName: zone);
    await service.init();
  });

  tearDown(() => service.dispose());

  group('init', () {
    test('does not request permission', () async {
      expect(
        plugin.requestPermissionsCount,
        0,
        reason: 'asking on cold start is what tanks the grant rate',
      );
    });

    test('switches off every iOS launch-time permission request', () async {
      // The plugin defaults these to true, so leaving them unset would prompt
      // on launch — the exact behaviour this design avoids.
      final darwin = plugin.lastSettings!.iOS!;
      expect(darwin.requestAlertPermission, isFalse);
      expect(darwin.requestBadgePermission, isFalse);
      expect(darwin.requestSoundPermission, isFalse);
    });

    test('is idempotent', () async {
      await service.init();
      expect(plugin.initializeCount, 1);
    });
  });

  group('scheduleReminder', () {
    Future<void> schedule({
      String ruleId = 'rule-1',
      String vehicleId = 'vehicle-1',
      String nickname = 'Blue Civic',
      String typeLabel = 'Oil change',
      DateTime? dueDate,
      DateTime? now,
    }) {
      return service.scheduleReminder(
        ruleId: ruleId,
        vehicleId: vehicleId,
        vehicleNickname: nickname,
        typeLabel: typeLabel,
        dueDate: dueDate ?? DateTime(2026, 9, 10),
        now: now ?? DateTime(2026, 6, 15),
      );
    }

    test('schedules at 09:00 local on the due date', () async {
      await schedule(dueDate: DateTime(2026, 9, 10));

      final at = plugin.scheduled.single.scheduledDate;
      expect(at.year, 2026);
      expect(at.month, 9);
      expect(at.day, 10);
      expect(at.hour, 9);
      expect(at.minute, 0);
      expect(at.location.name, zone);
    });

    test('uses the specified title and body', () async {
      await schedule(nickname: 'Blue Civic', typeLabel: 'Oil change');

      expect(plugin.scheduled.single.title, 'Blue Civic: Oil change due');
      expect(plugin.scheduled.single.body, 'Tap to log it or snooze.');
    });

    test('derives the id from the base plus a stable hash', () async {
      await schedule(ruleId: 'rule-1');

      expect(
        plugin.scheduled.single.id,
        NotificationService.reminderNotificationId('rule-1'),
      );
      expect(
        plugin.scheduled.single.id,
        greaterThanOrEqualTo(AppConstants.reminderNotificationBase),
      );
    });

    test('carries the vehicle and rule in the payload', () async {
      await schedule(ruleId: 'rule-1', vehicleId: 'vehicle-1');

      final payload =
          jsonDecode(plugin.scheduled.single.payload!) as Map<String, dynamic>;
      expect(payload['vehicleId'], 'vehicle-1');
      expect(payload['ruleId'], 'rule-1');
    });

    test('skips a due date already in the past', () async {
      await schedule(
        dueDate: DateTime(2026, 1, 10),
        now: DateTime(2026, 6, 15),
      );

      expect(
        plugin.scheduled,
        isEmpty,
        reason: 'firing "due today" for something months lapsed reads as a bug',
      );
    });

    test('skips today once 09:00 has passed', () async {
      await schedule(
        dueDate: DateTime(2026, 6, 15),
        now: DateTime(2026, 6, 15, 10),
      );

      expect(plugin.scheduled, isEmpty);
    });

    test('still schedules today before 09:00', () async {
      await schedule(
        dueDate: DateTime(2026, 6, 15),
        now: DateTime(2026, 6, 15, 7),
      );

      expect(plugin.scheduled, hasLength(1));
    });
  });

  group('reminderNotificationId', () {
    test('is stable for the same rule id', () {
      expect(
        NotificationService.reminderNotificationId('rule-1'),
        NotificationService.reminderNotificationId('rule-1'),
      );
    });

    test('differs between rule ids', () {
      expect(
        NotificationService.reminderNotificationId('rule-1'),
        isNot(NotificationService.reminderNotificationId('rule-2')),
      );
    });

    test('sits above the base and inside 32 bits', () {
      // Realistic uuids, since that is what rule ids actually are.
      const ids = [
        '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
        '7c9e6679-7425-40de-944b-e07fc1f90ae7',
        '550e8400-e29b-41d4-a716-446655440000',
      ];

      for (final id in ids) {
        final notificationId = NotificationService.reminderNotificationId(id);
        expect(
          notificationId,
          greaterThanOrEqualTo(AppConstants.reminderNotificationBase),
        );
        expect(notificationId, lessThan(1 << 31));
      }
    });

    test('never collides with the odometer nudge id', () {
      const ids = [
        'rule-1',
        'rule-2',
        '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
        '7c9e6679-7425-40de-944b-e07fc1f90ae7',
      ];

      for (final id in ids) {
        expect(
          NotificationService.reminderNotificationId(id),
          isNot(AppConstants.odometerNudgeNotificationId),
        );
      }
    });

    test('spreads a realistic set of uuids without collisions', () {
      final ids = <int>{};
      for (var i = 0; i < 500; i++) {
        ids.add(
          NotificationService.reminderNotificationId(
            '3f2504e0-4f89-11d3-9a0c-0305e82c${i.toString().padLeft(4, '0')}',
          ),
        );
      }

      expect(ids, hasLength(500));
    });
  });

  group('cancelReminder', () {
    test('cancels the id derived from the rule', () async {
      await service.cancelReminder('rule-1');

      expect(plugin.cancelled, [
        NotificationService.reminderNotificationId('rule-1'),
      ]);
    });
  });

  group('odometer nudge', () {
    test('uses the copy it is given', () async {
      await service.scheduleOdometerNudge(
        DateTime(2026, 7, 1),
        title: 'How many miles now?',
        body: 'Quick odometer update keeps your Blue Civic reminders accurate.',
        now: DateTime(2026, 6, 15),
      );

      final entry = plugin.scheduled.single;
      expect(entry.title, 'How many miles now?');
      expect(
        entry.body,
        'Quick odometer update keeps your Blue Civic reminders accurate.',
      );
    });

    test('schedules at 09:00 under the reserved id', () async {
      await service.scheduleOdometerNudge(
        DateTime(2026, 7, 1),
        now: DateTime(2026, 6, 15),
      );

      final entry = plugin.scheduled.single;
      expect(entry.id, AppConstants.odometerNudgeNotificationId);
      expect(entry.scheduledDate.hour, 9);
      expect(entry.scheduledDate.day, 1);
      expect(entry.scheduledDate.month, 7);
    });

    test('skips a date already past', () async {
      await service.scheduleOdometerNudge(
        DateTime(2026, 1, 1),
        now: DateTime(2026, 6, 15),
      );

      expect(plugin.scheduled, isEmpty);
    });

    test('cancel targets the reserved id', () async {
      await service.cancelOdometerNudge();

      expect(plugin.cancelled, [AppConstants.odometerNudgeNotificationId]);
    });
  });

  group('rescheduleAll', () {
    ScheduledReminder reminder(String ruleId, DateTime dueDate) {
      return ScheduledReminder(
        ruleId: ruleId,
        vehicleId: 'vehicle-1',
        vehicleNickname: 'Blue Civic',
        typeLabel: 'Oil change',
        dueDate: dueDate,
      );
    }

    test('clears everything before re-scheduling', () async {
      await service.rescheduleAll([
        reminder('rule-1', DateTime(2026, 9, 10)),
      ], now: DateTime(2026, 6, 15));

      expect(plugin.cancelAllCount, 1);
      expect(
        plugin.callOrder.indexOf('cancelAll'),
        lessThan(plugin.callOrder.indexOf('zonedSchedule')),
      );
    });

    test('schedules one notification per reminder', () async {
      await service.rescheduleAll([
        reminder('rule-1', DateTime(2026, 9, 10)),
        reminder('rule-2', DateTime(2026, 10, 1)),
      ], now: DateTime(2026, 6, 15));

      expect(plugin.scheduled.map((s) => s.id), [
        NotificationService.reminderNotificationId('rule-1'),
        NotificationService.reminderNotificationId('rule-2'),
      ]);
    });

    test('drops reminders whose date has passed', () async {
      await service.rescheduleAll([
        reminder('past', DateTime(2026, 1, 1)),
        reminder('future', DateTime(2026, 9, 10)),
      ], now: DateTime(2026, 6, 15));

      expect(plugin.scheduled.map((s) => s.id), [
        NotificationService.reminderNotificationId('future'),
      ]);
    });

    test('re-schedules the nudge that cancelAll just wiped', () async {
      await service.rescheduleAll(
        [reminder('rule-1', DateTime(2026, 9, 10))],
        odometerNudgeDate: DateTime(2026, 7, 1),
        now: DateTime(2026, 6, 15),
      );

      expect(
        plugin.scheduled.map((s) => s.id),
        contains(AppConstants.odometerNudgeNotificationId),
      );
    });

    test('leaves the nudge unscheduled when none is given', () async {
      await service.rescheduleAll([
        reminder('rule-1', DateTime(2026, 9, 10)),
      ], now: DateTime(2026, 6, 15));

      expect(
        plugin.scheduled.map((s) => s.id),
        isNot(contains(AppConstants.odometerNudgeNotificationId)),
      );
    });

    test('an empty set leaves nothing scheduled', () async {
      await service.rescheduleAll(const [], now: DateTime(2026, 6, 15));

      expect(plugin.cancelAllCount, 1);
      expect(plugin.scheduled, isEmpty);
    });
  });

  group('permissions', () {
    test('are requested only when asked for explicitly', () async {
      expect(plugin.requestPermissionsCount, 0);

      await service.requestPermissions();

      expect(plugin.requestPermissionsCount, 1);
    });

    test('return whatever the platform answered', () async {
      plugin.permissionResult = false;
      expect(await service.requestPermissions(), isFalse);

      plugin.permissionResult = true;
      expect(await service.requestPermissions(), isTrue);
    });
  });

  group('taps', () {
    test('a reminder tap emits its vehicle and rule', () async {
      final tapped = expectLater(
        service.taps,
        emits(
          isA<NotificationTap>()
              .having((t) => t.vehicleId, 'vehicleId', 'vehicle-1')
              .having((t) => t.ruleId, 'ruleId', 'rule-1'),
        ),
      );

      plugin.responseCallback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '{"vehicleId":"vehicle-1","ruleId":"rule-1"}',
        ),
      );

      await tapped;
    });

    test('a nudge tap is recognised and targets no vehicle', () async {
      final tapped = expectLater(
        service.taps,
        emits(
          isA<NotificationTap>()
              .having((t) => t.isOdometerNudge, 'isOdometerNudge', isTrue)
              .having((t) => t.vehicleId, 'vehicleId', isNull),
        ),
      );

      plugin.responseCallback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '{"nudge":true}',
        ),
      );

      await tapped;
    });

    test('an unreadable payload emits nothing rather than throwing', () async {
      final emitted = <NotificationTap>[];
      final subscription = service.taps.listen(emitted.add);

      plugin.responseCallback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'not json',
        ),
      );
      plugin.responseCallback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '{"ruleId":"rule-1"}',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);
      await subscription.cancel();
    });
  });

  group('initialTap', () {
    test('is null when the app did not launch from a notification', () async {
      plugin.launchDetails = const NotificationAppLaunchDetails(false);

      expect(await service.initialTap(), isNull);
    });

    test('returns the tap that launched the app', () async {
      plugin.launchDetails = const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '{"vehicleId":"vehicle-9","ruleId":"rule-9"}',
        ),
      );

      final tap = await service.initialTap();
      expect(tap!.vehicleId, 'vehicle-9');
      expect(tap.ruleId, 'rule-9');
    });
  });
}
