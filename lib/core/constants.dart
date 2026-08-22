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

  /// RevenueCat product identifiers, configured in App Store Connect and
  /// mapped to [premiumEntitlementId] in the RevenueCat dashboard.
  static const String lifetimeProductId = 'ourgarage_lifetime';
  static const String annualProductId = 'ourgarage_annual';

  // Source text lives in `store/legal/`, published from `docs/` via GitHub
  // Pages. These must be live and reachable before submission — review
  // rejects an IAP paywall whose legal links 404. Point these at
  // noktastudio.dev instead once that domain is actually hosting the pages.
  static const String termsUrl =
      'https://seralifatih.github.io/ourgarage/ourgarage/terms/';
  static const String privacyUrl =
      'https://seralifatih.github.io/ourgarage/ourgarage/privacy/';

  /// Supabase project URL and anon key, supplied at build time:
  /// `flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  ///              --dart-define=SUPABASE_ANON_KEY=eyJ...`
  ///
  /// The anon key is a public client credential — it is safe in the binary,
  /// because every table it can reach is behind RLS (see
  /// `supabase/migrations/`). Empty by default, which leaves
  /// [AuthService] unconfigured: sharing is unavailable and the app runs
  /// entirely local, which is exactly what a free user gets anyway.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Fallback household name when Apple withholds the user's name.
  ///
  /// Apple returns the display name only on the very first authorization, and
  /// the user may decline to share it at all, so this has to be a real
  /// possibility rather than an edge case.
  static const String defaultHouseholdName = 'My household';

  /// RevenueCat public SDK key, supplied at build time:
  /// `flutter run --dart-define=REVENUECAT_API_KEY=appl_xxx`.
  ///
  /// Empty by default, which leaves [PurchaseService] unconfigured and the
  /// user un-entitled rather than crashing — tests and any build without the
  /// key still run, they just can't purchase.
  static const String revenueCatApiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
  );
}
