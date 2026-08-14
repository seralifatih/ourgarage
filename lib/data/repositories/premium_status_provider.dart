import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/purchase_service_provider.dart';
import 'household_premium_provider.dart';

part 'premium_status_provider.g.dart';

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
@riverpod
bool premiumStatus(Ref ref) {
  final service = ref.watch(purchaseServiceProvider);
  final ownEntitlementActive = service.isPremium;

  // Watched, not read: when the household cache flips, this provider must
  // re-run so a member who was granted premium by someone else's purchase
  // stops seeing the paywall without restarting the app.
  final householdActive = ref.watch(householdPremiumActiveProvider);

  // Re-run this provider when the RevenueCat entitlement actually changes.
  // Going through `invalidateSelf` rather than holding state here keeps this a
  // plain functional `bool` provider — the shape every existing caller and
  // test override already expects.
  //
  // The `!= ownEntitlementActive` guard is load-bearing: `isPremiumStream`
  // replays its current value to every new subscriber, so invalidating
  // unconditionally would re-run this function, re-subscribe, receive the
  // replay, and invalidate again — an infinite rebuild loop that hangs the app.
  final subscription = service.isPremiumStream.listen((isPremium) {
    if (isPremium != ownEntitlementActive) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);

  return ownEntitlementActive || householdActive;
}
