import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';
import '../../data/repositories/stream_providers.dart';
import '../reminders/reminder_engine.dart';
import '../reminders/reminder_engine_adapter.dart';

/// A reminder rule paired with its computed due state.
class ReminderRuleWithStatus {
  const ReminderRuleWithStatus({required this.rule, required this.status});

  final ReminderRule rule;
  final ReminderStatus status;
}

/// Active reminder rules for one vehicle, each with its due status, ordered
/// most urgent first so the thing needing attention leads the section.
///
/// Depends on the vehicle as well as the rules: a distance-based rule's status
/// moves every time the odometer does, so this recomputes when either changes.
final vehicleRemindersProvider = Provider.autoDispose
    .family<AsyncValue<List<ReminderRuleWithStatus>>, String>((ref, vehicleId) {
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
              final active = rules
                  .where((r) => r.isActive && r.deletedAt == null)
                  .map(
                    (rule) => ReminderRuleWithStatus(
                      rule: rule,
                      status: ReminderEngine.compute(
                        rule: rule.toEngineInput(),
                        vehicle: context,
                        now: now,
                      ),
                    ),
                  )
                  .toList();

              active.sort(
                (a, b) =>
                    a.status.urgency.index.compareTo(b.status.urgency.index),
              );

              return AsyncValue.data(active);
            },
          );
        },
      );
    });
