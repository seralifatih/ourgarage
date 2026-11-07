import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'review_prompt_policy.dart';

export 'review_prompt_policy.dart' show ReviewTrigger;

/// The store-review plugin, behind a seam so the service can be tested.
abstract interface class ReviewStore {
  Future<bool> isAvailable();
  Future<void> requestReview();
}

class InAppReviewStore implements ReviewStore {
  const InAppReviewStore();

  @override
  Future<bool> isAvailable() => InAppReview.instance.isAvailable();

  @override
  Future<void> requestReview() => InAppReview.instance.requestReview();
}

/// Decides when to show the system App Store rating prompt.
///
/// [maybeRequestReview] is the only way features ask for a prompt. The rules
/// live in [ReviewPromptPolicy]; this class keeps the state they need (last
/// prompt, days opened, pending next-launch triggers, this session's bad
/// moment) and performs the one `requestReview()` call.
///
/// Apple decides whether the sheet actually appears, so a request is recorded
/// as a prompt whether or not the user saw it — that keeps the 90-day spacing
/// conservative. Never throws: a failed prompt must not surface to the user.
class ReviewPromptService {
  ReviewPromptService({
    ReviewStore store = const InAppReviewStore(),
    DateTime Function() clock = DateTime.now,
    Duration delay = ReviewPromptPolicy.promptDelay,
    Future<SharedPreferences> Function() preferences =
        SharedPreferences.getInstance,
    bool Function() isForeground = _appIsForeground,
  }) : _store = store,
       _now = clock,
       _delay = delay,
       _preferences = preferences,
       _isForeground = isForeground,
       _sessionStart = clock();

  final ReviewStore _store;
  final DateTime Function() _now;
  final Duration _delay;
  final Future<SharedPreferences> Function() _preferences;
  final bool Function() _isForeground;

  /// Unknown (null, before the first lifecycle event) counts as foreground.
  static bool _appIsForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// When this process started. A next-launch trigger recorded before it
  /// belongs to a previous session and may be acted on now.
  final DateTime _sessionStart;

  bool _badMoment = false;

  static const _lastPromptKey = 'review_last_prompt_at';
  static const _openDaysKey = 'review_open_days';
  static const _pendingTriggerKey = 'review_pending_trigger';
  static const _pendingAtKey = 'review_pending_at';

  /// The pre-policy flag: "asked once per install".
  static const _legacyAskedKey = 'asked_review';

  /// Whether this session already had a moment that rules out asking.
  bool get badMoment => _badMoment;

  /// Records an error, a failed or cancelled purchase, or a dismissed
  /// paywall. Blocks every prompt for the rest of this session.
  void markBadMoment() => _badMoment = true;

  /// The single entry point for asking. Returns whether the store prompt was
  /// requested.
  ///
  /// Immediate triggers wait [ReviewPromptPolicy.promptDelay] and then check
  /// the rules. Next-launch triggers are only stored here as pending; a later
  /// session's [recordAppOpen] prompts on the first launch the rules allow,
  /// within [ReviewPromptPolicy.pendingTriggerLifetime].
  Future<bool> maybeRequestReview(ReviewTrigger trigger) async {
    try {
      if (ReviewPromptPolicy.timingOf(trigger) ==
          ReviewTriggerTiming.nextLaunch) {
        final prefs = await _preferences();
        // Timestamp first: a trigger without one can't expire.
        await prefs.setString(_pendingAtKey, _now().toIso8601String());
        await prefs.setString(_pendingTriggerKey, trigger.name);
        return false;
      }
      return await _requestIfAllowed();
    } catch (error) {
      debugPrint('Review prompt failed: $error');
      return false;
    }
  }

  /// Counts today as a day the app was opened, then acts on a pending
  /// trigger left by a previous session. Call on launch and on resume.
  Future<bool> recordAppOpen() async {
    try {
      final prefs = await _preferences();
      final now = _now();

      // Users who were asked under the old "once per install" rule are
      // treated as asked today, so they wait the full 90 days.
      if ((prefs.getBool(_legacyAskedKey) ?? false) &&
          prefs.getString(_lastPromptKey) == null) {
        await prefs.setString(_lastPromptKey, now.toIso8601String());
      }
      await prefs.remove(_legacyAskedKey);

      final days = prefs.getStringList(_openDaysKey) ?? const <String>[];
      final updated = ReviewPromptPolicy.recordOpenDay(days, now);
      if (updated.length != days.length) {
        await prefs.setStringList(_openDaysKey, updated);
      }

      final pending = prefs.getString(_pendingTriggerKey);
      final pendingAt = DateTime.tryParse(prefs.getString(_pendingAtKey) ?? '');
      if (pending == null) return false;
      if (pendingAt == null) {
        // Half-written: it could never expire, so drop it.
        await _clearPending(prefs);
        return false;
      }
      // Never in the session that recorded it.
      if (!pendingAt.isBefore(_sessionStart)) return false;

      if (ReviewPromptPolicy.isPendingExpired(pendingAt, now: now)) {
        await _clearPending(prefs);
        return false;
      }

      // Stays pending until a launch where the rules allow a prompt; the
      // successful attempt clears it.
      return await _requestIfAllowed();
    } catch (error) {
      debugPrint('Review prompt failed: $error');
      return false;
    }
  }

  /// Waits for the triggering UI to settle, then asks if the rules allow it.
  ///
  /// Overlapping calls (launch and an immediate resume, or two triggers at
  /// once) share one attempt, so the store is never asked twice before the
  /// last-prompt time is written.
  Future<bool> _requestIfAllowed() {
    return _inFlight ??= _attempt().whenComplete(() => _inFlight = null);
  }

  Future<bool>? _inFlight;

  /// The rules are read after the delay, so a bad moment during it still
  /// blocks the prompt.
  Future<bool> _attempt() async {
    await Future<void>.delayed(_delay);

    // iOS silently drops a request from a backgrounded app; recording it as
    // a prompt would then cost the user 90 days for nothing.
    if (!_isForeground()) return false;

    final prefs = await _preferences();
    final now = _now();
    final snapshot = ReviewPromptSnapshot(
      lastPromptAt: DateTime.tryParse(prefs.getString(_lastPromptKey) ?? ''),
      distinctOpenDays: (prefs.getStringList(_openDaysKey) ?? const []).length,
      badMoment: _badMoment,
    );
    if (!ReviewPromptPolicy.mayPrompt(snapshot, now: now)) return false;
    if (!await _store.isAvailable()) return false;

    await _store.requestReview();
    await prefs.setString(_lastPromptKey, now.toIso8601String());
    // Whatever caused this prompt, a pending trigger has now been served:
    // left in place it could only wait out the 90-day gap and expire.
    await _clearPending(prefs);
    return true;
  }

  Future<void> _clearPending(SharedPreferences prefs) async {
    await prefs.remove(_pendingTriggerKey);
    await prefs.remove(_pendingAtKey);
  }
}

/// Kept alive for the app's lifetime: the bad-moment flag is per session,
/// so the instance must not be recreated mid-session.
final reviewPromptServiceProvider = Provider<ReviewPromptService>(
  (ref) => ReviewPromptService(),
);
