import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/features/reminders/reminder_engine.dart';
import 'package:ourgarage/features/reminders/reminder_status_label.dart';

String _label(ReminderStatus status, {String unit = 'mi'}) =>
    ReminderStatusLabel.format(status, distanceUnit: unit);

void main() {
  group('overdue', () {
    test('reports days past due', () {
      expect(
        _label(
          const ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.overdue,
            daysRemaining: -12,
          ),
        ),
        'Overdue by 12 days',
      );
    });

    test('singularises one day', () {
      expect(
        _label(
          const ReminderStatus(
            urgency: ReminderUrgency.overdue,
            daysRemaining: -1,
            odometerStale: false,
          ),
        ),
        'Overdue by 1 day',
      );
    });

    test('reports distance past due with the vehicle unit', () {
      expect(
        _label(
          const ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.overdue,
            distanceRemaining: -340,
          ),
        ),
        'Overdue by 340 mi',
      );
    });

    test('leads with whichever measure is further past due', () {
      // 60 days past is 2x its window; 200 mi past is 0.4x of its own.
      expect(
        _label(
          const ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.overdue,
            daysRemaining: -60,
            distanceRemaining: -200,
          ),
        ),
        'Overdue by 60 days',
      );

      // Now the distance is proportionally the worse of the two.
      expect(
        _label(
          const ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.overdue,
            daysRemaining: -2,
            distanceRemaining: -2000,
          ),
        ),
        'Overdue by 2000 mi',
      );
    });

    test('reads as due now, not overdue, on the boundary', () {
      // Zero days left is the due day itself, not a lapsed one — the engine
      // classifies this as dueNow, and the label follows.
      expect(
        _label(
          const ReminderStatus(
            urgency: ReminderUrgency.dueNow,
            daysRemaining: 0,
            odometerStale: false,
          ),
        ),
        'Due now',
      );
    });
  });

  group('upcoming', () {
    test('counts down in days inside the soon window', () {
      expect(
        _label(
          const ReminderStatus(
            urgency: ReminderUrgency.dueSoon,
            daysRemaining: 12,
            odometerStale: false,
          ),
        ),
        'Due in 12 days',
      );
    });

    test('counts down in distance when that binds first', () {
      expect(
        _label(
          const ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.dueSoon,
            distanceRemaining: 340,
          ),
        ),
        'Due in 340 mi',
      );
    });

    test('prefers the nearer of the two measures', () {
      // 5 days is 1/6 of its window; 400 mi is 4/5 of its own.
      expect(
        _label(
          const ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.dueSoon,
            daysRemaining: 5,
            distanceRemaining: 400,
          ),
        ),
        'Due in 5 days',
      );

      // Reversed: the distance is much closer proportionally.
      expect(
        _label(
          const ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.dueSoon,
            daysRemaining: 25,
            distanceRemaining: 50,
          ),
        ),
        'Due in 50 mi',
      );
    });

    test('names the month once further out than the day window', () {
      expect(
        _label(
          ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.upToDate,
            daysRemaining: 400,
            dueDate: DateTime(2027, 3, 14),
          ),
        ),
        'Due Mar 2027',
      );
    });

    test('uses the unit given rather than assuming miles', () {
      expect(
        _label(
          const ReminderStatus(
            odometerStale: false,
            urgency: ReminderUrgency.dueSoon,
            distanceRemaining: 300,
          ),
          unit: 'km',
        ),
        'Due in 300 km',
      );
    });
  });

  group('no schedule', () {
    test('reports nothing to measure when both deltas are absent', () {
      expect(
        _label(
          const ReminderStatus(
            urgency: ReminderUrgency.upToDate,
            odometerStale: false,
          ),
        ),
        'No schedule',
      );
    });
  });
}
