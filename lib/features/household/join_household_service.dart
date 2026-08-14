import '../../data/local/daos/sync_queue_dao.dart';
import '../../data/local/daos/vehicle_dao.dart';
import '../../data/sync/sync_service.dart';
import 'household_migration_service.dart';
import 'household_service.dart';

/// What the joiner wants done with the garage already on their phone.
enum LocalGarageChoice {
  /// Upload it into the household they just joined, sharing it with everyone.
  upload,

  /// Leave it on this device only. Nothing is deleted either way.
  keepLocal,
}

/// The outcome of joining, so the UI knows what to say next.
class JoinOutcome {
  const JoinOutcome({
    required this.householdId,
    required this.localVehicleCount,
    required this.uploaded,
  });

  final String householdId;

  /// How many vehicles were already on this device when they joined.
  final int localVehicleCount;

  /// Whether those vehicles were uploaded into the household.
  final bool uploaded;
}

/// Joining an existing household by code.
///
/// The awkward part is not the join, it is the garage the joiner may already
/// have. Joining does **not** merge two garages: their vehicles have no
/// household, the household's vehicles are not theirs, and quietly picking
/// either answer would be wrong. So the choice is put to them explicitly, and
/// neither branch destroys anything — "keep local" leaves the rows exactly
/// where they are, still readable, still theirs.
class JoinHouseholdService {
  const JoinHouseholdService({
    required HouseholdService households,
    required VehicleDao vehicleDao,
    required SyncQueueDao syncQueue,
    required HouseholdMigrationService migration,
    required SyncService sync,
  }) : _households = households,
       _vehicleDao = vehicleDao,
       _syncQueue = syncQueue,
       _migration = migration,
       _sync = sync;

  final HouseholdService _households;
  final VehicleDao _vehicleDao;
  final SyncQueueDao _syncQueue;
  final HouseholdMigrationService _migration;
  final SyncService _sync;

  /// Vehicles on this device that are not yet part of any household.
  ///
  /// What the warning is about: if this is non-zero, joining will leave them
  /// behind unless the user says otherwise.
  Future<int> unsharedVehicleCount() async {
    final vehicles = await _vehicleDao.getAllVehicles();
    return vehicles.where((v) => v.householdId == null).length;
  }

  /// Redeems [code] and settles what happens to the local garage.
  ///
  /// [choice] is only consulted when there is something to decide; a joiner
  /// with an empty garage is never asked.
  Future<JoinOutcome> join({
    required String code,
    required String userId,
    required LocalGarageChoice choice,
  }) async {
    final localCount = await unsharedVehicleCount();

    // Throws JoinException, which the UI turns into a specific message.
    final householdId = await _households.joinWithCode(code);

    // Anything queued before joining describes a row that belongs to nobody's
    // household. Pushing it now would upload the local garage regardless of
    // what the user chose — with a null household_id, so it would land
    // unreachable and, worse, overwrite a just-uploaded row's household_id
    // back to null. The queue is dropped and rebuilt from the decision below.
    await _syncQueue.clear();

    var uploaded = false;
    if (localCount > 0 && choice == LocalGarageChoice.upload) {
      // Same one-time upload the household creator runs, and it rolls back on
      // failure — so a failed upload leaves the local garage untouched rather
      // than half-shared.
      await _migration.migrate(householdId: householdId, userId: userId);
      uploaded = true;
    }

    // A full pull: lastPulledAt is null for a device that has never synced
    // this household, so this fetches everything the household already has.
    await _sync.sync(householdId: householdId);

    return JoinOutcome(
      householdId: householdId,
      localVehicleCount: localCount,
      uploaded: uploaded,
    );
  }
}
