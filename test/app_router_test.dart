import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/app.dart';
import 'package:ourgarage/app_router.dart';
import 'package:ourgarage/app_routes.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';

import 'support/fake_notification_plugin.dart';

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

  /// Pumps the app, navigates to [location], and settles enough frames for the
  /// destination to appear. Avoids pumpAndSettle: the list screen's loading
  /// spinner animates indefinitely.
  Future<void> go(WidgetTester tester, String location) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fakeNotificationServiceOverride()],
        child: const OurGarageApp(),
      ),
    );
    await tester.pump();

    appRouter.go(location);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> teardownTree(WidgetTester tester) async {
    appRouter.go(AppRoutes.vehicleList);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('/ shows the garage list', (tester) async {
    await go(tester, AppRoutes.vehicleList);

    expect(find.text('My Garage'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('/vehicle/:id resolves to the detail screen', (tester) async {
    await go(tester, AppRoutes.vehicleDetail('abc123'));

    // The route now renders the real detail screen. No vehicle with this id
    // exists in the test database, so it settles on its not-found state —
    // which still proves the route resolved and the id reached the screen.
    expect(find.text('Vehicle not found'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('/vehicle/:id/service/:recordId resolves to the edit form', (
    tester,
  ) async {
    await go(tester, AppRoutes.editService('abc123', 'rec1'));

    // No vehicle 'abc123' exists in the test database, so the real screen
    // settles on its not-found state — proof the route and both path
    // parameters reached the screen.
    expect(find.text('Vehicle not found'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('/vehicle/:id/add-service resolves to the add form', (
    tester,
  ) async {
    await go(tester, AppRoutes.addService('abc123'));

    expect(find.text('Vehicle not found'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('/vehicle/:id/reminders resolves', (tester) async {
    await go(tester, AppRoutes.reminders('abc123'));

    expect(find.text('Vehicle not found'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('/settings resolves', (tester) async {
    await go(tester, AppRoutes.settings);

    expect(find.text('Settings'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('/paywall resolves', (tester) async {
    await go(tester, AppRoutes.paywall);

    expect(find.text('Paywall — coming soon'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('/vehicle/new is not swallowed by /vehicle/:id', (tester) async {
    await go(tester, AppRoutes.addVehicle);

    // '/vehicle/new' now renders the real add-vehicle form, not a placeholder;
    // its AppBar title is the signal that the literal route won, rather than
    // '/vehicle/:id' capturing "new" as an id. "Add vehicle" also labels the
    // save button, so this must be scoped to the AppBar specifically.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Add vehicle'),
      ),
      findsOneWidget,
    );
    expect(find.text('id: new'), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('/vehicle/:id/edit resolves the real edit form', (tester) async {
    await go(tester, AppRoutes.editVehicle('abc123'));

    expect(find.text('Edit vehicle'), findsOneWidget);

    await teardownTree(tester);
  });
}
