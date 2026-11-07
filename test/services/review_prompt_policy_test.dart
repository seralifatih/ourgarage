import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/services/review_prompt_policy.dart';

void main() {
  final now = DateTime(2026, 11, 7, 12);

  ReviewPromptSnapshot snapshot({
    DateTime? lastPromptAt,
    int distinctOpenDays = 3,
    bool badMoment = false,
  }) {
    return ReviewPromptSnapshot(
      lastPromptAt: lastPromptAt,
      distinctOpenDays: distinctOpenDays,
      badMoment: badMoment,
    );
  }

  group('90-day rule', () {
    test('the first prompt has no spacing condition', () {
      expect(ReviewPromptPolicy.mayPrompt(snapshot(), now: now), isTrue);
    });

    test('blocks a prompt 89 days after the last one', () {
      final last = now.subtract(const Duration(days: 89));
      expect(
        ReviewPromptPolicy.mayPrompt(snapshot(lastPromptAt: last), now: now),
        isFalse,
      );
    });

    test('allows a prompt exactly 90 days after the last one', () {
      final last = now.subtract(const Duration(days: 90));
      expect(
        ReviewPromptPolicy.mayPrompt(snapshot(lastPromptAt: last), now: now),
        isTrue,
      );
    });
  });

  group('3-day rule', () {
    test('blocks with only 2 distinct open days', () {
      expect(
        ReviewPromptPolicy.mayPrompt(snapshot(distinctOpenDays: 2), now: now),
        isFalse,
      );
    });

    test('allows with 3 distinct open days', () {
      expect(
        ReviewPromptPolicy.mayPrompt(snapshot(distinctOpenDays: 3), now: now),
        isTrue,
      );
    });

    test('several opens on the same day count once', () {
      var days = <String>[];
      days = ReviewPromptPolicy.recordOpenDay(days, DateTime(2026, 11, 1, 8));
      days = ReviewPromptPolicy.recordOpenDay(days, DateTime(2026, 11, 1, 22));
      expect(days, hasLength(1));

      days = ReviewPromptPolicy.recordOpenDay(days, DateTime(2026, 11, 2, 9));
      days = ReviewPromptPolicy.recordOpenDay(days, DateTime(2026, 11, 5, 9));
      expect(days, hasLength(3));
    });

    test('stops storing days once the threshold is reached', () {
      var days = <String>[];
      for (var d = 1; d <= 10; d++) {
        days = ReviewPromptPolicy.recordOpenDay(days, DateTime(2026, 10, d));
      }
      expect(days, hasLength(ReviewPromptPolicy.minDistinctOpenDays));
    });
  });

  group('bad moment', () {
    test('blocks even when every other condition holds', () {
      expect(
        ReviewPromptPolicy.mayPrompt(snapshot(badMoment: true), now: now),
        isFalse,
      );
    });
  });

  group('pending lifetime', () {
    final pendingAt = DateTime(2026, 10, 1, 9);

    test('is still valid exactly 30 days later', () {
      expect(
        ReviewPromptPolicy.isPendingExpired(
          pendingAt,
          now: pendingAt.add(const Duration(days: 30)),
        ),
        isFalse,
      );
    });

    test('expires after 30 days', () {
      expect(
        ReviewPromptPolicy.isPendingExpired(
          pendingAt,
          now: pendingAt.add(const Duration(days: 30, minutes: 1)),
        ),
        isTrue,
      );
    });
  });

  group('trigger timing', () {
    test('service-record moments ask right away', () {
      expect(
        ReviewPromptPolicy.timingOf(ReviewTrigger.firstServiceRecord),
        ReviewTriggerTiming.immediate,
      );
      expect(
        ReviewPromptPolicy.timingOf(ReviewTrigger.dueReminderCompleted),
        ReviewTriggerTiming.immediate,
      );
    });

    test('purchase and household moments wait for the next launch', () {
      for (final trigger in [
        ReviewTrigger.purchaseCompleted,
        ReviewTrigger.householdJoined,
        ReviewTrigger.inviteShared,
      ]) {
        expect(
          ReviewPromptPolicy.timingOf(trigger),
          ReviewTriggerTiming.nextLaunch,
          reason: trigger.name,
        );
      }
    });
  });
}
