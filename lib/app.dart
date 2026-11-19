import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'app_routes.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'data/repositories/database_holder.dart';
import 'features/reminders/odometer_nudge_provider.dart';
import 'data/sync/sync_providers.dart';
import 'features/household/forget_household.dart';
import 'features/notifications/notification_permission.dart';
import 'features/household/household_migration_provider.dart';
import 'features/household/household_premium_claim.dart';
import 'features/reminders/reminder_notification_scheduler.dart';
import 'services/notification_service.dart';
import 'services/auth_service_provider.dart';
import 'services/notification_service_provider.dart';
import 'services/purchase_service_provider.dart';
import 'services/review_prompt_service.dart';

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
    // Counts the open day and acts on a review trigger from a previous
    // session (a purchase, a household join). Never blocks the first frame.
    unawaited(ref.read(reviewPromptServiceProvider).recordAppOpen());
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
      unawaited(_syncIfSharing());
      // Notifications may have been switched on or off in iOS Settings
      // while the app was in the background.
      ref.invalidate(notificationPermissionProvider);
      unawaited(ref.read(reviewPromptServiceProvider).recordAppOpen());
    }
  }

  /// Pushes anything queued and pulls what the household changed.
  ///
  /// Deliberately unawaited and failure-tolerant: this is a background
  /// reconciliation, and nothing the user can see waits on it. Skipped
  /// entirely for the local-only user, who has no household to sync with.
  ///
  /// A signed-in user the server no longer counts as a member — the owner
  /// removed them, or the app died between leaving and its local cleanup — is
  /// unlinked here, so the device stops syncing a household it can't reach.
  Future<void> _syncIfSharing() async {
    final auth = ref.read(authServiceProvider);
    final householdId = await auth.currentHouseholdId();
    if (householdId == null) {
      if (auth.isSignedIn) {
        await forgetHouseholdLocally(DatabaseHolder.instance);
        ref.invalidate(currentHouseholdIdProvider);
      }
      return;
    }

    final sync = ref.read(syncServiceProvider);
    await sync.sync(householdId: householdId);

    // Catch-up for premium that never reached the household: bought before
    // the household existed, or claimed before RevenueCat had linked the
    // purchase to this account. Only when there is something to gain, so a
    // resume normally costs no RevenueCat call.
    final ownPremium = ref.read(purchaseServiceProvider).isPremium;
    final householdPremium = await DatabaseHolder
        .instance
        .householdEntitlementDao
        .isHouseholdPremium();
    if (ownPremium && !householdPremium) {
      await claimHouseholdPremium(
        households: ref.read(householdServiceProvider),
        sync: sync,
        householdId: householdId,
      );
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
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
