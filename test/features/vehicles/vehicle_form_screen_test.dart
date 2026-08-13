import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/app_router.dart';
import 'package:ourgarage/app_routes.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/data/repositories/premium_status_provider.dart';
import 'package:ourgarage/features/vehicles/vehicle_form_screen.dart';

/// Pumps [VehicleFormScreen], routed through a real (minimal) GoRouter.
///
/// Edit-mode saves call `context.pop()`, a go_router extension that throws
/// without a router in the widget tree — a plain `MaterialApp` isn't enough,
/// even though it works fine for the create-mode tests, which never call pop.
Future<void> _pumpForm(
  WidgetTester tester, {
  String? vehicleId,
  bool premium = false,
}) async {
  final router = GoRouter(
    initialLocation: '/base',
    routes: [
      GoRoute(path: '/base', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/form', builder: (_, _) => const VehicleFormScreen()),
      GoRoute(
        path: '/form/:id',
        builder: (_, state) =>
            VehicleFormScreen(vehicleId: state.pathParameters['id']),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [premiumStatusProvider.overrideWith((ref) => premium)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();

  // Push the form on top of the base route so context.pop() (used by
  // edit-mode save) has somewhere to go back to. The push transition and,
  // in edit mode, the stream provider's first value both need real pumps to
  // land before the form is interactable.
  router.push(vehicleId == null ? '/form' : '/form/$vehicleId');
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Edit mode reads the vehicle through a stream provider, whose drift query
/// schedules a zero-duration cleanup timer on disposal. Draining it here stops
/// the test binding from reporting a leaked pending timer.
Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Finder _saveButton(String label) => find.widgetWithText(FilledButton, label);

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

  group('create mode validation', () {
    testWidgets('save is disabled until nickname and odometer are valid', (
      tester,
    ) async {
      await _pumpForm(tester);

      final save = _saveButton('Add vehicle');
      expect(_isEnabled(tester, save), isFalse);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic',
      );
      await tester.pump();
      expect(_isEnabled(tester, save), isFalse, reason: 'odometer still empty');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '12000',
      );
      await tester.pump();
      expect(_isEnabled(tester, save), isTrue);
    });

    testWidgets('rejects an empty nickname', (tester) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '0',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        '   ',
      );
      await tester.pump();

      expect(find.text('Nickname is required'), findsOneWidget);
      expect(_isEnabled(tester, _saveButton('Add vehicle')), isFalse);
    });

    testWidgets('rejects a nickname over 40 characters', (tester) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '0',
      );
      // maxLength:40 on the field itself truncates input at the platform
      // level, so exceeding the limit is exercised through the validator
      // directly rather than by typing 41 characters.
      final fieldState = tester.state<FormFieldState<String>>(
        find.byType(TextFormField).first,
      );
      expect(
        fieldState.widget.validator?.call('a' * 41),
        'Keep it under 40 characters',
      );
    });

    testWidgets('rejects a negative odometer', (tester) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic',
      );
      final odometerField = find.widgetWithText(
        TextFormField,
        'Current odometer',
      );
      final fieldState = tester.state<FormFieldState<String>>(odometerField);
      expect(
        fieldState.widget.validator?.call('-5'),
        'Enter a reading of 0 or more',
      );
    });

    testWidgets('accepts a zero odometer', (tester) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '0',
      );
      await tester.pump();

      expect(_isEnabled(tester, _saveButton('Add vehicle')), isTrue);
    });

    testWidgets('year field accepts empty and rejects out-of-range values', (
      tester,
    ) async {
      await _pumpForm(tester);

      final yearField = find.widgetWithText(TextFormField, 'Year');
      final fieldState = tester.state<FormFieldState<String>>(yearField);

      expect(fieldState.widget.validator?.call(''), isNull);
      expect(fieldState.widget.validator?.call('1899'), isNotNull);
      expect(fieldState.widget.validator?.call('1900'), isNull);
      final nextYear = (DateTime.now().year + 1).toString();
      expect(fieldState.widget.validator?.call(nextYear), isNull);
      final tooFar = (DateTime.now().year + 2).toString();
      expect(fieldState.widget.validator?.call(tooFar), isNotNull);
    });

    testWidgets('make/model/plate are optional and do not block save', (
      tester,
    ) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '500',
      );
      await tester.pump();

      expect(_isEnabled(tester, _saveButton('Add vehicle')), isTrue);
    });

    testWidgets('nickname field is autofocused', (tester) async {
      await _pumpForm(tester);

      final nicknameField = find.widgetWithText(TextFormField, 'Nickname');
      final textField = tester.widget<TextField>(
        find.descendant(of: nicknameField, matching: find.byType(TextField)),
      );
      expect(textField.autofocus, isTrue);
    });
  });

  group('create mode save flow', () {
    testWidgets('creates the vehicle and offers default reminders', (
      tester,
    ) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '12000',
      );
      await tester.pump();

      await tester.tap(_saveButton('Add vehicle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Set up reminders?'), findsOneWidget);
      expect(find.text('Oil change'), findsOneWidget);
      expect(find.text('Tire rotation'), findsOneWidget);
      expect(find.text('Inspection / MOT'), findsOneWidget);

      final vehicles = await db.select(db.vehicles).get();
      expect(vehicles, hasLength(1));
      expect(vehicles.single.nickname, 'Blue Civic');
      expect(vehicles.single.odometer, 12000);
    });

    testWidgets(
      'default reminder checkboxes are pre-checked and create rules',
      (tester) async {
        await _pumpForm(tester);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nickname'),
          'Blue Civic',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Current odometer'),
          '12000',
        );
        await tester.pump();
        await tester.tap(_saveButton('Add vehicle'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final checkboxes = tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .toList();
        expect(checkboxes, hasLength(3));
        expect(checkboxes.every((c) => c.value == true), isTrue);

        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Add reminders'),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.tap(find.widgetWithText(FilledButton, 'Add reminders'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final rules = await db.select(db.reminderRules).get();
        expect(rules, hasLength(3));
      },
    );

    testWidgets('skipping the reminders sheet creates no rules', (
      tester,
    ) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '12000',
      );
      await tester.pump();
      await tester.tap(_saveButton('Add vehicle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.ensureVisible(find.widgetWithText(TextButton, 'Skip'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.widgetWithText(TextButton, 'Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final rules = await db.select(db.reminderRules).get();
      expect(rules, isEmpty);
    });

    testWidgets('unchecking a reminder excludes it from creation', (
      tester,
    ) async {
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '12000',
      );
      await tester.pump();
      await tester.tap(_saveButton('Add vehicle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Inspection / MOT'));
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Add reminders'),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Add reminders'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final rules = await db.select(db.reminderRules).get();
      expect(rules, hasLength(2));
      expect(rules.any((r) => r.type == 'inspection'), isFalse);
    });
  });

  group('free-tier gate', () {
    testWidgets(
      'redirects to paywall instead of saving when at the free limit',
      (tester) async {
        // Pre-fill one active vehicle so the next create hits the limit.
        await db
            .into(db.vehicles)
            .insert(
              VehiclesCompanion.insert(
                id: 'existing',
                nickname: 'Old Truck',
                odometerUnit: 'km',
                createdAt: DateTime(2026, 1, 1),
                updatedAt: DateTime(2026, 1, 1),
              ),
            );

        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
        );
        await tester.pump();

        appRouter.go(AppRoutes.addVehicle);
        await tester.pump();
        await tester.pump();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nickname'),
          'Second Car',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Current odometer'),
          '500',
        );
        await tester.pump();

        await tester.tap(_saveButton('Add vehicle'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Paywall — coming soon'), findsOneWidget);

        final vehicles = await db.select(db.vehicles).get();
        expect(
          vehicles,
          hasLength(1),
          reason: 'the second vehicle must not have been saved',
        );

        appRouter.go(AppRoutes.vehicleList);
        await tester.pump();
        await _drainPendingTimers(tester);
      },
    );

    testWidgets('does not check countActiveVehicles when premium', (
      tester,
    ) async {
      await db
          .into(db.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: 'existing',
              nickname: 'Old Truck',
              odometerUnit: 'km',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      await _pumpForm(tester, premium: true);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Second Car',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current odometer'),
        '500',
      );
      await tester.pump();

      await tester.tap(_saveButton('Add vehicle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final vehicles = await db.select(db.vehicles).get();
      expect(vehicles, hasLength(2));

      // Reminders sheet is still shown for the newly created vehicle.
      expect(find.text('Set up reminders?'), findsOneWidget);
    });
  });

  group('edit mode', () {
    testWidgets('prefills fields from the existing vehicle', (tester) async {
      await db
          .into(db.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: 'v1',
              nickname: 'Blue Civic',
              make: const Value('Honda'),
              model: const Value('Civic'),
              year: const Value(2019),
              plate: const Value('ABC-123'),
              odometer: const Value(15000),
              odometerUnit: 'km',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      await _pumpForm(tester, vehicleId: 'v1');
      await tester.pump();

      expect(find.text('Blue Civic'), findsOneWidget);
      expect(find.text('Honda'), findsOneWidget);
      expect(find.text('Civic'), findsOneWidget);
      expect(find.text('2019'), findsOneWidget);
      expect(find.text('ABC-123'), findsOneWidget);
      expect(find.text('15000'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('does not offer default reminders on edit', (tester) async {
      await db
          .into(db.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: 'v1',
              nickname: 'Blue Civic',
              odometerUnit: 'km',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      await _pumpForm(tester, vehicleId: 'v1');
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nickname'),
        'Blue Civic Updated',
      );
      await tester.pump();

      await tester.tap(_saveButton('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Set up reminders?'), findsNothing);

      final vehicle = await (db.select(
        db.vehicles,
      )..where((v) => v.id.equals('v1'))).getSingle();
      expect(vehicle.nickname, 'Blue Civic Updated');

      await _drainPendingTimers(tester);
    });

    testWidgets('editing does not touch the odometer field value', (
      tester,
    ) async {
      await db
          .into(db.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: 'v1',
              nickname: 'Blue Civic',
              odometer: const Value(9999),
              odometerUnit: 'km',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      await _pumpForm(tester, vehicleId: 'v1');
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Make'),
        'Honda',
      );
      await tester.pump();
      await tester.tap(_saveButton('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final vehicle = await (db.select(
        db.vehicles,
      )..where((v) => v.id.equals('v1'))).getSingle();
      expect(vehicle.odometer, 9999, reason: 'edit must not alter odometer');
      expect(vehicle.make, 'Honda');

      await _drainPendingTimers(tester);
    });
  });
}
