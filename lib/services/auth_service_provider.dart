import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service.dart';

part 'auth_service_provider.g.dart';

/// The app-wide [AuthService].
///
/// Kept alive for the process lifetime: it is the source of the signed-in user
/// id that sync and household membership hang off, so tearing it down when the
/// last listener drops would be wrong.
///
/// Tests override this with a service wrapping a fake [AuthBackend].
@Riverpod(keepAlive: true)
AuthService authService(Ref ref) => AuthService();

/// The signed-in user's id, or null when signed out.
///
/// Null is the normal state: a free, local-only user never signs in at all.
@Riverpod(keepAlive: true)
Stream<String?> currentUserId(Ref ref) {
  final service = ref.watch(authServiceProvider);

  // Seeded with the restored session so the first frame after launch already
  // knows who the user is — supabase_flutter rehydrates from secure storage
  // during initialize(), before runApp.
  return service.userIdChanges;
}

/// The signed-in user's household, or null when signed out or not in one.
///
/// Watches [currentUserIdProvider] rather than reading it once, so signing in
/// or out — including the moment "Join a household" gives the user their
/// first one — re-resolves this rather than leaving it stale.
@riverpod
Future<String?> currentHouseholdId(Ref ref) async {
  final userId = await ref.watch(currentUserIdProvider.future);
  if (userId == null) return null;

  return ref.watch(authServiceProvider).currentHouseholdId();
}
