import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/features/export/export_labels.dart';
import 'package:ourgarage/features/export/records_csv.dart';

import 'export_test_data.dart';

/// Splits the CSV body into lines, dropping the BOM and the trailing CRLF.
List<String> lines(String csv) {
  expect(csv.startsWith('﻿'), isTrue, reason: 'UTF-8 BOM for Excel');
  final body = csv.substring(1);
  expect(body.endsWith('\r\n'), isTrue);
  return body.substring(0, body.length - 2).split('\r\n');
}

void main() {
  test('header only when there are no records', () {
    final out = lines(buildRecordsCsv([vehicle()], []));
    expect(out, [recordsCsvHeader.join(',')]);
  });

  test('one row per record with ISO dates, raw numbers and the unit', () {
    final out = lines(
      buildRecordsCsv(
        [vehicle()],
        [
          record(
            performedAt: DateTime(2026, 3, 14),
            odometer: 48210,
            cost: 89.4,
            currency: 'USD',
            notes: '0W-20 synthetic',
          ),
        ],
      ),
    );
    expect(
      out[1],
      'Blue Civic,Honda,Civic,2019,ABC 123,2026-03-14,Oil change,48210,mi,'
      '89.4,USD,0W-20 synthetic',
    );
  });

  test('missing odometer and cost leave their unit and currency blank', () {
    final out = lines(
      buildRecordsCsv(
        [vehicle(make: null, model: null, year: null, plate: null)],
        [record(performedAt: DateTime(2026, 3, 14), currency: 'USD')],
      ),
    );
    expect(out[1], 'Blue Civic,,,,,2026-03-14,Oil change,,,,,');
  });

  test('groups by vehicle in the given order, oldest record first', () {
    final out = lines(
      buildRecordsCsv(
        [
          vehicle(id: 'b', nickname: 'Second'),
          vehicle(id: 'a', nickname: 'First'),
        ],
        [
          record(id: '1', vehicleId: 'a', performedAt: DateTime(2026, 5, 1)),
          record(id: '2', vehicleId: 'b', performedAt: DateTime(2026, 2, 1)),
          record(id: '3', vehicleId: 'a', performedAt: DateTime(2025, 1, 1)),
        ],
      ),
    );
    expect(out.skip(1).map((l) => l.split(',').take(6).join(',')).toList(), [
      'Second,Honda,Civic,2019,ABC 123,2026-02-01',
      'First,Honda,Civic,2019,ABC 123,2025-01-01',
      'First,Honda,Civic,2019,ABC 123,2026-05-01',
    ]);
  });

  test('skips records whose vehicle is not in the export', () {
    final out = lines(
      buildRecordsCsv(
        [vehicle()],
        [record(vehicleId: 'deleted', performedAt: DateTime(2026, 1, 1))],
      ),
    );
    expect(out, hasLength(1));
  });

  test('quotes commas, quotes and newlines per RFC 4180', () {
    final out = buildRecordsCsv(
      [vehicle(nickname: 'Mum\'s "Civic", red')],
      [record(performedAt: DateTime(2026, 1, 1), notes: 'Line one\nline two')],
    );
    expect(out, contains('"Mum\'s ""Civic"", red"'));
    expect(out, contains('"Line one\nline two"'));
  });

  test('neutralises formula injection in text cells only', () {
    final out = lines(
      buildRecordsCsv(
        [vehicle(nickname: '=HYPERLINK("x")')],
        [
          record(
            performedAt: DateTime(2026, 1, 1),
            notes: '+1 extra quart',
            customTypeLabel: '@work',
            type: 'custom',
          ),
        ],
      ),
    );
    expect(out[1], startsWith('"\'=HYPERLINK(""x"")"'));
    expect(out[1], contains(",'@work,"));
    expect(out[1], endsWith(",'+1 extra quart"));
  });

  test('custom records use their label, falling back to "Custom"', () {
    final out = lines(
      buildRecordsCsv(
        [vehicle()],
        [
          record(
            id: '1',
            performedAt: DateTime(2026, 1, 1),
            type: 'custom',
            customTypeLabel: 'Windshield replacement',
          ),
          record(
            id: '2',
            performedAt: DateTime(2026, 1, 2),
            type: 'custom',
            customTypeLabel: '  ',
          ),
        ],
      ),
    );
    expect(out[1], contains(',Windshield replacement,'));
    expect(out[2], contains(',Custom,'));
  });

  test('keeps non-ASCII text intact', () {
    final out = buildRecordsCsv(
      [vehicle(nickname: 'Şahin')],
      [record(performedAt: DateTime(2026, 1, 1), notes: 'Ölçüm tamam ✓')],
    );
    expect(out, contains('Şahin'));
    expect(out, contains('Ölçüm tamam ✓'));
  });

  group('formatCsvNumber', () {
    test('drops trailing zeros and rounds to cents', () {
      expect(formatCsvNumber(120), '120');
      expect(formatCsvNumber(89.40), '89.4');
      expect(formatCsvNumber(1234.567), '1234.57');
      expect(formatCsvNumber(0), '0');
    });
  });

  group('fileSlug', () {
    test('makes a safe, readable slug', () {
      expect(fileSlug("Mum's Civic!"), 'mums-civic');
      expect(fileSlug('  Blue   Civic  2019 '), 'blue-civic-2019');
      expect(fileSlug('🚗'), 'vehicle');
      expect(fileSlug('a' * 60), hasLength(40));
    });
  });
}
