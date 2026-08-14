import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/features/household/household_migration_service.dart';
import 'package:ourgarage/services/remote_garage.dart';

import '../../support/fake_remote_garage.dart';

/// Integration test for the one-time upload.
///
/// The local half is a real Drift database on real sqlite — the same code path
/// the app uses. The remote half is [FakeRemoteGarage], which enforces the
/// foreign key and keys rows by id, so upload-ordering and idempotence bugs
/// still surface. It cannot catch anything that depends on Postgres itself
/// (RLS, constraints, type coercion); `supabase/tests/` covers that side.
const _householdId = 'household-1';
const _userId = 'user-1';

const _vehicleCount = 3;
const _serviceRecordCount = 20;
const _reminderRuleCount = 6;

void main() {
  late AppDatabase db;
  late FakeRemoteGarage remote;
  late HouseholdMigrationService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = FakeRemoteGarage();
    service = HouseholdMigrationService(
      vehicleDao: db.vehicleDao,
      serviceRecordDao: db.serviceRecordDao,
      reminderRuleDao: db.reminderRuleDao,
      remote: remote,
    );
    await _seed(db);
  });

  tearDown(() => db.close());

  group('a full upload', () {
    test('uploads exactly the seeded rows', () async {
      final result = await service.migrate(
        householdId: _householdId,
        userId: _userId,
      );

      expect(remote.vehicles, hasLength(_vehicleCount));
      expect(remote.serviceRecords, hasLength(_serviceRecordCount));
      expect(remote.reminderRules, hasLength(_reminderRuleCount));

      expect(result.vehicles, _vehicleCount);
      expect(result.serviceRecords, _serviceRecordCount);
      expect(result.reminderRules, _reminderRuleCount);
    });

    test('reuses the local uuids, so nothing needs remapping', () async {
      final localVehicleIds = (await db.vehicleDao.getAllVehicles())
          .map((v) => v.id)
          .toSet();
      final localRecordIds = (await db.serviceRecordDao.getAllRecords())
          .map((r) => r.id)
          .toSet();

      await service.migrate(householdId: _householdId, userId: _userId);

      expect(remote.vehicles.keys.toSet(), localVehicleIds);
      expect(remote.serviceRecords.keys.toSet(), localRecordIds);
    });

    test('stamps household_id and created_by on every row', () async {
      await service.migrate(householdId: _householdId, userId: _userId);

      for (final vehicle in remote.vehicles.values) {
        expect(vehicle['household_id'], _householdId);
        expect(vehicle['created_by'], _userId);
      }
      // Children carry no household_id of their own; they inherit it through
      // vehicle_id, exactly as the RLS policies resolve it.
      for (final record in remote.serviceRecords.values) {
        expect(record['created_by'], _userId);
        expect(remote.vehicles, contains(record['vehicle_id']));
      }
      for (final rule in remote.reminderRules.values) {
        expect(rule['created_by'], _userId);
        expect(remote.vehicles, contains(rule['vehicle_id']));
      }
    });

    test('mirrors household_id back into the local vehicles', () async {
      await service.migrate(householdId: _householdId, userId: _userId);

      final local = await db.vehicleDao.getAllVehicles();
      expect(local, hasLength(_vehicleCount));
      expect(
        local.every((v) => v.householdId == _householdId),
        isTrue,
        reason: 'the local database must know it is synced',
      );
    });

    test('preserves the field values, not just the row count', () async {
      final vehicle = (await db.vehicleDao.getAllVehicles()).first;

      await service.migrate(householdId: _householdId, userId: _userId);

      final uploaded = remote.vehicles[vehicle.id]!;
      expect(uploaded['nickname'], vehicle.nickname);
      expect(uploaded['odometer'], vehicle.odometer);
      expect(uploaded['odometer_unit'], vehicle.odometerUnit);
      // Timestamps go up as ISO-8601 UTC for Postgres timestamptz.
      expect(
        uploaded['created_at'],
        vehicle.createdAt.toUtc().toIso8601String(),
      );
    });

    test('an inactive reminder rule still goes up', () async {
      // A switched-off rule is still the user's data.
      await service.migrate(householdId: _householdId, userId: _userId);

      expect(
        remote.reminderRules.values.where((r) => r['is_active'] == false),
        isNotEmpty,
      );
    });
  });

  group('idempotence', () {
    test('re-running upserts rather than duplicating', () async {
      await service.migrate(householdId: _householdId, userId: _userId);
      await service.migrate(householdId: _householdId, userId: _userId);
      await service.migrate(householdId: _householdId, userId: _userId);

      expect(remote.vehicles, hasLength(_vehicleCount));
      expect(remote.serviceRecords, hasLength(_serviceRecordCount));
      expect(remote.reminderRules, hasLength(_reminderRuleCount));
    });

    test('a retry after a crash converges on the same rows', () async {
      // First attempt dies partway through the history upload.
      remote.failOn = 'upsertServiceRecords';
      await expectLater(
        service.migrate(householdId: _householdId, userId: _userId),
        throwsA(isA<MigrationFailure>()),
      );

      await service.migrate(householdId: _householdId, userId: _userId);

      expect(remote.vehicles, hasLength(_vehicleCount));
      expect(remote.serviceRecords, hasLength(_serviceRecordCount));
      expect(remote.reminderRules, hasLength(_reminderRuleCount));
    });
  });

  group('failure and rollback', () {
    test('a failed history upload removes the vehicles already sent', () async {
      remote.failOn = 'upsertServiceRecords';

      await expectLater(
        service.migrate(householdId: _householdId, userId: _userId),
        throwsA(isA<MigrationFailure>()),
      );

      expect(
        remote.isEmpty,
        isTrue,
        reason: 'a half-migrated garage is the thing this must never leave',
      );
      expect(remote.deleteHouseholdDataCount, 1);
    });

    test('a failed reminder upload rolls back vehicles and history', () async {
      remote.failOn = 'upsertReminderRules';

      await expectLater(
        service.migrate(householdId: _householdId, userId: _userId),
        throwsA(isA<MigrationFailure>()),
      );

      expect(remote.isEmpty, isTrue);
    });

    test('local data is untouched by a failed upload', () async {
      remote.failOn = 'upsertServiceRecords';

      await expectLater(
        service.migrate(householdId: _householdId, userId: _userId),
        throwsA(isA<MigrationFailure>()),
      );

      final vehicles = await db.vehicleDao.getAllVehicles();
      expect(vehicles, hasLength(_vehicleCount));
      expect(
        vehicles.every((v) => v.householdId == null),
        isTrue,
        reason: 'nothing may claim to be synced after a failure',
      );
      expect(
        await db.serviceRecordDao.getAllRecords(),
        hasLength(_serviceRecordCount),
      );
      expect(
        await db.reminderRuleDao.getAllRules(),
        hasLength(_reminderRuleCount),
      );
    });

    test(
      'a failed rollback is reported as such, local data still safe',
      () async {
        remote.failOn = 'upsertServiceRecords';
        // The compensating delete fails too — the worst case.
        final failingRemote = _RollbackAlsoFails(remote);
        final failingService = HouseholdMigrationService(
          vehicleDao: db.vehicleDao,
          serviceRecordDao: db.serviceRecordDao,
          reminderRuleDao: db.reminderRuleDao,
          remote: failingRemote,
        );

        await expectLater(
          failingService.migrate(householdId: _householdId, userId: _userId),
          throwsA(
            isA<MigrationFailure>().having(
              (f) => f.rollbackFailed,
              'rollbackFailed',
              isTrue,
            ),
          ),
        );

        final vehicles = await db.vehicleDao.getAllVehicles();
        expect(vehicles.every((v) => v.householdId == null), isTrue);
      },
    );
  });

  group('edge cases', () {
    test('an empty garage succeeds and uploads nothing', () async {
      // Emptied rather than built from a second AppDatabase: two instances on
      // one executor is what drift warns about, and the warning is worth not
      // teaching people to ignore. Children first, for the foreign key.
      await db.delete(db.serviceRecords).go();
      await db.delete(db.reminderRules).go();
      await db.delete(db.vehicles).go();

      final result = await service.migrate(
        householdId: _householdId,
        userId: _userId,
      );

      expect(result.isEmpty, isTrue);
      expect(remote.isEmpty, isTrue);
    });

    test('soft-deleted rows are left behind', () async {
      // Nothing else has this garage yet, so there is no peer that needs to
      // learn about a deletion — tombstones would be noise in a fresh cloud.
      await db.vehicleDao.softDeleteVehicle('vehicle-0', DateTime(2026, 5, 1));

      await service.migrate(householdId: _householdId, userId: _userId);

      expect(remote.vehicles, hasLength(_vehicleCount - 1));
      expect(remote.vehicles.containsKey('vehicle-0'), isFalse);
      // Its children were cascaded locally, so they must not be up there
      // orphaned either.
      expect(
        remote.serviceRecords.values.every(
          (r) => r['vehicle_id'] != 'vehicle-0',
        ),
        isTrue,
      );
    });

    test('progress is reported and ends complete', () async {
      final seen = <MigrationProgress>[];

      await service.migrate(
        householdId: _householdId,
        userId: _userId,
        onProgress: seen.add,
      );

      expect(seen.map((p) => p.phase), contains(MigrationPhase.done));
      expect(seen.last.uploaded, seen.last.total);
      expect(
        seen.last.total,
        _vehicleCount + _serviceRecordCount + _reminderRuleCount,
      );
    });
  });
}

