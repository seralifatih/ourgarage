import '../../data/local/database.dart';
import '../../data/models/service_type.dart';

/// The user-facing name of a record's service: the custom label for custom
/// records, the type's label otherwise. Matches what the history list shows.
String serviceLabel(ServiceRecord record) {
  final type = ServiceType.fromName(record.type);
  if (type != ServiceType.custom) return type.label;
  final custom = record.customTypeLabel?.trim();
  return custom == null || custom.isEmpty ? type.label : custom;
}

/// A filesystem-safe slug of a vehicle name for export file names:
/// "Mum's Civic!" -> "mums-civic". Falls back to "vehicle" when nothing
/// usable is left (e.g. a nickname written entirely in emoji).
String fileSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return 'vehicle';
  return slug.length > 40
      ? slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '')
      : slug;
}
