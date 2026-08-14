# Pre-submission checklist

Everything here must be checked against the actual build going up, not against
what the code is supposed to do. Two items below were found to be **not yet
true** while drafting this list — they're marked accordingly, not just listed
as generic boilerplate.

Deployment target is confirmed at **iOS 15.0** (`ios/Runner.xcodeproj`,
`ios/Podfile`) — not iOS 13, which this checklist was originally scoped
against. See the note under "Crash-free launch" for what that changes.

---

## App icon and launch screen

- [ ] `ios/Runner/Assets.xcassets/AppIcon.appiconset/` contains all 15 required
      sizes and `Contents.json` references every one of them (verify with
      `xcrun` or by opening the asset catalog in Xcode — a missing size fails
      the archive step, a wrong size passes the build but fails App Store
      validation).
- [ ] The 1024×1024 marketing icon (`Icon-App-1024x1024@1x.png`) has **no
      alpha channel** — App Store Connect rejects a marketing icon with
      transparency.
- [ ] Icon has no placeholder art, no Flutter default, no visible padding
      inconsistency against Apple's rounded-corner mask.
- [ ] `ios/Runner/Base.lproj/LaunchScreen.storyboard` renders correctly on
      the smallest supported screen (iPhone SE / iPhone 8 form factor) and the
      largest (iPhone 16 Pro Max) — a launch screen built once at one
      simulator size can clip or letterbox at the other extreme.
- [ ] Launch screen matches the first frame of the real app closely enough
      that there's no visible flash/swap on cold start.

## Screenshots

