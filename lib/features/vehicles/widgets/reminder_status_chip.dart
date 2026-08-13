import 'package:flutter/material.dart';

import '../../reminders/reminder_engine.dart';
import '../../reminders/reminder_status_label.dart';

/// Compact badge summarising a vehicle's most urgent reminder.
///
/// Colour carries the same meaning as the text, never on its own — the label
/// always states the status in words for anyone who can't distinguish the hues.
class ReminderStatusChip extends StatelessWidget {
  const ReminderStatusChip({
    required this.status,
    required this.distanceUnit,
    super.key,
  });

  final ReminderStatus status;

  /// The vehicle's odometer unit, used when the chip counts down in distance.
  final String distanceUnit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = _paletteFor(status.urgency, isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: palette.foreground,
        ),
      ),
    );
  }

  /// The chip's text, e.g. "Due now", "Due in 12 days", "Due in 300 km".
  ///
  /// Shares [ReminderStatusLabel] with the detail screen's reminder rows, so
  /// the same rule reads the same way wherever it appears.
  @visibleForTesting
  String get label {
    if (status.urgency == ReminderUrgency.upToDate) return 'Up to date';
    return ReminderStatusLabel.format(status, distanceUnit: distanceUnit);
  }

  static _ChipPalette _paletteFor(ReminderUrgency urgency, bool isDark) {
    switch (urgency) {
      case ReminderUrgency.overdue:
      case ReminderUrgency.dueNow:
        return isDark
            ? const _ChipPalette(Color(0xFF5C1F1C), Color(0xFFFFB4AB))
            : const _ChipPalette(Color(0xFFFFDAD6), Color(0xFF8C1D18));
      case ReminderUrgency.dueSoon:
        return isDark
            ? const _ChipPalette(Color(0xFF4A3609), Color(0xFFF5C86B))
            : const _ChipPalette(Color(0xFFFFEBC2), Color(0xFF6B4E00));
      case ReminderUrgency.upToDate:
        return isDark
            ? const _ChipPalette(Color(0xFF17371F), Color(0xFF9FD5A8))
            : const _ChipPalette(Color(0xFFD7F2DB), Color(0xFF1B5E27));
    }
  }
}

class _ChipPalette {
  const _ChipPalette(this.background, this.foreground);

  final Color background;
  final Color foreground;
}
