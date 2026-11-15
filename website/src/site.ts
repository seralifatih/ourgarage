/** Site-wide constants. Everything URL-shaped lives here so it changes in one place. */

export const SITE_URL = 'https://ourgarage.app';
export const SITE_NAME = 'OurGarage';
export const APP_STORE_ID = '6801807059';

/**
 * App Store Connect provider token (App Analytics → Campaigns → "Generate a
 * campaign link" shows it as `pt=`). Without it Apple does not attribute the
 * `ct` campaign, so set PUBLIC_APPSTORE_PT in the build environment.
 */
const PROVIDER_TOKEN = import.meta.env.PUBLIC_APPSTORE_PT ?? '';

/** App Store link tagged with an App Analytics campaign token. */
export function appStoreUrl(campaign: string): string {
  const params = new URLSearchParams();
  if (PROVIDER_TOKEN) params.set('pt', PROVIDER_TOKEN);
  params.set('ct', campaign);
  params.set('mt', '8');
  return `https://apps.apple.com/us/app/apple-store/id${APP_STORE_ID}?${params}`;
}

export const SUPPORT_URL = '/support/';
export const PRIVACY_URL = '/privacy/';
export const TERMS_URL = '/terms/';

/** YYYY-MM-DD in UTC. BUILD_DATE overrides it to preview a future day's build. */
export function today(): string {
  return process.env.BUILD_DATE || new Date().toISOString().slice(0, 10);
}

/** Show scheduled guides (marked noindex): always in `astro dev`, or with SHOW_SCHEDULED=1. Never set in CI. */
export const SHOW_SCHEDULED = process.env.SHOW_SCHEDULED === '1' || import.meta.env.DEV;

export function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function displayDate(d: Date): string {
  return d.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' });
}
