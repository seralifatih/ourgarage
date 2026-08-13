import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'app_routes.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'features/reminders/odometer_nudge_provider.dart';
import 'features/reminders/reminder_notification_scheduler.dart';
import 'services/notification_service.dart';
import 'services/notification_service_provider.dart';

class OurGarageApp extends ConsumerStatefulWidget {
  const OurGarageApp({super.key});

  @override
  ConsumerState<OurGarageApp> createState() => _OurGarageAppState();
}

class _OurGarageAppState extends ConsumerState<OurGarageApp>
    with WidgetsBindingObserver {
  StreamSubscription<NotificationTap>? _tapSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startNotifications());
  }

  @override
  void dispose() {
    unawaited(_tapSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS can drop pending notifications after a restore or forced restart
    // without telling us, so every resume rebuilds the whole schedule.
    if (state == AppLifecycleState.resumed) {
      unawaited(_rescheduleAll());
    }
  }

  Future<void> _startNotifications() async {
    final notifications = ref.read(notificationServiceProvider);

    // Initialising requests no permission — see NotificationService.init.
    await notifications.init();

    _tapSubscription = notifications.taps.listen(_handleTap);

    // A tap that launched the app from terminated never reaches the stream.
    final launchTap = await notifications.initialTap();
    if (launchTap != null) _handleTap(launchTap);

    await _rescheduleAll();
  }

  /// Rebuilds every scheduled notification, reminders and nudge alike.
  Future<void> _rescheduleAll() async {
    await ref.read(reminderNotificationSchedulerProvider).rescheduleAll();
    // The nudge is planned separately: whether it should exist at all depends
    // on live state (does any vehicle have a distance rule, and is its reading
    // already fresh?) rather than on a fixed schedule.
    await ref.read(odometerNudgeServiceProvider).refreshNudge();
  }

  /// Routes a tapped notification.
  ///
  /// The odometer nudge belongs to no single vehicle — it opens the screen
  /// that updates them all at once.
  void _handleTap(NotificationTap tap) {
    if (tap.isOdometerNudge) {
      appRouter.go(AppRoutes.updateOdometers);
      return;
    }

    final vehicleId = tap.vehicleId;
    if (vehicleId == null) return;
    appRouter.go(AppRoutes.vehicleDetail(vehicleId));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
