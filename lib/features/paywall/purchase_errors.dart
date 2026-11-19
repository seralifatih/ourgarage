import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../services/feedback_email.dart';

/// Shown when a purchase is waiting on someone else, typically Ask to Buy:
/// not an error, and not finished either.
const purchasePendingMessage =
    'Waiting for approval. Premium unlocks as soon as the purchase is '
    'approved.';

/// The RevenueCat error code in [error], or null when it carries none.
///
/// `PurchasesErrorHelper.getErrorCode` parses the code with `num.parse` and
/// throws on anything non-numeric, which a plugin-level PlatformException can
/// have.
PurchasesErrorCode? purchasesErrorCodeOf(Object error) {
  if (error is! PlatformException) return null;
  try {
    return PurchasesErrorHelper.getErrorCode(error);
  } on FormatException {
    return null;
  }
}

/// Whether [error] means the purchase went through but awaits approval.
bool isPurchasePending(Object error) =>
    purchasesErrorCodeOf(error) == PurchasesErrorCode.paymentPendingError;

/// What to tell the user about a failed purchase or restore.
///
/// Common, actionable cases get a plain sentence of their own; anything else
/// keeps the store's own message when there is one, since that is usually the
/// most specific thing available.
String purchaseErrorMessage(Object error, {required bool restoring}) {
  switch (purchasesErrorCodeOf(error)) {
    case PurchasesErrorCode.paymentPendingError:
      return purchasePendingMessage;
    case PurchasesErrorCode.networkError:
      return 'Couldn’t reach the App Store. Check your connection and try '
          'again.';
    case PurchasesErrorCode.purchaseNotAllowedError:
      return 'Purchases aren’t allowed on this device. Check Screen Time '
          'restrictions in Settings.';
    case PurchasesErrorCode.productAlreadyPurchasedError:
      return 'You already own this. Tap Restore purchases to unlock it.';
    default:
      break;
  }

  if (error is PlatformException) {
    final message = error.message;
    if (message != null && message.trim().isNotEmpty) return message;
  }
  return restoring
      ? 'Could not restore purchases. Please try again.'
      : 'The purchase didn’t go through. Please try again.';
}

/// Reports a failed purchase or restore, with a "Message me" action that
/// opens an email to support carrying the error code.
void showPurchaseError(
  ScaffoldMessengerState messenger,
  Object error, {
  required bool restoring,
}) {
  final code = error is PlatformException ? error.code : error.runtimeType;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(purchaseErrorMessage(error, restoring: restoring)),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Message me',
          onPressed: () => openFeedbackEmail(
            messenger,
            subject: restoring
                ? 'OurGarage restore problem'
                : 'OurGarage purchase problem',
            details: 'Error: $code',
          ),
        ),
      ),
    );
}

/// Reports a purchase that is waiting for approval.
void showPurchasePending(ScaffoldMessengerState messenger) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text(purchasePendingMessage),
        duration: Duration(seconds: 8),
      ),
    );
}
