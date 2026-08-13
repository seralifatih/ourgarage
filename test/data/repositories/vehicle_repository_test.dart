import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/reminder_rule_repository.dart';
import 'package:ourgarage/data/repositories/service_record_repository.dart';
import 'package:ourgarage/data/repositories/vehicle_repository.dart';

void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late ServiceRecordRepository records;
  late ReminderRuleRepository rules;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    vehicles = VehicleRepository(db.vehicleDao);
    records = ServiceRecordRepository(db.serviceRecordDao);
    rules = ReminderRuleRepository(db.reminderRuleDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('softDeleteVehicle', () {
    test(
      'cascades the tombstone to service records and reminder rules',
      () async {
        final vehicleId = await vehicles.createVehicle(
          nickname: 'Blue Civic',
          odometerUnit: 'km',
        );

        final recordId = await records.createRecord(
          vehicleId: vehicleId,
          performedAt: DateTime(2026, 1, 10),
          type: ServiceType.oilChange,
        );
        final ruleId = await rules.createRule(
          vehicleId: vehicleId,
          type: ServiceType.oilChange,
          intervalMonths: 6,
        );

        // Everything is visible before the delete.
        expect(await vehicles.getVehicle(vehicleId), isNotNull);
        expect(await records.getRecord(recordId), isNotNull);
        expect(await rules.getRule(ruleId), isNotNull);

        await vehicles.softDeleteVehicle(vehicleId);

        // The vehicle and both children drop out of the active views.
        expect(await vehicles.getVehicle(vehicleId), isNull);
        expect(await records.getRecord(recordId), isNull);
        expect(await rules.getRule(ruleId), isNull);

        // ...because they were tombstoned, not physically removed.
        final rawVehicle = await (db.select(
          db.vehicles,
        )..where((v) => v.id.equals(vehicleId))).getSingle();
        final rawRecord = await (db.select(
          db.serviceRecords,
        )..where((r) => r.id.equals(recordId))).getSingle();
        final rawRule = await (db.select(
          db.reminderRules,
        )..where((r) => r.id.equals(ruleId))).getSingle();

        expect(rawVehicle.deletedAt, isNotNull);
        expect(rawRecord.deletedAt, isNotNull);
        expect(rawRule.deletedAt, isNotNull);
      },
    );

    test('leaves other vehicles and their children untouched', () async {
      final doomedId = await vehicles.createVehicle(
        nickname: 'Old Truck',
        odometerUnit: 'km',
      );
      final keeperId = await vehicles.createVehicle(
        nickname: 'Blue Civic',
        odometerUnit: 'km',
      );

      final doomedRecord = await records.createRecord(
        vehicleId: doomedId,
        performedAt: DateTime(2026, 1, 10),
        type: ServiceType.brakes,
      );
      final keeperRecord = await records.createRecord(
        vehicleId: keeperId,
        performedAt: DateTime(2026, 1, 11),
        type: ServiceType.brakes,
      );
      final keeperRule = await rules.createRule(
        vehicleId: keeperId,
        type: ServiceType.inspection,
        intervalMonths: 12,
      );

      await vehicles.softDeleteVehicle(doomedId);

      expect(await records.getRecord(doomedRecord), isNull);
      expect(await vehicles.getVehicle(keeperId), isNotNull);
      expect(await records.getRecord(keeperRecord), isNotNull);
      expect(await rules.getRule(keeperRule), isNotNull);
    });

    test(
      'preserves the original tombstone on already-deleted children',
      () async {
        final vehicleId = await vehicles.createVehicle(
          nickname: 'Blue Civic',
          odometerUnit: 'km',
        );
        final recordId = await records.createRecord(
          vehicleId: vehicleId,
          performedAt: DateTime(2026, 1, 10),
          type: ServiceType.airFilter,
        );

        await records.softDeleteRecord(recordId);
        final firstTombstone = await (db.select(
          db.serviceRecords,
        )..where((r) => r.id.equals(recordId))).getSingle();

        await vehicles.softDeleteVehicle(vehicleId);
        final afterCascade = await (db.select(
          db.serviceRecords,
        )..where((r) => r.id.equals(recordId))).getSingle();

        expect(afterCascade.deletedAt, firstTombstone.deletedAt);
      },
    );

    test(
      'soft-deleted vehicles stop counting against the free-tier gate',
      () async {
        final firstId = await vehicles.createVehicle(
          nickname: 'Blue Civic',
          odometerUnit: 'km',
        );
        await vehicles.createVehicle(nickname: 'Old Truck', odometerUnit: 'km');
        expect(await vehicles.countActiveVehicles(), 2);

        await vehicles.softDeleteVehicle(firstId);

        expect(await vehicles.countActiveVehicles(), 1);
      },
    );

    test('watchAllVehicles excludes soft-deleted vehicles', () async {
      final firstId = await vehicles.createVehicle(
        nickname: 'Blue Civic',
        odometerUnit: 'km',
      );
      await vehicles.createVehicle(nickname: 'Old Truck', odometerUnit: 'km');

      await vehicles.softDeleteVehicle(firstId);

      final visible = await vehicles.watchAllVehicles().first;
      expect(visible.map((v) => v.nickname), ['Old Truck']);
    });
  });

  group('updateOdometer', () {
    test('records the reading and stamps odometerUpdatedAt', () async {
      final id = await vehicles.createVehicle(
        nickname: 'Blue Civic',
        odometerUnit: 'km',
      );
      expect((await vehicles.getVehicle(id))!.odometerUpdatedAt, isNull);

      await vehicles.updateOdometer(id, 12000);

      final updated = await vehicles.getVehicle(id);
      expect(updated!.odometer, 12000);
      expect(updated.odometerUpdatedAt, isNotNull);
    });
  });
}
