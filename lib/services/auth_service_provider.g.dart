// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_service_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app-wide [AuthService].
///
/// Kept alive for the process lifetime: it is the source of the signed-in user
/// id that sync and household membership hang off, so tearing it down when the
/// last listener drops would be wrong.
///
/// Tests override this with a service wrapping a fake [AuthBackend].

@ProviderFor(authService)
final authServiceProvider = AuthServiceProvider._();

/// The app-wide [AuthService].
///
/// Kept alive for the process lifetime: it is the source of the signed-in user
/// id that sync and household membership hang off, so tearing it down when the
/// last listener drops would be wrong.
///
/// Tests override this with a service wrapping a fake [AuthBackend].

final class AuthServiceProvider
    extends $FunctionalProvider<AuthService, AuthService, AuthService>
    with $Provider<AuthService> {
  /// The app-wide [AuthService].
  ///
  /// Kept alive for the process lifetime: it is the source of the signed-in user
  /// id that sync and household membership hang off, so tearing it down when the
  /// last listener drops would be wrong.
  ///
  /// Tests override this with a service wrapping a fake [AuthBackend].
  AuthServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authServiceHash();

  @$internal
  @override
  $ProviderElement<AuthService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthService create(Ref ref) {
    return authService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthService>(value),
    );
  }
}

String _$authServiceHash() => r'21d842d4dceafa3d239c0196a0f2b890d37c0b71';

/// The signed-in user's id, or null when signed out.
///
/// Null is the normal state: a free, local-only user never signs in at all.

@ProviderFor(currentUserId)
final currentUserIdProvider = CurrentUserIdProvider._();

/// The signed-in user's id, or null when signed out.
///
/// Null is the normal state: a free, local-only user never signs in at all.

final class CurrentUserIdProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, Stream<String?>>
    with $FutureModifier<String?>, $StreamProvider<String?> {
  /// The signed-in user's id, or null when signed out.
  ///
  /// Null is the normal state: a free, local-only user never signs in at all.
  CurrentUserIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserIdHash();

  @$internal
  @override
  $StreamProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<String?> create(Ref ref) {
    return currentUserId(ref);
  }
}

String _$currentUserIdHash() => r'4873936fd3e841ba50819c8b2b39409ef418b940';

/// The signed-in user's household, or null when signed out or not in one.
///
/// Watches [currentUserIdProvider] rather than reading it once, so signing in
/// or out — including the moment "Join a household" gives the user their
/// first one — re-resolves this rather than leaving it stale.

@ProviderFor(currentHouseholdId)
final currentHouseholdIdProvider = CurrentHouseholdIdProvider._();

/// The signed-in user's household, or null when signed out or not in one.
///
/// Watches [currentUserIdProvider] rather than reading it once, so signing in
/// or out — including the moment "Join a household" gives the user their
/// first one — re-resolves this rather than leaving it stale.

final class CurrentHouseholdIdProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// The signed-in user's household, or null when signed out or not in one.
  ///
  /// Watches [currentUserIdProvider] rather than reading it once, so signing in
  /// or out — including the moment "Join a household" gives the user their
  /// first one — re-resolves this rather than leaving it stale.
  CurrentHouseholdIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentHouseholdIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentHouseholdIdHash();

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    return currentHouseholdId(ref);
  }
}

String _$currentHouseholdIdHash() =>
    r'f0ce754e3b874e34a85923fe87c30158d0476472';
