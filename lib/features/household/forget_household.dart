import 'package:flutter/foundation.dart';

import '../../data/local/database.dart';

/// Unlinks this device from its household after the server no longer counts
/// the user as a member — they left, or deleted their account.
///
/// Local data stays: vehicles are detached (they become an ordinary local
/// garage again), and only sync and entitlement bookkeeping is dropped. Each
/// step is attempted even if an earlier one fails, and failures are logged
/// rather than thrown: by this point the server side is already done, and a
/// step that failed only leaves inert bookkeeping behind.
Future<void> forgetHouseholdLocally(AppDatabase db) async {
  for (final step in <(String, Future<void> Function())>[
    ('detach vehicles', () => db.vehicleDao.detachAllFromHousehold()),
    ('clear sync queue', () => db.syncQueueDao.clear()),
    ('reset pull cursor', () => db.syncQueueDao.resetLastPulledAt()),
    ('clear entitlement cache', () => db.householdEntitlementDao.clear()),
  ]) {
    try {
      await step.$2();
    } catch (error) {
      debugPrint('Household cleanup "${step.$1}" failed: $error');
    }
  }
}
