import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/purchase_service_provider.dart';

part 'paywall_providers.g.dart';

/// The offering the paywall renders, or null when there is nothing to sell.
///
/// Null covers every "can't buy right now" case — no API key, no network, or
/// no offering configured in the RevenueCat dashboard yet. The paywall shows
/// its value proposition regardless and only hides the purchase controls, so
/// a store hiccup never leaves the user staring at an empty screen.
///
/// Prices come from here rather than from constants: [StoreProduct.priceString]
/// is already localised and currency-converted by the store, so a user in
/// Türkiye sees ₺ and a user in the US sees $ without the app formatting
/// anything itself.
@riverpod
Future<Offering?> currentOffering(Ref ref) {
  return ref.watch(purchaseServiceProvider).getOfferings();
}
