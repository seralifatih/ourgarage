# OurGarage keyword plan

44 long-tail topics, each with a clear "track it / remind me" intent: the
searcher has a recurring task and a reason to want it remembered. One guide per
day. The slug is final once a guide is published; never change it afterwards.

**Ground rules for every guide**

- Answer in the first two sentences, then explain.
- General ranges only. Always say "check your owner's manual for your exact
  interval". No per-make or per-model numbers until we can verify them.
- Name sources in plain language (owner's manual, the tire placard, NHTSA, the
  FTC). Never invent a statistic. If we can't support a number, leave it out.
- 2–3 inline links to related guides, a `[[cta]]` marker right after the key
  answer, and the end CTA (added automatically).

Intent: **R** = wants a reminder/interval, **T** = wants to track/log,
**C** = checklist, **S** = sharing/household.

Status: `scheduled YYYY-MM-DD` is set by `npm run schedule`, `draft` is
written but unscheduled, `—` is not written yet.

## Priority queue: next 14 guides

Low-competition, app-intent long tail first. These are searches where the
person is already looking for a tool, a template or a system, so the CTA is
the natural next step. Head terms ("car maintenance", "oil change") stay in
the backlog; we can't outrank manufacturers and big publishers on them yet.

| Order | Target query | Slug | Hook | Status |
|---|---|---|---|---|
| 8 | car maintenance log template (printable) | car-maintenance-log-template | Free PDF: `/downloads/car-maintenance-log.pdf` | scheduled 2026-11-24 |
| 9 | printable car maintenance checklist | printable-car-maintenance-checklist | Free PDF: `/downloads/car-maintenance-checklist.pdf` | scheduled 2026-11-25 |
| 10 | best app to track car maintenance | best-app-to-track-car-maintenance | Honest comparison incl. OurGarage | scheduled 2026-11-26 |
| 11 | oil change reminder app | oil-change-reminder-app | Date + mileage setup walkthrough | scheduled 2026-11-27 |
| 12 | how to track maintenance for multiple cars | track-maintenance-multiple-cars | One system for 2+ cars | scheduled 2026-11-28 |
| 13 | sharing car maintenance with a teen driver / spouse | teen-driver-car-maintenance | Who does what; teaching the checks | scheduled 2026-11-29 |
| 14 | maintenance for a low-mileage / rarely driven car | low-mileage-car-maintenance | Time limits matter more than miles | scheduled 2026-11-30 |
| 15 | what to do if a car sat for months | car-sat-for-months | Restart checklist | next to draft |
| 16 | when was my last oil change (how to find out) | when-was-my-last-oil-change | Rebuild the date from receipts/sticker/shop | — |
| 17 | car maintenance spreadsheet vs app | car-maintenance-spreadsheet-vs-app | Honest trade-offs, template link | — |
| 18 | car registration renewal reminder | registration-inspection-reminders | Date-only reminders | — |
| 19 | car maintenance cost tracker | track-car-maintenance-costs | What to log, yearly totals | — |
| 20 | managing an elderly parent's car maintenance | manage-parents-car-maintenance | Remote oversight via shared record | — |
| 21 | lost service records: rebuild a car's maintenance history | rebuild-car-service-history | Shops, dealers, history reports | — |

