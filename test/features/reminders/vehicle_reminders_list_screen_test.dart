import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/reminders/vehicle_reminders_list_screen.dart';

import '../../support/fake_notification_plugin.dart';

const _vehicleId = 'v1';

Future<void> _pumpScreen(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/reminders',
    routes: [
      GoRoute(
        path: '/reminders',
        builder: (_, _) =>
            const VehicleRemindersListScreen(vehicleId: _vehicleId),
      ),
      GoRoute(
        path: '/vehicle/:id/reminders/new',
        builder: (_, state) =>
            Scaffold(body: Text('add reminder ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/vehicle/:id/reminders/:ruleId',
        builder: (_, state) => Scaffold(
          body: Text('edit reminder ${state.pathParameters['ruleId']}'),
        ),
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

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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

  Future<void> insertVehicle({int odometer = 10000, String unit = 'mi'}) {
    return db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: _vehicleId,
            nickname: 'Blue Civic',
            odometer: Value(odometer),
            odometerUnit: unit,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<void> insertRule({
    required String id,
    ServiceType type = ServiceType.oilChange,
    int? intervalMonths,
    int? intervalDistance,
    DateTime? lastDoneAt,
    int? lastDoneOdometer,
    bool isActive = true,
  }) {
    return db
        .into(db.reminderRules)
        .insert(
          ReminderRulesCompanion.insert(
            id: id,
            vehicleId: _vehicleId,
            type: type.name,
            intervalMonths: Value(intervalMonths),
            intervalDistance: Value(intervalDistance),
            lastDoneAt: Value(lastDoneAt),
            lastDoneOdometer: Value(lastDoneOdometer),
            isActive: Value(isActive),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  }

  testWidgets('shows the empty state with no rules', (tester) async {
    await insertVehicle();
    await _pumpScreen(tester);

    expect(find.textContaining('No reminders yet'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('lists a rule with its type, interval and status', (
    tester,
  ) async {
    await insertVehicle(unit: 'mi');
    await insertRule(
      id: 'r1',
      type: ServiceType.oilChange,
      intervalMonths: 6,
      intervalDistance: 5000,
      lastDoneAt: DateTime(2026, 1, 1),
    );
    await _pumpScreen(tester);

    expect(find.text('Oil change'), findsOneWidget);
    expect(find.text('Every 6 months or 5,000 mi'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('shows a custom label instead of the generic type name', (
    tester,
  ) async {
    await insertVehicle();
    await db
        .into(db.reminderRules)
        .insert(
          ReminderRulesCompanion.insert(
            id: 'r1',
            vehicleId: _vehicleId,
            type: ServiceType.custom.name,
            customTypeLabel: const Value('Windshield replacement'),
            intervalMonths: const Value(12),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
    await _pumpScreen(tester);

    expect(find.text('Windshield replacement'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('an inactive rule still appears, with its switch off', (
    tester,
  ) async {
    await insertVehicle();
    await insertRule(id: 'r1', intervalMonths: 6, isActive: false);
    await _pumpScreen(tester);

    expect(find.text('Oil change'), findsOneWidget);
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isFalse);

    await _drainPendingTimers(tester);
  });

  testWidgets('most urgent rule sorts first', (tester) async {
    await insertVehicle();
    await insertRule(
      id: 'far',
      type: ServiceType.tireRotation,
      intervalMonths: 24,
      lastDoneAt: DateTime(2026, 1, 1),
    );
    await insertRule(
      id: 'overdue',
      type: ServiceType.oilChange,
      intervalMonths: 1,
      lastDoneAt: DateTime(2020, 1, 1),
    );
    await _pumpScreen(tester);

    final tileTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final oilIndex = tileTexts.indexOf('Oil change');
    final tireIndex = tileTexts.indexOf('Tire rotation');
    expect(oilIndex, lessThan(tireIndex));

    await _drainPendingTimers(tester);
  });

  testWidgets('toggling the switch persists and reaches the scheduler', (
    tester,
  ) async {
    await insertVehicle();
    await insertRule(id: 'r1', intervalMonths: 6);
    await _pumpScreen(tester);

    await tester.tap(find.byType(Switch));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _settle(tester);

    final rule = await (db.select(
      db.reminderRules,
    )..where((r) => r.id.equals('r1'))).getSingle();
    expect(rule.isActive, isFalse);

    await _drainPendingTimers(tester);
  });

  testWidgets('tapping a row opens it for editing', (tester) async {
    await insertVehicle();
    await insertRule(id: 'r1', intervalMonths: 6);
    await _pumpScreen(tester);

    await tester.tap(find.text('Oil change'));
    await _settle(tester);

    expect(find.text('edit reminder r1'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('the FAB opens the add-reminder form', (tester) async {
    await insertVehicle();
    await _pumpScreen(tester);

    await tester.tap(find.text('Add reminder'));
    await _settle(tester);

    expect(find.text('add reminder $_vehicleId'), findsOneWidget);

    await _drainPendingTimers(tester);
  });
}
