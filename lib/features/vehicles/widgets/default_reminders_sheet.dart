import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../data/models/service_type.dart';
import '../../../data/repositories/providers.dart';
import '../../reminders/reminder_notification_scheduler.dart';
import '../../reminders/widgets/notification_permission_sheet.dart';

class _DefaultRuleOption {
  const _DefaultRuleOption({
    required this.type,
    required this.intervalMonths,
    required this.intervalDistance,
  });

  final ServiceType type;
  final int? intervalMonths;
  final int? intervalDistance;
}

/// Offered after creating a vehicle: pre-checked defaults for the reminders
/// most vehicles need. A vehicle with no rules never produces a notification,
/// so steering people toward at least one active rule matters more here than
/// completeness — this is not the place to expose every [ServiceType].
class DefaultRemindersSheet extends ConsumerStatefulWidget {
  const DefaultRemindersSheet({
    required this.vehicleId,
    required this.odometerUnit,
    super.key,
  });

  final String vehicleId;
  final String odometerUnit;

  /// Opens the sheet. Resolves after it closes, whichever way.
  static Future<void> show(
    BuildContext context, {
    required String vehicleId,
    required String odometerUnit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => DefaultRemindersSheet(
        vehicleId: vehicleId,
        odometerUnit: odometerUnit,
      ),
    );
  }

  @override
  ConsumerState<DefaultRemindersSheet> createState() =>
      _DefaultRemindersSheetState();
}

class _DefaultRemindersSheetState extends ConsumerState<DefaultRemindersSheet> {
  late final List<_DefaultRuleOption> _options = _buildOptions();
  late final List<bool> _checked = List.filled(_options.length, true);
  bool _saving = false;

  bool get _isMiles => widget.odometerUnit == 'mi';

  List<_DefaultRuleOption> _buildOptions() {
    final tireRotationDistance = _isMiles
        ? AppConstants.defaultTireRotationIntervalMiles
        : AppConstants.defaultTireRotationIntervalKm;
    final oilDistance = _isMiles
        ? AppConstants.defaultOilIntervalMiles
        : AppConstants.defaultOilIntervalKm;

    return [
      _DefaultRuleOption(
        type: ServiceType.oilChange,
        intervalMonths: AppConstants.defaultOilIntervalMonths,
        intervalDistance: oilDistance,
      ),
      _DefaultRuleOption(
        type: ServiceType.tireRotation,
        intervalMonths: AppConstants.defaultTireRotationIntervalMonths,
        intervalDistance: tireRotationDistance,
      ),
      _DefaultRuleOption(
        type: ServiceType.inspection,
        intervalMonths: AppConstants.defaultInspectionIntervalMonths,
        intervalDistance: null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anyChecked = _checked.contains(true);

    return SingleChildScrollView(
      // Small screens with all three options plus the keyboard inset can
      // exceed the viewport height, so the sheet needs to scroll rather than
      // clip its action buttons off-screen.
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set up reminders?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "We'll remind you before these are due.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _options.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _checked[i],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _checked[i] = value ?? false),
                title: Text(_options[i].type.label),
                subtitle: Text(_describeInterval(_options[i])),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : _skip,
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving || !anyChecked ? null : _save,
                  child: const Text('Add reminders'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _describeInterval(_DefaultRuleOption option) {
    final parts = <String>[];
    if (option.intervalMonths != null) {
      parts.add('every ${option.intervalMonths} months');
    }
    if (option.intervalDistance != null) {
      parts.add('every ${option.intervalDistance} ${widget.odometerUnit}');
    }
    return parts.join(' or ');
  }

  void _skip() => Navigator.of(context).pop();

  Future<void> _save() async {
    setState(() => _saving = true);

    final repository = ref.read(reminderRuleRepositoryProvider);
    final scheduler = ref.read(reminderNotificationSchedulerProvider);
    final createdRuleIds = <String>[];

    for (var i = 0; i < _options.length; i++) {
      if (!_checked[i]) continue;
      final option = _options[i];
      createdRuleIds.add(
        await repository.createRule(
          vehicleId: widget.vehicleId,
          type: option.type,
          intervalMonths: option.intervalMonths,
          intervalDistance: option.intervalDistance,
        ),
      );
    }

    // Ask for notification permission here rather than at launch: the user has
    // just asked to be reminded, so the prompt lands with its reason obvious.
    // iOS only ever shows it once, which makes the timing worth getting right.
    if (createdRuleIds.isNotEmpty && mounted) {
      await NotificationPermissionSheet.show(context);
    }

    // Schedule regardless of the answer. If permission was declined the OS
    // silently drops these, and if it's granted later in Settings the rules
    // are already queued rather than needing a re-save.
    for (final ruleId in createdRuleIds) {
      await scheduler.rescheduleForRule(ruleId);
    }

    if (mounted) Navigator.of(context).pop();
  }
}
