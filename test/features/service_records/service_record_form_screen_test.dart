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
import 'package:ourgarage/features/service_records/service_record_form_screen.dart';

import '../../support/fake_notification_plugin.dart';

const _vehicleId = 'v1';

/// Pumps [ServiceRecordFormScreen] behind a real router, so `context.pop()`
/// (used by both create and edit saves) has somewhere to go.
Future<void> _pumpForm(
  WidgetTester tester, {
  String? recordId,
  bool premium = false,
}) async {
  final router = GoRouter(
    initialLocation: '/base',
    routes: [
      GoRoute(path: '/base', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/form',
        builder: (_, _) => const ServiceRecordFormScreen(vehicleId: _vehicleId),
      ),
      GoRoute(
        path: '/form/:recordId',
        builder: (_, state) => ServiceRecordFormScreen(
          vehicleId: _vehicleId,
          recordId: state.pathParameters['recordId'],
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        premiumStatusProvider.overrideWith((ref) => premium),
        fakeNotificationServiceOverride(),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();

  router.push(recordId == null ? '/form' : '/form/$recordId');
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Stream providers leave a zero-duration drift cleanup timer pending on
/// disposal; draining it here keeps the test binding from flagging it.
Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Finder _saveButton(String label) => find.widgetWithText(FilledButton, label);

/// Taps the save button and waits for the save chain to actually land.
///
/// The save flow does multiple sequential drift round trips (insert the
/// record, read the vehicle's rules, update the matching one). Those run
/// against a real sqlite connection, so `tester.pump()`'s fake clock alone
/// doesn't guarantee they've finished — `runAsync` steps outside the fake-time
/// zone so the underlying Futures can genuinely resolve.
Future<void> _tapSave(WidgetTester tester, String label) async {
  await tester.tap(_saveButton(label));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

bool _isEnabled(WidgetTester tester, Finder buttonFinder) {
  final button = tester.widget<FilledButton>(buttonFinder);
  return button.onPressed != null;
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

  Future<void> insertVehicle({int odometer = 12500, String unit = 'km'}) {
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

  Future<String> insertRecord({
    required DateTime performedAt,
    ServiceType type = ServiceType.oilChange,
    String? customTypeLabel,
    int? odometer,
    String? notes,
    double? cost,
    String? currency,
  }) async {
    const id = 's1';
    await db
        .into(db.serviceRecords)
        .insert(
          ServiceRecordsCompanion.insert(
            id: id,
            vehicleId: _vehicleId,
            performedAt: performedAt,
            type: type.name,
            customTypeLabel: Value(customTypeLabel),
            odometer: Value(odometer),
            notes: Value(notes),
            cost: Value(cost),
            currency: Value(currency),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
    return id;
  }

  group('create mode', () {
    testWidgets('defaults type, date and odometer', (tester) async {
      await insertVehicle(odometer: 12500);
      await _pumpForm(tester);

      expect(find.text('Oil change'), findsOneWidget);
      expect(find.text('12500'), findsOneWidget);
      // Today's date, formatted "d MMM yyyy".
      final today = DateFormatForTest.today();
      expect(find.text(today), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('save is enabled without any optional field filled', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpForm(tester);

      expect(_isEnabled(tester, _saveButton('Add record')), isTrue);

      await _drainPendingTimers(tester);
    });

    testWidgets('selecting Custom reveals a required label field', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpForm(tester);

      expect(find.widgetWithText(TextFormField, 'Custom type'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<ServiceType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Custom type'), findsOneWidget);
      expect(_isEnabled(tester, _saveButton('Add record')), isFalse);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Custom type'),
        'Windshield replacement',
      );
      await tester.pump();
      expect(_isEnabled(tester, _saveButton('Add record')), isTrue);

      await _drainPendingTimers(tester);
    });

    testWidgets('rejects a negative odometer', (tester) async {
      await insertVehicle();
      await _pumpForm(tester);

      final field = find.widgetWithText(TextFormField, 'Odometer at service');
      final fieldState = tester.state<FormFieldState<String>>(field);
      expect(
        fieldState.widget.validator?.call('-1'),
        'Enter a reading of 0 or more',
      );

      await _drainPendingTimers(tester);
    });

    testWidgets('creates the record with the entered fields', (tester) async {
      await insertVehicle(odometer: 12500);
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer at service'),
        '13000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes'),
        'Synthetic oil',
      );
      await tester.pump();
      await _tapSave(tester, 'Add record');

      final records = await db.select(db.serviceRecords).get();
      expect(records, hasLength(1));
      expect(records.single.type, ServiceType.oilChange.name);
      expect(records.single.odometer, 13000);
      expect(records.single.notes, 'Synthetic oil');

      await _drainPendingTimers(tester);
    });

    group('premium cost gate', () {
      testWidgets('cost field is disabled for free users', (tester) async {
        await insertVehicle();
        await _pumpForm(tester, premium: false);

        final costField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Cost'),
        );
        expect(costField.enabled, isFalse);
        expect(find.text('Premium'), findsOneWidget);

        await _drainPendingTimers(tester);
      });

      testWidgets('tapping the disabled field opens the paywall', (
        tester,
      ) async {
        final router = GoRouter(
          initialLocation: '/base',
          routes: [
            GoRoute(path: '/base', builder: (_, _) => const SizedBox.shrink()),
            GoRoute(
              path: '/form',
              builder: (_, _) =>
                  const ServiceRecordFormScreen(vehicleId: _vehicleId),
            ),
            GoRoute(
              path: '/paywall',
              builder: (_, _) => const Scaffold(body: Text('paywall')),
            ),
          ],
        );
        await insertVehicle();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              premiumStatusProvider.overrideWith((ref) => false),
              fakeNotificationServiceOverride(),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        router.push('/form');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        await tester.tap(find.text('Premium'));
        await tester.pump();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.text('paywall'), findsOneWidget);

        await _drainPendingTimers(tester);
      });

      testWidgets('cost field is enabled and saved for premium users', (
        tester,
      ) async {
        await insertVehicle();
        await _pumpForm(tester, premium: true);

        final costField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Cost'),
        );
        expect(costField.enabled, isTrue);
        expect(find.text('Premium'), findsNothing);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Cost'),
          '89.50',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Currency'),
          'EUR',
        );
        await tester.pump();
        await _tapSave(tester, 'Add record');

        final record = await db.select(db.serviceRecords).getSingle();
        expect(record.cost, 89.5);
        expect(record.currency, 'EUR');

        await _drainPendingTimers(tester);
      });

      testWidgets('cost entered while free is never persisted', (tester) async {
        // Regression guard: even if a disabled field somehow carried a stale
        // value in its controller (e.g. after downgrading mid-session), the
        // save path must gate on premium status, not merely on field text.
        // The field can't be typed into while disabled, so this reaches the
        // controller directly to simulate that stale-value scenario.
        await insertVehicle();
        await _pumpForm(tester, premium: false);

        final costField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Cost'),
        );
        costField.controller!.text = '999';

        await _tapSave(tester, 'Add record');

        final record = await db.select(db.serviceRecords).getSingle();
        expect(record.cost, isNull);
        expect(record.currency, isNull);

        await _drainPendingTimers(tester);
      });
    });

    group('reminder linkage', () {
      testWidgets('saving a record marks the matching active rule done', (
        tester,
      ) async {
        await insertVehicle(odometer: 12500, unit: 'km');
        await insertRule(
          id: 'r1',
          type: ServiceType.oilChange,
          intervalDistance: 8000,
          lastDoneOdometer: 5000,
        );
        await _pumpForm(tester);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Odometer at service'),
          '13000',
        );
        await tester.pump();
        await _tapSave(tester, 'Add record');

        final rule = await (db.select(
          db.reminderRules,
        )..where((r) => r.id.equals('r1'))).getSingle();
        expect(rule.lastDoneOdometer, 13000);
        expect(rule.lastDoneAt, isNotNull);

        await _drainPendingTimers(tester);
      });

      testWidgets('does not touch a rule of a different type', (tester) async {
        await insertVehicle();
        await insertRule(
          id: 'r1',
          type: ServiceType.tireRotation,
          intervalMonths: 6,
        );
        await _pumpForm(tester); // defaults to oilChange

        await _tapSave(tester, 'Add record');

        final rule = await (db.select(
          db.reminderRules,
        )..where((r) => r.id.equals('r1'))).getSingle();
        expect(rule.lastDoneAt, isNull);
        expect(rule.lastDoneOdometer, isNull);

        await _drainPendingTimers(tester);
      });

      testWidgets('does not touch an inactive rule of the same type', (
        tester,
      ) async {
        await insertVehicle();
        await insertRule(
          id: 'r1',
          type: ServiceType.oilChange,
          intervalMonths: 6,
          isActive: false,
        );
        await _pumpForm(tester);

        await _tapSave(tester, 'Add record');

        final rule = await (db.select(
          db.reminderRules,
        )..where((r) => r.id.equals('r1'))).getSingle();
        expect(rule.lastDoneAt, isNull);

        await _drainPendingTimers(tester);
      });

      testWidgets('uses the record date and odometer, not "now"', (
        tester,
      ) async {
        await insertVehicle(odometer: 12500, unit: 'km');
        await insertRule(
          id: 'r1',
          type: ServiceType.oilChange,
          intervalMonths: 6,
        );
        await _pumpForm(tester);

        // Pick a date via the picker rather than typing — the field is a
        // read-only display driven by showDatePicker.
        await tester.tap(find.text(DateFormatForTest.today()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Odometer at service'),
          '9000',
        );
        await tester.pump();
        await _tapSave(tester, 'Add record');

        final rule = await (db.select(
          db.reminderRules,
        )..where((r) => r.id.equals('r1'))).getSingle();
        expect(rule.lastDoneOdometer, 9000);

        await _drainPendingTimers(tester);
      });

      testWidgets('leaves reminders alone when editing a record', (
        tester,
      ) async {
        await insertVehicle();
        await insertRule(
          id: 'r1',
          type: ServiceType.oilChange,
          intervalMonths: 6,
        );
        final recordId = await insertRecord(
          performedAt: DateTime(2026, 1, 10),
          odometer: 10000,
        );
        await _pumpForm(tester, recordId: recordId);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Notes'),
          'Corrected note',
        );
        await tester.pump();
        await _tapSave(tester, 'Save changes');

        final rule = await (db.select(
          db.reminderRules,
        )..where((r) => r.id.equals('r1'))).getSingle();
        expect(
          rule.lastDoneAt,
          isNull,
          reason: 'editing history should not silently complete a reminder',
        );

        await _drainPendingTimers(tester);
      });
    });
  });

  group('edit mode', () {
    testWidgets('prefills fields from the existing record', (tester) async {
      await insertVehicle();
      final recordId = await insertRecord(
        performedAt: DateTime(2026, 3, 5),
        type: ServiceType.brakes,
        odometer: 11000,
        notes: 'Front pads',
        cost: 120,
        currency: 'USD',
      );
      await _pumpForm(tester, recordId: recordId, premium: true);

      expect(find.text('Brakes'), findsOneWidget);
      expect(find.text('11000'), findsOneWidget);
      expect(find.text('Front pads'), findsOneWidget);
      expect(find.text('120.0'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('updates the record in place', (tester) async {
      await insertVehicle();
      final recordId = await insertRecord(
        performedAt: DateTime(2026, 3, 5),
        odometer: 11000,
      );
      await _pumpForm(tester, recordId: recordId);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer at service'),
        '11500',
      );
      await tester.pump();
      await _tapSave(tester, 'Save changes');

      final record = await (db.select(
        db.serviceRecords,
      )..where((r) => r.id.equals(recordId))).getSingle();
      expect(record.odometer, 11500);

      final all = await db.select(db.serviceRecords).get();
      expect(all, hasLength(1), reason: 'edit must not create a new row');

      await _drainPendingTimers(tester);
    });
  });
}

/// Small helper so tests don't hardcode "today" and drift out of sync with
/// the system clock.
class DateFormatForTest {
  static String today() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }
}
