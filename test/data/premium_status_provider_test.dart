import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/data/repositories/household_premium_provider.dart';
import 'package:ourgarage/data/repositories/premium_status_provider.dart';

import '../support/fake_purchases_api.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseHolder.overrideWith(db);
  });

  tearDown(() async {
    DatabaseHolder.overrideWith(null);
    await db.close();
  });

  ProviderContainer makeContainer(FakePurchasesApi api) {
    final container = ProviderContainer(
      overrides: [fakePurchaseServiceOverride(api)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Lets drift's stream deliver into the household provider.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  group('entitlement resolution', () {
    test('neither source active means not premium', () async {
      final container = makeContainer(FakePurchasesApi());
      container.listen(premiumStatusProvider, (_, _) {});
      await settle();

      expect(container.read(premiumStatusProvider), isFalse);
    });

    test('the user own RevenueCat entitlement alone grants premium', () async {
      final api = FakePurchasesApi();
      final container = makeContainer(api);
      container.listen(premiumStatusProvider, (_, _) {});
      await settle();

      api.emit(true);
      await settle();

      expect(container.read(premiumStatusProvider), isTrue);
    });

    test('a household member paying alone grants premium', () async {
      // The whole point: this user bought nothing themselves.
      final container = makeContainer(FakePurchasesApi());
      container.listen(premiumStatusProvider, (_, _) {});
      await settle();

      expect(container.read(premiumStatusProvider), isFalse);

      await db.householdEntitlementDao.cacheEntitlement(
        isPremium: true,
        householdId: 'household-1',
      );
      await settle();

      expect(container.read(premiumStatusProvider), isTrue);
      expect(
        container.read(householdPremiumActiveProvider),
        isTrue,
        reason: 'granted by the household, not by this user',
      );
    });

    test('both sources active is still just premium', () async {
      final api = FakePurchasesApi();
      final container = makeContainer(api);
      container.listen(premiumStatusProvider, (_, _) {});
      await settle();

      api.emit(true);
      await db.householdEntitlementDao.cacheEntitlement(isPremium: true);
      await settle();

      expect(container.read(premiumStatusProvider), isTrue);
    });

    test('losing the household flag keeps a self-paid entitlement', () async {
      final api = FakePurchasesApi();
      final container = makeContainer(api);
      container.listen(premiumStatusProvider, (_, _) {});
      await settle();

      api.emit(true);
      await db.householdEntitlementDao.cacheEntitlement(isPremium: true);
      await settle();

      // Leaving the household must not revoke premium the user paid for.
      await db.householdEntitlementDao.cacheEntitlement(isPremium: false);
      await settle();

      expect(container.read(premiumStatusProvider), isTrue);
    });

    test('losing a self-paid entitlement keeps household premium', () async {
      final api = FakePurchasesApi();
      final container = makeContainer(api);
      container.listen(premiumStatusProvider, (_, _) {});
      await settle();

      api.emit(true);
      await db.householdEntitlementDao.cacheEntitlement(isPremium: true);
      await settle();

      api.emit(false);
      await settle();

      expect(
        container.read(premiumStatusProvider),
        isTrue,
        reason: 'the household still covers them',
      );
    });

    test('both lapsing drops premium', () async {
      final api = FakePurchasesApi();
      final container = makeContainer(api);
      container.listen(premiumStatusProvider, (_, _) {});
      await settle();

      api.emit(true);
      await db.householdEntitlementDao.cacheEntitlement(isPremium: true);
      await settle();

      api.emit(false);
      await db.householdEntitlementDao.cacheEntitlement(isPremium: false);
      await settle();

      expect(container.read(premiumStatusProvider), isFalse);
    });
  });

  group('householdPremiumActive', () {
    test('defaults to false with nothing cached', () async {
      final container = makeContainer(FakePurchasesApi());

      expect(container.read(householdPremiumActiveProvider), isFalse);
    });

    test('follows the cache without needing a restart', () async {
      final container = makeContainer(FakePurchasesApi());
      container.listen(householdPremiumActiveProvider, (_, _) {});
      await settle();

      await db.householdEntitlementDao.cacheEntitlement(isPremium: true);
      await settle();

      expect(container.read(householdPremiumActiveProvider), isTrue);
    });
  });
}
