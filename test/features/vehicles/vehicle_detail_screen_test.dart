import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/data/repositories/premium_status_provider.dart';
import 'package:ourgarage/features/vehicles/vehicle_detail_screen.dart';

import '../../support/fake_auth_backend.dart';

const _vehicleId = 'v1';

/// Pumps the detail screen behind a real router, so `context.push`/`go` work
/// and pushed destinations can be asserted on.
Future<void> _pumpDetail(
  WidgetTester tester, {
  bool premium = false,
  FakeAuthBackend? auth,
}) async {
  final router = GoRouter(
    initialLocation: '/vehicle/$_vehicleId',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('garage list')),
      ),
      GoRoute(
        path: '/paywall',
        builder: (_, _) => const Scaffold(body: Text('paywall')),
      ),
      GoRoute(
        path: '/vehicle/:id',
        builder: (_, state) =>
            VehicleDetailScreen(vehicleId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, _) => const Scaffold(body: Text('edit vehicle')),
          ),
          GoRoute(
            path: 'add-service',
            builder: (_, _) => const Scaffold(body: Text('add service')),
          ),
          GoRoute(
            path: 'service/:recordId',
            builder: (_, state) => Scaffold(
              body: Text('edit service ${state.pathParameters['recordId']}'),
            ),
          ),
          GoRoute(
            path: 'reminders',
            builder: (_, _) => const Scaffold(body: Text('manage reminders')),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        premiumStatusProvider.overrideWith((ref) => premium),
        fakeAuthServiceOverride(auth),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
}

