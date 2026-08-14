import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/sync/sync_service.dart';
import 'package:ourgarage/features/household/household_migration_service.dart';
import 'package:ourgarage/features/household/household_service.dart';
import 'package:ourgarage/features/household/join_household_service.dart';

import '../../support/fake_household_backend.dart';
import '../../support/fake_remote_garage.dart';

const _householdId = 'household-1';
const _userId = 'joiner-1';
final _t0 = DateTime.utc(2026, 6, 1, 12);

void main() {
  late AppDatabase db;
  late FakeHouseholdBackend backend;
  late FakeRemoteGarage remote;
  late JoinHouseholdService join;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = FakeHouseholdBackend();
    remote = FakeRemoteGarage();

    join = JoinHouseholdService(
      households: HouseholdService(backend),
      vehicleDao: db.vehicleDao,
      syncQueue: db.syncQueueDao,
      migration: HouseholdMigrationService(
        vehicleDao: db.vehicleDao,
        serviceRecordDao: db.serviceRecordDao,
        reminderRuleDao: db.reminderRuleDao,
        remote: remote,
      ),
      sync: SyncService(db: db, remote: remote),
    );
  });

  tearDown(() => db.close());

  Future<void> seedLocalVehicle(String id) async {
    await db.vehicleDao.insertVehicle(
      VehiclesCompanion.insert(
        id: id,
        nickname: 'Local $id',
        odometerUnit: 'mi',
        createdAt: _t0,
        updatedAt: _t0,
      ),
    );
    await db.serviceRecordDao.insertRecord(
      ServiceRecordsCompanion.insert(
        id: 'record-for-$id',
        vehicleId: id,
        performedAt: _t0,
        type: ServiceType.oilChange.name,
        createdAt: _t0,
        updatedAt: _t0,
      ),
    );
  }

  group('redeeming a code', () {
    test('a valid code joins the household', () async {
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');

      final outcome = await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.keepLocal,
      );

      expect(outcome.householdId, _householdId);
      expect(backend.members[_householdId], hasLength(1));
    });

    test('a hand-typed code is repaired before being sent', () async {
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');

      // Lowercase, spaced, and with an O typed for the Q.
      final outcome = await join.join(
        code: 'mk7 npo',
        userId: _userId,
        choice: LocalGarageChoice.keepLocal,
      );

      expect(outcome.householdId, _householdId);
    });

    test('an unknown code fails without a round trip', () async {
      await expectLater(
        join.join(
          code: 'ZZZZZZ',
          userId: _userId,
          choice: LocalGarageChoice.keepLocal,
        ),
        throwsA(
          isA<JoinException>().having(
            (e) => e.failure,
            'failure',
            JoinFailure.notFound,
          ),
        ),
      );
    });

    test('a malformed code is rejected before the network', () async {
      await expectLater(
        join.join(
          code: 'NOPE',
          userId: _userId,
          choice: LocalGarageChoice.keepLocal,
        ),
        throwsA(isA<JoinException>()),
      );
    });

    test('an expired code is refused', () async {
      backend.seedInvite(
        householdId: _householdId,
        code: 'MK7NPQ',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      await expectLater(
        join.join(
          code: 'MK7NPQ',
          userId: _userId,
          choice: LocalGarageChoice.keepLocal,
        ),
        throwsA(
          isA<JoinException>().having(
            (e) => e.failure,
            'failure',
            JoinFailure.expired,
          ),
        ),
      );
    });

    test('a code is single-use', () async {
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');

      await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.keepLocal,
      );

      await expectLater(
        join.join(
          code: 'MK7NPQ',
          userId: _userId,
          choice: LocalGarageChoice.keepLocal,
        ),
        throwsA(
          isA<JoinException>().having(
            (e) => e.failure,
            'failure',
            JoinFailure.alreadyUsed,
          ),
        ),
      );
    });
  });

  group('the joiner already has a local garage', () {
    test('reports how many vehicles are at stake', () async {
      await seedLocalVehicle('v1');
      await seedLocalVehicle('v2');

      expect(await join.unsharedVehicleCount(), 2);
    });

    test('choosing upload shares them with the household', () async {
      await seedLocalVehicle('v1');
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');

      final outcome = await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.upload,
      );

      expect(outcome.uploaded, isTrue);
      expect(outcome.localVehicleCount, 1);
      expect(remote.vehicles, hasLength(1));
      expect(remote.vehicles['v1']?['household_id'], _householdId);
      // History goes with the vehicle, not just the vehicle itself.
      expect(remote.serviceRecords, hasLength(1));
    });

    test('choosing keep-local uploads nothing and deletes nothing', () async {
      // The requirement that matters most: their data must survive whichever
      // way they answer.
      await seedLocalVehicle('v1');
      await seedLocalVehicle('v2');
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');

      final outcome = await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.keepLocal,
      );

      expect(outcome.uploaded, isFalse);
      expect(remote.vehicles, isEmpty);

      final local = await db.vehicleDao.getAllVehicles();
      expect(local, hasLength(2), reason: 'nothing may be discarded');
      expect(
        local.every((v) => v.householdId == null),
        isTrue,
        reason: 'they stay local-only, exactly as promised',
      );
      expect(await db.serviceRecordDao.getAllRecords(), hasLength(2));
    });

    test('keep-local survives the sync queue built before joining', () async {
      // Regression: the joiner's earlier local writes were already queued for
      // push. Joining then ran a sync, which uploaded them anyway — with a
      // null household_id — silently overriding the choice they had just made.
      await seedLocalVehicle('v1');
      expect(
        await db.syncQueueDao.pending(),
        isNotEmpty,
        reason: 'local writes queue before there is any household',
      );

      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');
      await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.keepLocal,
      );

      expect(remote.vehicles, isEmpty);
      expect(remote.serviceRecords, isEmpty);
    });

    test('upload is not undone by a stale queued push', () async {
      // The same bug from the other side: the queued row carried
      // household_id null and would overwrite the freshly uploaded one.
      await seedLocalVehicle('v1');
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');

      await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.upload,
      );

      expect(remote.vehicles['v1']?['household_id'], _householdId);
    });

    test('an empty local garage needs no decision', () async {
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');

      final outcome = await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.upload,
      );

      expect(outcome.localVehicleCount, 0);
      expect(outcome.uploaded, isFalse, reason: 'nothing to upload');
    });

    test('a failed join leaves the local garage untouched', () async {
      await seedLocalVehicle('v1');

      await expectLater(
        join.join(
          code: 'ZZZZZZ',
          userId: _userId,
          choice: LocalGarageChoice.upload,
        ),
        throwsA(isA<JoinException>()),
      );

      final local = await db.vehicleDao.getAllVehicles();
      expect(local, hasLength(1));
      expect(local.single.householdId, isNull);
      expect(remote.vehicles, isEmpty);
    });
  });

  group('after joining', () {
    test('a full pull brings down what the household already has', () async {
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');

      // Already in the household, put there by another member.
      remote.seedRemote('vehicle', {
        'id': 'their-vehicle',
        'household_id': _householdId,
        'nickname': 'Shared Estate',
        'make': null,
        'model': null,
        'year': null,
        'plate': null,
        'odometer': 42000,
        'odometer_unit': 'km',
        'odometer_updated_at': null,
        'created_at': _t0.toIso8601String(),
        'updated_at': _t0.toIso8601String(),
        'deleted_at': null,
      });

      await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.keepLocal,
      );

      final pulled = await db.vehicleDao.getVehicle('their-vehicle');
      expect(pulled, isNotNull, reason: 'a full pull runs after joining');
      expect(pulled?.nickname, 'Shared Estate');
    });

    test('uploading and pulling leave both garages present', () async {
      await seedLocalVehicle('mine');
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');
      remote.seedRemote('vehicle', {
        'id': 'theirs',
        'household_id': _householdId,
        'nickname': 'Shared Estate',
        'make': null,
        'model': null,
        'year': null,
        'plate': null,
        'odometer': 1,
        'odometer_unit': 'km',
        'odometer_updated_at': null,
        'created_at': _t0.toIso8601String(),
        'updated_at': _t0.toIso8601String(),
        'deleted_at': null,
      });

      await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.upload,
      );

      final local = await db.vehicleDao.getAllVehicles();
      expect(local.map((v) => v.id), containsAll(['mine', 'theirs']));
    });
  });

  group('owner side', () {
    test('createInvite issues a well-formed, unique code', () async {
      final households = HouseholdService(backend);

      final codes = <String>{};
      for (var i = 0; i < 20; i++) {
        codes.add(await households.createInvite(_householdId));
      }

      expect(codes, hasLength(20));
      expect(backend.codesIssued, hasLength(20));
    });

    test('a collision is retried rather than surfaced', () async {
      backend.failNextCreate = true;

      final code = await HouseholdService(backend).createInvite(_householdId);

      expect(code, isNotEmpty);
      expect(backend.codesIssued, hasLength(1));
    });

    test('revoking removes it from the pending list', () async {
      final households = HouseholdService(backend);
      final code = await households.createInvite(_householdId);

      final pending = await households.listInvites(_householdId);
      expect(pending.single.code, code);
      expect(pending.single.isPending, isTrue);

      await households.revokeInvite(pending.single.id);

      expect(await households.listInvites(_householdId), isEmpty);
      expect(backend.revokeInviteCount, 1);
    });

    test('removing a member does not touch the household vehicles', () async {
      // The data belongs to the garage, not the person who left.
      backend.seedInvite(householdId: _householdId, code: 'MK7NPQ');
      await seedLocalVehicle('v1');
      await join.join(
        code: 'MK7NPQ',
        userId: _userId,
        choice: LocalGarageChoice.upload,
      );

      await HouseholdService(
        backend,
      ).removeMember(householdId: _householdId, userId: _userId);

      expect(backend.members[_householdId], isEmpty);
      expect(remote.vehicles, hasLength(1), reason: 'vehicles stay');
      expect(remote.serviceRecords, hasLength(1));
    });
  });
}
