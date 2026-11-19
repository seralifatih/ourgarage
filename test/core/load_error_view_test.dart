import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/core/widgets/load_error_view.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/stream_providers.dart';
import 'package:ourgarage/features/reminders/update_odometers_screen.dart';
import 'package:ourgarage/features/vehicles/vehicle_list_screen.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

/// Audit #15: a load failure shows a plain sentence and Retry, never the
/// exception text.

const _raw = 'SqliteException(14): unable to open database file';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('LoadErrorView', () {
    testWidgets('shows the message and Retry, not the error', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoadErrorView(
              message: "Couldn't load your garage",
              error: Exception(_raw),
              onRetry: () => retries++,
            ),
          ),
        ),
      );

      expect(find.text("Couldn't load your garage"), findsOneWidget);
      expect(find.textContaining('SqliteException'), findsNothing);

      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('compact form fits a section row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LoadErrorView(
                  message: "Couldn't load reminders",
                  error: Exception(_raw),
                  compact: true,
                  onRetry: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text("Couldn't load reminders"), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(find.textContaining('SqliteException'), findsNothing);
    });
  });

  group('screens', () {
    /// A vehicles stream that fails on first listen and succeeds after.
    Override failingOnce(List<int> attempts) {
      return vehiclesStreamProvider.overrideWith((ref) {
        attempts.add(attempts.length);
        if (attempts.length == 1) return Stream.error(Exception(_raw));
        return Stream.value(const <Vehicle>[]);
      });
    }

    testWidgets('garage list: friendly error, and Retry reloads', (
      tester,
    ) async {
      final attempts = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          // No automatic retries: this tests the Retry button itself.
          retry: (_, _) => null,
          overrides: [
            failingOnce(attempts),
            activeReminderRulesStreamProvider.overrideWith(
              (ref) => Stream.value(const <ReminderRule>[]),
            ),
          ],
          child: const MaterialApp(home: VehicleListScreen()),
        ),
      );
      await _settle(tester);

      expect(find.text("Couldn't load your garage"), findsOneWidget);
      expect(find.textContaining('SqliteException'), findsNothing);

      await tester.tap(find.text('Retry'));
      await _settle(tester);

      expect(attempts, hasLength(2));
      expect(find.text('Add your first vehicle'), findsOneWidget);
    });

    testWidgets('update odometers: friendly error, and Retry reloads', (
      tester,
    ) async {
      final attempts = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          // No automatic retries: this tests the Retry button itself.
          retry: (_, _) => null,
          overrides: [failingOnce(attempts)],
          child: const MaterialApp(home: UpdateOdometersScreen()),
        ),
      );
      await _settle(tester);

      expect(find.text("Couldn't load your vehicles"), findsOneWidget);
      expect(find.textContaining('SqliteException'), findsNothing);

      await tester.tap(find.text('Retry'));
      await _settle(tester);

      expect(attempts, hasLength(2));
      expect(find.text('No vehicles yet'), findsOneWidget);
    });
  });
}
