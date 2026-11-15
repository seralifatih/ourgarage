// Generates static images into public/. Run locally (`npm run og`) when the
// icon, screenshots or OG copy change; outputs are committed, CI never runs this.
import sharp from 'sharp';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = new URL('../../', import.meta.url);
const pub = new URL('../public/', import.meta.url);
const icon = fileURLToPath(new URL('assets/icon/icon.png', root));
const out = (p) => fileURLToPath(new URL(p, pub));

mkdirSync(out('shots/'), { recursive: true });

await sharp(icon).resize(32, 32).png().toFile(out('favicon-32.png'));
await sharp(icon).resize(96, 96).png().toFile(out('icon-96.png'));
await sharp(icon).resize(180, 180).png().toFile(out('apple-touch-icon.png'));

for (const name of ['01_garage', '02_reminders', '03_history']) {
  const src = fileURLToPath(new URL(`screenshots/1206x2622/${name}.png`, root));
  await sharp(src).resize(440).webp({ quality: 78 }).toFile(out(`shots/${name}.webp`));
}

// OG image: 1200x630, brand teal, icon + headline.
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#0c6f61"/><stop offset="1" stop-color="#139c8e"/></linearGradient></defs>
  <rect width="1200" height="630" fill="url(#g)"/>
  <text x="80" y="300" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-size="72" font-weight="700" fill="#fff">Car maintenance,</text>
  <text x="80" y="385" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-size="72" font-weight="700" fill="#fff">shared with your household</text>
  <text x="80" y="470" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-size="34" fill="#d6f3ee">Guides and reminders · ourgarage.app</text>
</svg>`;
const iconTile = await sharp(icon).resize(120, 120).png().toBuffer();
const roundMask = Buffer.from('<svg width="120" height="120"><rect width="120" height="120" rx="26" fill="#fff"/></svg>');
const roundedIcon = await sharp(iconTile).composite([{ input: roundMask, blend: 'dest-in' }]).png().toBuffer();
await sharp(Buffer.from(svg))
  .composite([{ input: roundedIcon, left: 80, top: 110 }])
  .png()
  .toFile(out('og.png'));

console.log('images written to public/');
