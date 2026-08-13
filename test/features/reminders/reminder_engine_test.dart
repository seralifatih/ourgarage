import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/features/reminders/reminder_engine.dart';

/// Fixed "now" so nothing in here depends on the wall clock.
final _now = DateTime(2026, 6, 15);

ReminderRuleInput _rule({
  DateTime? createdAt,
  int? intervalMonths,
  int? intervalDistance,
  DateTime? lastDoneAt,
  int? distanceBaseline,
}) {
  return ReminderRuleInput(
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    intervalMonths: intervalMonths,
    intervalDistance: intervalDistance,
    lastDoneAt: lastDoneAt,
    distanceBaseline: distanceBaseline,
  );
}

/// Defaults to a freshly-read odometer, so tests only opt in to staleness.
VehicleReminderContext _vehicle({
  int odometer = 10000,
  DateTime? odometerUpdatedAt,
}) {
  return VehicleReminderContext(
    odometer: odometer,
    odometerUpdatedAt: odometerUpdatedAt ?? _now,
  );
}

ReminderStatus _compute(
  ReminderRuleInput rule, {
  VehicleReminderContext? vehicle,
  DateTime? now,
}) {
  return ReminderEngine.compute(
    rule: rule,
    vehicle: vehicle ?? _vehicle(),
    now: now ?? _now,
  );
}

