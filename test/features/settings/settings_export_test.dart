import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/app_routes.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/data/repositories/premium_status_provider.dart';
import 'package:ourgarage/features/export/export_service.dart';
import 'package:ourgarage/features/settings/settings_screen.dart';

import '../../support/fake_notification_plugin.dart';
import '../../support/fake_purchases_api.dart';

/// Records what the Settings row asks the export service to do, without
/// touching the file system or the share sheet.
class FakeExportService implements ExportService {
  FakeExportService(this.db, {this.fail = false});

  @override
  final AppDatabase db;
  final bool fail;
  final calls = <String>[];

  @override
  ExportSharer get sharer => throw UnimplementedError();

  @override
  Future<List<Vehicle>> vehicles() => db.vehicleDao.getAllVehicles();

  @override
  Future<File> shareRecordsCsv({Rect? origin}) async {
    calls.add('csv');
    if (fail) throw StateError('disk full');
    return File('records.csv');
  }

  @override
  Future<File> shareServiceHistoryPdf(Vehicle vehicle, {Rect? origin}) async {
    calls.add('pdf:${vehicle.nickname}');
    return File('history.pdf');
  }
}

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

  Future<void> insertVehicle(String id, String nickname) {
    return db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: id,
            nickname: nickname,
            odometerUnit: 'mi',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets real async work (drift queries) complete outside the fake clock.
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
  }

  Future<void> pump(
    WidgetTester tester, {
    required bool premium,
    required FakeExportService export,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: AppRoutes.paywall,
          builder: (_, _) => const Scaffold(body: Text('paywall stub')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeNotificationServiceOverride(null),
          fakePurchaseServiceOverride(null),
          premiumStatusProvider.overrideWith((ref) => premium),
          exportServiceProvider.overrideWithValue(export),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('without Premium the row is shown and opens the paywall', (
    tester,
  ) async {
    final export = FakeExportService(db);
    await pump(tester, premium: false, export: export);

    expect(find.text('Export records'), findsOneWidget);
    expect(find.textContaining('Premium: CSV'), findsOneWidget);

    await tester.tap(find.text('Export records'));
    await settle(tester);

    expect(find.text('paywall stub'), findsOneWidget);
    expect(export.calls, isEmpty);
    await drain(tester);
  });

  testWidgets('with Premium and no vehicles it says there is nothing yet', (
    tester,
  ) async {
    await pump(tester, premium: true, export: FakeExportService(db));

    await tester.tap(find.text('Export records'));
    await flush(tester);

    expect(
      find.text('Nothing to export yet. Add a vehicle first.'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('offers the CSV and one PDF per vehicle, and exports the CSV', (
    tester,
  ) async {
    await insertVehicle('a', 'Blue Civic');
    await insertVehicle('b', 'Red Golf');
    final export = FakeExportService(db);
    await pump(tester, premium: true, export: export);

    await tester.tap(find.text('Export records'));
    await flush(tester);

    expect(find.text('All records (CSV)'), findsOneWidget);
    expect(find.text('Service history (PDF)'), findsOneWidget);
    expect(find.text('Blue Civic'), findsOneWidget);
    expect(find.text('Red Golf'), findsOneWidget);

    await tester.tap(find.text('All records (CSV)'));
    await flush(tester);

    expect(export.calls, ['csv']);
    await drain(tester);
  });

  testWidgets('exports the PDF for the chosen vehicle', (tester) async {
    await insertVehicle('a', 'Blue Civic');
    await insertVehicle('b', 'Red Golf');
    final export = FakeExportService(db);
    await pump(tester, premium: true, export: export);

    await tester.tap(find.text('Export records'));
    await flush(tester);
    await tester.tap(find.text('Red Golf'));
    await flush(tester);

    expect(export.calls, ['pdf:Red Golf']);
    await drain(tester);
  });

  testWidgets('a failed export shows an error instead of crashing', (
    tester,
  ) async {
    await insertVehicle('a', 'Blue Civic');
    final export = FakeExportService(db, fail: true);
    await pump(tester, premium: true, export: export);

    await tester.tap(find.text('Export records'));
    await flush(tester);
    await tester.tap(find.text('All records (CSV)'));
    await flush(tester);

    expect(
      find.text('Could not export your records. Please try again.'),
      findsOneWidget,
    );
    await drain(tester);
  });
}
