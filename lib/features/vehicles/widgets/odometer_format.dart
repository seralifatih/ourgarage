import '../../../data/local/database.dart';

/// Groups thousands so long readings stay scannable: 128500 -> "128,500".
String formatOdometer(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value.isNegative ? '-' : '');

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }

  return buffer.toString();
}

/// "Honda Civic 2019", dropping whichever parts are missing.
///
/// Returns null when none of make, model or year is set, so callers can omit
/// the line entirely rather than rendering an empty one.
String? describeVehicle(Vehicle vehicle) {
  final parts = [
    vehicle.make,
    vehicle.model,
    vehicle.year?.toString(),
  ].whereType<String>().where((part) => part.trim().isNotEmpty);

  return parts.isEmpty ? null : parts.join(' ');
}
