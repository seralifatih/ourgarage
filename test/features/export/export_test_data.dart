import 'dart:io';
import 'dart:typed_data';

import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/features/export/service_history_pdf.dart';

/// Shared fixtures for the export tests.

Vehicle vehicle({
  String id = 'v1',
  String nickname = 'Blue Civic',
  String? make = 'Honda',
  String? model = 'Civic',
  int? year = 2019,
  String? plate = 'ABC 123',
  int odometer = 48210,
  String unit = 'mi',
}) {
  final t = DateTime(2026, 1, 1);
  return Vehicle(
    id: id,
    nickname: nickname,
    make: make,
    model: model,
    year: year,
    plate: plate,
    odometer: odometer,
    odometerUnit: unit,
    createdAt: t,
    updatedAt: t,
  );
}

ServiceRecord record({
  String id = 'r1',
  String vehicleId = 'v1',
  required DateTime performedAt,
  String type = 'oilChange',
  String? customTypeLabel,
  int? odometer,
  double? cost,
  String? currency,
  String? notes,
}) {
  return ServiceRecord(
    id: id,
    vehicleId: vehicleId,
    performedAt: performedAt,
    odometer: odometer,
    type: type,
    customTypeLabel: customTypeLabel,
    notes: notes,
    cost: cost,
    currency: currency,
    createdAt: performedAt,
    updatedAt: performedAt,
  );
}

/// The bundled fonts, read from disk (tests run from the project root).
Future<PdfFonts> fontsFromDisk() async {
  Future<ByteData> load(String name) async =>
      ByteData.sublistView(await File('assets/fonts/$name').readAsBytes());
  return PdfFonts(
    regular: await load('Roboto-Regular.ttf'),
    medium: await load('Roboto-Medium.ttf'),
  );
}
