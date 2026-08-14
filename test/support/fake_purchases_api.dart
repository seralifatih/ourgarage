import 'package:flutter/services.dart';
import 'package:ourgarage/core/constants.dart';
import 'package:ourgarage/services/purchase_service.dart';
import 'package:ourgarage/services/purchase_service_provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// A [PurchasesApi] that touches no platform.
///
/// Any test that renders the settings screen — or pumps the whole app — needs
/// this: the real API is RevenueCat's static [Purchases] class, which blocks
/// forever on a method channel that has no implementation under the test
/// runner.
class FakePurchasesApi implements PurchasesApi {
  FakePurchasesApi({
    this.isPremium = false,
    this.restoreGrantsPremium,
    this.offerings,
    this.purchaseError,
  });

  /// What [getOfferings] returns. Defaults to [defaultOfferings] — a lifetime
  /// and an annual package with localised-looking prices. Pass an empty
  /// [Offerings] to exercise the "nothing to sell" path.
  final Offerings? offerings;

  /// When set, [purchase] throws it instead of granting the entitlement.
  final PlatformException? purchaseError;

  /// The package handed to the last [purchase] call.
  Package? lastPurchased;

  /// Entitlement state reported to listeners once configured.
  bool isPremium;

  /// What [restorePurchases] should leave the user entitled to. Defaults to
  /// whatever [isPremium] is at the time of the call.
  final bool? restoreGrantsPremium;

  int configureCount = 0;
  int restoreCount = 0;
  int purchaseCount = 0;

  /// Every id [logIn] was called with, in order — so a test can assert the
  /// identity bridge fired, and with what.
  final loggedInAs = <String>[];

  int logOutCount = 0;

  /// Models RevenueCat's real merge rule: `logIn(id)` only carries the
  /// anonymous entitlement across the **first** time `id` is seen. Every
  /// later `logIn` for the same id is a no-op merge — the entitlement is
  /// already there or it isn't, purely from a prior `identify`/`purchase`
  /// call. A `logIn` for a *different* id that this fake has already seen
  /// once does not inherit whatever is currently anonymous, exactly as
  /// RevenueCat's docs describe for a second device's fresh anonymous
  /// customer.
  final _seenUserIds = <String>{};

  /// Whether the *current, still-anonymous* customer has an entitlement, to
  /// be merged into whichever id next calls [logIn] for the first time. Set
  /// this before signing in to simulate a free-tier-only purchase made
  /// before the user ever creates an account.
  bool anonymousIsPremium = false;

  final _listeners = <void Function(CustomerInfo)>[];

  @override
  Future<void> configure(String apiKey) async {
    configureCount++;
  }

  @override
  Future<Offerings> getOfferings() async {
    return offerings ?? defaultOfferings();
  }

  @override
  Future<CustomerInfo> purchase(Package package) async {
    purchaseCount++;
    lastPurchased = package;

    final error = purchaseError;
    if (error != null) throw error;

    isPremium = true;
    return _customerInfo(isPremium);
  }

  @override
  Future<CustomerInfo> restorePurchases() async {
    restoreCount++;
    isPremium = restoreGrantsPremium ?? isPremium;
    return _customerInfo(isPremium);
  }

  @override
  Future<CustomerInfo> logIn(String appUserId) async {
    loggedInAs.add(appUserId);

    final firstTimeSeeingThisId = _seenUserIds.add(appUserId);
    if (firstTimeSeeingThisId && anonymousIsPremium) {
      // The one real merge case: an anonymous purchase, made before this id
      // was ever logged in, is carried across on its first sign-in.
      isPremium = true;
    }
    // A later logIn for an id already seen, or for a brand-new id with
    // nothing anonymous to merge, leaves `isPremium` exactly as it was —
    // which is the point: nothing is silently granted or revoked by logIn.

    return _customerInfo(isPremium);
  }

  @override
  Future<CustomerInfo> logOut() async {
    logOutCount++;
    // RevenueCat resets to a fresh anonymous customer on logOut, which by
    // construction has no entitlement — a previous user's purchase must not
    // leak to whoever signs in next on a shared device.
    isPremium = false;
    anonymousIsPremium = false;
    return _customerInfo(false);
  }

  @override
  void addCustomerInfoUpdateListener(void Function(CustomerInfo) listener) {
    _listeners.add(listener);
  }

  @override
  void removeCustomerInfoUpdateListener(void Function(CustomerInfo) listener) {
    _listeners.remove(listener);
  }

  /// Pushes an entitlement change, as the SDK would after a store event.
  void emit(bool premium) {
    isPremium = premium;
    for (final listener in List.of(_listeners)) {
      listener(_customerInfo(premium));
    }
  }

