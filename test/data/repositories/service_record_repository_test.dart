import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/service_record_repository.dart';
import 'package:ourgarage/data/repositories/vehicle_repository.dart';

void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late ServiceRecordRepository records;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    vehicles = VehicleRepository(db.vehicleDao);
    records = ServiceRecordRepository(db.serviceRecordDao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> createVehicleAt(int odometer) async {
    final id = await vehicles.createVehicle(
      nickname: 'Blue Civic',
      odometerUnit: 'km',
      odometer: odometer,
    );
    return id;
  }

  group('createRecord odometer side effect', () {
    test('advances the vehicle odometer when the reading is higher', () async {
      final id = await createVehicleAt(10000);

      await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 2, 1),
        type: ServiceType.oilChange,
        odometer: 12500,
      );

      final vehicle = await vehicles.getVehicle(id);
      expect(vehicle!.odometer, 12500);
      expect(vehicle.odometerUpdatedAt, isNotNull);
    });

    test('leaves the odometer alone when the reading is lower', () async {
      final id = await createVehicleAt(20000);
      final before = await vehicles.getVehicle(id);

      await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 2, 1),
        type: ServiceType.oilChange,
        odometer: 15000,
      );

      final after = await vehicles.getVehicle(id);
      expect(after!.odometer, 20000);
      expect(after.odometerUpdatedAt, before!.odometerUpdatedAt);
    });

    test('leaves the odometer alone when the reading is equal', () async {
      final id = await createVehicleAt(20000);
      final before = await vehicles.getVehicle(id);

      await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 2, 1),
        type: ServiceType.tireRotation,
        odometer: 20000,
      );

      final after = await vehicles.getVehicle(id);
      expect(after!.odometer, 20000);
      expect(after.odometerUpdatedAt, before!.odometerUpdatedAt);
    });

    test('leaves the odometer alone when the record has no reading', () async {
      final id = await createVehicleAt(20000);
      final before = await vehicles.getVehicle(id);

      await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 2, 1),
        type: ServiceType.inspection,
      );

      final after = await vehicles.getVehicle(id);
      expect(after!.odometer, 20000);
      expect(after.odometerUpdatedAt, before!.odometerUpdatedAt);
    });

    test('only touches the vehicle the record belongs to', () async {
      final target = await createVehicleAt(10000);
      final other = await vehicles.createVehicle(
        nickname: 'Old Truck',
        odometerUnit: 'km',
        odometer: 5000,
      );

      await records.createRecord(
        vehicleId: target,
        performedAt: DateTime(2026, 2, 1),
        type: ServiceType.oilChange,
        odometer: 30000,
      );

      expect((await vehicles.getVehicle(target))!.odometer, 30000);
      expect((await vehicles.getVehicle(other))!.odometer, 5000);
    });

    test('a later, higher reading advances the odometer again', () async {
      final id = await createVehicleAt(10000);

      await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 2, 1),
        type: ServiceType.oilChange,
        odometer: 12000,
      );
      await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 5, 1),
        type: ServiceType.tireRotation,
        odometer: 18000,
      );

      expect((await vehicles.getVehicle(id))!.odometer, 18000);
    });

    test(
      'backdated history entered after a newer reading does not rewind it',
      () async {
        final id = await createVehicleAt(10000);

        await records.createRecord(
          vehicleId: id,
          performedAt: DateTime(2026, 5, 1),
          type: ServiceType.oilChange,
          odometer: 18000,
        );
        // An older service logged after the fact.
        await records.createRecord(
          vehicleId: id,
          performedAt: DateTime(2026, 1, 1),
          type: ServiceType.airFilter,
          odometer: 11000,
        );

        expect((await vehicles.getVehicle(id))!.odometer, 18000);
      },
    );

    test(
      'the record itself is stored regardless of the odometer outcome',
      () async {
        final id = await createVehicleAt(20000);

        final recordId = await records.createRecord(
          vehicleId: id,
          performedAt: DateTime(2026, 2, 1),
          type: ServiceType.brakes,
          odometer: 15000,
          notes: 'Front pads',
        );

        final stored = await records.getRecord(recordId);
        expect(stored, isNotNull);
        expect(stored!.odometer, 15000);
        expect(stored.notes, 'Front pads');
        expect(stored.type, ServiceType.brakes.name);
      },
    );
  });

  group('watchRecordsForVehicle', () {
    test('returns newest first and excludes soft-deleted records', () async {
      final id = await createVehicleAt(0);

      await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 1, 1),
        type: ServiceType.oilChange,
      );
      final middle = await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 3, 1),
        type: ServiceType.brakes,
      );
      await records.createRecord(
        vehicleId: id,
        performedAt: DateTime(2026, 6, 1),
        type: ServiceType.tireChange,
      );

      var visible = await records.watchRecordsForVehicle(id).first;
      expect(visible.map((r) => r.type), [
        ServiceType.tireChange.name,
        ServiceType.brakes.name,
        ServiceType.oilChange.name,
      ]);

      await records.softDeleteRecord(middle);

      visible = await records.watchRecordsForVehicle(id).first;
      expect(visible.map((r) => r.type), [
        ServiceType.tireChange.name,
        ServiceType.oilChange.name,
      ]);
    });
  });
}
