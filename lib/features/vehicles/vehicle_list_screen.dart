import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_routes.dart';
import '../../data/local/database.dart';
import 'vehicle_list_providers.dart';
import 'widgets/odometer_update_sheet.dart';
import 'widgets/vehicle_card.dart';
import 'widgets/vehicle_list_empty_state.dart';

/// The home screen: every vehicle in the garage.
class VehicleListScreen extends ConsumerWidget {
  const VehicleListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(vehicleListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Garage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(error: error),
        data: (list) => list.isEmpty
            ? VehicleListEmptyState(onAddVehicle: () => _addVehicle(context))
            : _VehicleList(entries: list),
      ),
      floatingActionButton: entries.maybeWhen(
        // The empty state carries its own call to action; a FAB on top of it
        // would be a second competing button for the same job.
        data: (list) => list.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _addVehicle(context),
                icon: const Icon(Icons.add),
                label: const Text('Add vehicle'),
              ),
        orElse: () => null,
      ),
    );
  }

  void _addVehicle(BuildContext context) {
    context.push(AppRoutes.addVehicle);
  }
}

class _VehicleList extends StatelessWidget {
  const _VehicleList({required this.entries});

  final List<VehicleListEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return VehicleCard(
          vehicle: entry.vehicle,
          status: entry.status,
          onTap: () => context.push(AppRoutes.vehicleDetail(entry.vehicle.id)),
          onUpdateOdometer: () => _openOdometerSheet(context, entry.vehicle),
        );
      },
    );
  }

  void _openOdometerSheet(BuildContext context, Vehicle vehicle) {
    OdometerUpdateSheet.show(context, vehicle);
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your garage",
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
