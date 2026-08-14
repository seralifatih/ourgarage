import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('defaults to not premium when nothing has been cached', () async {
    expect(await db.householdEntitlementDao.isHouseholdPremium(), isFalse);
    expect(await db.householdEntitlementDao.getCached(), isNull);
  });

  test('the stream emits false before anything is cached', () async {
    expect(
      await db.householdEntitlementDao.watchHouseholdPremium().first,
      isFalse,
    );
  });

  test('caching an entitlement makes it readable', () async {
    await db.householdEntitlementDao.cacheEntitlement(
      isPremium: true,
      householdId: 'household-1',
    );

    expect(await db.householdEntitlementDao.isHouseholdPremium(), isTrue);

    final cached = await db.householdEntitlementDao.getCached();
    expect(cached?.householdId, 'household-1');
    expect(cached?.cachedAt, isNotNull);
  });

  test('caching twice replaces rather than accumulating', () async {
    await db.householdEntitlementDao.cacheEntitlement(isPremium: true);
    await db.householdEntitlementDao.cacheEntitlement(isPremium: false);

    final rows = await db.select(db.householdEntitlements).get();
    expect(rows, hasLength(1), reason: 'the cache is a single row');
    expect(rows.single.isPremium, isFalse);
  });

  test('the stream pushes updates as the cache changes', () async {
    final seen = <bool>[];
    final subscription = db.householdEntitlementDao
        .watchHouseholdPremium()
        .listen(seen.add);
    // Let the initial emission land before writing, so the transitions below
    // are what the assertion is actually about.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await db.householdEntitlementDao.cacheEntitlement(isPremium: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.householdEntitlementDao.cacheEntitlement(isPremium: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await subscription.cancel();
    expect(seen, containsAllInOrder([false, true, false]));
  });

  test('clearing reverts to not premium', () async {
    await db.householdEntitlementDao.cacheEntitlement(isPremium: true);
    await db.householdEntitlementDao.clear();

    expect(await db.householdEntitlementDao.isHouseholdPremium(), isFalse);
    expect(await db.householdEntitlementDao.getCached(), isNull);
  });

  test('a lapsed household is cached as not premium, not cleared', () async {
    // The webhook writes false when a member's subscription lapses. That has
    // to be distinguishable from "never fetched" for staleness checks.
    await db.householdEntitlementDao.cacheEntitlement(
      isPremium: false,
      householdId: 'household-1',
    );

    expect(await db.householdEntitlementDao.isHouseholdPremium(), isFalse);
    expect(await db.householdEntitlementDao.getCached(), isNotNull);
  });
}
