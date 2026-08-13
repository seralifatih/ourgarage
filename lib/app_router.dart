import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';
import 'features/reminders/reminder_rule_form_screen.dart';
import 'features/reminders/update_odometers_screen.dart';
import 'features/reminders/vehicle_reminders_list_screen.dart';
import 'features/service_records/service_record_form_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/vehicles/vehicle_detail_screen.dart';
import 'features/vehicles/vehicle_form_screen.dart';
import 'features/vehicles/vehicle_list_screen.dart';

/// Placeholder for a screen that hasn't been built yet.
///
/// Keeps the routing graph complete and navigable so the wiring can be
/// exercised before every destination exists.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text('$title — coming soon', style: theme.textTheme.titleMedium),
      ),
    );
  }
}

final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: AppRoutes.vehicleList,
      builder: (context, state) => const VehicleListScreen(),
    ),
    // Declared before '/vehicle/:id' so the literal segment is not swallowed by
    // the parameterised route.
    GoRoute(
      path: AppRoutes.addVehicle,
      builder: (context, state) => const VehicleFormScreen(),
    ),
    GoRoute(
      path: '/vehicle/:id',
      builder: (context, state) =>
          VehicleDetailScreen(vehicleId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (context, state) =>
              VehicleFormScreen(vehicleId: state.pathParameters['id']),
        ),
        GoRoute(
          path: 'add-service',
          builder: (context, state) =>
              ServiceRecordFormScreen(vehicleId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'service/:recordId',
          builder: (context, state) => ServiceRecordFormScreen(
            vehicleId: state.pathParameters['id']!,
            recordId: state.pathParameters['recordId'],
          ),
        ),
        GoRoute(
          path: 'reminders',
          builder: (context, state) => VehicleRemindersListScreen(
            vehicleId: state.pathParameters['id']!,
          ),
          routes: [
            // Declared before ':ruleId' so 'new' is not swallowed by the
            // parameterised route.
            GoRoute(
              path: 'new',
              builder: (context, state) => ReminderRuleFormScreen(
                vehicleId: state.pathParameters['id']!,
              ),
            ),
            GoRoute(
              path: ':ruleId',
              builder: (context, state) => ReminderRuleFormScreen(
                vehicleId: state.pathParameters['id']!,
                ruleId: state.pathParameters['ruleId'],
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.updateOdometers,
      builder: (context, state) => const UpdateOdometersScreen(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.paywall,
      builder: (context, state) => const _PlaceholderScreen(title: 'Paywall'),
    ),
  ],
);
