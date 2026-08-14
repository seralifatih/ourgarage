import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database_holder.dart';
import 'household_entitlement_repository.dart';
import 'reminder_rule_repository.dart';
import 'service_record_repository.dart';
import 'vehicle_repository.dart';

part 'providers.g.dart';

// This library must not import '../local/database.dart': riverpod_generator
// 4.0.4 fails with `InvalidTypeException` on any annotated function whose
// signature mentions a drift row type. The derived, row-typed stream providers
// therefore live in `stream_providers.dart` as manual declarations.

@Riverpod(keepAlive: true)
VehicleRepository vehicleRepository(Ref ref) {
  return VehicleRepository(DatabaseHolder.instance.vehicleDao);
}

@Riverpod(keepAlive: true)
ServiceRecordRepository serviceRecordRepository(Ref ref) {
  return ServiceRecordRepository(DatabaseHolder.instance.serviceRecordDao);
}

@Riverpod(keepAlive: true)
ReminderRuleRepository reminderRuleRepository(Ref ref) {
  return ReminderRuleRepository(DatabaseHolder.instance.reminderRuleDao);
}

@Riverpod(keepAlive: true)
HouseholdEntitlementRepository householdEntitlementRepository(Ref ref) {
  return HouseholdEntitlementRepository(
    DatabaseHolder.instance.householdEntitlementDao,
  );
}
