// Generates the free printable PDFs into public/downloads/. Run locally
// (`npm run pdfs`) when their content changes; outputs are committed.
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const outDir = fileURLToPath(new URL('../public/downloads/', import.meta.url));
mkdirSync(outDir, { recursive: true });

const TEAL = rgb(0.059, 0.612, 0.557);
const INK = rgb(0.09, 0.13, 0.12);
const MUTED = rgb(0.38, 0.43, 0.42);
const LINE = rgb(0.75, 0.8, 0.79);
const FILL = rgb(0.93, 0.97, 0.96);

const LETTER = [612, 792];
const LANDSCAPE = [792, 612];
const M = 36; // margin

async function newDoc(title) {
  const doc = await PDFDocument.create();
  doc.setTitle(title);
  doc.setAuthor('OurGarage');
  doc.setCreator('ourgarage.app');
  // Fixed dates so regenerating unchanged content gives identical bytes.
  doc.setCreationDate(new Date('2026-11-15T00:00:00Z'));
  doc.setModificationDate(new Date('2026-11-15T00:00:00Z'));
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  return { doc, font, bold };
}

function footer(page, font) {
  const { width } = page.getSize();
  page.drawText('Free from ourgarage.app  ·  Intervals vary by vehicle: use the numbers in your owner\'s manual.', {
    x: M, y: 20, size: 8, font, color: MUTED,
  });
  const right = 'Get reminders on your phone: OurGarage on the App Store';
  const narrow = width < 700; // portrait: put it on its own line
  page.drawText(right, { x: narrow ? M : width - M - font.widthOfTextAtSize(right, 8), y: narrow ? 32 : 20, size: 8, font, color: TEAL });
}

function header(page, bold, font, title, subtitle) {
  const { width, height } = page.getSize();
  page.drawRectangle({ x: 0, y: height - 6, width, height: 6, color: TEAL });
  page.drawText(title, { x: M, y: height - 44, size: 20, font: bold, color: INK });
  if (subtitle) page.drawText(subtitle, { x: M, y: height - 62, size: 10, font, color: MUTED });
}

/** Draws a ruled table with a shaded header row. Returns the y below it. */
function table(page, { x, y, cols, rows, rowH = 20, font, bold, size = 9 }) {
  const width = cols.reduce((s, c) => s + c.w, 0);
  page.drawRectangle({ x, y: y - rowH, width, height: rowH, color: FILL });
  let cx = x;
  for (const c of cols) {
    page.drawText(c.label, { x: cx + 4, y: y - rowH + 6, size, font: bold, color: INK });
    cx += c.w;
  }
  const total = rows + 1;
  for (let r = 0; r <= total; r++) {
    page.drawLine({ start: { x, y: y - r * rowH }, end: { x: x + width, y: y - r * rowH }, thickness: 0.6, color: LINE });
  }
  cx = x;
  for (let i = 0; i <= cols.length; i++) {
    page.drawLine({ start: { x: cx, y }, end: { x: cx, y: y - total * rowH }, thickness: 0.6, color: LINE });
    if (i < cols.length) cx += cols[i].w;
  }
  return y - total * rowH;
}

/** Label followed by a fill-in line that ends at absolute x `endX`. */
function field(page, font, label, x, y, endX) {
  page.drawText(label, { x, y, size: 9, font, color: MUTED });
  const lw = font.widthOfTextAtSize(label, 9) + 6;
  page.drawLine({ start: { x: x + lw, y: y - 2 }, end: { x: endX, y: y - 2 }, thickness: 0.6, color: LINE });
}

