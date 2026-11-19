import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/core/widgets/readable_width.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/data/repositories/premium_status_provider.dart';
import 'package:ourgarage/features/paywall/paywall_screen.dart';
import 'package:ourgarage/features/reminders/reminder_rule_form_screen.dart';
import 'package:ourgarage/features/reminders/update_odometers_screen.dart';
import 'package:ourgarage/features/reminders/vehicle_reminders_list_screen.dart';
import 'package:ourgarage/features/service_records/service_record_form_screen.dart';
import 'package:ourgarage/features/settings/settings_screen.dart';
import 'package:ourgarage/features/vehicles/vehicle_detail_screen.dart';
import 'package:ourgarage/features/vehicles/vehicle_form_screen.dart';
import 'package:ourgarage/services/review_prompt_service.dart';

import '../support/fake_notification_plugin.dart';
import '../support/fake_purchases_api.dart';

/// The screens changed for the state audit, laid out at iPad sizes (the test
/// device is an iPad on iOS 15) and a phone for contrast: nothing overflows,
/// and content stays a readable column, centred, instead of stretching to
/// 1366 points.

const _vehicleId = 'v1';

/// Logical sizes: iPad 9.7"/10.2" portrait, iPad Pro 12.9" portrait and
/// landscape, and an iPhone for contrast.
const _ipads = {
  'iPad 10.2 portrait': Size(810, 1080),
  'iPad Pro 12.9 portrait': Size(1024, 1366),
  'iPad Pro 12.9 landscape': Size(1366, 1024),
};
const _phone = Size(390, 844);

class _SilentReviewPrompt extends ReviewPromptService {
  @override
  Future<bool> maybeRequestReview(ReviewTrigger trigger) async => false;
}

Future<void> _pumpAt(WidgetTester tester, Size size, Widget screen) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        premiumStatusProvider.overrideWith((ref) => true),
        fakeNotificationServiceOverride(
          FakeNotificationPlugin()..enabled = false,
        ),
        fakePurchaseServiceOverride(FakePurchasesApi()),
        reviewPromptServiceProvider.overrideWithValue(_SilentReviewPrompt()),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

/// [finder]'s first match is at most [maxWidth] wide and centred on [size].
void _expectReadableColumn(
  WidgetTester tester,
  Finder finder,
  Size size, {
  double maxWidth = kReadableWidth,
}) {
  final rect = tester.getRect(finder.first);
  expect(rect.width, lessThanOrEqualTo(maxWidth + 0.5));
  expect(
    (rect.center.dx - size.width / 2).abs(),
    lessThan(1),
    reason: 'centred on the screen',
  );
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
            odometer: const Value(128500),
            odometerUnit: 'km',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.reminderRules)
        .insert(
          ReminderRulesCompanion.insert(
            id: 'r1',
            vehicleId: _vehicleId,
            type: ServiceType.oilChange.name,
            intervalMonths: const Value(6),
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    DatabaseHolder.overrideWith(null);
    await db.close();
  });

  for (final MapEntry(key: name, value: size) in _ipads.entries) {
    group(name, () {
      testWidgets('add vehicle form', (tester) async {
        await _pumpAt(tester, size, const VehicleFormScreen());
        expect(tester.takeException(), isNull);
        _expectReadableColumn(
          tester,
          find.widgetWithText(TextFormField, 'Nickname'),
          size,
        );
        await _drainPendingTimers(tester);
      });

      testWidgets('add service form', (tester) async {
        await _pumpAt(
          tester,
          size,
          const ServiceRecordFormScreen(vehicleId: _vehicleId),
        );
        expect(tester.takeException(), isNull);
        _expectReadableColumn(
          tester,
          find.widgetWithText(TextFormField, 'Notes'),
          size,
        );
        await _drainPendingTimers(tester);
      });

      testWidgets('edit reminder form', (tester) async {
        await _pumpAt(
          tester,
          size,
          const ReminderRuleFormScreen(vehicleId: _vehicleId, ruleId: 'r1'),
        );
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Delete reminder'), findsOneWidget);
        _expectReadableColumn(
          tester,
          find.widgetWithText(TextFormField, 'Interval (months)'),
          size,
        );
        await _drainPendingTimers(tester);
      });

      testWidgets('reminders list with the notifications-off banner', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          size,
          const VehicleRemindersListScreen(vehicleId: _vehicleId),
        );
        expect(tester.takeException(), isNull);
        _expectReadableColumn(
          tester,
          find.ancestor(
            of: find.textContaining('Notifications are off'),
            matching: find.byType(Material),
          ),
          size,
        );
        _expectReadableColumn(tester, find.byType(ListTile), size);
        await _drainPendingTimers(tester);
      });

      testWidgets('update odometers', (tester) async {
        await _pumpAt(tester, size, const UpdateOdometersScreen());
        expect(tester.takeException(), isNull);
        _expectReadableColumn(
          tester,
          find.widgetWithText(TextFormField, 'Blue Civic'),
          size,
        );
        await _drainPendingTimers(tester);
      });

      testWidgets('vehicle detail keeps one centred column', (tester) async {
        await _pumpAt(
          tester,
          size,
          const VehicleDetailScreen(vehicleId: _vehicleId),
        );
        expect(tester.takeException(), isNull);
        final divider = tester.getRect(find.byType(Divider).first);
        expect(divider.width, lessThanOrEqualTo(kReadableWidth + 0.5));
        expect((divider.center.dx - size.width / 2).abs(), lessThan(1));
        await _drainPendingTimers(tester);
      });

      testWidgets('settings, with the Notifications row', (tester) async {
        await _pumpAt(tester, size, const SettingsScreen());
        expect(tester.takeException(), isNull);
        expect(find.text('Notifications'), findsOneWidget);
        _expectReadableColumn(
          tester,
          find.ancestor(
            of: find.text('Notifications'),
            matching: find.byType(ListTile),
          ),
          size,
        );
        await _drainPendingTimers(tester);
      });

      testWidgets('paywall', (tester) async {
        await _pumpAt(tester, size, const PaywallScreen());
        expect(tester.takeException(), isNull);
        _expectReadableColumn(
          tester,
          find.widgetWithText(FilledButton, 'Unlock'),
          size,
          maxWidth: 720,
        );
        await _drainPendingTimers(tester);
      });
    });
  }

  group('phone', () {
    testWidgets('forms keep their normal 16pt margins', (tester) async {
      await _pumpAt(tester, _phone, const VehicleFormScreen());
      expect(tester.takeException(), isNull);
      final field = tester.getRect(
        find.widgetWithText(TextFormField, 'Nickname'),
      );
      expect(field.left, 16);
      expect(field.right, _phone.width - 16);
      await _drainPendingTimers(tester);
    });
  });
}
