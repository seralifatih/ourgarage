import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_routes.dart';
import '../../data/local/database.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/stream_providers.dart';
import 'vehicle_detail_providers.dart';
import 'widgets/odometer_update_sheet.dart';
import 'widgets/service_history_section.dart';
import 'widgets/vehicle_detail_header.dart';
import 'widgets/vehicle_reminders_section.dart';

enum _VehicleMenuAction { edit, delete }

/// Everything known about one vehicle: current odometer, reminders, history.
class VehicleDetailScreen extends ConsumerWidget {
  const VehicleDetailScreen({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleAsync = ref.watch(vehicleStreamProvider(vehicleId));

    return vehicleAsync.when(
      loading: () =>
          const _Shell(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => _Shell(body: Center(child: Text('$error'))),
      data: (vehicle) {
        if (vehicle == null) {
          // Reached after deleting the vehicle, or via a stale link.
          return const _Shell(body: Center(child: Text('Vehicle not found')));
        }
        return _VehicleDetailView(vehicle: vehicle);
      },
    );
  }
}

/// Scaffold used while there is no vehicle to title the screen with.
class _Shell extends StatelessWidget {
  const _Shell({required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(), body: body);
  }
}

class _VehicleDetailView extends ConsumerWidget {
  const _VehicleDetailView({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(vehicleRemindersProvider(vehicle.id));
    final recordsAsync = ref.watch(serviceRecordsStreamProvider(vehicle.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(vehicle.nickname),
        actions: [
          PopupMenuButton<_VehicleMenuAction>(
            onSelected: (action) => _onMenuAction(context, ref, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _VehicleMenuAction.edit,
                child: Text('Edit vehicle'),
              ),
              PopupMenuItem(
                value: _VehicleMenuAction.delete,
                child: Text('Delete vehicle'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          VehicleDetailHeader(
            vehicle: vehicle,
            onUpdateOdometer: () => _updateOdometer(context),
          ),
          const Divider(height: 1),
          remindersAsync.when(
            loading: () => const _SectionLoader(),
            error: (error, _) => _SectionError(error: error),
            data: (reminders) => VehicleRemindersSection(
              reminders: reminders,
              distanceUnit: vehicle.odometerUnit,
              onManage: () => context.push(AppRoutes.reminders(vehicle.id)),
            ),
          ),
          const Divider(height: 1),
          recordsAsync.when(
            loading: () => const _SectionLoader(),
            error: (error, _) => _SectionError(error: error),
            data: (records) => ServiceHistorySection(
              records: records,
              distanceUnit: vehicle.odometerUnit,
              onAddRecord: () => context.push(AppRoutes.addService(vehicle.id)),
              onEditRecord: (record) =>
                  context.push(AppRoutes.editService(vehicle.id, record.id)),
              onDeleteRecord: (record) => _deleteRecord(context, ref, record),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the odometer sheet, which writes through `updateOdometer`.
  ///
  /// Reminder statuses are derived from the vehicle's odometer on every build,
  /// so the reminders list re-evaluates itself as soon as the write lands.
  /// Rescheduling the OS-level notifications is Phase 3's job — the scheduler
  /// doesn't exist yet, so there is nothing further to call from here.
  Future<void> _updateOdometer(BuildContext context) {
    return OdometerUpdateSheet.show(context, vehicle);
  }

  Future<void> _onMenuAction(
    BuildContext context,
    WidgetRef ref,
    _VehicleMenuAction action,
  ) async {
    switch (action) {
      case _VehicleMenuAction.edit:
        context.push(AppRoutes.editVehicle(vehicle.id));
      case _VehicleMenuAction.delete:
        await _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${vehicle.nickname}?'),
        content: const Text(
          'This also deletes its service history and reminders. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(vehicleRepositoryProvider).softDeleteVehicle(vehicle.id);

    if (!context.mounted) return;
    // The vehicle is gone; this screen has nothing left to show.
    context.go(AppRoutes.vehicleList);
  }

  Future<void> _deleteRecord(
    BuildContext context,
    WidgetRef ref,
    ServiceRecord record,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(serviceRecordRepositoryProvider);

    await repository.softDeleteRecord(record.id);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Service record deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repository.restoreRecord(record.id),
          ),
        ),
      );
  }
}

class _SectionLoader extends StatelessWidget {
  const _SectionLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        '$error',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
