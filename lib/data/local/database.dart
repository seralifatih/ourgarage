import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/reminder_rule_dao.dart';
import 'daos/service_record_dao.dart';
import 'daos/vehicle_dao.dart';

part 'database.g.dart';

/// Vehicles owned or tracked by the user.
///
/// [householdId] is null while a vehicle is local-only; it gets populated once
/// household sharing lands. [deletedAt] is a soft delete so that deletions can
/// be replicated during sync rather than silently vanishing.
class Vehicles extends Table {
  TextColumn get id => text()();
  TextColumn get nickname => text()();
  TextColumn get make => text().nullable()();
  TextColumn get model => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get plate => text().nullable()();
  IntColumn get odometer => integer().withDefault(const Constant(0))();

  /// Either `km` or `mi`.
  TextColumn get odometerUnit => text()();
  DateTimeColumn get odometerUpdatedAt => dateTime().nullable()();
  TextColumn get householdId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A single piece of work performed on a vehicle.
///
/// [type] holds a [ServiceType] name; [customTypeLabel] carries the
/// user-supplied label when the type is `custom`.
@TableIndex(
  name: 'service_records_vehicle_performed_at',
  columns: {
    #vehicleId,
    IndexedColumn(#performedAt, orderBy: OrderingMode.desc),
  },
)
class ServiceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId =>
      text().references(Vehicles, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get performedAt => dateTime()();
  IntColumn get odometer => integer().nullable()();
  TextColumn get type => text()();
  TextColumn get customTypeLabel => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get cost => real().nullable()();
  TextColumn get currency => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A recurring maintenance rule that drives reminders.
///
/// At least one of [intervalMonths] / [intervalDistance] must be non-null. That
/// invariant is enforced in the repository layer, not by the schema, so the
/// error surfaces as a domain failure rather than a raw sqlite constraint.
/// [intervalDistance] is expressed in the owning vehicle's `odometerUnit`.
@TableIndex(
  name: 'reminder_rules_vehicle_active',
  columns: {#vehicleId, #isActive},
)
class ReminderRules extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId =>
      text().references(Vehicles, #id, onDelete: KeyAction.restrict)();
  TextColumn get type => text()();
  TextColumn get customTypeLabel => text().nullable()();
  IntColumn get intervalMonths => integer().nullable()();
  IntColumn get intervalDistance => integer().nullable()();
  DateTimeColumn get lastDoneAt => dateTime().nullable()();
  IntColumn get lastDoneOdometer => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [Vehicles, ServiceRecords, ReminderRules],
  daos: [VehicleDao, ServiceRecordDao, ReminderRuleDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'ourgarage'));

  /// Visible for testing — lets tests supply an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
