import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/paywall/paywall_screen.dart';
import 'package:ourgarage/features/paywall/purchase_errors.dart';
import 'package:ourgarage/features/settings/settings_screen.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../support/fake_notification_plugin.dart';
import '../../support/fake_purchases_api.dart';

/// Audit #12: every purchase/restore failure is reported, with a way to
/// reach support; Ask to Buy reads as "waiting", not as a failure.

PlatformException _rcError(PurchasesErrorCode code, [String? message]) =>
    PlatformException(code: '${code.index}', message: message);

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _realWait(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await _settle(tester);
}

Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Future<void> _pumpPaywall(WidgetTester tester, FakePurchasesApi api) async {
  final router = GoRouter(
    initialLocation: '/base',
    routes: [
      GoRoute(
        path: '/base',
        builder: (_, _) => const Scaffold(body: Text('base screen')),
      ),
      GoRoute(path: '/paywall', builder: (_, _) => const PaywallScreen()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [fakePurchaseServiceOverride(api)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  router.push('/paywall');
  await _realWait(tester);
}

void main() {
  group('purchaseErrorMessage', () {
    test('Ask to Buy reads as waiting for approval', () {
      final error = _rcError(PurchasesErrorCode.paymentPendingError);
      expect(isPurchasePending(error), isTrue);
      expect(
        purchaseErrorMessage(error, restoring: false),
        startsWith('Waiting for approval'),
      );
    });

    test('common store failures get a plain sentence of their own', () {
      expect(
        purchaseErrorMessage(
          _rcError(PurchasesErrorCode.networkError, 'NSURLErrorDomain -1009'),
          restoring: false,
        ),
        contains('Check your connection'),
      );
      expect(
        purchaseErrorMessage(
          _rcError(PurchasesErrorCode.purchaseNotAllowedError),
          restoring: false,
        ),
        contains('Screen Time'),
      );
      expect(
        purchaseErrorMessage(
          _rcError(PurchasesErrorCode.productAlreadyPurchasedError),
          restoring: false,
        ),
        contains('Restore purchases'),
      );
    });

    test('anything else keeps the store message when there is one', () {
      expect(
        purchaseErrorMessage(
          _rcError(PurchasesErrorCode.storeProblemError, 'Store said no'),
          restoring: false,
        ),
        'Store said no',
      );
    });

    test('falls back to a generic sentence, for purchase and restore', () {
      expect(
        purchaseErrorMessage(StateError('boom'), restoring: false),
        'The purchase didn’t go through. Please try again.',
      );
      expect(
        purchaseErrorMessage(StateError('boom'), restoring: true),
        'Could not restore purchases. Please try again.',
      );
    });

    test('a non-numeric error code does not throw', () {
      final error = PlatformException(code: 'channel-error');
      expect(isPurchasePending(error), isFalse);
      expect(
        purchaseErrorMessage(error, restoring: false),
        'The purchase didn’t go through. Please try again.',
      );
    });
  });

  group('paywall', () {
    testWidgets('Ask to Buy says it is waiting and stays on the paywall', (
      tester,
    ) async {
      final api = FakePurchasesApi(
        purchaseError: _rcError(PurchasesErrorCode.paymentPendingError),
      );
      await _pumpPaywall(tester, api);

      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await _realWait(tester);

      expect(find.text(purchasePendingMessage), findsOneWidget);
      expect(find.text('Message me'), findsNothing, reason: 'not an error');
      expect(find.text('Unlock'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('an unexpected failure is reported with Message me', (
      tester,
    ) async {
      // Used to be rethrown with no message at all.
      final api = FakePurchasesApi(purchaseError: StateError('boom'));
      await _pumpPaywall(tester, api);

      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await _realWait(tester);

      expect(
        find.text('The purchase didn’t go through. Please try again.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SnackBarAction, 'Message me'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _drainPendingTimers(tester);
    });

    testWidgets('a store failure is reported with Message me', (tester) async {
      final api = FakePurchasesApi(
        purchaseError: _rcError(PurchasesErrorCode.networkError),
      );
      await _pumpPaywall(tester, api);

      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await _realWait(tester);

      expect(find.textContaining('Check your connection'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Message me'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('a failed restore is reported with Message me', (tester) async {
      final api = FakePurchasesApi(restoreError: StateError('boom'));
      await _pumpPaywall(tester, api);

      await tester.tap(find.text('Restore purchases'));
      await _realWait(tester);

      expect(
        find.text('Could not restore purchases. Please try again.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SnackBarAction, 'Message me'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('no products to sell also offers Message me', (tester) async {
      final api = FakePurchasesApi(
        offerings: FakePurchasesApi.emptyOfferings(),
      );
      await _pumpPaywall(tester, api);

      expect(find.text('Purchases are unavailable right now.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Message me'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });

  group('Settings restore', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      DatabaseHolder.overrideWith(db);
    });

    tearDown(() async {
      DatabaseHolder.overrideWith(null);
      await db.close();
    });

    testWidgets('a failure of any kind is reported with Message me', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fakeNotificationServiceOverride(),
            fakePurchaseServiceOverride(
              FakePurchasesApi(restoreError: StateError('boom')),
            ),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await _realWait(tester);

      await tester.tap(find.text('Restore purchases'));
      await _realWait(tester);

      expect(
        find.text('Could not restore purchases. Please try again.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SnackBarAction, 'Message me'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _drainPendingTimers(tester);
    });
  });
}
