import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants.dart';

/// A reminder that should have an OS notification scheduled for it.
///
/// A plain value type so the service never touches drift rows directly.
class ScheduledReminder {
  const ScheduledReminder({
    required this.ruleId,
    required this.vehicleId,
    required this.vehicleNickname,
    required this.typeLabel,
    required this.dueDate,
  });

  final String ruleId;
  final String vehicleId;
  final String vehicleNickname;
  final String typeLabel;

  /// The day the rule falls due. Only the date part is used; the notification
  /// always fires at [NotificationService.notificationHour].
  final DateTime dueDate;
}

/// What a tapped notification asks the app to do.
class NotificationTap {
  const NotificationTap.reminder({required String this.vehicleId, this.ruleId})
    : isOdometerNudge = false;

  /// A tap on the odometer nudge, which belongs to no single vehicle.
  const NotificationTap.odometerNudge()
    : vehicleId = null,
      ruleId = null,
      isOdometerNudge = true;

  /// The vehicle to open. Null for the odometer nudge, which opens the
  /// multi-vehicle update screen instead.
  final String? vehicleId;

  /// The rule that fired, when the tap came from a reminder.
  final String? ruleId;

  /// Whether this tap came from the odometer nudge.
  final bool isOdometerNudge;
}

/// The slice of `flutter_local_notifications` this app actually uses.
///
/// [NotificationService] depends on this rather than the plugin class so the
/// scheduling rules can be tested. The plugin dispatches on
/// `defaultTargetPlatform` before anything reaches a method channel, so under
/// the test runner — neither Android nor iOS — even a mocked channel is never
/// consulted. An interface is the only seam that works.
abstract interface class NotificationPlugin {
  Future<bool?> initialize(
    InitializationSettings settings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  });

  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();

  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails();

  /// Every notification currently scheduled with the OS.
  ///
  /// Ground truth for the platform's own bookkeeping — in particular, iOS
  /// caps this list at 64 entries, so it is the only reliable way to check
  /// whether that limit is close during multi-vehicle testing.
  Future<List<PendingNotificationRequest>> pendingNotificationRequests();

  /// Asks iOS (or Android 13+) for permission. Null where inapplicable.
  Future<bool?> requestPermissions();

  /// Whether notifications are already allowed, or null when unknowable.
  Future<bool?> areNotificationsEnabled();
}

/// [NotificationPlugin] backed by the real plugin.
class FlutterLocalNotificationPlugin implements NotificationPlugin {
  FlutterLocalNotificationPlugin(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<bool?> initialize(
    InitializationSettings settings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) {
    return _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
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
  }) {
    return _plugin.zonedSchedule(
      id: id,
      scheduledDate: scheduledDate,
      notificationDetails: notificationDetails,
      androidScheduleMode: androidScheduleMode,
      title: title,
      body: body,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() =>
      _plugin.pendingNotificationRequests();

  @override
  Future<bool?> requestPermissions() {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return ios.requestPermissions(alert: true, badge: true, sound: true);
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return android?.requestNotificationsPermission() ?? Future.value();
  }

  @override
  Future<bool?> areNotificationsEnabled() {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) return android.areNotificationsEnabled();

    // iOS offers no synchronous "already granted?" check through this plugin.
    return Future<bool?>.value();
  }
}

/// Wraps `flutter_local_notifications` for reminder and nudge scheduling.
///
/// Deliberately knows nothing about Riverpod, go_router or the database:
/// callers hand it plain values and listen to [taps] for routing. That keeps
/// the scheduling rules testable without a widget tree.
class NotificationService {
  NotificationService(this._plugin, {String? localTimeZoneName})
    : _localTimeZoneName = localTimeZoneName;

  final NotificationPlugin _plugin;

  /// Overrides the device time zone. Tests pin this; production resolves it
  /// from the device's UTC offset (see [_resolveLocalLocation]).
  final String? _localTimeZoneName;

  final _tapController = StreamController<NotificationTap>.broadcast();

  /// Taps on reminder or nudge notifications, for the app to route on.
  Stream<NotificationTap> get taps => _tapController.stream;

  bool _initialized = false;
  bool _timeZonesReady = false;

  /// The hour of day, in local time, that reminders fire at.
  static const int notificationHour = 9;

  static const AndroidNotificationDetails _androidReminderDetails =
      AndroidNotificationDetails(
        'reminders',
        'Service reminders',
        channelDescription: 'Reminders that a service is coming due.',
        importance: Importance.high,
        priority: Priority.high,
      );

