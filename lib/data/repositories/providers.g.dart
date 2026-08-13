// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(vehicleRepository)
final vehicleRepositoryProvider = VehicleRepositoryProvider._();

final class VehicleRepositoryProvider
    extends
        $FunctionalProvider<
          VehicleRepository,
          VehicleRepository,
          VehicleRepository
        >
    with $Provider<VehicleRepository> {
  VehicleRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vehicleRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vehicleRepositoryHash();

  @$internal
  @override
  $ProviderElement<VehicleRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VehicleRepository create(Ref ref) {
    return vehicleRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VehicleRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VehicleRepository>(value),
    );
  }
}

String _$vehicleRepositoryHash() => r'3c84d621f01a7b5d8b7359a2ec06e48e417e13cb';

@ProviderFor(serviceRecordRepository)
final serviceRecordRepositoryProvider = ServiceRecordRepositoryProvider._();

final class ServiceRecordRepositoryProvider
    extends
        $FunctionalProvider<
          ServiceRecordRepository,
          ServiceRecordRepository,
          ServiceRecordRepository
        >
    with $Provider<ServiceRecordRepository> {
  ServiceRecordRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serviceRecordRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serviceRecordRepositoryHash();

  @$internal
  @override
  $ProviderElement<ServiceRecordRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ServiceRecordRepository create(Ref ref) {
    return serviceRecordRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ServiceRecordRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ServiceRecordRepository>(value),
    );
  }
}

String _$serviceRecordRepositoryHash() =>
    r'022400e5a1111236a4166000d06ed661e61efce8';

@ProviderFor(reminderRuleRepository)
final reminderRuleRepositoryProvider = ReminderRuleRepositoryProvider._();

final class ReminderRuleRepositoryProvider
    extends
        $FunctionalProvider<
          ReminderRuleRepository,
          ReminderRuleRepository,
          ReminderRuleRepository
        >
    with $Provider<ReminderRuleRepository> {
  ReminderRuleRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderRuleRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderRuleRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReminderRuleRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReminderRuleRepository create(Ref ref) {
    return reminderRuleRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReminderRuleRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReminderRuleRepository>(value),
    );
  }
}

String _$reminderRuleRepositoryHash() =>
    r'eecb488d7c21a3f6cba9a21b9b9bd2b7e08eda99';
