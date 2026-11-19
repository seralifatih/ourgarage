import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/data/repositories/reminder_rule_repository.dart';
import 'package:ourgarage/features/reminders/reminder_rule_form_screen.dart';
import 'package:ourgarage/services/notification_service.dart';

import '../../support/fake_notification_plugin.dart';

/// Audit #5: a reminder rule can be deleted, with Undo.

const _vehicleId = 'v1';
const _ruleId = 'r1';

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets the sequential drift writes resolve outside fake time.
Future<void> _realWait(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await _settle(tester);
}

Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseHolder.overrideWith(db);
    final now = DateTime(2026, 1, 1);
    await db
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
    await db
        .into(db.reminderRules)
        .insert(
          ReminderRulesCompanion.insert(
            id: _ruleId,
            vehicleId: _vehicleId,
            type: ServiceType.oilChange.name,
            intervalMonths: const Value(6),
            lastDoneAt: Value(DateTime.now()),
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    DatabaseHolder.overrideWith(null);
    await db.close();
  });

  Future<ReminderRule> storedRule() => (db.select(
    db.reminderRules,
  )..where((r) => r.id.equals(_ruleId))).getSingle();

  group('repository', () {
    test(
      'restoreRule clears the tombstone and only matches deleted rows',
      () async {
        final repository = ReminderRuleRepository(db.reminderRuleDao);

        expect(
          await repository.restoreRule(_ruleId),
          isFalse,
          reason: 'not deleted, nothing to undo',
        );

        await repository.softDeleteRule(_ruleId);
        expect((await storedRule()).deletedAt, isNotNull);

        expect(await repository.restoreRule(_ruleId), isTrue);
        expect((await storedRule()).deletedAt, isNull);
      },
    );
  });

  group('edit form', () {
    Future<FakeNotificationPlugin> pumpEditForm(WidgetTester tester) async {
      final plugin = FakeNotificationPlugin();
      final router = GoRouter(
        initialLocation: '/base',
        routes: [
          GoRoute(
            path: '/base',
            builder: (_, _) => const Scaffold(body: Text('reminders list')),
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
      router.push('/form/$_ruleId');
      await _settle(tester);
      return plugin;
    }

    testWidgets('add mode offers no delete', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const ReminderRuleFormScreen(vehicleId: _vehicleId),
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

      expect(find.byTooltip('Delete reminder'), findsNothing);
      await _drainPendingTimers(tester);
    });

    testWidgets('Delete removes the rule, cancels it and offers Undo', (
      tester,
    ) async {
      final plugin = await pumpEditForm(tester);

      await tester.tap(find.byTooltip('Delete reminder'));
      await _realWait(tester);

      expect(find.text('reminders list'), findsOneWidget);
      expect(find.text('Reminder deleted'), findsOneWidget);
      expect((await storedRule()).deletedAt, isNotNull);
      expect(
        plugin.cancelledIds,
        contains(NotificationService.reminderNotificationId(_ruleId)),
      );

      await _drainPendingTimers(tester);
    });

    testWidgets('Undo brings the rule back and reschedules it', (tester) async {
      final plugin = await pumpEditForm(tester);
      await tester.tap(find.byTooltip('Delete reminder'));
      await _realWait(tester);

      // Let the snackbar finish sliding in before tapping its action.
      await _settle(tester, frames: 20);
      await tester.tap(find.text('Undo'));
      await _realWait(tester);

      expect((await storedRule()).deletedAt, isNull);
      expect(
        plugin.scheduledIds,
        contains(NotificationService.reminderNotificationId(_ruleId)),
      );

      await _drainPendingTimers(tester);
    });
  });
}
