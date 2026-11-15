import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/local/database.dart';
import '../vehicles/widgets/odometer_format.dart';
import 'export_labels.dart';

/// The two embedded font files, loaded by the caller (from the asset bundle in
/// the app, from disk in tests) so this file stays free of Flutter services.
class PdfFonts {
  const PdfFonts({required this.regular, required this.medium});

  final ByteData regular;
  final ByteData medium;
}

/// A one-vehicle service history, meant to be handed to a buyer.
///
/// Oldest service first, so it reads as the car's life story; a summary block
/// up top (vehicle, current odometer, number of services, date range) so the
/// first page answers "was this car looked after?" at a glance. Costs are
/// totalled per currency, since records can carry different currency codes.
///
/// [generatedAt] is a parameter, not `DateTime.now()`, so output is
/// deterministic under test.
Future<Uint8List> buildServiceHistoryPdf({
  required Vehicle vehicle,
  required List<ServiceRecord> records,
  required PdfFonts fonts,
  required DateTime generatedAt,
}) async {
  final regular = pw.Font.ttf(fonts.regular);
  final medium = pw.Font.ttf(fonts.medium);
  final theme = pw.ThemeData.withFont(base: regular, bold: medium);

  final rows = [...records]
    ..sort((a, b) => a.performedAt.compareTo(b.performedAt));
  final date = DateFormat('d MMM yyyy');
  final unit = vehicle.odometerUnit;
  final description = describeVehicle(vehicle);

  const ink = PdfColor.fromInt(0xFF16201F);
  const muted = PdfColor.fromInt(0xFF5B6664);
  const accent = PdfColor.fromInt(0xFF0F9C8E);
  const rule = PdfColor.fromInt(0xFFD5DEDC);
  const fill = PdfColor.fromInt(0xFFEEF6F4);

  final doc = pw.Document(
    title: 'Service history: ${vehicle.nickname}',
    author: 'OurGarage',
    creator: 'OurGarage',
    theme: theme,
  );

  pw.Widget fact(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(right: 24, bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: muted)),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 11, font: medium, color: ink),
        ),
      ],
    ),
  );

  final facts = <pw.Widget>[
    if (description != null) fact('Vehicle', description),
    if ((vehicle.plate ?? '').trim().isNotEmpty)
      fact('Plate', vehicle.plate!.trim()),
    fact('Current odometer', '${formatOdometer(vehicle.odometer)} $unit'),
    fact('Services recorded', '${rows.length}'),
    if (rows.isNotEmpty)
      fact(
        'Records span',
        '${date.format(rows.first.performedAt)} – ${date.format(rows.last.performedAt)}',
      ),
  ];

  final totals = <String, double>{};
  for (final r in rows) {
    if (r.cost == null) continue;
    final code = (r.currency ?? '').trim();
    totals[code] = (totals[code] ?? 0) + r.cost!;
  }
  final money = NumberFormat('#,##0.00');
  String cost(double v, String? code) {
    final c = (code ?? '').trim();
    return c.isEmpty ? money.format(v) : '${money.format(v)} $c';
  }

  doc.addPage(
    pw.MultiPage(
      // The default (20) would throw for a long-lived car with a few hundred
      // services; a generous cap still stops a runaway layout.
      maxPages: 500,
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Exported from OurGarage on ${date.format(generatedAt)}',
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
        ],
      ),
      build: (context) => [
        pw.Container(height: 4, color: accent),
        pw.SizedBox(height: 14),
        pw.Text(
          'Service history',
          style: const pw.TextStyle(fontSize: 10, color: accent),
        ),
        pw.Text(
          vehicle.nickname,
          style: pw.TextStyle(fontSize: 22, font: medium, color: ink),
        ),
        pw.SizedBox(height: 12),
        pw.Wrap(children: facts),
        pw.SizedBox(height: 12),
        if (rows.isEmpty)
          pw.Text(
            'No services have been recorded for this vehicle yet.',
            style: const pw.TextStyle(fontSize: 11, color: muted),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Odometer', 'Service', 'Notes', 'Cost'],
            data: [
              for (final r in rows)
                [
                  date.format(r.performedAt),
                  r.odometer == null
                      ? ''
                      : '${formatOdometer(r.odometer!)} $unit',
                  serviceLabel(r),
                  _clipNote(r.notes),
                  r.cost == null ? '' : cost(r.cost!, r.currency),
                ],
            ],
            columnWidths: const {
              0: pw.FixedColumnWidth(72),
              1: pw.FixedColumnWidth(78),
              2: pw.FixedColumnWidth(100),
              3: pw.FlexColumnWidth(),
              4: pw.FixedColumnWidth(70),
            },
            headerStyle: pw.TextStyle(fontSize: 9, font: medium, color: ink),
            headerDecoration: const pw.BoxDecoration(color: fill),
            cellStyle: const pw.TextStyle(fontSize: 9, color: ink),
            cellAlignments: const {4: pw.Alignment.centerRight},
            headerAlignment: pw.Alignment.centerLeft,
            headerAlignments: const {4: pw.Alignment.centerRight},
            cellAlignment: pw.Alignment.topLeft,
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: rule, width: 0.5),
              bottom: pw.BorderSide(color: rule, width: 0.5),
            ),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 5,
            ),
          ),
        if (totals.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total recorded: ${totals.entries.map((e) => cost(e.value, e.key)).join(' + ')}',
              style: pw.TextStyle(fontSize: 10, font: medium, color: ink),
            ),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

/// Longest note printed in the PDF. A table row can't break across pages, so
/// one note taller than a page would make the whole export fail; the CSV
/// keeps the full text.
const maxPdfNoteLength = 500;

String _clipNote(String? note) {
  final text = (note ?? '').trim();
  if (text.length <= maxPdfNoteLength) return text;
  return '${text.substring(0, maxPdfNoteLength).trimRight()}…';
}
