import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_routes.dart';
import '../../core/constants.dart';
import '../../data/local/database.dart';
import '../../data/models/service_type.dart';
import '../../data/repositories/database_holder.dart';
import '../../data/repositories/premium_status_provider.dart';
import '../../data/repositories/providers.dart';
import '../../services/auth_service.dart';
import '../../services/auth_service_provider.dart';
import '../../services/notification_service_provider.dart';
import '../../debug/demo_data.dart';
import '../account/account_deletion_service.dart';
import '../export/export_service.dart';
import '../../services/purchase_service_provider.dart';
import '../paywall/paywall_providers.dart';

/// App settings.
///
/// In debug builds, tapping the title five times reveals a hidden section for
/// exercising the real notification-scheduling code against a physical
/// device — the production intervals (6 months, 8000 miles) can't be waited
/// out by hand, so this is the only practical way to verify the plugin call,
/// channel configuration and payload end-to-end.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _titleTapCount = 0;
  bool _debugToolsRevealed = false;

  void _onTitleTap() {
    if (!kDebugMode || _debugToolsRevealed) return;

    _titleTapCount++;
    if (_titleTapCount >= 5) {
      setState(() => _debugToolsRevealed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTap,
          behavior: HitTestBehavior.opaque,
          child: const Text('Settings'),
        ),
      ),
      body: ListView(
        children: [
          const _PurchasesSection(),
          const _ExportSection(),
          const _HouseholdSection(),
          const _FeedbackSection(),
          const _AccountSection(),
          if (kDebugMode) const _DemoDataSection(),
          if (_debugToolsRevealed) const _DebugNotificationSection(),
        ],
      ),
    );
  }
}

/// Purchase-related settings.
///
/// "Restore purchases" is not optional: Apple rejects apps that sell a
/// non-consumable without an in-app way to restore it on a new device or
/// after a reinstall.
class _PurchasesSection extends ConsumerStatefulWidget {
  const _PurchasesSection();

  @override
  ConsumerState<_PurchasesSection> createState() => _PurchasesSectionState();
}

class _PurchasesSectionState extends ConsumerState<_PurchasesSection> {
  bool _restoring = false;

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    final purchases = ref.read(purchaseServiceProvider);

    setState(() => _restoring = true);

    String message;
    try {
      final isPremium = await purchases.restorePurchases();
      message = isPremium
          ? 'Purchases restored'
          : 'No previous purchases found';
    } on PlatformException catch (error) {
      message = error.message ?? 'Could not restore purchases';
    } finally {
      if (mounted) setState(() => _restoring = false);
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(premiumStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('OurGarage Premium'),
          subtitle: Text(isPremium ? 'Active' : 'Not active'),
          // Already-premium users have nothing to buy, so the row stops being
          // a paywall entry point once the entitlement is active.
          trailing: isPremium ? null : const Icon(Icons.chevron_right),
          onTap: isPremium ? null : () => context.push(AppRoutes.paywall),
        ),
        ListTile(
          title: const Text('Restore purchases'),
          subtitle: const Text(
            'Already bought Premium? Restore it on this device.',
          ),
          trailing: _restoring
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _restoring ? null : _restore,
        ),
      ],
    );
  }
}

/// What the export sheet returns: the CSV, or one vehicle's PDF history.
sealed class _ExportChoice {
  const _ExportChoice();
}

class _CsvChoice extends _ExportChoice {
  const _CsvChoice();
}

class _PdfChoice extends _ExportChoice {
  const _PdfChoice(this.vehicle);
  final Vehicle vehicle;
}

/// "Export records" — a Premium feature, as the paywall promises ("Log
/// service costs and export your records").
///
/// Without Premium the row is still shown, and opens the paywall: hiding it
/// would make the paywall's promise unfindable. With Premium it offers the
/// all-vehicles CSV, or a PDF service history per vehicle (the resale
/// document), and hands the file to the iOS share sheet.
class _ExportSection extends ConsumerStatefulWidget {
  const _ExportSection();

  @override
  ConsumerState<_ExportSection> createState() => _ExportSectionState();
}

class _ExportSectionState extends ConsumerState<_ExportSection> {
  bool _exporting = false;

