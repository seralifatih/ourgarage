import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/daos/reminder_rule_dao.dart';
import '../local/database.dart';
import '../models/service_type.dart';

/// Thrown when a rule would be left with no interval to schedule from.
///
/// The schema permits it — a rule with neither an interval in months nor one in
/// distance is structurally valid but meaningless, since nothing would ever
/// make it come due. The invariant lives here so the failure arrives as a
/// domain error rather than a raw sqlite constraint violation.
class InvalidReminderRuleException implements Exception {
  const InvalidReminderRuleException(this.message);

  final String message;

  @override
  String toString() => 'InvalidReminderRuleException: $message';
}

class ReminderRuleRepository {
  ReminderRuleRepository(this._dao, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _now = clock ?? DateTime.now;

  final ReminderRuleDao _dao;
  final Uuid _uuid;
  final DateTime Function() _now;

  Stream<List<ReminderRule>> watchRulesForVehicle(String vehicleId) =>
      _dao.watchRulesForVehicle(vehicleId);

  Stream<List<ReminderRule>> watchAllActiveRules() =>
      _dao.watchAllActiveRules();

  Future<ReminderRule?> getRule(String id) => _dao.getRule(id);

  /// Whether any rule has ever been created, across all vehicles.
  ///
  /// Used to decide whether this is the user's first-ever reminder — the one
  /// moment the notification permission explainer should show unconditionally
  /// before the OS prompt, per [NotificationService].
  Future<bool> hasAnyRuleEverExisted() => _dao.hasAnyRuleEverExisted();

  /// Creates a reminder rule.
  ///
  /// At least one of [intervalMonths] / [intervalDistance] must be non-null,
  /// otherwise an [InvalidReminderRuleException] is thrown.
  ///
  /// Returns the id of the new rule.
  Future<String> createRule({
    required String vehicleId,
    required ServiceType type,
    int? intervalMonths,
    int? intervalDistance,
    String? customTypeLabel,
    DateTime? lastDoneAt,
    int? lastDoneOdometer,
    bool isActive = true,
  }) async {
    _requireAnInterval(intervalMonths, intervalDistance);

    final id = _uuid.v4();
    final now = _now();

    await _dao.insertRule(
      ReminderRulesCompanion.insert(
        id: id,
        vehicleId: vehicleId,
        type: type.name,
        customTypeLabel: Value(customTypeLabel),
        intervalMonths: Value(intervalMonths),
        intervalDistance: Value(intervalDistance),
        lastDoneAt: Value(lastDoneAt),
        lastDoneOdometer: Value(lastDoneOdometer),
        isActive: Value(isActive),
        createdAt: now,
        updatedAt: now,
      ),
    );

    return id;
  }

  /// Updates a rule, enforcing that it keeps at least one interval.
  ///
  /// Because either interval can be cleared here, the check runs against the
  /// rule's post-update state, which requires reading it first.
  Future<bool> updateRule(
    String id, {
    ServiceType? type,
    Value<String?> customTypeLabel = const Value.absent(),
    Value<int?> intervalMonths = const Value.absent(),
    Value<int?> intervalDistance = const Value.absent(),
    Value<DateTime?> lastDoneAt = const Value.absent(),
    Value<int?> lastDoneOdometer = const Value.absent(),
    bool? isActive,
  }) async {
    if (intervalMonths.present || intervalDistance.present) {
      final existing = await _dao.getRule(id);
      if (existing == null) return false;

      _requireAnInterval(
        intervalMonths.present ? intervalMonths.value : existing.intervalMonths,
        intervalDistance.present
            ? intervalDistance.value
            : existing.intervalDistance,
      );
    }

    return _dao.updateRule(
      id,
      ReminderRulesCompanion(
        type: type == null ? const Value.absent() : Value(type.name),
        customTypeLabel: customTypeLabel,
        intervalMonths: intervalMonths,
        intervalDistance: intervalDistance,
        lastDoneAt: lastDoneAt,
        lastDoneOdometer: lastDoneOdometer,
        isActive: isActive == null ? const Value.absent() : Value(isActive),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<bool> softDeleteRule(String id) {
    return _dao.softDeleteRule(id, _now());
  }

  /// Marks the rule as serviced, which re-bases the next due date/distance.
  Future<bool> markRuleDone(String ruleId, DateTime doneAt, int? doneOdometer) {
    return _dao.updateRule(
      ruleId,
      ReminderRulesCompanion(
        lastDoneAt: Value(doneAt),
        lastDoneOdometer: Value(doneOdometer),
        updatedAt: Value(_now()),
      ),
    );
  }

  void _requireAnInterval(int? intervalMonths, int? intervalDistance) {
    if (intervalMonths == null && intervalDistance == null) {
      throw const InvalidReminderRuleException(
        'A reminder rule needs at least one of intervalMonths or '
        'intervalDistance.',
      );
    }
  }
}
