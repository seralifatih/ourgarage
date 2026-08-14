// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_service_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app-wide [PurchaseService].
///
/// Kept alive for the process lifetime: it holds the RevenueCat entitlement
/// listener that [premiumStatusProvider] is derived from, so tearing it down
/// when the last listener drops would stop premium state updating.
///
/// Tests override this with a service wrapping a fake [PurchasesApi].

@ProviderFor(purchaseService)
final purchaseServiceProvider = PurchaseServiceProvider._();

/// The app-wide [PurchaseService].
///
/// Kept alive for the process lifetime: it holds the RevenueCat entitlement
/// listener that [premiumStatusProvider] is derived from, so tearing it down
/// when the last listener drops would stop premium state updating.
///
/// Tests override this with a service wrapping a fake [PurchasesApi].

final class PurchaseServiceProvider
    extends
        $FunctionalProvider<PurchaseService, PurchaseService, PurchaseService>
    with $Provider<PurchaseService> {
  /// The app-wide [PurchaseService].
  ///
  /// Kept alive for the process lifetime: it holds the RevenueCat entitlement
  /// listener that [premiumStatusProvider] is derived from, so tearing it down
  /// when the last listener drops would stop premium state updating.
  ///
  /// Tests override this with a service wrapping a fake [PurchasesApi].
  PurchaseServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'purchaseServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$purchaseServiceHash();

  @$internal
  @override
  $ProviderElement<PurchaseService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PurchaseService create(Ref ref) {
    return purchaseService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PurchaseService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PurchaseService>(value),
    );
  }
}

String _$purchaseServiceHash() => r'5a7eab59a848acfb8596d9f1428f37791a0c99fe';
