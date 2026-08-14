// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'household_premium_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the user's household has premium because another member paid for it.
///
/// One purchase covers everyone in a household. Charging each member
/// separately would mean nobody ever invites anyone, which would kill the
/// family-sharing angle this app is built around — so entitlement is a
/// property of the household, not of the individual account.
///
/// **This value is a cache and never a security boundary.** The authoritative
/// check lives server-side: Supabase RLS decides what household data a user
/// may read, and a RevenueCat webhook writes the household's premium flag when
/// a member purchases, renews or lapses. The copy read here lives in the local
/// sqlite file, which anyone with the device can edit, so it may only decide
/// what UI to draw. Any server-side operation must re-verify entitlement
/// itself rather than trusting a client that claims to be premium.
///
/// Defaults to false and stays false until Phase 5 populates the cache from
/// Supabase — correct in the meantime, since a user in no household has no
/// shared entitlement to inherit.
///
/// Exposes a plain `bool` rather than an `AsyncValue<bool>` to match
/// [premiumStatus]: a paywall that flickers a spinner while deciding looks
/// broken, and "not yet known" should render exactly like "not premium".

@ProviderFor(HouseholdPremiumActive)
final householdPremiumActiveProvider = HouseholdPremiumActiveProvider._();

/// Whether the user's household has premium because another member paid for it.
///
/// One purchase covers everyone in a household. Charging each member
/// separately would mean nobody ever invites anyone, which would kill the
/// family-sharing angle this app is built around — so entitlement is a
/// property of the household, not of the individual account.
///
/// **This value is a cache and never a security boundary.** The authoritative
/// check lives server-side: Supabase RLS decides what household data a user
/// may read, and a RevenueCat webhook writes the household's premium flag when
/// a member purchases, renews or lapses. The copy read here lives in the local
/// sqlite file, which anyone with the device can edit, so it may only decide
/// what UI to draw. Any server-side operation must re-verify entitlement
/// itself rather than trusting a client that claims to be premium.
///
/// Defaults to false and stays false until Phase 5 populates the cache from
/// Supabase — correct in the meantime, since a user in no household has no
/// shared entitlement to inherit.
///
/// Exposes a plain `bool` rather than an `AsyncValue<bool>` to match
/// [premiumStatus]: a paywall that flickers a spinner while deciding looks
/// broken, and "not yet known" should render exactly like "not premium".
final class HouseholdPremiumActiveProvider
    extends $NotifierProvider<HouseholdPremiumActive, bool> {
  /// Whether the user's household has premium because another member paid for it.
  ///
  /// One purchase covers everyone in a household. Charging each member
  /// separately would mean nobody ever invites anyone, which would kill the
  /// family-sharing angle this app is built around — so entitlement is a
  /// property of the household, not of the individual account.
  ///
  /// **This value is a cache and never a security boundary.** The authoritative
  /// check lives server-side: Supabase RLS decides what household data a user
  /// may read, and a RevenueCat webhook writes the household's premium flag when
  /// a member purchases, renews or lapses. The copy read here lives in the local
  /// sqlite file, which anyone with the device can edit, so it may only decide
  /// what UI to draw. Any server-side operation must re-verify entitlement
  /// itself rather than trusting a client that claims to be premium.
  ///
  /// Defaults to false and stays false until Phase 5 populates the cache from
  /// Supabase — correct in the meantime, since a user in no household has no
  /// shared entitlement to inherit.
  ///
  /// Exposes a plain `bool` rather than an `AsyncValue<bool>` to match
  /// [premiumStatus]: a paywall that flickers a spinner while deciding looks
  /// broken, and "not yet known" should render exactly like "not premium".
  HouseholdPremiumActiveProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'householdPremiumActiveProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$householdPremiumActiveHash();

  @$internal
  @override
  HouseholdPremiumActive create() => HouseholdPremiumActive();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$householdPremiumActiveHash() =>
    r'1168f3993b7338aec2ecf88b1245a896d15ccccd';

/// Whether the user's household has premium because another member paid for it.
///
/// One purchase covers everyone in a household. Charging each member
/// separately would mean nobody ever invites anyone, which would kill the
/// family-sharing angle this app is built around — so entitlement is a
/// property of the household, not of the individual account.
///
/// **This value is a cache and never a security boundary.** The authoritative
/// check lives server-side: Supabase RLS decides what household data a user
/// may read, and a RevenueCat webhook writes the household's premium flag when
/// a member purchases, renews or lapses. The copy read here lives in the local
/// sqlite file, which anyone with the device can edit, so it may only decide
/// what UI to draw. Any server-side operation must re-verify entitlement
/// itself rather than trusting a client that claims to be premium.
///
/// Defaults to false and stays false until Phase 5 populates the cache from
/// Supabase — correct in the meantime, since a user in no household has no
/// shared entitlement to inherit.
///
/// Exposes a plain `bool` rather than an `AsyncValue<bool>` to match
/// [premiumStatus]: a paywall that flickers a spinner while deciding looks
/// broken, and "not yet known" should render exactly like "not premium".

abstract class _$HouseholdPremiumActive extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
