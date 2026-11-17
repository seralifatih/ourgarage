# App Review notes — 1.0.9

Checked against the 1.0.9 code on `feature/household-invites-1.0.9`. The demo
household and its invite codes were created in production on 2026-11-17 with
`tool/create_review_household.py` and verified: joining with a code shows one
car, four services, two reminders and two members.

**Before submitting — all required:**
- [ ] Run `python -I tool/create_review_household.py --live --codes 0` once
      **with `REVENUECAT_SECRET_KEY` set**. It grants the demo owner a lifetime
      promotional entitlement, checks RevenueCat reports it as lifetime, and
      marks the demo household premium. Until this is done, a reviewer who
      joins does *not* get Premium, and step 3 of the join test is false.
      (Not done yet as of 2026-11-17.)
- [ ] Join the demo household once on a sandbox device with one of the codes
      and confirm the Family Civic appears and Premium is unlocked; then leave.
      Re-run the script to replace the code you used.
- [ ] Replace `<CODES IN ASC>` with the codes from `store/review_codes.local.txt`
      (gitignored — the codes let anyone join the demo household, so they live
      only there and in App Store Connect). Check they are unused and unexpired;
      if not, run `python -I tool/create_review_household.py --live --codes 5 --days 45`
      and put the new codes in that file — it reuses the same demo account and
      household.

**Paste into App Store Connect's "Notes" field for this version:**

---

OurGarage is fully usable with no account. Adding a vehicle, logging a
service and setting maintenance reminders all work offline, with no sign-in
prompt anywhere in that flow.

An account (Sign in with Apple, the only sign-in method) is requested only
when the user taps "Share with household" (in a vehicle's menu) or "Join a
household" (in Settings). Nothing else in the app triggers it. Because Sign in
with Apple uses your own Apple ID, we can't provide a login; instead we have
set up a demo household for you to join.

WHAT'S NEW IN 1.0.9: household sharing works end to end — inviting, joining,
the member list, removing and leaving — and one Premium purchase unlocks
Premium for every member of the household. Shared data syncs when the app is
opened.

Please do the join test first: once you are in a household, Settings shows
"Household" instead of "Join a household".

1) JOINING A HOUSEHOLD (one device, no purchase needed)
   a. Open Settings → "Join a household".
   b. Enter one of these invite codes. Each works once; please use the next
      one if you test more than once: <CODES IN ASC>
   c. Sign in with Apple when asked. If the device already has vehicles in
      the app, you'll be asked whether to share them with the household or
      keep them on this device.
   d. You've joined "Demo household": its car ("Family Civic"), service
      history and reminders appear in your garage, and Premium features are
      unlocked because the household's owner holds Premium.
   e. Settings → Household lists the members: "OurGarage Demo" (the owner)
      and you — shown as "Household member (you)" if you chose not to share
      your name with Apple. As a member you can leave; inviting and removing
      people are the owner's.

2) INVITING (as a household owner)
   a. Settings → Household → "Leave household" first. Your device keeps its
      own copy of the car; the household keeps it too.
   b. Open any vehicle → menu → "Share with household". Sharing is a Premium
      feature, so the paywall appears; a sandbox purchase unlocks it.
   c. Sign in with Apple if asked. Your garage is uploaded to your new
      household and the Household screen opens.
   d. Tap "Invite someone": a one-time code is created and the share sheet
      opens with the code and instructions. The code is listed under "Pending
      invites", where it can be shared again or revoked.

3) ACCOUNT DELETION
   Settings → "Delete account" (shown once signed in), then confirm with Sign
   in with Apple. Your account is deleted from our servers. If you were the
   only member of your household, the household and its shared data are
   deleted too; otherwise the household carries on for its other members.
   Data on the device stays.

IN-APP PURCHASES:
Two products are offered from the paywall: "OurGarage Lifetime"
(ourgarage_lifetime, non-consumable) and "OurGarage Annual"
(ourgarage_annual, auto-renewing subscription). Prices come from StoreKit via
RevenueCat at display time, so a non-US storefront shows local pricing. Either
purchase unlocks Premium for the buyer and, once they are in a household, for
every member of it.

---
