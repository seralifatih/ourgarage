import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes garage data to the household's cloud copy.
///
/// Deals in plain maps rather than Drift row types so the remote layer knows
/// nothing about the local schema, and so the mapping between the two lives in
/// exactly one place — [HouseholdMigrationService].
///
/// Every write is an upsert keyed on the row's uuid. The app generates v4 uuids
/// locally and reuses them verbatim as the remote primary keys, so there is no
/// id remapping anywhere in the system and a re-run of any upload converges on
/// the same rows instead of duplicating them.
abstract interface class RemoteGarage {
  Future<void> upsertVehicles(List<Map<String, dynamic>> rows);

  Future<void> upsertServiceRecords(List<Map<String, dynamic>> rows);

  Future<void> upsertReminderRules(List<Map<String, dynamic>> rows);

  /// Rows in the household changed strictly after [since], oldest change
  /// first. [since] null means "everything", the first pull after joining.
  ///
  /// Returns rows in remote column shape, including tombstoned ones: a delete
  /// travels as an ordinary row carrying `deleted_at`, and filtering those out
  /// would mean deletions never reached a peer.
  Future<List<Map<String, dynamic>>> fetchChangedSince({
    required String householdId,
    required DateTime? since,
  });

  /// Removes every row belonging to [householdId].
  ///
  /// The compensating action for a failed upload. Children go first:
  /// service_records and reminder_rules reference vehicles with
  /// `on delete restrict`, so deleting vehicles first would be rejected by the
  /// database and leave the rollback half-done.
  Future<void> deleteHouseholdData(String householdId);
}

/// [RemoteGarage] backed by Supabase.
class SupabaseRemoteGarage implements RemoteGarage {
  const SupabaseRemoteGarage();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<void> upsertVehicles(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('vehicles').upsert(rows, onConflict: 'id');
  }

  @override
  Future<void> upsertServiceRecords(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('service_records').upsert(rows, onConflict: 'id');
  }

  @override
  Future<void> upsertReminderRules(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('reminder_rules').upsert(rows, onConflict: 'id');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChangedSince({
    required String householdId,
    required DateTime? since,
  }) async {
    final cutoff = since?.toUtc().toIso8601String();

    // Vehicles carry household_id directly; their children are reached through
    // it, the same shape the RLS policies use. RLS would filter foreign rows
    // anyway — this is about fetching less, not about being safe.
    var vehicleQuery = _client
        .from('vehicles')
        .select()
        .eq('household_id', householdId);
    if (cutoff != null) vehicleQuery = vehicleQuery.gt('updated_at', cutoff);
    final vehicleRows = await vehicleQuery;

    final householdVehicleIds = await _client
        .from('vehicles')
        .select('id')
        .eq('household_id', householdId);
    final ids = [
      for (final row in householdVehicleIds as List)
        (row as Map)['id'] as String,
    ];

    final out = <Map<String, dynamic>>[
      for (final row in vehicleRows as List)
        {...(row as Map).cast<String, dynamic>(), '_entity': 'vehicle'},
    ];

    if (ids.isEmpty) return out;

    for (final entity in const [
      ('service_records', 'serviceRecord'),
      ('reminder_rules', 'reminderRule'),
    ]) {
      var query = _client.from(entity.$1).select().inFilter('vehicle_id', ids);
      if (cutoff != null) query = query.gt('updated_at', cutoff);

      out.addAll([
        for (final row in await query as List)
          {...(row as Map).cast<String, dynamic>(), '_entity': entity.$2},
      ]);
    }

    return out;
  }

  @override
  Future<void> deleteHouseholdData(String householdId) async {
    // The children carry no household_id of their own, so they are reached
    // through their vehicle — the same shape as the RLS policies use.
    final vehicleRows = await _client
        .from('vehicles')
        .select('id')
        .eq('household_id', householdId);

    final vehicleIds = [
      for (final row in vehicleRows as List) (row as Map)['id'] as String,
    ];

    if (vehicleIds.isNotEmpty) {
      await _client
          .from('service_records')
          .delete()
          .inFilter('vehicle_id', vehicleIds);
      await _client
          .from('reminder_rules')
          .delete()
          .inFilter('vehicle_id', vehicleIds);
    }

    await _client.from('vehicles').delete().eq('household_id', householdId);
  }
}
