import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_routes.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../services/auth_service_provider.dart';
import '../household_service.dart';
import '../invite_code.dart';
import '../join_household_service.dart';
import 'household_account_sheet.dart';

/// Live-normalises what the user types against [InviteCode]: uppercased, the
/// same lookalike repairs [InviteCode.normalise] applies on submit, and capped
/// at [InviteCode.length]. Doing this as-you-type rather than only on submit
/// means the field always shows the code that will actually be sent, instead
/// of silently rewriting it out from under a half-typed entry.
class _InviteCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = InviteCode.normalise(newValue.text);
    final capped = cleaned.length > InviteCode.length
        ? cleaned.substring(0, InviteCode.length)
        : cleaned;

    return TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
  }
}

/// Joining a household someone else created.
///
/// The second (and only other) trigger for auth, alongside "Share with
/// household" on a vehicle. That flow signs in and then creates a household,
/// because signing in there is itself the decision to start sharing; this one
/// signs in and then joins one, so it must not auto-create a household on the
/// way in — see [AuthService.signInWithoutHousehold] for why that matters.
class JoinHouseholdScreen extends ConsumerStatefulWidget {
  const JoinHouseholdScreen({super.key});

  @override
  ConsumerState<JoinHouseholdScreen> createState() =>
      _JoinHouseholdScreenState();
}

class _JoinHouseholdScreenState extends ConsumerState<JoinHouseholdScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && InviteCode.isWellFormed(_controller.text);

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final code = _controller.text;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final userId = await _signIn();
      if (userId == null) {
        // The Apple sheet was dismissed. Not an error — let them try again.
        setState(() => _busy = false);
        return;
      }
      if (!mounted) return;

      final choice = await _resolveLocalGarageChoice();
      if (choice == null) {
        // The user closed the upload/keep-local dialog without choosing.
        // Nothing has been joined yet, so there is nothing to undo.
        setState(() => _busy = false);
        return;
      }
      if (!mounted) return;

      final outcome = await ref
          .read(joinHouseholdServiceProvider)
          .join(code: code, userId: userId, choice: choice);

      if (!mounted) return;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_successMessage(outcome))),
        );
      router.go(AppRoutes.vehicleList);
    } on JoinException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  /// Signs in if there is no session yet, without creating a household —
  /// joining is about to give them one. An already-signed-in user (who
  /// presumably already has a household from sharing their own garage) is not
  /// re-authenticated; [JoinHouseholdService.join] and the invite RPC decide
  /// whether joining a second household from that state is meaningful.
  Future<String?> _signIn() async {
    final auth = ref.read(authServiceProvider);
    if (auth.isSignedIn) return auth.currentUserId;

    return HouseholdAccountSheet.showForJoin(context);
  }

  /// Asks what to do with any local-only vehicles, only when there is
  /// something to ask about. Returns null if the user backed out.
  Future<LocalGarageChoice?> _resolveLocalGarageChoice() async {
    final join = ref.read(joinHouseholdServiceProvider);
    final localCount = await join.unsharedVehicleCount();

    if (localCount == 0) return LocalGarageChoice.keepLocal;
    if (!mounted) return null;

    return showDialog<LocalGarageChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _LocalGarageChoiceDialog(count: localCount),
    );
  }

  String _successMessage(JoinOutcome outcome) {
    if (!outcome.uploaded) return 'You’ve joined the household';
    final n = outcome.localVehicleCount;
    return 'You’ve joined the household — $n ${n == 1 ? 'vehicle' : 'vehicles'} '
        'shared';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Join a household')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the 6-character code you were given.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_busy,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_InviteCodeInputFormatter()],
                style: theme.textTheme.headlineSmall?.copyWith(
                  letterSpacing: 4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  hintText: 'MK7NPQ',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                maxLength: InviteCode.length,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_canSubmit) _submit();
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Join'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks what happens to vehicles already on this device.
///
/// Neither choice destroys anything — see [JoinHouseholdService] — so this is
/// not a warning about data loss, only a decision about who else gets to see
/// what is already here.
class _LocalGarageChoiceDialog extends StatelessWidget {
  const _LocalGarageChoiceDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final vehicleWord = count == 1 ? 'vehicle' : 'vehicles';

    return AlertDialog(
      title: Text('You already have $count $vehicleWord'),
      content: Text(
        'Joining this household won’t merge your garage automatically. Do '
        'you want to share your existing $vehicleWord with the household, or '
        'keep them on this device only?\n\n'
        'Either way, nothing is deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(LocalGarageChoice.keepLocal),
          child: const Text('Keep local only'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(LocalGarageChoice.upload),
          child: const Text('Share with household'),
        ),
      ],
    );
  }
}
