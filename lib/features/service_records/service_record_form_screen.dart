import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/local/database.dart';
import '../../data/models/service_type.dart';
import '../../data/repositories/premium_status_provider.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/stream_providers.dart';
import '../../services/review_prompt_service.dart';
import '../reminders/reminder_engine.dart';
import '../reminders/reminder_engine_adapter.dart';
import '../reminders/reminder_notification_scheduler.dart';
import '../reminders/reminder_status_label.dart';
import 'currency_default.dart';
import 'widgets/premium_cost_field.dart';

/// Add or edit a service record for a vehicle.
///
/// On create, if there's an active [ReminderRule] on this vehicle matching the
/// record's [ServiceType], saving marks that rule done with this record's date
/// and odometer and re-schedules its notification. This is the core loop the
/// product depends on: logging a service silently resets the corresponding
/// reminder without the user doing anything extra.
class ServiceRecordFormScreen extends ConsumerWidget {
  const ServiceRecordFormScreen({
    required this.vehicleId,
    this.recordId,
    super.key,
  });

  final String vehicleId;
  final String? recordId;

  bool get isEditing => recordId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleAsync = ref.watch(vehicleStreamProvider(vehicleId));

    return vehicleAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit service' : 'Add service')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit service' : 'Add service')),
        body: Center(child: Text('$error')),
      ),
      data: (vehicle) {
        if (vehicle == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(isEditing ? 'Edit service' : 'Add service'),
            ),
            body: const Center(child: Text('Vehicle not found')),
          );
        }

        if (!isEditing) {
          return _ServiceRecordForm(vehicle: vehicle, initial: null);
        }

        final recordAsync = ref.watch(
          _serviceRecordProvider((vehicleId: vehicleId, recordId: recordId!)),
        );
        return recordAsync.when(
          loading: () => Scaffold(
            appBar: AppBar(title: const Text('Edit service')),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(title: const Text('Edit service')),
            body: Center(child: Text('$error')),
          ),
          data: (record) {
            if (record == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Edit service')),
                body: const Center(child: Text('Record not found')),
              );
            }
            return _ServiceRecordForm(vehicle: vehicle, initial: record);
          },
        );
      },
    );
  }
}

/// Looks up a single record by id from the vehicle's history stream.
///
/// A dedicated single-record repository stream doesn't exist, and the history
/// list is already kept live for the detail screen, so this reuses it rather
/// than adding a new DAO query for a rarely-hit edit path.
final _serviceRecordProvider = Provider.autoDispose
    .family<AsyncValue<ServiceRecord?>, ({String vehicleId, String recordId})>((
      ref,
      args,
    ) {
      final recordsAsync = ref.watch(
        serviceRecordsStreamProvider(args.vehicleId),
      );
      return recordsAsync.whenData(
        (records) => records.where((r) => r.id == args.recordId).firstOrNull,
      );
    });

class _ServiceRecordForm extends ConsumerStatefulWidget {
  const _ServiceRecordForm({required this.vehicle, required this.initial});

  final Vehicle vehicle;
  final ServiceRecord? initial;

  bool get isEditing => initial != null;

  @override
  ConsumerState<_ServiceRecordForm> createState() => _ServiceRecordFormState();
}

class _ServiceRecordFormState extends ConsumerState<_ServiceRecordForm> {
  final _formKey = GlobalKey<FormState>();

  late ServiceType _type = widget.initial == null
      ? ServiceType.oilChange
      : ServiceType.fromName(widget.initial!.type);

  late final TextEditingController _customLabel = TextEditingController(
    text: widget.initial?.customTypeLabel ?? '',
  );

  late DateTime _performedAt = widget.initial?.performedAt ?? DateTime.now();

  late final TextEditingController _odometer = TextEditingController(
    text:
        widget.initial?.odometer?.toString() ??
        widget.vehicle.odometer.toString(),
  );

  late final TextEditingController _notes = TextEditingController(
    text: widget.initial?.notes ?? '',
  );

  late final TextEditingController _cost = TextEditingController(
    text: widget.initial?.cost?.toString() ?? '',
  );

