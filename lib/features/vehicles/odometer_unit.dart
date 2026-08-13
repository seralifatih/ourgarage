import 'dart:ui';

/// Default odometer unit for a device locale.
///
/// `mi` for `en_US` (the one major locale that measures road distance in
/// miles day to day); `km` for everything else.
String defaultOdometerUnitForLocale(Locale locale) {
  final isUnitedStatesEnglish =
      locale.languageCode == 'en' && locale.countryCode == 'US';
  return isUnitedStatesEnglish ? 'mi' : 'km';
}
