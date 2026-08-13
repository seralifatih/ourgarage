import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/local/database.dart';
import 'odometer_format.dart';

/// Identity and current odometer for the vehicle detail screen.
class VehicleDetailHeader extends StatelessWidget {
  const VehicleDetailHeader({
    required this.vehicle,
    required this.onUpdateOdometer,
    super.key,
  });

  final Vehicle vehicle;
  final VoidCallback onUpdateOdometer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = describeVehicle(vehicle);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vehicle.nickname,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTextStyles.listSubtitle.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Odometer',
                      style: AppTextStyles.sectionHeader.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            formatOdometer(vehicle.odometer),
                            style: AppTextStyles.metricLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          vehicle.odometerUnit,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                // Sits the button on the odometer's baseline rather than the
                // very bottom of the row.
                padding: const EdgeInsets.only(bottom: 4),
                child: OutlinedButton(
                  onPressed: onUpdateOdometer,
                  child: const Text('Update'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
