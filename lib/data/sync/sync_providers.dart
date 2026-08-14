import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/household/household_migration_provider.dart';
import '../../features/household/join_household_service.dart';
import '../repositories/database_holder.dart';
import 'sync_service.dart';

// Declared by hand rather than with `@riverpod` for the reason documented in
// `stream_providers.dart`: riverpod_generator 4.0.4 rejects any annotated
// function whose library graph pulls in drift row types, and SyncService is
// built from the database directly.

/// The app-wide sync engine.
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    db: DatabaseHolder.instance,
    remote: ref.watch(remoteGarageProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Sync state for the indicator. Never gates anything the user can do.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncServiceProvider).statusStream;
});

/// How many local changes are still waiting to be pushed.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return DatabaseHolder.instance.syncQueueDao.watchPendingCount();
});

/// Joining an existing household, and what happens to a local garage.
final joinHouseholdServiceProvider = Provider<JoinHouseholdService>((ref) {
  return JoinHouseholdService(
    households: ref.watch(householdServiceProvider),
    vehicleDao: DatabaseHolder.instance.vehicleDao,
    syncQueue: DatabaseHolder.instance.syncQueueDao,
    migration: ref.watch(householdMigrationProvider),
    sync: ref.watch(syncServiceProvider),
  );
});
