import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/constants.dart';

/// The slice of `purchases_flutter` this app actually uses.
///
/// [PurchaseService] depends on this rather than the static [Purchases] class
/// so the entitlement logic can be tested: every RevenueCat entry point is a
/// static that talks to a method channel, which under the test runner has no
/// implementation to talk to. An interface is the only seam that works — the
/// same reason [NotificationPlugin] exists.
abstract interface class PurchasesApi {
  Future<void> configure(String apiKey);

  Future<Offerings> getOfferings();

  Future<CustomerInfo> purchase(Package package);

  Future<CustomerInfo> restorePurchases();

  /// Attaches [appUserId] to the current RevenueCat customer, merging in
  /// whatever was purchased anonymously before this was ever called — RevenueCat
  /// aliases the pre-login anonymous ID onto [appUserId] the first time it sees
  /// that identifier. Returns the resulting [CustomerInfo], reflecting any
  /// merged entitlement.
  Future<CustomerInfo> logIn(String appUserId);

  /// Detaches the current identity, reverting to a fresh anonymous customer.
  /// Returns that new (unentitled) customer's [CustomerInfo].
  Future<CustomerInfo> logOut();

  /// Fires with the latest [CustomerInfo] whenever it changes, and once
  /// immediately with the current value if one is already known.
  void addCustomerInfoUpdateListener(void Function(CustomerInfo) listener);

  void removeCustomerInfoUpdateListener(void Function(CustomerInfo) listener);
}

/// [PurchasesApi] backed by the real RevenueCat SDK.
class RevenueCatPurchasesApi implements PurchasesApi {
  const RevenueCatPurchasesApi();

  @override
  Future<void> configure(String apiKey) {
    return Purchases.configure(PurchasesConfiguration(apiKey));
  }

  @override
  Future<Offerings> getOfferings() => Purchases.getOfferings();

  @override
  Future<CustomerInfo> purchase(Package package) async {
    // `Purchases.purchasePackage` is deprecated in favour of the params form.
    final result = await Purchases.purchase(PurchaseParams.package(package));
    return result.customerInfo;
  }

  @override
  Future<CustomerInfo> restorePurchases() => Purchases.restorePurchases();

  @override
  Future<CustomerInfo> logIn(String appUserId) async {
    final result = await Purchases.logIn(appUserId);
    return result.customerInfo;
  }

  @override
  Future<CustomerInfo> logOut() => Purchases.logOut();

  @override
  void addCustomerInfoUpdateListener(void Function(CustomerInfo) listener) {
    Purchases.addCustomerInfoUpdateListener(listener);
  }

  @override
  void removeCustomerInfoUpdateListener(void Function(CustomerInfo) listener) {
    Purchases.removeCustomerInfoUpdateListener(listener);
  }
}

/// Wraps RevenueCat for the two things this app sells: a lifetime unlock
/// ([AppConstants.lifetimeProductId]) and an annual subscription
/// ([AppConstants.annualProductId]). Both grant
/// [AppConstants.premiumEntitlementId], so nothing outside this file needs to
/// know which one a given user bought.
///
/// Deliberately knows nothing about Riverpod or the UI: it exposes
/// [isPremiumStream] and callers decide what to do with it.
class PurchaseService {
  PurchaseService([this._api = const RevenueCatPurchasesApi()]);

  final PurchasesApi _api;

  final _entitlementController = StreamController<bool>.broadcast();

  /// Last known entitlement state, replayed to new listeners.
  ///
  /// A broadcast stream drops anything emitted before someone subscribes, and
  /// RevenueCat pushes the first [CustomerInfo] as soon as [configure] lands —
  /// typically before any widget is watching. Without this, a subscriber that
  /// arrives late would sit on the seed value until the *next* store event,
  /// which for an existing premium user may never come in that session.
  bool _isPremium = false;

  bool get isPremium => _isPremium;

  bool _configured = false;

  /// Whether the SDK is configured and usable. False when no API key was
  /// supplied at build time.
  bool get isConfigured => _configured;

  void Function(CustomerInfo)? _listener;

  /// Entitlement state over time, starting with the current value.
  Stream<bool> get isPremiumStream async* {
    yield _isPremium;
    yield* _entitlementController.stream;
  }

  /// Configures the SDK and starts listening for entitlement changes.
  ///
  /// A blank [apiKey] is a no-op: the app runs un-entitled rather than
  /// crashing, which is what happens in tests and in any build that wasn't
  /// given a key. Failures are swallowed for the same reason — a store outage
  /// or a device with no network must not stop the app launching.
  Future<void> configure(String apiKey) async {
    if (_configured || apiKey.isEmpty) return;

    try {
      await _api.configure(apiKey);

      final listener = _onCustomerInfo;
      _listener = listener;
      _api.addCustomerInfoUpdateListener(listener);

      _configured = true;
    } on PlatformException catch (error) {
      debugPrint('RevenueCat configure failed: $error');
    }
  }

  /// Marks the service configured without awaiting the SDK.
  ///
  /// [configure] necessarily awaits the platform call, which defers
  /// `_configured` past the current microtask. `main()` awaits it before
  /// `runApp` so nothing in the real app can observe the gap, but a widget
  /// test builds immediately — and a provider that reads an unconfigured
  /// service caches the empty result forever. This closes that gap for tests
  /// only; production must go through [configure].
  @visibleForTesting
  void configureForTest() {
    if (_configured) return;

    final listener = _onCustomerInfo;
    _listener = listener;
    _api.addCustomerInfoUpdateListener(listener);
    _configured = true;
  }

