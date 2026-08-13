import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/daos/vehicle_dao.dart';
import '../local/database.dart';

class VehicleRepository {
  VehicleRepository(this._dao, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _now = clock ?? DateTime.now;

  final VehicleDao _dao;
  final Uuid _uuid;
  final DateTime Function() _now;

  Stream<List<Vehicle>> watchAllVehicles() => _dao.watchAllVehicles();

  Stream<Vehicle?> watchVehicle(String id) => _dao.watchVehicle(id);

  Future<Vehicle?> getVehicle(String id) => _dao.getVehicle(id);

  /// Number of vehicles counting against the free-tier limit.
  Future<int> countActiveVehicles() => _dao.countActiveVehicles();

  /// Creates a vehicle, assigning it a v4 uuid and the creation timestamps.
  ///
  /// Returns the id of the new vehicle.
  Future<String> createVehicle({
    required String nickname,
    required String odometerUnit,
    String? make,
    String? model,
    int? year,
    String? plate,
    int odometer = 0,
    String? householdId,
  }) async {
    final id = _uuid.v4();
    final now = _now();

    await _dao.insertVehicle(
      VehiclesCompanion.insert(
        id: id,
        nickname: nickname,
        odometerUnit: odometerUnit,
        make: Value(make),
        model: Value(model),
        year: Value(year),
        plate: Value(plate),
        odometer: Value(odometer),
        // A starting odometer above zero is a real reading, so timestamp it.
        odometerUpdatedAt: Value(odometer > 0 ? now : null),
        householdId: Value(householdId),
        createdAt: now,
        updatedAt: now,
      ),
    );

    return id;
  }

  /// Updates the vehicle's editable fields and bumps `updatedAt`.
  ///
  /// Every parameter is optional; omitted ones are left untouched. Nullable
  /// fields take a [Value] so that clearing a field ([Value(null)]) stays
  /// distinguishable from leaving it alone (omitting the argument).
  Future<bool> updateVehicle(
    String id, {
    String? nickname,
    Value<String?> make = const Value.absent(),
    Value<String?> model = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<String?> plate = const Value.absent(),
    String? odometerUnit,
    Value<String?> householdId = const Value.absent(),
  }) {
    return _dao.updateVehicle(
      id,
      VehiclesCompanion(
        nickname: nickname == null ? const Value.absent() : Value(nickname),
        make: make,
        model: model,
        year: year,
        plate: plate,
        odometerUnit: odometerUnit == null
            ? const Value.absent()
            : Value(odometerUnit),
        householdId: householdId,
        updatedAt: Value(_now()),
      ),
    );
  }

  /// Records a new odometer reading.
  Future<bool> updateOdometer(String id, int value) {
    final now = _now();
    return _dao.updateVehicle(
      id,
      VehiclesCompanion(
        odometer: Value(value),
        odometerUpdatedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Soft-deletes the vehicle and cascades the tombstone to its service records
  /// and reminder rules.
  Future<void> softDeleteVehicle(String id) {
    return _dao.softDeleteVehicle(id, _now());
  }
}
