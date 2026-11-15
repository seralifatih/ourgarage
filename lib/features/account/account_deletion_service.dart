import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';
import '../../data/repositories/database_holder.dart';
import '../../services/auth_service.dart';
import '../../services/auth_service_provider.dart';
import '../household/household_migration_provider.dart';
import '../household/household_service.dart';

/// What deleting the account will do to the user's household, so the
/// confirmation dialog can say it plainly. Mirrors `delete_account_data()` in
/// the account-deletion migration, which is what actually decides.
sealed class DeletionImpact {
  const DeletionImpact();
}

/// Signed in, but in no household (e.g. joined nothing yet).
class NoHousehold extends DeletionImpact {
  const NoHousehold();
}

/// The only member: the household and everything shared in it is deleted.
class SoleMember extends DeletionImpact {
  const SoleMember();
}

/// The owner, with others: ownership passes to the member who joined first.
class OwnerHandsOver extends DeletionImpact {
  const OwnerHandsOver(this.otherMembers);
  final int otherMembers;
}

/// A plain member: they leave; the household carries on.
class LeavesHousehold extends DeletionImpact {
  const LeavesHousehold(this.otherMembers);
  final int otherMembers;
}

/// Account deletion end to end: server first, then the device.
///
/// The server side (data, membership, auth user, Apple token revocation) is
/// the `delete-account` Edge Function, reached through [AuthService]. This
/// class adds what only the device can do once that succeeds: unlink local
/// vehicles from the household and drop sync and entitlement state. Local
/// data itself stays — the free tier is local, and the dialog promises it.
class AccountDeletionService {
  AccountDeletionService({
    required this.auth,
    required this.households,
    required this.db,
  });

  final AuthService auth;
  final HouseholdService households;
  final AppDatabase db;

  /// Reads the household roster to describe the outcome. Throws if the
  /// roster can't be fetched (offline) — the caller should not guess.
  ///
  /// Checks the session first. A dead one (revoked, or the account was
  /// already deleted by an attempt whose response never arrived) throws
  /// [SessionInvalidException] after signing out and unlinking the device,
  /// which is the right end state either way.
  Future<DeletionImpact> impact() async {
    await _withSessionCheck(auth.ensureValidSession);

    final userId = auth.currentUserId;
    final householdId = await auth.currentHouseholdId();
    if (userId == null || householdId == null) return const NoHousehold();

    final members = await households.listMembers(householdId);
    final others = members.where((m) => m.userId != userId).length;
    final me = members.where((m) => m.userId == userId).firstOrNull;

    if (others == 0) return const SoleMember();
    if (me?.isOwner ?? false) return OwnerHandsOver(others);
    return LeavesHousehold(others);
  }

  /// Returns false if the user cancelled the Apple confirmation. Throws if the
  /// server did not confirm; in that case nothing local has changed.
  Future<bool> deleteAccount() async {
    final deleted = await _withSessionCheck(auth.deleteAccount);
    if (!deleted) return false;

    // The server is done and the session is gone, so from here on failures
    // are logged rather than surfaced: with no session nothing syncs, and a
    // step that failed only leaves inert bookkeeping behind.
    await _forgetHousehold();
    return true;
  }

  Future<T> _withSessionCheck<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SessionInvalidException {
      await _forgetHousehold();
      rethrow;
    }
  }

  Future<void> _forgetHousehold() async {
    for (final step in <(String, Future<void> Function())>[
      ('detach vehicles', () => db.vehicleDao.detachAllFromHousehold()),
      ('clear sync queue', () => db.syncQueueDao.clear()),
      ('reset pull cursor', () => db.syncQueueDao.resetLastPulledAt()),
      ('clear entitlement cache', () => db.householdEntitlementDao.clear()),
    ]) {
      try {
        await step.$2();
      } catch (error) {
        debugPrint('Account deletion cleanup "${step.$1}" failed: $error');
      }
    }
  }
}

final accountDeletionServiceProvider = Provider<AccountDeletionService>(
  (ref) => AccountDeletionService(
    auth: ref.watch(authServiceProvider),
    households: ref.watch(householdServiceProvider),
    db: DatabaseHolder.instance,
  ),
);
