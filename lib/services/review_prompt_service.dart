import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows the system App Store rating prompt at most once per install.
class ReviewPromptService {
  static const _askedKey = 'asked_review';

  /// Never throws: a failed prompt must not surface to the user.
  Future<void> maybeRequestReview() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) ?? false) return;

      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;

      await review.requestReview();
      await prefs.setBool(_askedKey, true);
    } catch (error) {
      debugPrint('Review prompt failed: $error');
    }
  }
}

final reviewPromptServiceProvider = Provider<ReviewPromptService>(
  (ref) => ReviewPromptService(),
);
