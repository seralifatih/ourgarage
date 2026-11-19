import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_routes.dart';
import '../../core/constants.dart';
import '../../data/repositories/premium_status_provider.dart';
import '../../data/repositories/providers.dart';

/// Whether one more vehicle fits: always for Premium, otherwise only under
/// the free limit.
Future<bool> canAddVehicle(WidgetRef ref) async {
  if (ref.read(premiumStatusProvider)) return true;
  final count = await ref.read(vehicleRepositoryProvider).countActiveVehicles();
  return count < AppConstants.freeVehicleLimit;
}

/// Opens the add-vehicle form, or the paywall first when the garage is full.
///
/// The limit is checked here, before the form opens, so nobody fills in a
/// whole vehicle only to be sent to the paywall on Save. The paywall is
/// pushed rather than gone to, so closing it returns here; if it ended in a
/// purchase, the form opens straight after, which is what the user came for.
Future<void> openAddVehicle(BuildContext context, WidgetRef ref) async {
  if (!await canAddVehicle(ref)) {
    if (!context.mounted) return;
    await context.push(AppRoutes.paywall);
    if (!context.mounted || !await canAddVehicle(ref)) return;
  }
  if (!context.mounted) return;
  await context.push(AppRoutes.addVehicle);
}
