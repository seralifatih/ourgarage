import 'package:intl/intl.dart';

import 'reminder_engine.dart';

/// Renders a [ReminderStatus] as the one line shown next to a rule.
///
/// A rule can be measured in time, in distance, or both. Only one line is
/// shown, so the formatter picks whichever measure the driver will hit first
/// and describes that one — the other is noise until it becomes the binding
/// constraint.
class ReminderStatusLabel {
  ReminderStatusLabel._();

  /// Formats [status] for a vehicle measuring distance in [distanceUnit].
  ///
  /// Examples: `Overdue by 12 days`, `Overdue by 340 mi`, `Due in 340 mi`,
  /// `Due in 12 days`, `Due Mar 2027`.
  static String format(ReminderStatus status, {required String distanceUnit}) {
    final days = status.daysRemaining;
    final distance = status.distanceRemaining;

    if (days == null && distance == null) return 'No schedule';

    if (status.urgency == ReminderUrgency.overdue) {
      return _overdueLabel(days, distance, distanceUnit);
    }

    // Not yet due: describe whichever threshold arrives first. Days and
    // distance aren't directly comparable, so each is measured as a fraction
    // of its own "due soon" window and the nearer one wins.
    final useDays = _timeIsNearer(days, distance);

    if (useDays && days != null) {
      if (days == 0) return 'Due now';
      // Beyond about a month out, a countdown in days stops being meaningful —
      // name the month instead.
      if (days >= ReminderStatus.dueSoonDays && status.dueDate != null) {
        return 'Due ${DateFormat('MMM yyyy').format(status.dueDate!)}';
      }
      return 'Due in ${_days(days)}';
    }

    if (distance != null) {
      return distance == 0 ? 'Due now' : 'Due in $distance $distanceUnit';
    }

    // Distance-only rule with no baseline to measure from.
    return status.dueDate == null
        ? 'No schedule'
        : 'Due ${DateFormat('MMM yyyy').format(status.dueDate!)}';
  }

  static String _overdueLabel(int? days, int? distance, String distanceUnit) {
    final overdueByDays = days != null && days < 0;
    final overdueByDistance = distance != null && distance < 0;

    // When both have lapsed, lead with whichever is further past due, since
    // that is the more alarming number and the one driving urgency.
    if (overdueByDays && overdueByDistance) {
      final daysPast = -days;
      final distancePast = -distance;
      final daysShare = daysPast / ReminderStatus.dueSoonDays;
      final distanceShare = distancePast / ReminderStatus.dueSoonDistance;
      return daysShare >= distanceShare
          ? 'Overdue by ${_days(daysPast)}'
          : 'Overdue by $distancePast $distanceUnit';
    }

    if (overdueByDays) return 'Overdue by ${_days(-days)}';
    if (overdueByDistance) return 'Overdue by ${-distance} $distanceUnit';

    // Urgency said overdue, but neither measure is past zero.
    return 'Due now';
  }

  /// Whether the time interval binds before the distance one.
  static bool _timeIsNearer(int? days, int? distance) {
    if (days == null) return false;
    if (distance == null) return true;

    final daysShare = days / ReminderStatus.dueSoonDays;
    final distanceShare = distance / ReminderStatus.dueSoonDistance;
    return daysShare <= distanceShare;
  }

  static String _days(int count) => count == 1 ? '1 day' : '$count days';
}
