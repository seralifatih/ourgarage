import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/remote_garage.dart';
import '../local/database.dart';
import 'sync_payloads.dart';

/// What the sync indicator shows. Never blocks anything.
enum SyncStatus {
  /// Nothing pending, nothing running.
  idle,

  /// Pushing or pulling right now.
  syncing,

  /// Changes are queued but could not be sent — almost always no network.
  pendingOffline,
}

/// Two-way sync between the local Drift database and the household's cloud
/// copy.
///
/// The local database is the read path for the entire UI and stays that way.
/// Nothing here is ever awaited by a screen: a service record gets logged in a
/// garage or a parking lot, where signal is worst, and an app that blocks on
/// connectivity in that moment has failed at the one job it had.
///
/// **Push** drains the outbox. Each queue row carries the snapshot to send, so
/// a failure leaves the row in place and the next run retries it. Rows are
/// coalesced per entity when enqueued, so the queue is proportional to how
/// many things changed, not how often.
///
/// **Pull** asks for rows changed since the high-water mark and merges them.
///
/// **Conflicts resolve last-write-wins on `updatedAt`, per row.** This is a
/// maintenance log, not collaborative text: two people almost never touch the
/// same record, and when they do, the later edit being the survivor is what a
/// reasonable person expects. Anything stronger — CRDTs, operational
/// transforms, merge UI — costs far more than the problem is worth here.
///
/// Two consequences worth stating, because they are easy to get wrong:
///  * A pulled row is only applied if it is **strictly newer** than the local
///    one. A device with an unpushed local edit therefore keeps it rather than
///    having it silently reverted by an older remote copy.
///  * Deletes travel as ordinary rows carrying `deletedAt`, so a delete on one
///    device is not resurrected by a stale push from another — the resurrection
///    would have to carry a newer `updatedAt`, which by definition means the
///    user really did edit it afterwards.
class SyncService {
  SyncService({
    required AppDatabase db,
    required RemoteGarage remote,
    DateTime Function()? clock,
  }) : _db = db,
       _remote = remote,
       _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final RemoteGarage _remote;
  final DateTime Function() _now;

  final _statusController = StreamController<SyncStatus>.broadcast();

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  /// Sync state for the indicator. Replays the current value to new listeners.
  Stream<SyncStatus> get statusStream async* {
    yield _status;
    yield* _statusController.stream;
  }

  /// Guards against two runs overlapping — resume and post-write can easily
  /// fire together, and both draining the same queue would double-push.
  bool _running = false;

