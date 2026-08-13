import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/settings/settings_screen.dart';

import '../../support/fake_notification_plugin.dart';

Future<void> _pumpScreen(
  WidgetTester tester, {
  FakeNotificationPlugin? plugin,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [fakeNotificationServiceOverride(plugin)],
      child: const MaterialApp(home: SettingsScreen()),
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

Future<void> _tapTitle(WidgetTester tester, {int times = 5}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text('Settings'));
    await tester.pump();
  }
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

  Future<String> insertVehicle({String id = 'v1'}) async {
    await db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: id,
            nickname: 'Blue Civic',
            odometerUnit: 'mi',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
    return id;
  }

  testWidgets('debug section is hidden until the title is tapped 5 times', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.text('Debug: fire test reminder'), findsNothing);

    await _tapTitle(tester, times: 4);
    expect(find.text('Debug: fire test reminder'), findsNothing);

    await tester.tap(find.text('Settings'));
    await _settle(tester);
    expect(find.text('Debug: fire test reminder'), findsOneWidget);
    expect(find.text('Debug: print pending notifications'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  testWidgets('firing a test reminder with no vehicle shows an error', (
    tester,
  ) async {
    await _pumpScreen(tester);
    await _tapTitle(tester);
    await _settle(tester);

    await tester.tap(find.text('Debug: fire test reminder'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _settle(tester);

    expect(
      find.text('No vehicle exists to attach a test reminder to'),
      findsOneWidget,
    );

    await _drainPendingTimers(tester);
  });

  testWidgets(
    'firing a test reminder schedules through the real notification service',
    (tester) async {
      final plugin = FakeNotificationPlugin();
      await insertVehicle();
      await _pumpScreen(tester, plugin: plugin);
      await _tapTitle(tester);
      await _settle(tester);

      await tester.tap(find.text('Debug: fire test reminder'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _settle(tester);

      expect(plugin.scheduledIds, hasLength(1));
      expect(
        find.textContaining('Test reminder scheduled for'),
        findsOneWidget,
      );

      // The rule only existed to carry a real id through the scheduling path;
      // it must not linger as a visible reminder on the vehicle.
      final rules = await db.select(db.reminderRules).get();
      expect(rules, hasLength(1));
      expect(rules.single.deletedAt, isNotNull);

      await _drainPendingTimers(tester);
    },
  );

  testWidgets('printing pending notifications reports the current count', (
    tester,
  ) async {
    final plugin = FakeNotificationPlugin();
    await insertVehicle();
    await _pumpScreen(tester, plugin: plugin);
    await _tapTitle(tester);
    await _settle(tester);

    await tester.tap(find.text('Debug: fire test reminder'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _settle(tester);

    await tester.tap(find.text('Debug: print pending notifications'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _settle(tester);

    expect(find.text('1 pending — see console'), findsOneWidget);

    await _drainPendingTimers(tester);
  });
}
