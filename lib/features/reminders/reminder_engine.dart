/// Pure reminder due-date maths.
///
/// Deliberately free of Flutter and database imports: everything the engine
/// needs arrives as plain values, so the rules can be exercised in isolation
/// and can't drift out of sync with a widget rebuild or a query.
library;

/// How urgent a reminder is, worst first.
///
/// Declaration order is meaningful — [ReminderUrgency.overdue] is index 0 and
/// [ReminderUrgency.upToDate] is last, so comparing indices sorts the most
/// pressing rule to the top.
enum ReminderUrgency { overdue, dueNow, dueSoon, upToDate }

/// The inputs describing a single reminder rule.
///
/// A plain value type rather than the drift row, so the engine has no database
/// dependency. [distanceBaseline] is the odometer reading the current interval
/// counts from: the reading at the last service, or — for a rule that has
/// never been completed — the vehicle's odometer when the rule was created.
class ReminderRuleInput {
  const ReminderRuleInput({
    required this.createdAt,
    this.intervalMonths,
    this.intervalDistance,
    this.lastDoneAt,
    this.distanceBaseline,
  });

  /// When the rule was created; the fallback start of the time interval.
  final DateTime createdAt;

  /// Months between services, or null for a distance-only rule.
  final int? intervalMonths;

  /// Distance between services in the vehicle's own unit, or null for a
  /// time-only rule.
  final int? intervalDistance;

  /// When the rule was last completed, or null if it never has been.
  final DateTime? lastDoneAt;

  /// Odometer reading the current distance interval counts from.
  ///
  /// Null means the rule has a distance interval but no known starting
  /// reading, so no distance figure can be produced.
  final int? distanceBaseline;
}

/// The vehicle state a rule is measured against.
class VehicleReminderContext {
  const VehicleReminderContext({
    required this.odometer,
    this.odometerUpdatedAt,
  });

  /// The vehicle's current odometer reading.
  final int odometer;

  /// When [odometer] was last recorded, or null if it never has been.
  final DateTime? odometerUpdatedAt;
}

/// The computed due state of one reminder rule.
class ReminderStatus {
  const ReminderStatus({
    required this.urgency,
    required this.odometerStale,
    this.dueDate,
    this.dueOdometer,
    this.daysRemaining,
    this.distanceRemaining,
  });

  /// The calendar date the rule falls due; null without a time interval.
  final DateTime? dueDate;

  /// The odometer reading the rule falls due at; null without a distance
  /// interval or a baseline to count from.
  final int? dueOdometer;

  /// Whole days until due. Negative when overdue.
  final int? daysRemaining;

  /// Distance until due in the vehicle's unit. Negative when overdue.
  final int? distanceRemaining;

  final ReminderUrgency urgency;

  /// Whether the distance side of this status is built on an odometer reading
  /// too old to trust.
  ///
  /// True only for rules that actually have a distance interval. When set, the
  /// distance figures are an estimate: the vehicle has almost certainly moved
  /// since the last reading, so [distanceRemaining] is an upper bound at best.
  /// See [canFireNotification] for why this matters.
  final bool odometerStale;

  /// Whether this status may fire an unprompted (scheduled) notification.
  ///
  /// Only time-based urgency qualifies. A distance interval can never trigger
  /// a notification on its own: the app only learns the odometer when the user
  /// types it in, so "due now by distance" is really "due now according to a
  /// reading that may be weeks stale". Firing on that would cry wolf.
  ///
  /// Distance rules instead surface in the UI, and are re-evaluated in the
  /// foreground when the user enters a fresh reading — that is the moment an
  /// immediate in-app alert is honest.
  bool get canFireNotification {
    final days = daysRemaining;
    return days != null && days <= dueNowDays;
  }

  /// At or inside this many days, a rule is [ReminderUrgency.dueNow].
  static const int dueNowDays = 7;

  /// At or inside this much distance, a rule is [ReminderUrgency.dueNow].
  static const int dueNowDistance = 200;

  /// At or inside this many days, a rule is [ReminderUrgency.dueSoon].
  static const int dueSoonDays = 30;

  /// At or inside this much distance, a rule is [ReminderUrgency.dueSoon].
  static const int dueSoonDistance = 500;

  /// An odometer reading older than this many days can't be trusted for
  /// distance-based urgency.
  static const int odometerStaleDays = 30;
}

/// Computes reminder due states.
abstract final class ReminderEngine {
  /// Computes the status of [rule] against [vehicle] as of [now].
  ///
  /// When the rule carries both intervals, whichever comes first decides the
  /// urgency — that is the threshold the driver actually reaches first. Both
  /// sets of figures are still reported, so callers can explain either.
  static ReminderStatus compute({
    required ReminderRuleInput rule,
    required VehicleReminderContext vehicle,
    required DateTime now,
  }) {
    final dueDate = _dueDate(rule);
    final daysRemaining = dueDate == null
        ? null
        : _wholeDaysBetween(now, dueDate);

    final dueOdometer = _dueOdometer(rule);
    final distanceRemaining = dueOdometer == null
        ? null
        : dueOdometer - vehicle.odometer;

    final odometerStale =
        rule.intervalDistance != null && _odometerIsStale(vehicle, now);

    return ReminderStatus(
      urgency: _urgency(
        daysRemaining: daysRemaining,
        distanceRemaining: distanceRemaining,
      ),
      odometerStale: odometerStale,
      dueDate: dueDate,
      dueOdometer: dueOdometer,
      daysRemaining: daysRemaining,
      distanceRemaining: distanceRemaining,
    );
  }

