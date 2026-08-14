import '../sync/sync_payloads.dart';
import 'database.dart';

/// Enqueues a local change for the sync worker to push.
///
/// Every one of these re-reads the row it is queuing, deliberately without the
/// usual `deletedAt is null` filter: a soft delete is enqueued *after* the
/// tombstone lands, and filtering it out would mean deletions never
/// propagated — the exact bug that lets a peer resurrect a deleted record.
///
/// Callers run these inside the same transaction as the data write. Drift
/// propagates the ambient transaction through the zone, so an enqueue issued
/// from inside `transaction()` commits or rolls back with the change it
/// describes.
extension SyncEnqueue on AppDatabase {
  Future<void> enqueueVehicle(
    String id,
    SyncOperation operation,
    DateTime now,
  ) async {
    final row = await (select(
      vehicles,
    )..where((v) => v.id.equals(id))).getSingleOrNull();
    if (row == null) return;

    await syncQueueDao.enqueue(
      entity: SyncEntity.vehicle,
      entityId: id,
      operation: operation,
      payload: SyncPayloads.vehicleToRemote(row),
      now: now,
    );
  }

  Future<void> enqueueServiceRecord(
    String id,
    SyncOperation operation,
    DateTime now,
  ) async {
    final row = await (select(
      serviceRecords,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return;

    await syncQueueDao.enqueue(
      entity: SyncEntity.serviceRecord,
      entityId: id,
      operation: operation,
      payload: SyncPayloads.serviceRecordToRemote(row),
      now: now,
    );
  }

  Future<void> enqueueReminderRule(
    String id,
    SyncOperation operation,
    DateTime now,
  ) async {
    final row = await (select(
      reminderRules,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return;

    await syncQueueDao.enqueue(
      entity: SyncEntity.reminderRule,
      entityId: id,
      operation: operation,
      payload: SyncPayloads.reminderRuleToRemote(row),
      now: now,
    );
  }

  /// Enqueues every service record and reminder rule hanging off a vehicle.
  ///
  /// Used by the soft-delete cascade: the children were tombstoned in the same
  /// transaction, and each needs its own queue row or the deletion only
  /// propagates one level deep.
  Future<void> enqueueChildrenOf(String vehicleId, DateTime now) async {
    final records = await (select(
      serviceRecords,
    )..where((r) => r.vehicleId.equals(vehicleId))).get();
    for (final record in records) {
      await enqueueServiceRecord(record.id, SyncOperation.delete, now);
    }

    final rules = await (select(
      reminderRules,
    )..where((r) => r.vehicleId.equals(vehicleId))).get();
    for (final rule in rules) {
      await enqueueReminderRule(rule.id, SyncOperation.delete, now);
    }
  }
}
