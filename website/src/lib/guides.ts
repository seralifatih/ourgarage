import { getCollection, type CollectionEntry } from 'astro:content';
import { SHOW_SCHEDULED, appStoreUrl, isoDate, today } from '../site';

export type Guide = CollectionEntry<'guides'>;

export function isPublished(g: Guide): boolean {
  return isoDate(g.data.publish_date) <= today();
}

/** Guides that go into this build, newest first. Future-dated ones are left out entirely. */
export async function getGuides(): Promise<Guide[]> {
  const all = await getCollection('guides');
  return all
    .filter((g) => SHOW_SCHEDULED || isPublished(g))
    .sort((a, b) => b.data.publish_date.valueOf() - a.data.publish_date.valueOf());
}

export function guideUrl(slug: string): string {
  return `/guides/${slug}/`;
}

export function ctaHtml(slug: string, topic: string, position: 'mid' | 'end'): string {
  const href = appStoreUrl(`seo-${slug}`);
  return `<aside class="cta cta-${position}" aria-label="Get the app">
  <img src="/icon-96.png" width="48" height="48" alt="" loading="lazy">
  <div>
    <p class="cta-title">Get reminders for ${escapeHtml(topic)} in OurGarage</p>
    <p class="cta-body">Set it once by date, mileage, or both, and keep the full service history on your phone. Free for one car.</p>
    <a class="cta-btn" href="${escapeHtml(href)}" rel="noopener">Download on the App Store</a>
  </div>
</aside>`;
}

/**
 * Finishes a guide's rendered HTML:
 * - `[[cta]]` on its own line becomes the mid-article CTA box.
 * - Links to guides not in this build are unwrapped to plain text, so a guide
 *   can link ahead to one scheduled for later; the link appears once that
 *   guide is published and the daily rebuild runs.
 */
export function finishGuideHtml(html: string, slug: string, topic: string, liveSlugs: Set<string>): string {
  let out = html.replace(/<p>\s*\[\[cta\]\]\s*<\/p>/g, () => ctaHtml(slug, topic, 'mid'));
  out = out.replace(
    /<a href="\/guides\/([a-z0-9-]+)\/?(#[^"]*)?"[^>]*>([\s\S]*?)<\/a>/g,
    (match, target: string, _hash, text: string) => (liveSlugs.has(target) ? match : text),
  );
  return out;
}

/**
 * A FAQ answer from frontmatter as HTML: escaped, with `[text](https://…)`
 * turned into a link. Used both on the page and in the FAQPage JSON-LD, so
 * the visible answer and the structured one stay identical. Only https URLs
 * are linked; anything else stays as literal text.
 */
export function faqAnswerHtml(answer: string): string {
  return escapeHtml(answer).replace(
    /\[([^\]]+)\]\((https:\/\/[^\s)]+)\)/g,
    (_m, text: string, href: string) => `<a href="${href}" rel="noopener">${text}</a>`,
  );
}

export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

/** Rough reading time at ~230 wpm, from the rendered HTML. */
export function readingMinutes(html: string): number {
  const words = html.replace(/<[^>]+>/g, ' ').split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / 230));
}
