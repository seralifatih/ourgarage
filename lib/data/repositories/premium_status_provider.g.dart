// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'premium_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the user has premium, from any source.
///
/// This is the single source of truth for premium status — UI code must read
/// this provider rather than checking `AppConstants.freeVehicleLimit`,
/// RevenueCat, or the household cache directly, so the gate logic only ever
/// lives in one place.
///
/// True when **either**:
///  * the user's own RevenueCat entitlement is active, or
///  * they belong to a household whose premium flag another member's purchase
///    set ([householdPremiumActive]).
///
/// One person pays and the whole household gets premium. The alternative —
/// everyone buying separately — means nobody ever invites anyone, which would
/// remove the reason this app has households at all.
///
/// **Neither input is a security boundary.** RevenueCat's entitlement is
/// verified by the store, but the household flag is a local cache of a value
/// that Supabase RLS and a RevenueCat webhook own; see
/// [householdPremiumActive]. This provider decides what UI to show, never
/// whether an operation is authorised — anything server-side re-checks.
///
/// Deliberately exposes a plain `bool` rather than an `AsyncValue<bool>`:
/// entitlement is never "loading" from the UI's point of view — an unknown
/// user is simply not premium yet, and a paywall that flickers a spinner
/// before deciding looks broken. Both inputs flip to true the moment they are
/// confirmed, and every widget watching rebuilds then.
///
/// Callers see the same `bool` this provider has always returned, so nothing
/// that reads it needed to change when RevenueCat, and then households,
/// landed behind it.

@ProviderFor(premiumStatus)
final premiumStatusProvider = PremiumStatusProvider._();

/// Whether the user has premium, from any source.
///
/// This is the single source of truth for premium status — UI code must read
/// this provider rather than checking `AppConstants.freeVehicleLimit`,
/// RevenueCat, or the household cache directly, so the gate logic only ever
/// lives in one place.
///
/// True when **either**:
///  * the user's own RevenueCat entitlement is active, or
///  * they belong to a household whose premium flag another member's purchase
///    set ([householdPremiumActive]).
///
/// One person pays and the whole household gets premium. The alternative —
/// everyone buying separately — means nobody ever invites anyone, which would
/// remove the reason this app has households at all.
///
/// **Neither input is a security boundary.** RevenueCat's entitlement is
/// verified by the store, but the household flag is a local cache of a value
/// that Supabase RLS and a RevenueCat webhook own; see
/// [householdPremiumActive]. This provider decides what UI to show, never
/// whether an operation is authorised — anything server-side re-checks.
///
/// Deliberately exposes a plain `bool` rather than an `AsyncValue<bool>`:
/// entitlement is never "loading" from the UI's point of view — an unknown
/// user is simply not premium yet, and a paywall that flickers a spinner
/// before deciding looks broken. Both inputs flip to true the moment they are
/// confirmed, and every widget watching rebuilds then.
///
/// Callers see the same `bool` this provider has always returned, so nothing
/// that reads it needed to change when RevenueCat, and then households,
/// landed behind it.

final class PremiumStatusProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the user has premium, from any source.
  ///
  /// This is the single source of truth for premium status — UI code must read
  /// this provider rather than checking `AppConstants.freeVehicleLimit`,
  /// RevenueCat, or the household cache directly, so the gate logic only ever
  /// lives in one place.
  ///
  /// True when **either**:
  ///  * the user's own RevenueCat entitlement is active, or
  ///  * they belong to a household whose premium flag another member's purchase
  ///    set ([householdPremiumActive]).
  ///
  /// One person pays and the whole household gets premium. The alternative —
  /// everyone buying separately — means nobody ever invites anyone, which would
  /// remove the reason this app has households at all.
  ///
  /// **Neither input is a security boundary.** RevenueCat's entitlement is
  /// verified by the store, but the household flag is a local cache of a value
  /// that Supabase RLS and a RevenueCat webhook own; see
  /// [householdPremiumActive]. This provider decides what UI to show, never
  /// whether an operation is authorised — anything server-side re-checks.
  ///
  /// Deliberately exposes a plain `bool` rather than an `AsyncValue<bool>`:
  /// entitlement is never "loading" from the UI's point of view — an unknown
  /// user is simply not premium yet, and a paywall that flickers a spinner
  /// before deciding looks broken. Both inputs flip to true the moment they are
  /// confirmed, and every widget watching rebuilds then.
  ///
  /// Callers see the same `bool` this provider has always returned, so nothing
  /// that reads it needed to change when RevenueCat, and then households,
  /// landed behind it.
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

String _$premiumStatusHash() => r'3b087bcfe2173783de1db43b6ab1aef8e25455b1';
