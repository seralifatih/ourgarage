/// Route paths, in one place so callers never hand-build a URL.
class AppRoutes {
  AppRoutes._();

  static const String vehicleList = '/';
  static const String settings = '/settings';
  static const String paywall = '/paywall';

  /// Where the odometer nudge lands: one field per vehicle, one Save.
  static const String updateOdometers = '/update-odometers';

  /// Not in the original route list, but both the FAB and the empty state need
  /// somewhere to go.
  static const String addVehicle = '/vehicle/new';

  static String vehicleDetail(String id) => '/vehicle/$id';
  static String editVehicle(String id) => '/vehicle/$id/edit';
  static String addService(String id) => '/vehicle/$id/add-service';
  static String reminders(String id) => '/vehicle/$id/reminders';

  /// Not in the original route list, but tapping a history row opens the
  /// record for editing, which needs its own destination.
  static String editService(String vehicleId, String recordId) =>
      '/vehicle/$vehicleId/service/$recordId';

  /// Not in the original route list, but the reminders screen's FAB and its
  /// row taps need somewhere to add or edit a rule.
  static String addReminderRule(String vehicleId) =>
      '/vehicle/$vehicleId/reminders/new';
  static String editReminderRule(String vehicleId, String ruleId) =>
      '/vehicle/$vehicleId/reminders/$ruleId';
}
