// Combat au tactile, émulation iPhone paysage 844×390.
// 1) Chromium mobile + CDP : vrai multitouch, identifiants ALÉATOIRES
//    (joystick tenu + boutons en même temps, glissé d'un bouton à l'autre).
// 2) WebKit : taps simples (la synthèse multitouch n'y est pas possible).
import { chromium, webkit } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { serve } from './serve.mjs';

const root = path.resolve(import.meta.dirname, '../../web/build');
const out = path.resolve(import.meta.dirname, '../out/touch');
fs.mkdirSync(out, { recursive: true });
const server = await serve(root, 8768);
const URL = 'http://localhost:8768/index.html?touch=1#scene=fight';
const errors = [];
const rid = () => Math.floor(Math.random() * 1e6) + 10;

// ---- Chromium : multitouch
{
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error' || /SCRIPT ERROR/.test(m.text())) errors.push(m.text()); });
  await page.goto(URL);
  await page.waitForSelector('canvas');
  await page.waitForTimeout(9000);
  const cdp = await ctx.newCDPSession(page);
  const active = new Map();
  const send = (type) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: [...active.values()] });
  async function down(id, x, y) { active.set(id, { x, y, id }); await send('touchStart'); }
  async function move(id, x, y) { active.set(id, { x, y, id }); await send('touchMove'); }
  async function up(id) {
    const p = active.get(id); active.delete(id);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [...active.values()] });
  }
  const stick = rid();
  await down(stick, 120, 300);
  for (let i = 1; i <= 6; i++) { await move(stick, 120 + i * 8, 300); await page.waitForTimeout(30); }
  await page.waitForTimeout(900);
  await page.screenshot({ path: `${out}/01_walk.png` });
  for (let k = 0; k < 3; k++) { const b = rid(); await down(b, 640, 290); await page.waitForTimeout(60); await up(b); await page.waitForTimeout(90); }
  await page.screenshot({ path: `${out}/02_punch_while_walking.png` });
  // Glissé POING → SPÉCIAL sans lever le doigt.
  const roll = rid();
  await down(roll, 640, 290); await page.waitForTimeout(50);
  for (let i = 1; i <= 5; i++) { await move(roll, 640 + i * 26, 290); await page.waitForTimeout(16); }
  await page.waitForTimeout(200);
  await page.screenshot({ path: `${out}/03_roll_special.png` });
  await up(roll); await up(stick);
  await browser.close();
}
// ---- WebKit : taps simples
{
  const browser = await webkit.launch();
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 3, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(URL);
  await page.waitForSelector('canvas');
  await page.waitForTimeout(9000);
  for (let k = 0; k < 3; k++) { await page.touchscreen.tap(640, 290); await page.waitForTimeout(120); }
  await page.screenshot({ path: `${out}/04_webkit_tap.png` });
  await browser.close();
}
server.close();
console.log(JSON.stringify({ errors: errors.slice(0, 8) }, null, 1));
