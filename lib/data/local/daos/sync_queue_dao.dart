import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../sync/sync_payloads.dart';
import '../database.dart';

part 'sync_queue_dao.g.dart';

/// The outbox of local changes waiting to reach the household's cloud copy.
@DriftAccessor(tables: [SyncQueue, SyncStates])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// Records a local change, replacing any earlier pending change to the same
  /// row.
  ///
  /// Coalescing is what keeps the queue proportional to how many things
  /// changed rather than how many times they changed — an odometer nudged five
  /// times offline pushes once. It is also why the queue is safe to drain in
  /// any order: one row per entity means no two entries can contradict.
  ///
  /// Callers must run this inside the same transaction as the data write. A
  /// change that lands locally without a queue row is invisible to sync
  /// forever, which is the one failure mode this design cannot recover from.
  Future<void> enqueue({
    required SyncEntity entity,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    required DateTime now,
  }) async {
    await (delete(syncQueue)..where(
          (q) => q.entityType.equals(entity.name) & q.entityId.equals(entityId),
        ))
        .go();

    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        id: _uuid.v4(),
        entityType: entity.name,
        entityId: entityId,
        operation: operation.name,
        payload: jsonEncode(payload),
        createdAt: now,
      ),
    );
  }

  /// Pending changes, oldest first.
  ///
  /// Ordered so that a vehicle enqueued before its service record is pushed
  /// first — the remote foreign key requires the parent to exist.
  Future<List<SyncQueueData>> pending({int limit = 200}) {
    return (select(syncQueue)
          ..orderBy([(q) => OrderingTerm.asc(q.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Live count of pending changes, for the sync indicator.
  Stream<int> watchPendingCount() {
    final count = syncQueue.id.count();
    return (selectOnly(
      syncQueue,
    )..addColumns([count])).watchSingle().map((row) => row.read(count) ?? 0);
  }

  Future<void> remove(String id) {
    return (delete(syncQueue)..where((q) => q.id.equals(id))).go();
  }

  Future<void> recordAttempt(String id) async {
    await customUpdate(
      'UPDATE sync_queue SET attempts = attempts + 1 WHERE id = ?',
      variables: [Variable<String>(id)],
      updates: {syncQueue},
    );
  }

  /// Clears the queue. Belongs in a sign-out path, alongside the entitlement
  /// cache — another account's pending writes must not be pushed.
  Future<void> clear() => delete(syncQueue).go();

  // --- pull bookkeeping ----------------------------------------------------

  Future<DateTime?> lastPulledAt() async {
    final row = await (select(
      syncStates,
    )..where((s) => s.id.equals(SyncStates.singleton))).getSingleOrNull();
    return row?.lastPulledAt;
  }

  Future<void> setLastPulledAt(DateTime value) {
    return into(syncStates).insertOnConflictUpdate(
      SyncStatesCompanion.insert(
        id: const Value(SyncStates.singleton),
        lastPulledAt: Value(value),
      ),
    );
  }

  Future<void> resetLastPulledAt() {
    return (delete(
      syncStates,
    )..where((s) => s.id.equals(SyncStates.singleton))).go();
  }
}
