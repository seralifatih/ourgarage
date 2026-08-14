import 'package:drift/drift.dart';

import '../local/database.dart';

/// Which table a queued change or a pulled row belongs to.
enum SyncEntity {
  vehicle('vehicle', 'vehicles'),
  serviceRecord('serviceRecord', 'service_records'),
  reminderRule('reminderRule', 'reminder_rules');

  const SyncEntity(this.name, this.remoteTable);

  /// Stored in `SyncQueue.entityType`. Persisted by name, never by index.
  final String name;

  /// The Postgres table this maps to.
  final String remoteTable;

  static SyncEntity fromName(String name) =>
      values.firstWhere((e) => e.name == name);
}

/// What a queued change does. Both push as an upsert; see [SyncQueue].
enum SyncOperation {
  upsert,
  delete;

  static SyncOperation fromName(String name) =>
      values.firstWhere((o) => o.name == name);
}

/// Converts between Drift rows and the remote column shape.
///
/// The single place that knows the mapping, shared by the one-time household
/// migration and the ongoing sync — two code paths writing the same tables in
/// two different shapes is a bug waiting to happen.
///
/// Remote columns are snake_case; timestamps travel as ISO-8601 UTC, which is
/// what Postgres `timestamptz` expects and what sorts correctly as a string.
class SyncPayloads {
  const SyncPayloads._();

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

  static DateTime? _dateTime(Object? value) {
    if (value == null) return null;
    // Parsed to UTC and kept there: comparisons between local and remote
    // `updatedAt` decide who wins under last-write-wins, and comparing a local
    // wall clock against a UTC instant would resolve conflicts wrongly.
    return DateTime.parse(value as String).toUtc();
  }

  static int? _int(Object? value) => (value as num?)?.toInt();

  // --- vehicles ------------------------------------------------------------

  /// [householdId] defaults to the one already stamped on the row by the
  /// one-time migration; the migration itself passes it explicitly, because at
  /// that point the local rows do not carry it yet.
  static Map<String, dynamic> vehicleToRemote(
    Vehicle v, {
    String? householdId,
    String? userId,
  }) {
    return {
      'id': v.id,
      'household_id': householdId ?? v.householdId,
      'created_by': ?userId,
      'nickname': v.nickname,
      'make': v.make,
      'model': v.model,
      'year': v.year,
      'plate': v.plate,
      'odometer': v.odometer,
      'odometer_unit': v.odometerUnit,
      'odometer_updated_at': _iso(v.odometerUpdatedAt),
      'created_at': _iso(v.createdAt),
      'updated_at': _iso(v.updatedAt),
      'deleted_at': _iso(v.deletedAt),
    };
  }

  static VehiclesCompanion vehicleFromRemote(Map<String, dynamic> row) {
    return VehiclesCompanion(
      id: Value(row['id'] as String),
      nickname: Value(row['nickname'] as String),
      make: Value(row['make'] as String?),
      model: Value(row['model'] as String?),
      year: Value(_int(row['year'])),
      plate: Value(row['plate'] as String?),
      odometer: Value(_int(row['odometer']) ?? 0),
      odometerUnit: Value(row['odometer_unit'] as String),
      odometerUpdatedAt: Value(_dateTime(row['odometer_updated_at'])),
      householdId: Value(row['household_id'] as String?),
      createdAt: Value(_dateTime(row['created_at'])!),
      updatedAt: Value(_dateTime(row['updated_at'])!),
      deletedAt: Value(_dateTime(row['deleted_at'])),
    );
  }

  // --- service_records -----------------------------------------------------

  static Map<String, dynamic> serviceRecordToRemote(
    ServiceRecord r, {
    String? userId,
  }) {
    return {
      'id': r.id,
      'vehicle_id': r.vehicleId,
      'created_by': ?userId,
      'performed_at': _iso(r.performedAt),
      'odometer': r.odometer,
      'type': r.type,
      'custom_type_label': r.customTypeLabel,
      'notes': r.notes,
      'cost': r.cost,
      'currency': r.currency,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'deleted_at': _iso(r.deletedAt),
    };
  }

  static ServiceRecordsCompanion serviceRecordFromRemote(
    Map<String, dynamic> row,
  ) {
    return ServiceRecordsCompanion(
      id: Value(row['id'] as String),
      vehicleId: Value(row['vehicle_id'] as String),
      performedAt: Value(_dateTime(row['performed_at'])!),
      odometer: Value(_int(row['odometer'])),
      type: Value(row['type'] as String),
      customTypeLabel: Value(row['custom_type_label'] as String?),
      notes: Value(row['notes'] as String?),
      cost: Value((row['cost'] as num?)?.toDouble()),
      currency: Value(row['currency'] as String?),
      createdAt: Value(_dateTime(row['created_at'])!),
      updatedAt: Value(_dateTime(row['updated_at'])!),
      deletedAt: Value(_dateTime(row['deleted_at'])),
    );
  }

  // --- reminder_rules ------------------------------------------------------

  static Map<String, dynamic> reminderRuleToRemote(
    ReminderRule r, {
    String? userId,
  }) {
    return {
      'id': r.id,
      'vehicle_id': r.vehicleId,
      'created_by': ?userId,
      'type': r.type,
      'custom_type_label': r.customTypeLabel,
      'interval_months': r.intervalMonths,
      'interval_distance': r.intervalDistance,
      'last_done_at': _iso(r.lastDoneAt),
      'last_done_odometer': r.lastDoneOdometer,
      'is_active': r.isActive,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'deleted_at': _iso(r.deletedAt),
    };
  }

  static ReminderRulesCompanion reminderRuleFromRemote(
    Map<String, dynamic> row,
  ) {
    return ReminderRulesCompanion(
      id: Value(row['id'] as String),
      vehicleId: Value(row['vehicle_id'] as String),
      type: Value(row['type'] as String),
      customTypeLabel: Value(row['custom_type_label'] as String?),
      intervalMonths: Value(_int(row['interval_months'])),
      intervalDistance: Value(_int(row['interval_distance'])),
      lastDoneAt: Value(_dateTime(row['last_done_at'])),
      lastDoneOdometer: Value(_int(row['last_done_odometer'])),
      isActive: Value(row['is_active'] as bool? ?? true),
      createdAt: Value(_dateTime(row['created_at'])!),
      updatedAt: Value(_dateTime(row['updated_at'])!),
      deletedAt: Value(_dateTime(row['deleted_at'])),
    );
  }

  /// The `updated_at` of a remote row, for last-write-wins comparisons.
  static DateTime remoteUpdatedAt(Map<String, dynamic> row) =>
      _dateTime(row['updated_at'])!;
}
