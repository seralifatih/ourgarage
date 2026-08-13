// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_service_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app-wide [NotificationService].
///
/// Kept alive for the process lifetime: it owns the tap stream the router
/// listens to, so tearing it down when the last listener drops would silently
/// stop deep links working.
///
/// Tests override this with a service wrapping a fake plugin.

@ProviderFor(notificationService)
final notificationServiceProvider = NotificationServiceProvider._();

/// The app-wide [NotificationService].
///
/// Kept alive for the process lifetime: it owns the tap stream the router
/// listens to, so tearing it down when the last listener drops would silently
/// stop deep links working.
///
/// Tests override this with a service wrapping a fake plugin.

final class NotificationServiceProvider
    extends
        $FunctionalProvider<
          NotificationService,
          NotificationService,
          NotificationService
        >
    with $Provider<NotificationService> {
  /// The app-wide [NotificationService].
  ///
  /// Kept alive for the process lifetime: it owns the tap stream the router
  /// listens to, so tearing it down when the last listener drops would silently
  /// stop deep links working.
  ///
  /// Tests override this with a service wrapping a fake plugin.
  NotificationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationServiceHash();

  @$internal
  @override
  $ProviderElement<NotificationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotificationService create(Ref ref) {
    return notificationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationService>(value),
    );
  }
}

String _$notificationServiceHash() =>
    r'1ac16f236bbaf444e97b6a75f065c79853a723af';
