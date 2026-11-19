import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';

/// A mailto to support with the app and OS version prefilled, so a report
/// arrives with what is needed to reproduce it. [details] (an error code, say)
/// goes above the version lines.
Future<Uri> feedbackEmailUri({
  String subject = 'OurGarage feedback',
  String? details,
}) async {
  var appVersion = 'unknown';
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = '${info.version} (${info.buildNumber})';
  } catch (error) {
    debugPrint('Could not read app version: $error');
  }
  final osName = Platform.isIOS ? 'iOS' : Platform.operatingSystem;
  final body =
      '\n\n---\n'
      '${details == null ? '' : '$details\n'}'
      'App version: $appVersion\n'
      '$osName version: ${Platform.operatingSystemVersion}\n';

  // Built by hand: Uri.queryParameters encodes spaces as "+", which mail
  // clients show literally.
  return Uri.parse(
    'mailto:${AppConstants.feedbackEmail}'
    '?subject=${Uri.encodeComponent(subject)}'
    '&body=${Uri.encodeComponent(body)}',
  );
}

/// Opens [uri] outside the app, reporting failure on [messenger].
Future<void> openExternal(ScaffoldMessengerState messenger, Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (error) {
    debugPrint('Could not open $uri: $error');
  }
  if (!opened) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Could not open link')));
  }
}

/// Starts an email to support; see [feedbackEmailUri].
Future<void> openFeedbackEmail(
  ScaffoldMessengerState messenger, {
  String subject = 'OurGarage feedback',
  String? details,
}) async {
  final uri = await feedbackEmailUri(subject: subject, details: details);
  await openExternal(messenger, uri);
}
