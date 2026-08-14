import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/services/purchase_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../support/fake_purchases_api.dart';

void main() {
  late FakePurchasesApi api;
  late PurchaseService service;

  setUp(() {
    api = FakePurchasesApi();
    service = PurchaseService(api);
  });

  tearDown(() => service.dispose());

  group('configure', () {
    test('an empty key leaves the service unconfigured', () async {
      await service.configure('');

      expect(service.isConfigured, isFalse);
      expect(api.configureCount, 0);
    });

    test('a key configures the SDK once, however many calls', () async {
      await service.configure('appl_test');
      await service.configure('appl_test');

      expect(service.isConfigured, isTrue);
      expect(api.configureCount, 1);
    });

    test('an unconfigured service reports the user as not premium', () async {
      await service.configure('');

      expect(service.isPremium, isFalse);
      expect(await service.isPremiumStream.first, isFalse);
    });
  });

  group('entitlement state', () {
    test('starts false before the store has said anything', () {
      expect(service.isPremium, isFalse);
    });

    test('an entitled customer flips it to true', () async {
      await service.configure('appl_test');

      api.emit(true);

      expect(service.isPremium, isTrue);
    });

    test('losing the entitlement flips it back', () async {
      await service.configure('appl_test');

      api.emit(true);
      api.emit(false);

      expect(service.isPremium, isFalse);
    });

    test('the stream replays the current value to a late listener', () async {
      await service.configure('appl_test');
      api.emit(true);

      // Subscribing only now: a plain broadcast stream would have dropped the
      // emission above and left this hanging.
      expect(await service.isPremiumStream.first, isTrue);
    });

    test('the stream emits on change', () async {
      await service.configure('appl_test');

      final seen = <bool>[];
      final subscription = service.isPremiumStream.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      api.emit(true);
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();
      expect(seen, [false, true]);
    });

    test('an unchanged value is not re-emitted', () async {
      await service.configure('appl_test');

      final seen = <bool>[];
      final subscription = service.isPremiumStream.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      api.emit(false);
      api.emit(false);
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();
      expect(seen, [false], reason: 'only the replayed seed');
    });
  });

  group('restorePurchases', () {
    test('returns true and updates state when a purchase is found', () async {
      api = FakePurchasesApi(restoreGrantsPremium: true);
      service = PurchaseService(api);
      await service.configure('appl_test');

      expect(await service.restorePurchases(), isTrue);
      expect(service.isPremium, isTrue);
    });

    test('returns false when there is nothing to restore', () async {
      await service.configure('appl_test');

      expect(await service.restorePurchases(), isFalse);
      expect(service.isPremium, isFalse);
    });

    test('is a no-op when unconfigured', () async {
      expect(await service.restorePurchases(), isFalse);
      expect(api.restoreCount, 0);
    });
  });

  group('identity', () {
    test('identify is a no-op when unconfigured', () async {
      await service.identify('user-1');

      expect(api.loggedInAs, isEmpty);
    });

    test('identify calls logIn with the given user id', () async {
      await service.configure('appl_test');

      await service.identify('user-1');

      expect(api.loggedInAs, ['user-1']);
    });

    test(
      'a free-tier-only lifetime purchase made before sign-in is not '
      'orphaned — identify merges it in',
      () async {
        // Exactly the scenario the bug report called out: someone buys
        // Premium without ever touching household sharing, then later signs
        // in for the first time.
        api.anonymousIsPremium = true;
        await service.configure('appl_test');
        expect(
          service.isPremium,
          isFalse,
          reason: 'still anonymous — configure alone never merges anything',
        );

        await service.identify('user-1');

        expect(
          service.isPremium,
          isTrue,
          reason:
              'RevenueCat aliases the anonymous customer onto user-1 the '
              'first time user-1 is logged in, carrying the entitlement '
              'across',
        );
      },
    );

    test(
      'a second identify for the same id does not need to re-merge anything',
      () async {
        api.anonymousIsPremium = true;
        await service.configure('appl_test');
        await service.identify('user-1');
        expect(service.isPremium, isTrue);

        // A second app launch, same signed-in user: identify runs again.
        await service.identify('user-1');

        expect(service.isPremium, isTrue, reason: 'entitlement still holds');
      },
    );

    test(
      'identify does not throw when the RevenueCat call fails — the '
      'Supabase session is unaffected either way',
      () async {
        final failing = _ThrowingLogInApi();
        final failingService = PurchaseService(failing);
        await failingService.configure('appl_test');

        await failingService.identify('user-1');

        expect(failingService.isPremium, isFalse);
        failingService.dispose();
      },
    );

    test('resetIdentity is a no-op when unconfigured', () async {
      await service.resetIdentity();

      expect(api.logOutCount, 0);
    });

    test('resetIdentity calls logOut', () async {
      await service.configure('appl_test');

      await service.resetIdentity();

      expect(api.logOutCount, 1);
    });

    test(
      'signing out drops entitlement locally too — a shared device must not '
      'keep showing the previous user as premium',
      () async {
        api.anonymousIsPremium = true;
        await service.configure('appl_test');
        await service.identify('user-1');
        expect(service.isPremium, isTrue);

        await service.resetIdentity();

        expect(service.isPremium, isFalse);
      },
    );
  });

  group('getOfferings', () {
    test('returns null when unconfigured', () async {
      expect(await service.getOfferings(), isNull);
    });

    test(
      'debugForceNoOfferings forces null even when configured with real '
      'products',
      () async {
        await service.configure('appl_test');
        expect(await service.getOfferings(), isNotNull);

        service.debugForceNoOfferings = true;

        expect(await service.getOfferings(), isNull);
      },
    );

    test('debugForceNoOfferings=false restores the real offering', () async {
      await service.configure('appl_test');
      service.debugForceNoOfferings = true;
      expect(await service.getOfferings(), isNull);

      service.debugForceNoOfferings = false;

      expect(await service.getOfferings(), isNotNull);
    });
  });
}

/// A [PurchasesApi] whose [logIn] always throws, for the "RevenueCat call
/// fails" case — everything else delegates to a normal [FakePurchasesApi].
class _ThrowingLogInApi implements PurchasesApi {
  final _delegate = FakePurchasesApi();

  @override
  Future<void> configure(String apiKey) => _delegate.configure(apiKey);

  @override
  Future<Offerings> getOfferings() => _delegate.getOfferings();

  @override
  Future<CustomerInfo> purchase(Package package) =>
      _delegate.purchase(package);

  @override
  Future<CustomerInfo> restorePurchases() => _delegate.restorePurchases();

  @override
  Future<CustomerInfo> logIn(String appUserId) {
    throw PlatformException(code: 'test', message: 'logIn failed');
  }

  @override
  Future<CustomerInfo> logOut() => _delegate.logOut();

  @override
  void addCustomerInfoUpdateListener(void Function(CustomerInfo) listener) =>
      _delegate.addCustomerInfoUpdateListener(listener);

  @override
  void removeCustomerInfoUpdateListener(
    void Function(CustomerInfo) listener,
  ) => _delegate.removeCustomerInfoUpdateListener(listener);
}
