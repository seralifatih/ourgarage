class AppConstants {
  AppConstants._();

  static const String appName = 'OurGarage';
  static const String databaseFileName = 'ourgarage.sqlite';

  // Free tier limits
  static const int freeVehicleLimit = 1;

  // Reminder defaults
  static const int defaultOilIntervalMonths = 6;
  static const int defaultOilIntervalKm = 8000;
  static const int defaultOilIntervalMiles = 5000;

  static const int defaultTireRotationIntervalMonths = 6;
  static const int defaultTireRotationIntervalKm = 8000;
  static const int defaultTireRotationIntervalMiles = 5000;

  static const int defaultInspectionIntervalMonths = 12;

  // Odometer nudge
  static const int odometerNudgeIntervalDays = 30;

  // Notification IDs base offsets
  static const int reminderNotificationBase = 1000;
  static const int odometerNudgeNotificationId = 999;

  // RevenueCat entitlement key (Phase 4)
  static const String premiumEntitlementId = 'premium';
}
