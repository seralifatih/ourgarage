import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/readable_width.dart';
import '../../core/widgets/load_error_view.dart';
import '../../data/local/database.dart';
import '../../data/models/service_type.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/stream_providers.dart';
import 'reminder_notification_scheduler.dart';
import 'widgets/notification_permission_sheet.dart';

/// Add or edit a reminder rule for a vehicle.
///
/// On save, the rule is persisted and its notification is scheduled or
/// cancelled to match — see [ReminderNotificationScheduler.rescheduleForRule].
/// The very first rule the user ever creates, on any vehicle, shows the
/// notification permission explainer first: that is the one moment asking
/// "why would this app want to notify me?" has an obvious answer.
class ReminderRuleFormScreen extends ConsumerWidget {
  const ReminderRuleFormScreen({
    required this.vehicleId,
    this.ruleId,
    super.key,
  });

  final String vehicleId;
  final String? ruleId;

  bool get isEditing => ruleId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleAsync = ref.watch(vehicleStreamProvider(vehicleId));

    return vehicleAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit reminder' : 'Add reminder'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit reminder' : 'Add reminder'),
        ),
        body: LoadErrorView(
          message: "Couldn't load this vehicle",
          error: error,
          stackTrace: stack,
          onRetry: () => ref.invalidate(vehicleStreamProvider(vehicleId)),
        ),
      ),
      data: (vehicle) {
        if (vehicle == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(isEditing ? 'Edit reminder' : 'Add reminder'),
            ),
            body: const Center(child: Text('Vehicle not found')),
          );
        }

        if (!isEditing) {
          return _ReminderRuleForm(vehicle: vehicle, initial: null);
        }

        final rulesAsync = ref.watch(reminderRulesStreamProvider(vehicleId));
        return rulesAsync.when(
          loading: () => Scaffold(
            appBar: AppBar(title: const Text('Edit reminder')),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => Scaffold(
            appBar: AppBar(title: const Text('Edit reminder')),
            body: LoadErrorView(
              message: "Couldn't load this reminder",
              error: error,
              stackTrace: stack,
              onRetry: () =>
                  ref.invalidate(reminderRulesStreamProvider(vehicleId)),
            ),
          ),
          data: (rules) {
            final rule = rules.where((r) => r.id == ruleId).firstOrNull;
            if (rule == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Edit reminder')),
                body: const Center(child: Text('Reminder not found')),
              );
            }
            return _ReminderRuleForm(vehicle: vehicle, initial: rule);
          },
        );
      },
    );
  }
}

class _ReminderRuleForm extends ConsumerStatefulWidget {
  const _ReminderRuleForm({required this.vehicle, required this.initial});

  final Vehicle vehicle;
  final ReminderRule? initial;

  bool get isEditing => initial != null;

  @override
  ConsumerState<_ReminderRuleForm> createState() => _ReminderRuleFormState();
}

class _ReminderRuleFormState extends ConsumerState<_ReminderRuleForm> {
  final _formKey = GlobalKey<FormState>();

  late ServiceType _type = widget.initial == null
      ? ServiceType.oilChange
      : ServiceType.fromName(widget.initial!.type);

  late final TextEditingController _customLabel = TextEditingController(
    text: widget.initial?.customTypeLabel ?? '',
  );

  late final TextEditingController _intervalMonths = TextEditingController(
    text: widget.initial?.intervalMonths?.toString() ?? '',
  );

  late final TextEditingController _intervalDistance = TextEditingController(
    text: widget.initial?.intervalDistance?.toString() ?? '',
  );

  DateTime? _lastDoneAt;

  late final TextEditingController _lastDoneOdometer = TextEditingController(
    text: widget.initial?.lastDoneOdometer?.toString() ?? '',
  );

  bool _saving = false;
  bool _formValid = false;

  @override
  void initState() {
    super.initState();
    _lastDoneAt = widget.initial?.lastDoneAt;

    for (final controller in [
      _customLabel,
      _intervalMonths,
      _intervalDistance,
      _lastDoneOdometer,
    ]) {
      controller.addListener(_revalidate);
    }
    _formValid = _isFormValid();
  }

  @override
  void dispose() {
    _customLabel.dispose();
    _intervalMonths.dispose();
    _intervalDistance.dispose();
    _lastDoneOdometer.dispose();
    super.dispose();
  }

  /// Enables or disables Save without painting error text on fields the
  /// user hasn't touched — see the vehicle form for why not `validate()`.
  void _revalidate() {
    final isValid = _isFormValid();
    if (isValid != _formValid) {
      setState(() => _formValid = isValid);
    }
  }

