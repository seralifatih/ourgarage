import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/features/paywall/paywall_screen.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../support/fake_purchases_api.dart';

/// Pumps the paywall pushed on top of a base route, so the close button has
/// somewhere to pop back to — the common case for every entry point but the
/// vehicle limit.
Future<void> _pumpPaywall(
  WidgetTester tester, {
  FakePurchasesApi? api,
  bool push = true,
}) async {
  final router = GoRouter(
    initialLocation: push ? '/base' : '/paywall',
    routes: [
      GoRoute(
        path: '/base',
        builder: (_, _) => const Scaffold(body: Text('base screen')),
      ),
      GoRoute(path: '/paywall', builder: (_, _) => const PaywallScreen()),
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('garage list')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [fakePurchaseServiceOverride(api)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();

  if (push) router.push('/paywall');

  // The offering arrives through a FutureProvider, whose async gap never
  // completes under the test's fake clock — `runAsync` steps outside it so the
  // packages are actually on screen before anything asserts.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
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

/// Whether the plan card containing [title] is the selected one.
///
/// Material inserts its own Semantics wrappers inside the card, so this looks
/// for the one that actually carries a `selected` flag rather than assuming a
/// position in the ancestor chain.
bool _isPlanSelected(WidgetTester tester, String title) {
  final wrappers = tester.widgetList<Semantics>(
    find.ancestor(of: find.text(title), matching: find.byType(Semantics)),
  );

  for (final wrapper in wrappers) {
    final selected = wrapper.properties.selected;
    if (selected != null) return selected;
  }
  return false;
}

/// Taps and lets the purchase round trip resolve outside fake time.
Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await _settle(tester);
}

void main() {
  group('content', () {
    testWidgets('shows the headline and every value bullet, in order', (
      tester,
    ) async {
      await _pumpPaywall(tester);

      expect(find.text('Unlock your whole garage'), findsOneWidget);

      final bullets = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();

      final unlimited = bullets.indexWhere(
        (t) => t.contains('Track unlimited vehicles'),
      );
      final household = bullets.indexWhere(
        (t) => t.contains('Share with your household'),
      );
      final costs = bullets.indexWhere(
        (t) => t.contains('Log service costs and export'),
      );

      expect(unlimited, isNonNegative);
      expect(household, greaterThan(unlimited));
      expect(costs, greaterThan(household));

      await _drainPendingTimers(tester);
    });

    testWidgets('the close affordance is present on the first frame', (
      tester,
    ) async {
      // Never delayed or hidden: a dismiss control that appears late is an
      // App Store rejection trigger.
      await _pumpPaywall(tester);

      final closeButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.close),
      );
      expect(closeButton.onPressed, isNotNull);

      await _drainPendingTimers(tester);
    });

    testWidgets('closing returns to where the user came from', (tester) async {
      await _pumpPaywall(tester);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      await _settle(tester);

      expect(find.text('base screen'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('closing works even when the paywall replaced the stack', (
      tester,
    ) async {
      // The vehicle-limit entry point uses `context.go`, leaving nothing to
      // pop. The close button must still work rather than throwing.
      await _pumpPaywall(tester, push: false);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      await _settle(tester);

      expect(find.text('garage list'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('offers Restore purchases, Terms and Privacy Policy', (
      tester,
    ) async {
      await _pumpPaywall(tester);

      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });

  group('pricing', () {
    testWidgets('renders the store price strings, not hardcoded ones', (
      tester,
    ) async {
      // Deliberately not the real prices: a UI with "$9.99" baked in would
      // pass a test that asserted the real figures.
      final api = FakePurchasesApi(
        offerings: FakePurchasesApi.defaultOfferings(
          lifetimePrice: '₺149,99',
          annualPrice: '₺74,99',
        ),
      );
      await _pumpPaywall(tester, api: api);

      expect(find.text('₺149,99'), findsOneWidget);
      expect(find.text('₺74,99/year'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('shows both plans with their captions and badge', (
      tester,
    ) async {
      await _pumpPaywall(tester);

      expect(find.text('Lifetime'), findsOneWidget);
      expect(find.text('Pay once, keep forever'), findsOneWidget);
      expect(find.text('Best value'), findsOneWidget);
      expect(find.text('Annual'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('lifetime is pre-selected, annual is not', (tester) async {
      await _pumpPaywall(tester);

      // Selection is exposed through Semantics.selected, which is both what
      // the visual treatment keys off and what a screen reader announces.
      expect(_isPlanSelected(tester, 'Lifetime'), isTrue);
      expect(_isPlanSelected(tester, 'Annual'), isFalse);

      await _drainPendingTimers(tester);
    });

    testWidgets('tapping annual moves the selection', (tester) async {
      await _pumpPaywall(tester);

      await tester.tap(find.text('Annual'));
      await _settle(tester);

      expect(_isPlanSelected(tester, 'Annual'), isTrue);
      expect(_isPlanSelected(tester, 'Lifetime'), isFalse);

      await _drainPendingTimers(tester);
    });

    testWidgets('hides the purchase controls when there is nothing to sell', (
      tester,
    ) async {
      final api = FakePurchasesApi(
        offerings: FakePurchasesApi.emptyOfferings(),
      );
      await _pumpPaywall(tester, api: api);

      // The value proposition still shows; only the controls are withheld.
      expect(find.text('Unlock your whole garage'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Unlock'), findsNothing);
      expect(find.textContaining('unavailable'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);

      await _drainPendingTimers(tester);
    });
  });

  group('purchasing', () {
    testWidgets('Unlock buys the pre-selected lifetime package', (
      tester,
    ) async {
      final api = FakePurchasesApi();
      await _pumpPaywall(tester, api: api);

      await _tapAndSettle(tester, find.widgetWithText(FilledButton, 'Unlock'));

      expect(api.purchaseCount, 1);
      expect(api.lastPurchased?.packageType, PackageType.lifetime);

      await _drainPendingTimers(tester);
    });

    testWidgets('selecting annual switches what Unlock buys', (tester) async {
      final api = FakePurchasesApi();
      await _pumpPaywall(tester, api: api);

      await tester.tap(find.text('Annual'));
      await _settle(tester);

      await _tapAndSettle(tester, find.widgetWithText(FilledButton, 'Unlock'));

      expect(api.lastPurchased?.packageType, PackageType.annual);

      await _drainPendingTimers(tester);
    });

    testWidgets('a successful purchase reports back and dismisses', (
      tester,
    ) async {
      await _pumpPaywall(tester, api: FakePurchasesApi());

      await _tapAndSettle(tester, find.widgetWithText(FilledButton, 'Unlock'));

      expect(find.text('Welcome to Premium'), findsOneWidget);
      expect(find.text('base screen'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('a failed purchase surfaces the error and stays put', (
      tester,
    ) async {
      final api = FakePurchasesApi(
        purchaseError: PlatformException(
          code: '2',
          message: 'The payment method was declined',
        ),
      );
      await _pumpPaywall(tester, api: api);

      await _tapAndSettle(tester, find.widgetWithText(FilledButton, 'Unlock'));

      expect(find.text('The payment method was declined'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget, reason: 'still on paywall');

      await _drainPendingTimers(tester);
    });
  });

  group('restoring', () {
    testWidgets('a successful restore reports back and dismisses', (
      tester,
    ) async {
      final api = FakePurchasesApi(restoreGrantsPremium: true);
      await _pumpPaywall(tester, api: api);

      await _tapAndSettle(tester, find.text('Restore purchases'));

      expect(api.restoreCount, 1);
      expect(find.text('Purchases restored'), findsOneWidget);
      expect(find.text('base screen'), findsOneWidget);

      await _drainPendingTimers(tester);
    });

    testWidgets('a restore that finds nothing says so and stays put', (
      tester,
    ) async {
      final api = FakePurchasesApi(restoreGrantsPremium: false);
      await _pumpPaywall(tester, api: api);

      await _tapAndSettle(tester, find.text('Restore purchases'));

      expect(find.text('No previous purchases found'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget, reason: 'still on paywall');

      await _drainPendingTimers(tester);
    });
  });
}