  static const AndroidNotificationDetails _androidNudgeDetails =
      AndroidNotificationDetails(
        'odometer_nudge',
        'Odometer check-ins',
        channelDescription:
            'Occasional prompts to update your odometer so distance-based '
            'reminders stay accurate.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );

  /// Notification payload/presentation shared by both kinds.
  static const NotificationDetails _reminderDetails = NotificationDetails(
    android: _androidReminderDetails,
    iOS: DarwinNotificationDetails(),
  );

  static const NotificationDetails _nudgeDetails = NotificationDetails(
    android: _androidNudgeDetails,
    iOS: DarwinNotificationDetails(),
  );

  /// Initialises the plugin and the timezone database.
  ///
  /// Deliberately does **not** request iOS permission: every
  /// `request*Permission` flag is off, so calling this on launch shows the user
  /// nothing. The prompt happens in [requestPermissions], called the first time
  /// someone creates a reminder rule and only after an explanatory sheet —
  /// asking cold, before the user knows what notifications are for, tanks the
  /// grant rate and iOS only ever lets you ask once.
  Future<void> init() async {
    if (_initialized) return;

    _ensureTimeZonesReady();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    _initialized = true;
  }

  /// Asks iOS for alert, badge and sound permission.
  ///
  /// Call this only from an explicit user action that has just been explained.
  /// Returns whether permission was granted; null when the platform doesn't
  /// gate notifications this way (Android below 13 grants implicitly).
  Future<bool?> requestPermissions() => _plugin.requestPermissions();

  /// Whether the app has already been granted notification permission.
  ///
  /// Null means unknown — iOS offers no such check through this plugin, so
  /// callers should ask and let the OS decide.
  Future<bool?> hasPermission() => _plugin.areNotificationsEnabled();

  /// Schedules the reminder for [ruleId] at 09:00 local time on [dueDate].
  ///
  /// A due date already in the past is skipped rather than fired immediately:
  /// an overdue rule is surfaced in the UI, and firing a "due today" alert for
  /// something that lapsed weeks ago reads as a bug.
  Future<void> scheduleReminder({
    required String ruleId,
    required String vehicleId,
    required String vehicleNickname,
    required String typeLabel,
    required DateTime dueDate,
    DateTime? now,
  }) async {
    _ensureTimeZonesReady();
    final scheduledAt = _atNotificationHour(dueDate);
    if (!scheduledAt.isAfter(_localNow(now))) return;

    await _plugin.zonedSchedule(
      id: reminderNotificationId(ruleId),
      scheduledDate: scheduledAt,
      title: '$vehicleNickname: $typeLabel due',
      body: 'Tap to log it or snooze.',
      notificationDetails: _reminderDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({'vehicleId': vehicleId, 'ruleId': ruleId}),
    );
  }

  /// Debug-only: schedules a real notification at an exact instant, bypassing
  /// the 09:00 rounding [scheduleReminder] always applies.
  ///
  /// A 6-month or 8000-mile interval can't be waited out by hand, so this
  /// exercises the same plugin call and channel configuration as a normal
  /// reminder while letting a developer pick a fire time seconds away. Guarded
  /// by [kDebugMode] so the call site can never reach a release build; asserts
  /// as a second guard in case that check is ever bypassed.
  Future<int> scheduleDebugTestReminder({
    required String ruleId,
    required String vehicleId,
    required String vehicleNickname,
    required String typeLabel,
    required DateTime fireAt,
  }) async {
    assert(kDebugMode, 'scheduleDebugTestReminder must not run in release');
    _ensureTimeZonesReady();

    final id = reminderNotificationId(ruleId);
    final scheduledAt = tz.TZDateTime.from(fireAt, tz.local);

    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: scheduledAt,
      title: '$vehicleNickname: $typeLabel due',
      body: 'Debug test reminder.',
      notificationDetails: _reminderDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({'vehicleId': vehicleId, 'ruleId': ruleId}),
    );

    return id;
  }

  Future<void> cancelReminder(String ruleId) {
    return _plugin.cancel(reminderNotificationId(ruleId));
  }

  /// Cancels everything and re-schedules from [reminders].
  ///
  /// Worth calling on app resume: iOS can silently drop pending notifications
  /// after a restore or a forced restart, and there is no event telling us it
  /// happened. Rebuilding the whole set from current state is cheap and makes
  /// the app self-healing rather than quietly stopping reminding anyone.
  ///
  /// [odometerNudgeDate] is re-scheduled in the same pass, since [cancelAll]
  /// would otherwise drop it too.
  Future<void> rescheduleAll(
    Iterable<ScheduledReminder> reminders, {
    DateTime? odometerNudgeDate,
    DateTime? now,
  }) async {
    await _plugin.cancelAll();

    for (final reminder in reminders) {
      await scheduleReminder(
        ruleId: reminder.ruleId,
        vehicleId: reminder.vehicleId,
        vehicleNickname: reminder.vehicleNickname,
        typeLabel: reminder.typeLabel,
        dueDate: reminder.dueDate,
        now: now,
      );
    }

    if (odometerNudgeDate != null) {
      await scheduleOdometerNudge(odometerNudgeDate, now: now);
    }
  }

