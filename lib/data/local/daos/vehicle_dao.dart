import 'package:drift/drift.dart';

import '../database.dart';

part 'vehicle_dao.g.dart';

@DriftAccessor(tables: [Vehicles, ServiceRecords, ReminderRules])
class VehicleDao extends DatabaseAccessor<AppDatabase> with _$VehicleDaoMixin {
  VehicleDao(super.db);

  /// Live list of vehicles that have not been soft-deleted, oldest first.
  Stream<List<Vehicle>> watchAllVehicles() {
    return (select(vehicles)
          ..where((v) => v.deletedAt.isNull())
          ..orderBy([(v) => OrderingTerm.asc(v.createdAt)]))
        .watch();
  }

  /// Live view of a single vehicle. Emits null once the vehicle is gone or
  /// soft-deleted.
  Stream<Vehicle?> watchVehicle(String id) {
    return (select(vehicles)
          ..where((v) => v.id.equals(id) & v.deletedAt.isNull()))
        .watchSingleOrNull();
  }

  Future<Vehicle?> getVehicle(String id) {
    return (select(
      vehicles,
    )..where((v) => v.id.equals(id) & v.deletedAt.isNull())).getSingleOrNull();
  }

  Future<void> insertVehicle(VehiclesCompanion vehicle) {
    return into(vehicles).insert(vehicle);
  }

  /// Applies [changes] to the vehicle with [id]. Returns whether a row matched.
  Future<bool> updateVehicle(String id, VehiclesCompanion changes) async {
    final updated = await (update(
      vehicles,
    )..where((v) => v.id.equals(id) & v.deletedAt.isNull())).write(changes);
    return updated > 0;
  }

  /// Number of vehicles that count against the free-tier limit.
  Future<int> countActiveVehicles() async {
    final count = vehicles.id.count();
    final query = selectOnly(vehicles)
      ..addColumns([count])
      ..where(vehicles.deletedAt.isNull());
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Soft-deletes the vehicle and cascades the tombstone to everything hanging
  /// off it, so that child rows are not left dangling for the sync layer.
  ///
  /// Runs in a single transaction: either the whole subtree is tombstoned or
  /// none of it is. Children already carrying a [deletedAt] keep their original
  /// timestamp — retaining the earlier tombstone preserves when the deletion
  /// actually happened.
  Future<void> softDeleteVehicle(String id, DateTime deletedAt) {
    return transaction(() async {
      await (update(
        vehicles,
      )..where((v) => v.id.equals(id) & v.deletedAt.isNull())).write(
        VehiclesCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(deletedAt),
        ),
      );

      await (update(
        serviceRecords,
      )..where((r) => r.vehicleId.equals(id) & r.deletedAt.isNull())).write(
        ServiceRecordsCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(deletedAt),
        ),
      );

      await (update(
        reminderRules,
      )..where((r) => r.vehicleId.equals(id) & r.deletedAt.isNull())).write(
        ReminderRulesCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(deletedAt),
        ),
      );
    });
  }
}
