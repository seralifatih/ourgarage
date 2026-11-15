import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/local/database.dart';
import '../../data/repositories/database_holder.dart';
import 'export_labels.dart';
import 'records_csv.dart';
import 'service_history_pdf.dart';

/// Hands a finished export file to the system share sheet.
///
/// An interface so widget tests can capture the file instead of invoking the
/// platform channel.
abstract class ExportSharer {
  Future<void> shareFile(File file, {required String subject, Rect? origin});
}

class SharePlusExportSharer implements ExportSharer {
  const SharePlusExportSharer();

  @override
  Future<void> shareFile(File file, {required String subject, Rect? origin}) {
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: subject,
        // Required on iPad, where the share sheet is a popover anchored to
        // the control that opened it; ignored on iPhone.
        sharePositionOrigin: origin,
      ),
    );
  }
}

final exportSharerProvider = Provider<ExportSharer>(
  (ref) => const SharePlusExportSharer(),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(
    db: DatabaseHolder.instance,
    sharer: ref.watch(exportSharerProvider),
  ),
);

/// Builds export files from the local database and shares them.
///
/// Reads the local database directly: in a household, it already holds every
/// shared vehicle and record, so the export covers the whole garage the user
/// can see. Soft-deleted rows are excluded by the DAOs.
class ExportService {
  ExportService({
    required this.db,
    required this.sharer,
    Future<Directory> Function()? outputDir,
    Future<PdfFonts> Function()? loadFonts,
    DateTime Function()? clock,
  }) : _outputDir = outputDir ?? getTemporaryDirectory,
       _loadFonts = loadFonts ?? _bundledFonts,
       _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final ExportSharer sharer;
  final Future<Directory> Function() _outputDir;
  final Future<PdfFonts> Function() _loadFonts;
  final DateTime Function() _clock;

  static Future<PdfFonts> _bundledFonts() async => PdfFonts(
    regular: await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    medium: await rootBundle.load('assets/fonts/Roboto-Medium.ttf'),
  );

  Future<List<Vehicle>> vehicles() => db.vehicleDao.getAllVehicles();

  /// Writes the all-vehicles CSV and opens the share sheet. Returns the file.
  Future<File> shareRecordsCsv({Rect? origin}) async {
    final vehicles = await db.vehicleDao.getAllVehicles();
    final records = await db.serviceRecordDao.getAllRecords();
    final csv = buildRecordsCsv(vehicles, records);

    final file = await _write(
      'ourgarage-records-${_stamp()}.csv',
      utf8.encode(csv),
    );
    await sharer.shareFile(
      file,
      subject: 'OurGarage service records',
      origin: origin,
    );
    return file;
  }

  /// Writes one vehicle's PDF service history and opens the share sheet.
  Future<File> shareServiceHistoryPdf(Vehicle vehicle, {Rect? origin}) async {
    final records = (await db.serviceRecordDao.getAllRecords())
        .where((r) => r.vehicleId == vehicle.id)
        .toList();
    final bytes = await buildServiceHistoryPdf(
      vehicle: vehicle,
      records: records,
      fonts: await _loadFonts(),
      generatedAt: _clock(),
    );

    final file = await _write(
      'service-history-${fileSlug(vehicle.nickname)}-${_stamp()}.pdf',
      bytes,
    );
    await sharer.shareFile(
      file,
      subject: 'Service history: ${vehicle.nickname}',
      origin: origin,
    );
    return file;
  }

  String _stamp() => DateFormat('yyyy-MM-dd').format(_clock());

  /// Writes into a dedicated `exports` subfolder of the temp directory,
  /// replacing anything from a previous export, so old files containing the
  /// user's history don't pile up.
  Future<File> _write(String name, List<int> bytes) async {
    final dir = Directory(p.join((await _outputDir()).path, 'exports'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
