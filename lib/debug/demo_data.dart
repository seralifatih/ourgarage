import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/local/database.dart';
import '../data/models/service_type.dart';
import '../features/reminders/reminder_engine.dart';

/// Debug-only demo data for screenshots and manual testing.
///
/// Rows go straight into [AppDatabase], bypassing the DAOs on purpose: the DAOs
/// enqueue every write for sync, and demo rows must never reach a real
/// household's cloud copy. Every row id starts with [idPrefix], which is how
/// [clear] finds exactly what [load] wrote and nothing else.
///
/// Every entry point refuses to run outside debug builds, and the only UI that
/// calls it sits behind `kDebugMode`, so release builds tree-shake it away.
///
/// Known limits, acceptable for a debug tool:
///  * [load] overwrites the cached household entitlement and [clear] drops it,
///    so a real cached premium flag is gone until the next server refetch.
///  * The household migration reads tables directly, not the sync queue, so
///    clear demo data before creating or joining a household in a debug build.
///  * Dates are relative to the load day; reload for exact "5 days" figures.
abstract final class DemoData {
  static const String idPrefix = 'demo-';
  static const String _householdId = '${idPrefix}household';
  static const String _currency = 'USD';

  /// Replaces any previous demo data with a fresh set, dated relative to now.
  static Future<void> load(AppDatabase db, {DateTime? now}) async {
    _requireDebug();
    final today = _dateOnly(now ?? DateTime.now());

    await db.transaction(() async {
      await _deleteDemoRows(db);

      for (final vehicle in _vehicles(today)) {
        await db.into(db.vehicles).insert(vehicle.toCompanion(today));
        for (final record in vehicle.records) {
          await db
              .into(db.serviceRecords)
              .insert(record.toCompanion(vehicle.id, today));
        }
        for (final rule in vehicle.rules) {
          await db
              .into(db.reminderRules)
              .insert(rule.toCompanion(vehicle.id, today));
        }
      }

      // The household premium cache is what the app reads for "premium active".
      await db.householdEntitlementDao.cacheEntitlement(
        isPremium: true,
        householdId: _householdId,
        cachedAt: today,
      );
    });
  }

  /// Removes everything [load] wrote, leaving real data untouched.
  static Future<void> clear(AppDatabase db) async {
    _requireDebug();

    await db.transaction(() async {
      await _deleteDemoRows(db);

      // Only drop the entitlement if it is the demo one — a real cached
      // entitlement belongs to the real household.
      final cached = await db.householdEntitlementDao.getCached();
      if (cached?.householdId == _householdId) {
        await db.householdEntitlementDao.clear();
      }
    });
  }

  static void _requireDebug() {
    if (!kDebugMode) {
      throw StateError('Demo data is only available in debug builds.');
    }
  }