  /// The row's on-screen rect: the iPad share sheet is a popover and needs
  /// an anchor.
  Rect? _originOf(BuildContext tileContext) {
    final box = tileContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _snack(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onTap(BuildContext tileContext) async {
    if (!ref.read(premiumStatusProvider)) {
      context.push(AppRoutes.paywall);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(exportServiceProvider);
    final origin = _originOf(tileContext);

    final List<Vehicle> vehicles;
    try {
      vehicles = await service.vehicles();
    } catch (error) {
      debugPrint('Export: could not read vehicles: $error');
      _snack(messenger, 'Could not export your records. Please try again.');
      return;
    }
    if (!mounted) return;
    if (vehicles.isEmpty) {
      _snack(messenger, 'Nothing to export yet. Add a vehicle first.');
      return;
    }

    final choice = await showModalBottomSheet<_ExportChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('All records (CSV)'),
              subtitle: const Text(
                'Every vehicle and service, with dates, mileage and costs. '
                'Opens in Numbers, Excel or Google Sheets.',
              ),
              onTap: () => Navigator.of(sheetContext).pop(const _CsvChoice()),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Service history (PDF)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final vehicle in vehicles)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(vehicle.nickname),
                subtitle: const Text('For a buyer, or your own records'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_PdfChoice(vehicle)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      switch (choice) {
        case _CsvChoice():
          await service.shareRecordsCsv(origin: origin);
        case _PdfChoice(:final vehicle):
          await service.shareServiceHistoryPdf(vehicle, origin: origin);
      }
    } catch (error) {
      debugPrint('Export failed: $error');
      _snack(messenger, 'Could not export your records. Please try again.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(premiumStatusProvider);

    return Builder(
      builder: (tileContext) => ListTile(
        leading: const Icon(Icons.ios_share),
        title: const Text('Export records'),
        subtitle: Text(
          isPremium
              ? 'CSV of every service, or a PDF service history per vehicle'
              : 'Premium: CSV of every service, or a PDF service history '
                    'per vehicle',
        ),
        trailing: _exporting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: _exporting ? null : () => _onTap(tileContext),
      ),
    );
  }
}

/// "Join a household" — the second and only other trigger for auth, alongside
/// "Share with household" on a vehicle.
///
/// Shown to anyone not already in a household, signed in or not: a signed-out
/// user can join (they'll be asked to sign in as part of it), and a signed-in
/// user who never shared their own garage has no household yet either. Once
/// they're in one, the row has nothing left to do, so it disappears rather
/// than sitting there as a dead tap target.
class _HouseholdSection extends ConsumerWidget {
  const _HouseholdSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdId = ref.watch(currentHouseholdIdProvider);

    // While loading, and on error, default to showing the row: a stale "no
    // household" read means a spurious extra tap into a screen that then
    // finds out the real state, which is far better than a row that
    // disappears and reappears as connectivity comes and goes.
    final alreadyInHousehold = householdId.asData?.value != null;
    if (alreadyInHousehold) return const SizedBox.shrink();

    return ListTile(
      title: const Text('Join a household'),
      subtitle: const Text('Have an invite code? Join to share a garage.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(AppRoutes.joinHousehold),
    );
  }
}

/// "Rate OurGarage" and "Something wrong? Message me".
///
/// Always shown, and deliberately independent of the system rating prompt:
/// App Store guideline 5.6.1 forbids gating or pre-screening that prompt, so
/// these are plain links, never a "do you like the app?" question in front
/// of it.
class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection();

  Future<void> _open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('Could not open $uri: $error');
    }
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  /// A mailto with the app and OS version prefilled, so a report arrives
  /// with what is needed to reproduce it.
  static Future<Uri> _feedbackEmail() async {
    var appVersion = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = '${info.version} (${info.buildNumber})';
    } catch (error) {
      debugPrint('Could not read app version: $error');
    }
    final osName = Platform.isIOS ? 'iOS' : Platform.operatingSystem;
    final body =
        '\n\n---\n'
        'App version: $appVersion\n'
        '$osName version: ${Platform.operatingSystemVersion}\n';

    // Built by hand: Uri.queryParameters encodes spaces as "+", which mail
    // clients show literally.
    return Uri.parse(
      'mailto:${AppConstants.feedbackEmail}'
      '?subject=${Uri.encodeComponent('OurGarage feedback')}'
      '&body=${Uri.encodeComponent(body)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.star_outline),
          title: const Text('Rate OurGarage'),
          onTap: () =>
              _open(context, Uri.parse(AppConstants.appStoreReviewUrl)),
        ),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: const Text('Something wrong? Message me'),
          onTap: () async {
            final uri = await _feedbackEmail();
            if (context.mounted) await _open(context, uri);
          },
        ),
      ],
    );
  }
}

