import '../local/database.dart';

/// Holds the process-wide [AppDatabase].
///
/// The database sits outside the provider graph because the provider library
/// cannot import drift's generated code (see the note in `providers.dart`).
/// Tests install an in-memory database with [overrideWith] before reading any
/// provider.
class DatabaseHolder {
  DatabaseHolder._();

  static AppDatabase? _instance;

  /// The shared database, opened on first use.
  static AppDatabase get instance => _instance ??= AppDatabase();

  /// Replaces the shared database, returning the previous instance if any.
  static AppDatabase? overrideWith(AppDatabase? db) {
    final previous = _instance;
    _instance = db;
    return previous;
  }
}
