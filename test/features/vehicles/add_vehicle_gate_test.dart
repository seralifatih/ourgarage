import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ourgarage/app_routes.dart';
import 'package:ourgarage/data/local/database.dart';
import 'package:ourgarage/data/repositories/database_holder.dart';
import 'package:ourgarage/data/repositories/premium_status_provider.dart';
import 'package:ourgarage/features/vehicles/vehicle_list_screen.dart';

/// Audit #4: the free-tier limit is checked where "Add vehicle" is tapped,
/// before the form opens, so nobody fills in a form only to lose it to the
/// paywall on Save.

/// Stand-in paywall: records that it opened, and can "buy" Premium.
class _PaywallStub extends ConsumerWidget {
  const _PaywallStub();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: [
          const Text('PAYWALL'),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Close paywall'),
          ),
          TextButton(
            onPressed: () {
              ref.read(_premium.notifier).state = true;
              context.pop();
            },
            child: const Text('Buy'),
          ),
        ],
      ),
    );
  }
}

class _PremiumFlag extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

final _premium = NotifierProvider<_PremiumFlag, bool>(_PremiumFlag.new);

Future<GoRouter> _pumpList(WidgetTester tester, {bool premium = false}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: AppRoutes.vehicleList,
        builder: (_, _) => const VehicleListScreen(),
      ),
      GoRoute(
        path: AppRoutes.addVehicle,
        builder: (_, _) => const Scaffold(body: Text('ADD FORM')),
      ),
      GoRoute(
        path: AppRoutes.paywall,
        builder: (_, _) => const _PaywallStub(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        premiumStatusProvider.overrideWith(
          (ref) => premium || ref.watch(_premium),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
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

  Future<void> insertVehicle() {
    final now = DateTime(2026, 1, 1);
    return db
        .into(db.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'existing',
            nickname: 'Old Truck',
            odometerUnit: 'km',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> tapAddVehicle(WidgetTester tester) async {
    await tester.tap(find.text('Add vehicle'));
    await _settle(tester);
  }

  testWidgets('empty garage: Add vehicle opens the form', (tester) async {
    await _pumpList(tester);

    await tapAddVehicle(tester);

    expect(find.text('ADD FORM'), findsOneWidget);
    expect(find.text('PAYWALL'), findsNothing);
    await _drainPendingTimers(tester);
  });

  testWidgets('at the free limit: the paywall opens instead of the form', (
    tester,
  ) async {
    await insertVehicle();
    await _pumpList(tester);

    await tapAddVehicle(tester);

    expect(find.text('PAYWALL'), findsOneWidget);
    expect(find.text('ADD FORM'), findsNothing);
    await _drainPendingTimers(tester);
  });

  testWidgets('closing the paywall returns to the garage, no form', (
    tester,
  ) async {
    await insertVehicle();
    await _pumpList(tester);
    await tapAddVehicle(tester);

    await tester.tap(find.text('Close paywall'));
    await _settle(tester);

    expect(find.text('My Garage'), findsOneWidget);
    expect(find.text('ADD FORM'), findsNothing);
    await _drainPendingTimers(tester);
  });

  testWidgets('buying on the paywall continues straight to the form', (
    tester,
  ) async {
    await insertVehicle();
    await _pumpList(tester);
    await tapAddVehicle(tester);

    await tester.tap(find.text('Buy'));
    await _settle(tester);

    expect(find.text('ADD FORM'), findsOneWidget);
    await _drainPendingTimers(tester);
  });

  testWidgets('Premium at the limit: the form opens directly', (tester) async {
    await insertVehicle();
    await _pumpList(tester, premium: true);

    await tapAddVehicle(tester);

    expect(find.text('ADD FORM'), findsOneWidget);
    expect(find.text('PAYWALL'), findsNothing);
    await _drainPendingTimers(tester);
  });
}
