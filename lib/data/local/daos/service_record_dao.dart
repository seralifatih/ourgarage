import 'package:drift/drift.dart';

import '../../sync/sync_payloads.dart';
import '../database.dart';
import '../sync_enqueue.dart';

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

  /// Every live service record across all vehicles. The migration's read side.
  Future<List<ServiceRecord>> getAllRecords() {
    return (select(serviceRecords)..where((r) => r.deletedAt.isNull())).get();
  }

  Future<void> insertRecord(ServiceRecordsCompanion record) {
    return transaction(() async {
      await into(serviceRecords).insert(record);
      await attachedDatabase.enqueueServiceRecord(
        record.id.value,
        SyncOperation.upsert,
        record.updatedAt.value,
      );
    });
  }

  Future<bool> updateRecord(String id, ServiceRecordsCompanion changes) {
    return transaction(() async {
      final updated = await (update(
        serviceRecords,
      )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(changes);
      if (updated == 0) return false;

      await attachedDatabase.enqueueServiceRecord(
        id,
        SyncOperation.upsert,
        changes.updatedAt.present ? changes.updatedAt.value : DateTime.now(),
      );
      return true;
    });
  }

  Future<bool> softDeleteRecord(String id, DateTime deletedAt) {
    return transaction(() async {
      final updated =
          await (update(
            serviceRecords,
          )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(
            ServiceRecordsCompanion(
              deletedAt: Value(deletedAt),
              updatedAt: Value(deletedAt),
            ),
          );
      if (updated == 0) return false;

      await attachedDatabase.enqueueServiceRecord(
        id,
        SyncOperation.delete,
        deletedAt,
      );
      return true;
    });
  }

  /// Clears a record's tombstone, bringing it back into the active views.
  ///
  /// Deliberately matches on rows that *are* deleted — the inverse of every
  /// other method here — so that an undo can find its target.
  Future<bool> restoreRecord(String id, DateTime updatedAt) {
    return transaction(() async {
      final updated =
          await (update(
            serviceRecords,
          )..where((r) => r.id.equals(id) & r.deletedAt.isNotNull())).write(
            ServiceRecordsCompanion(
              deletedAt: const Value(null),
              updatedAt: Value(updatedAt),
            ),
          );
      if (updated == 0) return false;

      // An undo is an ordinary change carrying a newer updatedAt, so
      // last-write-wins lets it beat the delete it is undoing.
      await attachedDatabase.enqueueServiceRecord(
        id,
        SyncOperation.upsert,
        updatedAt,
      );
      return true;
    });
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
      await attachedDatabase.enqueueServiceRecord(
        record.id.value,
        SyncOperation.upsert,
        now,
      );

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
      // The vehicle changed too, so it needs its own queue row.
      await attachedDatabase.enqueueVehicle(
        vehicleId,
        SyncOperation.upsert,
        now,
      );
    });
  }
}
