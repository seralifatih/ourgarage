import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/features/reminders/odometer_nudge_planner.dart';

final _now = DateTime(2026, 6, 15);
const _interval = 30;

NudgeVehicleState _vehicle({
  String vehicleId = 'v1',
  String nickname = 'Blue Civic',
  String unit = 'km',
  bool hasActiveDistanceRule = true,
  DateTime? odometerUpdatedAt,
}) {
  return NudgeVehicleState(
    vehicleId: vehicleId,
    nickname: nickname,
    odometerUnit: unit,
    hasActiveDistanceRule: hasActiveDistanceRule,
    odometerUpdatedAt: odometerUpdatedAt,
  );
}

OdometerNudgePlan _plan(
  List<NudgeVehicleState> vehicles, {
  DateTime? now,
  DateTime? from,
}) {
  return OdometerNudgePlanner.plan(
    vehicles: vehicles,
    now: now ?? _now,
    intervalDays: _interval,
    from: from,
  );
}

void main() {
  group('suppression', () {
    test('no vehicles at all means no nudge', () {
      expect(_plan(const []).shouldSchedule, isFalse);
    });

    test('no distance-based rules means no nudge', () {
      final plan = _plan([
        _vehicle(hasActiveDistanceRule: false),
        _vehicle(vehicleId: 'v2', hasActiveDistanceRule: false),
      ]);

      expect(
        plan.shouldSchedule,
        isFalse,
        reason: 'nothing is waiting on an odometer reading',
      );
    });

    test('a single vehicle with a distance rule is enough to nudge', () {
      final plan = _plan([
        _vehicle(hasActiveDistanceRule: false),
        _vehicle(
          vehicleId: 'v2',
          hasActiveDistanceRule: true,
          odometerUpdatedAt: DateTime(2026, 1, 1),
        ),
      ]);

      expect(plan.shouldSchedule, isTrue);
    });

    test('fresh readings defer the nudge rather than cancelling it', () {
      final plan = _plan([
        _vehicle(odometerUpdatedAt: DateTime(2026, 6, 10)),
        _vehicle(vehicleId: 'v2', odometerUpdatedAt: DateTime(2026, 6, 1)),
      ]);

      // Cancelling outright would end the mechanism the first time someone
      // was diligent; the nudge belongs after the freshest reading ages out.
      expect(plan.shouldSchedule, isTrue);
      expect(plan.nextNudgeDate, DateTime(2026, 7, 10));
      expect(plan.nextNudgeDate!.isAfter(_now), isTrue);
    });

    test('one stale reading among fresh ones still nudges', () {
      final plan = _plan([
        _vehicle(odometerUpdatedAt: DateTime(2026, 6, 10)),
        _vehicle(vehicleId: 'v2', odometerUpdatedAt: DateTime(2026, 1, 1)),
      ]);

      expect(plan.shouldSchedule, isTrue);
    });

    test('a reading at exactly the interval nudges immediately', () {
      final plan = _plan([_vehicle(odometerUpdatedAt: DateTime(2026, 5, 16))]);

      // 16 May + 30 days is 15 June, which is today — already past, so it is
      // pushed to a full interval out rather than scheduled in the past.
      expect(plan.shouldSchedule, isTrue);
      expect(plan.nextNudgeDate, DateTime(2026, 7, 15));
    });

    test('a reading one day fresher lands just ahead', () {
      final plan = _plan([_vehicle(odometerUpdatedAt: DateTime(2026, 5, 17))]);

      expect(plan.shouldSchedule, isTrue);
      expect(plan.nextNudgeDate, DateTime(2026, 6, 16));
    });

    test('a never-recorded odometer always nudges', () {
      final plan = _plan([_vehicle()]);

      expect(
        plan.shouldSchedule,
        isTrue,
        reason: 'a vehicle with no reading is the one most in need of one',
      );
    });

    test('a vehicle with no distance rule does not drive the schedule', () {
      final plan = _plan([
        _vehicle(
          hasActiveDistanceRule: false,
          odometerUpdatedAt: DateTime(2020, 1, 1),
        ),
        _vehicle(vehicleId: 'v2', odometerUpdatedAt: DateTime(2026, 6, 10)),
      ]);

      // The ancient reading belongs to a vehicle nothing is waiting on, so it
      // must not pull the nudge forward.
      expect(plan.nextNudgeDate, DateTime(2026, 7, 10));
    });
  });

  group('reschedule from save', () {
    test('counts the interval from the save date', () {
      final plan = _plan([
        _vehicle(odometerUpdatedAt: DateTime(2026, 1, 1)),
      ], from: DateTime(2026, 6, 15));

      expect(plan.nextNudgeDate, DateTime(2026, 7, 15));
    });

    test('a proactive update pushes the next nudge out', () {
      // One vehicle is fresh enough that the nudge is still pending, the other
      // is stale — so a nudge is due, counted from the newest reading.
      final vehicles = [
        _vehicle(odometerUpdatedAt: DateTime(2026, 6, 10)),
        _vehicle(vehicleId: 'v2', odometerUpdatedAt: DateTime(2026, 1, 1)),
      ];

      final scheduled = _plan(vehicles);
      expect(scheduled.nextNudgeDate, DateTime(2026, 7, 10));

      // Saving today moves it a full interval from now instead, so the user
      // who volunteered a reading isn't nudged on the old schedule.
      final afterSave = _plan(vehicles, from: _now);
      expect(afterSave.nextNudgeDate, DateTime(2026, 7, 15));
      expect(
        afterSave.nextNudgeDate!.isAfter(scheduled.nextNudgeDate!),
        isTrue,
      );
    });

    test('never schedules a date already past', () {
      final plan = _plan([
        _vehicle(odometerUpdatedAt: DateTime(2020, 1, 1)),
      ], from: DateTime(2020, 1, 1));

      expect(plan.nextNudgeDate!.isAfter(_now), isTrue);
      expect(plan.nextNudgeDate, DateTime(2026, 7, 15));
    });

    test('falls back to the newest reading when no save date is given', () {
      final plan = _plan([
        _vehicle(odometerUpdatedAt: DateTime(2026, 5, 20)),
        _vehicle(vehicleId: 'v2', odometerUpdatedAt: DateTime(2026, 1, 1)),
      ]);

      expect(plan.nextNudgeDate, DateTime(2026, 6, 19));
    });

    test('falls back to now when nothing has ever been recorded', () {
      final plan = _plan([_vehicle()]);

      expect(plan.nextNudgeDate, DateTime(2026, 7, 15));
    });
  });

  group('copy', () {
    test('names the vehicle when there is only one', () {
      final plan = _plan([_vehicle(nickname: 'Blue Civic')]);

      expect(
        plan.body,
        'Quick odometer update keeps your Blue Civic reminders accurate.',
      );
    });

    test('says "your vehicles" when there are several', () {
      final plan = _plan([
        _vehicle(nickname: 'Blue Civic'),
        _vehicle(vehicleId: 'v2', nickname: 'Old Truck'),
      ]);

      expect(
        plan.body,
        'Quick odometer update keeps your vehicles reminders accurate.',
      );
    });

    test('only counts vehicles the nudge is actually about', () {
      final plan = _plan([
        _vehicle(nickname: 'Blue Civic'),
        _vehicle(
          vehicleId: 'v2',
          nickname: 'Old Truck',
          hasActiveDistanceRule: false,
        ),
      ]);

      expect(plan.body, contains('your Blue Civic'));
    });

    test('asks in miles for a miles vehicle', () {
      final plan = _plan([_vehicle(unit: 'mi')]);

      expect(plan.title, 'How many miles now?');
    });

    test('asks in km for a km vehicle', () {
      final plan = _plan([_vehicle(unit: 'km')]);

      expect(plan.title, 'How many km now?');
    });

    test('stays neutral when units are mixed', () {
      final plan = _plan([
        _vehicle(unit: 'km'),
        _vehicle(vehicleId: 'v2', unit: 'mi'),
      ]);

      expect(
        plan.title,
        'How far have you driven?',
        reason: 'picking one unit would be wrong for the other vehicle',
      );
    });
  });
}
