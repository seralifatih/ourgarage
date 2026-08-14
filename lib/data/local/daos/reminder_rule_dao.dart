import 'package:drift/drift.dart';

import '../../sync/sync_payloads.dart';
import '../database.dart';
import '../sync_enqueue.dart';

part 'reminder_rule_dao.g.dart';

@DriftAccessor(tables: [ReminderRules])
class ReminderRuleDao extends DatabaseAccessor<AppDatabase>
    with _$ReminderRuleDaoMixin {
  ReminderRuleDao(super.db);

  /// Live list of a vehicle's rules, active and inactive alike, oldest first.
  Stream<List<ReminderRule>> watchRulesForVehicle(String vehicleId) {
    return (select(reminderRules)
          ..where((r) => r.vehicleId.equals(vehicleId) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .watch();
  }

  /// Live list of every active rule across all vehicles — the input the
  /// notification scheduler works from.
  Stream<List<ReminderRule>> watchAllActiveRules() {
    return (select(reminderRules)
          ..where((r) => r.isActive.equals(true) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .watch();
  }

  Future<ReminderRule?> getRule(String id) {
    return (select(
      reminderRules,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull();
  }

  /// Whether any rule has ever been created, across all vehicles and
  /// including inactive or soft-deleted ones.
  ///
  /// Unfiltered on purpose: this answers "has the user ever created a
  /// reminder before", which a later deactivation or deletion doesn't undo.
  Future<bool> hasAnyRuleEverExisted() async {
    final row =
        await (selectOnly(reminderRules)
              ..addColumns([reminderRules.id])
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Every live rule across all vehicles. The migration's read side.
  ///
  /// Unfiltered by `isActive` on purpose: a switched-off rule is still the
  /// user's data and must survive the move to a household.
  Future<List<ReminderRule>> getAllRules() {
    return (select(reminderRules)..where((r) => r.deletedAt.isNull())).get();
  }

  Future<void> insertRule(ReminderRulesCompanion rule) {
    return transaction(() async {
      await into(reminderRules).insert(rule);
      await attachedDatabase.enqueueReminderRule(
        rule.id.value,
        SyncOperation.upsert,
        rule.updatedAt.value,
      );
    });
  }

  Future<bool> updateRule(String id, ReminderRulesCompanion changes) {
    return transaction(() async {
      final updated = await (update(
        reminderRules,
      )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(changes);
      if (updated == 0) return false;

      await attachedDatabase.enqueueReminderRule(
        id,
        SyncOperation.upsert,
        changes.updatedAt.present ? changes.updatedAt.value : DateTime.now(),
      );
      return true;
    });
  }

  Future<bool> softDeleteRule(String id, DateTime deletedAt) {
    return transaction(() async {
      final updated =
          await (update(
            reminderRules,
          )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(
            ReminderRulesCompanion(
              deletedAt: Value(deletedAt),
              updatedAt: Value(deletedAt),
            ),
          );
      if (updated == 0) return false;

      await attachedDatabase.enqueueReminderRule(
        id,
        SyncOperation.delete,
        deletedAt,
      );
      return true;
    });
  }
}
