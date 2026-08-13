// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_record_dao.dart';

// ignore_for_file: type=lint
mixin _$ServiceRecordDaoMixin on DatabaseAccessor<AppDatabase> {
  $VehiclesTable get vehicles => attachedDatabase.vehicles;
  $ServiceRecordsTable get serviceRecords => attachedDatabase.serviceRecords;
  ServiceRecordDaoManager get managers => ServiceRecordDaoManager(this);
}

class ServiceRecordDaoManager {
  final _$ServiceRecordDaoMixin _db;
  ServiceRecordDaoManager(this._db);
  $$VehiclesTableTableManager get vehicles =>
      $$VehiclesTableTableManager(_db.attachedDatabase, _db.vehicles);
  $$ServiceRecordsTableTableManager get serviceRecords =>
      $$ServiceRecordsTableTableManager(
        _db.attachedDatabase,
        _db.serviceRecords,
      );
}
