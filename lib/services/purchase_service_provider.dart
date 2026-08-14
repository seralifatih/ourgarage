import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'purchase_service.dart';

part 'purchase_service_provider.g.dart';

/// The app-wide [PurchaseService].
///
/// Kept alive for the process lifetime: it holds the RevenueCat entitlement
/// listener that [premiumStatusProvider] is derived from, so tearing it down
/// when the last listener drops would stop premium state updating.
///
/// Tests override this with a service wrapping a fake [PurchasesApi].
@Riverpod(keepAlive: true)
PurchaseService purchaseService(Ref ref) {
  final service = PurchaseService();
  ref.onDispose(service.dispose);
  return service;
}