/// "Delete account" (App Store guideline 5.1.1(v)).
///
/// Only shown when signed in: a free, local-only user has no account, and
/// their data lives only on the device, where deleting the app removes it.
class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _busy = false;

  static const _signedOutMessage =
      "You've been signed out. If your account still exists, sign in again "
      'and delete it from Settings.';

  void _snack(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String describe(DeletionImpact impact) {
    String others(int n) => n == 1 ? '1 other member' : '$n other members';
    return switch (impact) {
      NoHousehold() => 'Your account is deleted from our servers.',
      SoleMember() =>
        'Your household and everything shared in it — cars, service '
            'history and reminders — are deleted from our servers.',
      OwnerHandsOver(:final otherMembers) =>
        'Your household is handed to the member who joined first. The cars '
            'and service history stay for the ${others(otherMembers)}.',
      LeavesHousehold(:final otherMembers) =>
        'You leave your household. The cars and service history stay for '
            'the ${others(otherMembers)}.',
    };
  }

  Future<bool> _confirm(DeletionImpact impact) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in [
                describe(impact),
                'Your account and sign-in are deleted, and OurGarage\'s '
                    'access to your Apple ID is revoked.',
                'Everything on this iPhone stays. You can keep using '
                    'OurGarage without an account.',
                'If your purchase gave your household Premium, Premium leaves '
                    'with you: it stays on your Apple ID, and you can restore '
                    'it later. Deleting your account does not cancel an App '
                    'Store subscription. Manage it in Settings → your name → '
                    'Subscriptions.',
                'To confirm, you\'ll sign in with Apple once more.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(line),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _onTap() async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(accountDeletionServiceProvider);

    setState(() => _busy = true);
    try {
      final DeletionImpact impact;
      try {
        impact = await service.impact();
      } on SessionInvalidException {
        _snack(messenger, _signedOutMessage);
        return;
      } catch (error) {
        debugPrint('Could not load deletion impact: $error');
        _snack(
          messenger,
          'Could not reach OurGarage. Check your connection and try again.',
        );
        return;
      }
      if (!mounted || !await _confirm(impact) || !mounted) return;

      final deleted = await service.deleteAccount();
      if (deleted) {
        _snack(
          messenger,
          'Your account was deleted. Everything on this iPhone is still here.',
        );
      }
    } on SessionInvalidException {
      _snack(messenger, _signedOutMessage);
    } catch (error) {
      debugPrint('Account deletion failed: $error');
      _snack(
        messenger,
        'Could not delete your account. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    // Still restoring the session: show nothing rather than flash "Not
    // signed in" for a frame on launch.
    if (userId.isLoading && !userId.hasValue) return const SizedBox.shrink();

    // `value` keeps the last known user through a transient stream error, so
    // a signed-in user doesn't briefly lose "Delete account". An error with
    // no previous value means Supabase isn't configured in this build, which
    // for the user is the same as not signed in: everything is local.
    final signedIn = userId.value != null;

    // Always shown, so a reviewer (or a user) can tell at a glance whether
    // this device has an account — and therefore why "Delete account" does
    // or doesn't appear under it.
    final status = ListTile(
      leading: Icon(
        signedIn ? Icons.account_circle_outlined : Icons.phone_iphone,
      ),
      title: Text(
        signedIn
            ? 'Signed in with Apple'
            : 'Not signed in — data stays on this device',
      ),
    );
    if (!signedIn) return status;

    final error = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        status,
        ListTile(
          leading: Icon(Icons.person_remove_outlined, color: error),
          title: Text('Delete account', style: TextStyle(color: error)),
          subtitle: const Text(
            'Delete your OurGarage account and the data shared through it',
          ),
          trailing: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _busy ? null : _onTap,
        ),
      ],
    );
  }
}

