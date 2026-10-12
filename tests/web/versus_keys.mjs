// Versus local au clavier dans le build web (Chromium) : titre → combat,
// J1 avance (D) puis uppercut (S+A+J), J2 frappe (flèches + virgule).
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { serve } from './serve.mjs';

const root = path.resolve(import.meta.dirname, '../../web/build');
const out = path.resolve(import.meta.dirname, '../out/p1web');
fs.mkdirSync(out, { recursive: true });
const server = await serve(root, 8766);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1152, height: 648 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.goto('http://localhost:8766/index.html');
await page.waitForSelector('canvas');
await page.waitForTimeout(4000);
await page.click('canvas');
await page.keyboard.press('Enter');
await page.waitForTimeout(4200);          // iris + intro « ROUND 1 / BORROKA ! »
await page.keyboard.down('d');
await page.keyboard.down('ArrowLeft');
await page.waitForTimeout(1100);
await page.keyboard.up('d');
await page.keyboard.up('ArrowLeft');
await page.screenshot({ path: `${out}/01_contact.png` });
for (let i = 0; i < 3; i++) { await page.keyboard.press('j'); await page.waitForTimeout(90); }
await page.screenshot({ path: `${out}/02_combo.png` });
await page.waitForTimeout(400);
await page.keyboard.down('s'); await page.keyboard.down('a');
await page.keyboard.press('j');
await page.waitForTimeout(160);
await page.screenshot({ path: `${out}/03_uppercut.png` });
await page.waitForTimeout(220);
await page.screenshot({ path: `${out}/04_uppercut.png` });
await page.keyboard.up('s'); await page.keyboard.up('a');
await page.waitForTimeout(900);
await page.keyboard.press(','); await page.waitForTimeout(60);
await page.keyboard.press('.');
await page.waitForTimeout(150);
await page.screenshot({ path: `${out}/05_j2.png` });
await browser.close();
server.close();
console.log(JSON.stringify({ errors }, null, 1));
process.exit(errors.length ? 1 : 0);
