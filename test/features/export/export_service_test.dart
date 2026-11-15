import 'dart:io';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/service_record_repository.dart';
import 'package:ourgarage/data/repositories/vehicle_repository.dart';
import 'package:ourgarage/features/export/export_service.dart';

import 'export_test_data.dart';

class FakeSharer implements ExportSharer {
  final shared = <({File file, String subject, Rect? origin})>[];

  @override
  Future<void> shareFile(
    File file, {
    required String subject,
    Rect? origin,
  }) async {
    shared.add((file: file, subject: subject, origin: origin));
  }
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FakeSharer sharer;
  late ExportService service;
  late VehicleRepository vehicles;
  late ServiceRecordRepository records;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('export_test');
    sharer = FakeSharer();
    vehicles = VehicleRepository(db.vehicleDao);
    records = ServiceRecordRepository(db.serviceRecordDao);
    service = ExportService(
      db: db,
      sharer: sharer,
      outputDir: () async => tmp,
      loadFonts: fontsFromDisk,
      clock: () => DateTime(2026, 11, 15, 9),
    );
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('CSV covers every live vehicle and record and is shared', () async {
    final civic = await vehicles.createVehicle(
      nickname: 'Civic',
      odometerUnit: 'mi',
      odometer: 50000,
    );
    final golf = await vehicles.createVehicle(
      nickname: 'Golf',
      odometerUnit: 'km',
      odometer: 90000,
    );
    await records.createRecord(
      vehicleId: civic,
      performedAt: DateTime(2026, 3, 14),
      type: ServiceType.oilChange,
      odometer: 48210,
    );
    await records.createRecord(
      vehicleId: golf,
      performedAt: DateTime(2026, 4, 1),
      type: ServiceType.tireRotation,
      odometer: 88000,
    );
    final deleted = await records.createRecord(
      vehicleId: golf,
      performedAt: DateTime(2026, 5, 1),
      type: ServiceType.brakes,
    );
    await records.softDeleteRecord(deleted);

    final file = await service.shareRecordsCsv(
      origin: const Rect.fromLTWH(1, 2, 3, 4),
    );

    expect(file.path, endsWith('ourgarage-records-2026-11-15.csv'));
    final csv = await file.readAsString();
    expect(csv, contains('Civic'));
    expect(csv, contains('2026-03-14,Oil change,48210,mi'));
    expect(csv, contains('2026-04-01,Tire rotation,88000,km'));
    expect(csv, isNot(contains('Brakes')));

    expect(sharer.shared, hasLength(1));
    expect(sharer.shared.single.file.path, file.path);
    expect(sharer.shared.single.subject, 'OurGarage service records');
    expect(sharer.shared.single.origin, const Rect.fromLTWH(1, 2, 3, 4));
  });

  test('PDF includes only the chosen vehicle and is named after it', () async {
    final civic = await vehicles.createVehicle(
      nickname: "Mum's Civic",
      odometerUnit: 'mi',
      odometer: 50000,
    );
    await records.createRecord(
      vehicleId: civic,
      performedAt: DateTime(2026, 3, 14),
      type: ServiceType.oilChange,
    );
    final vehicle = (await db.vehicleDao.getVehicle(civic))!;

    final file = await service.shareServiceHistoryPdf(vehicle);

    expect(file.path, endsWith('service-history-mums-civic-2026-11-15.pdf'));
    final bytes = await file.readAsBytes();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(sharer.shared.single.subject, "Service history: Mum's Civic");
  });

  test('a new export replaces the previous export files', () async {
    await vehicles.createVehicle(nickname: 'Civic', odometerUnit: 'mi');
    final first = await service.shareRecordsCsv();
    final vehicle = (await service.vehicles()).single;
    final second = await service.shareServiceHistoryPdf(vehicle);

    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
    expect(second.parent.listSync(), hasLength(1));
  });
}