// ---------- 1. Maintenance log ----------
async function maintenanceLog() {
  const { doc, font, bold } = await newDoc('Car Maintenance Log');
  const cols = [
    { label: 'Date', w: 70 }, { label: 'Odometer', w: 70 }, { label: 'Service performed', w: 260 },
    { label: 'Parts / fluids', w: 150 }, { label: 'Shop or DIY', w: 110 }, { label: 'Cost', w: 60 },
  ];

  // Page 1: vehicle details + log
  let p = doc.addPage(LANDSCAPE);
  header(p, bold, font, 'Car Maintenance Log', 'Write down every service the day it happens. The odometer reading matters as much as the date.');
  const fy = 612 - 92;
  field(p, font, 'Vehicle', M, fy, M + 250);
  field(p, font, 'Year / make / model', M + 270, fy, M + 540);
  field(p, font, 'Plate', M + 560, fy, 792 - M);
  field(p, font, 'VIN', M, fy - 22, M + 360);
  field(p, font, 'Oil type (from manual)', M + 380, fy - 22, 792 - M);
  table(p, { x: M, y: fy - 40, cols, rows: 18, font, bold });
  footer(p, font);

  // Page 2: more log rows
  p = doc.addPage(LANDSCAPE);
  header(p, bold, font, 'Car Maintenance Log (continued)', null);
  table(p, { x: M, y: 612 - 64, cols, rows: 23, font, bold });
  footer(p, font);

  // Page 3: what's due next
  p = doc.addPage(LANDSCAPE);
  header(p, bold, font, 'What\'s Due Next', 'Copy each interval from your owner\'s manual. When you do a service, update "Last done" and work out "Next due".');
  const due = [
    { label: 'Item', w: 170 }, { label: 'Interval (miles)', w: 95 }, { label: 'Interval (months)', w: 95 },
    { label: 'Last done: date', w: 95 }, { label: 'Last done: miles', w: 95 }, { label: 'Next due: date / miles', w: 170 },
  ];
  const yEnd = table(p, { x: M, y: 612 - 84, cols: due, rows: 16, rowH: 22, font, bold });
  const items = ['Oil and filter', 'Tire rotation', 'Engine air filter', 'Cabin air filter', 'Brake fluid', 'Coolant',
    'Spark plugs', 'Transmission fluid', 'Wiper blades', 'Battery check', 'Registration renewal', 'Inspection'];
  items.forEach((t, i) => p.drawText(t, { x: M + 4, y: 612 - 84 - 22 * (i + 2) + 7, size: 9, font, color: INK }));
  p.drawText('Whichever comes first: if the mileage or the date arrives first, it\'s due.', { x: M, y: yEnd - 18, size: 9, font: bold, color: INK });
  footer(p, font);

  writeFileSync(outDir + 'car-maintenance-log.pdf', await doc.save());
}

// ---------- 2. Checklist ----------
async function checklist() {
  const { doc, font, bold } = await newDoc('Car Maintenance Checklist');
  const p = doc.addPage(LETTER);
  header(p, bold, font, 'Car Maintenance Checklist', 'Tick each box when it\'s done. Vehicle: ____________________   Year: ________');

  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const labelW = 216;
  const cellW = (612 - 2 * M - labelW) / 12;
  const rowH = 19;

  function grid(title, rows, top) {
    p.drawText(title, { x: M, y: top, size: 12, font: bold, color: TEAL });
    let y = top - 10;
    p.drawRectangle({ x: M, y: y - rowH, width: 612 - 2 * M, height: rowH, color: FILL });
    months.forEach((m, i) => p.drawText(m, { x: M + labelW + i * cellW + 5, y: y - rowH + 6, size: 8, font: bold, color: INK }));
    y -= rowH;
    for (const r of rows) {
      p.drawText(r, { x: M + 4, y: y - rowH + 6, size: 9, font, color: INK });
      months.forEach((_, i) => p.drawRectangle({
        x: M + labelW + i * cellW + (cellW - 10) / 2, y: y - rowH + 5, width: 10, height: 10, borderColor: LINE, borderWidth: 0.8,
      }));
      p.drawLine({ start: { x: M, y: y - rowH }, end: { x: 612 - M, y: y - rowH }, thickness: 0.5, color: LINE });
      y -= rowH;
    }
    return y;
  }

  let y = grid('Every month', [
    'Tire pressure, all four + spare (cold)',
    'Tire tread and sidewalls',
    'Engine oil level',
    'Coolant level (engine cold)',
    'Washer fluid',
    'All lights and turn signals',
    'Wiper blades: streaks or chatter?',
    'Dashboard warning lights',
    'Update odometer reading',
  ], 792 - 100);

  y = grid('When due (check your manual\'s interval)', [
    'Oil and filter change',
    'Tire rotation',
    'Engine air filter',
    'Cabin air filter',
    'Brake inspection',
    'Battery test (if 3+ years old)',
    'Registration / inspection',
  ], y - 26);

  p.drawText('Before a long trip', { x: M, y: y - 26, size: 12, font: bold, color: TEAL });
  const trip = ['Tire pressure for full load', 'Spare, jack and wrench', 'Oil due during the trip?', 'Brake fluid level',
    'Battery age and terminals', 'A/C and heat', 'Emergency kit', 'Registration and insurance in car'];
  trip.forEach((t, i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = M + col * 270, ty = y - 48 - row * 18;
    p.drawRectangle({ x, y: ty - 1, width: 10, height: 10, borderColor: LINE, borderWidth: 0.8 });
    p.drawText(t, { x: x + 16, y: ty, size: 9, font, color: INK });
  });
  footer(p, font);

  writeFileSync(outDir + 'car-maintenance-checklist.pdf', await doc.save());
}

await maintenanceLog();
await checklist();
console.log('PDFs written to public/downloads/');
