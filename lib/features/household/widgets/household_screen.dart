import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../app_routes.dart';
import '../../../data/repositories/database_holder.dart';
import '../../../services/auth_service_provider.dart';
import '../forget_household.dart';
import '../household_migration_provider.dart';
import '../household_service.dart';
import '../invite_share.dart';

/// Settings → Household: who is in it, inviting people, and leaving.
///
/// Everyone in a household sees the roster and can leave. Invites and
/// removing members are the owner's — the server enforces that (RLS on
/// household_invites, and `remove_household_member()`); the UI only avoids
/// offering buttons that would be refused.
class HouseholdScreen extends ConsumerStatefulWidget {
  const HouseholdScreen({super.key});

  @override
  ConsumerState<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdData {
  const _HouseholdData({
    required this.householdId,
    required this.members,
    required this.invites,
  });

  final String householdId;
  final List<HouseholdMember> members;
  final List<HouseholdInvite> invites;
}

const _offlineMessage =
    'Could not reach OurGarage. Check your connection and try again.';

/// The server answered but refused — e.g. someone else already removed this
/// member, or the household changed under us. Reloading shows the real state.
const _refusedMessage = 'That didn’t work. The household may have changed.';

class _HouseholdScreenState extends ConsumerState<HouseholdScreen> {
  late Future<_HouseholdData?> _data = _load();
  bool _busy = false;

  String? get _userId => ref.read(authServiceProvider).currentUserId;

  Future<_HouseholdData?> _load() async {
    // Straight from the server rather than via currentHouseholdIdProvider:
    // that one is auto-disposed, and nothing here keeps it alive while it
    // resolves.
    final householdId = await ref
        .read(authServiceProvider)
        .currentHouseholdId();
    if (householdId == null) return null;

    final households = ref.read(householdServiceProvider);
    final members = await households.listMembers(householdId);
    final me = members.where((m) => m.userId == _userId).firstOrNull;

    // Only the owner can read invites; for anyone else the query would just
    // come back empty, so it isn't made.
    final invites = (me?.isOwner ?? false)
        ? (await households.listInvites(householdId))
              .where((i) => i.isPending)
              .toList()
        : const <HouseholdInvite>[];

    return _HouseholdData(
      householdId: householdId,
      members: members,
      invites: invites,
    );
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  /// Runs [action] with the buttons disabled, reporting failure as a snackbar.
  ///
  /// A server refusal reloads, since what is on screen is evidently stale;
  /// anything else is treated as connectivity.
  Future<void> _run(Future<void> Function() action) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } on PostgrestException catch (error) {
      debugPrint('Household action refused: ${error.code} ${error.message}');
      _show(messenger, _refusedMessage);
      if (mounted) _reload();
    } catch (error) {
      debugPrint('Household action failed: $error');
      _show(messenger, _offlineMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Opens the share sheet; a failure there is not a household problem, so
  /// it gets its own message rather than [_run]'s.
  Future<void> _share(String code, Rect? origin) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(inviteSharerProvider)(inviteMessage(code), origin);
    } catch (error) {
      debugPrint('Share sheet failed: $error');
      _show(
        messenger,
        'Could not open the share sheet. Your code is $code — it’s listed '
        'under Pending invites.',
      );
    }
  }

  Future<void> _invite(BuildContext buttonContext, String householdId) {
    final origin = shareOriginOf(buttonContext);
    return _run(() async {
      final code = await ref
          .read(householdServiceProvider)
          .createInvite(householdId);
      _reload();
      await _share(code, origin);
    });
  }

  Future<void> _reshare(BuildContext tileContext, HouseholdInvite invite) {
    return _share(invite.code, shareOriginOf(tileContext));
  }

  Future<void> _revoke(HouseholdInvite invite) {
    return _run(() async {
      await ref.read(householdServiceProvider).revokeInvite(invite.id);
      _reload();
    });
  }

  Future<void> _remove(String householdId, HouseholdMember member) async {
    final confirmed = await _confirm(
      title: 'Remove ${member.label}?',
      body:
          'They will no longer see this garage. The vehicles and service '
          'history stay with the household.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;

    await _run(() async {
      await ref
          .read(householdServiceProvider)
          .removeMember(householdId: householdId, userId: member.userId);
      _reload();
    });
  }

  Future<void> _leave(_HouseholdData data) async {
    final others = data.members.where((m) => m.userId != _userId).toList();
    final me = data.members.where((m) => m.userId == _userId).firstOrNull;

    final consequence = others.isEmpty
        ? 'You are the only member, so the household and everything shared '
              'in it will be deleted from our servers.'
        : (me?.isOwner ?? false)
        ? '${others.first.label} will become the owner. The household and '
              'its shared garage carry on for everyone else.'
        : 'The household and its shared garage carry on for everyone else.';

    final confirmed = await _confirm(
      title: 'Leave household?',
      body:
          '$consequence\n\nThis phone keeps its own copy of the garage, which '
          'will no longer sync.',
      action: 'Leave',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    await _run(() async {
      await ref
          .read(householdServiceProvider)
          .leaveHousehold(data.householdId);
      await forgetHouseholdLocally(DatabaseHolder.instance);
      ref.invalidate(currentHouseholdIdProvider);

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('You’ve left the household')),
        );
      router.go(AppRoutes.settings);
    });
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Household')),
      body: FutureBuilder<_HouseholdData?>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              text: _offlineMessage,
              actionLabel: 'Try again',
              onAction: _reload,
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const _Message(text: 'You’re not in a household.');
          }
          return _buildHousehold(context, data);
        },
      ),
    );
  }

  Widget _buildHousehold(BuildContext context, _HouseholdData data) {
    final theme = Theme.of(context);
    final userId = _userId;
    final isOwner = data.members.any((m) => m.userId == userId && m.isOwner);
    final joined = DateFormat.yMMMd();
    final expires = DateFormat.MMMd();

    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _data;
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (isOwner) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Invite the people who drive your cars. They’ll see the same '
                'vehicles, history and reminders on their own phone.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _invite(buttonContext, data.householdId),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Invite someone'),
                ),
              ),
            ),
            if (data.invites.isNotEmpty) ...[
              const _SectionHeader('Pending invites'),
              for (final invite in data.invites)
                Builder(
                  builder: (tileContext) => ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(
                      invite.code,
                      style: const TextStyle(
                        letterSpacing: 2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    subtitle: Text(
                      'Expires ${expires.format(invite.expiresAt)} · '
                      'tap to share again',
                    ),
                    onTap: _busy ? null : () => _reshare(tileContext, invite),
                    trailing: IconButton(
                      tooltip: 'Revoke invite ${invite.code}',
                      icon: const Icon(Icons.close),
                      onPressed: _busy ? null : () => _revoke(invite),
                    ),
                  ),
                ),
            ],
          ],
          const _SectionHeader('Members'),
          for (final member in data.members)
            ListTile(
              leading: Icon(
                member.isOwner ? Icons.star_outline : Icons.person_outline,
              ),
              title: Text(
                member.userId == userId ? '${member.label} (you)' : member.label,
              ),
              subtitle: Text(
                '${member.isOwner ? 'Owner' : 'Member'} · '
                'joined ${joined.format(member.joinedAt)}',
              ),
              trailing: isOwner && member.userId != userId
                  ? IconButton(
                      tooltip: 'Remove ${member.label}',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: _busy
                          ? null
                          : () => _remove(data.householdId, member),
                    )
                  : null,
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _busy ? null : () => _leave(data),
              child: const Text('Leave household'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
