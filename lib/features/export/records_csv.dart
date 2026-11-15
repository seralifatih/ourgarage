import 'package:intl/intl.dart';

import '../../data/local/database.dart';
import 'export_labels.dart';

/// Column headers of the records CSV, in order.
const recordsCsvHeader = [
  'Vehicle',
  'Make',
  'Model',
  'Year',
  'Plate',
  'Date',
  'Service',
  'Odometer',
  'Odometer unit',
  'Cost',
  'Currency',
  'Notes',
];

/// Every live service record across [vehicles] as one CSV document.
///
/// - One row per record, grouped by vehicle (in the order given) and oldest
///   first within each vehicle, so the file reads as a history.
/// - Dates are ISO `yyyy-MM-dd`, which every spreadsheet parses regardless of
///   locale. Odometer and cost are plain numbers, unformatted, so they sort
///   and sum.
/// - RFC 4180 quoting and CRLF line endings, with a UTF-8 byte-order mark so
///   Excel opens non-ASCII notes correctly instead of guessing a code page.
/// - Records whose vehicle isn't in [vehicles] (deleted vehicles) are skipped.
String buildRecordsCsv(List<Vehicle> vehicles, List<ServiceRecord> records) {
  final byVehicle = <String, List<ServiceRecord>>{};
  for (final record in records) {
    byVehicle.putIfAbsent(record.vehicleId, () => []).add(record);
  }

  // Byte-order mark, as a code point rather than an invisible literal.
  final buffer = StringBuffer(String.fromCharCode(0xFEFF))
    ..write(_row(recordsCsvHeader));
  final date = DateFormat('yyyy-MM-dd');

  for (final vehicle in vehicles) {
    final rows = [...?byVehicle[vehicle.id]]
      ..sort((a, b) => a.performedAt.compareTo(b.performedAt));
    for (final record in rows) {
      buffer.write(
        _row([
          _text(vehicle.nickname),
          _text(vehicle.make),
          _text(vehicle.model),
          vehicle.year?.toString() ?? '',
          _text(vehicle.plate),
          date.format(record.performedAt),
          _text(serviceLabel(record)),
          record.odometer?.toString() ?? '',
          record.odometer == null ? '' : vehicle.odometerUnit,
          record.cost == null ? '' : formatCsvNumber(record.cost!),
          _text(record.cost == null ? null : record.currency),
          _text(record.notes),
        ]),
      );
    }
  }
  return buffer.toString();
}

/// A cost as a plain decimal: no grouping, at most two decimals, no trailing
/// zeros (`89.4`, `120`), so spreadsheets read it as a number in any locale
/// that uses `.` as the decimal mark.
String formatCsvNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;
}

/// User-entered text, neutralised against spreadsheet formula injection: a
/// cell starting with `=`, `+`, `-`, `@`, tab or CR would be evaluated as a
/// formula by Excel and Sheets, so it gets a leading apostrophe, which both
/// treat as "this is text". Only applied to free text, never to the numeric
/// columns, where a leading `-` is legitimate.
String _text(String? value) {
  if (value == null) return '';
  if (value.isNotEmpty && '=+-@\t\r'.contains(value[0])) return "'$value";
  return value;
}

String _row(List<String> cells) => '${cells.map(_escape).join(',')}\r\n';

String _escape(String cell) {
  final needsQuotes = cell.contains(RegExp('[",\r\n]'));
  if (!needsQuotes) return cell;
  return '"${cell.replaceAll('"', '""')}"';
}
