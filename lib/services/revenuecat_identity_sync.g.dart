// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'revenuecat_identity_sync.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Starts the bridge. Read once, eagerly, from `main()` — its return value is
/// never used, only its side effect of subscribing to auth state for the
/// process lifetime.

@ProviderFor(revenueCatIdentitySync)
final revenueCatIdentitySyncProvider = RevenueCatIdentitySyncProvider._();

/// Starts the bridge. Read once, eagerly, from `main()` — its return value is
/// never used, only its side effect of subscribing to auth state for the
/// process lifetime.

final class RevenueCatIdentitySyncProvider
    extends
        $FunctionalProvider<
          RevenueCatIdentitySync,
          RevenueCatIdentitySync,
          RevenueCatIdentitySync
        >
    with $Provider<RevenueCatIdentitySync> {
  /// Starts the bridge. Read once, eagerly, from `main()` — its return value is
  /// never used, only its side effect of subscribing to auth state for the
  /// process lifetime.
  RevenueCatIdentitySyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'revenueCatIdentitySyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$revenueCatIdentitySyncHash();

  @$internal
  @override
  $ProviderElement<RevenueCatIdentitySync> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RevenueCatIdentitySync create(Ref ref) {
    return revenueCatIdentitySync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RevenueCatIdentitySync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RevenueCatIdentitySync>(value),
    );
  }
}

String _$revenueCatIdentitySyncHash() =>
    r'4a211d470151d406f2b6d5bdc7962bc1dcd6a74f';