void main() {
  group('time-only rules', () {
    test('due date is lastDoneAt plus the interval', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 3, 10)),
      );

      expect(status.dueDate, DateTime(2026, 9, 10));
      expect(status.daysRemaining, 87);
      expect(status.dueOdometer, isNull);
      expect(status.distanceRemaining, isNull);
    });

    test('falls back to createdAt when never completed', () {
      final status = _compute(
        _rule(createdAt: DateTime(2026, 2, 1), intervalMonths: 6),
      );

      expect(status.dueDate, DateTime(2026, 8, 1));
    });

    test('is up to date well before the due date', () {
      final status = _compute(
        _rule(intervalMonths: 12, lastDoneAt: DateTime(2026, 1, 1)),
      );

      expect(status.urgency, ReminderUrgency.upToDate);
    });

    test('is due soon inside 30 days', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 1, 5)),
      );

      expect(status.daysRemaining, 20);
      expect(status.urgency, ReminderUrgency.dueSoon);
    });

    test('is due now inside 7 days', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2025, 12, 20)),
      );

      expect(status.daysRemaining, 5);
      expect(status.urgency, ReminderUrgency.dueNow);
    });

    test('is due now, not overdue, on the day itself', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2025, 12, 15)),
      );

      expect(status.daysRemaining, 0);
      expect(status.urgency, ReminderUrgency.dueNow);
    });

    test('is overdue once the date has passed', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2025, 12, 1)),
      );

      expect(status.daysRemaining, -14);
      expect(status.urgency, ReminderUrgency.overdue);
    });

    test('is never stale — staleness only applies to distance', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 3, 10)),
        vehicle: _vehicle(odometerUpdatedAt: DateTime(2020, 1, 1)),
      );

      expect(status.odometerStale, isFalse);
    });
  });

  group('distance-only rules', () {
    test('due odometer is the baseline plus the interval', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometer: 10000),
      );

      expect(status.dueOdometer, 13000);
      expect(status.distanceRemaining, 3000);
      expect(status.dueDate, isNull);
      expect(status.daysRemaining, isNull);
    });

    test('is up to date when far away', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometer: 10000),
      );

      expect(status.urgency, ReminderUrgency.upToDate);
    });

    test('is due soon inside 500 units', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometer: 12600),
      );

      expect(status.distanceRemaining, 400);
      expect(status.urgency, ReminderUrgency.dueSoon);
    });

    test('is due now inside 200 units', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometer: 12900),
      );

      expect(status.distanceRemaining, 100);
      expect(status.urgency, ReminderUrgency.dueNow);
    });

    test('is due now, not overdue, exactly on the target', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometer: 13000),
      );

      expect(status.distanceRemaining, 0);
      expect(status.urgency, ReminderUrgency.dueNow);
    });

    test('is overdue past the target', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometer: 13500),
      );

      expect(status.distanceRemaining, -500);
      expect(status.urgency, ReminderUrgency.overdue);
    });

    test('reports nothing measurable without a baseline', () {
      final status = _compute(
        _rule(intervalDistance: 8000),
        vehicle: _vehicle(odometer: 50000),
      );

      expect(status.dueOdometer, isNull);
      expect(status.distanceRemaining, isNull);
      expect(status.urgency, ReminderUrgency.upToDate);
    });
  });

  group('rules with both intervals', () {
    test('time wins when it comes first', () {
      // Due in 5 days, but still 3000 units away.
      final status = _compute(
        _rule(
          intervalMonths: 6,
          lastDoneAt: DateTime(2025, 12, 20),
          intervalDistance: 8000,
          distanceBaseline: 5000,
        ),
        vehicle: _vehicle(odometer: 10000),
      );

      expect(status.daysRemaining, 5);
      expect(status.distanceRemaining, 3000);
      expect(status.urgency, ReminderUrgency.dueNow);
    });

    test('distance wins when it comes first', () {
      // 100 units away, but not due by date for another 200 days.
      final status = _compute(
        _rule(
          intervalMonths: 12,
          lastDoneAt: DateTime(2026, 1, 1),
          intervalDistance: 8000,
          distanceBaseline: 5000,
        ),
        vehicle: _vehicle(odometer: 12900),
      );

      expect(status.distanceRemaining, 100);
      expect(status.urgency, ReminderUrgency.dueNow);
    });

    test('overdue on either measure makes the rule overdue', () {
      final status = _compute(
        _rule(
          intervalMonths: 24,
          lastDoneAt: DateTime(2026, 1, 1),
          intervalDistance: 8000,
          distanceBaseline: 5000,
        ),
        vehicle: _vehicle(odometer: 14000),
      );

      expect(status.daysRemaining, greaterThan(0));
      expect(status.distanceRemaining, -1000);
      expect(status.urgency, ReminderUrgency.overdue);
    });

    test('both measures are reported regardless of which decides', () {
      final status = _compute(
        _rule(
          intervalMonths: 6,
          lastDoneAt: DateTime(2026, 3, 10),
          intervalDistance: 8000,
          distanceBaseline: 5000,
        ),
        vehicle: _vehicle(odometer: 10000),
      );

      expect(status.dueDate, DateTime(2026, 9, 10));
      expect(status.dueOdometer, 13000);
      expect(status.daysRemaining, 87);
      expect(status.distanceRemaining, 3000);
    });

    test('is up to date only when both measures are far off', () {
      final status = _compute(
        _rule(
          intervalMonths: 12,
          lastDoneAt: DateTime(2026, 1, 1),
          intervalDistance: 8000,
          distanceBaseline: 5000,
        ),
        vehicle: _vehicle(odometer: 10000),
      );

      expect(status.urgency, ReminderUrgency.upToDate);
    });
  });

  group('odometer staleness', () {
    test('is stale when the reading was never recorded', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: VehicleReminderContext(odometer: 10000),
      );

      expect(status.odometerStale, isTrue);
    });

    test('is stale at exactly 30 days old', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometerUpdatedAt: DateTime(2026, 5, 16)),
      );

      expect(status.odometerStale, isTrue);
    });

    test('is fresh at 29 days old', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometerUpdatedAt: DateTime(2026, 5, 17)),
      );

      expect(status.odometerStale, isFalse);
    });

    test('still reports the distance figures while stale', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(
          odometer: 12900,
          odometerUpdatedAt: DateTime(2026, 1, 1),
        ),
      );

      expect(status.odometerStale, isTrue);
      expect(status.dueOdometer, 13000);
      expect(status.distanceRemaining, 100);
      expect(status.urgency, ReminderUrgency.dueNow);
    });

    test('a rule with no distance interval is never stale', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 3, 10)),
        vehicle: VehicleReminderContext(odometer: 10000),
      );

      expect(status.odometerStale, isFalse);
    });
  });

  group('notification eligibility', () {
    test('a distance-only rule never fires, however overdue', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(odometer: 20000),
      );

      expect(status.urgency, ReminderUrgency.overdue);
      expect(
        status.canFireNotification,
        isFalse,
        reason: 'the odometer is only known when the user enters it',
      );
    });

    test('a time-based rule fires once inside the due-now window', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2025, 12, 20)),
      );

      expect(status.canFireNotification, isTrue);
    });

    test('a time-based rule fires when overdue', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2025, 12, 1)),
      );

      expect(status.canFireNotification, isTrue);
    });

    test('a time-based rule does not fire while only due soon', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 1, 5)),
      );

      expect(status.urgency, ReminderUrgency.dueSoon);
      expect(status.canFireNotification, isFalse);
    });

    test('a both-intervals rule fires on its time side only', () {
      // Distance says due now; time is still months away.
      final distanceDriven = _compute(
        _rule(
          intervalMonths: 12,
          lastDoneAt: DateTime(2026, 1, 1),
          intervalDistance: 8000,
          distanceBaseline: 5000,
        ),
        vehicle: _vehicle(odometer: 12900),
      );

      expect(distanceDriven.urgency, ReminderUrgency.dueNow);
      expect(
        distanceDriven.canFireNotification,
        isFalse,
        reason: 'urgency came from distance, which cannot fire unprompted',
      );

      // Same rule, but now the time side has arrived.
      final timeDriven = _compute(
        _rule(
          intervalMonths: 6,
          lastDoneAt: DateTime(2025, 12, 20),
          intervalDistance: 8000,
          distanceBaseline: 5000,
        ),
        vehicle: _vehicle(odometer: 10000),
      );

      expect(timeDriven.canFireNotification, isTrue);
    });

    test('a stale odometer never turns into a firing notification', () {
      final status = _compute(
        _rule(intervalDistance: 8000, distanceBaseline: 5000),
        vehicle: _vehicle(
          odometer: 14000,
          odometerUpdatedAt: DateTime(2026, 1, 1),
        ),
      );

      expect(status.odometerStale, isTrue);
      expect(status.urgency, ReminderUrgency.overdue);
      expect(status.canFireNotification, isFalse);
    });
  });

  group('a rule created today', () {
    test('with a time interval counts from today', () {
      final status = _compute(_rule(createdAt: _now, intervalMonths: 6));

      expect(status.dueDate, DateTime(2026, 12, 15));
      expect(status.daysRemaining, 183);
      expect(status.urgency, ReminderUrgency.upToDate);
    });

    test('with a distance interval counts from the current reading', () {
      final status = _compute(
        _rule(createdAt: _now, intervalDistance: 8000, distanceBaseline: 10000),
        vehicle: _vehicle(odometer: 10000),
      );

      expect(status.dueOdometer, 18000);
      expect(status.distanceRemaining, 8000);
      expect(status.urgency, ReminderUrgency.upToDate);
    });

    test('with no baseline reports no distance and stays up to date', () {
      final status = _compute(_rule(createdAt: _now, intervalDistance: 8000));

      expect(status.distanceRemaining, isNull);
      expect(status.urgency, ReminderUrgency.upToDate);
    });

    test('with no intervals at all can never come due', () {
      final status = _compute(_rule(createdAt: _now));

      expect(status.dueDate, isNull);
      expect(status.dueOdometer, isNull);
      expect(status.urgency, ReminderUrgency.upToDate);
      expect(status.canFireNotification, isFalse);
    });
  });

  group('month arithmetic', () {
    test('clamps when the target month is shorter', () {
      // 31 Jan + 1 month has no 31 Feb; DateTime rolls into March.
      final status = _compute(
        _rule(intervalMonths: 1, lastDoneAt: DateTime(2026, 1, 31)),
      );

      expect(status.dueDate, DateTime(2026, 3, 3));
    });

    test('rolls over the year boundary', () {
      final status = _compute(
        _rule(intervalMonths: 8, lastDoneAt: DateTime(2026, 7, 10)),
      );

      expect(status.dueDate, DateTime(2027, 3, 10));
    });

    test('ignores the time of day when counting days', () {
      final status = _compute(
        _rule(intervalMonths: 6, lastDoneAt: DateTime(2025, 12, 15, 23, 59)),
        now: DateTime(2026, 6, 15, 0, 1),
      );

      expect(status.daysRemaining, 0);
      expect(status.urgency, ReminderUrgency.dueNow);
    });
  });

  group('mostUrgent', () {
    test('returns null when there are no rules', () {
      expect(
        ReminderEngine.mostUrgent(
          rules: const [],
          vehicle: _vehicle(),
          now: _now,
        ),
        isNull,
      );
    });

    test('prefers the worst bucket', () {
      final status = ReminderEngine.mostUrgent(
        rules: [
          _rule(intervalMonths: 24, lastDoneAt: DateTime(2026, 1, 1)),
          _rule(intervalMonths: 6, lastDoneAt: DateTime(2025, 1, 1)),
          _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 1, 5)),
        ],
        vehicle: _vehicle(),
        now: _now,
      );

      expect(status!.urgency, ReminderUrgency.overdue);
    });

    test('within a bucket, picks the one nearest its threshold', () {
      final status = ReminderEngine.mostUrgent(
        rules: [
          _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 1, 10)),
          _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 1, 5)),
        ],
        vehicle: _vehicle(),
        now: _now,
      );

      expect(status!.urgency, ReminderUrgency.dueSoon);
      expect(status.daysRemaining, 20);
    });

    test('compares time and distance rules against each other', () {
      final status = ReminderEngine.mostUrgent(
        rules: [
          // Due in 20 days — two thirds through its window.
          _rule(intervalMonths: 6, lastDoneAt: DateTime(2026, 1, 5)),
          // 100 units out — a fifth of its window, so the nearer of the two.
          _rule(intervalDistance: 8000, distanceBaseline: 5000),
        ],
        vehicle: _vehicle(odometer: 12900),
        now: _now,
      );

      expect(status!.urgency, ReminderUrgency.dueNow);
      expect(status.distanceRemaining, 100);
    });
  });
}
