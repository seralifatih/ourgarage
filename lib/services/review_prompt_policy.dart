/// Pure rules for when the App Store rating prompt may be shown.
///
/// No Flutter, plugin or storage imports: every input arrives as a plain
/// value, so the rules are unit-testable on their own. [ReviewPromptService]
/// owns the state and the side effects; this decides.
library;

/// The moments that are allowed to ask for a review. Nothing else may.
enum ReviewTrigger {
  /// The very first service record was saved.
  firstServiceRecord,

  /// A service record was saved that completed a reminder that was due.
  dueReminderCompleted,

  /// A premium purchase completed. Asks on a later launch where the rules
  /// allow it, never at the moment of purchase.
  purchaseCompleted,

  /// This user joined a household with an invite code. Later launch.
  householdJoined,

  /// This user shared their household's invite code. Later launch.
  inviteShared,
}

/// When a trigger is allowed to turn into a prompt.
enum ReviewTriggerTiming {
  /// Right after the interaction that caused it finishes.
  immediate,

  /// Kept pending, and asked on the first later launch where the rules allow
  /// it — never in the same session, and not after
  /// [ReviewPromptPolicy.pendingTriggerLifetime].
  nextLaunch,
}

/// The decision inputs, as stored between launches.
class ReviewPromptSnapshot {
  const ReviewPromptSnapshot({
    required this.lastPromptAt,
    required this.distinctOpenDays,
    required this.badMoment,
  });

  /// When the prompt was last requested, or null if it never has been.
  final DateTime? lastPromptAt;

  /// How many different calendar days the app has been opened on.
  final int distinctOpenDays;

  /// Whether this session already had an error, a failed or cancelled
  /// purchase, or a dismissed paywall.
  final bool badMoment;
}

abstract final class ReviewPromptPolicy {
  /// Minimum gap between two prompts. Doesn't apply to the first one.
  static const int minDaysBetweenPrompts = 90;

  /// The app must have been opened on at least this many different days.
  static const int minDistinctOpenDays = 3;

  /// How long after the triggering interaction the prompt is requested, so
  /// it never lands on top of a closing screen or a running animation.
  static const Duration promptDelay = Duration(seconds: 1);

  static ReviewTriggerTiming timingOf(ReviewTrigger trigger) {
    return switch (trigger) {
      ReviewTrigger.firstServiceRecord ||
      ReviewTrigger.dueReminderCompleted => ReviewTriggerTiming.immediate,
      ReviewTrigger.purchaseCompleted ||
      ReviewTrigger.householdJoined ||
      ReviewTrigger.inviteShared => ReviewTriggerTiming.nextLaunch,
    };
  }

  /// Whether a prompt may be requested now. All conditions must hold.
  static bool mayPrompt(ReviewPromptSnapshot state, {required DateTime now}) {
    if (state.badMoment) return false;
    if (state.distinctOpenDays < minDistinctOpenDays) return false;

    final last = state.lastPromptAt;
    if (last == null) return true;
    return now.difference(last).inDays >= minDaysBetweenPrompts;
  }

  /// How long a next-launch trigger waits for a launch where the rules allow
  /// a prompt. After this it is dropped: a rating request weeks after the
  /// purchase or join no longer follows from it.
  static const Duration pendingTriggerLifetime = Duration(days: 30);

  /// Whether a pending trigger recorded at [pendingAt] has expired.
  static bool isPendingExpired(DateTime pendingAt, {required DateTime now}) {
    return now.difference(pendingAt) > pendingTriggerLifetime;
  }

  /// The calendar-day key an app open is counted under, in local time.
  static String dayKey(DateTime time) {
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  /// Adds today's [now] to [days], returning the updated distinct set.
  ///
  /// Capped at [minDistinctOpenDays] entries: once the threshold is reached
  /// it can never be un-reached, so storing more days would only grow the
  /// preference without changing any decision.
  static List<String> recordOpenDay(List<String> days, DateTime now) {
    final key = dayKey(now);
    if (days.contains(key) || days.length >= minDistinctOpenDays) return days;
    return [...days, key];
  }
}
