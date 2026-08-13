import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/reminders/reminder_rule_form_screen.dart';

import '../../support/fake_notification_plugin.dart';

const _vehicleId = 'v1';

/// Pumps [ReminderRuleFormScreen] behind a real router, so `context.pop()`
/// (used by both create and edit saves) has somewhere to go, and so the
/// permission sheet's own navigation has a stack under it.
Future<void> _pumpForm(WidgetTester tester, {String? ruleId}) async {
  final router = GoRouter(
    initialLocation: '/base',
    routes: [
      GoRoute(path: '/base', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/form',
        builder: (_, _) => const ReminderRuleFormScreen(vehicleId: _vehicleId),
      ),
      GoRoute(
        path: '/form/:ruleId',
        builder: (_, state) => ReminderRuleFormScreen(
          vehicleId: _vehicleId,
          ruleId: state.pathParameters['ruleId'],
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
  await tester.pump();

  router.push(ruleId == null ? '/form' : '/form/$ruleId');
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

Finder _saveButton(String label) => find.widgetWithText(FilledButton, label);

/// Scrolls [finder] into view. This form grows past the fixed test viewport
/// height once the custom-label or last-done fields are showing, which pushes
/// the save button below the fold — `find`/`tap` calls on an off-screen widget
/// fail (or, worse, silently target the wrong element), so every interaction
/// with the button goes through this first.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
}

/// The save flow does several sequential drift round trips (check for a first
/// rule, insert, re-read for scheduling), so `runAsync` steps outside fake
/// time to let the real sqlite connection actually resolve them.
Future<void> _tapSave(WidgetTester tester, String label) async {
  final button = _saveButton(label);
  await _scrollTo(tester, button);
  await tester.tap(button);
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await _settle(tester);
}

Future<bool> _isEnabled(WidgetTester tester, Finder buttonFinder) async {
  await _scrollTo(tester, buttonFinder);
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

  Future<String> insertRule({
    String id = 'r1',
    ServiceType type = ServiceType.oilChange,
    String? customTypeLabel,
    int? intervalMonths,
    int? intervalDistance,
    DateTime? lastDoneAt,
    int? lastDoneOdometer,
  }) async {
    await db
        .into(db.reminderRules)
        .insert(
          ReminderRulesCompanion.insert(
            id: id,
            vehicleId: _vehicleId,
            type: type.name,
            customTypeLabel: Value(customTypeLabel),
            intervalMonths: Value(intervalMonths),
            intervalDistance: Value(intervalDistance),
            lastDoneAt: Value(lastDoneAt),
            lastDoneOdometer: Value(lastDoneOdometer),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
    return id;
  }

  group('create mode validation', () {
    testWidgets('save is disabled with no interval set', (tester) async {
      await insertVehicle();
      await _pumpForm(tester);

      expect(await _isEnabled(tester, _saveButton('Add reminder')), isFalse);

      await _drainPendingTimers(tester);
    });

    testWidgets('months alone is enough to enable save', (tester) async {
      await insertVehicle();
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.pump();

      expect(await _isEnabled(tester, _saveButton('Add reminder')), isTrue);

      await _drainPendingTimers(tester);
    });

    testWidgets('distance alone is enough to enable save', (tester) async {
      await insertVehicle();
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (distance)'),
        '5000',
      );
      await tester.pump();

      expect(await _isEnabled(tester, _saveButton('Add reminder')), isTrue);

      await _drainPendingTimers(tester);
    });

    testWidgets('shows the validation message on both interval fields', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpForm(tester);

      // autovalidateMode kicks in once the form has been interacted with.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '',
      );
      await tester.pump();

      expect(
        find.text('Set an interval in months, distance, or both'),
        findsWidgets,
      );

      await _drainPendingTimers(tester);
    });

    testWidgets('selecting Custom reveals a required label field', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.pump();
      expect(await _isEnabled(tester, _saveButton('Add reminder')), isTrue);

      final dropdown = find.byType(DropdownButtonFormField<ServiceType>);
      await _scrollTo(tester, dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();

      final customTypeField = find.widgetWithText(TextFormField, 'Custom type');
      await _scrollTo(tester, customTypeField);
      expect(customTypeField, findsOneWidget);
      expect(await _isEnabled(tester, _saveButton('Add reminder')), isFalse);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Custom type'),
        'Windshield replacement',
      );
      await tester.pump();
      expect(await _isEnabled(tester, _saveButton('Add reminder')), isTrue);

      await _drainPendingTimers(tester);
    });

    testWidgets('rejects a negative last-done odometer', (tester) async {
      await insertVehicle();
      await _pumpForm(tester);

      final field = find.widgetWithText(
        TextFormField,
        'Odometer when last done',
      );
      final fieldState = tester.state<FormFieldState<String>>(field);
      expect(
        fieldState.widget.validator?.call('-1'),
        'Enter a reading of 0 or more',
      );

      await _drainPendingTimers(tester);
    });
  });

  group('create mode save flow', () {
    testWidgets('persists both intervals and the last-done fields', (
      tester,
    ) async {
      await insertVehicle(unit: 'mi');
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (distance)'),
        '5000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Odometer when last done'),
        '9000',
      );
      await tester.pump();
      await _tapSave(tester, 'Add reminder');

      final rules = await db.select(db.reminderRules).get();
      expect(rules, hasLength(1));
      expect(rules.single.type, ServiceType.oilChange.name);
      expect(rules.single.intervalMonths, 6);
      expect(rules.single.intervalDistance, 5000);
      expect(rules.single.lastDoneOdometer, 9000);

      await _drainPendingTimers(tester);
    });

    testWidgets('persists the chosen last-done date', (tester) async {
      await insertVehicle();
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.pump();

      final notSet = find.text('Not set');
      await _scrollTo(tester, notSet);
      await tester.tap(notSet);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await _tapSave(tester, 'Add reminder');

      final rule = await db.select(db.reminderRules).getSingle();
      expect(rule.lastDoneAt, isNotNull);

      await _drainPendingTimers(tester);
    });

    testWidgets('persists a custom type with its label', (tester) async {
      await insertVehicle();
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '12',
      );
      await tester.pump();
      final dropdown = find.byType(DropdownButtonFormField<ServiceType>);
      await _scrollTo(tester, dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom').last);
      await tester.pumpAndSettle();
      final customTypeField = find.widgetWithText(TextFormField, 'Custom type');
      await _scrollTo(tester, customTypeField);
      await tester.enterText(customTypeField, 'Windshield replacement');
      await tester.pump();

      await _tapSave(tester, 'Add reminder');

      final rule = await db.select(db.reminderRules).getSingle();
      expect(rule.type, ServiceType.custom.name);
      expect(rule.customTypeLabel, 'Windshield replacement');

      await _drainPendingTimers(tester);
    });

    testWidgets('schedules a notification for a time-based rule', (
      tester,
    ) async {
      final plugin = FakeNotificationPlugin();
      await insertVehicle();
      await _pumpFormWithPlugin(tester, plugin);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.pump();
      await _tapSave(tester, 'Add reminder');

      // First-ever rule: the permission explainer sheet blocks the save flow
      // until dismissed, so scheduling hasn't happened yet.
      await tester.tap(find.text('Not now'));
      await _settle(tester);

      expect(plugin.scheduledIds, isNotEmpty);

      await _drainPendingTimers(tester);
    });

    testWidgets('does not schedule an OS notification for distance alone', (
      tester,
    ) async {
      // A distance-only rule has no due date and must not fire on its own —
      // see ReminderNotificationScheduler.rescheduleForRule.
      final plugin = FakeNotificationPlugin();
      await insertVehicle();
      await _pumpFormWithPlugin(tester, plugin);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (distance)'),
        '5000',
      );
      await tester.pump();
      await _tapSave(tester, 'Add reminder');

      expect(plugin.scheduledIds, isEmpty);

      await _drainPendingTimers(tester);
    });
  });

  group('first-ever rule permission ask', () {
    testWidgets('shows the explainer sheet on the very first rule', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.pump();
      await _tapSave(tester, 'Add reminder');

      expect(find.text('Turn on reminders'), findsOneWidget);

      // Dismiss it so save can finish and pending timers can drain.
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      await _drainPendingTimers(tester);
    });

    testWidgets('does not ask again for a second rule', (tester) async {
      await insertVehicle();
      // A rule already exists — created before this form ever opened.
      await insertRule(id: 'existing', intervalMonths: 12);
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.pump();
      await _tapSave(tester, 'Add reminder');

      expect(find.text('Turn on reminders'), findsNothing);

      final rules = await db.select(db.reminderRules).get();
      expect(rules, hasLength(2));

      await _drainPendingTimers(tester);
    });

    testWidgets('does not ask when editing an existing rule', (tester) async {
      await insertVehicle();
      final ruleId = await insertRule(intervalMonths: 6);
      await _pumpForm(tester, ruleId: ruleId);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '9',
      );
      await tester.pump();
      await _tapSave(tester, 'Save changes');

      expect(find.text('Turn on reminders'), findsNothing);

      await _drainPendingTimers(tester);
    });

    testWidgets('saves the rule regardless of the sheet choice', (
      tester,
    ) async {
      await insertVehicle();
      await _pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '6',
      );
      await tester.pump();
      await _tapSave(tester, 'Add reminder');

      await tester.tap(find.text('Not now'));
      await _settle(tester);

      final rules = await db.select(db.reminderRules).get();
      expect(
        rules,
        hasLength(1),
        reason: 'declining notifications should not undo the save',
      );

      await _drainPendingTimers(tester);
    });
  });

  group('edit mode', () {
    testWidgets('prefills fields from the existing rule', (tester) async {
      await insertVehicle();
      final ruleId = await insertRule(
        type: ServiceType.brakes,
        intervalMonths: 6,
        intervalDistance: 5000,
        lastDoneOdometer: 8000,
      );
      await _pumpForm(tester, ruleId: ruleId);

      expect(find.text('Brakes'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('5000'), findsOneWidget);
      expect(find.text('8000'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('updates the rule in place', (tester) async {
      await insertVehicle();
      final ruleId = await insertRule(intervalMonths: 6);
      await _pumpForm(tester, ruleId: ruleId);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '12',
      );
      await tester.pump();
      await _tapSave(tester, 'Save changes');

      final rule = await db.select(db.reminderRules).getSingle();
      expect(rule.intervalMonths, 12);

      final all = await db.select(db.reminderRules).get();
      expect(all, hasLength(1), reason: 'edit must not create a new row');

      await _drainPendingTimers(tester);
    });

    testWidgets('clearing both intervals is rejected', (tester) async {
      await insertVehicle();
      final ruleId = await insertRule(intervalMonths: 6);
      await _pumpForm(tester, ruleId: ruleId);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '',
      );
      await tester.pump();

      expect(await _isEnabled(tester, _saveButton('Save changes')), isFalse);

      await _drainPendingTimers(tester);
    });

    testWidgets('switching from a time interval to distance-only cancels the '
        'notification', (tester) async {
      // A distance-only rule has no due date and cannot fire a notification —
      // switching to one must cancel whatever was scheduled under the old,
      // time-based interval.
      final plugin = FakeNotificationPlugin();
      await insertVehicle();
      final ruleId = await insertRule(intervalMonths: 6);
      await _pumpFormWithPlugin(tester, plugin, ruleId: ruleId);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (months)'),
        '',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Interval (distance)'),
        '5000',
      );
      await tester.pump();
      await _tapSave(tester, 'Save changes');

      expect(plugin.cancelledIds, isNotEmpty);
      expect(plugin.scheduledIds, isEmpty);

      await _drainPendingTimers(tester);
    });
  });
}

/// Same as [_pumpForm] but with a caller-supplied plugin, so scheduling calls
/// can be inspected.
Future<void> _pumpFormWithPlugin(
  WidgetTester tester,
  FakeNotificationPlugin plugin, {
  String? ruleId,
}) async {
  final router = GoRouter(
    initialLocation: '/base',
    routes: [
      GoRoute(path: '/base', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/form',
        builder: (_, _) => const ReminderRuleFormScreen(vehicleId: _vehicleId),
      ),
      GoRoute(
        path: '/form/:ruleId',
        builder: (_, state) => ReminderRuleFormScreen(
          vehicleId: _vehicleId,
          ruleId: state.pathParameters['ruleId'],
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [fakeNotificationServiceOverride(plugin)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();

  router.push(ruleId == null ? '/form' : '/form/$ruleId');
  await _settle(tester);
}
