import 'package:drift/drift.dart';

import '../database.dart';

part 'household_entitlement_dao.g.dart';

/// Reads and writes the cached household premium flag.
///
/// See [HouseholdEntitlements] for why this cache is not a security boundary.
/// Phase 5 is expected to call [cacheEntitlement] from whatever syncs with
/// Supabase; nothing else should write here.
@DriftAccessor(tables: [HouseholdEntitlements])
class HouseholdEntitlementDao extends DatabaseAccessor<AppDatabase>
    with _$HouseholdEntitlementDaoMixin {
  HouseholdEntitlementDao(super.db);

  /// Live view of whether the user's household has premium.
  ///
  /// Emits false when the row is absent, which is the state until Phase 5
  /// writes one — a user in no household is not household-premium.
  Stream<bool> watchHouseholdPremium() {
    return (select(householdEntitlements)
          ..where((e) => e.id.equals(HouseholdEntitlements.singleton)))
        .watchSingleOrNull()
        .map((row) => row?.isPremium ?? false);
  }

  /// The current cached flag, defaulting to false when nothing is cached.
  Future<bool> isHouseholdPremium() async {
    final row =
        await (select(householdEntitlements)
              ..where((e) => e.id.equals(HouseholdEntitlements.singleton)))
            .getSingleOrNull();
    return row?.isPremium ?? false;
  }

  /// The whole cached row, for callers that need [HouseholdEntitlement.cachedAt]
  /// to decide whether the cache is stale enough to refetch.
  Future<HouseholdEntitlement?> getCached() {
    return (select(householdEntitlements)
          ..where((e) => e.id.equals(HouseholdEntitlements.singleton)))
        .getSingleOrNull();
  }

  /// Replaces the cached flag.
  ///
  /// Phase 5 calls this after reading the household's entitlement from
  /// Supabase. [cachedAt] defaults to now so staleness is measurable.
  Future<void> cacheEntitlement({
    required bool isPremium,
    String? householdId,
    DateTime? cachedAt,
  }) {
    return into(householdEntitlements).insertOnConflictUpdate(
      HouseholdEntitlementsCompanion.insert(
        id: const Value(HouseholdEntitlements.singleton),
        isPremium: Value(isPremium),
        householdId: Value(householdId),
        cachedAt: Value(cachedAt ?? DateTime.now()),
      ),
    );
  }

  /// Drops the cache, reverting to "not household-premium".
  ///
  /// Belongs in a sign-out path: leaving the previous user's entitlement
  /// cached would show premium UI to whoever signs in next.
  Future<void> clear() {
    return (delete(
      householdEntitlements,
    )..where((e) => e.id.equals(HouseholdEntitlements.singleton))).go();
  }
}