  /// An offering with both products, priced as the store would report them.
  ///
  /// The price strings are deliberately not "$9.99"/"$4.99": tests assert that
  /// the UI renders whatever the store sent rather than a hardcoded constant,
  /// and identical strings would let a hardcoded UI pass by accident.
  static Offerings defaultOfferings({
    String lifetimePrice = 'US\$9.99',
    String annualPrice = 'US\$4.99',
  }) {
    final offering = <String, dynamic>{
      'identifier': 'default',
      'serverDescription': 'Default offering',
      'metadata': <String, Object>{},
      'availablePackages': [
        _package('lifetime', 'LIFETIME', lifetimePrice),
        _package('annual', 'ANNUAL', annualPrice),
      ],
      'lifetime': _package('lifetime', 'LIFETIME', lifetimePrice),
      'annual': _package('annual', 'ANNUAL', annualPrice),
    };

    return Offerings.fromJson(<String, dynamic>{
      'all': {'default': offering},
      'current': offering,
    });
  }

  /// An offering with no packages, as when the dashboard has none configured.
  static Offerings emptyOfferings() {
    return Offerings.fromJson(<String, dynamic>{
      'all': <String, dynamic>{},
      'current': null,
    });
  }

  static Map<String, dynamic> _package(
    String identifier,
    String type,
    String priceString,
  ) {
    return <String, dynamic>{
      'identifier': identifier,
      'packageType': type,
      'product': <String, dynamic>{
        'identifier': identifier == 'lifetime'
            ? AppConstants.lifetimeProductId
            : AppConstants.annualProductId,
        'description': 'OurGarage Premium',
        'title': 'OurGarage Premium',
        'price': 9.99,
        'priceString': priceString,
        'currencyCode': 'USD',
        'productCategory': type == 'LIFETIME'
            ? 'NON_SUBSCRIPTION'
            : 'SUBSCRIPTION',
      },
      'presentedOfferingContext': <String, dynamic>{
        'offeringIdentifier': 'default',
        'placementIdentifier': null,
        'targetingContext': null,
      },
    };
  }

  /// A [CustomerInfo] whose only interesting property is whether the premium
  /// entitlement is active — the one field [PurchaseService] reads.
  ///
  /// Built through `fromJson` rather than the constructors: those take a long
  /// list of positional arguments that shift between SDK releases, whereas the
  /// wire format these factories parse is the stable contract.
  static CustomerInfo _customerInfo(bool isPremium) {
    final entitlement = <String, dynamic>{
      'identifier': AppConstants.premiumEntitlementId,
      'isActive': true,
      'willRenew': true,
      'periodType': 'NORMAL',
      'latestPurchaseDate': '2026-01-01T00:00:00Z',
      'originalPurchaseDate': '2026-01-01T00:00:00Z',
      'expirationDate': null,
      'store': 'APP_STORE',
      'productIdentifier': AppConstants.lifetimeProductId,
      'isSandbox': true,
      'unsubscribeDetectedAt': null,
      'billingIssueDetectedAt': null,
      'ownershipType': 'PURCHASED',
      'verification': 'NOT_REQUESTED',
    };

    final active = isPremium
        ? {AppConstants.premiumEntitlementId: entitlement}
        : <String, dynamic>{};

    return CustomerInfo.fromJson(<String, dynamic>{
      'entitlements': <String, dynamic>{
        'all': active,
        'active': active,
        'verification': 'NOT_REQUESTED',
      },
      'allPurchaseDates': <String, dynamic>{},
      'activeSubscriptions': <String>[],
      'allPurchasedProductIdentifiers': <String>[],
      'nonSubscriptionTransactions': <dynamic>[],
      'firstSeen': '2026-01-01T00:00:00Z',
      'originalAppUserId': 'fake-user',
      'allExpirationDates': <String, dynamic>{},
      'requestDate': '2026-01-01T00:00:00Z',
      'latestExpirationDate': null,
      'originalPurchaseDate': null,
      'originalApplicationVersion': null,
      'managementURL': null,
      'subscriptionsByProductIdentifier': <String, dynamic>{},
    });
  }
}

/// Overrides [purchaseServiceProvider] with a platform-free service.
///
/// The service is configured with a dummy key, as `main()` does at launch, so
/// tests exercise the same code path a running app would — an unconfigured
/// service short-circuits every purchase call and would silently do nothing.
///
/// Configuration must be *complete* by the time this returns. `main()` awaits
/// it before `runApp`, so in the real app nothing can read the service while
/// it is still unconfigured. In a widget test the provider is read during the
/// first build, so leaving configuration on the microtask queue would let
/// `currentOfferingProvider` observe the unconfigured service, cache the null
/// it returns, and never re-fetch — a paywall with no packages.
Override fakePurchaseServiceOverride([FakePurchasesApi? api]) {
  return purchaseServiceProvider.overrideWith((ref) {
    final service = PurchaseService(api ?? FakePurchasesApi())
      ..configureForTest();
    ref.onDispose(service.dispose);
    return service;
  });
}
