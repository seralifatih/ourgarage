// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'household_entitlement_dao.dart';

// ignore_for_file: type=lint
mixin _$HouseholdEntitlementDaoMixin on DatabaseAccessor<AppDatabase> {
  $HouseholdEntitlementsTable get householdEntitlements =>
      attachedDatabase.householdEntitlements;
  HouseholdEntitlementDaoManager get managers =>
      HouseholdEntitlementDaoManager(this);
}

class HouseholdEntitlementDaoManager {
  final _$HouseholdEntitlementDaoMixin _db;
  HouseholdEntitlementDaoManager(this._db);
  $$HouseholdEntitlementsTableTableManager get householdEntitlements =>
      $$HouseholdEntitlementsTableTableManager(
        _db.attachedDatabase,
        _db.householdEntitlements,
      );
}
