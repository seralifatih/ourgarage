/// Decides whether the odometer nudge should be scheduled, and for when.
///
/// Pure Dart: no Flutter, no database. The nudge is what keeps distance-based
/// reminders alive — the app only learns the odometer when the user types it
/// in, so a distance rule can never come due on its own. Getting the "when"
/// wrong in either direction is costly: too eager and it becomes nagging the
/// user learns to swipe away, too shy and distance reminders quietly stop
/// working.
library;

/// One vehicle's state, as far as the nudge decision is concerned.
class NudgeVehicleState {
  const NudgeVehicleState({
    required this.vehicleId,
    required this.nickname,
    required this.odometerUnit,
    required this.hasActiveDistanceRule,
    this.odometerUpdatedAt,
  });

  final String vehicleId;
  final String nickname;

  /// `km` or `mi`, used to phrase the notification title.
  final String odometerUnit;

  /// Whether this vehicle has at least one active reminder keyed to distance.
  ///
  /// Vehicles without one are irrelevant to the nudge: their reminders all run
  /// on dates the app already knows.
  final bool hasActiveDistanceRule;

  /// When the odometer was last recorded, or null if it never has been.
  final DateTime? odometerUpdatedAt;
}

/// What should happen to the odometer nudge.
class OdometerNudgePlan {
  const OdometerNudgePlan._({
    required this.shouldSchedule,
    this.nextNudgeDate,
    this.title,
    this.body,
  });

  /// Nothing to nudge about — the caller should cancel any pending nudge.
  const OdometerNudgePlan.none()
    : shouldSchedule = false,
      nextNudgeDate = null,
      title = null,
      body = null;

  final bool shouldSchedule;

  /// The date the next nudge should fire. Null when [shouldSchedule] is false.
  final DateTime? nextNudgeDate;

  final String? title;
  final String? body;
}

abstract final class OdometerNudgePlanner {
  /// Plans the next nudge for [vehicles] as of [now].
  ///
  /// Returns [OdometerNudgePlan.none] only when no vehicle has a
  /// distance-based rule — the one case where a nudge would serve no purpose.
  /// A vehicle whose reading is still fresh doesn't cancel the nudge; it
  /// pushes it out to when that reading goes stale.
  ///
  /// [from] is the date the interval counts from. Callers pass the moment the
  /// user last saved a reading, so someone who updates proactively resets the
  /// clock rather than being nagged on the original schedule.
  static OdometerNudgePlan plan({
    required Iterable<NudgeVehicleState> vehicles,
    required DateTime now,
    required int intervalDays,
    DateTime? from,
  }) {
    final relevant = vehicles
        .where((vehicle) => vehicle.hasActiveDistanceRule)
        .toList();

    // No distance rules anywhere: a nudge would be asking for a number nothing
    // is waiting on. This is the only case that cancels outright.
    if (relevant.isEmpty) return const OdometerNudgePlan.none();

    // Freshness decides *when*, not *whether*. A vehicle updated recently
    // shouldn't be prompted today, but it will need prompting once that
    // reading ages out — cancelling here would silently end the mechanism the
    // first time someone was diligent.
    final baseline = from ?? _mostRecentReading(relevant) ?? now;
    var nextDate = _addDays(baseline, intervalDays);

    // A baseline far enough in the past puts the next nudge in the past too;
    // push it out so the reminder is always ahead of the user.
    if (!nextDate.isAfter(now)) {
      nextDate = _addDays(now, intervalDays);
    }

    return OdometerNudgePlan._(
      shouldSchedule: true,
      nextNudgeDate: nextDate,
      title: _title(relevant),
      body: _body(relevant),
    );
  }

  /// "How many miles now?" / "How many km now?".
  ///
  /// Mixed units across vehicles fall back to the neutral phrasing rather than
  /// picking one fleet's unit and being wrong for the other.
  static String _title(List<NudgeVehicleState> vehicles) {
    final units = vehicles.map((vehicle) => vehicle.odometerUnit).toSet();
    if (units.length != 1) return 'How far have you driven?';

    return units.single == 'mi' ? 'How many miles now?' : 'How many km now?';
  }

  static String _body(List<NudgeVehicleState> vehicles) {
    final subject = vehicles.length == 1
        ? 'your ${vehicles.single.nickname}'
        : 'your vehicles';
    return 'Quick odometer update keeps $subject reminders accurate.';
  }

  /// The newest reading across [vehicles], or null if none has one.
  static DateTime? _mostRecentReading(List<NudgeVehicleState> vehicles) {
    DateTime? newest;
    for (final vehicle in vehicles) {
      final updatedAt = vehicle.odometerUpdatedAt;
      if (updatedAt == null) continue;
      if (newest == null || updatedAt.isAfter(newest)) newest = updatedAt;
    }
    return newest;
  }

  static DateTime _addDays(DateTime from, int days) {
    return DateTime(from.year, from.month, from.day + days);
  }
}
