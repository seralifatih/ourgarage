import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../data/local/database.dart';
import '../../../data/models/service_type.dart';
import 'odometer_format.dart';

/// Reverse-chronological service history for a vehicle.
class ServiceHistorySection extends StatelessWidget {
  const ServiceHistorySection({
    required this.records,
    required this.distanceUnit,
    required this.onAddRecord,
    required this.onEditRecord,
    required this.onDeleteRecord,
    super.key,
  });

  final List<ServiceRecord> records;
  final String distanceUnit;
  final VoidCallback onAddRecord;
  final ValueChanged<ServiceRecord> onEditRecord;
  final ValueChanged<ServiceRecord> onDeleteRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Service history',
            style: AppTextStyles.sectionHeader.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (records.isEmpty)
          _EmptyHistory(onAddRecord: onAddRecord)
        else ...[
          for (final record in records)
            ServiceRecordRow(
              key: ValueKey(record.id),
              record: record,
              distanceUnit: distanceUnit,
              onTap: () => onEditRecord(record),
              onDismissed: () => onDeleteRecord(record),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: OutlinedButton.icon(
              onPressed: onAddRecord,
              icon: const Icon(Icons.add),
              label: const Text('Add service record'),
            ),
          ),
        ],
      ],
    );
  }
}

/// One service record. Swipe in either direction to delete.
class ServiceRecordRow extends StatelessWidget {
  const ServiceRecordRow({
    required this.record,
    required this.distanceUnit,
    required this.onTap,
    required this.onDismissed,
    super.key,
  });

  final ServiceRecord record;
  final String distanceUnit;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = ServiceType.fromName(record.type);
    final label = type == ServiceType.custom
        ? (record.customTypeLabel ?? type.label)
        : type.label;

    return Dismissible(
      key: ValueKey('dismiss-${record.id}'),
      background: _DismissBackground(alignment: Alignment.centerLeft),
      secondaryBackground: _DismissBackground(alignment: Alignment.centerRight),
      // No confirmation dialog: the undo snackbar is the safety net, and a
      // prompt on every swipe would make routine tidying tedious.
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        onTap: onTap,
        title: Text(label, style: AppTextStyles.listTitle),
        subtitle: Text(
          _describeDetails(),
          style: AppTextStyles.listSubtitle.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: record.cost == null
            ? null
            : Text(
                _formatCost(record.cost!, record.currency),
                style: AppTextStyles.listTitle,
              ),
      ),
    );
  }

  /// "12 Mar 2026 · 128,500 km", omitting the odometer when not recorded.
  String _describeDetails() {
    final date = DateFormat('d MMM yyyy').format(record.performedAt);
    final odometer = record.odometer;
    if (odometer == null) return date;
    return '$date · ${formatOdometer(odometer)} $distanceUnit';
  }

  String _formatCost(double cost, String? currency) {
    // Currency is stored as a free-form code; without a locale mapping the
    // safest rendering is the code alongside a plainly formatted amount.
    final amount = NumberFormat('#,##0.##').format(cost);
    return currency == null || currency.isEmpty ? amount : '$amount $currency';
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.errorContainer,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(
        Icons.delete_outline,
        color: theme.colorScheme.onErrorContainer,
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.onAddRecord});

  final VoidCallback onAddRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No service records yet. Add the last service you remember — '
            'reminders work better once OurGarage knows where you stand.',
            style: AppTextStyles.listSubtitle.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onAddRecord,
            icon: const Icon(Icons.add),
            label: const Text('Add service record'),
          ),
        ],
      ),
    );
  }
}
