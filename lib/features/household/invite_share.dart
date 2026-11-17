import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import 'household_service.dart';

/// The message sent with an invite. Written for someone who may not have the
/// app yet, so it says where to get it and exactly where the code goes.
String inviteMessage(String code) {
  final days = inviteLifetime.inDays;
  return 'Join our garage on ${AppConstants.appName}, so we see the same cars, '
      'service history and reminders.\n\n'
      '1. Get the app: ${AppConstants.appStoreUrl}\n'
      '2. Open Settings → Join a household\n'
      '3. Enter the code: $code\n\n'
      'The code works once and expires in $days days.';
}

/// Opens the system share sheet. [origin] anchors the popover on iPad, where
/// a share sheet without one is not shown at all.
typedef InviteSharer = Future<void> Function(String text, Rect? origin);

Future<void> _shareWithSystemSheet(String text, Rect? origin) async {
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: 'Join our garage on ${AppConstants.appName}',
      sharePositionOrigin: origin,
    ),
  );
}

/// Overridden in tests, which have no platform share sheet.
final inviteSharerProvider = Provider<InviteSharer>(
  (ref) => _shareWithSystemSheet,
);

/// The global rect of [context]'s render box, for [InviteSharer]'s origin.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