  late final TextEditingController _currency = TextEditingController(
    text:
        widget.initial?.currency ??
        defaultCurrencyForLocale(
          WidgetsBinding.instance.platformDispatcher.locale,
        ),
  );

  bool _saving = false;
  bool _formValid = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_customLabel, _odometer, _cost]) {
      controller.addListener(_revalidate);
    }
    _formValid = _isFormValid();
  }

  @override
  void dispose() {
    _customLabel.dispose();
    _odometer.dispose();
    _notes.dispose();
    _cost.dispose();
    _currency.dispose();
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
      _validateOdometer(_odometer.text) == null &&
      PremiumCostField.validateCost(_cost.text) == null;

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(premiumStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit service' : 'Add service'),
      ),
      body: Form(
        key: _formKey,
        // Per field, not here: a Form-level onUserInteraction validates
        // every field as soon as any one is touched.
        onChanged: _revalidate,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
            const SizedBox(height: 12),
            _DatePickerField(
              date: _performedAt,
              onChanged: (date) => setState(() => _performedAt = date),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _odometer,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Odometer at service',
                suffixText: widget.vehicle.odometerUnit,
                border: const OutlineInputBorder(),
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: _validateOdometer,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            PremiumCostField(
              isPremium: isPremium,
              costController: _cost,
              currencyController: _currency,
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
                  : Text(widget.isEditing ? 'Save changes' : 'Add record'),
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

  String? _validateOdometer(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null; // optional

    final odometer = int.tryParse(value);
    if (odometer == null || odometer < 0) {
      return 'Enter a reading of 0 or more';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final odometerText = _odometer.text.trim();
    final odometer = odometerText.isEmpty ? null : int.parse(odometerText);
    final notes = _notes.text.trim();
    final customLabel = _customLabel.text.trim();
    final isPremium = ref.read(premiumStatusProvider);
    final costText = _cost.text.trim();
    final cost = isPremium && costText.isNotEmpty
        ? double.parse(costText)
        : null;
    final currency = isPremium && cost != null ? _currency.text.trim() : null;

    if (widget.isEditing) {
      await ref
          .read(serviceRecordRepositoryProvider)
          .updateRecord(
            widget.initial!.id,
            performedAt: _performedAt,
            type: _type,
            odometer: Value(odometer),
            customTypeLabel: Value(
              _type == ServiceType.custom ? customLabel : null,
            ),
            notes: Value(notes.isEmpty ? null : notes),
            cost: Value(cost),
            currency: Value(currency),
          );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      _report(messenger, 'Service record updated');
      return;
    }

    final recordId = await ref
        .read(serviceRecordRepositoryProvider)
        .createRecord(
          vehicleId: widget.vehicle.id,
          performedAt: _performedAt,
          type: _type,
          odometer: odometer,
          customTypeLabel: _type == ServiceType.custom ? customLabel : null,
          notes: notes.isEmpty ? null : notes,
          cost: cost,
          currency: currency,
        );

    final reset = await _completeMatchingReminder(odometer: odometer);

    // Captured before popping: this State is disposed once the screen closes.
    final repository = ref.read(serviceRecordRepositoryProvider);
    final reviewPrompt = ref.read(reviewPromptServiceProvider);
    var isFirstRecord = false;
    try {
      isFirstRecord = await repository.countRecords() == 1;
    } catch (error) {
      // The record is already saved; never let the prompt check block the pop.
      debugPrint('First-record check failed: $error');
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.pop(recordId);
    // Saving quietly resets the matching reminder; say so, or the core loop
    // of the app happens where nobody can see it.
    _report(messenger, serviceSavedMessage(reset));

    final trigger = isFirstRecord
        ? ReviewTrigger.firstServiceRecord
        : reset?.wasDue ?? false
        ? ReviewTrigger.dueReminderCompleted
        : null;
    if (trigger != null) {
      // Not awaited: the service waits for the pop animation to finish, so
      // nothing here blocks the UI.
      unawaited(reviewPrompt.maybeRequestReview(trigger));
    }
  }

  /// Finds the vehicle's active rule matching this record's type and, if one
  /// exists, marks it done and re-schedules its notification.
  ///
  /// This is the linkage the product is built around: a user who logs an oil
  /// change should never have to separately tell the app "the oil change
  /// reminder is handled" — saving the record does that silently.
  ///
  /// Returns what was reset, or null when no rule matched. [ReminderReset]
  /// says whether the rule was due (due now or overdue) at the moment of
  /// saving — the "reminder done" moment for the review prompt — and when it
  /// comes due next, for the confirmation shown after saving.
  Future<ReminderReset?> _completeMatchingReminder({
    required int? odometer,
  }) async {
    final ruleRepository = ref.read(reminderRuleRepositoryProvider);
    final rules = await ruleRepository
        .watchRulesForVehicle(widget.vehicle.id)
        .first;

    final matchingRule = rules
        .where((rule) => rule.isActive && rule.deletedAt == null)
        .where((rule) => ServiceType.fromName(rule.type) == _type)
        .firstOrNull;

    if (matchingRule == null) return null;

    // Measured before marking done, which resets the interval.
    final urgency = ReminderEngine.compute(
      rule: matchingRule.toEngineInput(),
      vehicle: widget.vehicle.toEngineContext(),
      now: DateTime.now(),
    ).urgency;
    final wasDue =
        urgency == ReminderUrgency.overdue || urgency == ReminderUrgency.dueNow;

    await ruleRepository.markRuleDone(matchingRule.id, _performedAt, odometer);

    await ref
        .read(reminderNotificationSchedulerProvider)
        .rescheduleForRule(matchingRule.id);

    // Re-read both: marking done re-based the rule, and a record with a
    // higher reading has just advanced the vehicle's odometer.
    final rule = await ruleRepository.getRule(matchingRule.id) ?? matchingRule;
    final vehicle =
        await ref
            .read(vehicleRepositoryProvider)
            .getVehicle(widget.vehicle.id) ??
        widget.vehicle;
    final next = ReminderEngine.compute(
      rule: rule.toEngineInput(),
      vehicle: vehicle.toEngineContext(),
      now: DateTime.now(),
    );

    final type = ServiceType.fromName(rule.type);
    return ReminderReset(
      wasDue: wasDue,
      typeLabel: type == ServiceType.custom
          ? (rule.customTypeLabel ?? type.label)
          : type.label,
      nextDue: ReminderStatusLabel.format(
        next,
        distanceUnit: vehicle.odometerUnit,
      ),
    );
  }

  static void _report(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// What saving a service record did to the matching reminder.
@visibleForTesting
class ReminderReset {
  const ReminderReset({
    required this.wasDue,
    required this.typeLabel,
    required this.nextDue,
  });

  /// Whether the rule was due or overdue just before this save.
  final bool wasDue;

  /// The rule's name, e.g. "Oil change".
  final String typeLabel;

  /// Its status after the reset, as [ReminderStatusLabel] words it.
  final String nextDue;
}

/// The confirmation shown once a new service record is saved, e.g.
/// "Service saved. Oil change reminder reset — next due May 2027."
@visibleForTesting
String serviceSavedMessage(ReminderReset? reset) {
  if (reset == null) return 'Service saved';

  final head = 'Service saved. ${reset.typeLabel} reminder reset';
  // "Due May 2027" / "Due in 8000 km" read naturally after "next"; anything
  // else (no schedule, an odd overdue) is left out rather than garbled.
  final nextDue = reset.nextDue;
  if (!nextDue.startsWith('Due ') || nextDue == 'Due now') return '$head.';
  return '$head — next ${nextDue.replaceFirst('Due', 'due')}.';
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pickDate(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date performed',
          border: OutlineInputBorder(),
        ),
        child: Text(DateFormat('d MMM yyyy').format(date)),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: date.isAfter(now) ? now : date,
      firstDate: DateTime(1990),
      // A service can't have happened in the future.
      lastDate: now,
    );
    if (picked != null) onChanged(picked);
  }
}
