import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../household_migration_provider.dart';
import '../household_migration_service.dart';

/// Blocking progress while the local garage uploads into the new household.
///
/// Deliberately not dismissible while the upload is in flight. Everything the
/// user does from here on assumes their data is in the cloud, and letting them
/// wander off mid-upload would leave the app reasoning about a garage that is
/// only partly there.
///
/// On failure it stops being blocking: the upload has already been rolled back
/// by then, so there is a real choice to offer — try again, or carry on
/// locally, which still works exactly as it did before.
class HouseholdMigrationDialog extends ConsumerStatefulWidget {
  const HouseholdMigrationDialog({
    required this.householdId,
    required this.userId,
    super.key,
  });

  final String householdId;
  final String userId;

  /// Runs the migration behind a modal barrier. Resolves to true once the
  /// garage is uploaded, false if it failed and the user gave up.
  static Future<bool> run(
    BuildContext context, {
    required String householdId,
    required String userId,
  }) async {
    final uploaded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          HouseholdMigrationDialog(householdId: householdId, userId: userId),
    );
    return uploaded ?? false;
  }

  @override
  ConsumerState<HouseholdMigrationDialog> createState() =>
      _HouseholdMigrationDialogState();
}

class _HouseholdMigrationDialogState
    extends ConsumerState<HouseholdMigrationDialog> {
  MigrationProgress _progress = const MigrationProgress(
    phase: MigrationPhase.preparing,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    // Started from initState rather than a button: the user already agreed to
    // share when they signed in, so there is nothing left to confirm.
    WidgetsBinding.instance.addPostFrameCallback((_) => _migrate());
  }

  Future<void> _migrate() async {
    setState(() => _error = null);

    try {
      await ref
          .read(householdMigrationProvider)
          .migrate(
            householdId: widget.householdId,
            userId: widget.userId,
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress);
            },
          );

      if (mounted) Navigator.of(context).pop(true);
    } on MigrationFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } on Object {
      if (mounted) {
        setState(() {
          _error =
              'Your garage could not be uploaded. Nothing on this phone was '
              'changed.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;

    // PopScope with canPop: false is what actually blocks the Android back
    // gesture; barrierDismissible only covers taps outside the dialog.
    return PopScope(
      canPop: error != null,
      child: AlertDialog(
        title: Text(error == null ? 'Setting up sharing' : 'Upload failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (error == null) ...[
              LinearProgressIndicator(value: _progress.fraction),
              const SizedBox(height: 16),
              Text(_progress.label, style: theme.textTheme.bodyMedium),
              if (_progress.total > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${_progress.uploaded} of ${_progress.total}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else
              Text(error, style: theme.textTheme.bodyMedium),
          ],
        ),
        actions: error == null
            ? null
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: _migrate,
                  child: const Text('Try again'),
                ),
              ],
      ),
    );
  }
}
