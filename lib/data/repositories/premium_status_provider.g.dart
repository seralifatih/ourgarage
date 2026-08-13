// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'premium_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the user has an active premium entitlement.
///
/// This is the single source of truth for premium status — UI code must read
/// this provider rather than checking `AppConstants.freeVehicleLimit` or
/// entitlement state directly, so the gate logic only ever lives in one place.
///
/// Hardcoded to `false` for now. Phase 4 replaces this body with a real
/// RevenueCat/`PurchaseService` lookup; nothing that reads this provider should
/// need to change when that happens.

@ProviderFor(premiumStatus)
final premiumStatusProvider = PremiumStatusProvider._();

/// Whether the user has an active premium entitlement.
///
/// This is the single source of truth for premium status — UI code must read
/// this provider rather than checking `AppConstants.freeVehicleLimit` or
/// entitlement state directly, so the gate logic only ever lives in one place.
///
/// Hardcoded to `false` for now. Phase 4 replaces this body with a real
/// RevenueCat/`PurchaseService` lookup; nothing that reads this provider should
/// need to change when that happens.

final class PremiumStatusProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the user has an active premium entitlement.
  ///
  /// This is the single source of truth for premium status — UI code must read
  /// this provider rather than checking `AppConstants.freeVehicleLimit` or
  /// entitlement state directly, so the gate logic only ever lives in one place.
  ///
  /// Hardcoded to `false` for now. Phase 4 replaces this body with a real
  /// RevenueCat/`PurchaseService` lookup; nothing that reads this provider should
  /// need to change when that happens.
  PremiumStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'premiumStatusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$premiumStatusHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return premiumStatus(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$premiumStatusHash() => r'eff1947ee07717a709c8d7e57fee858913ffb9bc';
