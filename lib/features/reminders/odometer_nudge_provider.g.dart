// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'odometer_nudge_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The odometer nudge coordinator.
///
/// Lives in its own file because `odometer_nudge_service.dart` imports drift
/// row types, and riverpod_generator 4.0.4 fails on any annotated function in
/// a library that does — see the note in `data/repositories/providers.dart`.

@ProviderFor(odometerNudgeService)
final odometerNudgeServiceProvider = OdometerNudgeServiceProvider._();

/// The odometer nudge coordinator.
///
/// Lives in its own file because `odometer_nudge_service.dart` imports drift
/// row types, and riverpod_generator 4.0.4 fails on any annotated function in
/// a library that does — see the note in `data/repositories/providers.dart`.

final class OdometerNudgeServiceProvider
    extends
        $FunctionalProvider<
          OdometerNudgeService,
          OdometerNudgeService,
          OdometerNudgeService
        >
    with $Provider<OdometerNudgeService> {
  /// The odometer nudge coordinator.
  ///
  /// Lives in its own file because `odometer_nudge_service.dart` imports drift
  /// row types, and riverpod_generator 4.0.4 fails on any annotated function in
  /// a library that does — see the note in `data/repositories/providers.dart`.
  OdometerNudgeServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'odometerNudgeServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$odometerNudgeServiceHash();

  @$internal
  @override
  $ProviderElement<OdometerNudgeService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OdometerNudgeService create(Ref ref) {
    return odometerNudgeService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OdometerNudgeService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OdometerNudgeService>(value),
    );
  }
}

String _$odometerNudgeServiceHash() =>
    r'642e138875b86132504095e5929b23fdc00698f2';
