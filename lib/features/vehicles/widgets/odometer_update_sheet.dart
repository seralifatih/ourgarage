import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../data/repositories/providers.dart';

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

    // Odometers don't run backwards. Blocking this catches typos before they
    // corrupt the reminder maths, which keys off distance travelled.
    if (value < widget.vehicle.odometer) {
      return 'Cannot be lower than the current reading '
          '(${widget.vehicle.odometer})';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final value = int.parse(_controller.text.trim());

    await ref
        .read(vehicleRepositoryProvider)
        .updateOdometer(widget.vehicle.id, value);

    if (mounted) Navigator.of(context).pop();
  }
}
