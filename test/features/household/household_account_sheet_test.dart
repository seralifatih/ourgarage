import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/features/household/widgets/household_account_sheet.dart';
import 'package:ourgarage/services/auth_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

Future<void> _pumpSheet(
  WidgetTester tester,
  Future<SignInResult?> Function() signIn,
) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: HouseholdAccountSheet<SignInResult>(
            signIn: signIn,
            headline: 'Share your garage',
            explainer: 'Explainer',
            dataPoint: 'Data point',
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'a household failure says so, rather than "Could not sign in"',
    (tester) async {
      await _pumpSheet(
        tester,
        () async => throw HouseholdSetupException(Exception('42501')),
      );

      await tester.tap(find.byType(SignInWithAppleButton));
      await tester.pumpAndSettle();

      expect(
        find.text(const HouseholdSetupException('x').message),
        findsOneWidget,
      );
      expect(find.textContaining('Could not sign in'), findsNothing);
    },
  );

  testWidgets('an unexpected sign-in failure keeps the generic message', (
    tester,
  ) async {
    await _pumpSheet(tester, () async => throw StateError('boom'));

    await tester.tap(find.byType(SignInWithAppleButton));
    await tester.pumpAndSettle();

    expect(find.text('Could not sign in. Please try again.'), findsOneWidget);
  });
}
