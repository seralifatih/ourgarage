import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';

/// Raised when sign-in fails for a reason worth showing the user.
///
/// A user cancelling the Apple sheet is not one of these — that returns null
/// from [AuthService.signInWithApple], because backing out is a normal thing
/// to do and not an error worth a red banner.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}

/// The slice of Supabase and Sign in with Apple this app uses.
///
/// [AuthService] depends on this rather than the SDK singletons so the
/// sign-in and household-bootstrap logic can be tested. Both underlying APIs
/// are static or platform-channel bound and unreachable under the test runner
/// — the same reason `NotificationPlugin` and `PurchasesApi` exist.
abstract interface class AuthBackend {
  /// Whether Supabase was configured with a URL and key.
  bool get isConfigured;

  /// The signed-in user's id, or null when signed out.
  String? get currentUserId;

  /// Emits on every sign-in and sign-out.
  Stream<String?> get userIdChanges;

  /// Presents the Apple sheet. Returns null if the user cancelled.
  ///
  /// [rawNonce] is hashed before being handed to Apple; the unhashed value
  /// goes to Supabase so it can verify the token was minted for this request.
  Future<AppleCredential?> getAppleCredential({required String rawNonce});

  /// Exchanges an Apple identity token for a Supabase session.
  Future<String> signInWithAppleIdToken({
    required String idToken,
    required String rawNonce,
  });

  Future<void> signOut();

  /// Whether a profiles row already exists for [userId].
  Future<bool> profileExists(String userId);

  /// Creates the profiles row.
  Future<void> createProfile({required String userId, String? displayName});

  /// The household the user belongs to, or null when they belong to none.
  Future<String?> getHouseholdId(String userId);

  /// Creates a household owned by [userId], returning its id.
  ///
  /// The membership row is created by a database trigger, not here — see
  /// `add_owner_membership()` in the sharing-layer migration.
  Future<String> createHousehold({
    required String userId,
    required String name,
  });
}

/// What Apple returned from an authorization request.
///
/// [givenName] and [familyName] are populated **only on the very first
/// authorization** for a given Apple ID and app. Every subsequent sign-in
/// returns them as null, forever, even after reinstalling. That is an Apple
/// platform behaviour, not a bug to work around: the name has to be persisted
/// the moment it arrives or it is gone for good.
@immutable
class AppleCredential {
  const AppleCredential({
    required this.identityToken,
    this.givenName,
    this.familyName,
    this.email,
  });

  final String identityToken;
  final String? givenName;
  final String? familyName;
  final String? email;

  /// The user's name as Apple gave it, or null when withheld.
  String? get displayName {
    final parts = [
      givenName?.trim(),
      familyName?.trim(),
    ].whereType<String>().where((p) => p.isNotEmpty);

    return parts.isEmpty ? null : parts.join(' ');
  }
}

/// An authenticated user, before household bootstrap runs (or doesn't).
@immutable
class _AppleIdentity {
  const _AppleIdentity({required this.userId, required this.displayName});

  final String userId;
  final String? displayName;
}

/// A completed sign-in, and the household the user landed in.
@immutable
class SignInResult {
  const SignInResult({
    required this.userId,
    required this.householdId,
    required this.householdWasCreated,
  });

  final String userId;
  final String householdId;

  /// Whether this sign-in created the household, as opposed to finding one the
  /// user already belonged to. True is the signal that local data has never
  /// been uploaded — though the migration decides for itself by looking for
  /// unsynced vehicles, so a crashed first attempt still gets retried.
  final bool householdWasCreated;
}

