import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/service_type.dart';
import '../../data/repositories/providers.dart';
import '../../services/notification_service_provider.dart';

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
        children: [if (_debugToolsRevealed) const _DebugNotificationSection()],
      ),
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
      ],
    );
  }
}