/// Finite pumps: the loading states use an indefinite progress indicator, so
/// pumpAndSettle would never return.
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

  Future<void> insertVehicle({
    String? make,
    String? model,
    int? year,
    int odometer = 12500,
    String unit = 'km',
  }) async {
    await db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: _vehicleId,
            nickname: 'Blue Civic',
            make: Value(make),
            model: Value(model),
            year: Value(year),
            odometer: Value(odometer),
            odometerUnit: unit,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<void> insertRecord({
    required String id,
    required DateTime performedAt,
    ServiceType type = ServiceType.oilChange,
    int? odometer,
    double? cost,
    String? currency,
  }) async {
    await db
        .into(db.serviceRecords)
        .insert(
          ServiceRecordsCompanion.insert(
            id: id,
            vehicleId: _vehicleId,
            performedAt: performedAt,
            type: type.name,
            odometer: Value(odometer),
            cost: Value(cost),
            currency: Value(currency),
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
  }) async {
    await db
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

  group('header', () {
    testWidgets('shows nickname, description and odometer', (tester) async {
      await insertVehicle(make: 'Honda', model: 'Civic', year: 2019);
      await _pumpDetail(tester);

      expect(find.text('Honda Civic 2019'), findsOneWidget);
      expect(find.text('12,500'), findsOneWidget);
      expect(find.text('km'), findsOneWidget);
      // Nickname appears in the AppBar and the header.
      expect(find.text('Blue Civic'), findsWidgets);

      await _drainPendingTimers(tester);
    });

    testWidgets('omits the description line when make/model/year are unset', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpDetail(tester);

      expect(find.textContaining('null'), findsNothing);

      await _drainPendingTimers(tester);
    });

    testWidgets('Update opens the odometer sheet and saves a new reading', (
      tester,
    ) async {
      await insertVehicle(odometer: 12500);
      await _pumpDetail(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Update'));
      await _settle(tester);
      expect(find.text('Update odometer'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current reading'),
        '13000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _settle(tester);

      final vehicle = await (db.select(
        db.vehicles,
      )..where((v) => v.id.equals(_vehicleId))).getSingle();
      expect(vehicle.odometer, 13000);

      await _drainPendingTimers(tester);
    });

    testWidgets('a new odometer reading re-evaluates distance reminders', (
      tester,
    ) async {
      await insertVehicle(odometer: 12500, unit: 'mi');
      // Due at 10000 + 8000 = 18000; currently 5500 away.
      await insertRule(
        id: 'r1',
        intervalDistance: 8000,
        lastDoneOdometer: 10000,
      );
      await _pumpDetail(tester);

      expect(find.text('Due in 5500 mi'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Update'));
      await _settle(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current reading'),
        '17800',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _settle(tester);

      // The status recomputed from the new reading without a manual refresh.
      expect(find.text('Due in 200 mi'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });

  group('reminders section', () {
    testWidgets('lists active rules with their due status', (tester) async {
      await insertVehicle(unit: 'mi');
      await insertRule(
        id: 'r1',
        type: ServiceType.oilChange,
        intervalDistance: 8000,
        lastDoneOdometer: 10000,
      );
      await _pumpDetail(tester);

      expect(find.text('Oil change'), findsOneWidget);
      expect(find.text('Due in 5500 mi'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('hides inactive rules', (tester) async {
      await insertVehicle();
      await insertRule(
        id: 'r1',
        type: ServiceType.brakes,
        intervalMonths: 6,
        isActive: false,
      );
      await _pumpDetail(tester);

      expect(find.text('Brakes'), findsNothing);
      expect(find.text('No active reminders.'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('Manage reminders navigates', (tester) async {
      await insertVehicle();
      await _pumpDetail(tester);

      await tester.tap(find.text('Manage reminders'));
      await _settle(tester);

      expect(find.text('manage reminders'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });

  group('service history', () {
    testWidgets('shows the empty-state copy when there are no records', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpDetail(tester);

      expect(find.textContaining('No service records yet.'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('lists records newest first with date and odometer', (
      tester,
    ) async {
      await insertVehicle(unit: 'km');
      await insertRecord(
        id: 's1',
        performedAt: DateTime(2026, 1, 10),
        type: ServiceType.oilChange,
        odometer: 10000,
      );
      await insertRecord(
        id: 's2',
        performedAt: DateTime(2026, 5, 2),
        type: ServiceType.brakes,
        odometer: 12000,
      );
      await _pumpDetail(tester);

      expect(find.text('2 May 2026 · 12,000 km'), findsOneWidget);
      expect(find.text('10 Jan 2026 · 10,000 km'), findsOneWidget);

      // Newest first: the brakes row sits above the oil change row.
      final brakesY = tester.getTopLeft(find.text('Brakes')).dy;
      final oilY = tester.getTopLeft(find.text('Oil change')).dy;
      expect(brakesY, lessThan(oilY));

      await _drainPendingTimers(tester);
    });

    testWidgets('shows cost only when recorded', (tester) async {
      await insertVehicle();
      await insertRecord(
        id: 's1',
        performedAt: DateTime(2026, 5, 2),
        cost: 89.5,
        currency: 'EUR',
      );
      await insertRecord(
        id: 's2',
        performedAt: DateTime(2026, 4, 1),
        type: ServiceType.brakes,
      );
      await _pumpDetail(tester);

      expect(find.text('89.5 EUR'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('omits the odometer from the row when not recorded', (
      tester,
    ) async {
      await insertVehicle();
      await insertRecord(id: 's1', performedAt: DateTime(2026, 5, 2));
      await _pumpDetail(tester);

      expect(find.text('2 May 2026'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('tapping a record opens it for editing', (tester) async {
      await insertVehicle();
      await insertRecord(id: 's1', performedAt: DateTime(2026, 5, 2));
      await _pumpDetail(tester);

      await tester.tap(find.text('Oil change'));
      await _settle(tester);

      expect(find.text('edit service s1'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('Add service record navigates', (tester) async {
      await insertVehicle();
      await _pumpDetail(tester);

      await tester.tap(find.text('Add service record'));
      await _settle(tester);

      expect(find.text('add service'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('swiping a record deletes it and offers undo', (tester) async {
      await insertVehicle();
      await insertRecord(id: 's1', performedAt: DateTime(2026, 5, 2));
      await _pumpDetail(tester);

      await tester.drag(find.text('Oil change'), const Offset(-500, 0));
      await _settle(tester);

      expect(find.text('Service record deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      final stored = await (db.select(
        db.serviceRecords,
      )..where((r) => r.id.equals('s1'))).getSingle();
      expect(stored.deletedAt, isNotNull, reason: 'soft-deleted, not purged');

      await _drainPendingTimers(tester);
    });

    testWidgets('Undo restores the deleted record', (tester) async {
      await insertVehicle();
      await insertRecord(id: 's1', performedAt: DateTime(2026, 5, 2));
      await _pumpDetail(tester);

      await tester.drag(find.text('Oil change'), const Offset(-500, 0));
      // The snackbar slides up over ~250ms; tapping mid-animation lands
      // outside the viewport, so wait for it to come to rest.
      await _settle(tester, frames: 20);
      expect(find.textContaining('No service records yet.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await _settle(tester);

      final stored = await (db.select(
        db.serviceRecords,
      )..where((r) => r.id.equals('s1'))).getSingle();
      expect(stored.deletedAt, isNull);
      expect(find.text('Oil change'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });

  group('overflow menu', () {
    testWidgets('Edit vehicle navigates', (tester) async {
      await insertVehicle();
      await _pumpDetail(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Edit vehicle'));
      await _settle(tester);

      expect(find.text('edit vehicle'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('Share with household opens the paywall for free users', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpDetail(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Share with household'));
      await _settle(tester);

      expect(find.text('paywall'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('Share with household explains the account to a subscriber', (
      tester,
    ) async {
      // Auth is never requested on launch; this tap is the only thing that
      // triggers it, and only after the explainer.
      await insertVehicle();
      await _pumpDetail(tester, premium: true);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Share with household'));
      await _settle(tester);

      expect(find.text('paywall'), findsNothing);
      expect(find.text('Share your garage'), findsOneWidget);
      expect(find.textContaining('uploaded'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('a signed-in subscriber skips the explainer', (tester) async {
      final auth = FakeAuthBackend();
      await auth.signInWithAppleIdToken(idToken: 't', rawNonce: 'n');
      await insertVehicle();
      await _pumpDetail(tester, premium: true, auth: auth);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Share with household'));
      await _settle(tester);

      expect(find.text('Share your garage'), findsNothing);
      expect(auth.appleCallCount, 0, reason: 'no second sign-in');

      await _drainPendingTimers(tester);
    });

    testWidgets('Delete vehicle warns that history goes too', (tester) async {
      await insertVehicle();
      await _pumpDetail(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Delete vehicle'));
      await _settle(tester);

      expect(find.text('Delete Blue Civic?'), findsOneWidget);
      expect(find.textContaining('service history'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('cancelling the dialog keeps the vehicle', (tester) async {
      await insertVehicle();
      await _pumpDetail(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Delete vehicle'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester);

      final vehicle = await (db.select(
        db.vehicles,
      )..where((v) => v.id.equals(_vehicleId))).getSingle();
      expect(vehicle.deletedAt, isNull);

      await _drainPendingTimers(tester);
    });

    testWidgets('confirming deletes the vehicle and leaves the screen', (
      tester,
    ) async {
      await insertVehicle();
      await insertRecord(id: 's1', performedAt: DateTime(2026, 5, 2));
      await _pumpDetail(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
      await tester.tap(find.text('Delete vehicle'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _settle(tester);

      final vehicle = await (db.select(
        db.vehicles,
      )..where((v) => v.id.equals(_vehicleId))).getSingle();
      expect(vehicle.deletedAt, isNotNull);

      // The cascade tombstones the history along with the vehicle.
      final record = await (db.select(
        db.serviceRecords,
      )..where((r) => r.id.equals('s1'))).getSingle();
      expect(record.deletedAt, isNotNull);

      expect(find.text('garage list'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });
}
