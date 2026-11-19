import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/data/repositories/premium_status_provider.dart';
import 'package:ourgarage/features/reminders/reminder_rule_form_screen.dart';
import 'package:ourgarage/features/service_records/service_record_form_screen.dart';
import 'package:ourgarage/features/vehicles/vehicle_form_screen.dart';

import '../../support/fake_notification_plugin.dart';

/// Audit #6: a form must not open covered in error text. Errors belong to the
/// field the user is working on, once they have touched it; until then Save
/// is simply disabled.

const _vehicleId = 'v1';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        premiumStatusProvider.overrideWith((ref) => true),
        fakeNotificationServiceOverride(),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

bool _enabled(WidgetTester tester, String label) =>
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, label))
        .onPressed !=
    null;

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseHolder.overrideWith(db);
  });

  tearDown(() async {
    DatabaseHolder.overrideWith(null);
    await db.close();
  });

  Future<void> insertVehicle() {
    final now = DateTime(2026, 1, 1);
    return db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: _vehicleId,
            nickname: 'Blue Civic',
            odometerUnit: 'km',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  group('add vehicle', () {
    testWidgets('opens without error text, Save disabled', (tester) async {
      await _pump(tester, const VehicleFormScreen());

      expect(find.text('Nickname is required'), findsNothing);
      expect(find.text('Odometer is required'), findsNothing);
      expect(_enabled(tester, 'Add vehicle'), isFalse);

      await _drainPendingTimers(tester);
    });

    testWidgets('shows an error only on the field the user touched', (
      tester,
    ) async {
      await _pump(tester, const VehicleFormScreen());

      final nickname = find.widgetWithText(TextFormField, 'Nickname');
      await tester.enterText(nickname, 'x');
      await tester.enterText(nickname, '');
      await tester.pump();

      expect(find.text('Nickname is required'), findsOneWidget);
      expect(
        find.text('Odometer is required'),
        findsNothing,
        reason: 'odometer was never touched',
      );

      await _drainPendingTimers(tester);
    });

    testWidgets('Save enables once the required fields are valid', (
      tester,
    ) async {
      await _pump(tester, const VehicleFormScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '1200',
      );
      await tester.pump();

      expect(_enabled(tester, 'Add vehicle'), isTrue);

      await _drainPendingTimers(tester);
    });
  });

  group('add reminder', () {
    testWidgets('opens without the interval error, Save disabled', (
      tester,
    ) async {
      await insertVehicle();
      await _pump(tester, const ReminderRuleFormScreen(vehicleId: _vehicleId));

      expect(
        find.text('Set an interval in months, distance, or both'),
        findsNothing,
      );
      expect(_enabled(tester, 'Add reminder'), isFalse);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.pump();
      expect(_enabled(tester, 'Add reminder'), isTrue);

      await _drainPendingTimers(tester);
    });
  });

  group('shared interval validator', () {
    testWidgets('filling one interval clears the error on the other too', (
      tester,
    ) async {
      await insertVehicle();
      await _pump(tester, const ReminderRuleFormScreen(vehicleId: _vehicleId));

      final months = find.widgetWithText(TextFormField, 'Interval (months)');
      final distance = find.widgetWithText(
        TextFormField,
        'Interval (distance)',
      );
      const error = 'Set an interval in months, distance, or both';

      // Touch both, leaving both empty: both show the error.
      await tester.enterText(distance, '1');
      await tester.enterText(distance, '');
      await tester.enterText(months, '1');
      await tester.enterText(months, '');
      await tester.pump();
      expect(find.text(error), findsNWidgets(2));

      // Filling one satisfies the rule for both fields.
      await tester.enterText(months, '6');
      await tester.pump();
      expect(find.text(error), findsNothing);

      await _drainPendingTimers(tester);
    });
  });

  group('add service', () {
    testWidgets('choosing Custom does not paint the label error up front', (
      tester,
    ) async {
      await insertVehicle();
      await _pump(tester, const ServiceRecordFormScreen(vehicleId: _vehicleId));

      expect(_enabled(tester, 'Add record'), isTrue);

      await tester.tap(find.text('Oil change').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();

      expect(find.text('Enter a label for this custom type'), findsNothing);
      expect(
        _enabled(tester, 'Add record'),
        isFalse,
        reason: 'a custom type still needs its label',
      );

      await _drainPendingTimers(tester);
    });
  });
}
