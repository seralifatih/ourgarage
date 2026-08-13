// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reminder_rule_dao.dart';

// ignore_for_file: type=lint
mixin _$ReminderRuleDaoMixin on DatabaseAccessor<AppDatabase> {
  $VehiclesTable get vehicles => attachedDatabase.vehicles;
  $ReminderRulesTable get reminderRules => attachedDatabase.reminderRules;
  ReminderRuleDaoManager get managers => ReminderRuleDaoManager(this);
}

class ReminderRuleDaoManager {
  final _$ReminderRuleDaoMixin _db;
  ReminderRuleDaoManager(this._db);
  $$VehiclesTableTableManager get vehicles =>
      $$VehiclesTableTableManager(_db.attachedDatabase, _db.vehicles);
  $$ReminderRulesTableTableManager get reminderRules =>
      $$ReminderRulesTableTableManager(_db.attachedDatabase, _db.reminderRules);
}
