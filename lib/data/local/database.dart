import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/household_entitlement_dao.dart';
import 'daos/reminder_rule_dao.dart';
import 'daos/service_record_dao.dart';
import 'daos/sync_queue_dao.dart';
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

/// Cached household premium entitlement — **not** a security boundary.
///
/// One person in a household pays and everyone in it gets premium. Whether
/// that is true for the current user is decided **server-side**: Supabase RLS
/// gates the data, and a RevenueCat webhook writes the household's premium
/// flag when a member purchases or lapses. Phase 5 fills this table from that
/// source.
///
/// This local copy exists purely so the UI can answer "is this user premium?"
/// synchronously, without blocking a paywall or a gated field on a network
/// round trip. It is trivially editable by anyone with access to the device's
/// sqlite file, so it must never be the only thing standing between a user and
/// a paid feature — every server-side read has to re-check entitlement
/// independently. Treat a `true` here as "show the premium UI", never as
/// "this user is authorised".
///
/// Single-row by construction: [id] is always [HouseholdEntitlements.singleton]
/// so writes upsert over one another rather than accumulating.
class HouseholdEntitlements extends Table {
  /// Always [singleton]; see the class doc.
  IntColumn get id => integer()();

  /// Whether the household this user belongs to has premium.
  BoolColumn get isPremium => boolean().withDefault(const Constant(false))();

  /// The household the flag came from. Null while the user is in no household,
  /// which is every user until Phase 5.
  TextColumn get householdId => text().nullable()();

  /// When this cache was last refreshed from the server. Null means never.
  DateTimeColumn get cachedAt => dateTime().nullable()();

  /// The only primary key value this table ever holds.
  static const int singleton = 0;

  @override
  Set<Column> get primaryKey => {id};
}

/// Local writes that still have to reach the household's cloud copy.
///
/// The queue is what makes the app usable with no network at all. A service
/// record gets logged in a garage or a parking lot, where signal is worst, so
/// the write lands in sqlite and a row lands here; the two happen in the same
/// transaction, which is the only way to guarantee no change is silently lost.
///
/// Coalesced per entity by the unique index below: ten edits to one vehicle
/// before the next sync leave one row carrying the newest snapshot, not ten.
/// [payload] is that snapshot, already in the remote column shape.
@TableIndex(
  name: 'sync_queue_entity',
  columns: {#entityType, #entityId},
  unique: true,
)
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// `upsert` or `delete`. Both push as an upsert — a delete is a soft delete
  /// carrying `deleted_at`, so it travels as an ordinary row change and cannot
  /// be resurrected by a peer that never heard about it.
  TextColumn get operation => text()();

  /// The row as it will be sent, JSON-encoded.
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime()();

  /// Failed push attempts, for backoff and for spotting a poisoned row.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row bookkeeping for the pull side.
class SyncStates extends Table {
  IntColumn get id => integer()();

  /// High-water mark: rows changed remotely after this have not been seen.
  /// Null means nothing has ever been pulled.
  DateTimeColumn get lastPulledAt => dateTime().nullable()();

  static const int singleton = 0;

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Vehicles,
    ServiceRecords,
    ReminderRules,
    HouseholdEntitlements,
    SyncQueue,
    SyncStates,
  ],
  daos: [
    VehicleDao,
    ServiceRecordDao,
    ReminderRuleDao,
    HouseholdEntitlementDao,
    SyncQueueDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'ourgarage'));

  /// Visible for testing — lets tests supply an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // v2 added the household entitlement cache. Existing installs have every
      // other table already, so only the new one is created — `createAll`
      // would throw on the tables that are already there.
      if (from < 2) {
        await m.createTable(householdEntitlements);
      }
      if (from < 3) {
        // v3 added two-way sync. Existing rows are not back-filled into the
        // queue: an install upgrading to sync has never been in a household,
        // so there is nothing to push until it joins one — at which point the
        // one-time migration uploads everything in bulk.
        await m.createTable(syncQueue);
        await m.createTable(syncStates);
        await m.createIndex(syncQueueEntity);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
