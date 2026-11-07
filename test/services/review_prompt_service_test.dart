import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/services/review_prompt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStore implements ReviewStore {
  int requests = 0;
  bool available = true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requests++;
}

void main() {
  late _FakeStore store;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _FakeStore();
    now = DateTime(2026, 11, 1, 10);
  });

  /// A new service is a new app session (process), starting at [now].
  ReviewPromptService session({bool foreground = true}) => ReviewPromptService(
    store: store,
    clock: () => now,
    delay: Duration.zero,
    isForeground: () => foreground,
  );

  /// Whether a next-launch trigger is stored. Read directly: the 30-day
  /// lifetime is shorter than the 90-day gap, so "cleared" can't be told apart
  /// from "expired" through behaviour alone.
  Future<bool> hasPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('review_pending_trigger') != null ||
        prefs.getString('review_pending_at') != null;
  }

  /// Opens the app on three different days, ending a session on each.
  Future<void> openOnThreeDays() async {
    for (var i = 0; i < 3; i++) {
      await session().recordAppOpen();
      now = now.add(const Duration(days: 1));
    }
  }

  group('immediate triggers', () {
    test('firstServiceRecord prompts once the rules allow it', () async {
      await openOnThreeDays();
      final service = session();

      expect(
        await service.maybeRequestReview(ReviewTrigger.firstServiceRecord),
        isTrue,
      );
      expect(store.requests, 1);
    });

    test('dueReminderCompleted prompts once the rules allow it', () async {
      await openOnThreeDays();

      expect(
        await session().maybeRequestReview(ReviewTrigger.dueReminderCompleted),
        isTrue,
      );
      expect(store.requests, 1);
    });

    test('does not prompt before the app was opened on 3 days', () async {
      await session().recordAppOpen();
      now = now.add(const Duration(days: 1));
      await session().recordAppOpen();

      expect(
        await session().maybeRequestReview(ReviewTrigger.firstServiceRecord),
        isFalse,
      );
      expect(store.requests, 0);
    });

    test('does not prompt twice within 90 days', () async {
      await openOnThreeDays();
      await session().maybeRequestReview(ReviewTrigger.firstServiceRecord);

      now = now.add(const Duration(days: 89));
      expect(
        await session().maybeRequestReview(ReviewTrigger.dueReminderCompleted),
        isFalse,
      );

      now = now.add(const Duration(days: 1));
      expect(
        await session().maybeRequestReview(ReviewTrigger.dueReminderCompleted),
        isTrue,
      );
      expect(store.requests, 2);
    });

    test('a bad moment blocks prompts for the rest of the session', () async {
      await openOnThreeDays();
      final service = session()..markBadMoment();

      expect(
        await service.maybeRequestReview(ReviewTrigger.firstServiceRecord),
        isFalse,
      );
      expect(store.requests, 0);

      // The flag is per session: the next launch starts clean.
      expect(
        await session().maybeRequestReview(ReviewTrigger.firstServiceRecord),
        isTrue,
      );
    });

    test('a bad moment during the delay still blocks the prompt', () async {
      await openOnThreeDays();
      final service = ReviewPromptService(
        store: store,
        clock: () => now,
        delay: const Duration(milliseconds: 20),
        isForeground: () => true,
      );

      final result = service.maybeRequestReview(
        ReviewTrigger.firstServiceRecord,
      );
      service.markBadMoment();

      expect(await result, isFalse);
      expect(store.requests, 0);
    });

    test('overlapping triggers ask the store only once', () async {
      await openOnThreeDays();
      final service = session();

      final results = await Future.wait([
        service.maybeRequestReview(ReviewTrigger.firstServiceRecord),
        service.maybeRequestReview(ReviewTrigger.dueReminderCompleted),
      ]);

      expect(results, [isTrue, isTrue]);
      expect(store.requests, 1);
    });

    test(
      'a backgrounded app is not prompted, and it is not recorded',
      () async {
        await openOnThreeDays();

        expect(
          await session(
            foreground: false,
          ).maybeRequestReview(ReviewTrigger.firstServiceRecord),
          isFalse,
        );
        expect(store.requests, 0);

        // Not counted as a prompt, so the 90-day gap didn't start.
        expect(
          await session().maybeRequestReview(ReviewTrigger.firstServiceRecord),
          isTrue,
        );
      },
    );

    test('nothing is requested when the store is unavailable', () async {
      await openOnThreeDays();
      store.available = false;

      expect(
        await session().maybeRequestReview(ReviewTrigger.firstServiceRecord),
        isFalse,
      );
      expect(store.requests, 0);
    });
  });

  group('next-launch triggers', () {
    for (final trigger in [
      ReviewTrigger.purchaseCompleted,
      ReviewTrigger.householdJoined,
      ReviewTrigger.inviteShared,
    ]) {
      test('${trigger.name} never prompts in the same session', () async {
        await openOnThreeDays();
        final service = session();

        expect(await service.maybeRequestReview(trigger), isFalse);
        // A resume in the same session does not count as the next launch.
        expect(await service.recordAppOpen(), isFalse);
        expect(store.requests, 0);
      });

      test('${trigger.name} prompts on the next launch, once', () async {
        await openOnThreeDays();
        await session().maybeRequestReview(trigger);

        expect(await hasPending(), isTrue);

        now = now.add(const Duration(hours: 1));
        expect(await session().recordAppOpen(), isTrue);
        expect(store.requests, 1);

        // Cleared once shown.
        expect(await hasPending(), isFalse);
      });
    }

    test('stays pending until the first launch the rules allow', () async {
      // Day 1: the only open day so far, so no launch can prompt yet.
      await session().recordAppOpen();
      await session().maybeRequestReview(ReviewTrigger.purchaseCompleted);

      // Day 2: still only 2 open days. Rules say no; the trigger is kept.
      now = now.add(const Duration(days: 1));
      expect(await session().recordAppOpen(), isFalse);
      expect(store.requests, 0);

      // Day 3: third open day. Prompts now.
      now = now.add(const Duration(days: 1));
      expect(await session().recordAppOpen(), isTrue);
      expect(store.requests, 1);
    });

    test('a bad moment on a launch keeps it pending for the next', () async {
      await openOnThreeDays();
      await session().maybeRequestReview(ReviewTrigger.householdJoined);

      now = now.add(const Duration(hours: 1));
      final blocked = session()..markBadMoment();
      expect(await blocked.recordAppOpen(), isFalse);

      now = now.add(const Duration(hours: 1));
      expect(await session().recordAppOpen(), isTrue);
      expect(store.requests, 1);
    });

    test('is dropped after 30 days without a prompt', () async {
      await session().recordAppOpen();
      await session().maybeRequestReview(ReviewTrigger.purchaseCompleted);

      // 31 days later the rules would allow it, but it has expired.
      now = now.add(const Duration(days: 30));
      await session().recordAppOpen();
      now = now.add(const Duration(days: 1));
      expect(await session().recordAppOpen(), isFalse);
      expect(store.requests, 0);

      // Removed, not merely skipped.
      expect(await hasPending(), isFalse);
    });

    test('a backgrounded launch keeps it pending', () async {
      await openOnThreeDays();
      await session().maybeRequestReview(ReviewTrigger.purchaseCompleted);

      now = now.add(const Duration(hours: 1));
      expect(await session(foreground: false).recordAppOpen(), isFalse);
      expect(await hasPending(), isTrue);

      now = now.add(const Duration(hours: 1));
      expect(await session().recordAppOpen(), isTrue);
    });

    test('a pending trigger without a timestamp is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'review_pending_trigger': 'purchaseCompleted',
      });

      expect(await session().recordAppOpen(), isFalse);
      expect(await hasPending(), isFalse);
    });

    test('still prompts on day 30', () async {
      await session().recordAppOpen();
      await session().maybeRequestReview(ReviewTrigger.purchaseCompleted);

      now = now.add(const Duration(days: 29));
      await session().recordAppOpen();
      now = now.add(const Duration(days: 1));
      expect(await session().recordAppOpen(), isTrue);
    });

    test('a prompt from another trigger clears it', () async {
      await openOnThreeDays();
      final service = session();
      await service.maybeRequestReview(ReviewTrigger.purchaseCompleted);
      expect(await hasPending(), isTrue);
      expect(
        await service.maybeRequestReview(ReviewTrigger.firstServiceRecord),
        isTrue,
      );

      expect(await hasPending(), isFalse);
    });
  });

  test(
    'a user asked under the old once-per-install flag waits 90 days',
    () async {
      SharedPreferences.setMockInitialValues({'asked_review': true});
      // Migration runs on this first open, which counts as "asked today".
      final migratedAt = now;
      await openOnThreeDays();

      now = migratedAt.add(const Duration(days: 89));
      expect(
        await session().maybeRequestReview(ReviewTrigger.firstServiceRecord),
        isFalse,
      );

      now = migratedAt.add(const Duration(days: 90));
      expect(
        await session().maybeRequestReview(ReviewTrigger.firstServiceRecord),
        isTrue,
      );
    },
  );
}
