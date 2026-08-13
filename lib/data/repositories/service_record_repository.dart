import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/daos/service_record_dao.dart';
import '../local/database.dart';
import '../models/service_type.dart';

class ServiceRecordRepository {
  ServiceRecordRepository(this._dao, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _now = clock ?? DateTime.now;

  final ServiceRecordDao _dao;
  final Uuid _uuid;
  final DateTime Function() _now;

  Stream<List<ServiceRecord>> watchRecordsForVehicle(String vehicleId) =>
      _dao.watchRecordsForVehicle(vehicleId);

  Future<ServiceRecord?> getRecord(String id) => _dao.getRecord(id);

  /// Creates a service record for [vehicleId].
  ///
  /// When [odometer] is higher than the vehicle's current reading, the
  /// vehicle's odometer is advanced to match — logging a service is the most
  /// common moment a fresh reading becomes available. A lower or equal reading
  /// leaves the vehicle untouched, since it describes a past state.
  ///
  /// Returns the id of the new record.
  Future<String> createRecord({
    required String vehicleId,
    required DateTime performedAt,
    required ServiceType type,
    int? odometer,
    String? customTypeLabel,
    String? notes,
    double? cost,
    String? currency,
  }) async {
    final id = _uuid.v4();
    final now = _now();

    await _dao.insertRecordAndSyncOdometer(
      ServiceRecordsCompanion.insert(
        id: id,
        vehicleId: vehicleId,
        performedAt: performedAt,
        type: type.name,
        odometer: Value(odometer),
        customTypeLabel: Value(customTypeLabel),
        notes: Value(notes),
        cost: Value(cost),
        currency: Value(currency),
        createdAt: now,
        updatedAt: now,
      ),
      vehicleId: vehicleId,
      odometer: odometer,
      now: now,
    );

    return id;
  }

  /// Updates an existing record and bumps `updatedAt`.
  ///
  /// Editing a record deliberately does not touch the vehicle's odometer: the
  /// vehicle may have moved on since, and silently rewinding it from a
  /// correction to old history would lose real data.
  Future<bool> updateRecord(
    String id, {
    DateTime? performedAt,
    ServiceType? type,
    Value<int?> odometer = const Value.absent(),
    Value<String?> customTypeLabel = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<double?> cost = const Value.absent(),
    Value<String?> currency = const Value.absent(),
  }) {
    return _dao.updateRecord(
      id,
      ServiceRecordsCompanion(
        performedAt: performedAt == null
            ? const Value.absent()
            : Value(performedAt),
        type: type == null ? const Value.absent() : Value(type.name),
        odometer: odometer,
        customTypeLabel: customTypeLabel,
        notes: notes,
        cost: cost,
        currency: currency,
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<bool> softDeleteRecord(String id) {
    return _dao.softDeleteRecord(id, _now());
  }

  /// Undoes a [softDeleteRecord], putting the record back in the history.
  ///
  /// Note this does not roll back any odometer advance the record caused when
  /// it was created: the vehicle may legitimately have travelled further since,
  /// and rewinding it would discard a real reading.
  Future<bool> restoreRecord(String id) {
    return _dao.restoreRecord(id, _now());
  }
}
