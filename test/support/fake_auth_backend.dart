import 'dart:async';

import 'package:ourgarage/services/auth_service.dart';
import 'package:ourgarage/services/auth_service_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// An [AuthBackend] that touches no platform and no network.
///
/// Both real implementations are unreachable under the test runner: Sign in
/// with Apple is a platform channel, and Supabase is a static singleton that
/// throws unless `initialize()` ran.
class FakeAuthBackend implements AuthBackend {
  FakeAuthBackend({
    this.userId = 'user-1',
    this.givenName,
    this.familyName,
    this.cancels = false,
    this.appleError,
    this.signInError,
    bool alreadySignedIn = false,
  }) {
    // Models a session Supabase already restored before this backend was
    // ever asked — the case `RevenueCatIdentitySync` exists to cover, where
    // there is no live sign-in event to react to, only an already-settled
    // value.
    if (alreadySignedIn) _currentUserId = userId;
  }

  /// The id returned by a successful sign-in.
  final String userId;

  /// What Apple reports. Null on every authorization after the first.
  final String? givenName;
  final String? familyName;

  /// Whether the user dismisses the Apple sheet.
  final bool cancels;

  /// Thrown from the Apple step when set.
  final Object? appleError;

  /// Thrown from the Supabase exchange when set.
  final Object? signInError;

  String? _currentUserId;

  /// Broadcasts changes, but — like the real `gotrue` `onAuthStateChange` this
  /// stands in for — also replays the current value to a subscriber that
  /// joins after the fact. `RevenueCatIdentitySync` and `currentUserIdProvider`
  /// both depend on that: they only ever subscribe once, well after
  /// construction, and expect an already-restored session to arrive without
  /// requiring a live sign-in event.
  late final _controller = StreamController<String?>.broadcast(
    onListen: () => _replayCurrentValue(),
  );

  void _replayCurrentValue() => _controller.add(_currentUserId);

  /// Profiles created, by user id, with the display name they were given.
  final createdProfiles = <String, String?>{};

  /// Households created, by user id, with the name they were given.
  final createdHouseholds = <String, String>{};

  /// Nonces handed to Apple, so tests can assert they are per-attempt.
  final noncesUsed = <String>[];

  /// Nonce passed on to Supabase, which must be the unhashed one.
  String? nonceSentToSupabase;

  int appleCallCount = 0;
  int signOutCount = 0;

  /// Pre-existing server state, for the returning-user cases.
  bool profileAlreadyExists = false;
  bool householdAlreadyExists = false;

  /// The household a returning user is already in.
  String existingHouseholdId = 'existing-household';

  @override
  bool get isConfigured => true;

  @override
  String? get currentUserId => _currentUserId;

  @override
  Stream<String?> get userIdChanges => _controller.stream;

  @override
  Future<AppleCredential?> getAppleCredential({
    required String rawNonce,
  }) async {
    appleCallCount++;
    noncesUsed.add(rawNonce);

    if (appleError != null) throw appleError!;
    if (cancels) return null;

    return AppleCredential(
      identityToken: 'apple-identity-token',
      givenName: givenName,
      familyName: familyName,
    );
  }

  @override
  Future<String> signInWithAppleIdToken({
    required String idToken,
    required String rawNonce,
  }) async {
    if (signInError != null) throw signInError!;

    nonceSentToSupabase = rawNonce;
    _currentUserId = userId;
    _controller.add(userId);
    return userId;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _currentUserId = null;
    _controller.add(null);
  }

  @override
  Future<bool> profileExists(String id) async =>
      profileAlreadyExists || createdProfiles.containsKey(id);

  @override
  Future<void> createProfile({
    required String userId,
    String? displayName,
  }) async {
    createdProfiles[userId] = displayName;
  }

  @override
  Future<String?> getHouseholdId(String id) async {
    if (householdAlreadyExists) return existingHouseholdId;
    return createdHouseholds.containsKey(id) ? 'household-for-$id' : null;
  }

  @override
  Future<String> createHousehold({
    required String userId,
    required String name,
  }) async {
    createdHouseholds[userId] = name;
    return 'household-for-$userId';
  }

  Future<void> dispose() => _controller.close();
}

/// Overrides [authServiceProvider] with a platform-free service.
Override fakeAuthServiceOverride([FakeAuthBackend? backend]) {
  return authServiceProvider.overrideWith((ref) {
    final resolved = backend ?? FakeAuthBackend();
    ref.onDispose(resolved.dispose);
    return AuthService(resolved);
  });
}
