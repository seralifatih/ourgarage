# App Store Connect — US storefront (1.0.9)

Updated for 1.0.9, the first version in which household sharing works end to
end: owners invite from Settings → Household, members join with a code, and
one purchase unlocks Premium for every member. Every claim below was checked
against the 1.0.9 code; don't reuse this copy for a build without invites.

Every field below is length-checked. Paste verbatim; the keyword field in
particular breaks if a space sneaks in after a comma.

---

## App name — 26/30

```
OurGarage: Car Maintenance
```

Brand plus the category's highest-volume head term. "Car maintenance" is what
someone types when they don't yet know which app they want.

## Subtitle — 28/30

```
Oil Change Reminder, Service
```

Carries what the name doesn't. All four target terms don't fit in 30 characters
alongside the name — 3/4 is the ceiling — so **"log" moves to the keyword
field**. "Oil change reminder" is kept as an exact adjacent phrase because it is
the highest-intent search in the category: someone typing it has the problem
this app solves, today.

Coverage across name + subtitle: `oil change` ✓ `reminder` ✓ `service` ✓
`car` ✓ `maintenance` ✓ `garage` ✓ (via the brand token).

## Keywords — 100/100

```
vehicle,mileage,repair,tire,history,tracker,auto,odometer,fuel,family,shared,log,mechanic,truck,care
```

No spaces after commas — a space costs a character and buys nothing.

Nothing here repeats a word already in the name or subtitle. Apple indexes those
automatically, so `car`, `maintenance`, `oil`, `change`, `reminder`, `service`
and `garage` are all deliberately absent — including **`garage`, which is in the
brand name** and would otherwise have been a wasted slot from the priority list.

All 11 remaining priority terms are in, plus `log` recovered from the subtitle
tradeoff, plus `mechanic`, `truck` and `care` filling the last characters.

## Promotional text — 151/170

```
New: invite your household. Everyone sees the same cars, service history and reminders on their own iPhone, and one Premium purchase covers all of you.
```

Editable without a review cycle, so this is where the sharing angle goes. It
leads with a concrete two-person moment rather than a feature name.

---

## Description

> **Positioning note (guideline 4.3).** The paragraph order is deliberate.
> Reminders and history establish that the app works; household sharing then
> arrives as the reason to choose *this* one. A single-user maintenance log is
> indistinguishable from dozens of incumbents, and "track your car maintenance"
> as a lead is precisely the generic framing that draws a spam rejection.
> Sharing is named in the first screen of text, not buried under a fold.

```
Never miss an oil change again.

OurGarage tells you what your car needs before it becomes a problem. Set a
reminder once — every 6 months, every 5,000 miles, or both — and get a
notification the morning it falls due. No spreadsheet, no glovebox receipts,
no trying to remember whether that was last spring or the one before.

Log a service in seconds: what you had done, when, the mileage, and what it
cost. Your full history stays on your phone and works with no signal at all,
which matters, because you usually log a service standing in a garage.


SHARE ONE GARAGE WITH YOUR HOUSEHOLD

Most cars are not driven by one person. OurGarage is built for that.

Invite your partner, your family, or whoever else drives the car: send them a
one-time code from Settings → Household, and they join from their own iPhone.
Everyone sees the same vehicles, the same service history, and the same
reminders. When one of you logs an oil change, everyone else's phone picks it
up when they open the app — so nobody buys a second air filter or books a
service that was done last month.

One person pays. The whole household gets Premium. Charging everyone
separately would defeat the point.

Everyone can see who's in the household and leave at any time; the owner
can also remove someone.


WHAT YOU GET FREE

• One vehicle
• Unlimited service records
• Unlimited reminders, by date, mileage, or both
• Notifications before anything falls due
• Full offline use — everything works with no connection

FREE MEANS FREE

The free tier has no ads, no trial timer, and no feature that stops working
after a fortnight. If one car is all you need, you never have to pay us
anything, and we will not nag you about it.


OURGARAGE PREMIUM

• Unlimited vehicles
• Household sharing — one garage, everyone's phone
• Service costs
• Export your records

Lifetime — pay once, keep forever.
Annual — a yearly subscription.

Both unlock everything. Buy whichever suits you; the lifetime option is not a
worse deal that exists to make the subscription look good.


ABOUT YOUR DATA

Use OurGarage without an account and it collects nothing at all. Your garage
lives on your phone and never touches a server.

An account is only needed for household sharing, and you are only ever asked
for one at the moment you tap Share or Join. Sign in with Apple — no password,
no email list, no third-party sign-ins. You can delete your account from
Settings at any time.

Terms: https://ourgarage.app/terms/
Privacy: https://ourgarage.app/privacy/
```

---

## What's New in 1.0.9 — for the version's release notes

```
Household sharing is here.

• Invite people from Settings → Household: send a one-time code, and they join from their own iPhone.
• Everyone in the household sees the same cars, service history and reminders, synced when you open the app.
• One Premium purchase now unlocks Premium for every member.
• See who's in your household and leave at any time; owners can remove someone.
• Clearer messages if something goes wrong while setting up a household.
```

---

## Screenshots — order matters for 4.3

The description can be read carefully; the screenshots are what an App Review
screener actually looks at.

What is generated today (`test/screenshots/app_store_screenshots_test.dart`
and `ipad_app_store_screenshots_test.dart`) — all four captions are accurate
for 1.0.9:

| # | Shows | Caption (title / subtitle) |
|---|-------|----------------------------|
| 1 | Garage with a due reminder | **Never miss an oil change** / Reminders before maintenance is due |
| 2 | Reminders for a vehicle | **Know what's due next** / By mileage or by date |
| 3 | Service history | **Every service, logged** / Costs, mileage and notes in one place |
| 4 | Paywall | **Premium for the whole household** / One member unlocks it, everyone gets it |

Caption 4 was not true in 1.0.8 (household premium never reached other
members); it is in 1.0.9.

**Recommended addition for 1.0.9** — the one image that shows sharing rather
than describing it, placed second so it is seen without scrolling:

| # | Shows | Caption (title / subtitle) |
|---|-------|----------------------------|
| 2 (new) | Settings → Household: two named members, one pending invite, "Invite someone" | **Share one garage** / Invite your household with a one-time code |

Not added to the screenshot tests yet: the iPhone screenshot test has
uncommitted edits in the working tree, and those are left alone.

## Review notes

See `store/app_review_notes.md` — that file is the one to paste.
