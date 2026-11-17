import '../../data/sync/sync_service.dart';
import 'household_service.dart';

/// Asks the server to extend the user's own purchase to [householdId] (see
/// `claim-premium`), then re-reads the household's premium so every screen on
/// this device reflects it. Best effort throughout; never throws.
Future<void> claimHouseholdPremium({
  required HouseholdService households,
  required SyncService sync,
  required String householdId,
}) async {
  if (await households.claimPremium()) {
    await sync.refreshHouseholdPremium(householdId);
  }
}
