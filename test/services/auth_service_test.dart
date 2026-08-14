import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/core/constants.dart';
import 'package:ourgarage/services/auth_service.dart';

import '../support/fake_auth_backend.dart';

void main() {
  group('household naming', () {
    test('uses the name Apple gave', () {
      expect(AuthService.householdNameFor('Fatih'), 'Fatih’s garage');
    });

    test('a name ending in s takes a bare apostrophe', () {
      expect(AuthService.householdNameFor('Lucas'), 'Lucas’ garage');
    });

    test('falls back when Apple withheld the name', () {
      // The common case: Apple returns the name only on the very first
      // authorization, so every later sign-in lands here.
      expect(
        AuthService.householdNameFor(null),
        AppConstants.defaultHouseholdName,
      );
    });

    test('falls back on a blank or whitespace-only name', () {
      expect(
        AuthService.householdNameFor('   '),
        AppConstants.defaultHouseholdName,
      );
    });
  });

  group('sign-in', () {
    test('creates the profile and household on first sign-in', () async {
      final backend = FakeAuthBackend(givenName: 'Fatih', familyName: 'Ilhan');
      addTearDown(backend.dispose);
      final service = AuthService(backend);

      final result = await service.signInWithApple();

      expect(result?.userId, 'user-1');
      expect(backend.createdProfiles['user-1'], 'Fatih Ilhan');
      expect(backend.createdHouseholds['user-1'], 'Fatih Ilhan’s garage');
      expect(service.isSignedIn, isTrue);

      // The migration needs both of these to upload into the new household.
      expect(result?.householdId, isNotNull);
      expect(
        result?.householdWasCreated,
        isTrue,
        reason: 'a first sign-in creates the household to migrate into',
      );
    });

    test('a returning user reports the household they already had', () async {
      final backend = FakeAuthBackend()
        ..profileAlreadyExists = true
        ..householdAlreadyExists = true
        ..existingHouseholdId = 'household-99';
      addTearDown(backend.dispose);

      final result = await AuthService(backend).signInWithApple();

      expect(result?.householdId, 'household-99');
      expect(result?.householdWasCreated, isFalse);
    });

    test('persists the name immediately, since Apple sends it once', () async {
      // The name arrives on the first authorization and never again. If it is
      // not written during this very call, it is gone for good.
      final backend = FakeAuthBackend(givenName: 'Fatih');
      addTearDown(backend.dispose);

      await AuthService(backend).signInWithApple();

      expect(backend.createdProfiles['user-1'], 'Fatih');
    });

    test('a returning user gets no name and no second household', () async {
      // Second sign-in: Apple withholds the name, and the server already has
      // both rows. Nothing should be created or overwritten.
      final backend = FakeAuthBackend()
        ..profileAlreadyExists = true
        ..householdAlreadyExists = true;
      addTearDown(backend.dispose);

      await AuthService(backend).signInWithApple();

      expect(backend.createdProfiles, isEmpty);
      expect(backend.createdHouseholds, isEmpty);
    });

    test('bootstrap is idempotent after a partial first attempt', () async {
      // A sign-in whose follow-up writes failed leaves a session with a
      // profile but no household. The retry must finish the job.
      final backend = FakeAuthBackend(givenName: 'Fatih')
        ..profileAlreadyExists = true;
      addTearDown(backend.dispose);

      await AuthService(backend).signInWithApple();

      expect(backend.createdProfiles, isEmpty, reason: 'profile was there');
      expect(backend.createdHouseholds['user-1'], isNotNull);
    });

    test('cancelling returns null and creates nothing', () async {
      final backend = FakeAuthBackend(cancels: true);
      addTearDown(backend.dispose);
      final service = AuthService(backend);

      expect(await service.signInWithApple(), isNull);
      expect(backend.createdProfiles, isEmpty);
      expect(backend.createdHouseholds, isEmpty);
      expect(service.isSignedIn, isFalse);
    });

    test('an Apple failure propagates and creates nothing', () async {
      final backend = FakeAuthBackend(
        appleError: const AuthException('Apple is unavailable'),
      );
      addTearDown(backend.dispose);

      await expectLater(
        AuthService(backend).signInWithApple(),
        throwsA(isA<AuthException>()),
      );
      expect(backend.createdProfiles, isEmpty);
    });

    test('a Supabase failure propagates and creates nothing', () async {
      final backend = FakeAuthBackend(
        signInError: const AuthException('Token rejected'),
      );
      addTearDown(backend.dispose);

      await expectLater(
        AuthService(backend).signInWithApple(),
        throwsA(isA<AuthException>()),
      );
      expect(backend.createdProfiles, isEmpty);
      expect(backend.createdHouseholds, isEmpty);
    });
  });

  group('nonce', () {
    test(
      'the raw nonce goes to Supabase, for it to hash and compare',
      () async {
        final backend = FakeAuthBackend();
        addTearDown(backend.dispose);

        await AuthService(backend).signInWithApple();

        // Apple embeds the SHA-256 of this; Supabase recomputes it. Sending the
        // already-hashed value would fail verification.
        expect(backend.nonceSentToSupabase, backend.noncesUsed.single);
      },
    );

    test(
      'a fresh nonce per attempt, or replay protection is pointless',
      () async {
        final backend = FakeAuthBackend();
        addTearDown(backend.dispose);
        final service = AuthService(backend);

        await service.signInWithApple();
        await service.signInWithApple();

        expect(backend.noncesUsed, hasLength(2));
        expect(backend.noncesUsed[0], isNot(backend.noncesUsed[1]));
        expect(backend.noncesUsed.first.length, greaterThanOrEqualTo(32));
      },
    );
  });

  group('sign-out', () {
    test('clears the signed-in user', () async {
      final backend = FakeAuthBackend();
      addTearDown(backend.dispose);
      final service = AuthService(backend);

      await service.signInWithApple();
      expect(service.isSignedIn, isTrue);

      await service.signOut();
      expect(service.isSignedIn, isFalse);
      expect(backend.signOutCount, 1);
    });
  });
}
