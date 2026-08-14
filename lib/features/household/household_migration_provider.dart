import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/database_holder.dart';
import '../../services/remote_garage.dart';
import 'household_migration_service.dart';
import 'household_service.dart';

part 'household_migration_provider.g.dart';

/// Invites and membership. Tests override this with a fake backend.
@Riverpod(keepAlive: true)
HouseholdService householdService(Ref ref) => const HouseholdService();

/// The cloud copy of the garage. Tests override this with a fake.
@Riverpod(keepAlive: true)
RemoteGarage remoteGarage(Ref ref) => const SupabaseRemoteGarage();

/// The one-time upload of local data into a household.
@Riverpod(keepAlive: true)
HouseholdMigrationService householdMigration(Ref ref) {
  final db = DatabaseHolder.instance;
  return HouseholdMigrationService(
    vehicleDao: db.vehicleDao,
    serviceRecordDao: db.serviceRecordDao,
    reminderRuleDao: db.reminderRuleDao,
    remote: ref.watch(remoteGarageProvider),
  );
}