/// [AuthBackend] backed by Supabase and the real Apple sheet.
class SupabaseAuthBackend implements AuthBackend {
  const SupabaseAuthBackend();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  bool get isConfigured {
    // `Supabase.instance` throws if initialize() was never called, which is
    // the case in any build without the dart-define keys. Touching the client
    // is the only way to ask; there is no "was it initialised" flag.
    try {
      Supabase.instance.client;
      return true;
    } on Object {
      return false;
    }
  }

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges =>
      _client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  @override
  Future<AppleCredential?> getAppleCredential({
    required String rawNonce,
  }) async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.fullName,
          AppleIDAuthorizationScopes.email,
        ],
        // Apple embeds the SHA-256 of this in the identity token. Supabase is
        // given the raw value and recomputes the hash, which is what stops a
        // token captured from another session being replayed here.
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException('Apple did not return an identity token.');
      }

      return AppleCredential(
        identityToken: idToken,
        givenName: credential.givenName,
        familyName: credential.familyName,
        email: credential.email,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      // Cancelling is not a failure.
      if (error.code == AuthorizationErrorCode.canceled) return null;
      throw AuthException(error.message);
    }
  }

  @override
  Future<String> signInWithAppleIdToken({
    required String idToken,
    required String rawNonce,
  }) async {
    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw const AuthException('Sign-in did not return a user.');
    }
    return userId;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<bool> profileExists(String userId) async {
    final row = await _client
        .from('profiles')
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<void> createProfile({
    required String userId,
    String? displayName,
  }) async {
    await _client.from('profiles').insert({
      'id': userId,
      'display_name': displayName,
    });
  }

  @override
  Future<String?> getHouseholdId(String userId) async {
    final row = await _client
        .from('household_members')
        .select('household_id')
        .eq('user_id', userId)
        .limit(1)
        .maybeSingle();
    return row?['household_id'] as String?;
  }

  @override
  Future<String> createHousehold({
    required String userId,
    required String name,
  }) async {
    final row = await _client
        .from('households')
        .insert({'name': name, 'owner_id': userId})
        .select('id')
        .single();
    return row['id'] as String;
  }
}

/// Sign-in and first-run household bootstrap.
///
/// Auth is never requested at launch. The only thing that triggers it is a
/// user tapping "Share with household", at which point an account has an
/// obvious purpose — their household needs to see the same data on their own
/// devices. Asking cold, before that, trades a permanent drop in conversion
/// for nothing.
///
/// Sign in with Apple is the only provider offered, deliberately. Adding a
/// second third-party option (Google in particular) brings App Store guideline
/// 4.8 into play, which then requires offering an equivalent privacy-preserving
/// login. One provider, no 4.8 obligation.
class AuthService {
  AuthService([this._backend = const SupabaseAuthBackend()]);

  final AuthBackend _backend;

  /// Sessions are persisted by supabase_flutter itself, in the platform secure
  /// store, and restored during [Supabase.initialize]. Nothing here writes
  /// tokens to disk.
  bool get isSignedIn => _backend.currentUserId != null;

  String? get currentUserId => _backend.currentUserId;

  Stream<String?> get userIdChanges => _backend.userIdChanges;

  /// Runs the full flow: Apple sheet, Supabase exchange, then first-run setup.
  ///
  /// Returns the signed-in user and their household, or null if the user
  /// cancelled the Apple sheet. Throws [AuthException] for anything that
  /// genuinely failed.
  ///
  /// Creates an owned household when the user has none — the right default
  /// for "Share with household", where signing in is itself the decision to
  /// start sharing. A joiner is a different case: see [signInWithoutHousehold].
  Future<SignInResult?> signInWithApple() async {
    final identity = await _authenticate();
    if (identity == null) return null;

    return _bootstrap(
      userId: identity.userId,
      displayName: identity.displayName,
    );
  }

  /// Apple sheet and Supabase exchange, stopping short of household setup.
  ///
  /// For "Join a household": a first-time user here is about to call
  /// [HouseholdService.joinWithCode], and household_members has no constraint
  /// stopping a user joining a second household — so auto-creating one first
  /// (as [signInWithApple] does) would leave them owning an empty throwaway
  /// household alongside the one they meant to join, and
  /// [currentHouseholdId]'s `.limit(1)` would then return whichever of the two
  /// Postgres feels like handing back.
  ///
  /// The profile row is still created here (idempotently, like [_bootstrap]),
  /// since a user needs one to exist as a household member at all — it is only
  /// the household itself that is skipped.
  ///
  /// Returns the user id, or null if the user cancelled the Apple sheet.
  Future<String?> signInWithoutHousehold() async {
    final identity = await _authenticate();
    if (identity == null) return null;

    if (!await _backend.profileExists(identity.userId)) {
      await _backend.createProfile(
        userId: identity.userId,
        displayName: identity.displayName,
      );
    }

    return identity.userId;
  }