/// Wraps a [FakeRemoteGarage] so the compensating delete fails too.
class _RollbackAlsoFails implements RemoteGarage {
  _RollbackAlsoFails(this._inner);

  final FakeRemoteGarage _inner;

  @override
  Future<void> upsertVehicles(List<Map<String, dynamic>> rows) =>
      _inner.upsertVehicles(rows);

  @override
  Future<void> upsertServiceRecords(List<Map<String, dynamic>> rows) =>
      _inner.upsertServiceRecords(rows);

  @override
  Future<void> upsertReminderRules(List<Map<String, dynamic>> rows) =>
      _inner.upsertReminderRules(rows);

  @override
  Future<List<Map<String, dynamic>>> fetchChangedSince({
    required String householdId,
    required DateTime? since,
  }) => _inner.fetchChangedSince(householdId: householdId, since: since);

  @override
  Future<void> deleteHouseholdData(String householdId) async {
    throw StateError('Rollback failed');
  }
}

/// Seeds 3 vehicles, 20 service records and 6 reminder rules.
Future<void> _seed(AppDatabase db) async {
  final created = DateTime(2026, 1, 1);

  for (var v = 0; v < _vehicleCount; v++) {
    await db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'vehicle-$v',
            nickname: 'Vehicle $v',
            odometerUnit: v.isEven ? 'mi' : 'km',
            odometer: Value(10000 + v * 1000),
            make: Value('Make $v'),
            createdAt: created,
            updatedAt: created,
          ),
        );
  }

  // Spread unevenly across the vehicles, so a bug that only works for a clean
  // split would still be caught.
  for (var r = 0; r < _serviceRecordCount; r++) {
    await db
        .into(db.serviceRecords)
        .insert(
          ServiceRecordsCompanion.insert(
            id: 'record-$r',
            vehicleId: 'vehicle-${r % _vehicleCount}',
            performedAt: created.add(Duration(days: r)),
            type: ServiceType.oilChange.name,
            odometer: Value(10000 + r * 100),
            cost: Value(50.0 + r),
            currency: const Value('USD'),
            createdAt: created,
            updatedAt: created,
          ),
        );
  }

  for (var r = 0; r < _reminderRuleCount; r++) {
    await db
        .into(db.reminderRules)
        .insert(
          ReminderRulesCompanion.insert(
            id: 'rule-$r',
            vehicleId: 'vehicle-${r % _vehicleCount}',
            type: ServiceType.values[r % ServiceType.values.length].name,
            intervalMonths: Value(6 + r),
            // One inactive rule, to prove they still migrate.
            isActive: Value(r != 0),
            createdAt: created,
            updatedAt: created,
          ),
        );
  }
}
