import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_routes.dart';
import '../../data/models/service_type.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/stream_providers.dart';
import 'reminder_engine.dart';
import 'reminder_interval_summary.dart';
import 'reminder_notification_scheduler.dart';
import 'reminder_status_label.dart';
import 'vehicle_reminder_list_providers.dart';

/// Every reminder rule for one vehicle: interval, status, and an active
/// toggle, with tap-to-edit and a way to add another.
class VehicleRemindersListScreen extends ConsumerWidget {
  const VehicleRemindersListScreen({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleAsync = ref.watch(vehicleStreamProvider(vehicleId));
    final rowsAsync = ref.watch(vehicleRuleRowsProvider(vehicleId));

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: vehicleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (vehicle) {
          if (vehicle == null) {
            return const Center(child: Text('Vehicle not found'));
          }

          return rowsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (rows) => _RemindersList(
              vehicleId: vehicleId,
              distanceUnit: vehicle.odometerUnit,
              rows: rows,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.addReminderRule(vehicleId)),
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
      ),
    );
  }
}

class _RemindersList extends ConsumerWidget {
  const _RemindersList({
    required this.vehicleId,
    required this.distanceUnit,
    required this.rows,
  });

  final String vehicleId;
  final String distanceUnit;
  final List<VehicleRuleRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No reminders yet. A vehicle with no reminders never gets a '
            'notification — add one to get started.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = rows[index];
        return _ReminderRuleTile(
          vehicleId: vehicleId,
          distanceUnit: distanceUnit,
          row: row,
        );
      },
    );
  }
}

class _ReminderRuleTile extends ConsumerWidget {
  const _ReminderRuleTile({
    required this.vehicleId,
    required this.distanceUnit,
    required this.row,
  });

  final String vehicleId;
  final String distanceUnit;
  final VehicleRuleRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = row.rule;
    final type = ServiceType.fromName(rule.type);
    final typeLabel = type == ServiceType.custom
        ? (rule.customTypeLabel ?? type.label)
        : type.label;
    final theme = Theme.of(context);

    return ListTile(
      onTap: () => context.push(AppRoutes.editReminderRule(vehicleId, rule.id)),
      title: Text(typeLabel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reminderIntervalSummary(
              intervalMonths: rule.intervalMonths,
              intervalDistance: rule.intervalDistance,
              distanceUnit: distanceUnit,
            ),
          ),
          Text(
            ReminderStatusLabel.format(row.status, distanceUnit: distanceUnit),
            style: TextStyle(
              color: _statusColor(theme, row.status.urgency),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Switch(
        value: rule.isActive,
        onChanged: (value) => _toggleActive(ref, value),
      ),
    );
  }

  Color _statusColor(ThemeData theme, ReminderUrgency urgency) {
    return switch (urgency) {
      ReminderUrgency.overdue => theme.colorScheme.error,
      ReminderUrgency.dueNow => theme.colorScheme.error,
      ReminderUrgency.dueSoon => theme.colorScheme.tertiary,
      ReminderUrgency.upToDate => theme.colorScheme.onSurfaceVariant,
    };
  }

  Future<void> _toggleActive(WidgetRef ref, bool isActive) async {
    await ref
        .read(reminderRuleRepositoryProvider)
        .updateRule(row.rule.id, isActive: isActive);

    // The toggle is the one place a rule's active state changes outside the
    // form's own save, so the scheduler needs an explicit nudge here too.
    await ref
        .read(reminderNotificationSchedulerProvider)
        .rescheduleForRule(row.rule.id);
  }
}