  bool _isFormValid() =>
      _validateCustomLabel(_customLabel.text) == null &&
      _validateIntervals() == null &&
      _validateLastDoneOdometer(_lastDoneOdometer.text) == null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit reminder' : 'Add reminder'),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete reminder',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        // Per field, not here: a Form-level onUserInteraction validates
        // every field as soon as any one is touched.
        onChanged: _revalidate,
        child: ListView(
          padding: readablePadding(
            context,
            const EdgeInsets.fromLTRB(16, 16, 16, 32),
          ),
          children: [
            DropdownButtonFormField<ServiceType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final type in ServiceType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _type = value);
                // The custom-label requirement just appeared or went away.
                _revalidate();
              },
            ),
            if (_type == ServiceType.custom) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customLabel,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Custom type',
                  hintText: 'e.g. Windshield replacement',
                  border: OutlineInputBorder(),
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateCustomLabel,
              ),
            ],
            const SizedBox(height: 20),
            Text('Repeat every', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Set one or both — whichever comes first is what triggers the '
              'reminder.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _intervalMonths,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Interval (months)',
                suffixText: 'months',
                border: OutlineInputBorder(),
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (_) => _validateIntervals(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _intervalDistance,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Interval (distance)',
                suffixText: widget.vehicle.odometerUnit,
                border: const OutlineInputBorder(),
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (_) => _validateIntervals(),
            ),
            const SizedBox(height: 20),
            Text(
              'Last done (optional)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            _LastDoneDateField(
              date: _lastDoneAt,
              onChanged: (date) => setState(() => _lastDoneAt = date),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastDoneOdometer,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Odometer when last done',
                suffixText: widget.vehicle.odometerUnit,
                border: const OutlineInputBorder(),
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: _validateLastDoneOdometer,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _formValid && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.isEditing ? 'Save changes' : 'Add reminder'),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateCustomLabel(String? raw) {
    if (_type != ServiceType.custom) return null;
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Enter a label for this custom type';
    return null;
  }

  /// Both interval fields share this validator: neither is individually
  /// required, but at least one of them must be filled. Attaching it to both
  /// means the error surfaces next to the fields it's about, and re-runs
  /// automatically as either one changes.
  String? _validateIntervals() {
    final months = _intervalMonths.text.trim();
    final distance = _intervalDistance.text.trim();
    if (months.isEmpty && distance.isEmpty) {
      return 'Set an interval in months, distance, or both';
    }
    return null;
  }

  String? _validateLastDoneOdometer(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null; // optional

    final odometer = int.tryParse(value);
    if (odometer == null || odometer < 0) {
      return 'Enter a reading of 0 or more';
    }
    return null;
  }

  /// Deletes this rule, with Undo in a snackbar rather than a confirmation:
  /// the same safety net as deleting a service record.
  ///
  /// Pops first: the screen around this form watches the rule list, and once
  /// the rule is gone it would swap this form out for "Reminder not found"
  /// before the pop could run.
  Future<void> _delete() async {
    final repository = ref.read(reminderRuleRepositoryProvider);
    final scheduler = ref.read(reminderNotificationSchedulerProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ruleId = widget.initial!.id;

    context.pop();

    await repository.softDeleteRule(ruleId);
    // Cancels its pending notification: the rule is deleted now.
    await scheduler.rescheduleForRule(ruleId);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Reminder deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await repository.restoreRule(ruleId);
              await scheduler.rescheduleForRule(ruleId);
            },
          ),
        ),
      );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final monthsText = _intervalMonths.text.trim();
    final distanceText = _intervalDistance.text.trim();
    final odometerText = _lastDoneOdometer.text.trim();
    final customLabel = _customLabel.text.trim();

    final intervalMonths = monthsText.isEmpty ? null : int.parse(monthsText);
    final intervalDistance = distanceText.isEmpty
        ? null
        : int.parse(distanceText);
    final lastDoneOdometer = odometerText.isEmpty
        ? null
        : int.parse(odometerText);

    final repository = ref.read(reminderRuleRepositoryProvider);
    final scheduler = ref.read(reminderNotificationSchedulerProvider);

    if (widget.isEditing) {
      await repository.updateRule(
        widget.initial!.id,
        type: _type,
        customTypeLabel: Value(
          _type == ServiceType.custom ? customLabel : null,
        ),
        intervalMonths: Value(intervalMonths),
        intervalDistance: Value(intervalDistance),
        lastDoneAt: Value(_lastDoneAt),
        lastDoneOdometer: Value(lastDoneOdometer),
      );

      await scheduler.rescheduleForRule(widget.initial!.id);

      if (mounted) context.pop();
      return;
    }

    // This is the sole moment the permission ask is tied to this screen: only
    // for the very first reminder the user has ever created, anywhere. Every
    // later rule schedules silently — asking again would just be noise.
    final isFirstEverRule = !(await repository.hasAnyRuleEverExisted());

    final ruleId = await repository.createRule(
      vehicleId: widget.vehicle.id,
      type: _type,
      customTypeLabel: _type == ServiceType.custom ? customLabel : null,
      intervalMonths: intervalMonths,
      intervalDistance: intervalDistance,
      lastDoneAt: _lastDoneAt,
      lastDoneOdometer: lastDoneOdometer,
    );

    if (isFirstEverRule && mounted) {
      await NotificationPermissionSheet.show(context);
    }

    // Schedule regardless of the answer: a later grant in Settings should not
    // require re-saving every rule to pick it up.
    await scheduler.rescheduleForRule(ruleId);

    if (!mounted) return;
    context.pop(ruleId);
  }
}

class _LastDoneDateField extends StatelessWidget {
  const _LastDoneDateField({required this.date, required this.onChanged});

  final DateTime? date;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pickDate(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Last done date',
          border: const OutlineInputBorder(),
          suffixIcon: date == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          date == null ? 'Not set' : DateFormat('d MMM yyyy').format(date!),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (date != null && !date!.isAfter(now)) ? date! : now,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked != null) onChanged(picked);
  }
}
