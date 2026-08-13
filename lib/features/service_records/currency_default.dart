import 'dart:ui';

import 'package:intl/intl.dart';

/// Default currency code for a device locale, e.g. `USD` for `en_US`.
///
/// Falls back to `USD` when `intl` can't resolve a currency for the locale —
/// better than leaving the field blank, since a wrong-but-editable default is
/// easier to fix than an empty one.
String defaultCurrencyForLocale(Locale locale) {
  final format = NumberFormat.simpleCurrency(locale: locale.toString());
  return format.currencyName ?? 'USD';
}
