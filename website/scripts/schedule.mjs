// Reschedules unpublished guides one per day, keeping their current order.
//
//   npm run schedule -- 2026-11-20          first unpublished guide goes live on that date
//   npm run schedule -- 2026-11-20 --dry    show the plan without writing
//
// Guides already live (publish_date <= today, UTC) are never touched.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';

const [start, ...flags] = process.argv.slice(2);
const dry = flags.includes('--dry');
if (!/^\d{4}-\d{2}-\d{2}$/.test(start ?? '')) {
  console.error('Usage: npm run schedule -- YYYY-MM-DD [--dry]');
  process.exit(1);
}
const today = new Date().toISOString().slice(0, 10);
if (start <= today) {
  console.error(`Start date ${start} must be after today (${today}) so nothing goes live by accident.`);
  process.exit(1);
}

const dir = new URL('../content/guides/', import.meta.url);
const re = /^publish_date:\s*['"]?(\d{4}-\d{2}-\d{2})['"]?\s*$/m;

const pending = readdirSync(dir)
  .filter((f) => f.endsWith('.md'))
  .map((file) => {
    const text = readFileSync(new URL(file, dir), 'utf8');
    const date = text.match(re)?.[1];
    if (!date) throw new Error(`${file}: no publish_date`);
    return { file, text, date };
  })
  .filter((g) => g.date > today)
  .sort((a, b) => a.date.localeCompare(b.date) || a.file.localeCompare(b.file));

const day = new Date(`${start}T00:00:00Z`);
for (const g of pending) {
  const next = day.toISOString().slice(0, 10);
  console.log(`${next}  ${g.file}${g.date === next ? '' : `  (was ${g.date})`}`);
  if (!dry) writeFileSync(new URL(g.file, dir), g.text.replace(re, `publish_date: ${next}`));
  day.setUTCDate(day.getUTCDate() + 1);
}
if (!pending.length) console.log('No unpublished guides.');
