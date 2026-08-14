# App Review notes

Verified against the current codebase (not the earlier draft in
`app_store_listing_us.md`) before writing this — the household join screen
now exists at `lib/features/household/widgets/join_household_screen.dart`,
is routed at `/settings/join-household`, and is reachable from a "Join a
household" row in Settings.

**Paste into App Store Connect's "Notes" field for this version:**

---

OurGarage is fully usable with no account. Adding a vehicle, logging a
service, and setting maintenance reminders all work offline, with no sign-in
prompt anywhere in that flow.

An account (Sign in with Apple) is only requested when the user explicitly
taps "Share with household" (in a vehicle's settings menu) or "Join a
household" (in the app's Settings tab). Nothing else in the app triggers it.

**To test household sharing:**
Use this invite code: TODO-INVITE-CODE
1. Sign in with Apple via either entry point above.
2. Enter the code under Settings → Join a household.
3. The joining account will see the same vehicles and service history as the
   household that generated the code.

**To test in-app purchases:**
Two products are offered from the paywall: "OurGarage Lifetime"
(`ourgarage_lifetime`, non-consumable) and "OurGarage Annual"
(`ourgarage_annual`, auto-renewing subscription). Both prices are pulled live
from RevenueCat via StoreKit at display time — nothing is hardcoded — so a
reviewer testing from a non-US storefront will correctly see local pricing
rather than a fixed USD amount. Either purchase unlocks Premium for the
signed-in account and its household.

---

**Before submitting:** replace `TODO-INVITE-CODE` with a real code generated
from a test household — do not leave the placeholder in, and don't submit a
code close to its 7-day expiry.
