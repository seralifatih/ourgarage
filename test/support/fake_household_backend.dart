import 'package:ourgarage/features/household/household_service.dart';

/// An in-memory [HouseholdBackend] that enforces the rules the SQL function
/// does: a code is single-use, expires, and must exist.
class FakeHouseholdBackend implements HouseholdBackend {
  FakeHouseholdBackend({this.callerUserId = 'joiner-1'});

  final String callerUserId;

  final invites = <String, HouseholdInvite>{};
  final inviteHouseholds = <String, String>{};
  final members = <String, List<HouseholdMember>>{};

  /// Every code minted, so a test can assert on uniqueness and shape.
  final codesIssued = <String>[];

  /// Fails the next createInvite once, to drive the collision retry.
  bool failNextCreate = false;

  int removeMemberCount = 0;
  int revokeInviteCount = 0;

  @override
  Future<String> createInvite({
    required String householdId,
    required String code,
    required DateTime expiresAt,
  }) async {
    if (failNextCreate) {
      failNextCreate = false;
      throw StateError('duplicate key value violates unique constraint');
    }
    if (invites.values.any((i) => i.code == code)) {
      throw StateError('duplicate key value violates unique constraint');
    }

    codesIssued.add(code);
    final id = 'invite-${invites.length + 1}';
    invites[id] = HouseholdInvite(
      id: id,
      code: code,
      expiresAt: expiresAt,
      acceptedAt: null,
    );
    inviteHouseholds[id] = householdId;
    return id;
  }

  @override
  Future<List<HouseholdInvite>> listInvites(String householdId) async {
    return [
      for (final entry in invites.entries)
        if (inviteHouseholds[entry.key] == householdId) entry.value,
    ];
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    revokeInviteCount++;
    invites.remove(inviteId);
    inviteHouseholds.remove(inviteId);
  }

  @override
  Future<List<HouseholdMember>> listMembers(String householdId) async =>
      members[householdId] ?? const [];

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) async {
    removeMemberCount++;
    members[householdId]?.removeWhere((m) => m.userId == userId);
  }

  @override
  Future<String> acceptInvite(String code) async {
    final entry = invites.entries
        .where((e) => e.value.code == code)
        .firstOrNull;

    if (entry == null) throw const JoinException(JoinFailure.notFound);
    if (entry.value.acceptedAt != null) {
      throw const JoinException(JoinFailure.alreadyUsed);
    }
    if (!entry.value.expiresAt.isAfter(DateTime.now())) {
      throw const JoinException(JoinFailure.expired);
    }

    final householdId = inviteHouseholds[entry.key]!;

    invites[entry.key] = HouseholdInvite(
      id: entry.value.id,
      code: entry.value.code,
      expiresAt: entry.value.expiresAt,
      acceptedAt: DateTime.now(),
    );

    (members[householdId] ??= []).add(
      HouseholdMember(
        userId: callerUserId,
        role: 'member',
        joinedAt: DateTime.now(),
      ),
    );

    return householdId;
  }

  /// Seeds an invite as though the owner had created it.
  String seedInvite({
    required String householdId,
    required String code,
    DateTime? expiresAt,
  }) {
    final id = 'invite-${invites.length + 1}';
    invites[id] = HouseholdInvite(
      id: id,
      code: code,
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(days: 7)),
      acceptedAt: null,
    );
    inviteHouseholds[id] = householdId;
    return id;
  }
}
