// Critère Phase 4 en émulation (Chromium mobile + CDP multitouch, index aléatoires) :
// 1) tutoriel complet au doigt, super déclenché par le bouton MARÉE ;
// 2) combat entier au tactile contre l'IA Facile, jusqu'à l'écran de fin.
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { serve } from './serve.mjs';

const root = path.resolve(import.meta.dirname, '../../web/build');
const out = path.resolve(import.meta.dirname, '../out/phase4');
fs.mkdirSync(out, { recursive: true });
const server = await serve(root, 8769);
const errors = [];
const rid = () => Math.floor(Math.random() * 1e6) + 10;
// Boutons du losange (px CSS, iPhone 844×390 → vue logique 468×216, ×1,805).
const B = { punch: [652, 282], special: [783, 282], guard: [717, 217], kick: [717, 348], maree: [717, 145] };

async function session(url) {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (/SCRIPT ERROR/.test(m.text())) errors.push(m.text()); });
  await page.goto(url);
  await page.waitForSelector('canvas');
  await page.waitForTimeout(6500);
  const cdp = await ctx.newCDPSession(page);
  const active = new Map();
  const send = (type) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: [...active.values()] });
  const T = {
    async down(id, x, y) { active.set(id, { x, y, id }); await send('touchStart'); },
    async move(id, x, y) { active.set(id, { x, y, id }); await send('touchMove'); },
    async up(id) { active.delete(id); await send('touchEnd'); },
    async tap(name, hold = 70) { const id = rid(); await T.down(id, ...B[name]); await page.waitForTimeout(hold); await T.up(id); },
    async stick(dx, dy, ms) {
      const id = rid(); await T.down(id, 140, 300);
      for (let i = 1; i <= 5; i++) { await T.move(id, 140 + dx * i / 5, 300 + dy * i / 5); await page.waitForTimeout(16); }
      return id;
    },
  };
  return { browser, page, T };
}

// ---- 1) Tutoriel
{
  const { browser, page, T } = await session('http://localhost:8769/index.html?touch=1#scene=tutorial');
  await page.waitForTimeout(1500);
  let s = await T.stick(50, 0); await page.waitForTimeout(900); await T.up(s);           // bouger
  await page.waitForTimeout(1200);
  for (let i = 0; i < 3; i++) { await T.tap('punch'); await page.waitForTimeout(80); }  // frapper
  await page.waitForTimeout(1600);
  const g = rid(); await T.down(g, ...B.guard); await page.waitForTimeout(3500); await T.up(g); // garder
  await page.screenshot({ path: `${out}/t1_guard.png` });
  await page.waitForTimeout(1200);
  s = await T.stick(-40, 40); await page.waitForTimeout(80); await T.tap('punch'); await page.waitForTimeout(100); await T.up(s); // uppercut
  await page.waitForTimeout(1600);
  await T.tap('special');                                                                  // spécial
  await page.waitForTimeout(1800);
  await page.screenshot({ path: `${out}/t2_before_super.png` });
  await T.tap('maree');                                                                    // super au pad
  await page.waitForTimeout(250);
  await page.screenshot({ path: `${out}/t3_super.png` });
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${out}/t4_end.png` });
  await browser.close();
}
// ---- 2) Combat entier au tactile contre l'IA Facile
{
  const { browser, page, T } = await session('http://localhost:8769/index.html?touch=1#scene=touchfight');
  const t0 = Date.now();
  let shots = 0;
  while (Date.now() - t0 < 240000) {
    const s = await T.stick(40, 0); await page.waitForTimeout(250); await T.up(s);
    for (let i = 0; i < 3; i++) { await T.tap('punch', 50); await page.waitForTimeout(60); }
    if (Math.random() < 0.3) await T.tap('kick');
    if (Math.random() < 0.15) await T.tap('special');
    if (Math.random() < 0.1) await T.tap('maree');
    if ((Date.now() - t0) > shots * 40000) { await page.screenshot({ path: `${out}/f_${shots}.png` }); shots++; }
    const over = await page.evaluate(() => document.title);
    if (Date.now() - t0 > 200000) break;
  }
  await page.screenshot({ path: `${out}/f_end.png` });
  await browser.close();
}
server.close();
console.log(JSON.stringify({ errors: errors.slice(0, 8) }, null, 1));
