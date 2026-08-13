import 'package:drift/drift.dart';

import '../database.dart';

part 'service_record_dao.g.dart';

@DriftAccessor(tables: [ServiceRecords, Vehicles])
class ServiceRecordDao extends DatabaseAccessor<AppDatabase>
    with _$ServiceRecordDaoMixin {
  ServiceRecordDao(super.db);

  /// Live list of a vehicle's service history, newest first.
  ///
  /// Ties on [ServiceRecords.performedAt] fall back to [ServiceRecords.createdAt]
  /// so that same-day entries keep a stable, predictable order.
  Stream<List<ServiceRecord>> watchRecordsForVehicle(String vehicleId) {
    return (select(serviceRecords)
          ..where((r) => r.vehicleId.equals(vehicleId) & r.deletedAt.isNull())
          ..orderBy([
            (r) => OrderingTerm.desc(r.performedAt),
            (r) => OrderingTerm.desc(r.createdAt),
          ]))
        .watch();
  }

  Future<ServiceRecord?> getRecord(String id) {
    return (select(
      serviceRecords,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull();
  }

  Future<void> insertRecord(ServiceRecordsCompanion record) {
    return into(serviceRecords).insert(record);
  }

  Future<bool> updateRecord(String id, ServiceRecordsCompanion changes) async {
    final updated = await (update(
      serviceRecords,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(changes);
    return updated > 0;
  }

  Future<bool> softDeleteRecord(String id, DateTime deletedAt) async {
    final updated =
        await (update(
          serviceRecords,
        )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(
          ServiceRecordsCompanion(
            deletedAt: Value(deletedAt),
            updatedAt: Value(deletedAt),
          ),
        );
    return updated > 0;
  }

  /// Clears a record's tombstone, bringing it back into the active views.
  ///
  /// Deliberately matches on rows that *are* deleted — the inverse of every
  /// other method here — so that an undo can find its target.
  Future<bool> restoreRecord(String id, DateTime updatedAt) async {
    final updated =
        await (update(
          serviceRecords,
        )..where((r) => r.id.equals(id) & r.deletedAt.isNotNull())).write(
          ServiceRecordsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(updatedAt),
          ),
        );
    return updated > 0;
  }

  /// Inserts [record] and, when its odometer reading exceeds the vehicle's
  /// current one, advances the vehicle's odometer to match.
  ///
  /// Both writes share a transaction so the reading and the vehicle's odometer
  /// can never disagree, and the vehicle is re-read inside it so a concurrent
  /// update cannot be clobbered by a stale comparison.
  Future<void> insertRecordAndSyncOdometer(
    ServiceRecordsCompanion record, {
    required String vehicleId,
    required int? odometer,
    required DateTime now,
  }) {
    return transaction(() async {
      await into(serviceRecords).insert(record);

      if (odometer == null) return;

      final vehicle =
          await (select(vehicles)
                ..where((v) => v.id.equals(vehicleId) & v.deletedAt.isNull()))
              .getSingleOrNull();
      if (vehicle == null) return;
      if (odometer <= vehicle.odometer) return;

      await (update(vehicles)..where((v) => v.id.equals(vehicleId))).write(
        VehiclesCompanion(
          odometer: Value(odometer),
          odometerUpdatedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }
}
