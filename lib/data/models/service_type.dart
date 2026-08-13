/// Service categories used by both service records and reminder rules.
///
/// Persisted by [name] (a string), never by index — index-based storage breaks
/// as soon as the enum is reordered.
enum ServiceType {
  oilChange('Oil change'),
  tireRotation('Tire rotation'),
  tireChange('Tire change'),
  brakes('Brakes'),
  airFilter('Air filter'),
  batteryCheck('Battery'),
  inspection('Inspection / MOT'),
  insurance('Insurance renewal'),
  generalService('General service'),
  custom('Custom');

  const ServiceType(this.label);

  /// User-facing display label.
  final String label;

  /// Resolves a stored string back to a [ServiceType].
  ///
  /// Falls back to [ServiceType.custom] for unknown values so that rows written
  /// by a newer app version don't crash an older one.
  static ServiceType fromName(String name) {
    for (final type in ServiceType.values) {
      if (type.name == name) {
        return type;
      }
    }
    return ServiceType.custom;
  }
}
