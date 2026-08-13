import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_routes.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../../data/repositories/stream_providers.dart';
import 'odometer_nudge_provider.dart';
import 'widgets/due_now_alert_sheet.dart';

/// Where the odometer nudge lands: every vehicle, one field each, one Save.
///
/// Deliberately not a per-vehicle flow. The nudge is the only thing keeping
/// distance-based reminders alive, and making someone navigate into each
/// vehicle in turn is exactly the friction that would stop them bothering.
class UpdateOdometersScreen extends ConsumerWidget {
  const UpdateOdometersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(vehiclesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Update odometers')),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return const Center(child: Text('No vehicles yet'));
          }
          return _UpdateOdometersForm(vehicles: vehicles);
        },
      ),
    );
  }
}

class _UpdateOdometersForm extends ConsumerStatefulWidget {
  const _UpdateOdometersForm({required this.vehicles});

  final List<Vehicle> vehicles;

  @override
  ConsumerState<_UpdateOdometersForm> createState() =>
      _UpdateOdometersFormState();
}

class _UpdateOdometersFormState extends ConsumerState<_UpdateOdometersForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final vehicle in widget.vehicles)
      vehicle.id: TextEditingController(text: vehicle.odometer.toString()),
  };

  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Enter what each one reads now. Anything you leave unchanged is '
            'left alone.',
            style: AppTextStyles.listSubtitle.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          for (final vehicle in widget.vehicles) ...[
            TextFormField(
              controller: _controllers[vehicle.id],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: vehicle.nickname,
                suffixText: vehicle.odometerUnit,
                border: const OutlineInputBorder(),
              ),
              validator: (raw) => _validate(raw, vehicle),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  String? _validate(String? raw, Vehicle vehicle) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Enter a reading';

    final odometer = int.tryParse(value);
    if (odometer == null) return 'Enter a number';

    // Odometers don't run backwards. Catching a typo here matters more than
    // usual: these readings drive when distance reminders come due.
    if (odometer < vehicle.odometer) {
      return 'Cannot be lower than ${vehicle.odometer}';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    // Only changed values are written, so an untouched vehicle keeps its
    // existing odometerUpdatedAt rather than looking freshly confirmed.
    final readings = <String, int>{};
    for (final vehicle in widget.vehicles) {
      final entered = int.tryParse(_controllers[vehicle.id]!.text.trim());
      if (entered == null || entered == vehicle.odometer) continue;
      readings[vehicle.id] = entered;
    }

    final due = await ref
        .read(odometerNudgeServiceProvider)
        .saveReadings(readings);

    if (!mounted) return;

    if (due.isEmpty) {
      context.go(AppRoutes.vehicleList);
      return;
    }

    final choice = await DueNowAlertSheet.show(context, due);
    if (!mounted) return;

    // "Log it now" jumps straight to the service form for that vehicle;
    // anything else just returns to the garage.
    if (choice != null && choice.$1 == DueNowAction.logIt) {
      context.go(AppRoutes.addService(choice.$2.vehicleId));
      return;
    }

    context.go(AppRoutes.vehicleList);
  }
}
