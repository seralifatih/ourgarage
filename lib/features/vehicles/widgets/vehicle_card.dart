import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../data/local/database.dart';
import '../../reminders/reminder_engine.dart';
import 'odometer_format.dart';
import 'reminder_status_chip.dart';

/// One vehicle in the garage list.
class VehicleCard extends StatelessWidget {
  const VehicleCard({
    required this.vehicle,
    required this.status,
    required this.onTap,
    required this.onUpdateOdometer,
    this.now,
    super.key,
  });

  final Vehicle vehicle;

  /// Most urgent reminder for this vehicle, or null when it has no active
  /// rules — in which case no chip is shown.
  final ReminderStatus? status;

  final VoidCallback onTap;
  final VoidCallback onUpdateOdometer;

  /// Injectable clock, so the staleness hint is testable.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = describeVehicle(vehicle);
    final isStale = _odometerIsStale(now ?? DateTime.now());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vehicle.nickname, style: AppTextStyles.listTitle),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: AppTextStyles.listSubtitle.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _OdometerReadout(
                    odometer: vehicle.odometer,
                    unit: vehicle.odometerUnit,
                  ),
                ],
              ),
              if (status != null) ...[
                const SizedBox(height: 12),
                ReminderStatusChip(
                  status: status!,
                  distanceUnit: vehicle.odometerUnit,
                ),
              ],
              if (isStale) ...[
                const SizedBox(height: 8),
                _StaleOdometerHint(onTap: onUpdateOdometer),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _odometerIsStale(DateTime asOf) {
    final updatedAt = vehicle.odometerUpdatedAt;
    // A vehicle whose odometer was never recorded isn't stale — there is
    // nothing to be out of date yet.
    if (updatedAt == null) return false;

    return asOf.difference(updatedAt).inDays >=
        AppConstants.odometerNudgeIntervalDays;
  }
}

class _OdometerReadout extends StatelessWidget {
  const _OdometerReadout({required this.odometer, required this.unit});

  final int odometer;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatOdometer(odometer),
          style: AppTextStyles.metricLarge.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          unit,
          style: AppTextStyles.listSubtitle.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StaleOdometerHint extends StatelessWidget {
  const _StaleOdometerHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        // Keeps the tap target comfortable without visually detaching the hint.
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Odometer may be out of date',
                style: AppTextStyles.listSubtitle.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
