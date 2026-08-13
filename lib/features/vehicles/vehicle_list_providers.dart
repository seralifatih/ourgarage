import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';
import '../../data/repositories/stream_providers.dart';
import '../reminders/reminder_engine.dart';
import '../reminders/reminder_engine_adapter.dart';

/// A vehicle paired with the status of its most urgent active reminder.
class VehicleListEntry {
  const VehicleListEntry({required this.vehicle, this.status});

  final Vehicle vehicle;

  /// Null when the vehicle has no active reminder rules — the card then shows
  /// no chip at all.
  final ReminderStatus? status;
}

/// The home screen's data: every vehicle, each with its most urgent reminder.
///
/// Rules are fetched once for all vehicles and grouped in memory rather than
/// opening a stream per card, so adding vehicles doesn't multiply subscriptions.
/// The result is a plain [AsyncValue] combination: it stays loading until both
/// sources have produced a value, and surfaces whichever errors first.
final vehicleListProvider =
    Provider.autoDispose<AsyncValue<List<VehicleListEntry>>>((ref) {
      final vehicles = ref.watch(vehiclesStreamProvider);
      final rules = ref.watch(activeReminderRulesStreamProvider);

      return vehicles.when(
        loading: () => const AsyncValue.loading(),
        error: AsyncValue.error,
        data: (vehicleList) => rules.when(
          loading: () => const AsyncValue.loading(),
          error: AsyncValue.error,
          data: (ruleList) {
            final now = DateTime.now();
            // The engine has no notion of active or deleted, so rules are filtered
            // here before they reach it.
            final byVehicle = <String, List<ReminderRule>>{};
            for (final rule in ruleList) {
              if (!rule.isActive || rule.deletedAt != null) continue;
              byVehicle.putIfAbsent(rule.vehicleId, () => []).add(rule);
            }

            return AsyncValue.data([
              for (final vehicle in vehicleList)
                VehicleListEntry(
                  vehicle: vehicle,
                  status: ReminderEngine.mostUrgent(
                    rules: (byVehicle[vehicle.id] ?? const []).map(
                      (rule) => rule.toEngineInput(),
                    ),
                    vehicle: vehicle.toEngineContext(),
                    now: now,
                  ),
                ),
            ]);
          },
        ),
      );
    });
