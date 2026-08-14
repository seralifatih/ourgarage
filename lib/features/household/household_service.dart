import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invite_code.dart';

/// How long an invite stays redeemable.
const Duration inviteLifetime = Duration(days: 7);

/// Why joining a household failed, in terms the UI can act on.
enum JoinFailure {
  notFound,
  expired,
  alreadyUsed,
  notSignedIn,
  network;

  String get message => switch (this) {
    JoinFailure.notFound => 'That code doesn’t match any invite.',
    JoinFailure.expired => 'That invite has expired. Ask for a new one.',
    JoinFailure.alreadyUsed => 'That invite has already been used.',
    JoinFailure.notSignedIn => 'You need to be signed in to join.',
    JoinFailure.network =>
      'Could not reach the server. Check your connection and try again.',
  };
}

class JoinException implements Exception {
  const JoinException(this.failure);

  final JoinFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'JoinException: ${failure.name}';
}

@immutable
class HouseholdInvite {
  const HouseholdInvite({
    required this.id,
    required this.code,
    required this.expiresAt,
    required this.acceptedAt,
  });

  final String id;
  final String code;
  final DateTime expiresAt;
  final DateTime? acceptedAt;

  bool get isPending => acceptedAt == null && expiresAt.isAfter(DateTime.now());
  bool get isExpired =>
      acceptedAt == null && !expiresAt.isAfter(DateTime.now());
}

@immutable
class HouseholdMember {
  const HouseholdMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.displayName,
  });

  final String userId;
  final String role;
  final DateTime joinedAt;
  final String? displayName;

  bool get isOwner => role == 'owner';
}

/// Invites and membership, from the owner's and the joiner's side.
///
/// Every method here goes through the policies and functions in
/// `supabase/migrations/`. Notably, nothing in this class inserts into
/// `household_members` — that table has no client INSERT policy at all, and
/// [joinWithCode] reaches it only through the `accept_household_invite`
/// SECURITY DEFINER function, which is the single sanctioned path.
abstract interface class HouseholdBackend {
  Future<String> createInvite({
    required String householdId,
    required String code,
    required DateTime expiresAt,
  });

  Future<List<HouseholdInvite>> listInvites(String householdId);

  Future<void> revokeInvite(String inviteId);

  Future<List<HouseholdMember>> listMembers(String householdId);

  Future<void> removeMember({
    required String householdId,
    required String userId,
  });

  /// Redeems [code], returning the household joined.
  Future<String> acceptInvite(String code);
}

class SupabaseHouseholdBackend implements HouseholdBackend {
  const SupabaseHouseholdBackend();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<String> createInvite({
    required String householdId,
    required String code,
    required DateTime expiresAt,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const JoinException(JoinFailure.notSignedIn);

    final row = await _client
        .from('household_invites')
        .insert({
          'household_id': householdId,
          'code': code,
          'created_by': userId,
          'expires_at': expiresAt.toUtc().toIso8601String(),
        })
        .select('id')
        .single();

    return row['id'] as String;
  }

  @override
  Future<List<HouseholdInvite>> listInvites(String householdId) async {
    final rows = await _client
        .from('household_invites')
        .select()
        .eq('household_id', householdId)
        .order('expires_at', ascending: false);

    return [
      for (final row in rows as List)
        HouseholdInvite(
          id: (row as Map)['id'] as String,
          code: row['code'] as String,
          expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
          acceptedAt: row['accepted_at'] == null
              ? null
              : DateTime.parse(row['accepted_at'] as String).toLocal(),
        ),
    ];
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    await _client.from('household_invites').delete().eq('id', inviteId);
  }

  @override
  Future<List<HouseholdMember>> listMembers(String householdId) async {
    // profiles is readable only for your own row, so a member's display name
    // is not fetchable here. The roster shows roles and join dates; putting
    // names on it needs a view or a definer function, which is a deliberate
    // gap rather than an oversight.
    final rows = await _client
        .from('household_members')
        .select()
        .eq('household_id', householdId)
        .order('joined_at');

    return [
      for (final row in rows as List)
        HouseholdMember(
          userId: (row as Map)['user_id'] as String,
          role: row['role'] as String,
          joinedAt: DateTime.parse(row['joined_at'] as String).toLocal(),
        ),
    ];
  }

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) async {
    // Removing a member deletes only the membership row. Their vehicles stay
    // with the household — the data belongs to the garage, not the person, and
    // cascading a delete here would destroy shared history because somebody
    // left.
    await _client
        .from('household_members')
        .delete()
        .eq('household_id', householdId)
        .eq('user_id', userId);
  }

  @override
  Future<String> acceptInvite(String code) async {
    try {
      final result = await _client.rpc<dynamic>(
        'accept_household_invite',
        params: {'invite_code': code},
      );
      return result as String;
    } on PostgrestException catch (error) {
      throw JoinException(_failureFor(error));
    }
  }

  /// Maps the SQL function's error codes onto something the UI can phrase.
  ///
  /// The codes are chosen in the migration precisely so the client can tell
  /// these apart without string-matching an error message.
  static JoinFailure _failureFor(PostgrestException error) {
    return switch (error.code) {
      'P0002' => JoinFailure.notFound,
      '23505' => JoinFailure.alreadyUsed,
      '22023' => JoinFailure.expired,
      '28000' => JoinFailure.notSignedIn,
      _ => JoinFailure.network,
    };
  }
}

/// Owner- and joiner-side household operations.
class HouseholdService {
  const HouseholdService([this._backend = const SupabaseHouseholdBackend()]);

  final HouseholdBackend _backend;

  /// Mints a fresh invite and returns the code to share.
  ///
  /// Retries on collision rather than assuming uniqueness: the code column is
  /// unique, so a duplicate is a constraint violation rather than a silent
  /// overwrite, and at 887 million combinations a second attempt is
  /// overwhelmingly likely to succeed.
  Future<String> createInvite(String householdId, {int attempts = 3}) async {
    Object? lastError;

    for (var attempt = 0; attempt < attempts; attempt++) {
      final code = InviteCode.generate();
      try {
        await _backend.createInvite(
          householdId: householdId,
          code: code,
          expiresAt: DateTime.now().toUtc().add(inviteLifetime),
        );
        return code;
      } on Object catch (error) {
        lastError = error;
      }
    }

    throw StateError('Could not create an invite: $lastError');
  }

  Future<List<HouseholdInvite>> listInvites(String householdId) =>
      _backend.listInvites(householdId);

  Future<void> revokeInvite(String inviteId) => _backend.revokeInvite(inviteId);

  Future<List<HouseholdMember>> listMembers(String householdId) =>
      _backend.listMembers(householdId);

  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) {
    return _backend.removeMember(householdId: householdId, userId: userId);
  }

  /// Redeems a hand-typed code, returning the household joined.
  Future<String> joinWithCode(String rawCode) {
    final code = InviteCode.normalise(rawCode);
    if (!InviteCode.isWellFormed(code)) {
      // Caught before the round trip: a six-character check is not worth a
      // network call, and "that isn't a code" is a better message than
      // whatever the server would say.
      throw const JoinException(JoinFailure.notFound);
    }
    return _backend.acceptInvite(code);
  }
}