  /// Debug-only: when true, [getOfferings] returns null unconditionally.
  ///
  /// Lets the "no offering available" fallback in `PaywallScreen` be verified
  /// on a real device without breaking connectivity or misconfiguring the API
  /// key — useful mid-sandbox-test-session, when airplane mode would also kill
  /// an in-flight purchase. Only ever readable/settable in debug builds; the
  /// field still exists in release but [getOfferings] never consults it there,
  /// so it cannot affect a shipped build regardless of its value.
  bool debugForceNoOfferings = false;

  /// The packages available to buy, or null when there is no current offering
  /// (no key, no network, or nothing configured in the dashboard yet).
  Future<Offering?> getOfferings() async {
    if (kDebugMode && debugForceNoOfferings) return null;
    if (!_configured) return null;

    try {
      final offerings = await _api.getOfferings();
      return offerings.current;
    } on PlatformException catch (error) {
      debugPrint('RevenueCat getOfferings failed: $error');
      return null;
    }
  }

  /// Buys [package], returning whether it left the user entitled.
  ///
  /// A user-cancelled purchase returns false rather than throwing: backing out
  /// of the sheet is a normal thing to do, not an error worth surfacing.
  /// Genuine failures rethrow so the caller can show them.
  Future<bool> purchasePackage(Package package) async {
    if (!_configured) return false;

    try {
      final info = await _api.purchase(package);
      return _publish(info);
    } on PlatformException catch (error) {
      if (PurchasesErrorHelper.getErrorCode(error) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return _isPremium;
      }
      rethrow;
    }
  }

  /// Re-applies purchases made on another device or before a reinstall.
  ///
  /// Returns whether the user is entitled afterwards. Apple requires this to
  /// be reachable from the UI for any app selling a non-consumable.
  Future<bool> restorePurchases() async {
    if (!_configured) return false;

    final info = await _api.restorePurchases();
    return _publish(info);
  }

  /// Attaches the store customer to [userId], so the RevenueCat webhook can
  /// resolve a purchase back to this user (and from there, their household).
  ///
  /// [configure] runs before any sign-in — `main()` calls it right after
  /// restoring a Supabase session, and a brand-new user starts fully
  /// anonymous — so RevenueCat's `appUserID` is its own generated one until
  /// this is called. Call this immediately once a Supabase user id is known:
  /// on sign-in, and again on app start if a session was already restored.
  ///
  /// **Anonymous purchase history is merged automatically the first time
  /// [userId] is logged in from an anonymous state** — this is RevenueCat's
  /// own documented behaviour (`Identifying Customers`), not something this
  /// method has to implement. A free-tier-only lifetime purchase made before
  /// the user ever signs in is not orphaned: the first `logIn(userId)` call
  /// for that Supabase account aliases the anonymous customer onto it and
  /// carries the entitlement across, and [_publish] below reflects that
  /// immediately from the returned [CustomerInfo] rather than waiting for the
  /// SDK's own listener callback.
  ///
  /// The one case that does **not** merge — also per RevenueCat's docs — is
  /// logging in to a [userId] that RevenueCat has already seen from a
  /// *different* anonymous customer (e.g. the same account signing in again
  /// on a second device or after a reinstall, which starts with its own new
  /// anonymous ID). That second anonymous customer's history, if it has any,
  /// is not merged — but the original purchase is untouched, since it is
  /// already attached to `userId` from the first device. [restorePurchases]
  /// is what surfaces that entitlement on the second device, and is already
  /// wired to the Settings/paywall "Restore purchases" action.
  Future<void> identify(String userId) async {
    if (!_configured) return;

    try {
      final info = await _api.logIn(userId);
      _publish(info);
    } on PlatformException catch (error) {
      // Not fatal: the user is still signed in to Supabase either way, and
      // the next `restorePurchases`/entitlement check gets another chance.
      debugPrint('RevenueCat logIn failed: $error');
    }
  }

  /// Detaches the RevenueCat identity on sign-out, reverting to a fresh
  /// anonymous customer so the next person to sign in on this device — a
  /// shared or handed-down phone — is not attributed the previous user's
  /// purchase history.
  ///
  /// Publishes the fresh (unentitled) customer immediately, the same reason
  /// [identify] does — otherwise `isPremium` would keep reporting the signed-
  /// out user's entitlement locally until the next unrelated store event.
  Future<void> resetIdentity() async {
    if (!_configured) return;

    try {
      final info = await _api.logOut();
      _publish(info);
    } on PlatformException catch (error) {
      // RevenueCat throws if already anonymous — harmless here, since that is
      // exactly the state this call is trying to reach.
      debugPrint('RevenueCat logOut failed: $error');
    }
  }

  void _onCustomerInfo(CustomerInfo info) => _publish(info);

  /// Records entitlement state from [info] and emits it if it changed.
  bool _publish(CustomerInfo info) {
    final isPremium = info.entitlements.active.containsKey(
      AppConstants.premiumEntitlementId,
    );

    if (isPremium != _isPremium) {
      _isPremium = isPremium;
      if (!_entitlementController.isClosed) {
        _entitlementController.add(isPremium);
      }
    }

    return isPremium;
  }

  Future<void> dispose() async {
    final listener = _listener;
    if (listener != null) {
      _api.removeCustomerInfoUpdateListener(listener);
      _listener = null;
    }
    await _entitlementController.close();
  }
}
