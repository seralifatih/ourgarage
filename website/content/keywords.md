# OurGarage keyword plan

40 long-tail topics, each with a clear "track it / remind me" intent: the
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

## Cluster 1: Oil and fluids

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 1 | how often to change oil | how-often-to-change-oil | R | scheduled (guide 1) |
| 2 | oil change every 6 months or by mileage (whichever comes first) | oil-change-time-vs-mileage | R | — |
| 3 | how long can you go past an oil change | overdue-oil-change | R | — |
| 4 | severe vs normal maintenance schedule: which one applies to me | severe-vs-normal-maintenance-schedule | R | — |
| 5 | how often to check engine oil level | how-often-to-check-oil-level | R | — |
| 6 | how often to change brake fluid | how-often-to-change-brake-fluid | R | — |
| 7 | how often to change coolant | how-often-to-change-coolant | R | — |
| 8 | how often to change transmission fluid | how-often-to-change-transmission-fluid | R | — |
| 9 | oil life monitor vs fixed interval | oil-life-monitor-explained | R | — |

## Cluster 2: Tires

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 10 | how often to rotate tires (tire rotation interval) | how-often-to-rotate-tires | R | scheduled (guide 2) |
| 11 | how often to check tire pressure | how-often-to-check-tire-pressure | R | scheduled (guide 4) |
| 12 | how to check tire tread depth (penny test) | how-to-check-tire-tread-depth | C | — |
| 13 | when to replace tires by age and tread | when-to-replace-tires | R | — |
| 14 | how often to get a wheel alignment | how-often-wheel-alignment | R | — |
| 15 | seasonal tire changeover: when to switch to winter tires | when-to-switch-winter-tires | R | — |

## Cluster 3: Schedules and planning

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 16 | car maintenance schedule by mileage | car-maintenance-schedule-by-mileage | R | scheduled (guide 3) |
| 17 | what is a 30k / 60k / 90k mile service | 30-60-90-mile-service | R | — |
| 18 | 100,000 mile maintenance checklist | 100000-mile-maintenance | C | — |
| 19 | monthly car maintenance checklist | monthly-car-maintenance-checklist | C | — |
| 20 | car maintenance for low-mileage drivers | low-mileage-car-maintenance | R | — |
| 21 | how often to replace engine and cabin air filters | how-often-to-replace-air-filters | R | — |
| 22 | how often to replace wiper blades | how-often-to-replace-wiper-blades | R | — |
| 23 | how long does a car battery last and when to test it | car-battery-life-and-testing | R | — |
| 24 | how often to replace brake pads (and the signs) | when-to-replace-brake-pads | R | — |
| 25 | timing belt replacement interval (and how to tell if you have a chain) | timing-belt-replacement-interval | R | — |
| 26 | annual car maintenance budget: how to plan for it | car-maintenance-budget | T | — |

## Cluster 4: Seasons and trips

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 27 | what to check before a road trip | road-trip-car-checklist | C | scheduled (guide 5) |
| 28 | winter car maintenance checklist | winter-car-maintenance-checklist | C | — |
| 29 | summer car maintenance checklist | summer-car-maintenance-checklist | C | — |
| 30 | car maintenance before storing a car | car-storage-checklist | C | — |

## Cluster 5: Records and paperwork

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 31 | how to keep a car service record for resale | car-service-records-for-resale | T | scheduled (guide 6) |
| 32 | does doing your own oil change void the warranty | diy-maintenance-warranty | T | — |
| 33 | how to track car maintenance costs | track-car-maintenance-costs | T | — |
| 34 | how to check for open recalls by VIN | check-car-recalls-by-vin | R | — |
| 35 | car registration and inspection renewal reminders | registration-inspection-reminders | R | — |
| 36 | lost service records: how to rebuild a car's maintenance history | rebuild-car-service-history | T | — |

## Cluster 6: Household and sharing

| # | Topic / target query | Slug | Intent | Status |
|---|---|---|---|---|
| 37 | sharing car maintenance with family | share-car-maintenance-with-family | S | scheduled (guide 7) |
| 38 | keeping track of maintenance for multiple cars | track-maintenance-multiple-cars | T/S | — |
| 39 | maintaining a teen driver's car: what they should know | teen-driver-car-maintenance | S | — |
| 40 | managing an elderly parent's car maintenance remotely | manage-parents-car-maintenance | S | — |

## Internal-link map for the first 7

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
