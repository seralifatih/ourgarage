import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../services/auth_service.dart';
import '../../../services/auth_service_provider.dart';

/// Explains why sharing needs an account, then signs the user in with Apple.
///
/// Everything up to this point works with no account at all, so being asked to
/// sign in is a genuine surprise unless the reason is given first. The three
/// things a reasonable person wants to know before tapping — why an account is
/// needed, what gets stored, and what happens to the data already on their
/// phone — are answered here rather than in a privacy policy nobody opens.
///
/// Sign in with Apple is the only option offered. A second third-party
/// provider would trigger App Store guideline 4.8, which then requires
/// offering an equivalent privacy-preserving alternative.
///
/// Generic in what a successful sign-in returns, because the two callers want
/// different things: "Share with household" wants a [SignInResult] (a
/// household is created as part of signing in there), while "Join a
/// household" only wants the user id — joining is what gives it a household,
/// so creating one during sign-in would be wrong. See
/// [AuthService.signInWithoutHousehold].
class HouseholdAccountSheet<T> extends ConsumerStatefulWidget {
  const HouseholdAccountSheet({
    required this.signIn,
    required this.headline,
    required this.explainer,
    required this.dataPoint,
    super.key,
  });

  final Future<T?> Function() signIn;
  final String headline;
  final String explainer;

  /// What happens to the user's data, phrased for the specific flow: a
  /// sharer's garage is about to be uploaded as a direct consequence of
  /// signing in, but a joiner's is not — that decision comes after, in
  /// [JoinHouseholdScreen]'s upload/keep-local dialog — so telling them it
  /// will be uploaded here would be wrong.
  final String dataPoint;

  /// Shows the sheet for the "Share with household" flow: sign in and create
  /// a household in the same step. Returns the completed sign-in, or null if
  /// the user backed out or sign-in failed.
  static Future<SignInResult?> show(BuildContext context) {
    return showModalBottomSheet<SignInResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (_, ref, _) => HouseholdAccountSheet<SignInResult>(
          signIn: () => ref.read(authServiceProvider).signInWithApple(),
          headline: 'Share your garage',
          explainer:
              'Sharing needs an account, so the people you invite can see '
              'the same vehicles and service history on their own phones.',
          dataPoint:
              'Your vehicles, service history and reminders are uploaded '
              'so your household can see them.',
        ),
      ),
    );
  }

  /// Shows the sheet for the "Join a household" flow: sign in **without**
  /// creating a household — see [AuthService.signInWithoutHousehold]. Returns
  /// the signed-in user id, or null if the user backed out or sign-in failed.
  static Future<String?> showForJoin(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (_, ref, _) => HouseholdAccountSheet<String>(
          signIn: () => ref.read(authServiceProvider).signInWithoutHousehold(),
          headline: 'Join a household',
          explainer:
              'Joining needs an account, so the household can recognise you '
              'and show you what its members have shared.',
          dataPoint:
              'If you already track vehicles on this phone, you’ll choose '
              'next whether to share them with the household or keep them '
              'to yourself.',
        ),
      ),
    );
  }

  @override
  ConsumerState<HouseholdAccountSheet<T>> createState() =>
      _HouseholdAccountSheetState<T>();
}

class _HouseholdAccountSheetState<T>
    extends ConsumerState<HouseholdAccountSheet<T>> {
  bool _signingIn = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });

    try {
      final result = await widget.signIn();

      if (!mounted) return;

      // Null means the user dismissed Apple's sheet. Leave ours open so they
      // can try again — closing both would make a stray tap feel like the
      // feature refused them.
      if (result == null) {
        setState(() => _signingIn = false);
        return;
      }

      Navigator.of(context).pop(result);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _error = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _error = 'Could not sign in. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
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
            Icon(
              Icons.people_outline,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              widget.headline,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.explainer,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _Point(icon: Icons.cloud_upload_outlined, text: widget.dataPoint),
            const _Point(
              icon: Icons.lock_outline,
              text:
                  'Only people in the household can see it. Nobody else, '
                  'including other OurGarage users.',
            ),
            const _Point(
              icon: Icons.phone_iphone,
              text:
                  'Everything stays on this phone as well, and keeps working '
                  'offline.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_signingIn)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              SignInWithAppleButton(
                onPressed: _signIn,
                text: 'Continue with Apple',
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _signingIn
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
