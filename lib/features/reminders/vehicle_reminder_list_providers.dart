import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';
import '../../data/repositories/stream_providers.dart';
import 'reminder_engine.dart';
import 'reminder_engine_adapter.dart';

/// A reminder rule paired with its computed due state, for the full-list
/// reminders screen.
///
/// Distinct from `vehicle_detail_providers.dart`'s equivalent: that one
/// filters to active rules only, for the detail screen's summary section. This
/// screen manages every rule, including inactive ones — a toggled-off rule
/// still needs to be visible so it can be toggled back on.
class VehicleRuleRow {
  const VehicleRuleRow({required this.rule, required this.status});

  final ReminderRule rule;
  final ReminderStatus status;
}

/// Every rule for [vehicleId] (active and inactive, excluding soft-deleted),
/// each with its computed status, ordered most urgent first.
///
/// An inactive rule's status is still computed — the interval maths doesn't
/// care whether notifications are switched on — so re-enabling it shows an
/// accurate status immediately rather than a stale or blank one.
final vehicleRuleRowsProvider = Provider.autoDispose
    .family<AsyncValue<List<VehicleRuleRow>>, String>((ref, vehicleId) {
      final vehicleAsync = ref.watch(vehicleStreamProvider(vehicleId));
      final rulesAsync = ref.watch(reminderRulesStreamProvider(vehicleId));

      return vehicleAsync.when(
        loading: () => const AsyncValue.loading(),
        error: AsyncValue.error,
        data: (vehicle) {
          if (vehicle == null) return const AsyncValue.data([]);

          return rulesAsync.when(
            loading: () => const AsyncValue.loading(),
            error: AsyncValue.error,
            data: (rules) {
              final now = DateTime.now();
              final context = vehicle.toEngineContext();

              final rows = rules
                  .map(
                    (rule) => VehicleRuleRow(
                      rule: rule,
                      status: ReminderEngine.compute(
                        rule: rule.toEngineInput(),
                        vehicle: context,
                        now: now,
                      ),
                    ),
                  )
                  .toList();

              rows.sort(
                (a, b) =>
                    a.status.urgency.index.compareTo(b.status.urgency.index),
              );

              return AsyncValue.data(rows);
            },
          );
        },
      );
    });
