# App Store Connect — US storefront

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
One person logs the oil change, everyone in the house sees it. Share one garage across your family's phones — no more asking who last serviced the car.
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

Invite your partner, your family, or whoever else drives the car. Everyone
sees the same vehicles, the same service history, and the same reminders on
their own phone. When one of you logs an oil change, it appears for everyone —
so nobody buys a second air filter or books a service that was done last month.

One person pays. The whole household gets Premium. Charging everyone
separately would defeat the point.


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
• Service costs and spending totals
• Export your records

Lifetime — pay once, keep forever.
Annual — a yearly subscription.

Both unlock everything. Buy whichever suits you; the lifetime option is not a
worse deal that exists to make the subscription look good.


ABOUT YOUR DATA

Use OurGarage without an account and it collects nothing at all. Your garage
lives on your phone and never touches a server.

An account is only needed for household sharing, and you are only ever asked
for one at the moment you tap Share. Sign in with Apple — no password, no
email list, no third-party sign-ins.

Terms: https://noktastudio.dev/ourgarage/terms
Privacy: https://noktastudio.dev/ourgarage/privacy
```

---

## Screenshots — order matters for 4.3

The description can be read carefully; the screenshots are what an App Review
screener actually looks at. Sharing must be visible without scrolling.

| # | Shows | Caption |
|---|-------|---------|
| 1 | Two phones, same garage, one service just logged | **One garage. Everyone's phone.** |
| 2 | Household members list + invite code sheet | **Invite your partner in seconds** |
| 3 | Reminder due notification on the lock screen | **Told before it's due** |
| 4 | Vehicle detail: reminders + service history | **Every service, every car** |
| 5 | Service record form with cost | **What was done, when, what it cost** |
| 6 | Garage list with several vehicles | **The whole fleet, one place** |

Screenshot 1 carries the differentiation claim. If only one image is ever
looked at, it must be the one that is not a single-user maintenance log.

**Review notes field** — say this explicitly, because a screener will not
create two accounts to discover it:

```
OurGarage is a car maintenance tracker whose primary differentiator is
household sharing: multiple people share one garage, with service history and
reminders synced between them, and a single purchase covering every member.

To test sharing you need two accounts:
1. Sign in with Apple (Settings → OurGarage Premium, or tap Share with
   household on any vehicle).
2. Household settings → Invite someone. A 6-character code is generated.
3. On a second device or account: Settings → Join a household → enter the code.
4. Both accounts now see the same vehicles and service history.

The app is fully usable with no account and no network. An account is requested
only when the user taps Share with household, never at launch.
```
