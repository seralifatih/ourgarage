import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/services/revenuecat_identity_sync.dart';

import '../support/fake_auth_backend.dart';
import '../support/fake_purchases_api.dart';

void main() {
  group('RevenueCatIdentitySync', () {
    testWidgets(
      'a session already restored at boot is identified immediately — no '
      'live sign-in event needed',
      (tester) async {
        // Mirrors main(): Supabase.initialize() restores a session before
        // PurchaseService is even configured, so there is no "change" for
        // ref.listen to observe, only an already-settled value. This is the
        // exact scenario `fireImmediately: true` exists for.
        final auth = FakeAuthBackend(userId: 'user-1', alreadySignedIn: true);
        final purchases = FakePurchasesApi();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              fakeAuthServiceOverride(auth),
              fakePurchaseServiceOverride(purchases),
            ],
            child: const _BridgeReader(),
          ),
        );
        await tester.pumpAndSettle();

        expect(purchases.loggedInAs, ['user-1']);
      },
    );

    testWidgets('a live sign-in triggers identify with the new user id', (
      tester,
    ) async {
      final auth = FakeAuthBackend(userId: 'user-2');
      final purchases = FakePurchasesApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fakeAuthServiceOverride(auth),
            fakePurchaseServiceOverride(purchases),
          ],
          child: const _BridgeReader(),
        ),
      );
      await tester.pumpAndSettle();
      expect(purchases.loggedInAs, isEmpty, reason: 'not signed in yet');

      await auth.signInWithAppleIdToken(idToken: 'x', rawNonce: 'y');
      await tester.pumpAndSettle();

      expect(purchases.loggedInAs, ['user-2']);
    });

    testWidgets('signing out triggers resetIdentity', (tester) async {
      final auth = FakeAuthBackend(userId: 'user-1', alreadySignedIn: true);
      final purchases = FakePurchasesApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fakeAuthServiceOverride(auth),
            fakePurchaseServiceOverride(purchases),
          ],
          child: const _BridgeReader(),
        ),
      );
      await tester.pumpAndSettle();
      expect(purchases.loggedInAs, ['user-1']);

      await auth.signOut();
      await tester.pumpAndSettle();

      expect(purchases.logOutCount, 1);
    });
  });
}

/// Reads [revenueCatIdentitySyncProvider] the same way `main()` does — for
/// its side effect, not its value — so the bridge starts under a real widget
/// tree and gets pumped by [WidgetTester] like production code does.
class _BridgeReader extends ConsumerWidget {
  const _BridgeReader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(revenueCatIdentitySyncProvider);
    return const SizedBox.shrink();
  }
}
