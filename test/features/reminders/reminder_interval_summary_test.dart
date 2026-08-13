import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/features/reminders/reminder_interval_summary.dart';

void main() {
  test('months only', () {
    expect(
      reminderIntervalSummary(
        intervalMonths: 6,
        intervalDistance: null,
        distanceUnit: 'mi',
      ),
      'Every 6 months',
    );
  });

  test('distance only, grouped with a thousands separator', () {
    expect(
      reminderIntervalSummary(
        intervalMonths: null,
        intervalDistance: 5000,
        distanceUnit: 'mi',
      ),
      'Every 5,000 mi',
    );
  });

  test('both intervals joined with "or"', () {
    expect(
      reminderIntervalSummary(
        intervalMonths: 6,
        intervalDistance: 5000,
        distanceUnit: 'mi',
      ),
      'Every 6 months or 5,000 mi',
    );
  });

  test('uses the vehicle unit, not a hardcoded one', () {
    expect(
      reminderIntervalSummary(
        intervalMonths: null,
        intervalDistance: 8000,
        distanceUnit: 'km',
      ),
      'Every 8,000 km',
    );
  });

  test('small distances are not grouped', () {
    expect(
      reminderIntervalSummary(
        intervalMonths: null,
        intervalDistance: 500,
        distanceUnit: 'km',
      ),
      'Every 500 km',
    );
  });
}
