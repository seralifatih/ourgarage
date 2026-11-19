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
import 'package:ourgarage/services/review_prompt_service.dart';

import '../../support/fake_notification_plugin.dart';

/// Audit #7: saving a service record says what happened, including the
/// reminder it quietly reset.

const _vehicleId = 'v1';

class _SilentReviewPrompt extends ReviewPromptService {
  @override
  Future<bool> maybeRequestReview(ReviewTrigger trigger) async => false;
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
  group('serviceSavedMessage', () {
    ReminderReset reset(String nextDue) =>
        ReminderReset(wasDue: false, typeLabel: 'Oil change', nextDue: nextDue);

    test('no matching reminder', () {
      expect(serviceSavedMessage(null), 'Service saved');
    });

    test('names the reset reminder and when it is next due', () {
      expect(
        serviceSavedMessage(reset('Due May 2027')),
        'Service saved. Oil change reminder reset — next due May 2027.',
      );
      expect(
        serviceSavedMessage(reset('Due in 8000 km')),
        'Service saved. Oil change reminder reset — next due in 8000 km.',
      );
    });

    test('leaves out a next-due phrase that would read badly', () {
      expect(
        serviceSavedMessage(reset('No schedule')),
        'Service saved. Oil change reminder reset.',
      );
      expect(
        serviceSavedMessage(reset('Due now')),
        'Service saved. Oil change reminder reset.',
      );
    });
  });

  group('after saving', () {
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
              odometer: const Value(12000),
              odometerUnit: 'km',
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    tearDown(() async {
      DatabaseHolder.overrideWith(null);
      await db.close();
    });

    Future<void> pumpAndSave(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/base',
        routes: [
          GoRoute(
            path: '/base',
            builder: (_, _) => const Scaffold(body: Text('vehicle detail')),
          ),
          GoRoute(
            path: '/form',
            builder: (_, _) =>
                const ServiceRecordFormScreen(vehicleId: _vehicleId),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            premiumStatusProvider.overrideWith((ref) => false),
            fakeNotificationServiceOverride(),
            reviewPromptServiceProvider.overrideWithValue(
              _SilentReviewPrompt(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      router.push('/form');
      await _settle(tester);

      final save = find.widgetWithText(FilledButton, 'Add record');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await _settle(tester, frames: 20);
    }

    testWidgets('with no matching reminder: "Service saved"', (tester) async {
      await pumpAndSave(tester);

      expect(find.text('vehicle detail'), findsOneWidget);
      expect(find.text('Service saved'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('with a matching reminder: says it was reset and when next', (
      tester,
    ) async {
      await db
          .into(db.reminderRules)
          .insert(
            ReminderRulesCompanion.insert(
              id: 'r1',
              vehicleId: _vehicleId,
              type: ServiceType.oilChange.name,
              intervalMonths: const Value(6),
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      await pumpAndSave(tester);

      expect(
        find.textContaining('Service saved. Oil change reminder reset'),
        findsOneWidget,
      );
      expect(find.textContaining('next due'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });
}