  /// Children first: the foreign keys are `restrict`.
  ///
  /// Children are matched by their vehicle too, so a record or rule the user
  /// added to a demo vehicle through the app (which gets a real uuid) doesn't
  /// block the vehicle delete. Queue rows for demo entities are purged as
  /// well: editing a demo row through the app goes via the DAOs, which enqueue
  /// it for sync.
  static Future<void> _deleteDemoRows(AppDatabase db) async {
    const like = '$idPrefix%';
    final records =
        await (db.select(db.serviceRecords)
              ..where((r) => r.id.like(like) | r.vehicleId.like(like)))
            .map((r) => r.id)
            .get();
    final rules =
        await (db.select(db.reminderRules)
              ..where((r) => r.id.like(like) | r.vehicleId.like(like)))
            .map((r) => r.id)
            .get();

    await (db.delete(db.syncQueue)..where(
          (q) =>
              q.entityId.like(like) |
              q.entityId.isIn(records) |
              q.entityId.isIn(rules),
        ))
        .go();
    await (db.delete(
      db.serviceRecords,
    )..where((r) => r.id.like(like) | r.vehicleId.like(like))).go();
    await (db.delete(
      db.reminderRules,
    )..where((r) => r.id.like(like) | r.vehicleId.like(like))).go();
    await (db.delete(db.vehicles)..where((v) => v.id.like(like))).go();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<_Vehicle> _vehicles(DateTime today) {
    DateTime ago(int days) =>
        DateTime(today.year, today.month, today.day - days);
    DateTime monthsAgo(int months) =>
        DateTime(today.year, today.month - months, today.day);

    // Dad's F-150 tire rotation: 6-month interval landing exactly 5 days out.
    final f150RotationDone = _lastDoneForDueIn(
      today: today,
      months: 6,
      days: 5,
    );

    // Emma's Civic inspection: 12-month interval, last done 13 months ago.
    final civicInspectionDone = monthsAgo(13);

    return [
      _Vehicle(
        id: '${idPrefix}vehicle-crv',
        nickname: "Mom's CR-V",
        make: 'Honda',
        model: 'CR-V',
        year: 2019,
        odometer: 42300,
        records: [
          _Record(
            'crv-1',
            ago(120),
            37620,
            ServiceType.oilChange,
            64.99,
            'Full synthetic 0W-20, new filter',
          ),
          _Record(
            'crv-2',
            ago(150),
            36900,
            ServiceType.tireRotation,
            29.00,
            'Rotated and balanced, set to 33 psi',
          ),
          _Record(
            'crv-3',
            ago(240),
            34800,
            ServiceType.inspection,
            35.00,
            'State inspection passed',
          ),
          _Record(
            'crv-4',
            ago(310),
            33100,
            ServiceType.brakes,
            289.50,
            'Front pads and rotor resurfacing',
          ),
          _Record(
            'crv-5',
            ago(430),
            30900,
            ServiceType.oilChange,
            59.99,
            'Synthetic blend, cabin filter swapped',
          ),
        ],
        rules: [
          // Oil due at 37,620 + 5,000 = 42,620 → 320 mi remaining.
          _Rule(
            'crv-oil',
            ServiceType.oilChange,
            intervalDistance: 5000,
            lastDoneAt: ago(120),
            lastDoneOdometer: 37620,
          ),
        ],
      ),
      _Vehicle(
        id: '${idPrefix}vehicle-f150',
        nickname: "Dad's F-150",
        make: 'Ford',
        model: 'F-150',
        year: 2021,
        odometer: 28900,
        records: [
          _Record(
            'f150-1',
            ago(40),
            28150,
            ServiceType.oilChange,
            89.95,
            '5W-20 synthetic blend, 7 qt',
          ),
          _Record(
            'f150-2',
            f150RotationDone,
            25500,
            ServiceType.tireRotation,
            35.00,
            'Rotated all four, checked tread depth',
          ),
          _Record(
            'f150-3',
            ago(260),
            23900,
            ServiceType.inspection,
            40.00,
            'Passed, no advisories',
          ),
          _Record(
            'f150-4',
            ago(330),
            21700,
            ServiceType.oilChange,
            84.95,
            'Synthetic blend, new filter',
          ),
          _Record(
            'f150-5',
            ago(400),
            20300,
            ServiceType.brakes,
            412.00,
            'Rear pads and rotors replaced',
          ),
        ],
        rules: [
          _Rule(
            'f150-rotation',
            ServiceType.tireRotation,
            intervalMonths: 6,
            lastDoneAt: f150RotationDone,
            lastDoneOdometer: 25500,
          ),
        ],
      ),
      _Vehicle(
        id: '${idPrefix}vehicle-civic',
        nickname: "Emma's Civic",
        make: 'Honda',
        model: 'Civic',
        year: 2017,
        odometer: 67150,
        records: [
          _Record(
            'civic-1',
            civicInspectionDone,
            57200,
            ServiceType.inspection,
            30.00,
            'Passed, wipers replaced',
          ),
          _Record(
            'civic-2',
            ago(340),
            59000,
            ServiceType.tireRotation,
            25.00,
            'Rotated, pressure check',
          ),
          _Record(
            'civic-3',
            ago(270),
            61000,
            ServiceType.oilChange,
            52.99,
            'Conventional 5W-20',
          ),
          _Record(
            'civic-4',
            ago(230),
            62100,
            ServiceType.brakes,
            320.00,
            'Front pads, rear rotors',
          ),
          _Record(
            'civic-5',
            ago(160),
            63800,
            ServiceType.tireRotation,
            25.00,
            'Rotated, tread at 6/32',
          ),
          _Record(
            'civic-6',
            ago(75),
            66000,
            ServiceType.oilChange,
            54.99,
            'Synthetic blend, new filter',
          ),
        ],
        rules: [
          _Rule(
            'civic-inspection',
            ServiceType.inspection,
            intervalMonths: 12,
            lastDoneAt: civicInspectionDone,
            lastDoneOdometer: 57200,
          ),
        ],
      ),
    ];
  }

  /// The `lastDoneAt` that makes a [months]-interval rule fall due in [days].
  ///
  /// Searched through [ReminderEngine] itself rather than computed by hand, so
  /// month-end overflow in `DateTime` can't leave the demo a day off.
  static DateTime _lastDoneForDueIn({
    required DateTime today,
    required int months,
    required int days,
  }) {
    for (var offset = -3; offset <= 3; offset++) {
      final candidate = DateTime(
        today.year,
        today.month - months,
        today.day + days + offset,
      );
      final status = ReminderEngine.compute(
        rule: ReminderRuleInput(
          createdAt: candidate,
          intervalMonths: months,
          lastDoneAt: candidate,
        ),
        vehicle: const VehicleReminderContext(odometer: 0),
        now: today,
      );
      if (status.daysRemaining == days) return candidate;
    }
    return DateTime(today.year, today.month - months, today.day + days);
  }
}

class _Vehicle {
  const _Vehicle({
    required this.id,
    required this.nickname,
    required this.make,
    required this.model,
    required this.year,
    required this.odometer,
    required this.records,
    required this.rules,
  });

