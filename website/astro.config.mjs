import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import { readdirSync, readFileSync } from 'node:fs';

const SITE = 'https://ourgarage.app';

/** slug -> last modified date, read from guide frontmatter for sitemap <lastmod>. */
function guideLastmod() {
  const dir = new URL('./content/guides/', import.meta.url);
  const map = new Map();
  for (const file of readdirSync(dir)) {
    if (!file.endsWith('.md')) continue;
    const fm = readFileSync(new URL(file, dir), 'utf8').split('---')[1] ?? '';
    const pick = (key) => fm.match(new RegExp(`^${key}:\\s*['"]?(\\d{4}-\\d{2}-\\d{2})`, 'm'))?.[1];
    const date = pick('updated_date') ?? pick('publish_date');
    if (date) map.set(file.replace(/\.md$/, ''), date);
  }
  return map;
}

const lastmod = guideLastmod();

export default defineConfig({
  site: SITE,
  trailingSlash: 'always',
  build: { format: 'directory', inlineStylesheets: 'always' },
  integrations: [
    sitemap({
      filter: (page) => !page.includes('/404'),
      serialize(item) {
        const slug = item.url.match(/\/guides\/([^/]+)\/$/)?.[1];
        if (slug && lastmod.has(slug)) item.lastmod = new Date(lastmod.get(slug)).toISOString();
        return item;
      },
    }),
  ],
});