- [ ] A screenshot set exists for **every device size class Apple currently
      requires** for this app's supported orientations — at minimum the
      6.9" and 6.5" iPhone sizes, plus iPad sizes if the app is
      iPad-compatible (`TARGETED_DEVICE_FAMILY` in the Xcode project —
      confirm whether this ships as iPhone-only or universal before assuming
      iPad screenshots aren't needed).
- [ ] **At least two screenshots explicitly show household sharing** — not
      implied, not a settings toggle in the background, but the actual
      shared-garage moment (per the drafted set in
      `store/app_store_listing_us.md`: screenshot 1, "two phones, same
      garage," and screenshot 2, the invite/members screen). This is the
      guideline-4.3 differentiation argument — if the screenshots don't carry
      it, the description alone is not reliably enough.
- [ ] Screenshots are taken from the **actual build being submitted**, not an
      older build or a design mock — text, icons, and the household-sharing
      UI must match what a reviewer installs.
- [ ] No status bar showing low battery, no signal, or a debug banner in any
      screenshot.

## Legal URLs

- [x] **`store/legal/terms.md` and `store/legal/privacy.md` written this
      session**, matching the `noktastudio.dev` hosting target and the app's
      actual behavior. **Found and fixed two overstatements in the earlier
      drafts**: they had claimed in-app account deletion and data export
      exist. Neither is built. Both documents now say so explicitly instead
      of implying a feature that isn't there — this is a real gap, not just a
      documentation fix, and it's the honest current answer for the
      account-deletion requirement below.
- [ ] `https://noktastudio.dev/ourgarage/terms` is **live and returns 200**,
      not a 404 or a placeholder page — verify by curling it, not by trusting
      the constant in `lib/core/constants.dart`. **Not yet hosted — this is
      still local markdown, nobody has published it to the domain.**
- [ ] `https://noktastudio.dev/ourgarage/privacy` is live and returns 200.
      **Same — not yet hosted.**
- [ ] Both pages are reachable **without authentication** and without a
      redirect chain that a reviewer's automated check might not follow.
- [ ] The content hosted matches `store/legal/terms.md` and
      `store/legal/privacy.md` — i.e., the published page was actually updated
      from those drafts, not left as a stub.
- [ ] Both URLs are entered in App Store Connect's app metadata (Terms of Use
      / Privacy Policy fields), not only linked from inside the app.
- [ ] The in-app links (`PaywallScreen`'s Terms/Privacy buttons) open the same
      URLs and actually launch — test on-device, since `url_launcher` can fail
      silently in a way that only shows up at runtime.

## Restore Purchases

- [x] **Audited this session.** Present and reachable without an active
      subscription (`settings_screen.dart`, `paywall_screen.dart`). Traced the
      full chain: `PurchaseService._publish` → entitlement stream →
      `premiumStatusProvider` — confirmed the UI (premium status, vehicle
      limit) updates without an app restart, no stale-cache bug found.
- [ ] Tapping it with **no prior purchase** shows a clear "nothing to
      restore" state, not a silent no-op or a crash.
- [ ] Tapping it **with** a prior purchase on the same Apple ID actually
      restores entitlement and updates the UI (premium status, unlocked
      vehicle limit) without requiring an app restart.
- [ ] Test this on a **sandbox tester account** that has a real prior sandbox
      purchase — not just that the button exists, but that the round trip to
      RevenueCat/StoreKit actually completes.
- [x] **Confirmed no sandbox/production branching exists anywhere in the
      codebase** — grepped for `sandbox`, `Environment.`, `StoreEnvironment`;
      RevenueCat resolves this transparently as expected.
- [x] **Added a debug toggle** (`PurchaseService.debugForceNoOfferings`,
      `kDebugMode`-gated, plus a Settings debug row) so the "no offering
      available" paywall fallback can be verified on-device without airplane
      mode aborting an in-flight sandbox purchase.
- [x] **RevenueCat `appUserID` bug fixed and verified.**
      `lib/services/revenuecat_identity_sync.dart` now calls
      `Purchases.logIn(supabaseUserId)` on sign-in (including a session
      already restored at app launch, via `fireImmediately: true`) and
      `Purchases.logOut()` on sign-out, so
      `supabase/functions/revenuecat-webhook/index.ts`'s `event.app_user_id`
      now matches a `household_members.user_id` row on a real purchase.
      Verified: RevenueCat's documented anonymous-purchase merge behavior
      (a free-tier-only lifetime purchase made before the user ever signs in
      is not orphaned) explicitly by test, not assumed — see
      `test/services/purchase_service_test.dart`. The Riverpod bridge itself,
      including the boot-time "already signed in" case, is covered by
      `test/services/revenuecat_identity_sync_test.dart`. The one leg that
      cannot be a Dart test — RevenueCat's server actually putting the
      Supabase user ID in a real webhook POST — is a documented manual
      verification step in `store/privacy_nutrition_label.md`
      ("Fixed: RevenueCat customer identity now follows the Supabase user");
      **that manual check against a live RevenueCat/Supabase project is still
      outstanding and should be done before trusting the webhook with a real
      transaction.** See `store/privacy_nutrition_label.md` for the full
      writeup, including the now-updated ASC answer for Purchase History →
      "linked to identity" (**Yes**).

## Notification permission timing

- [ ] Confirmed in code: `NotificationPermissionSheet` is triggered from
      `reminder_rule_form_screen.dart` on first reminder creation, **not**
      from `main.dart` or app launch. Re-verify this hasn't regressed —
      grep for any new call site of `requestPermissions()` before submitting.
- [ ] Fresh-install test: launch the app, do nothing that creates a reminder,
      confirm **no system permission dialog appears** at any point during
      onboarding.
- [ ] The explainer sheet's copy accurately describes what the permission is
      for before the system dialog appears (context-then-ask, not
      ask-then-explain).
- [ ] Declining the permission doesn't break reminder creation — the reminder
      still saves, it just won't notify.

## Paywall

- [ ] Close/dismiss control is visible on the **first frame**, not after a
      delay, not hidden behind a scroll — this is guideline 3.1.2 /
      design-rejection territory and was a deliberate build requirement
      (`PaywallScreen`'s `leading: IconButton` in the AppBar).
- [ ] Dismissing the paywall from **every entry point** (vehicle limit hit,
      locked cost field, Settings row, "Share with household") returns the
      user to a sane screen, not a crash or a blank route — confirmed
      `_close()` falls back to the vehicle list when there's nothing to pop;
      re-test each entry point manually since this is exactly the kind of
      navigation edge case unit tests can miss.
- [x] **Re-audited this session, zero hardcoded price strings found.** Grepped
      `9.99`, `4.99`, `$9`, `$4` across `lib/features/paywall/`,
      `lib/features/settings/`, and all of `lib/` — no matches anywhere. Both
      price displays go through `storeProduct.priceString` exactly as
      intended.
- [ ] Prices shown on-device match what's configured in App Store Connect for
      **the storefront the test device is on** — test on a sandbox account
      with a non-US Apple ID region at least once, since this is the actual
      point of pulling from RevenueCat instead of hardcoding.
- [ ] The "no offering available" fallback state (`lifetime == null && annual
      == null` in `PaywallScreen`) has been seen at least once on a real
      device with network disabled, not just reasoned about — confirm it
      doesn't look broken.

## In-App Purchase products

- [ ] Both `ourgarage_lifetime` (non-consumable) and `ourgarage_annual`
      (auto-renewing subscription) exist in App Store Connect, matching the
      identifiers in `lib/core/constants.dart` exactly (case-sensitive).
- [ ] Both have pricing set for every storefront/region the app will be
      available in.
- [ ] Both are attached to a RevenueCat offering, and that offering is the
      one `currentOfferingProvider` fetches — confirm the RevenueCat
      dashboard's "current" offering isn't accidentally pointed at a test
      offering.
- [ ] **Both products are submitted for review together with this app build**
      — a first-time IAP submission requires the products to be in "Waiting
      for Review" or attached to the app version being submitted, or the
      binary gets rejected for referencing IAP that isn't there yet.
- [ ] Subscription group, localized display names, and localized descriptions
      are filled in for the annual product — an incomplete subscription
      listing blocks submission separately from the app binary.
- [ ] Screenshot/review-note context makes clear which product is "Best
      value" (lifetime) matches what's actually configured — a mismatch
      between the marketed badge and the real pricing is a review flag.

## Privacy nutrition labels

- [x] **Fully rewritten this session** as a literal, ordered ASC answer key
      (`store/privacy_nutrition_label.md`), backed by an audit of the entire
      dependency tree — ~140 resolved packages, direct and transitive
      (`flutter pub deps`) — not just `pubspec.yaml`'s direct list.
      **Confirmed zero crash reporters or analytics SDKs** anywhere in the
      tree (grepped for Firebase, Crashlytics, Sentry, Amplitude, Mixpanel,
      Segment, AppsFlyer, Adjust, Facebook SDK, AdMob, Braze, OneSignal,
      Bugsnag, Datadog, Instabug — zero matches; also checked for stray
      `GoogleService-Info.plist`/Firebase config files — none exist).
      RevenueCat's and Supabase's own published data-collection disclosures
      were pulled directly and cited, not assumed.
- [x] **RevenueCat `appUserID` bug (noted under "Restore Purchases" above) is
      now fixed** — the Supabase user ID is passed to RevenueCat via
      `Purchases.logIn()` on sign-in. Purchase History → "linked to identity"
      is now correctly **Yes** in `store/privacy_nutrition_label.md`, updated
      from the earlier "No" this audit had flagged. A live-project manual
      verification of the webhook payload itself is still outstanding — see
      the note above.
- [ ] App Store Connect's privacy questionnaire answers match
      `store/privacy_nutrition_label.md` **exactly**, entry by entry, not
      just in spirit.
- [x] Confirmed the free/local-only tier collecting nothing does **not**
      change the "Yes" answer to the top-level collection question — verified
      again this session, unchanged from before.
- [x] `NSUserTrackingUsageDescription` is **absent** from `Info.plist` —
      re-confirmed directly this session (`grep` on the actual file, not
      inferred), and no code path calls the ATT prompt.
- [ ] Data-type answers (email, name, user content, user ID, purchase history)
      are each marked per the corrected table in
      `store/privacy_nutrition_label.md` — spot-check these individually in
      the ASC UI, paying particular attention to the Purchase History row
      above, which is the one that changed.
- [ ] If any new third-party SDK was added since `privacy_nutrition_label.md`
      was written, its own data collection has been folded into the
      questionnaire — a webhook or SDK addition after this doc was drafted is
      the most likely way the label goes stale.

## Demo account / App Review notes

- [x] **Previously flagged gap, now closed**: `JoinHouseholdService` had no UI
      entry point when this checklist was first drafted. A "Join a household"
      screen now exists (`lib/features/household/widgets/join_household_screen.dart`),
      reachable from Settings, and is covered by widget tests including a
      dedicated end-to-end test that generates a real invite code via
      `HouseholdService.createInvite` and consumes it through the actual
      screen (`test/features/household/join_household_end_to_end_test.dart`).
      **That test runs against fakes, not live Supabase** — there is no
      `supabase` CLI, Docker, or local Postgres in the dev environment this
      was built in, so `accept_household_invite` itself was never called for
      real. Treat the item below as still open regardless of this checkbox.
- [x] **Re-verified this session, before writing the review notes**: grepped
      the router and Settings screen directly (not trusted from memory or the
      earlier draft) to confirm `JoinHouseholdScreen` is actually wired —
      routed at `/settings/join-household`, reachable via a "Join a
      household" row in `settings_screen.dart`. Also re-confirmed "Share with
      household" lives in vehicle settings (`vehicle_detail_screen.dart`, not
      a global menu) and that no auth call exists anywhere in `main.dart` /
      `app.dart`, so there is genuinely no sign-in prompt at launch.
- [x] **`store/app_review_notes.md` written this session** — the actual text
      to paste into ASC's Notes field, under 300 words, covering local-only
      usage, when auth triggers, how to test sharing, and both IAP product
      IDs with a note that pricing is live from RevenueCat (for reviewers
      testing from non-US storefronts).
- [ ] **Not yet done — this is the item that actually needs a live project**:
      create a real test household via a sandbox/demo Apple ID against a real
      Supabase project, generate an invite code through the real app, and
      confirm a second real account can redeem it end-to-end (Sign in with
      Apple → RPC → membership row visible). Only then replace the
      `TODO-INVITE-CODE` placeholder in `store/app_review_notes.md` with that
      **actual working code** — generated shortly before submission so its
      7-day expiry doesn't lapse first. The placeholder was left in
      deliberately rather than a fabricated code; do not submit with it still
      in place.
- [x] Review notes state plainly that the app is fully usable with **no
      account** — browsing, adding a vehicle, logging service, setting
      reminders — so a reviewer isn't confused about why no sign-in prompt
      appears on first launch. (Done in `store/app_review_notes.md`.)
- [x] Review notes explain *when* an account becomes necessary (tapping
      "Share with household" or "Join a household") so the reviewer doesn't
      mark the absence of auth as broken functionality. (Done.)
- [ ] If household data collection needs a demo account for the privacy
      questionnaire's account-deletion requirement, confirm there's an
      in-app or documented path to delete the demo account's data, since
      Apple checks for this separately from the privacy label itself.
      **Still open, and the honest answer right now is "no in-app path" —**
      `store/legal/terms.md` and `store/legal/privacy.md` now say so
      explicitly (email-only deletion) rather than implying an in-app flow
      that doesn't exist. Decide whether that's acceptable for submission or
      whether an in-app deletion flow needs to ship first.

## Crash-free launch, verified on-device

- [ ] **Deployment target is actually 15.0, not 13.0.** Re-scope this item:
      "crash-free on the deployment target" now means iOS 15.0, and there is
      no device in this project currently on exactly 15.0 to test against —
      confirm what device/simulator combination will stand in for the
      floor OS version before checking this box.
- [ ] TestFlight build installs and launches cleanly on the physical iPad
      (iOS 15.8.8) referenced in the Codemagic debug workflow — this is the
      one real device available and should be the actual floor-OS check,
      deployment-target number notwithstanding.
- [ ] Cold launch (app not in memory, device just rebooted or app
      force-quit) does not crash — this is the specific case App Review's
      automated + manual checks hit first and most often.
- [ ] Launch with **no network connection** does not crash or hang — the
      local-first design should guarantee this, but verify it hasn't
      regressed now that sync/household code paths exist and might block on
      a network call during startup.
- [ ] Launch with an **expired or invalid Supabase session** (e.g. token
      revoked server-side while the app was closed) does not crash — this is
      a state the local session cache can be in that's easy to not exercise
      in normal dev testing.
- [ ] No unhandled exception in the TestFlight crash log after a full manual
      pass through: onboarding → add vehicle → log service → set reminder →
      hit paywall → dismiss paywall → (once the join screen exists) attempt
      household join with a bad code → attempt with a good code.
