# ourgarage.app

Static Astro site: home page + SEO guides. Deployed to Cloudflare Pages by
`.github/workflows/website.yml` on every push to `website/` and daily at 06:05 UTC.

## Daily publishing

A guide is built only when its `publish_date` (UTC) has arrived. The daily
workflow run is what makes a scheduled guide go live; nothing else is needed.
Links from a live guide to a not-yet-published one render as plain text until
that guide's day.

## Commands

```sh
npm install
npm run dev                      # local preview; shows scheduled guides too (marked noindex)
npm run build                    # production build, only guides due today or earlier
BUILD_DATE=2026-12-01 npm run build   # build as it will look on that day
npm run schedule -- 2026-11-20   # re-date unpublished guides one per day from that date
npm run og                       # regenerate icons, OG image and screenshots in public/
```

## Writing a guide

Add `content/guides/<slug>.md`. The slug is the URL; never change it once live.

```yaml
---
title: "How Often Should You …?"        # ≤70 chars, " | OurGarage" is appended
description: "…"                         # 70–160 chars, used for meta + OG
publish_date: 2026-11-24
updated_date: 2026-12-10                 # optional; sets dateModified + sitemap lastmod
keywords: ["…", "…"]
related: ["other-slug", "other-slug"]    # "Related guides" box
cta_topic: "oil changes"                 # "Get reminders for oil changes in OurGarage"
faq:                                     # optional; rendered on page + FAQPage JSON-LD
  - q: "…"
    a: "…"
---
```

Body rules (see `content/keywords.md`): answer first in a `<p class="answer">`,
then a line containing only `[[cta]]` (the build fails without it), 2–3 inline
links to `/guides/<slug>/`, general ranges only, and "check your owner's manual".

## Config

- `PUBLIC_APPSTORE_PT` (GitHub repo variable `APPSTORE_PT`): App Store Connect
  provider token, so `ct=seo-<slug>` campaigns show up in App Analytics.
- Secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` for deploys.
