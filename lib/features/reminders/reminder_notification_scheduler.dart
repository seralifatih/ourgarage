import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/service_type.dart';
import '../../data/repositories/providers.dart';
import '../../services/notification_service.dart';
import '../../services/notification_service_provider.dart';
import 'reminder_engine.dart';
import 'reminder_engine_adapter.dart';

part 'reminder_notification_scheduler.g.dart';

/// Keeps OS notifications in step with the reminder rules in the database.
///
/// The [NotificationService] deals in plain values; this is the piece that
/// reads current state and hands it over, so the service stays testable
/// without a database.
class ReminderNotificationScheduler {
  const ReminderNotificationScheduler(this._ref);

  final Ref _ref;

  /// Re-schedules the notification for the rule with [ruleId].
  ///
  /// Called whenever a rule's due date moves — most commonly because
  /// `ReminderRuleRepository.markRuleDone` just re-based it after a service
  /// was logged.
  Future<void> rescheduleForRule(String ruleId) async {
    // Every provider is read up front: the reads that follow sit after awaits,
    // and the scope may be gone by then.
    final notifications = _ref.read(notificationServiceProvider);
    final ruleRepository = _ref.read(reminderRuleRepositoryProvider);
    final vehicleRepository = _ref.read(vehicleRepositoryProvider);

    final rule = await ruleRepository.getRule(ruleId);

    // Gone, switched off, or nothing left to fire for: drop any pending
    // notification rather than leaving a stale one scheduled.
    if (rule == null || !rule.isActive || rule.deletedAt != null) {
      await notifications.cancelReminder(ruleId);
      return;
    }

    final vehicle = await vehicleRepository.getVehicle(rule.vehicleId);
    if (vehicle == null) {
      await notifications.cancelReminder(ruleId);
      return;
    }

    final status = ReminderEngine.compute(
      rule: rule.toEngineInput(),
      vehicle: vehicle.toEngineContext(),
      now: DateTime.now(),
    );

    // A distance-only rule has no due date, and must not fire on its own: the
    // app only learns the odometer when the user enters it. Those rules rely
    // on the odometer nudge bringing the user back instead.
    final dueDate = status.dueDate;
    if (dueDate == null) {
      await notifications.cancelReminder(ruleId);
      return;
    }

    await notifications.cancelReminder(ruleId);
    await notifications.scheduleReminder(
      ruleId: rule.id,
      vehicleId: rule.vehicleId,
      vehicleNickname: vehicle.nickname,
      typeLabel: _labelFor(rule.type, rule.customTypeLabel),
      dueDate: dueDate,
    );
  }

  /// Rebuilds every scheduled notification from current database state.
  ///
  /// Call on app resume — see [NotificationService.rescheduleAll] for why the
  /// app has to be self-healing here.
  Future<void> rescheduleAll({DateTime? odometerNudgeDate}) async {
    // Every provider is read up front: this runs from app startup and on
    // resume, so the scope can be torn down while it is still in flight, and
    // reading Ref after an await would throw.
    final ruleRepository = _ref.read(reminderRuleRepositoryProvider);
    final vehicleRepository = _ref.read(vehicleRepositoryProvider);
    final notifications = _ref.read(notificationServiceProvider);

    // These streams close without emitting if the database is torn down while
    // startup is still in flight, and `first` throws on an empty stream. There
    // is nothing to schedule in that case, so bail rather than blow up.
    final rules = await _firstOrNull(ruleRepository.watchAllActiveRules());
    final vehicles = await _firstOrNull(vehicleRepository.watchAllVehicles());
    if (rules == null || vehicles == null) return;

    final byId = {for (final vehicle in vehicles) vehicle.id: vehicle};

    final now = DateTime.now();
    final reminders = <ScheduledReminder>[];

    for (final rule in rules) {
      final vehicle = byId[rule.vehicleId];
      if (vehicle == null) continue;

      final status = ReminderEngine.compute(
        rule: rule.toEngineInput(),
        vehicle: vehicle.toEngineContext(),
        now: now,
      );

      final dueDate = status.dueDate;
      if (dueDate == null) continue;

      reminders.add(
        ScheduledReminder(
          ruleId: rule.id,
          vehicleId: rule.vehicleId,
          vehicleNickname: vehicle.nickname,
          typeLabel: _labelFor(rule.type, rule.customTypeLabel),
          dueDate: dueDate,
        ),
      );
    }

    await notifications.rescheduleAll(
      reminders,
      odometerNudgeDate: odometerNudgeDate,
      now: now,
    );
  }

  /// The stream's first value, or null if it closes without emitting.
  ///
  /// `Stream.first` throws on an empty stream — which a drift query stream
  /// does when the database is disposed mid-flight — and `package:async` isn't
  /// a direct dependency, so this is the dependency-free equivalent. The
  /// subscription is cancelled as soon as a value arrives, so the caller never
  /// holds a live query open.
  static Future<T?> _firstOrNull<T>(Stream<T> stream) {
    final completer = Completer<T?>();
    late final StreamSubscription<T> subscription;

    void complete(T? value) {
      if (completer.isCompleted) return;
      completer.complete(value);
      unawaited(subscription.cancel());
    }

    subscription = stream.listen(
      complete,
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
      onDone: () => complete(null),
    );

    return completer.future;
  }

  static String _labelFor(String storedType, String? customLabel) {
    final type = ServiceType.fromName(storedType);
    return type == ServiceType.custom
        ? (customLabel ?? type.label)
        : type.label;
  }
}

@Riverpod(keepAlive: true)
ReminderNotificationScheduler reminderNotificationScheduler(Ref ref) {
  return ReminderNotificationScheduler(ref);
}
