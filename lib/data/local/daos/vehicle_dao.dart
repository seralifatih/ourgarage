import 'package:drift/drift.dart';

import '../../sync/sync_payloads.dart';
import '../database.dart';
import '../sync_enqueue.dart';

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

  /// Every live vehicle, oldest first. The migration's read side.
  Future<List<Vehicle>> getAllVehicles() {
    return (select(vehicles)
          ..where((v) => v.deletedAt.isNull())
          ..orderBy([(v) => OrderingTerm.asc(v.createdAt)]))
        .get();
  }

  /// Stamps [householdId] onto the given vehicles, marking them as synced.
  ///
  /// Deliberately does not touch `updatedAt`: this is a sync bookkeeping write,
  /// not a user edit, and bumping the timestamp would make every vehicle look
  /// freshly modified to whatever reconciles changes later.
  Future<int> assignHousehold(List<String> ids, String householdId) {
    if (ids.isEmpty) return Future.value(0);

    return (update(vehicles)..where((v) => v.id.isIn(ids))).write(
      VehiclesCompanion(householdId: Value(householdId)),
    );
  }

  Future<void> insertVehicle(VehiclesCompanion vehicle) {
    // Write and queue entry share a transaction: a change that lands locally
    // without a queue row would never sync, and nothing would ever notice.
    return transaction(() async {
      await into(vehicles).insert(vehicle);
      await attachedDatabase.enqueueVehicle(
        vehicle.id.value,
        SyncOperation.upsert,
        vehicle.updatedAt.value,
      );
    });
  }

  /// Applies [changes] to the vehicle with [id]. Returns whether a row matched.
  Future<bool> updateVehicle(String id, VehiclesCompanion changes) {
    return transaction(() async {
      final updated = await (update(
        vehicles,
      )..where((v) => v.id.equals(id) & v.deletedAt.isNull())).write(changes);
      if (updated == 0) return false;

      await attachedDatabase.enqueueVehicle(
        id,
        SyncOperation.upsert,
        changes.updatedAt.present ? changes.updatedAt.value : DateTime.now(),
      );
      return true;
    });
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

      // The tombstone has to propagate to every row it touched, not just the
      // vehicle: a peer that only heard about the vehicle would keep showing
      // its history.
      await attachedDatabase.enqueueVehicle(
        id,
        SyncOperation.delete,
        deletedAt,
      );
      await attachedDatabase.enqueueChildrenOf(id, deletedAt);
    });
  }
}
