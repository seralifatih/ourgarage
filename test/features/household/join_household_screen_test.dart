import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/household/household_migration_provider.dart';
import 'package:ourgarage/features/household/household_service.dart';
import 'package:ourgarage/features/household/widgets/join_household_screen.dart';

import '../../support/fake_auth_backend.dart';
import '../../support/fake_household_backend.dart';
import '../../support/fake_remote_garage.dart';

const _householdId = 'household-1';

/// Pumps the screen behind a real router, so `context.go` on success can be
/// asserted on and there's somewhere for it to land.
Future<void> _pumpScreen(
  WidgetTester tester, {
  FakeAuthBackend? auth,
  FakeHouseholdBackend? household,
  FakeRemoteGarage? remote,
}) async {
  final router = GoRouter(
    initialLocation: '/join',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('vehicle list')),
      ),
      GoRoute(
        path: '/join',
        builder: (_, _) => const JoinHouseholdScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeAuthServiceOverride(auth),
        householdServiceProvider.overrideWith(
          (ref) => HouseholdService(household ?? FakeHouseholdBackend()),
        ),
        fakeRemoteGarageOverride(remote ?? FakeRemoteGarage()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

/// A [FakeAuthBackend] already signed in, for tests about join outcomes
/// rather than about the sign-in step itself — otherwise every one of them
/// would first have to fight through the account explainer sheet.
Future<FakeAuthBackend> _signedInAuth() async {
  final auth = FakeAuthBackend();
  await auth.signInWithAppleIdToken(idToken: 't', rawNonce: 'n');
  return auth;
}

/// Types into the code field and lets the async submit round-trip resolve
/// outside fake time — the same pattern used by every other Supabase-backed
/// screen test in this suite.
Future<void> _enterCodeAndJoin(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await _settle(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Join'));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await _settle(tester);
}

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

  Future<void> seedLocalVehicle(String id) {
    return db.vehicleDao.insertVehicle(
      VehiclesCompanion.insert(
        id: id,
        nickname: 'Local $id',
        odometerUnit: 'mi',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  }

  group('the code field', () {
    testWidgets('Join is disabled until 6 well-formed characters are entered', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join')).onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'MK7NP');
      await _settle(tester);
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join')).onPressed,
        isNull,
        reason: 'only five characters',
      );

      await tester.enterText(find.byType(TextField), 'MK7NPQ');
      await _settle(tester);
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join')).onPressed,
        isNotNull,
      );

      await _drainPendingTimers(tester);
    });

    testWidgets('typing is uppercased and repairs lookalike characters live', (
      tester,
    ) async {
      await _pumpScreen(tester);

      // Lowercase, and an O where the real code has a Q — same repair
      // InviteCode.normalise applies on submit, just visible as you type.
      await tester.enterText(find.byType(TextField), 'mk7npo');
      await _settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'MK7NPQ');

      await _drainPendingTimers(tester);
    });

    testWidgets('input is capped at six characters', (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'ABCDEFGHIJ');
      await _settle(tester);

      // find.text alone would also match the "ABCDEF" hint text if the entry
      // happened to equal it; asserting through the field's own value avoids
      // that ambiguity regardless of what the hint says.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'ABCDEF');

      await _drainPendingTimers(tester);
    });
  });

  group('bad code', () {
    testWidgets('an unknown code surfaces a specific message and stays put', (
      tester,
    ) async {
      final household = FakeHouseholdBackend();
      await _pumpScreen(
        tester,
        auth: await _signedInAuth(),
        household: household,
      );

      await _enterCodeAndJoin(tester, 'ZZZZZZ');

      expect(
        find.text('That code doesn’t match any invite.'),
        findsOneWidget,
      );
      expect(find.text('vehicle list'), findsNothing, reason: 'did not navigate');

      await _drainPendingTimers(tester);
    });
  });

  group('expired code', () {
    testWidgets('an expired code surfaces a specific message', (tester) async {
      final household = FakeHouseholdBackend()
        ..seedInvite(
          householdId: _householdId,
          code: 'MK7NPQ',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        );
      await _pumpScreen(
        tester,
        auth: await _signedInAuth(),
        household: household,
      );

      await _enterCodeAndJoin(tester, 'MK7NPQ');

      expect(
        find.text('That invite has expired. Ask for a new one.'),
        findsOneWidget,
      );

      await _drainPendingTimers(tester);
    });
  });

  group('already-accepted code', () {
    testWidgets('a single-use code that was already redeemed is refused', (
      tester,
    ) async {
      final household = FakeHouseholdBackend()
        ..seedInvite(householdId: _householdId, code: 'MK7NPQ');
      // Consumed by someone else before this attempt.
      await household.acceptInvite('MK7NPQ');

      await _pumpScreen(
        tester,
        auth: await _signedInAuth(),
        household: household,
      );

      await _enterCodeAndJoin(tester, 'MK7NPQ');

      expect(
        find.text('That invite has already been used.'),
        findsOneWidget,
      );

      await _drainPendingTimers(tester);
    });
  });

  group('network failure', () {
    testWidgets('a network error is shown and the field stays usable', (
      tester,
    ) async {
      final household = _ThrowingHouseholdBackend();
      await _pumpScreen(
        tester,
        auth: await _signedInAuth(),
        household: household,
      );

      await _enterCodeAndJoin(tester, 'MK7NPQ');

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      // Not stuck: the button is enabled again for a retry.
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join')).onPressed,
        isNotNull,
      );

      await _drainPendingTimers(tester);
    });
  });

  group('success with no local data', () {
    testWidgets('joins directly, no upload dialog, and navigates away', (
      tester,
    ) async {
      final household = FakeHouseholdBackend()
        ..seedInvite(householdId: _householdId, code: 'MK7NPQ');
      final auth = FakeAuthBackend();
      await auth.signInWithAppleIdToken(idToken: 't', rawNonce: 'n');

      await _pumpScreen(tester, auth: auth, household: household);

      await _enterCodeAndJoin(tester, 'MK7NPQ');

      expect(
        find.textContaining('You’ve joined the household'),
        findsOneWidget,
      );
      expect(
        find.text('You already have'),
        findsNothing,
        reason: 'nothing to decide with an empty garage',
      );
      expect(find.text('vehicle list'), findsOneWidget);
      expect(household.members[_householdId], hasLength(1));

      await _drainPendingTimers(tester);
    });

    testWidgets('signs in first when there is no session yet', (
      tester,
    ) async {
      final household = FakeHouseholdBackend()
        ..seedInvite(householdId: _householdId, code: 'MK7NPQ');
      final auth = FakeAuthBackend();
      await _pumpScreen(tester, auth: auth, household: household);

      await tester.enterText(find.byType(TextField), 'MK7NPQ');
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await _settle(tester);

      // The explainer sheet, not the household screen's own copy.
      expect(find.text('Join a household'), findsWidgets);
      expect(
        find.textContaining('Joining needs an account'),
        findsOneWidget,
      );

      await tester.tap(find.text('Continue with Apple'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _settle(tester);

      expect(auth.appleCallCount, 1);
      expect(household.members[_householdId], hasLength(1));

      await _drainPendingTimers(tester);
    });

  });

  group('success with existing local data', () {
    testWidgets('choosing to share uploads the local garage', (tester) async {
      final household = FakeHouseholdBackend()
        ..seedInvite(householdId: _householdId, code: 'MK7NPQ');
      final auth = FakeAuthBackend();
      await auth.signInWithAppleIdToken(idToken: 't', rawNonce: 'n');
      await seedLocalVehicle('v1');
      final remote = FakeRemoteGarage();

      await _pumpScreen(
        tester,
        auth: auth,
        household: household,
        remote: remote,
      );

      await tester.enterText(find.byType(TextField), 'MK7NPQ');
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _settle(tester);

      // The choice dialog, not yet resolved.
      expect(find.text('You already have 1 vehicle'), findsOneWidget);

      await tester.tap(find.text('Share with household'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _settle(tester);

      expect(
        find.textContaining('1 vehicle shared'),
        findsOneWidget,
      );
      expect(remote.vehicles, hasLength(1));
      expect(remote.vehicles['v1']?['household_id'], _householdId);

      final local = await db.vehicleDao.getVehicle('v1');
      expect(local?.householdId, _householdId);

      await _drainPendingTimers(tester);
    });

    testWidgets(
      'choosing to keep local uploads nothing and deletes nothing',
      (tester) async {
        final household = FakeHouseholdBackend()
          ..seedInvite(householdId: _householdId, code: 'MK7NPQ');
        final auth = FakeAuthBackend();
        await auth.signInWithAppleIdToken(idToken: 't', rawNonce: 'n');
        await seedLocalVehicle('v1');
        await seedLocalVehicle('v2');
        final remote = FakeRemoteGarage();

        await _pumpScreen(
          tester,
          auth: auth,
          household: household,
          remote: remote,
        );

        await tester.enterText(find.byType(TextField), 'MK7NPQ');
        await _settle(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Join'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await _settle(tester);

        expect(find.text('You already have 2 vehicles'), findsOneWidget);

        await tester.tap(find.text('Keep local only'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await _settle(tester);

        expect(find.text('You’ve joined the household'), findsOneWidget);
        expect(remote.vehicles, isEmpty, reason: 'nothing was uploaded');

        final local = await db.vehicleDao.getAllVehicles();
        expect(local, hasLength(2), reason: 'nothing was deleted');
        expect(
          local.every((v) => v.householdId == null),
          isTrue,
          reason: 'they stay local-only, exactly as promised',
        );

        await _drainPendingTimers(tester);
      },
    );

    testWidgets(
      'dismissing the choice dialog leaves the join unfinished',
      (tester) async {
        final household = FakeHouseholdBackend()
          ..seedInvite(householdId: _householdId, code: 'MK7NPQ');
        final auth = FakeAuthBackend();
        await auth.signInWithAppleIdToken(idToken: 't', rawNonce: 'n');
        await seedLocalVehicle('v1');

        await _pumpScreen(tester, auth: auth, household: household);

        await tester.enterText(find.byType(TextField), 'MK7NPQ');
        await _settle(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Join'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await _settle(tester);

        expect(find.text('You already have 1 vehicle'), findsOneWidget);

        // Back button / barrier: the dialog is not dismissible, but the join
        // must still not have happened while it's up.
        expect(household.members[_householdId], isNull);

        await _drainPendingTimers(tester);
      },
    );
  });
}

/// A [HouseholdBackend] whose every call fails, for the network-error case.
class _ThrowingHouseholdBackend extends FakeHouseholdBackend {
  @override
  Future<String> acceptInvite(String code) async {
    throw StateError('Connection refused');
  }
}
