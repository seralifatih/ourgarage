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
import '../reminders/reminder_notification_scheduler.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _revalidate());
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

  void _revalidate() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (isValid != _formValid) {
      setState(() => _formValid = isValid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(premiumStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit service' : 'Add service'),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
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
                // Re-validate on the next frame: the custom-label field's
                // presence just changed, and its validator needs a fresh pass.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _revalidate(),
                );
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

      if (mounted) context.pop();
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

    await _completeMatchingReminder(odometer: odometer);

    if (!mounted) return;
    context.pop(recordId);
  }

  /// Finds the vehicle's active rule matching this record's type and, if one
  /// exists, marks it done and re-schedules its notification.
  ///
  /// This is the linkage the product is built around: a user who logs an oil
  /// change should never have to separately tell the app "the oil change
  /// reminder is handled" — saving the record does that silently.
  Future<void> _completeMatchingReminder({required int? odometer}) async {
    final ruleRepository = ref.read(reminderRuleRepositoryProvider);
    final rules = await ruleRepository
        .watchRulesForVehicle(widget.vehicle.id)
        .first;

    final matchingRule = rules
        .where((rule) => rule.isActive && rule.deletedAt == null)
        .where((rule) => ServiceType.fromName(rule.type) == _type)
        .firstOrNull;

    if (matchingRule == null) return;

    await ruleRepository.markRuleDone(matchingRule.id, _performedAt, odometer);

    await ref
        .read(reminderNotificationSchedulerProvider)
        .rescheduleForRule(matchingRule.id);
  }
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