  final String id;
  final String nickname;
  final String make;
  final String model;
  final int year;
  final int odometer;
  final List<_Record> records;
  final List<_Rule> rules;

  VehiclesCompanion toCompanion(DateTime today) {
    final stamp = DateTime(today.year, today.month, today.day - 3);
    return VehiclesCompanion.insert(
      id: id,
      nickname: nickname,
      odometerUnit: 'mi',
      make: Value(make),
      model: Value(model),
      year: Value(year),
      odometer: Value(odometer),
      odometerUpdatedAt: Value(stamp),
      createdAt: today,
      updatedAt: today,
    );
  }
}

class _Record {
  const _Record(
    this.key,
    this.performedAt,
    this.odometer,
    this.type,
    this.cost,
    this.notes,
  );

  final String key;
  final DateTime performedAt;
  final int odometer;
  final ServiceType type;
  final double cost;
  final String notes;

  ServiceRecordsCompanion toCompanion(String vehicleId, DateTime today) {
    return ServiceRecordsCompanion.insert(
      id: '${DemoData.idPrefix}record-$key',
      vehicleId: vehicleId,
      performedAt: performedAt,
      type: type.name,
      odometer: Value(odometer),
      notes: Value(notes),
      cost: Value(cost),
      currency: const Value(DemoData._currency),
      createdAt: today,
      updatedAt: today,
    );
  }
}

class _Rule {
  const _Rule(
    this.key,
    this.type, {
    this.intervalMonths,
    this.intervalDistance,
    required this.lastDoneAt,
    required this.lastDoneOdometer,
  });

  final String key;
  final ServiceType type;
  final int? intervalMonths;
  final int? intervalDistance;
  final DateTime lastDoneAt;
  final int lastDoneOdometer;

  ReminderRulesCompanion toCompanion(String vehicleId, DateTime today) {
    return ReminderRulesCompanion.insert(
      id: '${DemoData.idPrefix}rule-$key',
      vehicleId: vehicleId,
      type: type.name,
      intervalMonths: Value(intervalMonths),
      intervalDistance: Value(intervalDistance),
      lastDoneAt: Value(lastDoneAt),
      lastDoneOdometer: Value(lastDoneOdometer),
      createdAt: lastDoneAt,
      updatedAt: today,
    );
  }
}
