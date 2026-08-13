import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/reminders/update_odometers_screen.dart';

import '../../support/fake_notification_plugin.dart';

Future<void> _pumpScreen(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/update-odometers',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('garage list')),
      ),
      GoRoute(
        path: '/update-odometers',
        builder: (_, _) => const UpdateOdometersScreen(),
      ),
      GoRoute(
        path: '/vehicle/:id/add-service',
        builder: (_, state) =>
            Scaffold(body: Text('add service ${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [fakeNotificationServiceOverride()],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
}

/// Finite pumps: loading states animate indefinitely, so pumpAndSettle hangs.
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The save chain does several real sqlite round trips; `runAsync` steps out
/// of fake time so they can actually resolve.
Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await _settle(tester);
}

Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
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

  Future<void> insertVehicle({
    required String id,
    required String nickname,
    int odometer = 10000,
    String unit = 'km',
  }) {
    return db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: id,
            nickname: nickname,
            odometer: Value(odometer),
            odometerUnit: unit,
            odometerUpdatedAt: Value(DateTime(2026, 1, 1)),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<void> insertDistanceRule({
    required String id,
    required String vehicleId,
    int intervalDistance = 8000,
    int? lastDoneOdometer,
  }) {
    return db
        .into(db.reminderRules)
        .insert(
          ReminderRulesCompanion.insert(
            id: id,
            vehicleId: vehicleId,
            type: ServiceType.oilChange.name,
            intervalDistance: Value(intervalDistance),
            lastDoneOdometer: Value(lastDoneOdometer),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  }

  testWidgets('lists every vehicle with one field each', (tester) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 10000);
    await insertVehicle(id: 'v2', nickname: 'Old Truck', odometer: 90000);
    await _pumpScreen(tester);

    // One pass over all vehicles, not a per-vehicle journey.
    expect(find.widgetWithText(TextFormField, 'Blue Civic'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Old Truck'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('prefills each field with the current reading', (tester) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 12345);
    await _pumpScreen(tester);

    expect(find.text('12345'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('saves every changed vehicle in one pass', (tester) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 10000);
    await insertVehicle(id: 'v2', nickname: 'Old Truck', odometer: 90000);
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Blue Civic'),
      '11000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Old Truck'),
      '95000',
    );
    await tester.pump();
    await _tapSave(tester);

    final vehicles = await db.select(db.vehicles).get();
    final byId = {for (final vehicle in vehicles) vehicle.id: vehicle};
    expect(byId['v1']!.odometer, 11000);
    expect(byId['v2']!.odometer, 95000);

    await _drainPendingTimers(tester);
  });

  testWidgets('leaves an untouched vehicle alone', (tester) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 10000);
    await insertVehicle(id: 'v2', nickname: 'Old Truck', odometer: 90000);
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Blue Civic'),
      '11000',
    );
    await tester.pump();
    await _tapSave(tester);

    final untouched = await (db.select(
      db.vehicles,
    )..where((v) => v.id.equals('v2'))).getSingle();
    expect(
      untouched.odometerUpdatedAt,
      DateTime(2026, 1, 1),
      reason: 'an unchanged field should not look freshly confirmed',
    );

    await _drainPendingTimers(tester);
  });

  testWidgets('rejects a reading lower than the current one', (tester) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 10000);
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Blue Civic'),
      '9000',
    );
    await tester.pump();

    expect(find.text('Cannot be lower than 10000'), findsOneWidget);

    await _tapSave(tester);

    final vehicle = await (db.select(
      db.vehicles,
    )..where((v) => v.id.equals('v1'))).getSingle();
    expect(vehicle.odometer, 10000, reason: 'the invalid save was blocked');

    await _drainPendingTimers(tester);
  });

  testWidgets('alerts about a rule the new reading made due', (tester) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 10000);
    // Due at 5000 + 8000 = 13000.
    await insertDistanceRule(id: 'r1', vehicleId: 'v1', lastDoneOdometer: 5000);
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Blue Civic'),
      '13500',
    );
    await tester.pump();
    await _tapSave(tester);

    expect(find.text('Blue Civic is due for an oil change'), findsOneWidget);
    expect(find.text('Log it now'), findsOneWidget);
    expect(find.text('Remind me later'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('"Log it now" goes to the service form for that vehicle', (
    tester,
  ) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 10000);
    await insertDistanceRule(id: 'r1', vehicleId: 'v1', lastDoneOdometer: 5000);
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Blue Civic'),
      '13500',
    );
    await tester.pump();
    await _tapSave(tester);

    await tester.tap(find.text('Log it now'));
    await _settle(tester);

    expect(find.text('add service v1'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('"Remind me later" returns to the garage', (tester) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 10000);
    await insertDistanceRule(id: 'r1', vehicleId: 'v1', lastDoneOdometer: 5000);
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Blue Civic'),
      '13500',
    );
    await tester.pump();
    await _tapSave(tester);

    await tester.tap(find.text('Remind me later'));
    await _settle(tester);

    expect(find.text('garage list'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('no alert when nothing came due', (tester) async {
    await insertVehicle(id: 'v1', nickname: 'Blue Civic', odometer: 10000);
    await insertDistanceRule(id: 'r1', vehicleId: 'v1', lastDoneOdometer: 5000);
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Blue Civic'),
      '10500',
    );
    await tester.pump();
    await _tapSave(tester);

    expect(find.text('Log it now'), findsNothing);
    expect(find.text('garage list'), findsOneWidget);

    await _drainPendingTimers(tester);
  });
}
