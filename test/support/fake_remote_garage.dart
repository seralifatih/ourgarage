import 'package:ourgarage/features/household/household_migration_provider.dart';
import 'package:ourgarage/services/remote_garage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// An in-memory [RemoteGarage] that behaves like the real tables.
///
/// It enforces the two things that make upload ordering matter, so a bug in
/// the migration surfaces here rather than only against a live database:
///
///  * a service record or reminder rule whose vehicle is absent is rejected,
///    mirroring the foreign key;
///  * rows are keyed by id, so an upsert of an existing id replaces rather
///    than duplicates — which is what makes the idempotence assertion real.
class FakeRemoteGarage implements RemoteGarage {
  /// Rows by id, exactly as the migration sent them.
  final vehicles = <String, Map<String, dynamic>>{};
  final serviceRecords = <String, Map<String, dynamic>>{};
  final reminderRules = <String, Map<String, dynamic>>{};

  /// Fails the matching call once, then behaves normally. Lets a test drive
  /// the rollback path and then a successful retry.
  String? failOn;

  /// When true, every call throws — the device is offline.
  bool offline = false;

  int deleteHouseholdDataCount = 0;

  void _maybeFail(String call) {
    if (offline) {
      throw StateError('Offline: $call');
    }
    if (failOn != call) return;
    failOn = null;
    throw StateError('Simulated failure in $call');
  }

  /// Writes a row as if another device had pushed it, bypassing the checks
  /// that apply to this device's own pushes.
  void seedRemote(String entity, Map<String, dynamic> row) {
    switch (entity) {
      case 'vehicle':
        vehicles[row['id'] as String] = row;
      case 'serviceRecord':
        serviceRecords[row['id'] as String] = row;
      case 'reminderRule':
        reminderRules[row['id'] as String] = row;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChangedSince({
    required String householdId,
    required DateTime? since,
  }) async {
    _maybeFail('fetchChangedSince');

    bool changed(Map<String, dynamic> row) {
      if (since == null) return true;
      final updatedAt = DateTime.parse(row['updated_at'] as String).toUtc();
      return updatedAt.isAfter(since.toUtc());
    }

    final householdVehicleIds = vehicles.values
        .where((v) => v['household_id'] == householdId)
        .map((v) => v['id'] as String)
        .toSet();

    return [
      for (final v in vehicles.values)
        if (v['household_id'] == householdId && changed(v))
          {...v, '_entity': 'vehicle'},
      for (final r in serviceRecords.values)
        if (householdVehicleIds.contains(r['vehicle_id']) && changed(r))
          {...r, '_entity': 'serviceRecord'},
      for (final r in reminderRules.values)
        if (householdVehicleIds.contains(r['vehicle_id']) && changed(r))
          {...r, '_entity': 'reminderRule'},
    ];
  }

  @override
  Future<void> upsertVehicles(List<Map<String, dynamic>> rows) async {
    _maybeFail('upsertVehicles');
    for (final row in rows) {
      vehicles[row['id'] as String] = row;
    }
  }

  @override
  Future<void> upsertServiceRecords(List<Map<String, dynamic>> rows) async {
    _maybeFail('upsertServiceRecords');
    for (final row in rows) {
      final vehicleId = row['vehicle_id'] as String;
      if (!vehicles.containsKey(vehicleId)) {
        throw StateError(
          'service_records.vehicle_id $vehicleId has no vehicle — '
          'vehicles must be uploaded first',
        );
      }
      serviceRecords[row['id'] as String] = row;
    }
  }

  @override
  Future<void> upsertReminderRules(List<Map<String, dynamic>> rows) async {
    _maybeFail('upsertReminderRules');
    for (final row in rows) {
      final vehicleId = row['vehicle_id'] as String;
      if (!vehicles.containsKey(vehicleId)) {
        throw StateError(
          'reminder_rules.vehicle_id $vehicleId has no vehicle — '
          'vehicles must be uploaded first',
        );
      }
      reminderRules[row['id'] as String] = row;
    }
  }

  @override
  Future<void> deleteHouseholdData(String householdId) async {
    deleteHouseholdDataCount++;
    _maybeFail('deleteHouseholdData');

    final doomed = vehicles.values
        .where((v) => v['household_id'] == householdId)
        .map((v) => v['id'] as String)
        .toSet();

    serviceRecords.removeWhere((_, r) => doomed.contains(r['vehicle_id']));
    reminderRules.removeWhere((_, r) => doomed.contains(r['vehicle_id']));
    vehicles.removeWhere((id, _) => doomed.contains(id));
  }

  bool get isEmpty =>
      vehicles.isEmpty && serviceRecords.isEmpty && reminderRules.isEmpty;
}

Override fakeRemoteGarageOverride(FakeRemoteGarage remote) {
  return remoteGarageProvider.overrideWithValue(remote);
}
