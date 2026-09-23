import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_routes.dart';
import '../../core/constants.dart';
import '../../services/purchase_service_provider.dart';
import 'paywall_providers.dart';

/// Which of the two products the user is about to buy.
enum _Plan { lifetime, annual }

/// The premium upsell.
///
/// Deliberately free of countdown timers, fake scarcity and delayed dismiss
/// controls: the close button is present and enabled from the first frame.
/// Beyond being App Store review triggers (3.1.2 and design rejections), those
/// patterns are what earn one-star reviews from people who felt cornered.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  /// Lifetime is pre-selected: it is the better deal for the kind of user who
  /// keeps a car for years, which is most of them.
  _Plan _selected = _Plan.lifetime;

  bool _busy = false;

  /// Dismisses the paywall.
  ///
  /// Not simply `context.pop()`: the vehicle-limit entry point arrives via
  /// `context.go`, which replaces the stack rather than pushing onto it, so
  /// there may be nothing to pop. Falling back to the garage list keeps the
  /// close button working from every entry point rather than throwing.
  static void _close(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.vehicleList);
    }
  }

  Future<void> _purchase(Package package) async {
    final messenger = ScaffoldMessenger.of(context);
    final purchases = ref.read(purchaseServiceProvider);

    setState(() => _busy = true);
    try {
      final isPremium = await purchases.purchasePackage(package);
      if (!mounted) return;

      if (isPremium) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Welcome to Premium')));
        // Nothing left to sell; drop straight back where they came from.
        _close(context);
        return;
      }
      // Not entitled and no error: the user backed out of the store sheet,
      // which needs no message of its own.
    } on PlatformException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(error.message ?? 'Purchase failed')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    final purchases = ref.read(purchaseServiceProvider);

    setState(() => _busy = true);
    try {
      final isPremium = await purchases.restorePurchases();
      if (!mounted) return;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isPremium ? 'Purchases restored' : 'No previous purchases found',
            ),
          ),
        );
      if (isPremium) _close(context);
    } on PlatformException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not restore purchases'),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offeringAsync = ref.watch(currentOfferingProvider);
    final offering = offeringAsync.asData?.value;

    final lifetime = offering?.lifetime;
    final annual = offering?.annual;
    final selectedPackage = _selected == _Plan.lifetime ? lifetime : annual;

    return Scaffold(
      appBar: AppBar(
        // Visible from the first frame, never delayed. See the class doc.
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _close(context),
          tooltip: 'Close',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              'Unlock your whole garage',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            const _ValueBullet('Track unlimited vehicles'),
            const _ValueBullet(
              'Share with your household — everyone sees the same service '
              'history',
            ),
            const _ValueBullet('Log service costs and export your records'),
            const SizedBox(height: 32),

            if (offeringAsync.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (lifetime == null && annual == null)
              // No products to show. The value proposition above still stands;
              // only the controls that cannot work are withheld.
              // A retry rather than a dead end: the App Store sandbox can fail
              // a first product fetch and succeed seconds later.
              Column(
                children: [
                  Text(
                    'Purchases are unavailable right now.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(currentOfferingProvider),
                    child: const Text('Try again'),
                  ),
                ],
              )
            else ...[
              // IntrinsicHeight so the two cards match height regardless of
              // which has the badge or caption. `stretch` alone would ask for
              // an unbounded height inside this ListView and fail layout.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (lifetime != null)
                      Expanded(
                        child: _PlanCard(
                          title: 'Lifetime',
                          price: lifetime.storeProduct.priceString,
                          caption: 'Pay once, keep forever',
                          badge: 'Best value',
                          selected: _selected == _Plan.lifetime,
                          onTap: () =>
                              setState(() => _selected = _Plan.lifetime),
                        ),
                      ),
                    if (lifetime != null && annual != null)
                      const SizedBox(width: 12),
                    if (annual != null)
                      Expanded(
                        child: _PlanCard(
                          title: 'Annual',
                          price: '${annual.storeProduct.priceString}/year',
                          selected: _selected == _Plan.annual,
                          onTap: () => setState(() => _selected = _Plan.annual),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy || selectedPackage == null
                    ? null
                    : () => _purchase(selectedPackage),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Unlock'),
              ),
            ],

            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _restore,
              child: const Text('Restore purchases'),
            ),
            const SizedBox(height: 8),
            const _LegalLinks(),
          ],
        ),
      ),
    );
  }
}

class _ValueBullet extends StatelessWidget {
  const _ValueBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

/// One of the two purchase options.
///
/// [price] is always a store-provided localised string — the UI never formats
/// or hardcodes a currency amount.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.selected,
    required this.onTap,
    this.caption,
    this.badge,
  });

  final String title;
  final String price;
  final String? caption;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.3)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(caption!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Terms and Privacy Policy links, which App Store review requires any app
/// selling an IAP to surface at the point of purchase.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );

    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () => _open(context, AppConstants.termsUrl),
          child: const Text('Terms'),
        ),
        const Text('·'),
        TextButton(
          onPressed: () => _open(context, AppConstants.privacyUrl),
          child: const Text('Privacy Policy'),
        ),
      ],
    );
  }
}
