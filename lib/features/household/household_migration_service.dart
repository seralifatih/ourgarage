import 'package:flutter/foundation.dart';

import '../../data/local/daos/reminder_rule_dao.dart';
import '../../data/local/daos/service_record_dao.dart';
import '../../data/local/daos/vehicle_dao.dart';
import '../../data/local/database.dart';
import '../../services/remote_garage.dart';

/// What the migration is doing, for the blocking progress UI.
enum MigrationPhase {
  preparing,
  uploadingVehicles,
  uploadingHistory,
  uploadingReminders,
  finishing,
  done,
}

@immutable
class MigrationProgress {
  const MigrationProgress({
    required this.phase,
    this.uploaded = 0,
    this.total = 0,
  });

  final MigrationPhase phase;

  /// Rows written so far, and how many there are in all. Both zero while
  /// preparing, since nothing has been counted yet.
  final int uploaded;
  final int total;

  double? get fraction => total == 0 ? null : uploaded / total;

  String get label => switch (phase) {
    MigrationPhase.preparing => 'Preparing your garage…',
    MigrationPhase.uploadingVehicles => 'Uploading vehicles…',
    MigrationPhase.uploadingHistory => 'Uploading service history…',
    MigrationPhase.uploadingReminders => 'Uploading reminders…',
    MigrationPhase.finishing => 'Finishing up…',
    MigrationPhase.done => 'Done',
  };
}

/// Raised when the upload failed and was rolled back.
class MigrationFailure implements Exception {
  const MigrationFailure(this.message, {this.rollbackFailed = false});

  final String message;

  /// Whether the compensating delete also failed, leaving rows behind.
  ///
  /// Not data loss — the local database is still untouched and authoritative,
  /// and re-running upserts over whatever survived — but worth distinguishing
  /// so the UI can say something truthful.
  final bool rollbackFailed;

  @override
  String toString() => 'MigrationFailure: $message';
}

/// Counts of what was uploaded, for assertions and for the success message.
@immutable
class MigrationResult {
  const MigrationResult({
    required this.vehicles,
    required this.serviceRecords,
    required this.reminderRules,
  });

  final int vehicles;
  final int serviceRecords;
  final int reminderRules;

  bool get isEmpty =>
      vehicles == 0 && serviceRecords == 0 && reminderRules == 0;
}

/// Uploads the local garage into a freshly created household, once.
///
/// Runs immediately after the household is created, while a blocking progress
/// dialog is up. The user must never be left with a half-migrated garage, so
/// the whole thing behaves as one logical unit:
///
///  * **Ordering.** Vehicles first, then service records and reminder rules,
///    both of which carry a foreign key to a vehicle. Uploading a child before
///    its parent is a guaranteed constraint violation.
///  * **Rollback.** PostgREST has no cross-request transaction, so atomicity
///    is achieved by compensation: any failure deletes everything already
///    uploaded for this household, leaving the cloud as empty as it was before
///    the attempt. (A Postgres RPC doing all three inserts inside one real
///    transaction would be stronger — see the note in the class docs of
///    [RemoteGarage] — but this keeps the write path plain PostgREST.)
///  * **Local data is never touched until the remote side is complete.** The
///    only local write is stamping `household_id` onto the vehicles, and it
///    happens last, after every upload has succeeded. A failed migration
///    therefore leaves the local database byte-for-byte as it was.
///  * **Idempotence.** Every write is an upsert keyed on the row's existing
///    uuid, so a crashed-and-retried migration converges rather than
///    duplicating. Ids are shared between local and remote, so nothing needs
///    remapping.
class HouseholdMigrationService {
  const HouseholdMigrationService({
    required VehicleDao vehicleDao,
    required ServiceRecordDao serviceRecordDao,
    required ReminderRuleDao reminderRuleDao,
    required RemoteGarage remote,
  }) : _vehicleDao = vehicleDao,
       _serviceRecordDao = serviceRecordDao,
       _reminderRuleDao = reminderRuleDao,
       _remote = remote;

  final VehicleDao _vehicleDao;
  final ServiceRecordDao _serviceRecordDao;
  final ReminderRuleDao _reminderRuleDao;
  final RemoteGarage _remote;

