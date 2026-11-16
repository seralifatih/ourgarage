import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/account/account_deletion_service.dart';
import 'package:ourgarage/features/household/household_service.dart';
import 'package:ourgarage/features/settings/settings_screen.dart';
import 'package:ourgarage/services/auth_service.dart';
import 'package:ourgarage/services/auth_service_provider.dart';

import '../../support/fake_auth_backend.dart';
import '../../support/fake_household_backend.dart';
import '../../support/fake_notification_plugin.dart';
import '../../support/fake_purchases_api.dart';

class OfflineHouseholdBackend extends FakeHouseholdBackend {
  @override
  Future<List<HouseholdMember>> listMembers(String householdId) async =>
      throw Exception('offline');
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
  }

  Future<void> pump(
    WidgetTester tester, {
    required FakeAuthBackend auth,
    FakeHouseholdBackend? households,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final householdBackend = households ?? FakeHouseholdBackend();
    householdBackend.members['existing-household'] ??= [
      HouseholdMember(
        userId: 'user-1',
        role: 'owner',
        joinedAt: DateTime(2026, 1, 1),
      ),
      HouseholdMember(
        userId: 'user-2',
        role: 'member',
        joinedAt: DateTime(2026, 1, 2),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeNotificationServiceOverride(null),
          fakePurchaseServiceOverride(null),
          fakeAuthServiceOverride(auth),
          accountDeletionServiceProvider.overrideWith(
            (ref) => AccountDeletionService(
              auth: AuthService(auth),
              households: HouseholdService(householdBackend),
              db: db,
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await flush(tester);
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('signed out: says data stays local, and offers no deletion', (
    tester,
  ) async {
    await pump(tester, auth: FakeAuthBackend());
    expect(
      find.text('Not signed in — data stays on this device'),
      findsOneWidget,
    );
    expect(find.text('Signed in with Apple'), findsNothing);
    expect(find.text('Delete account'), findsNothing);
    await drain(tester);
  });

  testWidgets('no Supabase in the build (auth stream errors): treated as '
      'not signed in', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeNotificationServiceOverride(null),
          fakePurchaseServiceOverride(null),
          currentUserIdProvider.overrideWith(
            (ref) => Stream<String?>.error(StateError('not configured')),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await flush(tester);

    expect(
      find.text('Not signed in — data stays on this device'),
      findsOneWidget,
    );
    expect(find.text('Delete account'), findsNothing);
    await drain(tester);
  });

  testWidgets('shown when signed in; the dialog explains the outcome and '
      'cancelling deletes nothing', (tester) async {
    final auth = FakeAuthBackend(alreadySignedIn: true)
      ..householdAlreadyExists = true;
    await pump(tester, auth: auth);

    expect(find.text('Signed in with Apple'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    await tester.tap(find.text('Delete account'));
    await flush(tester);

    expect(find.text('Delete your account?'), findsOneWidget);
    expect(
      find.textContaining('handed to the member who joined first'),
      findsOneWidget,
    );
    expect(find.textContaining('1 other member'), findsOneWidget);
    expect(
      find.textContaining('Everything on this iPhone stays'),
      findsOneWidget,
    );
    expect(
      find.textContaining('does not cancel an App Store subscription'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await flush(tester);

    expect(auth.deleteCalls, isEmpty);
    expect(auth.currentUserId, 'user-1');
    await drain(tester);
  });

  testWidgets('confirming deletes, signs out and hides the row', (
    tester,
  ) async {
    final auth = FakeAuthBackend(alreadySignedIn: true)
      ..householdAlreadyExists = true;
    await pump(tester, auth: auth);

    await tester.tap(find.text('Delete account'));
    await flush(tester);
    // The dialog's destructive button shares the row's label.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete account'),
      ),
    );
    await flush(tester);

    expect(auth.deleteCalls, hasLength(1));
    expect(auth.currentUserId, isNull);
    expect(
      find.text(
        'Your account was deleted. Everything on this iPhone is still here.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'Delete account'), findsNothing);
    expect(
      find.text('Not signed in — data stays on this device'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('a server failure shows an error and keeps the account', (
    tester,
  ) async {
    final auth = FakeAuthBackend(alreadySignedIn: true)
      ..householdAlreadyExists = true
      ..deleteError = const AuthException('500');
    await pump(tester, auth: auth);

    await tester.tap(find.text('Delete account'));
    await flush(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete account'),
      ),
    );
    await flush(tester);

    expect(
      find.text(
        'Could not delete your account. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(auth.currentUserId, 'user-1');
    await drain(tester);
  });

  testWidgets('a dead session signs out and explains, without the dialog', (
    tester,
  ) async {
    final auth = FakeAuthBackend(alreadySignedIn: true)
      ..householdAlreadyExists = true
      ..sessionValid = false;
    await pump(tester, auth: auth);

    await tester.tap(find.text('Delete account'));
    await flush(tester);

    expect(find.text('Delete your account?'), findsNothing);
    expect(find.textContaining("You've been signed out"), findsOneWidget);
    expect(auth.currentUserId, isNull);
    expect(find.widgetWithText(ListTile, 'Delete account'), findsNothing);
    await drain(tester);
  });

  testWidgets('offline before the dialog: explains instead of guessing', (
    tester,
  ) async {
    final auth = FakeAuthBackend(alreadySignedIn: true)
      ..householdAlreadyExists = true;
    await pump(tester, auth: auth, households: OfflineHouseholdBackend());

    await tester.tap(find.text('Delete account'));
    await flush(tester);

    expect(find.text('Delete your account?'), findsNothing);
    expect(
      find.text(
        'Could not reach OurGarage. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    await drain(tester);
  });
}
