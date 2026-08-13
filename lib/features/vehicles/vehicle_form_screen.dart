import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_routes.dart';
import '../../core/constants.dart';
import '../../data/local/database.dart';
import '../../data/repositories/premium_status_provider.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/stream_providers.dart';
import 'odometer_unit.dart';
import 'widgets/default_reminders_sheet.dart';

/// Add or edit a vehicle.
///
/// In create mode ([vehicleId] is null) this also runs the free-tier gate and,
/// on success, offers to set up default reminders. Edit mode only touches the
/// vehicle's own fields — the odometer is intentionally not editable here; that
/// flow belongs to [OdometerUpdateSheet] elsewhere, so an edit can't silently
/// rewrite travelled distance.
class VehicleFormScreen extends ConsumerWidget {
  const VehicleFormScreen({this.vehicleId, super.key});

  final String? vehicleId;

  bool get isEditing => vehicleId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isEditing) {
      return _VehicleForm(vehicleId: null, initial: null);
    }

    final vehicleAsync = ref.watch(vehicleStreamProvider(vehicleId!));

    return vehicleAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Edit vehicle')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit vehicle')),
        body: Center(child: Text('$error')),
      ),
      data: (vehicle) {
        if (vehicle == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit vehicle')),
            body: const Center(child: Text('Vehicle not found')),
          );
        }
        return _VehicleForm(vehicleId: vehicleId, initial: vehicle);
      },
    );
  }
}

class _VehicleForm extends ConsumerStatefulWidget {
  const _VehicleForm({required this.vehicleId, required this.initial});

  final String? vehicleId;
  final Vehicle? initial;

  bool get isEditing => vehicleId != null;

  @override
  ConsumerState<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends ConsumerState<_VehicleForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nickname = TextEditingController(
    text: widget.initial?.nickname ?? '',
  );
  late final TextEditingController _make = TextEditingController(
    text: widget.initial?.make ?? '',
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.initial?.model ?? '',
  );
  late final TextEditingController _year = TextEditingController(
    text: widget.initial?.year?.toString() ?? '',
  );
  late final TextEditingController _plate = TextEditingController(
    text: widget.initial?.plate ?? '',
  );
  late final TextEditingController _odometer = TextEditingController(
    text: widget.initial?.odometer.toString() ?? '',
  );

  late String _unit =
      widget.initial?.odometerUnit ??
      defaultOdometerUnitForLocale(
        WidgetsBinding.instance.platformDispatcher.locale,
      );

  bool _saving = false;
  bool _formValid = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_nickname, _odometer, _year]) {
      controller.addListener(_revalidate);
    }
    // Fields without their own validators still need to trigger a revalidate
    // for the odometer non-emptiness check (year is caught above already).
    WidgetsBinding.instance.addPostFrameCallback((_) => _revalidate());
  }

  @override
  void dispose() {
    _nickname.dispose();
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _plate.dispose();
    _odometer.dispose();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit vehicle' : 'Add vehicle'),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: _revalidate,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            TextFormField(
              controller: _nickname,
              autofocus: !widget.isEditing,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                hintText: 'e.g. Blue Civic',
                border: OutlineInputBorder(),
              ),
              validator: _validateNickname,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _make,
                    decoration: const InputDecoration(
                      labelText: 'Make',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _year,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Year',
                border: OutlineInputBorder(),
              ),
              validator: _validateYear,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Plate',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _odometer,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Current odometer',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateOdometer,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'km', child: Text('km')),
                      DropdownMenuItem(value: 'mi', child: Text('mi')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _unit = value);
                    },
                  ),
                ),
              ],
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
                  : Text(widget.isEditing ? 'Save changes' : 'Add vehicle'),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateNickname(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Nickname is required';
    if (value.length > 40) return 'Keep it under 40 characters';
    return null;
  }

  String? _validateYear(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null; // optional

    final year = int.tryParse(value);
    final maxYear = DateTime.now().year + 1;
    if (year == null || year < 1900 || year > maxYear) {
      return 'Enter a year between 1900 and $maxYear';
    }
    return null;
  }

  String? _validateOdometer(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Odometer is required';

    final odometer = int.tryParse(value);
    if (odometer == null || odometer < 0) {
      return 'Enter a reading of 0 or more';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final nickname = _nickname.text.trim();
    final make = _make.text.trim();
    final model = _model.text.trim();
    final plate = _plate.text.trim();
    final year = int.tryParse(_year.text.trim());
    final odometer = int.parse(_odometer.text.trim());

    if (widget.isEditing) {
      await ref
          .read(vehicleRepositoryProvider)
          .updateVehicle(
            widget.vehicleId!,
            nickname: nickname,
            make: Value(make.isEmpty ? null : make),
            model: Value(model.isEmpty ? null : model),
            year: Value(year),
            plate: Value(plate.isEmpty ? null : plate),
            odometerUnit: _unit,
          );

      if (mounted) context.pop();
      return;
    }

    // Free-tier gate: the single source of truth for premium status is
    // premiumStatusProvider, checked here and nowhere else in this flow.
    final isPremium = ref.read(premiumStatusProvider);
    if (!isPremium) {
      final activeCount = await ref
          .read(vehicleRepositoryProvider)
          .countActiveVehicles();
      if (activeCount >= AppConstants.freeVehicleLimit) {
        if (mounted) context.go(AppRoutes.paywall);
        return;
      }
    }

    final newId = await ref
        .read(vehicleRepositoryProvider)
        .createVehicle(
          nickname: nickname,
          odometerUnit: _unit,
          make: make.isEmpty ? null : make,
          model: model.isEmpty ? null : model,
          year: year,
          plate: plate.isEmpty ? null : plate,
          odometer: odometer,
        );

    if (!mounted) return;

    // Offer default reminders while still on this screen — a vehicle with no
    // rules never produces a notification, so this is worth a beat before
    // moving on. Whether the user adds them or skips, we then continue to the
    // new vehicle's detail page.
    await DefaultRemindersSheet.show(
      context,
      vehicleId: newId,
      odometerUnit: _unit,
    );

    if (!mounted) return;
    context.pushReplacement(AppRoutes.vehicleDetail(newId));
  }
}
