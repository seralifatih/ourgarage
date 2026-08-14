import '../local/daos/household_entitlement_dao.dart';

/// Access to the cached household premium flag.
///
/// **This is a cache, not an authorisation check.** The authoritative answer
/// lives server-side — Supabase RLS gates household data, and a RevenueCat
/// webhook sets the household's premium flag when any member buys or lapses.
/// The local copy exists so the UI can decide what to show without waiting on
/// the network; anyone can edit the device's sqlite file, so every server-side
/// operation must verify entitlement itself rather than trusting this.
///
/// Phase 5 populates it from Supabase. Until then [isHouseholdPremium] is
/// false for everyone, which is the correct default: no household, no shared
/// entitlement.
class HouseholdEntitlementRepository {
  const HouseholdEntitlementRepository(this._dao);

  final HouseholdEntitlementDao _dao;

  /// Live view of the cached flag; false when nothing is cached.
  Stream<bool> watchHouseholdPremium() => _dao.watchHouseholdPremium();

  /// The cached flag right now, false when nothing is cached.
  Future<bool> isHouseholdPremium() => _dao.isHouseholdPremium();

  /// Updates the cache from a server-provided value.
  Future<void> cacheEntitlement({
    required bool isPremium,
    String? householdId,
    DateTime? cachedAt,
  }) {
    return _dao.cacheEntitlement(
      isPremium: isPremium,
      householdId: householdId,
      cachedAt: cachedAt,
    );
  }

  /// Clears the cache. Call on sign-out — see [HouseholdEntitlementDao.clear].
  Future<void> clear() => _dao.clear();
}