/// Debug-only: loads or removes the sample garage from `DemoData`.
class _DemoDataSection extends StatelessWidget {
  const _DemoDataSection();

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      await action();
      message = done;
    } catch (error) {
      message = 'Demo data failed: $error';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('Load demo data'),
          subtitle: const Text(
            '3 vehicles, service history, reminders and premium (debug only)',
          ),
          onTap: () => _run(
            context,
            () => DemoData.load(DatabaseHolder.instance),
            'Demo data loaded',
          ),
        ),
        ListTile(
          title: const Text('Clear demo data'),
          subtitle: const Text('Removes only the demo rows (debug only)'),
          onTap: () => _run(
            context,
            () => DemoData.clear(DatabaseHolder.instance),
            'Demo data cleared',
          ),
        ),
      ],
    );
  }
}

class _DebugNotificationSection extends ConsumerWidget {
  const _DebugNotificationSection();

  Future<void> _fireTestReminder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final vehicleRepository = ref.read(vehicleRepositoryProvider);
    final ruleRepository = ref.read(reminderRuleRepositoryProvider);
    final notifications = ref.read(notificationServiceProvider);

    final vehicles = await vehicleRepository.watchAllVehicles().first;
    if (vehicles.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No vehicle exists to attach a test reminder to'),
          ),
        );
      return;
    }

    final vehicle = vehicles.first;
    final fireAt = DateTime.now().add(const Duration(minutes: 2));

    // A real rule, through the real repository, so scheduling runs off the
    // same data every production reminder does. `lastDoneAt` is set to make
    // the interval irrelevant to the fire time — `fireAt` below is what
    // actually drives the notification.
    final ruleId = await ruleRepository.createRule(
      vehicleId: vehicle.id,
      type: ServiceType.custom,
      customTypeLabel: 'Debug test reminder',
      intervalMonths: 1,
      lastDoneAt: DateTime.now(),
    );

    final notificationId = await notifications.scheduleDebugTestReminder(
      ruleId: ruleId,
      vehicleId: vehicle.id,
      vehicleNickname: vehicle.nickname,
      typeLabel: 'Debug test reminder',
      fireAt: fireAt,
    );

    // The rule only exists to carry a valid ruleId/payload through the real
    // scheduling path; nothing about it should linger in the vehicle's actual
    // reminder list once the notification is scheduled.
    await ruleRepository.softDeleteRule(ruleId);

    debugPrint(
      '[debug] scheduled test reminder id=$notificationId fireAt=$fireAt',
    );

    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Test reminder scheduled for $fireAt')),
      );
  }

  Future<void> _printPendingNotifications(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifications = ref.read(notificationServiceProvider);

    final pending = await notifications.pendingNotificationRequests();

    debugPrint('[debug] ${pending.length} pending notification(s):');
    for (final request in pending) {
      debugPrint('[debug]   id=${request.id} title=${request.title}');
    }

    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${pending.length} pending — see console')),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchaseServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            'DEBUG',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
        ),
        ListTile(
          title: const Text('Debug: fire test reminder'),
          subtitle: const Text(
            'Schedules a real notification 2 minutes from now on the first '
            'vehicle',
          ),
          onTap: () => _fireTestReminder(context, ref),
        ),
        ListTile(
          title: const Text('Debug: print pending notifications'),
          subtitle: const Text('Logs the pending count, ids and titles'),
          onTap: () => _printPendingNotifications(context, ref),
        ),
        // Forces PaywallScreen's "no offering available" fallback, so it can
        // be verified on-device without airplane mode — which would also kill
        // an in-flight sandbox purchase mid-test.
        StatefulBuilder(
          builder: (context, setState) {
            return SwitchListTile(
              title: const Text('Debug: force no offerings on paywall'),
              subtitle: const Text(
                'Simulates RevenueCat returning no products, without '
                'breaking connectivity',
              ),
              value: purchases.debugForceNoOfferings,
              onChanged: (value) {
                setState(() => purchases.debugForceNoOfferings = value);
                ref.invalidate(currentOfferingProvider);
              },
            );
          },
        ),
      ],
    );
  }
}
