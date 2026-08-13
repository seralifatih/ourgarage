import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/constants.dart';
import '../../data/local/database.dart';
import '../../data/models/service_type.dart';
import '../../data/repositories/providers.dart';
import '../../services/notification_service_provider.dart';
import 'odometer_nudge_planner.dart';
import 'reminder_engine.dart';
import 'reminder_engine_adapter.dart';

/// A rule that came due as a direct result of a fresh odometer reading.
class DueAfterUpdate {
  const DueAfterUpdate({
    required this.ruleId,
    required this.vehicleId,
    required this.vehicleNickname,
    required this.typeLabel,
    required this.urgency,
  });

  final String ruleId;
  final String vehicleId;
  final String vehicleNickname;
  final String typeLabel;
  final ReminderUrgency urgency;

  /// "Blue Civic is due for an oil change".
  String get message {
    final subject = _midSentence(typeLabel);
    return '$vehicleNickname is due for ${_article(subject)}$subject';
  }

  /// Type labels are sentence-cased for standalone display ("Oil change");
  /// mid-sentence they read better lowercased. Acronyms like "MOT" must
  /// survive intact.
  static String _midSentence(String value) {
    if (value.isEmpty) return value;

    final firstWord = value.split(' ').first;
    if (firstWord.toUpperCase() == firstWord && firstWord.length > 1) {
      return value;
    }
    return value[0].toLowerCase() + value.substring(1);
  }

  /// "an oil change" / "a tire rotation".
  ///
  /// Only the sound of the first letter matters here, and every current
  /// service label is a plain noun phrase, so the vowel test is enough.
  static String _article(String value) {
    if (value.isEmpty) return '';
    return 'aeiou'.contains(value[0].toLowerCase()) ? 'an ' : 'a ';
  }
}

/// Keeps the odometer nudge in step with the rules that depend on it.
///
/// Distance-based reminders can't fire on their own — the app only learns the
/// odometer when the user enters it. This is the mechanism that brings them
/// back to enter one, and re-evaluates those rules the moment they do.
class OdometerNudgeService {
  const OdometerNudgeService(this._ref);

  final Ref _ref;

  /// Recomputes and re-schedules the nudge from current state.
  ///
  /// Pass [from] as the moment the user last saved a reading, so someone who
  /// updates proactively isn't nudged on the old schedule. Cancels any pending
  /// nudge when nothing needs one.
  Future<void> refreshNudge({DateTime? from, DateTime? now}) async {
    // Read every provider before the first await: this runs from app startup
    // and after saves, so the scope may be gone by the time it finishes.
    final notifications = _ref.read(notificationServiceProvider);
    final vehicleRepository = _ref.read(vehicleRepositoryProvider);
    final ruleRepository = _ref.read(reminderRuleRepositoryProvider);

    final vehicles = await _firstOrNull(vehicleRepository.watchAllVehicles());
    final rules = await _firstOrNull(ruleRepository.watchAllActiveRules());
    if (vehicles == null || rules == null) return;

    final plan = OdometerNudgePlanner.plan(
      vehicles: _toNudgeState(vehicles, rules),
      now: now ?? DateTime.now(),
      intervalDays: AppConstants.odometerNudgeIntervalDays,
      from: from,
    );

    if (!plan.shouldSchedule) {
      await notifications.cancelOdometerNudge();
      return;
    }

    await notifications.cancelOdometerNudge();
    await notifications.scheduleOdometerNudge(
      plan.nextNudgeDate!,
      title: plan.title!,
      body: plan.body!,
      now: now,
    );
  }

  /// Saves [readings] (vehicle id to odometer value), then reports which rules
  /// that made due.
  ///
  /// Only rules whose urgency is [ReminderUrgency.dueNow] or
  /// [ReminderUrgency.overdue] *after* the update come back — the caller
  /// surfaces those immediately, which is the honest moment to do it: the
  /// reading is seconds old rather than weeks stale.
  Future<List<DueAfterUpdate>> saveReadings(
    Map<String, int> readings, {
    DateTime? now,
  }) async {
    final vehicleRepository = _ref.read(vehicleRepositoryProvider);
    final ruleRepository = _ref.read(reminderRuleRepositoryProvider);

    for (final entry in readings.entries) {
      await vehicleRepository.updateOdometer(entry.key, entry.value);
    }

    final vehicles = await _firstOrNull(vehicleRepository.watchAllVehicles());
    final rules = await _firstOrNull(ruleRepository.watchAllActiveRules());
    if (vehicles == null || rules == null) return const [];

    final asOf = now ?? DateTime.now();
    final byId = {for (final vehicle in vehicles) vehicle.id: vehicle};
    final due = <DueAfterUpdate>[];

    for (final rule in rules) {
      // Only rules on vehicles the user just updated: an unrelated rule that
      // happens to be overdue isn't a consequence of this action, and
      // surfacing it here would feel like a non sequitur.
      if (!readings.containsKey(rule.vehicleId)) continue;

      final vehicle = byId[rule.vehicleId];
      if (vehicle == null) continue;

      final status = ReminderEngine.compute(
        rule: rule.toEngineInput(),
        vehicle: vehicle.toEngineContext(),
        now: asOf,
      );

      if (status.urgency != ReminderUrgency.dueNow &&
          status.urgency != ReminderUrgency.overdue) {
        continue;
      }

      due.add(
        DueAfterUpdate(
          ruleId: rule.id,
          vehicleId: rule.vehicleId,
          vehicleNickname: vehicle.nickname,
          typeLabel: _labelFor(rule.type, rule.customTypeLabel),
          urgency: status.urgency,
        ),
      );
    }

    // The clock restarts from this save, not the original schedule.
    await refreshNudge(from: asOf, now: asOf);

    return due;
  }

  /// Pairs each vehicle with whether it has an active distance-based rule.
  static List<NudgeVehicleState> _toNudgeState(
    List<Vehicle> vehicles,
    List<ReminderRule> rules,
  ) {
    final withDistanceRule = <String>{
      for (final rule in rules)
        if (rule.intervalDistance != null) rule.vehicleId,
    };

    return [
      for (final vehicle in vehicles)
        NudgeVehicleState(
          vehicleId: vehicle.id,
          nickname: vehicle.nickname,
          odometerUnit: vehicle.odometerUnit,
          hasActiveDistanceRule: withDistanceRule.contains(vehicle.id),
          odometerUpdatedAt: vehicle.odometerUpdatedAt,
        ),
    ];
  }

  static String _labelFor(String storedType, String? customLabel) {
    final type = ServiceType.fromName(storedType);
    return type == ServiceType.custom
        ? (customLabel ?? type.label)
        : type.label;
  }

  /// The stream's first value, or null if it closes without emitting.
  ///
  /// A drift query stream closes empty when the database is disposed
  /// mid-flight, and `Stream.first` throws on that.
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
}