  /// Uploads everything local into [householdId], attributed to [userId].
  ///
  /// Throws [MigrationFailure] if anything went wrong; the cloud will have
  /// been cleaned up and the local database left alone.
  Future<MigrationResult> migrate({
    required String householdId,
    required String userId,
    ValueChanged<MigrationProgress>? onProgress,
  }) async {
    void report(MigrationPhase phase, {int uploaded = 0, int total = 0}) {
      onProgress?.call(
        MigrationProgress(phase: phase, uploaded: uploaded, total: total),
      );
    }

    report(MigrationPhase.preparing);

    final vehicles = await _vehicleDao.getAllVehicles();
    final vehicleIds = {for (final v in vehicles) v.id};

    // Children whose vehicle isn't going up would violate the remote foreign
    // key. The local soft-delete cascade should make this impossible, but a
    // constraint violation mid-upload is a miserable thing to debug, so the
    // filter is cheap insurance rather than a trusted invariant.
    final records = [
      for (final r in await _serviceRecordDao.getAllRecords())
        if (vehicleIds.contains(r.vehicleId)) r,
    ];
    final rules = [
      for (final r in await _reminderRuleDao.getAllRules())
        if (vehicleIds.contains(r.vehicleId)) r,
    ];

    final total = vehicles.length + records.length + rules.length;
    if (total == 0) {
      report(MigrationPhase.done);
      return const MigrationResult(
        vehicles: 0,
        serviceRecords: 0,
        reminderRules: 0,
      );
    }

    var uploaded = 0;

    try {
      report(MigrationPhase.uploadingVehicles, uploaded: 0, total: total);
      await _remote.upsertVehicles([
        for (final v in vehicles) _vehicleRow(v, householdId, userId),
      ]);
      uploaded += vehicles.length;

      report(MigrationPhase.uploadingHistory, uploaded: uploaded, total: total);
      await _remote.upsertServiceRecords([
        for (final r in records) _serviceRecordRow(r, userId),
      ]);
      uploaded += records.length;

      report(
        MigrationPhase.uploadingReminders,
        uploaded: uploaded,
        total: total,
      );
      await _remote.upsertReminderRules([
        for (final r in rules) _reminderRuleRow(r, userId),
      ]);
      uploaded += rules.length;
    } on Object catch (error) {
      // Returns Never: it always throws, either the original failure or a
      // rollback-failed variant of it.
      await _rollback(householdId, error);
    }

    // Only now, with every remote write landed, does the local database learn
    // that it is synced. Doing this earlier would leave vehicles claiming to
    // belong to a household that does not have them.
    report(MigrationPhase.finishing, uploaded: uploaded, total: total);
    await _vehicleDao.assignHousehold(vehicleIds.toList(), householdId);

    report(MigrationPhase.done, uploaded: total, total: total);

    return MigrationResult(
      vehicles: vehicles.length,
      serviceRecords: records.length,
      reminderRules: rules.length,
    );
  }

  /// Undoes a partial upload, then reports the original failure.
  Future<Never> _rollback(String householdId, Object cause) async {
    try {
      await _remote.deleteHouseholdData(householdId);
    } on Object catch (rollbackError) {
      debugPrint('Migration rollback failed: $rollbackError');
      throw MigrationFailure(
        'Your garage could not be uploaded, and the partial upload could not '
        'be cleaned up. Nothing on this phone was changed — trying again will '
        'reconcile it.',
        rollbackFailed: true,
      );
    }

    debugPrint('Migration failed, rolled back: $cause');
    throw const MigrationFailure(
      'Your garage could not be uploaded. Nothing on this phone was changed.',
    );
  }

  // The remote column names are snake_case; the Drift row fields are camelCase.
  // Timestamps go over the wire as ISO-8601 UTC, which is what Postgres
  // timestamptz expects.

  Map<String, dynamic> _vehicleRow(
    Vehicle v,
    String householdId,
    String userId,
  ) {
    return {
      'id': v.id,
      'household_id': householdId,
      'created_by': userId,
      'nickname': v.nickname,
      'make': v.make,
      'model': v.model,
      'year': v.year,
      'plate': v.plate,
      'odometer': v.odometer,
      'odometer_unit': v.odometerUnit,
      'odometer_updated_at': _iso(v.odometerUpdatedAt),
      'created_at': _iso(v.createdAt),
      'updated_at': _iso(v.updatedAt),
      'deleted_at': _iso(v.deletedAt),
    };
  }

  Map<String, dynamic> _serviceRecordRow(ServiceRecord r, String userId) {
    return {
      'id': r.id,
      'vehicle_id': r.vehicleId,
      'created_by': userId,
      'performed_at': _iso(r.performedAt),
      'odometer': r.odometer,
      'type': r.type,
      'custom_type_label': r.customTypeLabel,
      'notes': r.notes,
      'cost': r.cost,
      'currency': r.currency,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'deleted_at': _iso(r.deletedAt),
    };
  }

  Map<String, dynamic> _reminderRuleRow(ReminderRule r, String userId) {
    return {
      'id': r.id,
      'vehicle_id': r.vehicleId,
      'created_by': userId,
      'type': r.type,
      'custom_type_label': r.customTypeLabel,
      'interval_months': r.intervalMonths,
      'interval_distance': r.intervalDistance,
      'last_done_at': _iso(r.lastDoneAt),
      'last_done_odometer': r.lastDoneOdometer,
      'is_active': r.isActive,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'deleted_at': _iso(r.deletedAt),
    };
  }

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();
}
