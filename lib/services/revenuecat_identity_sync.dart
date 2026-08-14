import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service_provider.dart';
import 'purchase_service.dart';
import 'purchase_service_provider.dart';

part 'revenuecat_identity_sync.g.dart';

/// Keeps RevenueCat's customer identity in step with the Supabase session.
///
/// [AuthService] and [PurchaseService] deliberately know nothing about each
/// other — this is the one place that bridges them, so neither has to import
/// the other's concerns.
///
/// Without this, RevenueCat runs under its own anonymous, device-generated
/// `appUserID` forever: [PurchaseService.configure] happens at app start,
/// before any sign-in, so a brand-new customer starts anonymous regardless of
/// whether they ever create an account. The RevenueCat webhook that grants
/// household premium on purchase keys off `app_user_id`, expecting it to be
/// the Supabase user id — if it never is, the webhook can never match a
/// purchase to a household, and every real transaction silently fails to
/// unlock anything.
///
/// [currentUserIdProvider] already fires with the current value on
/// subscription (Supabase's `onAuthStateChange` replays its last state), so
/// listening to it here covers both an app launch that restores an existing
/// session and a live sign-in/sign-out with the same code path.
class RevenueCatIdentitySync {
  RevenueCatIdentitySync(this._purchases);

  final PurchaseService _purchases;

  Future<void> onUserIdChanged(String? userId) async {
    if (userId != null) {
      await _purchases.identify(userId);
    } else {
      await _purchases.resetIdentity();
    }
  }
}

/// Starts the bridge. Read once, eagerly, from `main()` — its return value is
/// never used, only its side effect of subscribing to auth state for the
/// process lifetime.
@Riverpod(keepAlive: true)
RevenueCatIdentitySync revenueCatIdentitySync(Ref ref) {
  final sync = RevenueCatIdentitySync(ref.watch(purchaseServiceProvider));

  // `ref.listen` rather than folding this into `build`: the provider's own
  // return value must stay a plain, stable `RevenueCatIdentitySync` that
  // nothing needs to rebuild around, while the auth stream can fire many
  // times over the app's life.
  //
  // `fireImmediately: true` is load-bearing. `ref.listen` defaults to only
  // firing on *changes* — without this, a session already restored by
  // `Supabase.initialize()` before this provider is ever read would never
  // reach RevenueCat at all, since there is no "change" to observe, only an
  // already-settled value. `currentUserIdProvider` is seeded with exactly
  // that restored session (see its own doc comment), so this is precisely the
  // case this bridge exists to cover.
  final subscription = ref.listen(
    currentUserIdProvider,
    (previous, next) {
      // `next.asData` is also null while `next` is `AsyncLoading` — skip
      // that case rather than reading it as "signed out", or every app
      // launch would fire a spurious `resetIdentity()` before the restored
      // session (or lack of one) has actually resolved.
      final data = next.asData;
      if (data == null) return;

      unawaited(sync.onUserIdChanged(data.value));
    },
    fireImmediately: true,
  );
  ref.onDispose(subscription.close);

  return sync;
}
