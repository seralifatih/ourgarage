import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/sync/sync_payloads.dart';
import 'package:ourgarage/data/sync/sync_service.dart';

import '../../support/fake_remote_garage.dart';

const _householdId = 'household-1';
const _vehicleId = 'vehicle-1';

/// Fixed instants, so "which edit is newer" is a fact rather than a race.
final _t0 = DateTime.utc(2026, 6, 1, 12);
final _t1 = DateTime.utc(2026, 6, 1, 13);
final _t2 = DateTime.utc(2026, 6, 1, 14);

void main() {
  late AppDatabase db;
  late FakeRemoteGarage remote;
  late SyncService sync;

  /// Advances a second per read, starting before any fixture data.
  ///
  /// A frozen clock would set the pull high-water mark to the same instant as
  /// the rows under test, and the `updated_at > since` filter would then
  /// correctly exclude them — hiding real behaviour behind a test artefact.
  late DateTime clockNow;
  DateTime clock() {
    clockNow = clockNow.add(const Duration(seconds: 1));
    return clockNow;
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = FakeRemoteGarage();
    clockNow = DateTime.utc(2026, 6, 1, 11);
    sync = SyncService(db: db, remote: remote, clock: clock);

    await db.vehicleDao.insertVehicle(
      VehiclesCompanion.insert(
        id: _vehicleId,
        nickname: 'Blue Civic',
        odometerUnit: 'mi',
        odometer: const Value(10000),
        householdId: const Value(_householdId),
        createdAt: _t0,
        updatedAt: _t0,
      ),
    );
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  /// Returns whether everything got through, which the offline cases assert on.
  Future<bool> runSync() => sync.sync(householdId: _householdId);

  /// A row as another device would have pushed it.
  Map<String, dynamic> remoteRecord({
    required String id,
    required DateTime updatedAt,
    String type = 'oilChange',
    double? cost,
    DateTime? deletedAt,
  }) {
    return {
      'id': id,
      'vehicle_id': _vehicleId,
      'performed_at': _t0.toIso8601String(),
      'odometer': 10000,
      'type': type,
      'custom_type_label': null,
      'notes': null,
      'cost': cost,
      'currency': 'USD',
      'created_at': _t0.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  Future<void> insertLocalRecord({
    required String id,
    required DateTime at,
    double? cost,
  }) {
    return db.serviceRecordDao.insertRecord(
      ServiceRecordsCompanion.insert(
        id: id,
        vehicleId: _vehicleId,
        performedAt: _t0,
        type: ServiceType.oilChange.name,
        cost: Value(cost),
        createdAt: at,
        updatedAt: at,
      ),
    );
  }

  group('local writes enqueue', () {
    test('every write lands in the outbox', () async {
      // The vehicle from setUp, plus this record.
      await insertLocalRecord(id: 'record-1', at: _t0);

      final pending = await db.syncQueueDao.pending();
      expect(pending, hasLength(2));
      expect(
        pending.map((p) => p.entityType),
        containsAll(<String>['vehicle', 'serviceRecord']),
      );
    });

    test('repeated edits to one row coalesce into a single entry', () async {
      await insertLocalRecord(id: 'record-1', at: _t0);
      for (var i = 0; i < 5; i++) {
        await db.serviceRecordDao.updateRecord(
          'record-1',
          ServiceRecordsCompanion(
            cost: Value(10.0 * i),
            updatedAt: Value(_t0.add(Duration(minutes: i))),
          ),
        );
      }

      final forRecord = (await db.syncQueueDao.pending())
          .where((p) => p.entityId == 'record-1')
          .toList();
      expect(forRecord, hasLength(1), reason: 'one row per entity');
    });
  });

  group('offline write then reconnect', () {
    test('writes survive being offline and push on reconnect', () async {
      remote.offline = true;

      // The garage with no signal. Everything must still work.
      await insertLocalRecord(id: 'record-1', at: _t0, cost: 80);
      await insertLocalRecord(id: 'record-2', at: _t1, cost: 45);

      final okOffline = await runSync();
      expect(okOffline, isFalse);
      expect(remote.serviceRecords, isEmpty);
      expect(sync.status, SyncStatus.pendingOffline);

      // The local database is entirely unaffected — this is the read path.
      expect(await db.serviceRecordDao.getAllRecords(), hasLength(2));

      remote.offline = false;
      final okOnline = await runSync();

      expect(okOnline, isTrue);
      expect(remote.serviceRecords, hasLength(2));
      expect(remote.vehicles, hasLength(1));
      expect(await db.syncQueueDao.pending(), isEmpty);
      expect(sync.status, SyncStatus.idle);
    });

    test(
      'a failed push leaves the entry queued and counts the attempt',
      () async {
        remote.offline = true;
        await insertLocalRecord(id: 'record-1', at: _t0);

        await runSync();
        await runSync();

        final pending = await db.syncQueueDao.pending();
        expect(pending, isNotEmpty);
        expect(pending.first.attempts, greaterThanOrEqualTo(1));
      },
    );

    test('pulled rows are not queued straight back for pushing', () async {
      // The ping-pong bug: applying a pulled change through the DAOs would
      // enqueue it again, and two devices would bounce it forever.
      remote.seedRemote(
        'serviceRecord',
        remoteRecord(id: 'from-peer', updatedAt: _t1),
      );

      await runSync();

      expect(await db.syncQueueDao.pending(), isEmpty);
    });
  });

  group('conflicting edits on two devices', () {
    test('the later edit wins, whichever side it came from', () async {
      await insertLocalRecord(id: 'record-1', at: _t0, cost: 80);
      await runSync();

      // The peer edited the same record afterwards.
      remote.seedRemote(
        'serviceRecord',
        remoteRecord(id: 'record-1', updatedAt: _t2, cost: 120),
      );

      await runSync();

      final local = await db.serviceRecordDao.getRecord('record-1');
      expect(local?.cost, 120, reason: 'the newer remote edit wins');
      expect(local?.updatedAt.toUtc(), _t2);
    });

    test(
      'an unpushed local edit is not reverted by an older remote row',
      () async {
        // This is the case that makes naive "remote always wins" sync lose data.
        await insertLocalRecord(id: 'record-1', at: _t0, cost: 80);
        await runSync();

        // Offline, the user edits it. Meanwhile the remote still holds the old
        // copy — older than what is on this device.
        remote.offline = true;
        await db.serviceRecordDao.updateRecord(
          'record-1',
          ServiceRecordsCompanion(
            cost: const Value(200),
            updatedAt: Value(_t2),
          ),
        );
        remote.offline = false;

        await runSync();

        final local = await db.serviceRecordDao.getRecord('record-1');
        expect(
          local?.cost,
          200,
          reason: 'the local edit is newer and survives',
        );
        // And it reached the peer rather than being quietly dropped.
        expect(remote.serviceRecords['record-1']?['cost'], 200);
      },
    );

    test('an equal timestamp is left alone rather than churned', () async {
      await insertLocalRecord(id: 'record-1', at: _t1, cost: 80);
      await runSync();

      remote.seedRemote(
        'serviceRecord',
        remoteRecord(id: 'record-1', updatedAt: _t1, cost: 999),
      );

      await runSync();

      final local = await db.serviceRecordDao.getRecord('record-1');
      expect(local?.cost, 80, reason: 'not strictly newer, so not applied');
    });
  });

  group('a delete racing an edit', () {
    test('a delete propagates as a tombstone, not a disappearance', () async {
      await insertLocalRecord(id: 'record-1', at: _t0);
      await runSync();

      await db.serviceRecordDao.softDeleteRecord('record-1', _t1);
      await runSync();

      final pushed = remote.serviceRecords['record-1'];
      expect(pushed, isNotNull, reason: 'the row still exists remotely');
      expect(pushed?['deleted_at'], isNotNull);
    });

    test('a stale edit does not resurrect a deleted row', () async {
      // Device A deletes at t1. Device B, which never saw the delete, pushes
      // an edit it made at t0. The delete is newer and must hold.
      await insertLocalRecord(id: 'record-1', at: _t0);
      await runSync();

      await db.serviceRecordDao.softDeleteRecord('record-1', _t1);
      await runSync();

      remote.seedRemote(
        'serviceRecord',
        remoteRecord(id: 'record-1', updatedAt: _t0, cost: 55),
      );

      await runSync();

      final local = await db.serviceRecordDao.getRecord('record-1');
      expect(
        local,
        isNull,
        reason: 'getRecord filters tombstones — it must stay deleted',
      );
    });

    test(
      'a genuinely newer edit does undelete, since that is what LWW means',
      () async {
        await insertLocalRecord(id: 'record-1', at: _t0);
        await db.serviceRecordDao.softDeleteRecord('record-1', _t1);
        await runSync();

        // Someone edited it after the delete: under last-write-wins that is a
        // deliberate resurrection, not a stale push.
        remote.seedRemote(
          'serviceRecord',
          remoteRecord(id: 'record-1', updatedAt: _t2, cost: 70),
        );

        await runSync();

        final local = await db.serviceRecordDao.getRecord('record-1');
        expect(local?.cost, 70);
      },
    );

    test('deleting a vehicle propagates tombstones to its children', () async {
      await insertLocalRecord(id: 'record-1', at: _t0);
      await db.reminderRuleDao.insertRule(
        ReminderRulesCompanion.insert(
          id: 'rule-1',
          vehicleId: _vehicleId,
          type: ServiceType.oilChange.name,
          intervalMonths: const Value(6),
          createdAt: _t0,
          updatedAt: _t0,
        ),
      );
      await runSync();

      await db.vehicleDao.softDeleteVehicle(_vehicleId, _t1);
      await runSync();

      // A peer that only heard about the vehicle would keep showing its
      // history, so every child needs its own tombstone pushed.
      expect(remote.vehicles[_vehicleId]?['deleted_at'], isNotNull);
      expect(remote.serviceRecords['record-1']?['deleted_at'], isNotNull);
      expect(remote.reminderRules['rule-1']?['deleted_at'], isNotNull);
    });
  });

  group('pull bookkeeping', () {
    test('the high-water mark advances and limits the next fetch', () async {
      await runSync();

      // Compared as an instant: drift reads timestamps back in local time, so
      // the same moment is a different DateTime object. Every last-write-wins
      // comparison in the engine normalises to UTC for exactly this reason —
      // without it, sync would resolve conflicts differently per timezone.
      final mark = await db.syncQueueDao.lastPulledAt();
      expect(mark!.toUtc(), clockNow.toUtc());
      expect(mark.toUtc().isBefore(_t1), isTrue);
    });

    test('a new vehicle from a peer arrives before its children', () async {
      // Reversing the order would violate the local foreign key.
      remote.seedRemote('vehicle', {
        'id': 'peer-vehicle',
        'household_id': _householdId,
        'nickname': 'Peer Truck',
        'make': null,
        'model': null,
        'year': null,
        'plate': null,
        'odometer': 500,
        'odometer_unit': 'km',
        'odometer_updated_at': null,
        'created_at': _t0.toIso8601String(),
        'updated_at': _t1.toIso8601String(),
        'deleted_at': null,
      });
      remote.seedRemote('serviceRecord', {
        ...remoteRecord(id: 'peer-record', updatedAt: _t1),
        'vehicle_id': 'peer-vehicle',
      });

      await runSync();

      expect(await db.vehicleDao.getVehicle('peer-vehicle'), isNotNull);
      expect(await db.serviceRecordDao.getRecord('peer-record'), isNotNull);
    });
  });

  group('payload round trip', () {
    test('a row survives the trip out and back unchanged', () async {
      await insertLocalRecord(id: 'record-1', at: _t0, cost: 99.5);
      await runSync();

      final sent = remote.serviceRecords['record-1']!;
      final back = SyncPayloads.serviceRecordFromRemote(sent);

      expect(back.id.value, 'record-1');
      expect(back.cost.value, 99.5);
      expect(back.updatedAt.value, _t0);
    });
  });
}
