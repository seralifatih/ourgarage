import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../data/repositories/providers.dart';
import '../../reminders/odometer_nudge_provider.dart';
import '../../reminders/reminder_notification_scheduler.dart';
import 'odometer_format.dart';

/// Bottom sheet for recording a fresh odometer reading.
class OdometerUpdateSheet extends ConsumerStatefulWidget {
  const OdometerUpdateSheet({required this.vehicle, super.key});

  final Vehicle vehicle;

  /// Opens the sheet and resolves once it closes.
  static Future<void> show(BuildContext context, Vehicle vehicle) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OdometerUpdateSheet(vehicle: vehicle),
    );
  }

  @override
  ConsumerState<OdometerUpdateSheet> createState() =>
      _OdometerUpdateSheetState();
}

class _OdometerUpdateSheetState extends ConsumerState<OdometerUpdateSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.vehicle.odometer.toString(),
  );
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        // Keeps the field clear of the keyboard.
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Update odometer',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.vehicle.nickname,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Current reading',
                suffixText: widget.vehicle.odometerUnit,
                border: const OutlineInputBorder(),
              ),
              validator: _validate,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _validate(String? raw) {
    final value = int.tryParse(raw?.trim() ?? '');
    if (value == null) return 'Enter a number';
    if (value < 0) return 'Reading cannot be negative';
    // A lower reading is not an error here: this sheet is also how a mistyped
    // reading gets fixed. [_save] asks before going backwards.
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final value = int.parse(_controller.text.trim());

    // Every provider is read before the first await; the sheet may close
    // while the writes are still in flight.
    final vehicles = ref.read(vehicleRepositoryProvider);
    final scheduler = ref.read(reminderNotificationSchedulerProvider);
    final nudge = ref.read(odometerNudgeServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    // Compared against the stored reading, not the one this sheet opened
    // with: a sync or a service record may have moved it since.
    final current =
        (await vehicles.getVehicle(widget.vehicle.id))?.odometer ??
        widget.vehicle.odometer;
    if (!mounted) return;

    // Odometers don't run backwards, so a lower value is either a typo now or
    // the correction of an earlier one. Without this path an over-entered
    // reading (1285000 for 128500) could never be undone, and every distance
    // reminder would stay wrong for good.
    if (value < current && !await _confirmCorrection(value, current)) {
      return;
    }
    if (!mounted) return;

    setState(() => _saving = true);

    try {
      await vehicles.updateOdometer(widget.vehicle.id, value);
    } catch (error, stack) {
      debugPrint('Odometer update failed: $error\n$stack');
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Couldn't save the reading. Please try again."),
          ),
        );
      return;
    }

    if (mounted) Navigator.of(context).pop();

    // On-screen statuses follow the vehicle stream by themselves; scheduled
    // notifications and the nudge don't, so they are rebuilt from the new
    // reading. The reading is already saved, so a failure here is only
    // logged — the next app resume rebuilds the schedule anyway.
    try {
      await scheduler.rescheduleAll();
      await nudge.refreshNudge(from: DateTime.now());
    } catch (error, stack) {
      debugPrint('Rescheduling after odometer update failed: $error\n$stack');
    }
  }

  /// Asks before saving a reading lower than the current one.
  Future<bool> _confirmCorrection(int value, int current) async {
    final unit = widget.vehicle.odometerUnit;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Correct a typo?'),
        content: Text(
          '${formatOdometer(value)} $unit is lower than the current reading, '
          '${formatOdometer(current)} $unit.\n\n'
          'Odometers only go up, so only do this to fix a reading that was '
          'entered wrong. Reminders are recalculated from the corrected '
          'value.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Correct reading'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
