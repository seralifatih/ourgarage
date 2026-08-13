import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_routes.dart';

/// Cost + currency inputs, disabled for free users behind a "Premium" badge.
///
/// Tapping the disabled field opens the paywall — free users can see the
/// feature exists (nothing hidden) but can't fill it in until they upgrade.
class PremiumCostField extends StatelessWidget {
  const PremiumCostField({
    required this.isPremium,
    required this.costController,
    required this.currencyController,
    super.key,
  });

  final bool isPremium;
  final TextEditingController costController;
  final TextEditingController currencyController;

  @override
  Widget build(BuildContext context) {
    final costField = TextFormField(
      controller: costController,
      enabled: isPremium,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Cost',
        border: OutlineInputBorder(),
      ),
      validator: _validateCost,
    );

    final currencyField = TextFormField(
      controller: currencyController,
      enabled: isPremium,
      textCapitalization: TextCapitalization.characters,
      maxLength: 3,
      decoration: const InputDecoration(
        labelText: 'Currency',
        border: OutlineInputBorder(),
        counterText: '',
      ),
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: costField),
        const SizedBox(width: 12),
        Expanded(child: currencyField),
      ],
    );

    if (isPremium) return row;

    return Stack(
      children: [
        row,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push(AppRoutes.paywall),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _PremiumBadge(onTap: () => context.push(AppRoutes.paywall)),
        ),
      ],
    );
  }

  static String? _validateCost(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null; // optional

    final cost = double.tryParse(value);
    if (cost == null || cost < 0) {
      return 'Enter an amount of 0 or more';
    }
    return null;
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 12,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                'Premium',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
