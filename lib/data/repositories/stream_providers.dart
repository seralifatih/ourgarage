import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/database.dart';
import 'providers.dart';

// These derived providers are declared by hand rather than with `@riverpod`.
//
// riverpod_generator 4.0.4 — the newest version compatible with drift_dev's
// analyzer constraint — throws `InvalidTypeException` for any annotated
// function whose signature mentions a drift row type (`Vehicle`,
// `ServiceRecord`, `ReminderRule`), including behind a typedef or `Raw<>`.
// The repository providers in `providers.dart` are generated normally; only
// these row-typed ones need the manual form. Once riverpod_generator >= 4.0.6
// and drift_dev can coexist, these can move back to `@riverpod`.

/// Live list of vehicles, oldest first, excluding soft-deleted ones.
final vehiclesStreamProvider = StreamProvider.autoDispose<List<Vehicle>>((ref) {
  return ref.watch(vehicleRepositoryProvider).watchAllVehicles();
});

/// Live view of a single vehicle; emits null once it is gone.
final vehicleStreamProvider = StreamProvider.autoDispose
    .family<Vehicle?, String>((ref, id) {
      return ref.watch(vehicleRepositoryProvider).watchVehicle(id);
    });

/// Vehicle count backing the free-tier gate.
final activeVehicleCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(vehicleRepositoryProvider).countActiveVehicles();
});

/// Live service history for a vehicle, newest first.
final serviceRecordsStreamProvider = StreamProvider.autoDispose
    .family<List<ServiceRecord>, String>((ref, vehicleId) {
      return ref
          .watch(serviceRecordRepositoryProvider)
          .watchRecordsForVehicle(vehicleId);
    });

/// Live reminder rules for a vehicle.
final reminderRulesStreamProvider = StreamProvider.autoDispose
    .family<List<ReminderRule>, String>((ref, vehicleId) {
      return ref
          .watch(reminderRuleRepositoryProvider)
          .watchRulesForVehicle(vehicleId);
    });

/// Every active rule across all vehicles — the scheduler's input.
final activeReminderRulesStreamProvider =
    StreamProvider.autoDispose<List<ReminderRule>>((ref) {
      return ref.watch(reminderRuleRepositoryProvider).watchAllActiveRules();
    });
