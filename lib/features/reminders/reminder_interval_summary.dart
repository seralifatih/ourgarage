import 'package:intl/intl.dart';

/// Formats a rule's interval(s) for display: "Every 6 months or 5,000 mi".
///
/// A rule always has at least one interval — the repository enforces that on
/// save — so this never has to describe an empty rule.
String reminderIntervalSummary({
  required int? intervalMonths,
  required int? intervalDistance,
  required String distanceUnit,
}) {
  final parts = <String>[
    if (intervalMonths != null) '$intervalMonths months',
    if (intervalDistance != null)
      '${NumberFormat('#,##0').format(intervalDistance)} $distanceUnit',
  ];

  return 'Every ${parts.join(' or ')}';
}
