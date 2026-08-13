import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/app.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';

import 'support/fake_notification_plugin.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseHolder.overrideWith(db);
  });

  tearDown(() async {
    DatabaseHolder.overrideWith(null);
    await db.close();
  });

  testWidgets('App starts on the garage list and shows the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fakeNotificationServiceOverride()],
        child: const OurGarageApp(),
      ),
    );

    // Not pumpAndSettle: the loading state's progress indicator animates
    // forever, so settling never completes. Pump until the stream delivers
    // its first value and the empty state replaces the spinner.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Add your first vehicle').evaluate().isNotEmpty) break;
    }

    expect(find.text('My Garage'), findsOneWidget);
    expect(find.text('Add your first vehicle'), findsOneWidget);

    // Tearing down the tree cancels drift's query streams, which schedule a
    // zero-duration cleanup timer. Drain it here so the binding doesn't report
    // it as a leaked pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