Spouse queries ("share car maintenance with spouse/partner") are served by
the existing family guide (#7) plus a section in #13, so they don't get a
separate page that would compete with #7.

Comparison guides (#10, #17) must be dated, describe competitors only by what
their current App Store listing says, leave out prices (they vary by region and
change), and state OurGarage's limits as plainly as its strengths.

## Guides 15–30: maintenance-item intervals (scheduled Dec 1–16, 2026)

One query per guide; variants are H2s or FAQs, never a second page.

| # | Main keyword | Slug | publish_date |
|---|---|---|---|
| 15 | how long do car batteries last | how-long-do-car-batteries-last | 2026-12-01 |
| 16 | how long do brake pads last | how-long-do-brake-pads-last | 2026-12-02 |
| 17 | how long do tires last | how-long-do-tires-last | 2026-12-03 |
| 18 | cabin air filter | how-often-to-change-cabin-air-filter | 2026-12-04 |
| 19 | change spark plugs | how-often-to-change-spark-plugs | 2026-12-05 |
| 20 | transmission fluid | how-often-to-change-transmission-fluid | 2026-12-06 |
| 21 | brake fluid | how-often-to-change-brake-fluid | 2026-12-07 |
| 22 | engine air filter | how-often-to-change-engine-air-filter | 2026-12-08 |
| 23 | how long do brakes last (rotors) | how-long-do-brakes-last | 2026-12-09 |
| 24 | windshield wipers | how-often-to-replace-wiper-blades | 2026-12-10 |
| 25 | coolant / antifreeze | how-often-to-change-coolant | 2026-12-11 |
| 26 | how long do alternators last | how-long-do-alternators-last | 2026-12-12 |
| 27 | differential fluid | how-often-to-change-differential-fluid | 2026-12-13 |
| 28 | serpentine belt / timing belt | serpentine-and-timing-belt-replacement | 2026-12-14 |
| 29 | fuel filter | how-often-to-change-fuel-filter | 2026-12-15 |
| 30 | power steering fluid | how-often-to-change-power-steering-fluid | 2026-12-16 |

Synthetic oil intervals and the oil filter are covered inside how-often-to-change-oil (no separate page).

# Backlog by cluster

### Cluster 1: Oil and fluids

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 1 | how often to change oil | how-often-to-change-oil | R | scheduled (guide 1) |
| 2 | oil change every 6 months or by mileage (whichever comes first) | oil-change-time-vs-mileage | R | — |
| 3 | how long can you go past an oil change | overdue-oil-change | R | — |
| 4 | severe vs normal maintenance schedule: which one applies to me | severe-vs-normal-maintenance-schedule | R | — |
| 5 | how often to check engine oil level | how-often-to-check-oil-level | R | — |
| 6 | how often to change brake fluid | how-often-to-change-brake-fluid | R | scheduled 2026-12-07 |
| 7 | how often to change coolant | how-often-to-change-coolant | R | scheduled 2026-12-11 |
| 8 | how often to change transmission fluid | how-often-to-change-transmission-fluid | R | scheduled 2026-12-06 |
| 9 | oil life monitor vs fixed interval | oil-life-monitor-explained | R | — |

### Cluster 2: Tires

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 10 | how often to rotate tires (tire rotation interval) | how-often-to-rotate-tires | R | scheduled (guide 2) |
| 11 | how often to check tire pressure | how-often-to-check-tire-pressure | R | scheduled (guide 4) |
| 12 | how to check tire tread depth (penny test) | how-to-check-tire-tread-depth | C | — |
| 13 | when to replace tires by age and tread | when-to-replace-tires | R | covered by how-long-do-tires-last (2026-12-03) |
| 14 | how often to get a wheel alignment | how-often-wheel-alignment | R | — |
| 15 | seasonal tire changeover: when to switch to winter tires | when-to-switch-winter-tires | R | — |

### Cluster 3: Schedules and planning

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 16 | car maintenance schedule by mileage | car-maintenance-schedule-by-mileage | R | scheduled (guide 3) |
| 17 | what is a 30k / 60k / 90k mile service | 30-60-90-mile-service | R | — |
| 18 | 100,000 mile maintenance checklist | 100000-mile-maintenance | C | — |
| 19 | monthly car maintenance checklist | monthly-car-maintenance-checklist | C | — |
| 20 | car maintenance for low-mileage drivers | low-mileage-car-maintenance | R | queue #14 |
| 21 | how often to replace engine and cabin air filters | how-often-to-replace-air-filters | R | covered by cabin (2026-12-04) + engine (2026-12-08) air filter guides |
| 22 | how often to replace wiper blades | how-often-to-replace-wiper-blades | R | scheduled 2026-12-10 |
| 23 | how long does a car battery last and when to test it | car-battery-life-and-testing | R | covered by how-long-do-car-batteries-last (2026-12-01) |
| 24 | how often to replace brake pads (and the signs) | when-to-replace-brake-pads | R | covered by how-long-do-brake-pads-last (2026-12-02) |
| 25 | timing belt replacement interval (and how to tell if you have a chain) | timing-belt-replacement-interval | R | covered by serpentine-and-timing-belt-replacement (2026-12-14) |
| 26 | annual car maintenance budget: how to plan for it | car-maintenance-budget | T | — |

### Cluster 4: Seasons and trips

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 27 | what to check before a road trip | road-trip-car-checklist | C | scheduled (guide 5) |
| 28 | winter car maintenance checklist | winter-car-maintenance-checklist | C | — |
| 29 | summer car maintenance checklist | summer-car-maintenance-checklist | C | — |
| 30 | car maintenance before storing a car | car-storage-checklist | C | — |

### Cluster 5: Records and paperwork

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 31 | how to keep a car service record for resale | car-service-records-for-resale | T | scheduled (guide 6) |
| 32 | does doing your own oil change void the warranty | diy-maintenance-warranty | T | — |
| 33 | how to track car maintenance costs | track-car-maintenance-costs | T | queue #19 |
| 34 | how to check for open recalls by VIN | check-car-recalls-by-vin | R | — |
| 35 | car registration and inspection renewal reminders | registration-inspection-reminders | R | queue #18 |
| 36 | lost service records: how to rebuild a car's maintenance history | rebuild-car-service-history | T | queue #21 |

### Cluster 6: Household and sharing

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 37 | sharing car maintenance with family | share-car-maintenance-with-family | S | scheduled (guide 7) |
| 38 | keeping track of maintenance for multiple cars | track-maintenance-multiple-cars | T/S | queue #12 |
| 39 | maintaining a teen driver's car: what they should know | teen-driver-car-maintenance | S | queue #13 |
| 40 | managing an elderly parent's car maintenance remotely | manage-parents-car-maintenance | S | queue #20 |

## Internal-link map

| Guide | Links to |
|---|---|
| how-often-to-change-oil | car-maintenance-schedule-by-mileage, how-often-to-rotate-tires, car-service-records-for-resale |
| how-often-to-rotate-tires | how-often-to-check-tire-pressure, how-often-to-change-oil, car-maintenance-schedule-by-mileage |
| car-maintenance-schedule-by-mileage | how-often-to-change-oil, how-often-to-rotate-tires, car-service-records-for-resale |
| how-often-to-check-tire-pressure | how-often-to-rotate-tires, road-trip-car-checklist |
| road-trip-car-checklist | how-often-to-check-tire-pressure, how-often-to-change-oil, share-car-maintenance-with-family |
| car-service-records-for-resale | car-maintenance-schedule-by-mileage, share-car-maintenance-with-family, how-often-to-change-oil |
| share-car-maintenance-with-family | car-service-records-for-resale, car-maintenance-schedule-by-mileage, road-trip-car-checklist |

Links to a guide that isn't published yet render as plain text and turn into
links automatically on the day that guide goes live.

### Guides 8–14

| Guide | Links to |
|---|---|
| car-maintenance-log-template | car-service-records-for-resale, car-maintenance-schedule-by-mileage, printable-car-maintenance-checklist |
| printable-car-maintenance-checklist | how-often-to-check-tire-pressure, car-maintenance-log-template, road-trip-car-checklist |
| best-app-to-track-car-maintenance | oil-change-reminder-app, car-maintenance-log-template, share-car-maintenance-with-family |
| oil-change-reminder-app | how-often-to-change-oil, best-app-to-track-car-maintenance, low-mileage-car-maintenance |
| track-maintenance-multiple-cars | car-maintenance-log-template, share-car-maintenance-with-family, car-maintenance-schedule-by-mileage |
| teen-driver-car-maintenance | how-often-to-check-tire-pressure, share-car-maintenance-with-family, printable-car-maintenance-checklist |
| low-mileage-car-maintenance | how-often-to-change-oil, oil-change-reminder-app, car-maintenance-schedule-by-mileage |
