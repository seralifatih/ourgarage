import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/features/export/service_history_pdf.dart';

import 'export_test_data.dart';

/// Counts page objects in the raw PDF bytes.
int pageCount(List<int> bytes) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length;

void main() {
  late PdfFonts fonts;

  setUpAll(() async {
    fonts = await fontsFromDisk();
  });

  test('produces a one-page PDF for a short history', () async {
    final bytes = await buildServiceHistoryPdf(
      vehicle: vehicle(),
      records: [
        record(
          performedAt: DateTime(2026, 3, 14),
          odometer: 48210,
          cost: 89.4,
          currency: 'USD',
        ),
      ],
      fonts: fonts,
      generatedAt: DateTime(2026, 11, 15),
    );

    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(pageCount(bytes), 1);
  });

  test('renders a vehicle with no records', () async {
    final bytes = await buildServiceHistoryPdf(
      vehicle: vehicle(make: null, model: null, year: null, plate: null),
      records: const [],
      fonts: fonts,
      generatedAt: DateTime(2026, 11, 15),
    );
    expect(pageCount(bytes), 1);
  });

  test('flows a long history onto more pages', () async {
    final records = [
      for (var i = 0; i < 80; i++)
        record(
          id: 'r$i',
          performedAt: DateTime(2018, 1, 1).add(Duration(days: 30 * i)),
          odometer: 10000 + i * 2500,
          cost: 50.0 + i,
          currency: i.isEven ? 'USD' : 'EUR',
          notes: i % 5 == 0 ? 'Long note ' * 20 : null,
        ),
    ];
    final bytes = await buildServiceHistoryPdf(
      vehicle: vehicle(),
      records: records,
      fonts: fonts,
      generatedAt: DateTime(2026, 11, 15),
    );
    expect(pageCount(bytes), greaterThan(1));
  });

  test('survives a note longer than a page and a very long history', () async {
    final records = [
      record(
        id: 'huge',
        performedAt: DateTime(2010, 1, 1),
        notes: 'x ' * 10000,
      ),
      for (var i = 0; i < 1500; i++)
        record(
          id: 'r$i',
          performedAt: DateTime(2010, 1, 2).add(Duration(days: 5 * i)),
          odometer: 1000 + i * 300,
        ),
    ];
    final bytes = await buildServiceHistoryPdf(
      vehicle: vehicle(),
      records: records,
      fonts: fonts,
      generatedAt: DateTime(2026, 11, 15),
    );
    expect(pageCount(bytes), greaterThan(20));
  });

  test('handles non-Latin text in names and notes', () async {
    final bytes = await buildServiceHistoryPdf(
      vehicle: vehicle(nickname: 'Şahin Doğan', plate: '34 ÇĞ 123'),
      records: [
        record(
          performedAt: DateTime(2026, 1, 1),
          type: 'custom',
          customTypeLabel: 'Замена масла',
          notes: 'Ölçüm tamam. Ελληνικά.',
        ),
      ],
      fonts: fonts,
      generatedAt: DateTime(2026, 11, 15),
    );
    expect(bytes, isNotEmpty);
  });
}
