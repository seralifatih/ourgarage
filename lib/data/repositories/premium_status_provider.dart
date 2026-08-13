import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'premium_status_provider.g.dart';

/// Whether the user has an active premium entitlement.
///
/// This is the single source of truth for premium status — UI code must read
/// this provider rather than checking `AppConstants.freeVehicleLimit` or
/// entitlement state directly, so the gate logic only ever lives in one place.
///
/// Hardcoded to `false` for now. Phase 4 replaces this body with a real
/// RevenueCat/`PurchaseService` lookup; nothing that reads this provider should
/// need to change when that happens.
@riverpod
bool premiumStatus(Ref ref) {
  return false;
}
