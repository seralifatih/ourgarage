import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/features/reminders/reminder_engine.dart';
import 'package:ourgarage/features/vehicles/widgets/vehicle_card.dart';

Vehicle _vehicle({
  String nickname = 'Blue Civic',
  String? make,
  String? model,
  int? year,
  int odometer = 12500,
  String unit = 'km',
  DateTime? odometerUpdatedAt,
}) {
  final now = DateTime(2026, 6, 1);
  return Vehicle(
    id: 'v1',
    nickname: nickname,
    make: make,
    model: model,
    year: year,
    odometer: odometer,
    odometerUnit: unit,
    odometerUpdatedAt: odometerUpdatedAt,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required Vehicle vehicle,
  ReminderStatus? status,
  DateTime? now,
  VoidCallback? onTap,
  VoidCallback? onUpdateOdometer,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VehicleCard(
          vehicle: vehicle,
          status: status,
          now: now ?? DateTime(2026, 6, 1),
          onTap: onTap ?? () {},
          onUpdateOdometer: onUpdateOdometer ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('subtitle', () {
    testWidgets('shows make, model and year on one line', (tester) async {
      await _pumpCard(
        tester,
        vehicle: _vehicle(make: 'Honda', model: 'Civic', year: 2019),
      );

      expect(find.text('Honda Civic 2019'), findsOneWidget);
    });

    testWidgets('omits the line entirely when all three are null', (
      tester,
    ) async {
      await _pumpCard(tester, vehicle: _vehicle());

      expect(find.text('Blue Civic'), findsOneWidget);
      // Only the nickname and the odometer readout carry text.
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('drops just the missing parts', (tester) async {
      await _pumpCard(tester, vehicle: _vehicle(make: 'Honda', year: 2019));

      expect(find.text('Honda 2019'), findsOneWidget);
    });
  });

  group('odometer readout', () {
    testWidgets('groups thousands and shows the unit', (tester) async {
      await _pumpCard(tester, vehicle: _vehicle(odometer: 128500, unit: 'mi'));

      expect(find.text('128,500'), findsOneWidget);
      expect(find.text('mi'), findsOneWidget);
    });

    testWidgets('leaves short readings ungrouped', (tester) async {
      await _pumpCard(tester, vehicle: _vehicle(odometer: 940));

      expect(find.text('940'), findsOneWidget);
    });
  });

  group('status chip', () {
    testWidgets('shows no chip when the vehicle has no active rules', (
      tester,
    ) async {
      await _pumpCard(tester, vehicle: _vehicle(), status: null);

      expect(find.text('Due now'), findsNothing);
      expect(find.text('Up to date'), findsNothing);
    });

    testWidgets('names how far past due an overdue rule is', (tester) async {
      await _pumpCard(
        tester,
        vehicle: _vehicle(),
        status: const ReminderStatus(
          odometerStale: false,
          urgency: ReminderUrgency.overdue,
          daysRemaining: -3,
        ),
      );

      expect(find.text('Overdue by 3 days'), findsOneWidget);
    });

    testWidgets('shows "Due now" on the day a rule falls due', (tester) async {
      await _pumpCard(
        tester,
        vehicle: _vehicle(),
        status: const ReminderStatus(
          odometerStale: false,
          urgency: ReminderUrgency.dueNow,
          daysRemaining: 0,
        ),
      );

      expect(find.text('Due now'), findsOneWidget);
    });

    testWidgets('counts down in days when time is nearest', (tester) async {
      await _pumpCard(
        tester,
        vehicle: _vehicle(),
        status: const ReminderStatus(
          odometerStale: false,
          urgency: ReminderUrgency.dueSoon,
          daysRemaining: 12,
        ),
      );

      expect(find.text('Due in 12 days'), findsOneWidget);
    });

    testWidgets('counts down in distance with the vehicle unit', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        vehicle: _vehicle(unit: 'mi'),
        status: const ReminderStatus(
          odometerStale: false,
          urgency: ReminderUrgency.dueSoon,
          distanceRemaining: 300,
        ),
      );

      expect(find.text('Due in 300 mi'), findsOneWidget);
    });

    testWidgets('shows "Up to date" when nothing is close', (tester) async {
      await _pumpCard(
        tester,
        vehicle: _vehicle(),
        status: const ReminderStatus(
          odometerStale: false,
          urgency: ReminderUrgency.upToDate,
          daysRemaining: 120,
        ),
      );

      expect(find.text('Up to date'), findsOneWidget);
    });
  });

  group('stale odometer hint', () {
    testWidgets('appears once the reading is 30 days old', (tester) async {
      await _pumpCard(
        tester,
        vehicle: _vehicle(odometerUpdatedAt: DateTime(2026, 5, 1)),
        now: DateTime(2026, 6, 1),
      );

      expect(find.text('Odometer may be out of date'), findsOneWidget);
    });

    testWidgets('stays hidden for a recent reading', (tester) async {
      await _pumpCard(
        tester,
        vehicle: _vehicle(odometerUpdatedAt: DateTime(2026, 5, 20)),
        now: DateTime(2026, 6, 1),
      );

      expect(find.text('Odometer may be out of date'), findsNothing);
    });

    testWidgets('stays hidden when the odometer was never recorded', (
      tester,
    ) async {
      await _pumpCard(tester, vehicle: _vehicle());

      expect(find.text('Odometer may be out of date'), findsNothing);
    });

    testWidgets('tapping it opens the odometer flow, not the card', (
      tester,
    ) async {
      var cardTaps = 0;
      var odometerTaps = 0;

      await _pumpCard(
        tester,
        vehicle: _vehicle(odometerUpdatedAt: DateTime(2026, 1, 1)),
        now: DateTime(2026, 6, 1),
        onTap: () => cardTaps++,
        onUpdateOdometer: () => odometerTaps++,
      );

      await tester.tap(find.text('Odometer may be out of date'));
      await tester.pump();

      expect(odometerTaps, 1);
      expect(cardTaps, 0);
    });
  });

  testWidgets('tapping the card navigates', (tester) async {
    var taps = 0;
    await _pumpCard(tester, vehicle: _vehicle(), onTap: () => taps++);

    await tester.tap(find.text('Blue Civic'));
    await tester.pump();

    expect(taps, 1);
  });
}