  /// Picks the most urgent status among [rules], or null when there are none.
  ///
  /// Rules are supplied already filtered to the ones worth showing; the engine
  /// has no notion of active or deleted.
  static ReminderStatus? mostUrgent({
    required Iterable<ReminderRuleInput> rules,
    required VehicleReminderContext vehicle,
    required DateTime now,
  }) {
    ReminderStatus? best;

    for (final rule in rules) {
      final status = compute(rule: rule, vehicle: vehicle, now: now);
      if (best == null || _isMoreUrgent(status, best)) {
        best = status;
      }
    }

    return best;
  }

  /// Urgency from whichever measure is closest to (or furthest past) due.
  ///
  /// A rule with neither measure can never come due, so it reads as up to
  /// date rather than inventing pressure.
  static ReminderUrgency _urgency({
    required int? daysRemaining,
    required int? distanceRemaining,
  }) {
    if (daysRemaining == null && distanceRemaining == null) {
      return ReminderUrgency.upToDate;
    }

    final overdue =
        (daysRemaining != null && daysRemaining < 0) ||
        (distanceRemaining != null && distanceRemaining < 0);
    if (overdue) return ReminderUrgency.overdue;

    final dueNow =
        (daysRemaining != null && daysRemaining <= ReminderStatus.dueNowDays) ||
        (distanceRemaining != null &&
            distanceRemaining <= ReminderStatus.dueNowDistance);
    if (dueNow) return ReminderUrgency.dueNow;

    final dueSoon =
        (daysRemaining != null &&
            daysRemaining <= ReminderStatus.dueSoonDays) ||
        (distanceRemaining != null &&
            distanceRemaining <= ReminderStatus.dueSoonDistance);
    if (dueSoon) return ReminderUrgency.dueSoon;

    return ReminderUrgency.upToDate;
  }

  static bool _isMoreUrgent(ReminderStatus candidate, ReminderStatus best) {
    if (candidate.urgency != best.urgency) {
      return candidate.urgency.index < best.urgency.index;
    }

    // Same bucket: prefer whichever sits closest to its threshold.
    final mine = _margin(candidate);
    final theirs = _margin(best);
    if (mine == null) return false;
    if (theirs == null) return true;
    return mine < theirs;
  }

  /// A single "how far from due" figure used only to order two statuses in the
  /// same bucket.
  ///
  /// Days and distance aren't directly comparable, so distance is scaled into
  /// rough day-equivalents using the ratio of their "due soon" windows.
  static double? _margin(ReminderStatus status) {
    final byDays = status.daysRemaining?.toDouble();
    final byDistance = status.distanceRemaining == null
        ? null
        : status.distanceRemaining! *
              (ReminderStatus.dueSoonDays / ReminderStatus.dueSoonDistance);

    if (byDays == null) return byDistance;
    if (byDistance == null) return byDays;
    return byDays < byDistance ? byDays : byDistance;
  }

  /// The date [rule] falls due, or null without a time interval.
  static DateTime? _dueDate(ReminderRuleInput rule) {
    final months = rule.intervalMonths;
    if (months == null) return null;

    final from = rule.lastDoneAt ?? rule.createdAt;
    // DateTime normalises overflowing months and clamps day-of-month, so
    // 31 Jan + 1 month lands on 3 Mar rather than throwing.
    return DateTime(from.year, from.month + months, from.day);
  }

  /// The odometer reading [rule] falls due at, or null without a distance
  /// interval or a baseline.
  static int? _dueOdometer(ReminderRuleInput rule) {
    final interval = rule.intervalDistance;
    final baseline = rule.distanceBaseline;
    if (interval == null || baseline == null) return null;

    return baseline + interval;
  }

  static bool _odometerIsStale(VehicleReminderContext vehicle, DateTime now) {
    final updatedAt = vehicle.odometerUpdatedAt;
    // Never recorded is the least trustworthy case of all.
    if (updatedAt == null) return true;

    return _wholeDaysBetween(updatedAt, now) >=
        ReminderStatus.odometerStaleDays;
  }

  /// Whole days from [from] to [to], both truncated to midnight.
  ///
  /// Truncating keeps "due later today" reading as 0 days rather than a
  /// fraction that rounds the wrong way.
  static int _wholeDaysBetween(DateTime from, DateTime to) {
    return DateTime(
      to.year,
      to.month,
      to.day,
    ).difference(DateTime(from.year, from.month, from.day)).inDays;
  }
}
