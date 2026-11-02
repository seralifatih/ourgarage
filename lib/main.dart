import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/repositories/premium_status_provider.dart';
import 'services/auth_service_provider.dart';
import 'services/purchase_service_provider.dart';
import 'services/revenuecat_identity_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restores any existing session from secure storage. This does NOT prompt
  // anyone to sign in — auth is only ever requested when the user taps "Share
  // with household", and a free, local-only user never gets here with keys
  // configured at all.
  //
  // Skipped entirely when the project keys are absent, which is how tests and
  // any local-only build run: the app then works exactly as it does for a free
  // user, with sharing unavailable rather than crashing on a null client.
  if (AppConstants.supabaseUrl.isNotEmpty &&
      AppConstants.supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
  }

  // A single container, configured before the first frame and then handed to
  // the widget tree, so `premiumStatusProvider` is already seeded with the
  // real entitlement state on first build rather than flashing un-entitled.
  final container = ProviderContainer();
  await container
      .read(purchaseServiceProvider)
      .configure(AppConstants.revenueCatApiKey);

  // Started only now, after RevenueCat is configured: `identify`/`resetIdentity`
  // are no-ops until then, so starting the bridge earlier would silently miss
  // an already-restored Supabase session. Read once, purely for the side
  // effect of subscribing — see the provider's own doc comment for why this
  // exists at all.
  container.read(revenueCatIdentitySyncProvider);

  // Not awaited: the first frame must not wait on a network round-trip.
  unawaited(_recoverMissedPurchases(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OurGarageApp(),
    ),
  );
}

/// Picks up purchases that never reached RevenueCat while its key was
/// invalid, then refreshes premium status so the UI updates straight away.
Future<void> _recoverMissedPurchases(ProviderContainer container) async {
  try {
    // Wait for the restored session to resolve, so the initial identify /
    // resetIdentity is queued ahead of the receipt sync rather than after it.
    // Throws when Supabase isn't configured: no identity will ever be
    // applied, so syncing anonymously is correct.
    await container
        .read(currentUserIdProvider.future)
        .timeout(const Duration(seconds: 10));
  } catch (_) {}

  try {
    final unlocked = await container
        .read(purchaseServiceProvider)
        .syncPurchasesOnce();
    if (unlocked) container.invalidate(premiumStatusProvider);
  } catch (error) {
    debugPrint('Purchase recovery failed: $error');
  }
}
