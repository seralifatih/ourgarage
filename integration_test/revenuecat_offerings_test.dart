// Diagnostic check for the "getOfferings failed: CONFIGURATION_ERROR" issue
// (see APP_STORE_SUBMISSION.md, section 6): configures the real RevenueCat
// SDK against the real App Store sandbox and reports whether the products
// come back. Run on a real simulator/device — the sandbox network call
// behaves the same on a simulator as on a device, only the purchase sheet
// itself needs a physical device.
//
// Run with:
//   flutter test integration_test/revenuecat_offerings_test.dart \
//     --dart-define=REVENUECAT_API_KEY=appl_xxx -d <simulator-id>
//
// Read the result from the test output, not from pass/fail: the test always
// passes (so it doesn't block CI on a store-side hiccup) and instead prints a
// clear PASS/FAIL verdict line for a human to read in the Codemagic log.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:ourgarage/core/constants.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RevenueCat getOfferings returns the configured products', (
    tester,
  ) async {
    const apiKey = String.fromEnvironment('REVENUECAT_API_KEY');

    if (apiKey.isEmpty) {
      // ignore: avoid_print
      print(
        'RESULT: SKIP — no REVENUECAT_API_KEY passed via --dart-define',
      );
      return;
    }

    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(apiKey));

    Offerings? offerings;
    Object? failure;
    try {
      offerings = await Purchases.getOfferings();
    } catch (error) {
      failure = error;
    }

    if (failure != null) {
      // ignore: avoid_print
      print('RESULT: FAIL — getOfferings threw: $failure');
      return;
    }

    final current = offerings?.current;
    final lifetime = current?.availablePackages
        .where((p) => p.storeProduct.identifier == AppConstants.lifetimeProductId)
        .toList();
    final annual = current?.availablePackages
        .where((p) => p.storeProduct.identifier == AppConstants.annualProductId)
        .toList();

    // ignore: avoid_print
    print('--- RevenueCat offerings diagnostic ---');
    // ignore: avoid_print
    print('Current offering: ${current?.identifier ?? "NONE"}');
    // ignore: avoid_print
    print(
      'All offerings returned: ${offerings?.all.keys.toList() ?? "NONE"}',
    );
    // ignore: avoid_print
    print(
      'Packages in current offering: '
      '${current?.availablePackages.map((p) => p.storeProduct.identifier).toList() ?? "NONE"}',
    );

    final lifetimeOk = lifetime != null && lifetime.isNotEmpty;
    final annualOk = annual != null && annual.isNotEmpty;

    if (lifetimeOk) {
      // ignore: avoid_print
      print(
        'Lifetime product: FOUND — price ${lifetime.first.storeProduct.priceString}',
      );
    } else {
      // ignore: avoid_print
      print(
        'Lifetime product: MISSING (expected id "${AppConstants.lifetimeProductId}")',
      );
    }

    if (annualOk) {
      // ignore: avoid_print
      print(
        'Annual product: FOUND — price ${annual.first.storeProduct.priceString}',
      );
    } else {
      // ignore: avoid_print
      print(
        'Annual product: MISSING (expected id "${AppConstants.annualProductId}")',
      );
    }

    if (lifetimeOk && annualOk) {
      // ignore: avoid_print
      print('RESULT: PASS — both products resolved from the App Store.');
    } else {
      // ignore: avoid_print
      print(
        'RESULT: FAIL — one or both products did not come back. This is '
        'the CONFIGURATION_ERROR / "Purchases are unavailable" bug. Check '
        'Agreements/Tax/Banking status and the RevenueCat <-> App Store '
        'Connect product mapping.',
      );
    }
  });
}