  /// The Apple sheet plus the Supabase token exchange, shared by both
  /// sign-in entry points. Returns null if the user cancelled.
  Future<_AppleIdentity?> _authenticate() async {
    final rawNonce = _generateNonce();

    final credential = await _backend.getAppleCredential(rawNonce: rawNonce);
    if (credential == null) return null;

    final userId = await _backend.signInWithAppleIdToken(
      idToken: credential.identityToken,
      rawNonce: rawNonce,
    );

    // The name is only ever present on the first authorization, so it is
    // carried out of here immediately rather than re-fetched later.
    return _AppleIdentity(userId: userId, displayName: credential.displayName);
  }

  /// The current user's household, or null when signed out or not in one.
  ///
  /// Cheap enough to call on every resume; the sync worker uses it to decide
  /// whether there is anything to sync with at all.
  Future<String?> currentHouseholdId() async {
    final userId = _backend.currentUserId;
    if (userId == null) return null;
    return _backend.getHouseholdId(userId);
  }

  /// Resolves the current user's household, signing in first if needed.
  ///
  /// [showSignInSheet] is only invoked when there is no session — an existing
  /// one skips the explainer, which exists to justify a surprising request and
  /// has nothing left to explain to someone already signed in.
  ///
  /// A session that exists but has no household (setup crashed between the two)
  /// is completed here rather than left broken.
  Future<SignInResult?> signInIfNeeded(
    Future<SignInResult?> Function() showSignInSheet,
  ) async {
    final userId = _backend.currentUserId;
    if (userId == null) return showSignInSheet();

    final householdId = await _backend.getHouseholdId(userId);
    if (householdId == null) {
      // Apple will not hand the name over a second time, so this recovery path
      // necessarily falls back to the default household name.
      return _bootstrap(userId: userId, displayName: null);
    }

    return SignInResult(
      userId: userId,
      householdId: householdId,
      householdWasCreated: false,
    );
  }

  /// Creates the profile and first household, if they don't exist yet.
  ///
  /// Idempotent on purpose: a sign-in that succeeded but whose follow-up
  /// writes failed (offline, server error) leaves a valid session with no
  /// profile, and the next attempt has to be able to finish the job rather
  /// than collide with what already landed.
  Future<SignInResult> _bootstrap({
    required String userId,
    required String? displayName,
  }) async {
    if (!await _backend.profileExists(userId)) {
      await _backend.createProfile(userId: userId, displayName: displayName);
    }

    final existing = await _backend.getHouseholdId(userId);
    if (existing != null) {
      return SignInResult(
        userId: userId,
        householdId: existing,
        householdWasCreated: false,
      );
    }

    final householdId = await _backend.createHousehold(
      userId: userId,
      name: householdNameFor(displayName),
    );

    return SignInResult(
      userId: userId,
      householdId: householdId,
      householdWasCreated: true,
    );
  }

  Future<void> signOut() => _backend.signOut();

  /// "Fatih's garage", or [AppConstants.defaultHouseholdName] when Apple
  /// withheld the name — which happens on every sign-in after the first, and
  /// on the first too if the user chose not to share it.
  @visibleForTesting
  static String householdNameFor(String? displayName) {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return AppConstants.defaultHouseholdName;

    // A name already ending in "s" takes a bare apostrophe.
    final suffix = name.endsWith('s') || name.endsWith('S') ? '’' : '’s';
    return '$name$suffix garage';
  }

  /// A cryptographically random nonce, per sign-in attempt.
  ///
  /// [Random.secure] rather than [Random]: this value is what ties the Apple
  /// identity token to this specific request, so a predictable one would
  /// defeat the replay protection it exists to provide.
  static String _generateNonce([int length = 32]) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
