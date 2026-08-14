import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'providers.dart';

part 'household_premium_provider.g.dart';

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
@riverpod
class HouseholdPremiumActive extends _$HouseholdPremiumActive {
  @override
  bool build() {
    final repository = ref.watch(householdEntitlementRepositoryProvider);

    // Follows the cache for the provider's lifetime. A Notifier is used rather
    // than a functional provider because this genuinely holds state: the
    // seeded value has to survive across stream events, which a plain function
    // re-running from scratch cannot do.
    final subscription = repository.watchHouseholdPremium().listen((isPremium) {
      if (state != isPremium) state = isPremium;
    });
    ref.onDispose(subscription.cancel);

    // False until the stream delivers the cached row. Not "unknown": a user
    // with no cached household entitlement is genuinely not household-premium.
    return false;
  }
}
