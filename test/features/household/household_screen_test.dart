import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/app_routes.dart';
import 'package:ourgarage/core/constants.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/household/household_migration_provider.dart';
import 'package:ourgarage/features/household/household_service.dart';
import 'package:ourgarage/features/household/invite_share.dart';
import 'package:ourgarage/features/household/widgets/household_screen.dart';

import '../../support/fake_auth_backend.dart';
import '../../support/fake_household_backend.dart';

const _household = 'existing-household';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseHolder.overrideWith(db);
  });

  tearDown(() async {
    DatabaseHolder.overrideWith(null);
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps the screen as [userId]. Returns what the share sheet was handed.
  Future<List<(String, Rect?)>> pump(
    WidgetTester tester, {
    required FakeHouseholdBackend households,
    String userId = 'owner-1',
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Unmount before the database closes, so nothing is left waiting on it.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });

    final auth = FakeAuthBackend(userId: userId, alreadySignedIn: true)
      ..householdAlreadyExists = true;
    final shared = <(String, Rect?)>[];

    final router = GoRouter(
      initialLocation: AppRoutes.household,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => const Scaffold(body: Text('Settings screen')),
        ),
        GoRoute(
          path: AppRoutes.household,
          builder: (_, _) => const HouseholdScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeAuthServiceOverride(auth),
          householdServiceProvider.overrideWith(
            (ref) => HouseholdService(households),
          ),
          inviteSharerProvider.overrideWithValue((text, origin) async {
            shared.add((text, origin));
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    return shared;
  }

  FakeHouseholdBackend seeded({String caller = 'owner-1'}) {
    return FakeHouseholdBackend(callerUserId: caller)
      ..members[_household] = [
        HouseholdMember(
          userId: 'owner-1',
          role: 'owner',
          joinedAt: DateTime(2026, 11, 1),
          displayName: 'Fatih',
        ),
        HouseholdMember(
          userId: 'member-1',
          role: 'member',
          joinedAt: DateTime(2026, 11, 2),
          displayName: 'Ayşe',
        ),
      ];
  }

  testWidgets('the owner sees named members and can invite', (tester) async {
    final households = seeded();
    final shared = await pump(tester, households: households);

    expect(find.text('Fatih (you)'), findsOneWidget);
    expect(find.text('Ayşe'), findsOneWidget);
    expect(find.byTooltip('Remove Ayşe'), findsOneWidget);
    expect(find.byTooltip('Remove Fatih'), findsNothing);

    await tester.tap(find.text('Invite someone'));
    await settle(tester);

    final code = households.codesIssued.single;
    expect(shared, hasLength(1));
    expect(shared.single.$1, contains(code));
    expect(shared.single.$1, contains(AppConstants.appStoreUrl));
    expect(shared.single.$1, contains('Join a household'));
    expect(shared.single.$2, isNotNull, reason: 'iPad needs an anchor');

    // The new code is listed as pending, and can be revoked.
    expect(find.text(code), findsOneWidget);
    await tester.tap(find.byTooltip('Revoke invite $code'));
    await settle(tester);
    expect(households.revokeInviteCount, 1);
    expect(find.text(code), findsNothing);
  });

  testWidgets('a pending invite can be shared again', (tester) async {
    final households = seeded()
      ..seedInvite(householdId: _household, code: 'MK7NPQ');
    final shared = await pump(tester, households: households);

    await tester.tap(find.text('MK7NPQ'));
    await settle(tester);

    expect(shared.single.$1, contains('MK7NPQ'));
    expect(households.codesIssued, isEmpty, reason: 'no new code minted');
  });

  testWidgets('expired and accepted invites are not listed', (tester) async {
    final households = seeded()
      ..seedInvite(
        householdId: _household,
        code: 'OLD234',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
    await pump(tester, households: households);
    expect(find.text('OLD234'), findsNothing);
    expect(find.text('Pending invites'), findsNothing);
  });

  testWidgets('removing a member asks first, then removes them', (
    tester,
  ) async {
    final households = seeded();
    await pump(tester, households: households);

    await tester.tap(find.byTooltip('Remove Ayşe'));
    await settle(tester);
    expect(find.text('Remove Ayşe?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(households.removeMemberCount, 0);

    await tester.tap(find.byTooltip('Remove Ayşe'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settle(tester);

    expect(households.removeMemberCount, 1);
    expect(find.text('Ayşe'), findsNothing);
  });

  testWidgets('a plain member sees the roster but no owner controls', (
    tester,
  ) async {
    await pump(
      tester,
      households: seeded(caller: 'member-1'),
      userId: 'member-1',
    );

    expect(find.text('Ayşe (you)'), findsOneWidget);
    expect(find.text('Fatih'), findsOneWidget);
    expect(find.text('Invite someone'), findsNothing);
    expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
    expect(find.text('Leave household'), findsOneWidget);
  });

  testWidgets('leaving as owner names the new owner, then unlinks the '
      'device and returns to settings', (tester) async {
    await db.vehicleDao.insertVehicle(
      VehiclesCompanion.insert(
        id: 'car-1',
        nickname: 'Civic',
        odometerUnit: 'km',
        householdId: const Value(_household),
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      ),
    );
    final households = seeded();
    await pump(tester, households: households);

    await tester.tap(find.text('Leave household'));
    await settle(tester);
    expect(find.textContaining('Ayşe will become the owner'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await settle(tester);

    expect(households.leftHouseholds, [_household]);
    expect(find.text('Settings screen'), findsOneWidget);
    expect(find.text('You’ve left the household'), findsOneWidget);

    final car = (await db.vehicleDao.getAllVehicles()).single;
    expect(car.householdId, isNull, reason: 'the local copy stays, unlinked');
  });

  testWidgets('the sole member is told the household will be deleted', (
    tester,
  ) async {
    final households = FakeHouseholdBackend(callerUserId: 'owner-1')
      ..members[_household] = [
        HouseholdMember(
          userId: 'owner-1',
          role: 'owner',
          joinedAt: DateTime(2026, 11, 1),
        ),
      ];
    await pump(tester, households: households);

    expect(find.text('Household member (you)'), findsOneWidget);
    await tester.tap(find.text('Leave household'));
    await settle(tester);
    expect(
      find.textContaining('the household and everything shared in it will '
          'be deleted'),
      findsOneWidget,
    );
  });

  testWidgets('a failed leave keeps the household and says why', (
    tester,
  ) async {
    final households = _FailingLeaveBackend()
      ..members[_household] = seeded().members[_household]!;
    await pump(tester, households: households);

    await tester.tap(find.text('Leave household'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await settle(tester);

    expect(find.textContaining('Could not reach OurGarage'), findsOneWidget);
    expect(find.text('Settings screen'), findsNothing);
  });
}

class _FailingLeaveBackend extends FakeHouseholdBackend {
  _FailingLeaveBackend() : super(callerUserId: 'owner-1');

  @override
  Future<LeaveOutcome> leaveHousehold(String householdId) async =>
      throw Exception('offline');
}
