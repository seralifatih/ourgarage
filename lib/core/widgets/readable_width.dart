import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Widest a column of form fields or list rows gets before it stops reading
/// as one column. Phones never reach it; on an iPad the content centres.
const double kReadableWidth = 640;

/// [base] widened on both sides so the content between them is at most
/// [maxWidth] across.
///
/// Padding rather than a ConstrainedBox around the scroll view: the scroll
/// view keeps the full screen width, so a drag in the side margins on an
/// iPad still scrolls.
EdgeInsets readablePadding(
  BuildContext context,
  EdgeInsets base, {
  double maxWidth = kReadableWidth,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final extra = math.max(0.0, (width - base.horizontal - maxWidth) / 2);
  return base.copyWith(left: base.left + extra, right: base.right + extra);
}
