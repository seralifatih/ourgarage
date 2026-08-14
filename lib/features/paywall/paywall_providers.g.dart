// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The offering the paywall renders, or null when there is nothing to sell.
///
/// Null covers every "can't buy right now" case — no API key, no network, or
/// no offering configured in the RevenueCat dashboard yet. The paywall shows
/// its value proposition regardless and only hides the purchase controls, so
/// a store hiccup never leaves the user staring at an empty screen.
///
/// Prices come from here rather than from constants: [StoreProduct.priceString]
/// is already localised and currency-converted by the store, so a user in
/// Türkiye sees ₺ and a user in the US sees $ without the app formatting
/// anything itself.

@ProviderFor(currentOffering)
final currentOfferingProvider = CurrentOfferingProvider._();

/// The offering the paywall renders, or null when there is nothing to sell.
///
/// Null covers every "can't buy right now" case — no API key, no network, or
/// no offering configured in the RevenueCat dashboard yet. The paywall shows
/// its value proposition regardless and only hides the purchase controls, so
/// a store hiccup never leaves the user staring at an empty screen.
///
/// Prices come from here rather than from constants: [StoreProduct.priceString]
/// is already localised and currency-converted by the store, so a user in
/// Türkiye sees ₺ and a user in the US sees $ without the app formatting
/// anything itself.

final class CurrentOfferingProvider
    extends
        $FunctionalProvider<
          AsyncValue<Offering?>,
          Offering?,
          FutureOr<Offering?>
        >
    with $FutureModifier<Offering?>, $FutureProvider<Offering?> {
  /// The offering the paywall renders, or null when there is nothing to sell.
  ///
  /// Null covers every "can't buy right now" case — no API key, no network, or
  /// no offering configured in the RevenueCat dashboard yet. The paywall shows
  /// its value proposition regardless and only hides the purchase controls, so
  /// a store hiccup never leaves the user staring at an empty screen.
  ///
  /// Prices come from here rather than from constants: [StoreProduct.priceString]
  /// is already localised and currency-converted by the store, so a user in
  /// Türkiye sees ₺ and a user in the US sees $ without the app formatting
  /// anything itself.
  CurrentOfferingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentOfferingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentOfferingHash();

  @$internal
  @override
  $FutureProviderElement<Offering?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Offering?> create(Ref ref) {
    return currentOffering(ref);
  }
}

String _$currentOfferingHash() => r'25fa181fcf832e9339ef503de35c1bf256269bcf';
