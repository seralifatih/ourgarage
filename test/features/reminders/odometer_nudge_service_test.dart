import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/core/constants.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/models/service_type.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/features/reminders/odometer_nudge_provider.dart';
import 'package:ourgarage/features/reminders/reminder_engine.dart';

import '../../support/fake_notification_plugin.dart';

final _now = DateTime(2026, 6, 15);

void main() {
  late AppDatabase db;
  late FakeNotificationPlugin plugin;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseHolder.overrideWith(db);
    plugin = FakeNotificationPlugin();
    container = ProviderContainer(
      overrides: [fakeNotificationServiceOverride(plugin)],
    );
  });

  tearDown(() async {
    container.dispose();
    DatabaseHolder.overrideWith(null);
    await db.close();
  });

  Future<void> insertVehicle({
    required String id,
    String nickname = 'Blue Civic',
    String unit = 'km',
    int odometer = 10000,
    DateTime? odometerUpdatedAt,
  }) {
    return db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: id,
            nickname: nickname,
            odometer: Value(odometer),
            odometerUnit: unit,
            odometerUpdatedAt: Value(odometerUpdatedAt),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<void> insertRule({
    required String id,
    required String vehicleId,
    ServiceType type = ServiceType.oilChange,
    int? intervalMonths,
    int? intervalDistance,
    int? lastDoneOdometer,
    bool isActive = true,
  }) {
    return db
        .into(db.reminderRules)
        .insert(
          ReminderRulesCompanion.insert(
            id: id,
            vehicleId: vehicleId,
            type: type.name,
            intervalMonths: Value(intervalMonths),
            intervalDistance: Value(intervalDistance),
            lastDoneOdometer: Value(lastDoneOdometer),
            isActive: Value(isActive),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  }

  bool nudgeScheduled() =>
      plugin.scheduledIds.contains(AppConstants.odometerNudgeNotificationId);

  group('refreshNudge suppression', () {
    test('cancels when no vehicle has a distance rule', () async {
      await insertVehicle(id: 'v1', odometerUpdatedAt: DateTime(2026, 1, 1));
      await insertRule(id: 'r1', vehicleId: 'v1', intervalMonths: 6);

      await container
          .read(odometerNudgeServiceProvider)
          .refreshNudge(now: _now);

      expect(nudgeScheduled(), isFalse);
      expect(
        plugin.cancelledIds,
        contains(AppConstants.odometerNudgeNotificationId),
      );
    });

    test(
      'schedules when a distance rule exists and readings are stale',
      () async {
        await insertVehicle(id: 'v1', odometerUpdatedAt: DateTime(2026, 1, 1));
        await insertRule(
          id: 'r1',
          vehicleId: 'v1',
          intervalDistance: 8000,
          lastDoneOdometer: 5000,
        );

        await container
            .read(odometerNudgeServiceProvider)
            .refreshNudge(now: _now);

        expect(nudgeScheduled(), isTrue);
      },
    );

    test('defers rather than cancels when the reading is fresh', () async {
      await insertVehicle(id: 'v1', odometerUpdatedAt: DateTime(2026, 6, 10));
      await insertRule(
        id: 'r1',
        vehicleId: 'v1',
        intervalDistance: 8000,
        lastDoneOdometer: 5000,
      );

      await container
          .read(odometerNudgeServiceProvider)
          .refreshNudge(now: _now);

      // Scheduled for after the current reading goes stale, not cancelled —
      // cancelling would end the mechanism for anyone who stays on top of it.
      final scheduledAt =
          plugin.scheduledDates[AppConstants.odometerNudgeNotificationId];
      expect(scheduledAt, isNotNull);
      expect(
        DateTime(scheduledAt!.year, scheduledAt.month, scheduledAt.day),
        DateTime(2026, 7, 10),
      );
    });

    test('ignores rules that are inactive', () async {
      await insertVehicle(id: 'v1', odometerUpdatedAt: DateTime(2026, 1, 1));
      await insertRule(
        id: 'r1',
        vehicleId: 'v1',
        intervalDistance: 8000,
        isActive: false,
      );

      await container
          .read(odometerNudgeServiceProvider)
          .refreshNudge(now: _now);

      expect(nudgeScheduled(), isFalse);
    });

    test('one stale vehicle among fresh ones still schedules', () async {
      await insertVehicle(id: 'v1', odometerUpdatedAt: DateTime(2026, 6, 10));
      await insertVehicle(
        id: 'v2',
        nickname: 'Old Truck',
        odometerUpdatedAt: DateTime(2026, 1, 1),
      );
      await insertRule(id: 'r1', vehicleId: 'v1', intervalDistance: 8000);
      await insertRule(id: 'r2', vehicleId: 'v2', intervalDistance: 8000);

      await container
          .read(odometerNudgeServiceProvider)
          .refreshNudge(now: _now);

      expect(nudgeScheduled(), isTrue);
    });
  });

  group('saveReadings', () {
    test('writes the readings it was given', () async {
      await insertVehicle(id: 'v1', odometer: 10000);
      await insertRule(id: 'r1', vehicleId: 'v1', intervalDistance: 8000);

      await container.read(odometerNudgeServiceProvider).saveReadings({
        'v1': 12000,
      }, now: _now);

      final vehicle = await (db.select(
        db.vehicles,
      )..where((v) => v.id.equals('v1'))).getSingle();
      expect(vehicle.odometer, 12000);
      expect(vehicle.odometerUpdatedAt, isNotNull);
    });

    test(
      'reschedules the nudge from the save date, not the old schedule',
      () async {
        // A stale reading would otherwise put the next nudge in early February.
        await insertVehicle(id: 'v1', odometerUpdatedAt: DateTime(2026, 1, 1));
        await insertRule(
          id: 'r1',
          vehicleId: 'v1',
          intervalDistance: 8000,
          lastDoneOdometer: 5000,
        );

        await container.read(odometerNudgeServiceProvider).saveReadings({
          'v1': 11000,
        }, now: _now);

        final scheduledAt =
            plugin.scheduledDates[AppConstants.odometerNudgeNotificationId];
        expect(scheduledAt, isNotNull);
        expect(
          DateTime(scheduledAt!.year, scheduledAt.month, scheduledAt.day),
          DateTime(2026, 7, 15),
          reason:
              'a full interval after the save, so a proactive user is not '
              'nagged on the original schedule',
        );
      },
    );

    test('reports a rule the new reading just made due', () async {
      await insertVehicle(id: 'v1', odometer: 10000, nickname: 'Blue Civic');
      // Due at 5000 + 8000 = 13000.
      await insertRule(
        id: 'r1',
        vehicleId: 'v1',
        intervalDistance: 8000,
        lastDoneOdometer: 5000,
      );

      final due = await container
          .read(odometerNudgeServiceProvider)
          .saveReadings({'v1': 13500}, now: _now);

      expect(due, hasLength(1));
      expect(due.single.urgency, ReminderUrgency.overdue);
      expect(due.single.message, 'Blue Civic is due for an oil change');
    });

    test('reports nothing when the reading leaves rules comfortable', () async {
      await insertVehicle(id: 'v1', odometer: 10000);
      await insertRule(
        id: 'r1',
        vehicleId: 'v1',
        intervalDistance: 8000,
        lastDoneOdometer: 5000,
      );

      final due = await container
          .read(odometerNudgeServiceProvider)
          .saveReadings({'v1': 10500}, now: _now);

      expect(due, isEmpty);
    });

    test('ignores rules on vehicles the user did not update', () async {
      await insertVehicle(id: 'v1', odometer: 10000);
      await insertVehicle(id: 'v2', nickname: 'Old Truck', odometer: 90000);
      await insertRule(
        id: 'r1',
        vehicleId: 'v1',
        intervalDistance: 8000,
        lastDoneOdometer: 5000,
      );
      // Already long overdue, but untouched by this save.
      await insertRule(
        id: 'r2',
        vehicleId: 'v2',
        intervalDistance: 8000,
        lastDoneOdometer: 10000,
      );

      final due = await container
          .read(odometerNudgeServiceProvider)
          .saveReadings({'v1': 10500}, now: _now);

      expect(
        due,
        isEmpty,
        reason: 'an unrelated overdue rule is not a consequence of this save',
      );
    });

    test('an empty save still refreshes the nudge', () async {
      await insertVehicle(id: 'v1', odometerUpdatedAt: DateTime(2026, 1, 1));
      await insertRule(id: 'r1', vehicleId: 'v1', intervalDistance: 8000);

      final due = await container
          .read(odometerNudgeServiceProvider)
          .saveReadings(const {}, now: _now);

      expect(due, isEmpty);
      expect(nudgeScheduled(), isTrue);
    });
  });
}
