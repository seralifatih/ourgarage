// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'household_migration_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Invites and membership. Tests override this with a fake backend.

@ProviderFor(householdService)
final householdServiceProvider = HouseholdServiceProvider._();

/// Invites and membership. Tests override this with a fake backend.

final class HouseholdServiceProvider
    extends
        $FunctionalProvider<
          HouseholdService,
          HouseholdService,
          HouseholdService
        >
    with $Provider<HouseholdService> {
  /// Invites and membership. Tests override this with a fake backend.
  HouseholdServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'householdServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$householdServiceHash();

  @$internal
  @override
  $ProviderElement<HouseholdService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HouseholdService create(Ref ref) {
    return householdService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HouseholdService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HouseholdService>(value),
    );
  }
}

String _$householdServiceHash() => r'faedd1522a9f0fc2b94a642bc49b076c35bb9b55';

/// The cloud copy of the garage. Tests override this with a fake.

@ProviderFor(remoteGarage)
final remoteGarageProvider = RemoteGarageProvider._();

/// The cloud copy of the garage. Tests override this with a fake.

final class RemoteGarageProvider
    extends $FunctionalProvider<RemoteGarage, RemoteGarage, RemoteGarage>
    with $Provider<RemoteGarage> {
  /// The cloud copy of the garage. Tests override this with a fake.
  RemoteGarageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'remoteGarageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$remoteGarageHash();

  @$internal
  @override
  $ProviderElement<RemoteGarage> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RemoteGarage create(Ref ref) {
    return remoteGarage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RemoteGarage value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RemoteGarage>(value),
    );
  }
}

String _$remoteGarageHash() => r'af0f397e243078a0d970f0374787b292ac900cd4';

/// The one-time upload of local data into a household.

@ProviderFor(householdMigration)
final householdMigrationProvider = HouseholdMigrationProvider._();

/// The one-time upload of local data into a household.

final class HouseholdMigrationProvider
    extends
        $FunctionalProvider<
          HouseholdMigrationService,
          HouseholdMigrationService,
          HouseholdMigrationService
        >
    with $Provider<HouseholdMigrationService> {
  /// The one-time upload of local data into a household.
  HouseholdMigrationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'householdMigrationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$householdMigrationHash();

  @$internal
  @override
  $ProviderElement<HouseholdMigrationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  HouseholdMigrationService create(Ref ref) {
    return householdMigration(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HouseholdMigrationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HouseholdMigrationService>(value),
    );
  }
}

String _$householdMigrationHash() =>
    r'f972aa46c6a09194497bfa4e8caa2b503329475e';
