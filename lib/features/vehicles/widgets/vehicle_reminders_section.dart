import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/service_type.dart';
import '../../reminders/reminder_engine.dart';
import '../../reminders/reminder_status_label.dart';
import '../vehicle_detail_providers.dart';

/// Active reminder rules for a vehicle, most urgent first.
class VehicleRemindersSection extends StatelessWidget {
  const VehicleRemindersSection({
    required this.reminders,
    required this.distanceUnit,
    required this.onManage,
    super.key,
  });

  final List<ReminderRuleWithStatus> reminders;
  final String distanceUnit;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Reminders',
                  style: AppTextStyles.sectionHeader.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: onManage,
                child: const Text('Manage reminders'),
              ),
            ],
          ),
        ),
        if (reminders.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'No active reminders.',
              style: AppTextStyles.listSubtitle.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final entry in reminders)
            _ReminderRow(entry: entry, distanceUnit: distanceUnit),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.entry, required this.distanceUnit});

  final ReminderRuleWithStatus entry;
  final String distanceUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = ServiceType.fromName(entry.rule.type);
    final label = type == ServiceType.custom
        ? (entry.rule.customTypeLabel ?? type.label)
        : type.label;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.listTitle)),
          const SizedBox(width: 12),
          Text(
            ReminderStatusLabel.format(
              entry.status,
              distanceUnit: distanceUnit,
            ),
            style: AppTextStyles.listSubtitle.copyWith(
              color: _statusColor(theme, entry.status.urgency),
              fontWeight: _needsAttention(entry.status.urgency)
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  /// Rules needing action now get the error colour; everything else stays
  /// neutral so the row that needs attention is the only one competing for it.
  Color _statusColor(ThemeData theme, ReminderUrgency urgency) {
    return switch (urgency) {
      ReminderUrgency.overdue ||
      ReminderUrgency.dueNow => theme.colorScheme.error,
      ReminderUrgency.dueSoon => theme.colorScheme.onSurface,
      ReminderUrgency.upToDate => theme.colorScheme.onSurfaceVariant,
    };
  }

  bool _needsAttention(ReminderUrgency urgency) {
    return urgency == ReminderUrgency.overdue ||
        urgency == ReminderUrgency.dueNow;
  }
}
