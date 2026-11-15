import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/sync/sync_payloads.dart';
import 'package:ourgarage/features/account/account_deletion_service.dart';
import 'package:ourgarage/features/household/household_service.dart';
import 'package:ourgarage/services/auth_service.dart';

import '../../support/fake_auth_backend.dart';
import '../../support/fake_household_backend.dart';

HouseholdMember member(String id, String role, int day) =>
    HouseholdMember(userId: id, role: role, joinedAt: DateTime(2026, 1, day));

void main() {
  late AppDatabase db;
  late FakeAuthBackend authBackend;
  late FakeHouseholdBackend householdBackend;
  late AccountDeletionService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Signed in as user-1, already in "existing-household".
    authBackend = FakeAuthBackend(alreadySignedIn: true)
      ..householdAlreadyExists = true;
    householdBackend = FakeHouseholdBackend();
    service = AccountDeletionService(
      auth: AuthService(authBackend),
      households: HouseholdService(householdBackend),
      db: db,
    );
  });

  tearDown(() async {
    await authBackend.dispose();
    await db.close();
  });

  group('impact', () {
    test('sole member', () async {
      householdBackend.members['existing-household'] = [
        member('user-1', 'owner', 1),
      ];
      expect(await service.impact(), isA<SoleMember>());
    });

    test('owner with others hands over', () async {
      householdBackend.members['existing-household'] = [
        member('user-1', 'owner', 1),
        member('user-2', 'member', 2),
        member('user-3', 'member', 3),
      ];
      final impact = await service.impact();
      expect(impact, isA<OwnerHandsOver>());
      expect((impact as OwnerHandsOver).otherMembers, 2);
    });

    test('plain member leaves', () async {
      householdBackend.members['existing-household'] = [
        member('user-0', 'owner', 1),
        member('user-1', 'member', 2),
      ];
      final impact = await service.impact();
      expect(impact, isA<LeavesHousehold>());
      expect((impact as LeavesHousehold).otherMembers, 1);
    });

    test('no household', () async {
      authBackend.householdAlreadyExists = false;
      expect(await service.impact(), isA<NoHousehold>());
    });
  });

  group('deleteAccount', () {
    Future<void> seedSharedState() async {
      await db
          .into(db.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: 'v1',
              nickname: 'Blue Civic',
              odometerUnit: 'mi',
              householdId: const Value('existing-household'),
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      await db.syncQueueDao.enqueue(
        entity: SyncEntity.vehicle,
        entityId: 'v1',
        operation: SyncOperation.upsert,
        payload: const {},
        now: DateTime(2026, 1, 1),
      );
      await db.syncQueueDao.setLastPulledAt(DateTime(2026, 1, 1));
      await db.householdEntitlementDao.cacheEntitlement(
        isPremium: true,
        householdId: 'existing-household',
      );
    }

    test('deletes on the server with the Apple code, then unlinks the device '
        'but keeps local data', () async {
      await seedSharedState();

      expect(await service.deleteAccount(), isTrue);

      expect(authBackend.deleteCalls, ['apple-auth-code-1']);
      expect(authBackend.currentUserId, isNull);

      final vehicles = await db.vehicleDao.getAllVehicles();
      expect(vehicles, hasLength(1), reason: 'local data stays');
      expect(vehicles.single.householdId, isNull);
      expect(await db.syncQueueDao.pending(), isEmpty);
      expect(await db.syncQueueDao.lastPulledAt(), isNull);
      expect(await db.householdEntitlementDao.isHouseholdPremium(), isFalse);
    });

    test('cancelling the Apple sheet changes nothing', () async {
      final cancelling = FakeAuthBackend(alreadySignedIn: true, cancels: true);
      addTearDown(cancelling.dispose);
      final cancelService = AccountDeletionService(
        auth: AuthService(cancelling),
        households: HouseholdService(householdBackend),
        db: db,
      );
      await seedSharedState();

      expect(await cancelService.deleteAccount(), isFalse);

      expect(cancelling.deleteCalls, isEmpty);
      expect(cancelling.currentUserId, 'user-1');
      final vehicle = (await db.vehicleDao.getAllVehicles()).single;
      expect(vehicle.householdId, 'existing-household');
      expect(await db.syncQueueDao.pending(), hasLength(1));
    });

    test('a dead session (already deleted, or revoked) signs out and unlinks '
        'the device instead of failing forever', () async {
      authBackend.sessionValid = false;
      await seedSharedState();

      await expectLater(
        service.deleteAccount(),
        throwsA(isA<SessionInvalidException>()),
      );

      expect(authBackend.appleCallCount, 0, reason: 'no Apple sheet');
      expect(authBackend.deleteCalls, isEmpty);
      expect(authBackend.currentUserId, isNull);
      final vehicle = (await db.vehicleDao.getAllVehicles()).single;
      expect(vehicle.householdId, isNull);
      expect(await db.syncQueueDao.pending(), isEmpty);
    });

    test('impact also checks the session first', () async {
      authBackend.sessionValid = false;
      await expectLater(
        service.impact(),
        throwsA(isA<SessionInvalidException>()),
      );
      expect(authBackend.currentUserId, isNull);
    });

    test('a server failure throws and leaves the device untouched', () async {
      authBackend.deleteError = const AuthException('boom');
      await seedSharedState();

      await expectLater(service.deleteAccount(), throwsA(isA<AuthException>()));

      expect(authBackend.currentUserId, 'user-1');
      final vehicle = (await db.vehicleDao.getAllVehicles()).single;
      expect(vehicle.householdId, 'existing-household');
      expect(await db.householdEntitlementDao.isHouseholdPremium(), isTrue);
    });
  });
}
