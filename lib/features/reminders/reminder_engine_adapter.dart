import '../../data/local/database.dart';
import 'reminder_engine.dart';

/// Bridges drift rows into [ReminderEngine]'s plain inputs.
///
/// The engine deliberately knows nothing about the database; this is the one
/// place that translates, so the mapping can't drift between call sites.
extension ReminderRuleEngineInput on ReminderRule {
  /// This rule as engine input.
  ///
  /// [distanceBaseline] falls back to [lastDoneOdometer]. There is no column
  /// recording the odometer when the rule was created, so a distance rule that
  /// has never been completed has no baseline and produces no distance figure
  /// until it is first marked done.
  ReminderRuleInput toEngineInput() {
    return ReminderRuleInput(
      createdAt: createdAt,
      intervalMonths: intervalMonths,
      intervalDistance: intervalDistance,
      lastDoneAt: lastDoneAt,
      distanceBaseline: lastDoneOdometer,
    );
  }
}

/// Bridges a vehicle row into the engine's context.
extension VehicleEngineContext on Vehicle {
  VehicleReminderContext toEngineContext() {
    return VehicleReminderContext(
      odometer: odometer,
      odometerUpdatedAt: odometerUpdatedAt,
    );
  }
}
