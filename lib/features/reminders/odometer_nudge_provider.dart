import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'odometer_nudge_service.dart';

part 'odometer_nudge_provider.g.dart';

/// The odometer nudge coordinator.
///
/// Lives in its own file because `odometer_nudge_service.dart` imports drift
/// row types, and riverpod_generator 4.0.4 fails on any annotated function in
/// a library that does — see the note in `data/repositories/providers.dart`.
@Riverpod(keepAlive: true)
OdometerNudgeService odometerNudgeService(Ref ref) {
  return OdometerNudgeService(ref);
}
