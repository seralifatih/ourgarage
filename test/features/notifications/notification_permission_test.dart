import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/notifications/notification_permission.dart';
import 'package:ourgarage/features/reminders/vehicle_reminders_list_screen.dart';
import 'package:ourgarage/features/settings/settings_screen.dart';

import '../../support/fake_notification_plugin.dart';
import '../../support/fake_purchases_api.dart';

/// Audit #2: a declined notification permission is visible — a
/// "Notifications" row in Settings, and a dismissible banner above a
/// vehicle's reminders — with a way to turn notifications back on.

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  FakeNotificationPlugin plugin,
) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeNotificationServiceOverride(plugin),
        fakePurchaseServiceOverride(FakePurchasesApi()),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await _settle(tester);
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

  group('Settings row', () {
    testWidgets('reads On when notifications are allowed', (tester) async {
      await _pump(tester, const SettingsScreen(), FakeNotificationPlugin());

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Turn on'), findsNothing);

      await _drainPendingTimers(tester);
    });

    testWidgets('reads Off with a Turn on button when they are not', (
      tester,
    ) async {
      final plugin = FakeNotificationPlugin()..enabled = false;
      await _pump(tester, const SettingsScreen(), plugin);

      expect(find.text('Off — reminders can’t alert you'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Turn on'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('is hidden when the platform cannot say', (tester) async {
      final plugin = FakeNotificationPlugin()..enabled = null;
      await _pump(tester, const SettingsScreen(), plugin);

      expect(find.text('Notifications'), findsNothing);

      await _drainPendingTimers(tester);
    });

    testWidgets('Turn on asks first; granted, it flips to On without '
        'opening Settings', (tester) async {
      final plugin = FakeNotificationPlugin()..enabled = false;
      await _pump(tester, const SettingsScreen(), plugin);

      await tester.tap(find.widgetWithText(TextButton, 'Turn on'));
      await _settle(tester);

      expect(plugin.requestCount, 1);
      expect(plugin.openSettingsCount, 0);
      expect(find.text('On'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('a refusal offers the Settings app instead of opening it', (
      tester,
    ) async {
      // iOS answers false both right after "Don't Allow" and, with no
      // prompt, after an earlier refusal; neither should yank the user into
      // Settings unasked.
      final plugin = FakeNotificationPlugin()
        ..enabled = false
        ..requestResult = false;
      await _pump(tester, const SettingsScreen(), plugin);

      await tester.tap(find.widgetWithText(TextButton, 'Turn on'));
      await _settle(tester);

      expect(plugin.requestCount, 1);
      expect(plugin.openSettingsCount, 0);
      expect(
        find.text('Notifications are off. You can turn them on in Settings.'),
        findsOneWidget,
      );

      await _settle(tester, frames: 20);
      await tester.tap(find.text('Open Settings'));
      await _settle(tester);

      expect(plugin.openSettingsCount, 1);

      await _drainPendingTimers(tester);
    });

    testWidgets('the row stays put while a resume re-reads the status', (
      tester,
    ) async {
      final plugin = FakeNotificationPlugin()..enabled = false;
      await _pump(tester, const SettingsScreen(), plugin);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      container.invalidate(notificationPermissionProvider);
      await tester.pump();

      expect(find.text('Off — reminders can’t alert you'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });

  group('reminders banner', () {
    const screen = VehicleRemindersListScreen(vehicleId: 'v1');
    const bannerText =
        'Notifications are off, so these reminders can’t alert '
        'you.';

    testWidgets('not shown while notifications are on', (tester) async {
      await _pump(tester, screen, FakeNotificationPlugin());

      expect(find.text(bannerText), findsNothing);

      await _drainPendingTimers(tester);
    });

    testWidgets('shown while they are off, and can be dismissed', (
      tester,
    ) async {
      final plugin = FakeNotificationPlugin()..enabled = false;
      await _pump(tester, screen, plugin);

      expect(find.text(bannerText), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await _settle(tester);

      expect(find.text(bannerText), findsNothing);

      await _drainPendingTimers(tester);
    });

    testWidgets('Turn on that is granted removes the banner', (tester) async {
      final plugin = FakeNotificationPlugin()..enabled = false;
      await _pump(tester, screen, plugin);

      await tester.tap(find.widgetWithText(TextButton, 'Turn on'));
      await _settle(tester);

      expect(find.text(bannerText), findsNothing);

      await _drainPendingTimers(tester);
    });
  });
}