  void _setStatus(SyncStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  /// Pushes the outbox, then pulls. Safe to call at any time from anywhere.
  ///
  /// Never throws: sync failing is an ordinary condition, not an error the
  /// caller has to handle. Failures leave work queued and update [status].
  /// Returns whether everything got through.
  Future<bool> sync({required String householdId}) async {
    if (_running) return false;
    _running = true;
    _setStatus(SyncStatus.syncing);

    try {
      final pushed = await _push();
      // Pull regardless: a push that failed on a poisoned row should not stop
      // this device from seeing what everyone else did.
      final pulled = await _pull(householdId);

      final pending = await _db.syncQueueDao.pending(limit: 1);
      _setStatus(pending.isEmpty ? SyncStatus.idle : SyncStatus.pendingOffline);
      return pushed && pulled;
    } finally {
      _running = false;
    }
  }

  /// Drains the outbox, oldest first.
  Future<bool> _push() async {
    final pending = await _db.syncQueueDao.pending();
    if (pending.isEmpty) return true;

    for (final item in pending) {
      final entity = SyncEntity.fromName(item.entityType);
      final payload = jsonDecode(item.payload) as Map<String, dynamic>;

      try {
        switch (entity) {
          case SyncEntity.vehicle:
            await _remote.upsertVehicles([payload]);
          case SyncEntity.serviceRecord:
            await _remote.upsertServiceRecords([payload]);
          case SyncEntity.reminderRule:
            await _remote.upsertReminderRules([payload]);
        }
        await _db.syncQueueDao.remove(item.id);
      } on Object catch (error) {
        // Left queued deliberately. Whether this was a dead network or a row
        // the server rejects, the next run tries again; `attempts` is what
        // makes a permanently poisoned row visible rather than invisible.
        await _db.syncQueueDao.recordAttempt(item.id);
        debugPrint(
          'Sync push failed for ${item.entityType} ${item.entityId}: '
          '$error',
        );
        return false;
      }
    }

    return true;
  }

  /// Fetches remote changes and merges them under last-write-wins.
  Future<bool> _pull(String householdId) async {
    final since = await _db.syncQueueDao.lastPulledAt();

    // Captured before the fetch, never after: anything written remotely while
    // this request was in flight must be caught by the next pull rather than
    // skipped by a mark that has already moved past it.
    final startedAt = _now().toUtc();

    final List<Map<String, dynamic>> rows;
    try {
      rows = await _remote.fetchChangedSince(
        householdId: householdId,
        since: since,
      );
    } on Object catch (error) {
      debugPrint('Sync pull failed: $error');
      return false;
    }

    // Vehicles first: a service record arriving before its vehicle would
    // violate the local foreign key.
    final ordered = [
      ...rows.where((r) => r['_entity'] == SyncEntity.vehicle.name),
      ...rows.where((r) => r['_entity'] != SyncEntity.vehicle.name),
    ];

    await _db.transaction(() async {
      for (final row in ordered) {
        await _applyRemoteRow(row);
      }
    });

    await _db.syncQueueDao.setLastPulledAt(startedAt);
    return true;
  }

  /// Applies one remote row, if it is newer than what is already here.
  Future<void> _applyRemoteRow(Map<String, dynamic> row) async {
    final entity = SyncEntity.fromName(row['_entity'] as String);
    final id = row['id'] as String;
    final remoteUpdatedAt = SyncPayloads.remoteUpdatedAt(row);

    final localUpdatedAt = await _localUpdatedAt(entity, id);

    // Strictly newer, so an equal timestamp is a no-op rather than a pointless
    // rewrite — and, more importantly, a local edit made at the same instant
    // is not thrown away on a coin flip.
    if (localUpdatedAt != null &&
        !remoteUpdatedAt.isAfter(localUpdatedAt.toUtc())) {
      return;
    }

    // Written straight to the tables rather than through the DAOs, and that is
    // load-bearing: the DAO write methods enqueue a sync row, so applying a
    // pulled change through them would queue it straight back for pushing —
    // two devices bouncing the same row between them forever.
    switch (entity) {
      case SyncEntity.vehicle:
        await _db
            .into(_db.vehicles)
            .insertOnConflictUpdate(SyncPayloads.vehicleFromRemote(row));
      case SyncEntity.serviceRecord:
        await _db
            .into(_db.serviceRecords)
            .insertOnConflictUpdate(SyncPayloads.serviceRecordFromRemote(row));
      case SyncEntity.reminderRule:
        await _db
            .into(_db.reminderRules)
            .insertOnConflictUpdate(SyncPayloads.reminderRuleFromRemote(row));
    }
  }

  Future<DateTime?> _localUpdatedAt(SyncEntity entity, String id) async {
    switch (entity) {
      case SyncEntity.vehicle:
        final row = await (_db.select(
          _db.vehicles,
        )..where((v) => v.id.equals(id))).getSingleOrNull();
        return row?.updatedAt;
      case SyncEntity.serviceRecord:
        final row = await (_db.select(
          _db.serviceRecords,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        return row?.updatedAt;
      case SyncEntity.reminderRule:
        final row = await (_db.select(
          _db.reminderRules,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        return row?.updatedAt;
    }
  }

  Future<void> dispose() => _statusController.close();
}
