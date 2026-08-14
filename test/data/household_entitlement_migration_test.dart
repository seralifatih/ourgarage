import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';

/// Guards the v1 → v2 upgrade that added the household entitlement cache.
///
/// Existing installs are on v1 and already have every other table, so the
/// upgrade must create only the new one. Getting this wrong doesn't fail
/// gracefully — it throws on open and bricks the app for anyone upgrading.
void main() {
  test(
    'upgrading a v1 database adds the cache and keeps existing data',
    () async {
      // A v1 database: the three original tables, no household entitlement, and
      // `user_version` left at 1 so drift runs onUpgrade rather than onCreate.
      final executor = NativeDatabase.memory(
        setup: (rawDb) {
          rawDb
            ..execute('''
            CREATE TABLE vehicles (
              id TEXT NOT NULL PRIMARY KEY,
              nickname TEXT NOT NULL,
              make TEXT NULL,
              model TEXT NULL,
              year INTEGER NULL,
              plate TEXT NULL,
              odometer INTEGER NOT NULL DEFAULT 0,
              odometer_unit TEXT NOT NULL,
              odometer_updated_at INTEGER NULL,
              household_id TEXT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER NULL
            )
          ''')
            ..execute('''
            CREATE TABLE service_records (
              id TEXT NOT NULL PRIMARY KEY,
              vehicle_id TEXT NOT NULL REFERENCES vehicles (id),
              type TEXT NOT NULL,
              custom_type_label TEXT NULL,
              performed_at INTEGER NOT NULL,
              odometer INTEGER NULL,
              cost REAL NULL,
              currency TEXT NULL,
              notes TEXT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER NULL
            )
          ''')
            ..execute('''
            CREATE TABLE reminder_rules (
              id TEXT NOT NULL PRIMARY KEY,
              vehicle_id TEXT NOT NULL REFERENCES vehicles (id),
              type TEXT NOT NULL,
              custom_type_label TEXT NULL,
              interval_months INTEGER NULL,
              interval_distance INTEGER NULL,
              last_done_at INTEGER NULL,
              last_done_odometer INTEGER NULL,
              is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER NULL
            )
          ''')
            ..execute('''
            INSERT INTO vehicles (
              id, nickname, odometer, odometer_unit, created_at, updated_at
            ) VALUES ('v1', 'Blue Civic', 12000, 'mi', 0, 0)
          ''')
            ..execute('PRAGMA user_version = 1');
        },
      );

      final db = AppDatabase.forTesting(executor);
      addTearDown(db.close);

      // Opening runs the migration.
      final premium = await db.householdEntitlementDao.isHouseholdPremium();
      expect(premium, isFalse, reason: 'the new table exists and is empty');

      // The pre-existing row survived.
      final vehicles = await db.select(db.vehicles).get();
      expect(vehicles, hasLength(1));
      expect(vehicles.single.nickname, 'Blue Civic');

      // And the new table is writable.
      await db.householdEntitlementDao.cacheEntitlement(
        isPremium: true,
        householdId: 'household-1',
      );
      expect(await db.householdEntitlementDao.isHouseholdPremium(), isTrue);
    },
  );

  test('a fresh database gets the cache from onCreate', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.householdEntitlementDao.isHouseholdPremium(), isFalse);
  });
}