  /// Schedules the odometer check-in prompt for [nextDate] at 09:00 local.
  ///
  /// This nudge is what makes distance-based reminders work at all: the app
  /// only learns the odometer when the user types it in, so a distance rule
  /// can never fire on its own. Bringing the user back to enter a reading is
  /// the moment those rules get re-evaluated.
  Future<void> scheduleOdometerNudge(
    DateTime nextDate, {
    String title = 'How far have you driven?',
    String body = 'Update your odometer to keep reminders accurate.',
    DateTime? now,
  }) async {
    _ensureTimeZonesReady();
    final scheduledAt = _atNotificationHour(nextDate);
    if (!scheduledAt.isAfter(_localNow(now))) return;

    await _plugin.zonedSchedule(
      id: AppConstants.odometerNudgeNotificationId,
      scheduledDate: scheduledAt,
      title: title,
      body: body,
      notificationDetails: _nudgeDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({'nudge': true}),
    );
  }

  Future<void> cancelOdometerNudge() {
    return _plugin.cancel(AppConstants.odometerNudgeNotificationId);
  }

  /// Every notification currently scheduled with the OS. See
  /// [NotificationPlugin.pendingNotificationRequests].
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() {
    return _plugin.pendingNotificationRequests();
  }

  /// The tap that launched the app from a terminated state, if any.
  ///
  /// Cold-start taps never reach [taps] — the plugin surfaces them here
  /// instead, so the app must check this once during startup routing.
  Future<NotificationTap?> initialTap() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;

    return _decodePayload(details.notificationResponse?.payload);
  }

  /// The notification id for [ruleId].
  ///
  /// Rule ids are uuids but notification ids must be 32-bit ints, so the id is
  /// derived from a stable hash. [String.hashCode] is deliberately avoided:
  /// it is not guaranteed stable across runs, which would strand notifications
  /// scheduled under a previous id.
  static int reminderNotificationId(String ruleId) {
    return AppConstants.reminderNotificationBase + _stableHash(ruleId);
  }

  /// FNV-1a, folded into a range that leaves room above the base without
  /// overflowing a 32-bit notification id.
  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash % 1000000;
  }

  /// Loads the timezone database and pins [tz.local].
  ///
  /// `tz.local` is a late field that throws when read before it is set, so
  /// every entry point that computes a time calls this rather than assuming
  /// [init] ran first — a scheduling call that beats initialisation should not
  /// crash.
  void _ensureTimeZonesReady() {
    if (_timeZonesReady) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(_resolveLocalLocation());
    _timeZonesReady = true;
  }

  /// [now] as a wall-clock time in the scheduling zone.
  ///
  /// Compares by wall clock rather than instant: callers pass a plain
  /// [DateTime] meaning "09:00 where the user is", and converting that by
  /// instant would shift the hour by the machine's own UTC offset — making a
  /// reminder that has already passed today look like it is still to come.
  static tz.TZDateTime _localNow(DateTime? now) {
    final value = now ?? DateTime.now();
    return tz.TZDateTime(
      tz.local,
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
  }

  /// [date] at [notificationHour] local time.
  static tz.TZDateTime _atNotificationHour(DateTime date) {
    return tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      notificationHour,
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    final tap = _decodePayload(response.payload);
    if (tap != null) _tapController.add(tap);
  }

  static NotificationTap? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;

      if (decoded['nudge'] == true) {
        return const NotificationTap.odometerNudge();
      }

      final vehicleId = decoded['vehicleId'];
      if (vehicleId is! String) return null;

      final ruleId = decoded['ruleId'];
      return NotificationTap.reminder(
        vehicleId: vehicleId,
        ruleId: ruleId is String ? ruleId : null,
      );
    } on FormatException {
      // A payload we can't read shouldn't crash the tap handler; the user just
      // gets the app opened on its default screen.
      return null;
    }
  }

  /// Resolves the device's timezone.
  ///
  /// `timezone` defaults [tz.local] to UTC, which would schedule everything at
  /// 09:00 UTC — wrong for most of the world. There is no IANA zone name
  /// available without an extra plugin, so this picks a zone matching the
  /// device's current UTC offset. That gets the hour right; it can pick a
  /// neighbouring zone with different DST rules, so a caller that knows the
  /// real zone name should pass it to the constructor.
  tz.Location _resolveLocalLocation() {
    final name = _localTimeZoneName;
    if (name != null) return tz.getLocation(name);

    final offset = DateTime.now().timeZoneOffset;
    for (final location in tz.timeZoneDatabase.locations.values) {
      final now = tz.TZDateTime.now(location);
      if (now.timeZoneOffset == offset) return location;
    }

    return tz.UTC;
  }

  Future<void> dispose() => _tapController.close();
}
