// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reminder_notification_scheduler.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reminderNotificationScheduler)
final reminderNotificationSchedulerProvider =
    ReminderNotificationSchedulerProvider._();

final class ReminderNotificationSchedulerProvider
    extends
        $FunctionalProvider<
          ReminderNotificationScheduler,
          ReminderNotificationScheduler,
          ReminderNotificationScheduler
        >
    with $Provider<ReminderNotificationScheduler> {
  ReminderNotificationSchedulerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderNotificationSchedulerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderNotificationSchedulerHash();

  @$internal
  @override
  $ProviderElement<ReminderNotificationScheduler> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReminderNotificationScheduler create(Ref ref) {
    return reminderNotificationScheduler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReminderNotificationScheduler value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReminderNotificationScheduler>(
        value,
      ),
    );
  }
}

String _$reminderNotificationSchedulerHash() =>
    r'd54b74b0437af4a1aa8767bba849203af267954d';
